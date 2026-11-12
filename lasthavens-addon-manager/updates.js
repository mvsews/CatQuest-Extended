// Updates from the voice server (GET /api/v1/release).
// - Addons (CatQuest) live on the server: the first check installs them and
//   enables them, later checks replace them with newer builds. An addon the
//   player removed is not brought back.
// - The extension cannot replace its own files (it is loaded unpacked), so a
//   different channel version is announced: the manager offers the download
//   and a restart once the player has unpacked it over the old folder.
// Only the service worker runs checkUpdates, so two installs never overlap.
import { importZip } from "./archive.js";
import { mergeAddons } from "./library.js";
import { readLibrary, writeLibrary } from "./repository.js";

export const UPDATE_ORIGIN = "https://quester.mvse.ws";
const CHECK_EVERY_MS = 6 * 60 * 60 * 1000;
const RETRY_MS = 10 * 60 * 1000;

export function compareVersions(a, b) {
  const x = String(a || "").split(/[^0-9]+/).filter(Boolean).map(Number);
  const y = String(b || "").split(/[^0-9]+/).filter(Boolean).map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] || 0) - (y[i] || 0);
    if (d) return d > 0 ? 1 : -1;
  }
  return 0;
}

async function sha256(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function downloadUrl(entry) {
  const url = new URL(entry.url, UPDATE_ORIGIN);
  if (url.origin !== UPDATE_ORIGIN || !url.pathname.startsWith("/downloads/")) throw Error("bad url");
  return url.href;
}

async function fetchAddon(entry) {
  const response = await fetch(downloadUrl(entry), { cache: "no-store" });
  if (!response.ok) throw Error(`HTTP ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (entry.bytes && bytes.length !== entry.bytes) throw Error("size mismatch");
  if (entry.sha256 && (await sha256(bytes)) !== String(entry.sha256).toLowerCase())
    throw Error("checksum mismatch");
  const items = await importZip(bytes);
  const item = items.find((a) => a.folder.toLowerCase() === String(entry.folder).toLowerCase());
  if (!item || items.length !== 1) throw Error("unexpected archive");
  return item;
}

async function setBadge(state) {
  try {
    await chrome.action.setBadgeText({ text: state.extension ? "1" : "" });
    await chrome.action.setBadgeBackgroundColor({ color: "#c58b00" });
  } catch {
    // No action API in a page context; the service worker sets it.
  }
}

export async function readUpdateState() {
  const { updateState = {} } = await chrome.storage.local.get("updateState");
  return updateState;
}

export async function readUpdateChannel() {
  const { earlyUpdates = false } = await chrome.storage.local.get("earlyUpdates");
  return earlyUpdates ? "beta" : "stable";
}

// force: the player pressed "Check", the extension was just installed or
// updated. Otherwise at most every 6 hours (10 minutes after a failure, or
// while CatQuest has never been installed).
export async function checkUpdates({ force = false } = {}) {
  const state = await readUpdateState();
  const { serverAddons = {} } = await chrome.storage.local.get("serverAddons");
  const { updateChannels = {} } = await chrome.storage.local.get("updateChannels");
  const channel = await readUpdateChannel();
  const waitingFirstInstall = !serverAddons.CatQuest;
  const wait = state.error || waitingFirstInstall ? RETRY_MS : CHECK_EVERY_MS;
  if (!force && state.channel === channel && Date.now() - (state.checkedAt || 0) < wait) return state;

  const current = chrome.runtime.getManifest().version;
  const next = {
    checkedAt: Date.now(),
    current,
    channel,
    extension: null,
    installed: [],
    error: "",
  };
  try {
    const response = await fetch(
      `${UPDATE_ORIGIN}/api/v1/release?channel=${encodeURIComponent(channel)}`,
      { cache: "no-store" },
    );
    if (!response.ok) throw Error(`HTTP ${response.status}`);
    const release = await response.json();

    let library = await readLibrary();
    const fresh = [];
    for (const entry of Array.isArray(release.addons) ? release.addons : []) {
      if (!/^[A-Za-z0-9_-]+$/.test(entry?.folder || "") || !entry.version) continue;
      const installed = library.addons.find((a) => a.folder.toLowerCase() === entry.folder.toLowerCase());
      if (!installed && serverAddons[entry.folder]) continue; // removed by the player
      const installedChannel = updateChannels[entry.folder] || "stable";
      const channelChanged = installed && installedChannel !== channel;
      if (installed && !channelChanged && compareVersions(entry.version, installed.version) <= 0) continue;
      const item = await fetchAddon(entry);
      fresh.push({ item, first: !installed });
    }
    if (fresh.length) {
      library = await readLibrary();
      const merged = mergeAddons(library, fresh.map((f) => f.item));
      const firsts = new Set(fresh.filter((f) => f.first).map((f) => f.item.folder));
      await writeLibrary({
        ...merged,
        // A new addon starts enabled; an update keeps the player's choice.
        addons: merged.addons.map((a) => (firsts.has(a.folder) ? { ...a, enabled: true } : a)),
      });
      for (const { item } of fresh) {
        serverAddons[item.folder] = item.version;
        updateChannels[item.folder] = channel;
      }
      await chrome.storage.local.set({ serverAddons, updateChannels });
      next.installed = fresh.map(({ item, first }) => ({
        folder: item.folder, title: item.title, version: item.version, first, at: Date.now(),
      }));
    }

    const ext = release.extension;
    // A channel switch may intentionally be a downgrade (beta -> stable), so
    // equality is the only case where the installed extension is current.
    if (ext?.version && compareVersions(ext.version, current) !== 0) {
      next.extension = { version: ext.version, url: downloadUrl(ext), notes: String(release.notes || "") };
    }
  } catch (error) {
    next.error = String(error?.message || error).slice(0, 200);
    next.extension = state.extension && compareVersions(state.extension.version, current) > 0
      ? state.extension
      : null;
  }
  // Keep the last install notice until a newer one replaces it.
  if (!next.installed.length && state.installed?.length) next.installed = state.installed;
  await chrome.storage.local.set({ updateState: next });
  await setBadge(next);
  return next;
}
