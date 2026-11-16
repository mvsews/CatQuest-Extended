// Persist every received part before networking. Completed messages survive
// offline operation, service worker restarts and closing the game page.
import { UPDATE_ORIGIN } from "./updates.js";
import { explicitMessageIdentity, captureAttribution, deliveryAttribution, cleanVoteCharacter } from "./quest-ratings.js";
import { exportDiagnostics } from "./diagnostics-format.js";

let chain = Promise.resolve(), flushing = null;
const update = (fn) => (chain = chain.then(fn, fn));
const categories = ["error", "suggestion", "other"];
const valid = (m) => /^[0-9a-f]{16}$/.test(m?.id) && Number.isInteger(m.index) && Number.isInteger(m.total)
  && m.index >= 1 && m.index <= m.total && m.total <= 78 && categories[m.category - 1]
  && Array.isArray(m.bytes) && m.bytes.length >= 1 && m.bytes.length <= 58
  && m.bytes.every((b) => Number.isInteger(b) && b >= 0 && b <= 255);

export async function receiveContactPart(message) {
  if (!valid(message)) return false;
  const accepted = await update(async () => {
    const { contactParts = {}, contactOutbox = {}, contactReceived = {}, telemetryOff = false, identityOff = false } = await chrome.storage.local.get([
      "contactParts", "contactOutbox", "contactReceived", "telemetryOff", "identityOff",
    ]);
    const { id, index, total, category, bytes } = message;
    if (contactReceived[id] || contactOutbox[id]) return true;
    const now = Date.now();
    for (const [key, part] of Object.entries(contactParts)) if (now - part.at > 7 * 86400000) delete contactParts[key];
    if (!contactParts[id] && Object.keys(contactParts).length >= 20) return false;
    const part = contactParts[id] || { total, category, chunks: {}, at: now, allowCharacter: !telemetryOff && !identityOff };
    if (part.total !== total || part.category !== category) return false;
    if (part.chunks[index] && JSON.stringify(part.chunks[index]) !== JSON.stringify(bytes)) return false;
    part.chunks[index] = bytes; contactParts[id] = part;
    if (Object.keys(part.chunks).length === total) {
      const joined = [];
      for (let i = 1; i <= total; i++) joined.push(...part.chunks[i]);
      let body;
      try { body = new TextDecoder("utf-8", { fatal: true }).decode(new Uint8Array(joined)); }
      catch { delete contactParts[id]; await chrome.storage.local.set({ contactParts }); return false; }
      let character = null, submitted_at = part.at / 1000, addon_version = "";
      let attachDiagnostics = false, addonDiagnostics = "";
      if (body.startsWith("CQ2\t") || body.startsWith("CQ3\t")) {
        const end = body.indexOf("\n");
        if (end < 0) return false;
        const fields = body.slice(0, end).split("\t");
        const v3 = fields[0] === "CQ3";
        if ((!v3 && fields.length !== 6) || (v3 && fields.length !== 7) ||
            !/^\d{1,12}$/.test(fields[1]) || !/^[0-9A-Za-z.+_-]{1,32}$/.test(fields[2]) ||
            (v3 && fields[3] !== "0" && fields[3] !== "1")) return false;
        submitted_at = Number(fields[1]); addon_version = fields[2];
        const offset = v3 ? 1 : 0;
        attachDiagnostics = v3 && fields[3] === "1";
        character = cleanVoteCharacter({ realm: fields[3 + offset], name: fields[4 + offset], guid: fields[5 + offset] });
        body = body.slice(end + 1);
      }
      const diagnosticMarker = "\n\n--- CATQUEST ADDON DIAGNOSTICS ---\n";
      const diagnosticAt = body.indexOf(diagnosticMarker);
      if (diagnosticAt >= 0) {
        addonDiagnostics = body.slice(diagnosticAt + diagnosticMarker.length);
        body = body.slice(0, diagnosticAt);
      }
      let extensionDiagnostics = "";
      if (attachDiagnostics) {
        const { probeLog = [] } = await chrome.storage.session.get("probeLog");
        const report = exportDiagnostics(Array.isArray(probeLog) ? probeLog : [], chrome.runtime.getManifest().version);
        extensionDiagnostics = new TextDecoder().decode(new TextEncoder().encode(report).slice(0, 30000));
      }
      if (joined.length > 4500 || new TextEncoder().encode(body).length > 4000 || !body.trim() || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(body)) return false;
      if (Object.keys(contactOutbox).length >= 100) return false;
      const actor = await captureAttribution(part.allowCharacter ? character : null);
      contactOutbox[id] = { message_id: id, category: categories[category - 1], body, client: "3.3.5a",
        addon_version, extension_version: chrome.runtime.getManifest().version, at: now, submitted_at,
        diagnostics_attached: attachDiagnostics, addon_diagnostics: addonDiagnostics,
        extension_diagnostics: extensionDiagnostics, ...actor };
      // Acknowledges durable browser receipt, not server delivery.
      contactReceived[id] = now;
      const recent = Object.entries(contactReceived).sort((a, b) => b[1] - a[1]).slice(0, 500);
      delete contactParts[id];
      await chrome.storage.local.set({ contactParts, contactOutbox, contactReceived: Object.fromEntries(recent) });
    } else await chrome.storage.local.set({ contactParts });
    return true;
  });
  if (accepted) flushContactMessages().catch(() => {});
  return accepted;
}

async function flush() {
  if (!Object.keys((await chrome.storage.local.get("contactOutbox")).contactOutbox || {}).length) return;
  const who = await explicitMessageIdentity();
  if (!who) return;
  for (let n = 0; n < 10; n++) {
    const [id, item] = Object.entries((await chrome.storage.local.get("contactOutbox")).contactOutbox || {})[0] || [];
    if (!item) return;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    const actor = await deliveryAttribution(item);
    if (!actor.share_character && item.character) await update(async () => {
      const { contactOutbox = {} } = await chrome.storage.local.get("contactOutbox");
      if (contactOutbox[id]) contactOutbox[id] = { ...item, share_character: false, character: null };
      await chrome.storage.local.set({ contactOutbox });
    });
    let answer;
    try {
      answer = await fetch(`${UPDATE_ORIGIN}/api/v1/contact`, { method: "POST",
        headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...item, ...who, ...actor }), signal: controller.signal });
      if (!answer.ok || !(await answer.json())?.ok) return;
    } finally { clearTimeout(timer); }
    await update(async () => {
      const { contactOutbox = {} } = await chrome.storage.local.get("contactOutbox");
      delete contactOutbox[id]; await chrome.storage.local.set({ contactOutbox });
    });
  }
}
export function flushContactMessages() {
  if (!flushing) flushing = flush().catch(() => {}).finally(() => { flushing = null; });
  return flushing;
}
