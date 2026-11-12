import { checkUpdates } from "./updates.js";
import {
  countProbe, getAddonSettings, getHeardPlaces, markHeardPlace, reportCharacter,
  reportFeedback, reportOrder, reportPlaceRequest, resetHeardPlaces, saveAddonSettings,
  sendTelemetry,
} from "./telemetry.js";
import { errorOf, recordError, sendErrors } from "./reports.js";

// Errors of this service worker go to the error report too (reports.js).
self.addEventListener("error", (e) => recordError({ source: "background", message: `${e.message} ${e.filename || ""}:${e.lineno || ""}` }));
self.addEventListener("unhandledrejection", (e) =>
  recordError({ source: "background", message: String(e.reason?.stack || e.reason) }));

const VOICE_API_ORIGIN = "https://quester.mvse.ws";
const VOICE_PATH = /^\/api\/v1\/voice\/\d{1,7}\/(DETAIL|PROGRESS|COMPLETE)$/;
const STATUS_PATH = /^\/api\/v1\/status\/\d{1,7}\/(DETAIL|PROGRESS|COMPLETE)$/;
const GOSSIP_PATH = /^\/api\/v1\/gossip$/;
const VOICE_PARAMS = new Set(["wait", "client", "locale", "variant", "p"]);
const GOSSIP_PARAMS = new Set(["wait", "client", "locale", "npc_id", "npc_gender", "title", "text", "p"]);
const BOOK_PATH = /^\/api\/v1\/book\/[0-9a-f]{8}$/;
const VOICE_LOCALES = new Set([
  "ruRU", "enUS", "zhCN", "zhTW", "deDE", "frFR",
  "esES", "esMX", "ptBR", "koKR", "itIT",
]);
const PROBE_LIMIT = 200;
const PLAY_PAGE = "https://lasthavens.com/play";

chrome.action.onClicked.addListener(() => chrome.runtime.openOptionsPage());

// CatQuest lives on the voice server: the first check installs it, later
// checks update it (updates.js). The manager opens once after installation.
const runUpdates = (force) =>
  checkUpdates({ force })
    .catch((error) => console.warn("Update check failed", error))
    .then(() => sendTelemetry({ force }));
chrome.runtime.onInstalled.addListener(async ({ reason }) => {
  if (reason === "install") chrome.runtime.openOptionsPage();
  chrome.alarms.create("updates", { periodInMinutes: 60 });
  await runUpdates(true);
});
chrome.runtime.onStartup.addListener(() => runUpdates(false));
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "updates") runUpdates(false);
  if (alarm.name === "error-report") sendErrors();
});

function base64(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 32768)
    binary += String.fromCharCode(...bytes.subarray(i, i + 32768));
  return btoa(binary);
}

// The page and game workers are untrusted: only exact voice track URLs pass.
function voiceUrl(raw) {
  let url;
  try {
    url = new URL(String(raw));
  } catch {
    return null;
  }
  if (url.origin !== VOICE_API_ORIGIN) return null;
  const isBook = BOOK_PATH.test(url.pathname);
  const isGossip = GOSSIP_PATH.test(url.pathname);
  if (!isBook && !VOICE_PATH.test(url.pathname) && !isGossip) return null;
  const variant = url.searchParams.get("variant");
  if (variant !== null && (!isBook || !["x", "m", "f"].includes(variant))) return null;
  const allowed = isGossip ? GOSSIP_PARAMS : VOICE_PARAMS;
  for (const key of url.searchParams.keys())
    if (!allowed.has(key) || url.searchParams.getAll(key).length > 1)
      return null;
  const locale = url.searchParams.get("locale");
  if (locale !== null && !VOICE_LOCALES.has(locale)) return null;
  if (isGossip) {
    const text = url.searchParams.get("text") || "";
    const title = url.searchParams.get("title") || "";
    const npcId = url.searchParams.get("npc_id") || "";
    const npcGender = url.searchParams.get("npc_gender") || "";
    if (!text || text.length > 5000 || title.length > 120) return null;
    if (npcId && !/^\d{1,7}$/.test(npcId)) return null;
    if (npcGender && !["male", "female"].includes(npcGender)) return null;
  }
  return url;
}

// Ready server tracks per locale: { ruRU: [[questId, "DETAIL", size], ...] }.
async function fetchVoiceIndex(demand) {
  try {
    const query = VOICE_LOCALES.has(demand) ? `&demand=${demand}` : "";
    const response = await fetch(`${VOICE_API_ORIGIN}/api/v1/index?client=3.3.5a${query}`, {
      cache: "no-store",
    });
    if (!response.ok) return { ok: false, error: `HTTP ${response.status}` };
    const {
      tracks, demand: wanted, placeholder_size: placeholderSize,
      gossip_placeholder_size: gossipPlaceholderSize, books, durations,
    } = await response.json();
    const clean = {};
    for (const [locale, list] of Object.entries(tracks || {})) {
      if (!VOICE_LOCALES.has(locale) || !Array.isArray(list)) continue;
      clean[locale] = list.filter(
        (t) =>
          Array.isArray(t) &&
          Number.isInteger(t[0]) && t[0] > 0 && t[0] < 1e7 &&
          (t[1] === "DETAIL" || t[1] === "COMPLETE") &&
          Number.isInteger(t[2]) && t[2] > 0 && t[2] <= 64 * 1024 * 1024,
      );
    }
    const pending = (wanted && wanted[demand]) || [];
    // Seconds of generated tracks, for the addon's subtitle bar.
    const seconds = {};
    for (const [locale, list] of Object.entries(durations || {})) {
      if (!VOICE_LOCALES.has(locale) || !Array.isArray(list)) continue;
      seconds[locale] = list.filter(
        (t) =>
          Array.isArray(t) && Number.isInteger(t[0]) && t[0] > 0 && t[0] < 1e7 &&
          (t[1] === "DETAIL" || t[1] === "COMPLETE") &&
          typeof t[2] === "number" && t[2] > 0 && t[2] < 3600,
      );
    }
    return {
      ok: true,
      tracks: clean,
      durations: seconds,
      books: (Array.isArray(books?.ruRU) ? books.ruRU : []).filter(
        (t) =>
          Array.isArray(t) && /^[0-9a-f]{8}$/.test(t[0]) && ["", "m", "f"].includes(t[1]) &&
          Number.isInteger(t[2]) && t[2] > 0 && t[2] <= 64 * 1024 * 1024,
      ),
      placeholderSize:
        Number.isInteger(placeholderSize) && placeholderSize > 0 && placeholderSize <= 16 * 1024 * 1024
          ? placeholderSize
          : 0,
      gossipPlaceholderSize:
        Number.isInteger(gossipPlaceholderSize) && gossipPlaceholderSize > 0 && gossipPlaceholderSize <= 16 * 1024 * 1024
          ? gossipPlaceholderSize
          : 0,
      demand: Array.isArray(pending)
        ? pending.filter(
            (t) =>
              Array.isArray(t) && Number.isInteger(t[0]) && t[0] > 0 && t[0] < 1e7 &&
              (t[1] === "DETAIL" || t[1] === "COMPLETE"),
          )
        : [],
    };
  } catch (error) {
    return { ok: false, error: String(error) };
  }
}

// Session storage writes are serialized so probe events are never lost.
let probeWrite = Promise.resolve();
function appendProbe(event) {
  countProbe(event);
  const error = errorOf(event);
  if (error) recordError(error, event);
  // The game ordered a track: tell the server who (telemetry.js reportOrder).
  if (event?.type === "demand") reportOrder({ quest: event.quest, kind: event.kind, locale: event.locale });
  probeWrite = probeWrite
    .then(async () => {
      const { probeLog = [] } = await chrome.storage.session.get("probeLog");
      probeLog.push(event);
      await chrome.storage.session.set({
        probeLog: probeLog.slice(-PROBE_LIMIT),
      });
    })
    .catch(() => {});
}

chrome.runtime.onMessage.addListener((m, sender, sendResponse) => {
  const senderUrl = sender.tab?.url || sender.url || "";
  const fromGame = senderUrl.startsWith(PLAY_PAGE);

  if (m.kind === "diagnostic" && fromGame) {
    chrome.storage.session.set({ lastStatus: m.status });
    return;
  }
  if (m.kind === "feedback" && fromGame) {
    reportFeedback(m);
    return;
  }
  if (m.kind === "character" && fromGame) {
    reportCharacter(m);
    return;
  }
  if (m.kind === "place-request" && fromGame) {
    reportPlaceRequest(m);
    return;
  }
  if (m.kind === "addon-settings-get" && fromGame) {
    getAddonSettings()
      .then((settings) => sendResponse({ ok: true, settings }))
      .catch(() => sendResponse({ ok: false, settings: {} }));
    return true;
  }
  if (m.kind === "addon-settings-save" && fromGame) {
    saveAddonSettings(m.settings)
      .then((ok) => sendResponse({ ok }))
      .catch(() => sendResponse({ ok: false }));
    return true;
  }
  if (m.kind === "places-heard-get" && fromGame) {
    getHeardPlaces()
      .then((heard) => sendResponse({ ok: true, heard }))
      .catch(() => sendResponse({ ok: false, heard: [] }));
    return true;
  }
  if (m.kind === "place-heard-save" && fromGame) {
    markHeardPlace(m.hash, m.areaId)
      .then((ok) => sendResponse({ ok }))
      .catch(() => sendResponse({ ok: false }));
    return true;
  }
  if (m.kind === "places-heard-reset" && fromGame) {
    resetHeardPlaces()
      .then((ok) => sendResponse({ ok }))
      .catch(() => sendResponse({ ok: false }));
    return true;
  }
  if (m.kind === "probe" && fromGame) {
    appendProbe(m.event);
    return;
  }
  // Status panel over the game: read-only server state, never a generation.
  if (m.kind === "voice-status" || m.kind === "voice-capacity") {
    // The manager page may read capacity too; status only from the game.
    const fromManager = sender.url?.startsWith(`chrome-extension://${chrome.runtime.id}/`);
    if (!fromGame && !(fromManager && m.kind === "voice-capacity")) {
      sendResponse(null);
      return;
    }
    let url;
    if (m.kind === "voice-capacity") url = new URL(`${VOICE_API_ORIGIN}/api/v1/capacity`);
    else {
      const quest = Number(m.quest);
      if (!Number.isInteger(quest) || quest <= 0 || quest >= 1e7 ||
          !["DETAIL", "PROGRESS", "COMPLETE"].includes(m.type) || !VOICE_LOCALES.has(m.locale)) {
        sendResponse(null);
        return;
      }
      url = new URL(`${VOICE_API_ORIGIN}/api/v1/status/${quest}/${m.type}?client=3.3.5a&locale=${m.locale}`);
      if (!STATUS_PATH.test(url.pathname)) {
        sendResponse(null);
        return;
      }
    }
    fetch(url, { cache: "no-store" })
      .then((r) => r.json())
      .then(sendResponse)
      .catch(() => sendResponse(null));
    return true;
  }
  if (m.kind === "check-updates") {
    const fromManager = sender.url?.startsWith(`chrome-extension://${chrome.runtime.id}/`);
    if (!fromManager) {
      sendResponse(null);
      return;
    }
    checkUpdates({ force: Boolean(m.force) })
      .then(sendResponse)
      .catch((error) => sendResponse({ error: String(error) }));
    return true;
  }
  if (m.kind === "voice-index") {
    if (!fromGame) {
      sendResponse({ ok: false, error: "invalid sender" });
      return;
    }
    // The game page opened: a good moment for the (throttled) update check.
    runUpdates(false);
    fetchVoiceIndex(m.demand).then(sendResponse);
    return true;
  }
  if (m.kind !== "voice-fetch") return;
  if (!fromGame) {
    sendResponse({ ok: false, status: 403, error: "invalid sender" });
    return;
  }
  const url = voiceUrl(m.url);
  if (!url) {
    sendResponse({ ok: false, status: 403, error: "voice URL is not allowed" });
    return;
  }

  fetch(url, { cache: "no-store" })
    .then(async (response) => {
      const contentType = response.headers.get("Content-Type") || "";
      const audio =
        response.status === 200 &&
        /^(audio\/|application\/ogg)/i.test(contentType);
      // A 202 "still generating" JSON or an error page is never sent as audio.
      const body64 = audio
        ? base64(new Uint8Array(await response.arrayBuffer()))
        : "";
      sendResponse({
        ok: audio,
        status: response.status,
        contentType,
        body64,
        error: audio ? "" : `HTTP ${response.status} ${contentType}`.trim(),
      });
    })
    .catch((error) =>
      sendResponse({ ok: false, status: 502, error: String(error) }),
    );
  return true;
});
