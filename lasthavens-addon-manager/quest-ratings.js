// Votes keep a separate install identity. Character attribution is optional
// and requires metrics sharing both at capture time and at delivery time.
import { UPDATE_ORIGIN } from "./updates.js";

const CLIENT = "3.3.5a";
let storageChain = Promise.resolve();
const update = (fn) => (storageChain = storageChain.then(fn, fn));
let flushing = null;
const valid = (m) => Number.isInteger(m?.quest) && m.quest > 0 && m.quest < 1e7 && (m.vote === 1 || m.vote === -1);

async function post(path, body) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await fetch(`${UPDATE_ORIGIN}${path}`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body), signal: controller.signal,
    });
    return { status: response.status, ok: response.ok, body: await response.json().catch(() => null) };
  } finally {
    clearTimeout(timer);
  }
}

async function identity() {
  const { questVoteIdentity } = await chrome.storage.local.get("questVoteIdentity");
  if (questVoteIdentity?.id && questVoteIdentity?.token) return questVoteIdentity;
  for (let i = 0; i < 2; i++) {
    const id = crypto.randomUUID();
    const answer = await post("/api/v1/quest-voters", { id });
    if (answer.status === 409) continue;
    if (!answer.ok || !answer.body?.token) return null;
    const who = { id, token: answer.body.token };
    await chrome.storage.local.set({ questVoteIdentity: who });
    return who;
  }
  return null;
}

let identifying = null;
export function explicitMessageIdentity() {
  if (!identifying) identifying = identity().finally(() => { identifying = null; });
  return identifying;
}

export function cleanVoteCharacter(value) {
  if (!value || typeof value !== "object") return null;
  const { realm, name, guid } = value;
  if (typeof realm !== "string" || realm.trim().length < 1 || [...realm].length > 48 ||
      typeof name !== "string" || name.trim().length < 1 || [...name].length > 24 ||
      /[\x00-\x1f]/.test(realm + name) || !/^0x[0-9a-f]{16}$/i.test(guid)) return null;
  return { realm: realm.trim(), name: name.trim(), guid: "0x" + guid.slice(2).toUpperCase() };
}

export async function captureAttribution(character) {
  const { telemetryOff = false, identityOff = false } = await chrome.storage.local.get(["telemetryOff", "identityOff"]);
  const actor = !telemetryOff && !identityOff ? cleanVoteCharacter(character) : null;
  return { share_character: Boolean(actor), character: actor };
}

export async function deliveryAttribution(item) {
  // Never look up a later/current character here. An offline message belongs
  // to the original actor; opting out before delivery suppresses that actor.
  return captureAttribution(item.share_character === true ? item.character : null);
}

export async function reportQuestVote(message) {
  if (!valid(message)) return false;
  const actor = await captureAttribution(message.character);
  const item = {
    quest: message.quest, vote: message.vote, client: CLIENT,
    locale: /^[a-z]{2}[A-Z]{2}$/.test(message.locale) ? message.locale : "",
    revision: crypto.randomUUID(), at: Date.now(), ...actor,
    event_id: /^[0-9a-f]{16}$/.test(message.event_id) ? message.event_id : crypto.randomUUID(),
    submitted_at: Number.isFinite(message.submitted_at) ? message.submitted_at : Date.now() / 1000,
  };
  await update(async () => {
    const { questVoteOutbox = {}, questVoteCache = {} } = await chrome.storage.local.get(["questVoteOutbox", "questVoteCache"]);
    questVoteOutbox[`${CLIENT}|${item.quest}`] = item;
    questVoteCache[item.quest] = { vote: item.vote, at: item.at };
    const recent = Object.entries(questVoteCache).sort((a, b) => b[1].at - a[1].at).slice(0, 2000);
    await chrome.storage.local.set({ questVoteOutbox, questVoteCache: Object.fromEntries(recent) });
  });
  // Persist before networking; a closed page, offline browser or service-worker
  // restart must not lose an already clicked vote.
  flushQuestVotes().catch(() => {});
  return true;
}

async function flush() {
  const { questVoteOutbox = {} } = await chrome.storage.local.get("questVoteOutbox");
  if (!Object.keys(questVoteOutbox).length) return;
  const who = await explicitMessageIdentity();
  if (!who) return;
  for (let sent = 0; sent < 10; sent++) {
    const current = (await chrome.storage.local.get("questVoteOutbox")).questVoteOutbox || {};
    const [key, item] = Object.entries(current)[0] || [];
    if (!item) return;
    if (!valid(item)) {
      await update(async () => {
        const { questVoteOutbox = {} } = await chrome.storage.local.get("questVoteOutbox");
        if (questVoteOutbox[key]?.revision === item.revision) delete questVoteOutbox[key];
        await chrome.storage.local.set({ questVoteOutbox });
      });
      continue;
    }
    const actor = await deliveryAttribution(item);
    if (!actor.share_character && item.character) await update(async () => {
      const { questVoteOutbox = {} } = await chrome.storage.local.get("questVoteOutbox");
      if (questVoteOutbox[key]?.revision === item.revision)
        questVoteOutbox[key] = { ...item, share_character: false, character: null };
      await chrome.storage.local.set({ questVoteOutbox });
    });
    const answer = await post("/api/v1/quest-votes", {
      ...who, quest: item.quest, vote: item.vote, client: CLIENT, locale: item.locale,
      ...actor, event_id: item.event_id || item.revision, submitted_at: item.submitted_at || item.at / 1000,
    });
    if (!answer.ok || !answer.body?.ok) return;
    await update(async () => {
      const { questVoteOutbox = {} } = await chrome.storage.local.get("questVoteOutbox");
      // A changed vote arriving while this request was in flight stays queued.
      if (questVoteOutbox[key]?.revision === item.revision) delete questVoteOutbox[key];
      await chrome.storage.local.set({ questVoteOutbox });
    });
  }
}

export function flushQuestVotes() {
  if (!flushing) flushing = flush().catch(() => {}).finally(() => { flushing = null; });
  return flushing;
}
