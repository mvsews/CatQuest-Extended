// Error reports for the voice server (POST /api/v1/errors).
// Collected: Lua errors of CatQuest (via the addon's markers), errors of the
// extension's own code (runtime, bridge, background) and failed voice
// deliveries. A minute after an error the report goes out with the last
// diagnostics events, so the cause can be found without asking the player.
// Nothing is kept or sent while statistics are off. The character is added
// only when the player lets the extension report it (telemetry.js).
import { UPDATE_ORIGIN } from "./updates.js";
import { readLibrary } from "./repository.js";

const MAX_KINDS = 40; // distinct errors kept until sent
const PROBES_IN_REPORT = 40;
const SEND_AFTER_MIN = 1;
let chain = Promise.resolve();
const serial = (fn) => (chain = chain.then(fn).catch(() => {}));

// Which diagnostics events are errors, and the text that groups them.
export function errorOf(event) {
  switch (event?.type) {
    case "lua-error":
      return { source: "addon", message: String(event.error || "") };
    case "runtime-error":
      return { source: "runtime", message: `${event.error || ""} ${event.path || ""}`.trim() };
    case "bridge-error":
      return { source: "bridge", message: String(event.error || "") };
    case "size-mismatch":
      return { source: "delivery", message: `size mismatch ${event.kind || ""} ${event.locale || ""}`.trim() };
    case "fetch-done":
      return event.ok ? null : { source: "delivery", message: `fetch failed ${event.status || ""} ${event.error || ""}`.trim() };
    case "direct":
      return event.status === 0 || event.status >= 500
        ? { source: "delivery", message: `direct read ${event.status}` }
        : null;
    default:
      return null;
  }
}

export function recordError({ source, message }, event = null) {
  message = String(message || "").replace(/\s+/g, " ").slice(0, 300);
  if (!message) return;
  serial(async () => {
    const { telemetryOff = false, errorLog = [] } = await chrome.storage.local.get(["telemetryOff", "errorLog"]);
    if (telemetryOff) return;
    const now = Date.now();
    const found = errorLog.find((e) => e.source === source && e.message === message);
    if (found) {
      found.count = Math.min(found.count + 1, 100000);
      found.last = now;
    } else {
      errorLog.push({ source, message, count: 1, first: now, last: now, quest: event?.quest || 0 });
      while (errorLog.length > MAX_KINDS) errorLog.shift();
    }
    await chrome.storage.local.set({ errorLog });
    chrome.alarms.create("error-report", { delayInMinutes: SEND_AFTER_MIN });
  });
}

export function sendErrors() {
  return serial(async () => {
    const { telemetryOff = false, identityOff = false, errorLog = [], telemetry = {} } =
      await chrome.storage.local.get(["telemetryOff", "identityOff", "errorLog", "telemetry"]);
    if (telemetryOff) {
      if (errorLog.length) await chrome.storage.local.set({ errorLog: [] });
      return;
    }
    if (!errorLog.length) return;
    let id = telemetry.id;
    if (!id) {
      id = crypto.randomUUID();
      await chrome.storage.local.set({ telemetry: { ...telemetry, id } });
    }
    const { probeLog = [], character = null } = await chrome.storage.session.get(["probeLog", "character"]);
    const library = await readLibrary().catch(() => ({ addons: [] }));
    const addon = library.addons.find((a) => a.folder === "CatQuest");
    const { voiceLocale, voiceLocaleAuto } = await chrome.storage.local.get(["voiceLocale", "voiceLocaleAuto"]);
    const body = {
      id,
      ext: chrome.runtime.getManifest().version,
      addon: addon?.version || "",
      locale: (voiceLocale !== "auto" && voiceLocale) || voiceLocaleAuto || "",
      browser: navigator.userAgent.slice(0, 160),
      character: !identityOff && character ? { realm: character.realm, name: character.name } : null,
      errors: errorLog,
      probes: probeLog.slice(-PROBES_IN_REPORT),
    };
    let ok = false;
    try {
      const response = await fetch(`${UPDATE_ORIGIN}/api/v1/errors`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      // 4xx: the server will not take this report; do not retry it for ever.
      ok = response.ok || (response.status >= 400 && response.status < 500);
    } catch {
      // Offline: next alarm.
    }
    if (ok) {
      // Errors added while sending stay for the next report.
      const { errorLog: now = [] } = await chrome.storage.local.get("errorLog");
      const sent = new Set(errorLog.map((e) => `${e.source}\t${e.message}\t${e.count}`));
      await chrome.storage.local.set({ errorLog: now.filter((e) => !sent.has(`${e.source}\t${e.message}\t${e.count}`)) });
    } else {
      chrome.alarms.create("error-report", { delayInMinutes: 30 });
    }
  });
}
