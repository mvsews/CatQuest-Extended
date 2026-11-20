import { importZip, exportZip } from "./archive.js";
import { AddonError } from "./errors.js";
import { diagnosticLabel, exportDiagnostics } from "./diagnostics-format.js";
import {
  mergeAddons,
  toggleAddon,
  removeAddon,
  missingDependencies,
} from "./library.js";
import { readLibrary, writeLibrary } from "./repository.js";
import { languages, setLocale, t, formatSize } from "./i18n.js";
import { compareVersions, readUpdateChannel, readUpdateState } from "./updates.js";
import {
  getAccountStatus, linkAccount, rotateRecoveryCode, setTelemetryOff,
} from "./telemetry.js";
const $ = (s) => document.querySelector(s),
  el = (tag, text, className) => {
    const n = document.createElement(tag);
    if (text) n.textContent = text;
    if (className) n.className = className;
    return n;
  };
const GAME_PAGES = Object.freeze({
  main: "https://lasthavens.com/play",
  alt: "https://alt.lasthavens.com/play",
});
let library = await readLibrary(),
  busy = false,
  messageKey = "",
  details = "";
const pref = await chrome.storage.local.get(["language"]);
await setLocale(pref.language || chrome.i18n.getUILanguage());
const gamePagePref = await chrome.storage.local.get({ gamePage: "main" });
let gamePage = gamePagePref.gamePage === "alt" ? "alt" : "main";
for (const [code, name] of Object.entries(languages)) {
  const option = el("option", name);
  option.value = code;
  $("#language").append(option);
}
$("#language").value = document.documentElement.lang.replace("-", "_");
$("#version").textContent = " · v" + chrome.runtime.getManifest().version;
function showMessage(key, extra = "") {
  messageKey = key;
  details = extra;
  $("#message").textContent = key
    ? t(key, typeof extra === "object" ? extra : {})
    : "";
}
function download(addon) {
  const url = URL.createObjectURL(
    new Blob([exportZip(addon)], { type: "application/zip" }),
  );
  const link = el("a");
  link.href = url;
  link.download = addon.folder + ".zip";
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}
async function commit(next) {
  library = await writeLibrary(next);
  showMessage("saved");
}
async function action(fn) {
  if (busy) return;
  busy = true;
  render();
  try {
    await fn();
  } catch (error) {
    if (error instanceof AddonError) showMessage(error.code, error.params);
    else if (error.message === "libraryLimit") showMessage("libraryLimit");
    else {
      console.error("Addon manager operation failed", error);
      showMessage("errorUnexpected");
    }
  } finally {
    busy = false;
    render();
  }
}
function render() {
  document.title = t("title") + " · Lasthavens";
  for (const node of document.querySelectorAll("[data-i18n]"))
    node.textContent = t(node.dataset.i18n);
  for (const node of document.querySelectorAll("[data-i18n-placeholder]"))
    node.placeholder = t(node.dataset.i18nPlaceholder);
  $("#game-page").value = gamePage;
  $("#import").disabled = busy;
  $("#count").textContent =
    `${library.addons.length} ${t("addons")} · ${library.addons.filter((a) => a.enabled).length} ${t("active")} · ${formatSize(library.addons.reduce((s, a) => s + a.size, 0))}`;
  const list = $("#list");
  list.replaceChildren();
  if (!library.addons.length) list.append(el("div", t("empty"), "empty"));
  for (const addon of library.addons) {
    const card = el("article");
    const row = el("div", "", "row");
    const title = el("div");
    title.append(
      el("h2", addon.title),
      el(
        "p",
        `${addon.folder} · ${addon.version || t("noVersion")} · ${Object.keys(addon.files).length} ${t("files")} · ${formatSize(addon.size)}`,
        "meta",
      ),
    );
    const label = el("label", "", "switch-control");
    const input = el("input");
    input.type = "checkbox";
    input.role = "switch";
    input.checked = addon.enabled;
    input.disabled = busy;
    input.setAttribute("aria-label", addon.title);
    input.onchange = () =>
      action(() => commit(toggleAddon(library, addon.folder, input.checked)));
    const track = el("span", "", "switch-track");
    track.setAttribute("aria-hidden", "true");
    label.append(
      input,
      track,
      el("span", t(addon.enabled ? "enabled" : "disabled"), "switch-text"),
    );
    row.append(title, label);
    card.append(row, el("p", t("hint"), "apply-note"));
    if (addon.notes) card.append(el("p", addon.notes));
    if (addon.warnings.length)
      card.append(el("p", t("interfaceWarning"), "warning"));
    const missing = missingDependencies(addon, library);
    if (missing.length)
      card.append(
        el("p", t("dependencies", { names: missing.join(", ") }), "warning"),
      );
    const buttons = el("div", "", "actions");
    for (const [key, fn] of [
      ["exportZip", () => download(addon)],
      [
        "remove",
        () => action(() => commit(removeAddon(library, addon.folder))),
      ],
    ]) {
      const button = el("button", t(key));
      button.disabled = busy;
      button.onclick = fn;
      buttons.append(button);
    }
    card.append(buttons);
    list.append(card);
  }
  showMessage(messageKey, details);
  status();
  renderProbe();
  renderVoiceLocale();
  renderUpdates();
}
async function status() {
  const { lastStatus: s } = await chrome.storage.session.get("lastStatus");
  $("#status").textContent = !s
    ? t("waiting")
    : s.state === "error"
      ? t("loadError")
      : s.state === "pending" || s.revision !== library.revision
        ? t("changed")
        : t("ready", { count: s.loaded.length });
}
// Phase 0 diagnostics: what the game did when CatQuest asked for audio.
let probeLog = [];
const kb = (n) => (n >= 1024 ? `${Math.round(n / 1024)} KB` : `${n} B`);
function describeLegacyProbe(e) {
  const quest = e.quest
    ? `q${e.quest} ${e.kind || ""} ${e.locale || ""}`.replace(/\s+/g, " ").trim()
    : "";
  switch (e.type) {
    case "read":
      return [
        `read ${e.via}${e.sync ? " sync" : e.via === "xhr" ? " async" : ""}`,
        quest,
        e.cached ? "cache hit" : "cache miss",
      ].join(" · ");
    case "read-unmatched":
      return `unmatched ${e.via} · ${e.path}`;
    case "fetch-start":
      return `fetch → server · ${quest}`;
    case "prefetch-sent":
      return `prefetch → page · ${quest} · slot ${e.slot}`;
    case "prefetch":
      return `prefetch ${e.ok ? "ready" : "waiting/error"} · ${quest} · slot ${e.slot} · HTTP ${e.status}${e.error ? " · " + e.error : ""}`;
    case "shared-ready":
      return `shared audio ready · slot ${e.slot} · ${kb(e.bytes || 0)}`;
    case "signal":
      return `game readiness · slot ${e.slot} · ${e.ok ? "ready" : "waiting"}`;
    case "font-fs":
      return `native font read · slot ${e.slot} · ${e.ok ? "ready" : e.stage || "waiting"}${e.error ? " · " + e.error : ""}`;
    case "fetch-done":
      return [
        `fetch ← HTTP ${e.status}`,
        quest,
        e.bytes ? kb(e.bytes) : "",
        `${e.ms} ms`,
        e.ok ? "ok" : e.error,
      ]
        .filter(Boolean)
        .join(" · ");
    case "audio-api":
      return `audio api · ${e.api}${e.bytes ? " · " + kb(e.bytes) : ""}`;
    case "env":
      return `env · ${e.globals || "—"} · crossOriginIsolated=${e.isolated}`;
    case "install":
      return `overlay installed · ${e.files} addon files · ${e.bytes || 0} server tracks in manifest` +
        (e.status ? ` · ${e.status} on demand (${e.locale})` : "") +
        (e.api ? ` · ${e.api}` : "") + (e.detail ? ` · ${e.detail}` : "") +
        (e.addon || e.ext ? ` · addon=${e.addon || "?"} ext=${e.ext || "?"}` : "");
    case "voice-locale":
      return `addon voice language · ${e.locale} (applies after reloading the game)`;
    case "demand":
      return `generation requested · ${quest} · HTTP ${e.status}`;
    case "limited":
      return `generation limited · ${quest} · HTTP ${e.status}`;
    case "readiness":
      return `audio readiness · ${quest} · ${e.ok ? "confirmed" : "waiting"}`;
    case "texture-probe":
      return `texture probe read · ${e.status === 200 ? "yes.tga (served)" : "no.tga (missing)"}${e.sync ? " · sync" : " · async"}`;
    case "poll":
      return `poll.ogg → ${quest} · ready, handed to the game`;
    case "direct":
      return e.error
        ? `direct read blocked · ${e.error}`
        : [`direct read ← HTTP ${e.status}`, quest, e.bytes ? kb(e.bytes) : "", `${e.ms} ms`]
            .filter(Boolean)
            .join(" · ");
    case "size-mismatch":
      return `size mismatch · ${quest} · got ${e.bytes} B, manifest ${e.status} B`;
    default:
      return [e.type,e.error,e.detail,e.path].filter(Boolean).join(" · ");
  }
}
function describeProbe(e) { return diagnosticLabel(e, describeLegacyProbe(e)); }
function probeVerdict(log) {
  const reads = log.filter((e) => e.type === "read");
  if (!reads.length)
    return log.some((e) => e.type === "install") ? t("diagNoRead") : "";
  if (reads.some((e) => e.sync))
    return t("diagSync", {
      count: reads.filter((e) => e.sync && e.cached).length,
    });
  return t("diagAsync");
}
async function renderProbe() {
  ({ probeLog = [] } = await chrome.storage.session.get("probeLog"));
  const list = $("#diag-log");
  list.replaceChildren();
  if (!probeLog.length) list.append(el("li", t("diagEmpty")));
  for (const e of [...probeLog].reverse().slice(0, 100)) {
    const row = el(
      "li",
      "",
      e.type === "fetch-done" || e.type === "direct"
        ? e.ok ? "good" : "bad"
        : e.type === "size-mismatch" ? "bad" : "",
    );
    const time = el("time", new Date(e.at || 0).toLocaleTimeString());
    row.append(time, el("span", e.ctx || "", "ctx"), el("span", describeProbe(e)));
    list.append(row);
  }
  const verdict = probeVerdict(probeLog);
  $("#diag-verdict").hidden = !verdict;
  $("#diag-verdict").textContent = verdict;
}
$("#diag-clear").onclick = async () => {
  await chrome.storage.session.remove("probeLog");
  renderProbe();
};
$("#diag-copy").onclick = async () => {
  ({ probeLog = [] } = await chrome.storage.session.get("probeLog"));
  const text = exportDiagnostics(probeLog, chrome.runtime.getManifest().version);
  try {
    await navigator.clipboard.writeText(text || "(empty)");
    showMessage("diagCopied");
  } catch {
    showMessage("errorUnexpected");
  }
};
$("#import").onchange = (e) => {
  const files = [...e.target.files];
  action(async () => {
    const items = [];
    for (const file of files)
      items.push(
        ...(await importZip(new Uint8Array(await file.arrayBuffer()))),
      );
    await commit(mergeAddons(library, items));
    showMessage("imported");
  }).finally(() => (e.target.value = ""));
};
$("#language").onchange = async (e) => {
  await setLocale(e.target.value);
  await chrome.storage.local.set({ language: e.target.value });
  render();
};

// Voice language for on-demand voicing: "auto" follows /cq lang from the game.
const VOICE_LOCALES = ["ruRU", "enUS", "zhCN", "zhTW", "deDE", "frFR", "esES", "esMX", "ptBR", "koKR", "itIT"];
async function renderVoiceLocale() {
  const { voiceLocale = "auto", voiceLocaleAuto = "" } = await chrome.storage.local.get([
    "voiceLocale",
    "voiceLocaleAuto",
  ]);
  const select = $("#voice-locale");
  select.replaceChildren();
  const auto = el("option", t("voiceLocaleAuto", { locale: voiceLocaleAuto || "ruRU" }));
  auto.value = "auto";
  select.append(auto);
  for (const code of VOICE_LOCALES) {
    const option = el("option", code);
    option.value = code;
    select.append(option);
  }
  select.value = VOICE_LOCALES.includes(voiceLocale) ? voiceLocale : "auto";
}
$("#voice-locale").onchange = async (e) => {
  await chrome.storage.local.set({ voiceLocale: e.target.value });
  showMessage("voiceApiSaved");
};
renderVoiceLocale();

// How much the voice server can still do: queue, hourly limit, budget.
async function renderCapacity() {
  const c = await chrome.runtime.sendMessage({ kind: "voice-capacity" }).catch(() => null);
  $("#voice-capacity").textContent = !c
    ? t("capacityOffline")
    : !c.generation
      ? t("capacityOff")
      : t("capacity", {
          queue: c.queued + c.running,
          used: c.used_last_hour,
          limit: c.per_hour,
          seconds: c.average_seconds,
          budget: c.budget_tracks ?? "?",
        }) + (c.left_this_hour === 0 ? " " + t("capacityLimited", { minutes: Math.ceil(c.next_slot_seconds / 60) }) : "");
}
renderCapacity();
setInterval(renderCapacity, 15000);
$("#game-page").onchange = async (event) => {
  gamePage = event.target.value === "alt" ? "alt" : "main";
  await chrome.storage.local.set({ gamePage });
  showMessage("gamePageSaved");
};
$("#play").onclick = () => chrome.tabs.create({ url: GAME_PAGES[gamePage] });
// Updates: CatQuest comes from the voice server and is updated by the
// service worker; a newer extension is offered as a download.
async function renderUpdates() {
  const state = await readUpdateState();
  const channel = await readUpdateChannel();
  const early = channel === "beta";
  const earlyInput = $("#early-updates");
  earlyInput.checked = early;
  earlyInput.disabled = busy;
  const current = chrome.runtime.getManifest().version;
  const lines = [
    state.checkedAt
      ? t("updatesChecked", { time: new Date(state.checkedAt).toLocaleString() })
      : t("updatesNever"),
  ];
  const extension =
    state.extension && compareVersions(state.extension.version, current) !== 0 ? state.extension : null;
  lines.unshift(t(early ? "updatesChannelBeta" : "updatesChannelStable"));
  if (state.error) lines.push(t("updatesOffline", { error: state.error }));
  else if (!extension) lines.push(t("updatesUpToDate", { version: current }));
  for (const item of state.installed || [])
    lines.push(t(item.first ? "updatesAddonInstalled" : "updatesAddonUpdated", {
      name: item.title || item.folder,
      version: item.version,
    }));
  $("#updates-status").textContent = lines.join(" ");
  $("#updates-extension").hidden = !extension;
  if (extension) {
    $("#updates-extension-text").textContent = t("updatesExtension", { version: extension.version, current });
    $("#updates-notes").textContent = extension.notes || "";
  }
}
$("#early-updates").onchange = async (event) => {
  await chrome.storage.local.set({ earlyUpdates: Boolean(event.target.checked) });
  await checkNow(true);
};
async function checkNow(force) {
  $("#updates-check").disabled = true;
  if (force) $("#updates-status").textContent = t("updatesChecking");
  await chrome.runtime.sendMessage({ kind: "check-updates", force }).catch(() => null);
  $("#updates-check").disabled = false;
  renderUpdates();
}
$("#updates-check").onclick = () => checkNow(true);
$("#updates-download").onclick = async () => {
  const { extension } = await readUpdateState();
  if (!extension?.url) return;
  // The server sends it as an attachment: the browser saves it, the page stays.
  const link = el("a");
  link.href = extension.url;
  link.click();
};
$("#updates-reload").onclick = () => chrome.runtime.reload();
async function renderAccount() {
  $("#account-status").textContent = t("accountLoading");
  const status = await getAccountStatus();
  const text = $("#account-status");
  const row = $("#account-code-row");
  if (!status) {
    text.textContent = t("accountOffline");
    row.hidden = true;
    return;
  }
  const names = (status.characters || []).slice(0, 5).map((c) => `${c.name} (${c.realm})`);
  text.textContent = t("accountReady", {
    id: status.account_id,
    installs: status.installs,
    characters: names.length ? names.join(", ") : t("accountNoCharacters"),
  });
  const { telemetry = {} } = await chrome.storage.local.get("telemetry");
  $("#account-code").textContent = telemetry.recoveryCode || t("accountNoCode");
  row.hidden = !telemetry.recoveryCode;
  const { placesScope = "account" } = await chrome.storage.local.get("placesScope");
  $("#places-scope").value = placesScope === "character" ? "character" : "account";
}
$("#account-recovery").onclick = async () => {
  const result = await rotateRecoveryCode();
  if (result?.recovery_code) {
    $("#account-code").textContent = result.recovery_code;
    $("#account-code-row").hidden = false;
    showMessage("accountCodeSaved");
  } else showMessage("accountUnavailable");
};
$("#account-link").onclick = async () => {
  const result = await linkAccount($("#account-link-code").value);
  if (result?.account_id) {
    $("#account-link-code").value = "";
    showMessage("accountLinked");
    renderAccount();
  } else showMessage("accountLinkFailed");
};
renderAccount();
$("#places-scope").onchange = async (event) => {
  await chrome.storage.local.set({
    placesScope: event.target.value === "character" ? "character" : "account",
    placesHeardScopeKey: "",
  });
  showMessage("placesScopeSaved");
};
// Statistics, the character playing and error reports (telemetry.js,
// reports.js): on by default; one switch at the bottom turns all of it off.
chrome.storage.local.get("telemetryOff").then(({ telemetryOff }) => {
  $("#telemetry").checked = !telemetryOff;
});
// 0.6.13 had a separate switch for the character: one switch now.
chrome.storage.local.remove("identityOff").catch(() => {});
$("#telemetry").onchange = async (e) => {
  await setTelemetryOff(!e.target.checked);
  showMessage("saved");
};
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "local" && changes.updateState) renderUpdates();
});
checkNow(false);
chrome.storage.onChanged.addListener(async (changes, area) => {
  if (area === "session") {
    status();
    if (changes.probeLog) renderProbe();
  }
  if (area === "local" && (changes.voiceLocale || changes.voiceLocaleAuto)) renderVoiceLocale();
  if (area === "local" && changes.library && !busy) {
    library = await readLibrary();
    render();
  }
});
render();
