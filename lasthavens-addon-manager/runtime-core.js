// Runs both on the page and in game workers. Addon bytes stay local; CatQuest
// audio is fetched from the voice API through the extension on demand.
//
// The game reads files with synchronous XHR, and a synchronous read cannot
// wait for the network. So the first read of a server track answers 404 and
// starts a background fetch; the addon retries PlaySoundFile and a later read
// is served from the in-memory cache. Every CatQuest read is also reported to
// the extension as a Phase 0 probe event, so the manager page shows how the
// client actually requests audio.
globalThis.LHInstallOverlay = function (
  files,
  base,
  voiceApi,
  clientVersion,
  remoteTracks,
  remoteDemand,
  remoteBooks,
  remoteGossip,
  player,
) {
  const Native = XMLHttpRequest,
    NativeFetch = globalThis.fetch,
    paths = Object.keys(files),
    api = String(voiceApi || "https://quester.mvse.ws").replace(/\/+$/, ""),
    // Whose request it is, for the server's history of plays: the install
    // number, only when statistics are on (else the server counts a guest).
    playerParam = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(String(player || ""))
      ? `&p=${player}`
      : "",
    version = encodeURIComponent(clientVersion || "3.3.5a"),
    CHANNEL = "lh-catquest-voice-v1",
    REMOTE_FOLDER = "Interface/AddOns/CatQuest335_ServerVoices",
    pageContext = typeof window !== "undefined" && window === globalThis,
    context = pageContext ? "page" : "worker",
    voiceChannel =
      !pageContext && typeof BroadcastChannel === "function"
        ? new BroadcastChannel(CHANNEL)
        : null,
    pending = new Map(),
    audio = new Map(),
    inflight = new Map(),
    missedAt = new Map(),
    declared = new Map(),
    probeSeen = new Map(),
    VOICE_LOCALES = [
      "ruRU", "enUS", "zhCN", "zhTW", "deDE", "frFR",
      "esES", "esMX", "ptBR", "koKR", "itIT",
    ],
    // Cloudflare Tunnel drops a response after 100 s (HTTP 524), so the
    // server must answer before that: wait at most 90 s per request.
    SERVER_WAIT_S = 90,
    // After a non-audio answer (404, 502, 202 after the wait) the addon keeps
    // retrying every 0.5 s; do not turn each retry into a server request.
    MISS_BACKOFF_MS = 5000,
    AUDIO_CACHE_LIMIT = 32,
    BRIDGE_TIMEOUT_MS = 100000;
  const placeholders = new Set(),
    directMissAt = new Map();
  const GOSSIP_PLACEHOLDER_SIZE = Number.isInteger(remoteGossip)
    ? remoteGossip
    : Number(remoteGossip?.size) || 0;
  const GOSSIP_LOCALE = VOICE_LOCALES.includes(remoteGossip?.locale)
    ? remoteGossip.locale
    : "ruRU";
  const GOSSIP_AUDIO_SLOTS = 255;
  const GOSSIP_MARKER_SLOTS = 16;
  const GOSSIP_MARKER_NIBBLES = 144;
  const gossipNibbles = new Map(), gossipParts = new Map(), gossipTexts = new Map();
  let lastCatQuestAt = 0,
    // Direct synchronous reads from the voice API work only if the page's
    // CSP allows them; after the first network error the bridge is used.
    directState = "unknown";

  const post = (message) => {
    message.channel = CHANNEL;
    if (pageContext) window.postMessage(message, location.origin);
    else if (voiceChannel) voiceChannel.postMessage(message);
  };
  const parseSavedAddonSettings = (text) => {
    const source = String(text || "");
    if (!/CatQuest335DB\s*=\s*\{/.test(source)) return null;
    const settings = {};
    const bools = [
      "enabled", "auto", "showSubtitle", "books", "turnin", "queue", "readAfterAccept",
      "stopOnClose", "readButton", "bookPages", "head", "headLocked", "keepInBackground",
      "compact", "minimap", "minimapLocked", "storyQuestTitles", "places", "remoteEnabled",
    ];
    const numbers = ["trackGap", "duck", "scale", "minimapAngle", "remoteDuration", "pendingTimeout"];
    const texts = ["volumeChannel", "language", "uiLanguage", "pack"];
    for (const key of bools) {
      const match = new RegExp(`\\["${key}"\\]\\s*=\\s*(true|false)`).exec(source);
      if (match) settings[key] = match[1] === "true";
    }
    for (const key of numbers) {
      const match = new RegExp(`\\["${key}"\\]\\s*=\\s*(-?\\d+(?:\\.\\d+)?)`).exec(source);
      if (match) settings[key] = Number(match[1]);
    }
    for (const key of texts) {
      const match = new RegExp(`\\["${key}"\\]\\s*=\\s*"([^"]*)"`).exec(source);
      if (match) settings[key] = match[1];
    }
    const position = /\["headPosition"\]\s*=\s*\{([\s\S]*?)\}/.exec(source)?.[1] || "";
    const point = /\["point"\]\s*=\s*"([^"\\]{1,32})"/.exec(position)?.[1];
    const relativePoint = /\["relativePoint"\]\s*=\s*"([^"\\]{1,32})"/.exec(position)?.[1];
    const x = /\["x"\]\s*=\s*(-?\d+(?:\.\d+)?)/.exec(position)?.[1];
    const y = /\["y"\]\s*=\s*(-?\d+(?:\.\d+)?)/.exec(position)?.[1];
    if (point && relativePoint && x !== undefined && y !== undefined)
      settings.headPosition = { point, relativePoint, x: Number(x), y: Number(y) };
    return Object.keys(settings).length ? settings : null;
  };
  const probe = (event) => {
    try {
      post({ kind: "probe", event: { ...event, ctx: context, at: Date.now() } });
    } catch {
      // Diagnostics must never break the game.
    }
  };
  const runtimeError = (where, error, path) =>
    probe({ type: "runtime-error", error: `${where}: ${String(error?.stack || error).slice(0, 180)}`,
      path: String(path || "").slice(0, 120) });
  // Lua retries every 0.5 s; report the same read at most every 10 s.
  const probeOnce = (key, event) => {
    const now = Date.now();
    if (now - (probeSeen.get(key) || 0) < 10000) return;
    probeSeen.set(key, now);
    if (probeSeen.size > 200) probeSeen.delete(probeSeen.keys().next().value);
    probe(event);
  };

  const onResponse = (data) => {
    if (data?.kind !== "voice-response") return;
    const waiting = pending.get(data.id);
    if (!waiting) return;
    pending.delete(data.id);
    clearTimeout(waiting.timer);
    waiting.resolve(data);
  };
  if (voiceChannel)
    voiceChannel.addEventListener("message", (event) => onResponse(event.data));
  // Which track poll.ogg stands for now (page side, from the game worker).
  const pagePolls = new Map(); // poll file n -> remote picked by the worker
  if (pageContext && typeof BroadcastChannel === "function")
    new BroadcastChannel(CHANNEL).addEventListener("message", (event) => {
      if (event.data?.kind === "poll-pick" && typeof event.data.path === "string" && Number.isInteger(event.data.n)) {
        pagePolls.set(event.data.n, remoteFor("/game/" + event.data.path));
        if (pagePolls.size > 64) pagePolls.delete(pagePolls.keys().next().value);
      }
      if (event.data?.kind === "gossip-text" && Number.isInteger(event.data.id) && typeof event.data.text === "string")
        gossipTexts.set(event.data.id, event.data.text);
    });
  if (pageContext)
    window.addEventListener("message", (event) => {
      if (
        event.source === window &&
        event.origin === location.origin &&
        event.data?.channel === CHANNEL
      )
        onResponse(event.data);
    });

  const askBridge = (url) =>
    new Promise((resolve) => {
      const id = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const timer = setTimeout(() => {
        pending.delete(id);
        resolve({ ok: false, status: 504, error: "bridge timeout" });
      }, BRIDGE_TIMEOUT_MS);
      pending.set(id, { resolve, timer });
      post({ kind: "voice-fetch", id, url });
    });

  const decode64 = (text) => {
    const binary = atob(text);
    const out = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
    return out;
  };
  const isAudio = (type) =>
    /^(audio\/|application\/ogg)/i.test(String(type || ""));

  // Strict path parser: only CatQuest server tracks, everything else passes.
  const remoteFor = (pathname) => {
    let p = String(pathname);
    try {
      p = decodeURIComponent(p);
    } catch {
      // keep the raw path
    }
    p = p
      .replace(/\\/g, "/")
      .replace(/^\/+/, "")
      .replace(/^(game|blocks)\//i, "");
    const block = p.match(/\/(\d+)-(\d+)-(\d+)k\.bin$/i);
    if (block) p = p.slice(0, block.index);
    // Free-form NPC greetings are sent by the addon through marker files and
    // then opened as one of these fixed virtual slots. Keep the text in the
    // URL only after the runtime has reconstructed it; the game never sees a
    // long or user-controlled path in its manifest.
    const gossip = p.match(
      /^Interface\/AddOns\/CatQuest335_ServerVoices\/gossip\/(\d{1,3})\.ogg$/i,
    );
    if (gossip) {
      const slot = Number(gossip[1]), packed = gossipTexts.get(slot);
      if (!GOSSIP_PLACEHOLDER_SIZE || !packed || slot < 1 || slot > GOSSIP_AUDIO_SLOTS) return null;
      const firstSplit = packed.indexOf("\n");
      let title = firstSplit >= 0 ? packed.slice(0, firstSplit) : "NPC dialogue";
      let text = firstSplit >= 0 ? packed.slice(firstSplit + 1) : packed;
      let npcId = "";
      let npcGender = "";
      // CatQuest 3.3.5 sends an optional v2 header so the backend can pick
      // the voice for the actual NPC instead of using one generic voice.
      if (firstSplit >= 0 && packed.slice(0, firstSplit).startsWith("v2\t")) {
        const header = packed.slice(0, firstSplit).split("\t");
        npcId = /^\d{1,7}$/.test(header[1] || "") ? header[1] : "";
        npcGender = ["male", "female"].includes(header[2]) ? header[2] : "";
        const secondSplit = packed.indexOf("\n", firstSplit + 1);
        title = secondSplit >= 0 ? packed.slice(firstSplit + 1, secondSplit) : "NPC dialogue";
        text = secondSplit >= 0 ? packed.slice(secondSplit + 1) : "";
      }
      if (!text) return null;
      if (!/^https?:\/\//i.test(api)) return null;
      const npcParam = npcId ? `&npc_id=${npcId}` : "";
      const genderParam = npcGender ? `&npc_gender=${npcGender}` : "";
      const url = `${api}/api/v1/gossip?wait=${SERVER_WAIT_S}&client=${version}&locale=${GOSSIP_LOCALE}` +
        `${npcParam}${genderParam}&title=${encodeURIComponent(title.slice(0, 120))}` +
        `&text=${encodeURIComponent(text.slice(0, 5000))}${playerParam}`;
      return {
        key: url,
        url,
        quest: 0,
        type: "GOSSIP",
        locale: GOSSIP_LOCALE,
        size: GOSSIP_PLACEHOLDER_SIZE,
        placeholder: true,
        path: p,
        block: block
          ? { start: Number(block[2]) * Number(block[3]) * 1024, size: Number(block[3]) * 1024 }
          : null,
      };
    }
    // Books, notes and place lore: narrator tracks keyed by an 8-hex hash.
    const book = p.match(
      /^Interface\/AddOns\/CatQuest335_ServerVoices\/(?:([a-z]{4})\/)?Sounds\/b\/([0-9a-f]{8})(?:_([mf]))?\.ogg$/i,
    );
    if (book) {
      if (!/^https?:\/\//i.test(api)) return null;
      const hash = book[2].toLowerCase(),
        variant = (book[3] || "").toLowerCase();
      const url = `${api}/api/v1/book/${hash}?wait=${SERVER_WAIT_S}&client=${version}&locale=ruRU&variant=${variant || "x"}`;
      return {
        key: url,
        url,
        hash,
        quest: 0,
        type: "BOOK",
        locale: "ruRU",
        size: declared.get(`book|${hash}|${variant}`) || 0,
        placeholder: false,
        path: p,
        block: block
          ? { start: Number(block[2]) * Number(block[3]) * 1024, size: Number(block[3]) * 1024 }
          : null,
      };
    }
    // The voice locale is a path segment; a path without it means ruRU.
    let quest, type, rawLocale, m;
    if (
      (m = p.match(
        /^Interface\/AddOns\/CatQuest335_ServerVoices\/(?:([a-z]{4})\/)?Sounds\/q\/(\d{1,7})(_t)?(?:_n(\d{1,7}))?(?:_[mf])?\.ogg$/i,
      ))
    ) {
      rawLocale = m[1];
      quest = m[2];
      type = m[3] ? "COMPLETE" : "DETAIL";
    } else if (
      (m = p.match(
        /^Interface\/AddOns\/CatQuest\/Sounds\/(?:([a-z]{4})\/)?q(\d{1,7})_(DETAIL|PROGRESS|COMPLETE)\.ogg$/i,
      ))
    ) {
      rawLocale = m[1];
      quest = m[2];
      type = m[3].toUpperCase();
    } else return null;
    const locale = VOICE_LOCALES.find(
      (l) => l.toLowerCase() === String(rawLocale || "ruRU").toLowerCase(),
    );
    if (!locale) return null;
    if (!/^https?:\/\//i.test(api)) return null;
    const npcId = m[4] || "";
    const npcParam = npcId ? `&npc_id=${npcId}` : "";
    const url = `${api}/api/v1/voice/${quest}/${type}?wait=${SERVER_WAIT_S}&client=${version}&locale=${locale}${npcParam}${playerParam}`;
    return {
      key: url,
      url,
      quest: Number(quest),
      type,
      locale,
      size: declared.get(`${locale}|${Number(quest)}|${type}`) || 0,
      placeholder: placeholders.has(`${locale}|${Number(quest)}|${type}`),
      path: p,
      block: block
        ? {
            start: Number(block[2]) * Number(block[3]) * 1024,
            size: Number(block[3]) * 1024,
          }
        : null,
    };
  };

  // One full download per track, shared by every reader; only real audio is cached.
  const fetchAudio = (remote) => {
    const hit = audio.get(remote.key);
    if (hit) {
      audio.delete(remote.key);
      audio.set(remote.key, hit);
      return Promise.resolve(hit);
    }
    if (inflight.has(remote.key)) return inflight.get(remote.key);
    if (Date.now() - (missedAt.get(remote.key) || 0) < MISS_BACKOFF_MS)
      return Promise.resolve(null);
    const started = Date.now();
    probe({
      type: "fetch-start",
      quest: remote.quest,
      kind: remote.type,
      locale: remote.locale,
      ok: remote.placeholder,
    });
    const job = (async () => {
      let res;
      if (pageContext || voiceChannel) res = await askBridge(remote.url);
      else {
        try {
          const r = await NativeFetch.call(globalThis, remote.url, {
            cache: "no-store",
          });
          res = {
            ok: r.ok,
            status: r.status,
            contentType: r.headers.get("Content-Type"),
            bytes: new Uint8Array(await r.arrayBuffer()),
          };
        } catch (error) {
          res = { ok: false, status: 502, error: String(error) };
        }
      }
      let bytes = res.bytes instanceof Uint8Array ? res.bytes : null;
      if (!bytes && typeof res.body64 === "string") bytes = decode64(res.body64);
      const good =
        res.status === 200 && isAudio(res.contentType) && !!bytes?.length;
      probe({
        type: "fetch-done",
        quest: remote.quest,
        kind: remote.type,
        locale: remote.locale,
        status: res.status || 0,
        bytes: bytes ? bytes.length : 0,
        ms: Date.now() - started,
        ok: good,
        error: res.error || (good ? "" : String(res.contentType || "")),
      });
      if (!good) {
        missedAt.set(remote.key, Date.now());
        if (missedAt.size > 200) missedAt.delete(missedAt.keys().next().value);
        return null;
      }
      missedAt.delete(remote.key);
      return store(remote, bytes);
    })().finally(() => inflight.delete(remote.key));
    inflight.set(remote.key, job);
    return job;
  };

  const slice = (bytes, remote, rangeHeader) => {
    let start = 0,
      end = bytes.length,
      status = 200;
    if (remote.block) {
      start = remote.block.start;
      end = Math.min(bytes.length, start + remote.block.size);
    }
    const m = rangeHeader && /bytes=(\d+)-(\d*)/.exec(rangeHeader);
    if (m) {
      start = Number(m[1]);
      end = m[2] ? Math.min(bytes.length, Number(m[2]) + 1) : bytes.length;
      status = 206;
    }
    start = Math.min(start, bytes.length);
    end = Math.max(start, end);
    return {
      bytes: bytes.slice(start, end),
      status,
      range: status === 206 ? `bytes ${start}-${end - 1}/${bytes.length}` : "",
    };
  };

  // Place lore heard: the game read its track. SavedVariables are lost on
  // F5, so the bridge keeps the list and gives it back in Bridge.lua; else
  // the place the player logs in at is read again on every login.
  const heardPosted = new Set();
  const noteRead = (via, remote, sync) => {
    lastCatQuestAt = Date.now();
    if (remote.type === "BOOK" && remote.hash && !heardPosted.has(remote.hash)) {
      heardPosted.add(remote.hash);
      post({ kind: "place-heard", hash: remote.hash });
    }
    const cached = audio.has(remote.key);
    probeOnce(`${via}|${remote.key}|${cached}`, {
      type: "read",
      via,
      sync,
      quest: remote.quest,
      kind: remote.type,
      locale: remote.locale,
      cached,
      path: remote.path,
    });
  };
  const noteUnmatched = (via, path) => {
    if (!/catquest/i.test(path)) return;
    probeOnce(`unmatched|${path}`, { type: "read-unmatched", via, path });
  };

  // Server tracks become ordinary files in the game's manifest: the game
  // only reads files it knows, and it needs their exact size.
  const remoteLines = [];
  for (const [locale, tracks] of Object.entries(remoteTracks || {})) {
    if (!VOICE_LOCALES.includes(locale) || !Array.isArray(tracks)) continue;
    for (const track of tracks) {
      const [quest, type, size] = Array.isArray(track) ? track : [];
      if (!Number.isInteger(quest) || !Number.isInteger(size) || size <= 0) continue;
      if (type !== "DETAIL" && type !== "COMPLETE") continue;
      declared.set(`${locale}|${quest}|${type}`, size);
      remoteLines.push(
        `${size}\t${REMOTE_FOLDER}/${locale}/Sounds/q/${quest}${type === "COMPLETE" ? "_t" : ""}.ogg`,
      );
    }
  }
  // Book tracks (ruRU narrator) are ordinary files of the manifest too.
  for (const track of Array.isArray(remoteBooks) ? remoteBooks : []) {
    const [hash, variant, size] = Array.isArray(track) ? track : [];
    if (!/^[0-9a-f]{8}$/.test(hash) || !["", "m", "f"].includes(variant)) continue;
    if (!Number.isInteger(size) || size <= 0) continue;
    declared.set(`book|${hash}|${variant}`, size);
    remoteLines.push(`${size}\t${REMOTE_FOLDER}/ruRU/Sounds/b/${hash}${variant ? "_" + variant : ""}.ogg`);
  }
  const bookCount = Array.isArray(remoteBooks) ? remoteBooks.length : 0;

  // Fixed virtual files for free-form NPC gossip. Their content is supplied
  // just before playback through gossip-msg marker files and is padded to the
  // same placeholder size as other on-demand tracks.
  if (GOSSIP_PLACEHOLDER_SIZE) {
    for (let slot = 1; slot <= GOSSIP_AUDIO_SLOTS; slot++)
      remoteLines.push(`${GOSSIP_PLACEHOLDER_SIZE}\t${REMOTE_FOLDER}/gossip/${slot}.ogg`);
  }

  // On-demand voicing: quests with text but no track yet are listed with a
  // placeholder size. Reading one asks the server to generate it; the real
  // OGG is padded to the placeholder size before the game sees it.
  const demand = remoteDemand && typeof remoteDemand === "object" ? remoteDemand : {};
  if (
    VOICE_LOCALES.includes(demand.locale) &&
    Number.isInteger(demand.size) && demand.size > 0 &&
    Array.isArray(demand.tracks)
  ) {
    for (const track of demand.tracks) {
      const [quest, type] = Array.isArray(track) ? track : [];
      const key = `${demand.locale}|${quest}|${type}`;
      if (!Number.isInteger(quest) || declared.has(key)) continue;
      if (type !== "DETAIL" && type !== "COMPLETE") continue;
      declared.set(key, demand.size);
      placeholders.add(key);
      remoteLines.push(
        `${demand.size}\t${REMOTE_FOLDER}/${demand.locale}/Sounds/q/${quest}${type === "COMPLETE" ? "_t" : ""}.ogg`,
      );
    }
  }
  // Language markers: the addon "plays" lang/<locale>.ogg at login and on
  // /cq lang, which tells the extension its voice language (a 3.3.5 addon has
  // no other way to send data out). Each marker is a 0.2 s silent OGG.
  const SILENT_OGG = decode64("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");
  const announced = new Set();
  // lang/<locale>.ogg: the language the addon runs with (played at login);
  // lang/set/<locale|auto>.ogg: the player just chose it (/cq lang, options).
  for (const locale of VOICE_LOCALES) {
    remoteLines.push(`${SILENT_OGG.length}\t${REMOTE_FOLDER}/lang/${locale}.ogg`);
    remoteLines.push(`${SILENT_OGG.length}\t${REMOTE_FOLDER}/lang/set/${locale}.ogg`);
  }
  remoteLines.push(`${SILENT_OGG.length}\t${REMOTE_FOLDER}/lang/set/auto.ogg`);
  // ui/<ruRU|enUS|auto>.ogg: the player chose the addon's interface language.
  const UI_LOCALES = ["ruRU", "enUS", "auto"];
  for (const ui of UI_LOCALES) remoteLines.push(`${SILENT_OGG.length}\t${REMOTE_FOLDER}/ui/${ui}.ogg`);
  // who/<slot>/<position>/<0-f>.ogg: who plays (realm, name, GUID), half a
  // byte per file (CatQuest's SendBytes: the character, Lua errors). Three
  // slots: the game reads a file once per page load, so each message takes
  // the next one.
  const WHO_SLOTS = 3, WHO_NIBBLES = 144;
  for (let slot = 1; slot <= WHO_SLOTS; slot++)
    for (let pos = 0; pos < WHO_NIBBLES; pos++)
      for (let n = 0; n < 16; n++)
        remoteLines.push(`${SILENT_OGG.length}	${REMOTE_FOLDER}/who/${slot}/${pos}/${n.toString(16)}.ogg`);
  // gossip-msg/<slot>/<position>/<0-f>.ogg: free-form NPC greeting frames.
  // Separate slots keep the character/error marker pool independent.
  for (let slot = 1; slot <= GOSSIP_MARKER_SLOTS; slot++)
    for (let pos = 0; pos < GOSSIP_MARKER_NIBBLES; pos++)
      for (let n = 0; n < 16; n++)
        remoteLines.push(`${SILENT_OGG.length}\t${REMOTE_FOLDER}/gossip-msg/${slot}/${pos}/${n.toString(16)}.ogg`);
  // places/reset.ogg: /cq lore reset, forget the places heard.
  remoteLines.push(`${SILENT_OGG.length}\t${REMOTE_FOLDER}/places/reset.ogg`);
  // poll.ogg: how a track voiced on demand reaches the game. On Lasthavens
  // PlaySoundFile reports success before the file is read, and a read that
  // waits for the server (10-30 s) makes the game drop the sound. So the first
  // read of a quest only starts the job; while anything is being voiced the
  // addon "plays" poll.ogg every few seconds, and the first read after a track
  // is ready gets that track, once. Otherwise poll.ogg is missing.
  const pollSize = Number.isInteger(demand.size) && demand.size > 0 ? demand.size : 0;
  // poll/<n>.ogg: the game caches a played sound by its file name, so every
  // poll uses a new name (the addon counts n up and wraps at POLL_SLOTS).
  const POLL_SLOTS = 2048;
  if (pollSize)
    for (let n = 1; n <= POLL_SLOTS; n++) remoteLines.push(`${pollSize}\t${REMOTE_FOLDER}/poll/${n}.ogg`);
  // Experiment: probe/yes.tga is a real 1x1 TGA, probe/no.tga is listed but
  // answers "missing" (probe/none.tga is not listed at all). /cq probe tex in
  // the addon shows what SetTexture returns for each.
  const PROBE_TGA = new Uint8Array([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 32, 8, 255, 255, 255, 255]);
  remoteLines.push(`${PROBE_TGA.length}\t${REMOTE_FOLDER}/probe/yes.tga`);
  remoteLines.push(`${PROBE_TGA.length}\t${REMOTE_FOLDER}/probe/no.tga`);
  const probeFor = (path) => {
    const m = /CatQuest335_ServerVoices\/probe\/(yes|no)\.tga(?:\/(\d+)-(\d+)-(\d+)k\.bin)?$/i.exec(path);
    return m ? { yes: m[1].toLowerCase() === "yes" } : null;
  };
  const markerCount =
    VOICE_LOCALES.length * 2 + 2 + UI_LOCALES.length + WHO_SLOTS * WHO_NIBBLES * 16 +
    GOSSIP_MARKER_SLOTS * GOSSIP_MARKER_NIBBLES * 16 + (pollSize ? POLL_SLOTS : 0) + 2;

  const waitingDemand = new Map(); // key -> remote, oldest first
  // The answer for each poll file, kept: one play reads the file more than
  // once (whole, again, by blocks) and must always get the same bytes.
  const pollAnswers = new Map(); // n -> { bytes, at }
  // Until when the last handed track plays: the addon does not know it is
  // playing, so the next ready track waits here and they never overlap.
  let pollBusyUntil = 0;
  // Length of an Ogg Vorbis track: last granule position / sample rate.
  const oggSeconds = (bytes) => {
    try {
      if (bytes[0] !== 0x4f || bytes[1] !== 0x67 || bytes[2] !== 0x67 || bytes[3] !== 0x53) return 0;
      const body = 27 + bytes[26];
      if (bytes[body] !== 1) return 0;
      const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      const rate = view.getUint32(body + 12, true);
      for (let at = bytes.length - 27; at >= 0; at--) {
        if (bytes[at] === 0x4f && bytes[at + 1] === 0x67 && bytes[at + 2] === 0x67 && bytes[at + 3] === 0x53) {
          const granule = view.getUint32(at + 6, true) + view.getUint32(at + 10, true) * 2 ** 32;
          return rate > 0 && granule > 0 && granule < 2 ** 52 ? granule / rate : 0;
        }
      }
    } catch {
      // not an OGG: unknown length
    }
    return 0;
  };
  const pollFor = (path) => {
    const m = /CatQuest335_ServerVoices\/poll\/(\d{1,5})\.ogg(?:\/(\d+)-(\d+)-(\d+)k\.bin)?$/i.exec(path);
    if (!m || !pollSize) return null;
    const n = Number(m[1]);
    if (n < 1 || n > POLL_SLOTS) return null;
    return {
      key: "poll",
      n,
      size: pollSize,
      block: m[2] ? { start: Number(m[3]) * Number(m[4]) * 1024, size: Number(m[4]) * 1024 } : null,
    };
  };
  // The first read of a poll file picks the next ready track (each one is
  // handed over once) or answers "missing"; later reads of it repeat that.
  const pollRead = (poll) => {
    const now = Date.now();
    const known = pollAnswers.get(poll.n);
    // A slot comes back after the addon wrapped around: a new poll then.
    if (known && now - known.at < 10 * 60 * 1000) return known.bytes;
    let bytes = null;
    for (const [key, remote] of now < pollBusyUntil ? [] : waitingDemand) {
      if (now - remote.waitingSince > 600000) {
        waitingDemand.delete(key);
        continue;
      }
      const found = audio.get(key) || directRead(remote);
      if (found) {
        waitingDemand.delete(key);
        bytes = found;
        // Unknown length (not an OGG): assume a long line.
        pollBusyUntil = Date.now() + ((oggSeconds(found) || 30) + 1.5) * 1000;
        // The page may read the same play with fetch: tell it which track.
        post({ kind: "poll-pick", n: poll.n, path: remote.path });
        probe({ type: "poll", quest: remote.quest, kind: remote.type, locale: remote.locale, ok: true });
        break;
      }
    }
    pollAnswers.set(poll.n, { bytes, at: Date.now() });
    if (pollAnswers.size > 256) pollAnswers.delete(pollAnswers.keys().next().value);
    return bytes;
  };
  const gossipMarkerFor = (path) => {
    const m = /CatQuest335_ServerVoices\/gossip-msg\/(\d{1,2})\/(\d{1,3})\/([0-9a-f])\.ogg(?:\/(\d+)-(\d+)-(\d+)k\.bin)?$/i.exec(path);
    if (!m) return null;
    const slot = Number(m[1]), pos = Number(m[2]);
    return slot >= 1 && slot <= GOSSIP_MARKER_SLOTS && pos < GOSSIP_MARKER_NIBBLES
      ? { gossipMarker: { slot, pos, value: parseInt(m[3], 16) },
          block: m[4] ? { start: Number(m[5]) * Number(m[6]) * 1024, size: Number(m[6]) * 1024 } : null }
      : null;
  };
  const recordGossipMarker = (slot, pos, value) => {
    if (!gossipNibbles.has(slot)) gossipNibbles.set(slot, []);
    const nibbles = gossipNibbles.get(slot);
    nibbles[pos] = value;
    const byte = (index) =>
      nibbles[2 * index] === undefined || nibbles[2 * index + 1] === undefined
        ? -1
        : nibbles[2 * index] * 16 + nibbles[2 * index + 1];
    const kind = byte(0), length = byte(1);
    if (kind !== 4 || length < 3 || length + 3 > GOSSIP_MARKER_NIBBLES / 2) return;
    const bytes = [];
    for (let i = 0; i < length + 3; i++) {
      const current = byte(i);
      if (current < 0) return;
      bytes.push(current);
    }
    const checksum = bytes.slice(0, -1).reduce((sum, current) => sum + current, 0) % 256;
    if (checksum !== bytes[bytes.length - 1]) return;
    const payload = bytes.slice(2, -1);
    const id = payload[0], index = payload[1], total = payload[2];
    if (id < 1 || id > GOSSIP_AUDIO_SLOTS || total < 1 || total > GOSSIP_MARKER_SLOTS || index < 1 || index > total) return;
    let part = gossipParts.get(id);
    if (!part || part.total !== total) {
      part = { total, chunks: new Map() };
      gossipParts.set(id, part);
    }
    part.chunks.set(index, payload.slice(3));
    if (part.chunks.size !== total) return;
    const joined = [];
    for (let i = 1; i <= total; i++) {
      if (!part.chunks.has(i)) return;
      joined.push(...part.chunks.get(i));
    }
    try {
      const text = new TextDecoder("utf-8", { fatal: true }).decode(new Uint8Array(joined));
      if (text) {
        gossipTexts.set(id, text);
        if (!pageContext && voiceChannel)
          voiceChannel.postMessage({ kind: "gossip-text", id, text });
      }
    } catch {
      // A partial or malformed UTF-8 frame is ignored; the addon retries with
      // a new marker slot on the next click.
    }
    gossipParts.delete(id);
  };
  const markerFor = (path) => {
    const gossipMarker = gossipMarkerFor(path);
    if (gossipMarker) return gossipMarker;
    const who = /CatQuest335_ServerVoices\/who\/(\d)\/(\d{1,3})\/([0-9a-f])\.ogg(?:\/(\d+)-(\d+)-(\d+)k\.bin)?$/i.exec(path);
    if (who) {
      const slot = Number(who[1]), pos = Number(who[2]);
      return slot >= 1 && slot <= WHO_SLOTS && pos < WHO_NIBBLES
        ? { who: { slot, pos, value: parseInt(who[3], 16) },
            block: who[4] ? { start: Number(who[5]) * Number(who[6]) * 1024, size: Number(who[6]) * 1024 } : null }
        : null;
    }
    const ui = /CatQuest335_ServerVoices\/ui\/([a-z]{4})\.ogg(?:\/(\d+)-(\d+)-(\d+)k\.bin)?$/i.exec(path);
    if (ui) {
      const locale = UI_LOCALES.find((l) => l.toLowerCase() === ui[1].toLowerCase());
      return locale
        ? { ui: locale, block: ui[2] ? { start: Number(ui[3]) * Number(ui[4]) * 1024, size: Number(ui[4]) * 1024 } : null }
        : null;
    }
    const reset = /CatQuest335_ServerVoices\/places\/reset\.ogg(?:\/(\d+)-(\d+)-(\d+)k\.bin)?$/i.exec(path);
    if (reset)
      return {
        reset: true,
        block: reset[1] ? { start: Number(reset[2]) * Number(reset[3]) * 1024, size: Number(reset[3]) * 1024 } : null,
      };
    const m = /CatQuest335_ServerVoices\/lang\/(set\/)?([a-z]{4})\.ogg(?:\/(\d+)-(\d+)-(\d+)k\.bin)?$/i.exec(path);
    if (!m) return null;
    const chosen = Boolean(m[1]);
    const locale =
      chosen && m[2].toLowerCase() === "auto"
        ? "auto"
        : VOICE_LOCALES.find((l) => l.toLowerCase() === m[2].toLowerCase());
    return locale
      ? { locale, chosen, block: m[3] ? { start: Number(m[4]) * Number(m[5]) * 1024, size: Number(m[5]) * 1024 } : null }
      : null;
  };
  const entries = paths
    .map((p) => files[p].size + "\t" + p)
    .concat(remoteLines)
    .join("\n");

  // Keep the cached copy exactly as long as the manifest says.
  // A track voiced on demand is listed in the game with a fixed placeholder
  // size, so it must be served at exactly that size. Zeros after the OGG
  // make the game's sound engine refuse it; instead the Vorbis comment header
  // grows by a padding comment, which keeps a valid stream of the same sound.
  // Returns null if the bytes are not a plain Ogg Vorbis stream.
  const OGG_CRC = (() => {
    const table = new Uint32Array(256);
    for (let i = 0; i < 256; i++) {
      let r = i << 24;
      for (let j = 0; j < 8; j++) r = r & 0x80000000 ? (r << 1) ^ 0x04c11db7 : r << 1;
      table[i] = r >>> 0;
    }
    return (bytes) => {
      let crc = 0;
      for (let i = 0; i < bytes.length; i++) crc = ((crc << 8) ^ table[((crc >>> 24) ^ bytes[i]) & 0xff]) >>> 0;
      return crc >>> 0;
    };
  })();
  const oggPages = (bytes) => {
    const pages = [];
    let at = 0;
    while (at < bytes.length) {
      if (at + 27 > bytes.length || bytes[at] !== 0x4f || bytes[at + 1] !== 0x67 || bytes[at + 2] !== 0x67 || bytes[at + 3] !== 0x53)
        return null;
      const segments = bytes[at + 26];
      if (at + 27 + segments > bytes.length) return null;
      const lacing = bytes.subarray(at + 27, at + 27 + segments);
      let bodySize = 0;
      for (const v of lacing) bodySize += v;
      const end = at + 27 + segments + bodySize;
      if (end > bytes.length) return null;
      pages.push({ header: bytes.subarray(at, at + 27), lacing, body: bytes.subarray(at + 27 + segments, end) });
      at = end;
    }
    return pages;
  };
  const oggPage = (template, flags, seq, lacing, body) => {
    const out = new Uint8Array(27 + lacing.length + body.length);
    out.set(template.subarray(0, 27));
    out[5] = flags;
    out.fill(0, 6, 14); // granule position 0 for header pages
    new DataView(out.buffer).setUint32(18, seq, true);
    out.fill(0, 22, 26);
    out[26] = lacing.length;
    out.set(lacing, 27);
    out.set(body, 27 + lacing.length);
    new DataView(out.buffer).setUint32(22, OGG_CRC(out), true);
    return out;
  };
  const oggPad = (bytes, size) => {
    const pages = oggPages(bytes);
    if (!pages || pages.length < 3) return null;
    const serial = new DataView(pages[0].header.buffer, pages[0].header.byteOffset).getUint32(14, true);
    // Header packets 1-3 (identification, comment, setup) and the pages they use.
    const packets = [];
    let current = [];
    let headerPages = 0;
    for (const page of pages) {
      if (new DataView(page.header.buffer, page.header.byteOffset).getUint32(14, true) !== serial) return null;
      headerPages++;
      let at = 0;
      for (const v of page.lacing) {
        current.push(page.body.subarray(at, at + v));
        at += v;
        if (v < 255) {
          const length = current.reduce((n, c) => n + c.length, 0);
          const packet = new Uint8Array(length);
          let o = 0;
          for (const c of current) { packet.set(c, o); o += c.length; }
          packets.push(packet);
          current = [];
        }
      }
      if (packets.length >= 3) break;
    }
    // Audio must start on a fresh page after the setup header.
    if (packets.length !== 3 || current.length || headerPages < 2) return null;
    const [ident, comment, setup] = packets;
    const isHeader = (p, type) =>
      p[0] === type && String.fromCharCode(...p.subarray(1, 7)) === "vorbis";
    if (!isHeader(ident, 1) || !isHeader(comment, 3) || !isHeader(setup, 5)) return null;
    if (comment[comment.length - 1] !== 1) return null;
    const view = new DataView(comment.buffer, comment.byteOffset, comment.byteLength);
    const vendorLength = view.getUint32(7, true);
    const countAt = 11 + vendorLength;
    if (countAt + 4 > comment.length - 1) return null;
    const count = view.getUint32(countAt, true);
    const audio = pages.slice(headerPages);
    const audioBytes = audio.reduce((n, p) => n + 27 + p.lacing.length + p.body.length, 0);
    const identPage = pages[0];
    if (identPage.lacing.length !== 1) return null;
    const identBytes = 27 + 1 + identPage.body.length;
    const template = pages[1].header;

    const build = (padding) => {
      const extra = new TextEncoder().encode("PADDING=" + " ".repeat(padding));
      const grown = new Uint8Array(comment.length + 4 + extra.length);
      grown.set(comment.subarray(0, comment.length - 1));
      new DataView(grown.buffer).setUint32(countAt, count + 1, true);
      new DataView(grown.buffer).setUint32(comment.length - 1, extra.length, true);
      grown.set(extra, comment.length + 3);
      grown[grown.length - 1] = 1;
      return grown;
    };
    // Lace comment + setup into pages of at most 255 segments.
    const paginate = (packetsToLace) => {
      const segments = [];
      for (const p of packetsToLace) {
        let left = p.length, at = 0;
        while (left >= 255) { segments.push(p.subarray(at, at + 255)); at += 255; left -= 255; }
        segments.push(p.subarray(at, at + left));
      }
      const out = [];
      for (let i = 0; i < segments.length; i += 255) {
        const chunk = segments.slice(i, i + 255);
        out.push({
          continued: i > 0 && segments[i - 1].length === 255,
          lacing: Uint8Array.from(chunk.map((c) => c.length)),
          body: chunk,
        });
      }
      return out;
    };
    const sizeOf = (padding) => {
      const commentLength = comment.length + 4 + 8 + padding;
      const segments = Math.floor(commentLength / 255) + 1 + Math.floor(setup.length / 255) + 1;
      return identBytes + 27 * Math.ceil(segments / 255) + segments + commentLength + setup.length + audioBytes;
    };
    if (sizeOf(0) > size) return null;
    // sizeOf grows by 1 per padding byte, plus a lacing byte every 255 and a
    // page header every 255 lacing bytes: search down from an upper bound.
    let padding = size - sizeOf(0);
    while (padding > 0 && sizeOf(padding) > size) padding--;
    let fill = null;
    for (let p = padding; p >= Math.max(0, padding - 70000); p--)
      if (sizeOf(p) === size) { fill = p; break; }
    if (fill === null) return null;

    const pagesOut = [bytes.subarray(0, identBytes)];
    let seq = 1;
    for (const page of paginate([build(fill), setup])) {
      const body = new Uint8Array(page.body.reduce((n, c) => n + c.length, 0));
      let o = 0;
      for (const c of page.body) { body.set(c, o); o += c.length; }
      pagesOut.push(oggPage(template, page.continued ? 1 : 0, seq++, page.lacing, body));
    }
    for (const page of audio) {
      const raw = new Uint8Array(27 + page.lacing.length + page.body.length);
      raw.set(page.header);
      raw.set(page.lacing, 27);
      raw.set(page.body, 27 + page.lacing.length);
      new DataView(raw.buffer).setUint32(18, seq++, true);
      raw.fill(0, 22, 26);
      new DataView(raw.buffer).setUint32(22, OGG_CRC(raw), true);
      pagesOut.push(raw);
    }
    const out = new Uint8Array(size);
    let o = 0;
    for (const p of pagesOut) { out.set(p, o); o += p.length; }
    return o === size ? out : null;
  };

  function store(remote, bytes) {
    let out = bytes;
    if (remote.size && bytes.length !== remote.size) {
      // A placeholder is meant to be larger than the real track: no warning.
      if (!remote.placeholder || bytes.length > remote.size) probe({
        type: "size-mismatch",
        quest: remote.quest,
        kind: remote.type,
        locale: remote.locale,
        bytes: bytes.length,
        status: remote.size,
      });
      out = (remote.placeholder && bytes.length < remote.size && oggPad(bytes, remote.size)) || null;
      if (!out) {
        out = new Uint8Array(remote.size);
        out.set(bytes.subarray(0, remote.size));
      }
    }
    audio.set(remote.key, out);
    while (audio.size > AUDIO_CACHE_LIMIT)
      audio.delete(audio.keys().next().value);
    return out;
  }

  // Worker-only synchronous read straight from the voice API. Tracks in the
  // manifest are ready on the server, so wait=0 answers at once.
  const directRead = (remote) => {
    if (pageContext || directState === "blocked" || !remote.size) return null;
    // A track being generated answers 202. The game's worker never gets the
    // bridge's answer (its event loop does not run while the game does), so
    // this read is the only way a generated track reaches it: ask again every
    // 10 s for a quest voiced on demand, every 2 min for anything else.
    const gap = remote.placeholder ? 10000 : 120000;
    if (Date.now() - (directMissAt.get(remote.key) || 0) < gap) return null;
    const started = Date.now();
    // Never wait here: a read that takes 10-30 s makes the game drop the
    // sound. A quest voiced on demand reaches the game through poll.ogg.
    const wait = 0;
    try {
      const x = new Native();
      x.open("GET", remote.url.replace(/wait=\d+/, "wait=" + wait), false);
      x.responseType = "arraybuffer";
      x.send();
      const ok =
        x.status === 200 && isAudio(x.getResponseHeader("Content-Type"));
      probe({
        type: "direct",
        quest: remote.quest,
        kind: remote.type,
        locale: remote.locale,
        status: x.status,
        bytes: ok ? x.response.byteLength : 0,
        ms: Date.now() - started,
        ok,
      });
      if (!ok) {
        directMissAt.set(remote.key, Date.now());
        if (remote.placeholder && !waitingDemand.has(remote.key)) {
          remote.waitingSince = Date.now();
          waitingDemand.set(remote.key, remote);
        }
        if (remote.placeholder && !wait)
          probe({ type: "demand", quest: remote.quest, kind: remote.type, locale: remote.locale, status: x.status });
        return null;
      }
      directState = "ok";
      waitingDemand.delete(remote.key);
      return store(remote, new Uint8Array(x.response));
    } catch (error) {
      // A long wait can fail on its own (network); only a first failure means
      // the page does not allow direct reads at all.
      if (directState !== "ok") directState = "blocked";
      directMissAt.set(remote.key, Date.now());
      probe({ type: "direct", ok: false, error: String(error), ms: Date.now() - started });
      return null;
    }
  };

  if (typeof NativeFetch === "function") {
    globalThis.fetch = function (input, init) {
      const isRequest = typeof Request !== "undefined" && input instanceof Request;
      let remote = null,
        pathname = "";
      try {
        pathname = new URL(isRequest ? input.url : String(input), base).pathname;
        remote = remoteFor(pathname);
      } catch {
        remote = null;
      }
      // The page reads blocks of big addon files with fetch (files over
      // 64 KB: /blocks/<file>/<size>-<index>-64k.bin). Serve them from the
      // local copy exactly like the XHR path, never from the game server.
      let decoded = pathname;
      try {
        decoded = decodeURIComponent(pathname);
      } catch {
        // keep the raw path
      }
      const local = paths.find(
        (p) => decoded === "/game/" + p || decoded.startsWith("/blocks/" + p + "/"),
      );
      if (local) {
        const range =
          new Headers(init?.headers || (isRequest ? input.headers : undefined)).get("Range") || "";
        return NativeFetch.call(globalThis, files[local].url)
          .then((r) => r.arrayBuffer())
          .then((buffer) => {
            const bytes = new Uint8Array(buffer);
            let start = 0,
              end = bytes.length;
            const block = decoded.match(/\/(\d+)-(\d+)-(\d+)k\.bin$/);
            if (block) {
              start = Number(block[2]) * Number(block[3]) * 1024;
              end = Math.min(bytes.length, start + Number(block[3]) * 1024);
            }
            const m = range && /bytes=(\d+)-(\d*)/.exec(range);
            if (m) {
              start = Number(m[1]);
              end = m[2] ? Math.min(bytes.length, Number(m[2]) + 1) : bytes.length;
            }
            return new Response(bytes.slice(start, end), { status: m ? 206 : 200 });
          });
      }
      if (
        /^\/blocks\/Interface\/AddOns\/[^/]+\/bundle-/.test(decoded) &&
        paths.some((p) => decoded.startsWith("/blocks/" + p.split("/").slice(0, 3).join("/") + "/"))
      )
        return Promise.resolve(new Response(null, { status: 404, statusText: "Not Found" }));
      const poll = !remote && pollFor(decoded);
      if (poll) {
        // Only the play the worker just answered; later polls are new plays.
        const picked = pagePolls.get(poll.n) || null;
        if (!picked) return Promise.resolve(new Response(null, { status: 404, statusText: "Not Found" }));
        const range =
          new Headers(init?.headers || (isRequest ? input.headers : undefined)).get("Range") || "";
        return fetchAudio(picked).then((bytes) => {
          if (!bytes) return new Response(null, { status: 404, statusText: "Not Found" });
          const part = slice(bytes, poll, range);
          const headers = { "Content-Type": "audio/ogg" };
          if (part.range) headers["Content-Range"] = part.range;
          return new Response(part.bytes, { status: part.status, headers });
        });
      }
      if (!remote) {
        noteUnmatched("fetch", pathname);
        return NativeFetch.call(globalThis, input, init);
      }
      noteRead("fetch", remote, false);
      const range =
        new Headers(init?.headers || (isRequest ? input.headers : undefined)).get(
          "Range",
        ) || "";
      return fetchAudio(remote).then((bytes) => {
        if (!bytes) return new Response(null, { status: 404, statusText: "Not Found" });
        const part = slice(bytes, remote, range);
        const headers = { "Content-Type": "audio/ogg" };
        if (part.range) headers["Content-Range"] = part.range;
        return new Response(part.bytes, { status: part.status, headers });
      });
    };
  }

  const finishAsync = (xhr) => {
    for (const type of ["readystatechange", "load", "loadend"])
      xhr.dispatchEvent(new Event(type));
  };

  globalThis.XMLHttpRequest = class extends Native {
    // A bug here must not go unnoticed: it is reported (runtime-error) and
    // thrown on as before.
    open(method, url, ...args) {
      try {
        return this.openInner(method, url, ...args);
      } catch (error) {
        runtimeError("open", error, url);
        throw error;
      }
    }
    send(body) {
      try {
        return this.sendInner(body);
      } catch (error) {
        runtimeError("send", error, this.path);
        throw error;
      }
    }
    openInner(method, url, ...args) {
      this.answer = null;
      this.range = "";
      this.p = new URL(String(url), base);
      this.method = String(method).toUpperCase();
      this.isAsync = args.length === 0 || args[0] !== false;
      this.path = decodeURIComponent(this.p.pathname);
      this.local = paths.find(
        (p) =>
          this.path === "/game/" + p ||
          this.path.startsWith("/blocks/" + p + "/"),
      );
      this.bundle =
        /^\/blocks\/Interface\/AddOns\/[^/]+\/bundle-/.test(this.path) &&
        (paths.some((p) =>
          this.path.startsWith(
            "/blocks/" + p.split("/").slice(0, 3).join("/") + "/",
          ),
        ) ||
          (remoteLines.length > 0 &&
            this.path.startsWith("/blocks/" + REMOTE_FOLDER + "/")));
      this.remote = this.local ? null : remoteFor(this.path);
      this.marker = this.local || this.remote ? null : markerFor(this.path);
      this.poll = this.local || this.remote || this.marker ? null : pollFor(this.path);
      this.probeTex = this.local || this.remote || this.marker || this.poll ? null : probeFor(this.path);
      if (!this.local && !this.remote && !this.marker && !this.poll && !this.probeTex) noteUnmatched("xhr", this.path);
      return super.open(
        method,
        this.local ? files[this.local].url : this.p.href,
        ...args,
      );
    }
    setRequestHeader(k, v) {
      if ((this.local || this.remote || this.poll) && k.toLowerCase() === "range") {
        this.range = v;
        return;
      }
      return super.setRequestHeader(k, v);
    }
    answerWith(bytes) {
      if (!bytes) {
        this.answer = { status: 404, text: "" };
        return;
      }
      const part = slice(bytes, this.remote, this.range);
      this.answer = {
        status: part.status,
        bytes: part.bytes,
        type: this.responseType,
        range: part.range,
      };
    }
    sendInner(body) {
      if (this.bundle && this.method === "GET") {
        this.answer = { status: 404, text: "" };
        return;
      }
      if (this.probeTex && this.method === "GET") {
        probe({ type: "texture-probe", status: this.probeTex.yes ? 200 : 404, sync: !this.isAsync, path: this.path });
        this.answer = this.probeTex.yes
          ? { status: 200, bytes: PROBE_TGA, type: this.responseType }
          : { status: 404, text: "" };
        if (this.isAsync) setTimeout(() => finishAsync(this), 0);
        return;
      }
      if (this.poll && this.method === "GET") {
        const bytes = pollRead(this.poll);
        const part = bytes && slice(bytes, this.poll, this.range);
        this.answer = part
          ? { status: part.status, bytes: part.bytes, type: this.responseType, range: part.range }
          : { status: 404, text: "" };
        if (this.isAsync) setTimeout(() => finishAsync(this), 0);
        return;
      }
      if (this.marker && this.method === "GET") {
        const { locale, chosen, block, reset, ui, who, gossipMarker } = this.marker;
        const key = (chosen ? "set/" : "") + locale;
        if (gossipMarker) {
          recordGossipMarker(gossipMarker.slot, gossipMarker.pos, gossipMarker.value);
        } else if (who) {
          post({ kind: "who", slot: who.slot, pos: who.pos, value: who.value });
        } else if (ui) {
          if (!block || block.start === 0) post({ kind: "ui-locale", locale: ui });
        } else if (reset) {
          if (!block || block.start === 0) {
            heardPosted.clear();
            post({ kind: "places-reset" });
          }
        // A choice is reported every time: the player may switch back and forth.
        } else if ((chosen && (!block || block.start === 0)) || !announced.has(key)) {
          announced.add(key);
          post({ kind: "voice-locale", locale, choice: chosen });
          probe({ type: "voice-locale", locale, choice: chosen });
        }
        const start = block ? Math.min(block.start, SILENT_OGG.length) : 0;
        const end = block ? Math.min(SILENT_OGG.length, start + block.size) : SILENT_OGG.length;
        this.answer = { status: 200, bytes: SILENT_OGG.slice(start, end), type: this.responseType };
        if (this.isAsync) setTimeout(() => finishAsync(this), 0);
        return;
      }
      if (this.local && this.method === "GET") {
        const type = this.responseType;
        this.responseType = "arraybuffer";
        super.send();
        let bytes = new Uint8Array(super.response);
        let start = 0,
          end = bytes.length;
        const block = this.path.match(/\/(\d+)-(\d+)-(\d+)k\.bin$/);
        if (block) {
          start = Number(block[2]) * Number(block[3]) * 1024;
          end = start + Number(block[3]) * 1024;
        }
        if (this.range) {
          const m = this.range.match(/bytes=(\d+)-(\d+)/);
          if (m) {
            start = +m[1];
            end = +m[2] + 1;
          }
        }
        bytes = bytes.slice(start, end);
        this.answer = { status: this.range ? 206 : 200, bytes, type };
        return;
      }
      if (this.remote && this.method === "GET") {
        noteRead("xhr", this.remote, !this.isAsync);
        const cached = audio.get(this.remote.key);
        if (!this.isAsync) {
          // A synchronous read cannot wait for the bridge: read directly if
          // allowed, otherwise miss now and fetch in the background. A worker
          // never sees the background answer, so it only reads directly.
          const bytes = cached || directRead(this.remote);
          if (!bytes && (pageContext || directState === "blocked" || !this.remote.size)) fetchAudio(this.remote);
          this.answerWith(bytes || null);
          return;
        }
        fetchAudio(this.remote).then((bytes) => {
          this.answerWith(bytes);
          finishAsync(this);
        });
        return;
      }
      const r = super.send(body);
      // The addon's saved settings tell which voice language to prepare next time.
      if (/\/SavedVariables\/CatQuest\.lua$/i.test(this.path)) {
        const read = () => {
          const text = super.status === 200 ? super.responseText || "" : "";
          const m = /\["language"\]\s*=\s*"([A-Za-z]{2,5})"/.exec(text);
          if (m) post({ kind: "voice-locale", locale: m[1] });
          const settings = parseSavedAddonSettings(text);
          if (settings) post({ kind: "addon-settings", settings });
        };
        if (super.readyState === 4) read();
        else this.addEventListener("load", read);
      }
      if (this.path === "/game-manifest.txt" && super.status === 200 && entries)
        this.answer = {
          status: 200,
          text: super.responseText.trimEnd() + "\n" + entries + "\n",
        };
      return r;
    }
    getResponseHeader(name) {
      if (!this.answer || !(this.remote || this.marker || this.poll || this.probeTex)) return super.getResponseHeader(name);
      const key = String(name).toLowerCase();
      if (key === "content-type") return this.answer.bytes ? "audio/ogg" : null;
      if (key === "content-length")
        return this.answer.bytes ? String(this.answer.bytes.length) : "0";
      if (key === "content-range") return this.answer.range || null;
      return null;
    }
    get status() {
      return this.answer?.status ?? super.status;
    }
    get readyState() {
      return this.answer ? 4 : super.readyState;
    }
    get responseText() {
      return this.answer
        ? (this.answer.text ?? new TextDecoder().decode(this.answer.bytes))
        : super.responseText;
    }
    get response() {
      if (!this.answer) return super.response;
      if (!this.answer.bytes) return this.answer.text;
      if (this.answer.type === "arraybuffer") return this.answer.bytes.buffer;
      if (this.answer.type === "blob") return new Blob([this.answer.bytes]);
      return new TextDecoder().decode(this.answer.bytes);
    }
  };

  // Phase 0: which browser audio APIs fire right after a CatQuest read.
  const watchAudioApi = (name, proto, method) => {
    const original = proto?.[method];
    if (typeof original !== "function") return;
    proto[method] = function (...args) {
      if (Date.now() - lastCatQuestAt < 5000)
        probe({
          type: "audio-api",
          api: name,
          bytes: args[0]?.byteLength ?? 0,
        });
      return original.apply(this, args);
    };
  };
  if (typeof BaseAudioContext !== "undefined")
    watchAudioApi("decodeAudioData", BaseAudioContext.prototype, "decodeAudioData");
  if (typeof AudioBufferSourceNode !== "undefined")
    watchAudioApi("AudioBufferSourceNode.start", AudioBufferSourceNode.prototype, "start");
  if (typeof HTMLMediaElement !== "undefined")
    watchAudioApi("HTMLMediaElement.play", HTMLMediaElement.prototype, "play");

  probe({
    type: "install",
    files: paths.length,
    bytes: remoteLines.length - placeholders.size - markerCount - bookCount, // ready quest tracks
    api: bookCount ? `${bookCount} book tracks` : "",
    status: placeholders.size,
    locale: placeholders.size ? demand.locale : "",
  });
  setTimeout(
    () =>
      probe({
        type: "env",
        globals: [
          "FS",
          "IDBFS",
          "Module",
          "wasmImports",
          "WebVfsStoreIo",
          "HEAPU8",
          "SharedArrayBuffer",
        ]
          .filter((n) => typeof globalThis[n] !== "undefined")
          .join(","),
        isolated: !!globalThis.crossOriginIsolated,
      }),
    20000,
  );
};
