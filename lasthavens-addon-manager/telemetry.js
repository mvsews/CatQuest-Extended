// Anonymous usage statistics for the voice server (POST /api/v1/telemetry).
// Sent: a random install ID made here, extension and addon versions, voice
// language, browser language and counters of what the game did with voice
// files. The server stores nothing derived from the IP. The player can turn
// it off in the manager. With it on, the character playing and the quests
// ordered are sent too (below), unless the player turns that part off.
import { UPDATE_ORIGIN } from "./updates.js";
import { readLibrary } from "./repository.js";

const SEND_EVERY_MS = 55 * 60 * 1000;
const CLIENT_VERSION = "3.3.5a";
let chain = Promise.resolve();
const serial = (fn) => (chain = chain.then(fn).catch(() => {}));

// A game read can happen every few hundred milliseconds. Writing one
// chrome.storage.local record for every read creates an unbounded promise
// queue and makes the game tab stutter even when the addon itself is disabled.
// Accumulate counters in memory and flush them as one small write instead.
let pendingCounters = Object.create(null);
let pendingLocale = "";
let counterTimer = null;
function flushCounters() {
  const counters = pendingCounters;
  const locale = pendingLocale;
  pendingCounters = Object.create(null);
  pendingLocale = "";
  if (!Object.keys(counters).length && !locale) return;
  serial(async () => {
    const { telemetry = {}, telemetryOff = false } = await chrome.storage.local.get(["telemetry", "telemetryOff"]);
    if (telemetryOff) return;
    const merged = { ...(telemetry.counters || {}) };
    for (const [key, value] of Object.entries(counters))
      merged[key] = Math.min((merged[key] || 0) + value, 100000);
    await chrome.storage.local.set({
      telemetry: { ...telemetry, counters: merged, locale: locale || telemetry.locale || "" },
    });
  });
}
function scheduleCounterFlush() {
  if (counterTimer) return;
  counterTimer = setTimeout(() => {
    counterTimer = null;
    flushCounters();
  }, 2000);
}

async function load() {
  const { telemetry = {}, telemetryOff = false } = await chrome.storage.local.get(["telemetry", "telemetryOff"]);
  return { telemetry, off: telemetryOff };
}

// Probe events from the game page (background.js appendProbe).
function counterFor(event) {
  switch (event?.type) {
    case "install": return "sessions"; // the game page loaded the addons
    case "read": return "reads"; // the game read a voice file
    case "demand": return "demand"; // a track was ordered from the server
    case "size-mismatch":
    case "read-unmatched":
    case "lua-error":
    case "runtime-error":
    case "bridge-error": return "errors";
    case "fetch-done": return event.ok ? "fetch_ok" : "fetch_fail";
    case "direct":
      if (event.status === 200) return "fetch_ok";
      return event.status === 0 || event.status >= 500 ? "fetch_fail" : null;
    default: return null;
  }
}

export function countProbe(event) {
  const field = counterFor(event);
  const locale = (event?.type === "install" || event?.type === "voice-locale") && event.locale;
  if (!field && !locale) return;
  if (field) pendingCounters[field] = (pendingCounters[field] || 0) + 1;
  if (locale) pendingLocale = locale;
  scheduleCounterFlush();
}

export function sendTelemetry({ force = false } = {}) {
  // Commit any counters collected since the last timer tick before taking a
  // telemetry snapshot. This is one batched write, never one write per read.
  flushCounters();
  return serial(async () => {
    const { telemetry, off } = await load();
    if (off) return;
    if (!force && Date.now() - (telemetry.sentAt || 0) < SEND_EVERY_MS) return;
    const id = telemetry.id || crypto.randomUUID();
    const library = await readLibrary();
    const addon = library.addons.find((a) => a.folder === "CatQuest");
    const { voiceLocale, voiceLocaleAuto } = await chrome.storage.local.get(["voiceLocale", "voiceLocaleAuto"]);
    const counters = telemetry.counters || {};
    const body = {
      id,
      ext: chrome.runtime.getManifest().version,
      addon: addon?.version || "",
      addonEnabled: Boolean(addon?.enabled),
      locale: (voiceLocale !== "auto" && voiceLocale) || telemetry.locale || voiceLocaleAuto || "",
      ui: chrome.i18n.getUILanguage().slice(0, 8),
      counters,
    };
    let ok = false;
    try {
      const response = await fetch(`${UPDATE_ORIGIN}/api/v1/telemetry`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      ok = response.ok;
    } catch {
      // Offline: the counters wait for the next report.
    }
    await chrome.storage.local.set({
      telemetry: {
        ...telemetry,
        id,
        sentAt: ok ? Date.now() : telemetry.sentAt || 0,
        counters: ok ? {} : counters,
      },
    });
  });
}

export async function setTelemetryOff(off) {
  await serial(async () => {
    const { telemetry } = await load();
    // Turning it off also drops what was counted and not sent, the token
    // and the errors waiting for a report.
    await chrome.storage.local.set({
      telemetryOff: off,
      telemetry: off ? { id: telemetry.id } : telemetry,
      ...(off ? { errorLog: [] } : {}),
    });
  });
}

// Players (backend/accounts.py): this install's token, the character playing
// and the quests it ordered, for the server's list of who uses the voice-over.
// Only while statistics are on (one switch in the manager; identityOff is
// left from 0.6.13). The token is made by the server on registration; only
// this copy of the extension knows it.
const ORDER_REPEAT_MS = 30 * 60 * 1000;

async function resolveIdentity() {
  const { telemetry = {}, telemetryOff = false, identityOff = false } =
    await chrome.storage.local.get(["telemetry", "telemetryOff", "identityOff"]);
  if (telemetryOff || identityOff) return null;
  if (telemetry.id && telemetry.token) {
    const who = { id: telemetry.id, token: telemetry.token };
    if (!telemetry.accountId) {
      try {
        const response = await fetch(`${UPDATE_ORIGIN}/api/v1/account`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ ...who, mode: "status" }),
        });
        const answer = response.ok ? await response.json().catch(() => null) : null;
        if (answer?.account_id) {
          await chrome.storage.local.set({ telemetry: { ...telemetry, accountId: answer.account_id } });
          return { ...who, accountId: answer.account_id };
        }
      } catch {
        // The normal signed request will retry when the server is available.
      }
    }
    return { ...who, accountId: telemetry.accountId || "" };
  }
  // An ID registers once: if this one is taken (its token was lost), start a new one.
  for (const id of [telemetry.id || crypto.randomUUID(), crypto.randomUUID()]) {
    let response;
    try {
      response = await fetch(`${UPDATE_ORIGIN}/api/v1/register`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id }),
      });
    } catch {
      return null; // offline: next time
    }
    if (response.status === 409) continue;
    const answer = response.ok ? await response.json().catch(() => null) : null;
    if (!answer?.token) return null;
    await chrome.storage.local.set({ telemetry: {
      ...telemetry, id, token: answer.token,
      accountId: String(answer.account_id || ""),
      recoveryCode: String(answer.recovery_code || ""),
    } });
    return {
      id, token: answer.token, accountId: String(answer.account_id || ""),
      recoveryCode: String(answer.recovery_code || ""),
    };
  }
  return null;
}

// Settings and heard-place restoration can start together when the game page
// opens. Share one registration promise so one extension install cannot create
// two server identities during that first load.
let identityInFlight = null;
async function identity() {
  if (!identityInFlight) identityInFlight = resolveIdentity();
  const current = identityInFlight;
  try {
    return await current;
  } finally {
    if (identityInFlight === current) identityInFlight = null;
  }
}

async function postSigned(path, body) {
  const who = await identity();
  if (!who) return false;
  try {
    const response = await fetch(`${UPDATE_ORIGIN}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...body, id: who.id, token: who.token }),
    });
    if (response.status === 403) {
      // The server does not know this token any more: register again next time.
      const { telemetry = {} } = await chrome.storage.local.get("telemetry");
      await chrome.storage.local.set({ telemetry: { ...telemetry, token: "" } });
    }
    return response.ok;
  } catch {
    return false;
  }
}

const SETTING_BOOLS = new Set([
  "enabled", "auto", "showSubtitle", "books", "turnin", "queue", "readAfterAccept",
  "stopOnClose", "readButton", "bookPages", "head", "headLocked", "keepInBackground",
  "compact", "minimap", "minimapLocked", "storyQuestTitles", "places", "remoteEnabled", "requestPanel", "questRatings",
]);
const SETTING_NUMBERS = {
  trackGap: [0, 10], duck: [0, 100], scale: [0.5, 2], minimapAngle: [0, 360],
  remoteDuration: [3, 600], pendingTimeout: [10, 1800],
};
const SETTING_TEXT = {
  volumeChannel: new Set(["Master", "SFX", "Music", "Ambience", "Dialog"]),
  language: new Set(["auto", "ruRU", "enUS", "zhCN", "zhTW", "deDE", "frFR", "esES", "esMX", "ptBR", "koKR", "itIT"]),
  uiLanguage: new Set(["auto", "ruRU", "enUS"]),
  pack: new Set(["auto", "original"]),
};

export function cleanAddonSettings(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const out = {};
  for (const key of SETTING_BOOLS)
    if (typeof value[key] === "boolean") out[key] = value[key];
  for (const [key, [min, max]] of Object.entries(SETTING_NUMBERS)) {
    const number = Number(value[key]);
    if (Number.isFinite(number) && number >= min && number <= max) out[key] = Math.round(number * 1000) / 1000;
  }
  for (const [key, allowed] of Object.entries(SETTING_TEXT))
    if (allowed.has(value[key])) out[key] = value[key];
  const position = value.headPosition;
  if (position && typeof position === "object" && !Array.isArray(position)) {
    const x = Number(position.x), y = Number(position.y);
    if (typeof position.point === "string" && position.point.length <= 32 &&
        typeof position.relativePoint === "string" && position.relativePoint.length <= 32 &&
        Number.isFinite(x) && Number.isFinite(y) && Math.abs(x) <= 10000 && Math.abs(y) <= 10000) {
      out.headPosition = {
        point: position.point, relativePoint: position.relativePoint,
        x: Math.round(x * 100) / 100, y: Math.round(y * 100) / 100,
      };
    }
  }
  return out;
}

async function postSignedJson(path, body) {
  const who = await identity();
  if (!who) return null;
  try {
    const response = await fetch(`${UPDATE_ORIGIN}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...body, id: who.id, token: who.token }),
    });
    if (response.status === 403) {
      const { telemetry = {} } = await chrome.storage.local.get("telemetry");
      await chrome.storage.local.set({ telemetry: { ...telemetry, token: "" } });
      return null;
    }
    return response.ok ? await response.json().catch(() => null) : null;
  } catch {
    return null;
  }
}

export async function getAddonSettings() {
  await addonSettingsSaveChain;
  const { addonSettings = {}, addonSettingsDirty = false } =
    await chrome.storage.local.get(["addonSettings", "addonSettingsDirty"]);
  const local = cleanAddonSettings(addonSettings);
  if (addonSettingsDirty && Object.keys(local).length) {
    const saved = await postSignedJson("/api/v1/settings", { mode: "put", scope: "account", settings: local });
    if (saved) await chrome.storage.local.set({ addonSettingsDirty: false });
    return local;
  }
  const answer = await postSignedJson("/api/v1/settings", { mode: "get", scope: "account" });
  const remote = cleanAddonSettings(answer?.settings);
  if (Object.keys(remote).length) {
    // Older servers omit Music from the account reply. Keep the local choice
    // across page reloads until the server accepts it too.
    const settings = { ...remote };
    if (!settings.volumeChannel && local.volumeChannel === "Music") settings.volumeChannel = "Music";
    await chrome.storage.local.set({ addonSettings: settings, addonSettingsDirty: false });
    return settings;
  }
  if (Object.keys(local).length && answer?.updated_at === 0)
    await postSignedJson("/api/v1/settings", { mode: "put", scope: "account", settings: local });
  return local;
}

let addonSettingsSaveChain = Promise.resolve(false);

export function saveAddonSettings(value, { fromSnapshot = false } = {}) {
  const incoming = cleanAddonSettings(value);
  if (!Object.keys(incoming).length) return Promise.resolve(false);
  addonSettingsSaveChain = addonSettingsSaveChain.then(async () => {
    const { addonSettings = {} } = await chrome.storage.local.get("addonSettings");
    // The browser can return an older SavedVariables snapshot after F5. Its
    // window fields must not replace values already received via markers.
    const current = cleanAddonSettings(addonSettings);
    if (fromSnapshot && !Object.keys(current).length) {
      // The initial settings fetch may have timed out while the game read its
      // SavedVariables. Recover the account's window values before importing.
      const answer = await postSignedJson("/api/v1/settings", { mode: "get", scope: "account" });
      const remote = cleanAddonSettings(answer?.settings);
      for (const key of ["scale", "duck", "headPosition", "volumeChannel", "questRatings"])
        if (Object.prototype.hasOwnProperty.call(remote, key)) current[key] = remote[key];
    }
    const updates = { ...incoming };
    if (fromSnapshot)
      for (const key of ["scale", "duck", "headPosition", "volumeChannel", "questRatings"])
        if (Object.prototype.hasOwnProperty.call(current, key)) delete updates[key];
    const settings = cleanAddonSettings({ ...current, ...updates });
    await chrome.storage.local.set({ addonSettings: settings, addonSettingsDirty: true });
    const saved = await postSignedJson("/api/v1/settings", { mode: "put", scope: "account", settings });
    if (saved) await chrome.storage.local.set({ addonSettingsDirty: false });
    return Boolean(saved);
  }).catch(() => false);
  return addonSettingsSaveChain;
}

export async function getAccountStatus() {
  const answer = await postSignedJson("/api/v1/account", { mode: "status" });
  if (answer?.account_id) {
    const { telemetry = {} } = await chrome.storage.local.get("telemetry");
    if (telemetry.accountId !== answer.account_id)
      await chrome.storage.local.set({ telemetry: { ...telemetry, accountId: answer.account_id } });
  }
  return answer?.ok ? answer : null;
}

export async function rotateRecoveryCode() {
  const answer = await postSignedJson("/api/v1/account", { mode: "rotate-recovery" });
  if (!answer?.recovery_code) return null;
  const { telemetry = {} } = await chrome.storage.local.get("telemetry");
  await chrome.storage.local.set({ telemetry: {
    ...telemetry, accountId: answer.account_id || telemetry.accountId,
    recoveryCode: answer.recovery_code,
  } });
  return answer;
}

export async function linkAccount(recoveryCode) {
  const code = String(recoveryCode || "").toUpperCase().replace(/-/g, "");
  if (!/^[A-Z2-9]{16}$/.test(code)) return null;
  const answer = await postSignedJson("/api/v1/account", { mode: "link", recovery_code: code });
  if (!answer?.account_id) return null;
  const { telemetry = {} } = await chrome.storage.local.get("telemetry");
  await chrome.storage.local.set({ telemetry: {
    ...telemetry, accountId: answer.account_id, recoveryCode: code,
  } });
  return answer;
}

const PLACE_HEARD_MAX = 5000;
const cleanHeard = (value) => [...new Set(
  (Array.isArray(value) ? value : []).filter((hash) => /^[0-9a-f]{8}$/.test(String(hash))).map(String),
)].slice(-PLACE_HEARD_MAX);

async function placeMemory() {
  const { placesScope = "account" } = await chrome.storage.local.get("placesScope");
  const { character = null } = await chrome.storage.session.get("character");
  if (placesScope === "character" && character?.realm && GUID_RE.test(String(character.guid || ""))) {
    return {
      scope: "character", realm: character.realm, guid: character.guid,
      key: `character:${character.realm}\u001f${character.guid}`,
    };
  }
  return { scope: "account", key: "account" };
}

export async function getHeardPlaces() {
  const memory = await placeMemory();
  const { placesHeard = [], placesHeardScopeKey = "" } = await chrome.storage.local.get([
    "placesHeard", "placesHeardScopeKey",
  ]);
  const local = placesHeardScopeKey === memory.key ? cleanHeard(placesHeard) : [];
  const answer = await postSignedJson("/api/v1/place-heard", {
    mode: "get", ...memory, client: CLIENT_VERSION,
  });
  const remote = cleanHeard(answer?.heard);
  const merged = cleanHeard([...local, ...remote]);
  if (merged.length !== local.length || merged.some((hash, index) => hash !== local[index]) || placesHeardScopeKey !== memory.key)
    await chrome.storage.local.set({ placesHeard: merged, placesHeardScopeKey: memory.key });
  return merged;
}

export async function markHeardPlace(hash, areaId = 0) {
  hash = String(hash || "").toLowerCase();
  if (!/^[0-9a-f]{8}$/.test(hash)) return false;
  const memory = await placeMemory();
  return Boolean(await postSignedJson("/api/v1/place-heard", {
    mode: "mark", ...memory, client: CLIENT_VERSION, hash,
    area_id: Number.isInteger(areaId) && areaId >= 0 && areaId <= 9999999 ? areaId : 0,
  }));
}

export async function resetHeardPlaces() {
  const memory = await placeMemory();
  await chrome.storage.local.set({ placesHeard: [] });
  return Boolean(await postSignedJson("/api/v1/place-heard", {
    mode: "reset", ...memory, client: CLIENT_VERSION,
  }));
}

const GUID_RE = /^0x[0-9A-F]{16}$/;
export function reportCharacter({ realm, name, guid } = {}) {
  realm = String(realm || "").slice(0, 48);
  name = String(name || "").slice(0, 24);
  guid = String(guid || "");
  if (!realm || !name || !GUID_RE.test(guid)) return;
  serial(async () => {
    await chrome.storage.session.set({ character: { realm, name, guid } });
    await postSigned("/api/v1/character", { realm, name, guid });
  });
}

export function reportOrder({ quest, kind, locale } = {}) {
  if (!Number.isInteger(quest) || !["DETAIL", "PROGRESS", "COMPLETE"].includes(kind) || !/^[a-z]{2}[A-Z]{2}$/.test(locale))
    return;
  serial(async () => {
    // The game asks again every few seconds while a track is voiced: one order.
    const key = `${quest}|${kind}|${locale}`;
    const { ordersSent = {}, character = null } = await chrome.storage.session.get(["ordersSent", "character"]);
    const now = Date.now();
    if (now - (ordersSent[key] || 0) < ORDER_REPEAT_MS) return;
    for (const k of Object.keys(ordersSent)) if (now - ordersSent[k] > ORDER_REPEAT_MS) delete ordersSent[k];
    await chrome.storage.session.set({ ordersSent: { ...ordersSent, [key]: now } });
    await postSigned("/api/v1/order", {
      quest, type: kind, locale, client: "3.3.5a",
      realm: character?.realm || "", guid: character?.guid || "",
    });
  });
}

// A place is reported once per install and place/hash every 30 minutes. The
// empty hash is meaningful: it says the player requested lore we do not have.
const PLACE_REPEAT_MS = 30 * 60 * 1000;
export function reportPlaceRequest({ zone, subzone, hash, areaId } = {}) {
  zone = String(zone || "").replace(/\s+/g, " ").trim().slice(0, 80);
  subzone = String(subzone || "").replace(/\s+/g, " ").trim().slice(0, 80);
  hash = String(hash || "").toLowerCase();
  areaId = Number.isInteger(areaId) && areaId >= 0 && areaId <= 9999999 ? areaId : 0;
  if (!zone || !subzone || (hash && !/^[0-9a-f]{8}$/.test(hash))) return;
  serial(async () => {
    const key = `${zone}\t${subzone}\t${hash}\t${areaId}`;
    const { placeRequestsSent = {} } = await chrome.storage.session.get("placeRequestsSent");
    const now = Date.now();
    if (now - (placeRequestsSent[key] || 0) < PLACE_REPEAT_MS) return;
    for (const k of Object.keys(placeRequestsSent))
      if (now - placeRequestsSent[k] > PLACE_REPEAT_MS) delete placeRequestsSent[k];
    const { character = null } = await chrome.storage.session.get("character");
    const ok = await postSigned("/api/v1/place", {
      zone, subzone, hash, area_id: areaId, locale: "ruRU", client: "3.3.5a",
      realm: character?.realm || "", guid: character?.guid || "",
    });
    if (ok) {
      placeRequestsSent[key] = now;
      await chrome.storage.session.set({ placeRequestsSent });
    }
  });
}

export async function setIdentityOff(off) {
  await chrome.storage.local.set({ identityOff: off });
}

// "Something is wrong with this voice-over" from the game (the bug button).
// The player sent it on purpose, so it goes out even with statistics off,
// but then without the install and the character.
const FEEDBACK_TARGETS = ["quest", "turnin", "book", "npc"];
export function reportFeedback({ target, id, reason, locale, note } = {}) {
  if (!FEEDBACK_TARGETS.includes(target) || !Number.isInteger(reason) || reason < 1 || reason > 20) return;
  if (target === "book" ? !/^[0-9a-f]{8}$/.test(String(id)) : !(Number.isInteger(id) && id > 0 && id < 1e7)) return;
  // "id" of a signed request is the install: the quest or book goes in "quest".
  const body = {
    target, quest: id, reason,
    locale: /^[a-z]{2}[A-Z]{2}$/.test(locale) ? locale : "",
    note: String(note || "").slice(0, 200),
    ext: chrome.runtime.getManifest().version,
  };
  serial(async () => {
    const { telemetryOff = false } = await chrome.storage.local.get("telemetryOff");
    const { character = null } = await chrome.storage.session.get("character");
    if (!telemetryOff && (await postSigned("/api/v1/feedback", {
      ...body, realm: character?.realm || "", guid: character?.guid || "",
    }))) return;
    try {
      await fetch(`${UPDATE_ORIGIN}/api/v1/feedback`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
    } catch {
      // Offline: lost; the player can send it again.
    }
  });
}
