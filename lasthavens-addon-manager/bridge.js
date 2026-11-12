(() => {
  if (location.pathname !== "/play" && location.pathname !== "/play/") return;

  // Status panel over the game for tracks being voiced on demand. The 3.3.5
  // addon cannot receive data, so the extension shows queue, progress and
  // what the server can still voice. Server values only reach textContent.
  const Panel = (() => {
    const TEXTS = {
      ru: {
        title: "CatQuest · озвучка по запросу",
        close: "Закрыть",
        turnin: "(сдача) ",
        queued: (d) => `в очереди: ${d.position}-я, ~${d.eta} с`,
        running: (d) => `озвучивается: ${d.elapsed} с из ~${d.total} с`,
        ready: "готово, играет",
        fetching: "готово, загружаю звук",
        failed: (e) => `не удалось: ${e}`,
        limited: (min) => `лимит часа исчерпан, новая через ${min} мин`,
        budget: "бюджет озвучки исчерпан, новые квесты пока не озвучиваются — напишите об этом в https://t.me/warcraft_rus_chat",
        missing: "нет текста квеста для этого языка",
        waiting: "запрос отправлен",
        drag: "Перетащите, чтобы сдвинуть; двойной клик — вернуть наверх",
        addonUpdated: (v) => `CatQuest обновлён до ${v} — перезагрузите страницу (F5)`,
        extensionUpdate: (v) => `доступна новая версия расширения ${v} — откройте менеджер аддонов`,
        identityNotice: (name) =>
          `CatQuest сообщает серверу персонажа (${name}, реалм), заказанные квесты и ошибки — отключить можно внизу менеджера аддонов`,
        footer: (c) =>
          `в очереди ${c.queued + c.running} · за час ${c.used_last_hour}/${c.per_hour}` +
          (c.budget_tracks != null ? ` · бюджета ≈ на ${c.budget_tracks} дор.` : ""),
      },
      zh: {
        title: "CatQuest · 按需配音",
        close: "关闭",
        turnin: "（交任务）",
        queued: (d) => `排队中：第 ${d.position} 位，约 ${d.eta} 秒`,
        running: (d) => `正在配音：${d.elapsed} / 约 ${d.total} 秒`,
        ready: "已完成，正在播放",
        fetching: "已完成，正在加载音频",
        failed: (e) => `失败：${e}`,
        limited: (min) => `本小时额度已用完，${min} 分钟后可用`,
        budget: "配音预算已用完，暂时无法生成新配音。请在 https://t.me/warcraft_rus_chat 告知我们",
        missing: "该语言没有任务文本",
        waiting: "已发送请求",
        drag: "拖动可移动；双击回到顶部",
        addonUpdated: (v) => `CatQuest 已更新到 ${v}，请刷新页面（F5）`,
        extensionUpdate: (v) => `扩展有新版本 ${v}，请打开插件管理器`,
        identityNotice: (name) => `CatQuest 会向服务器报告角色（${name}、服务器）、请求配音的任务和错误，可在插件管理器底部关闭`,
        footer: (c) =>
          `队列 ${c.queued + c.running} · 本小时 ${c.used_last_hour}/${c.per_hour}` +
          (c.budget_tracks != null ? ` · 预算约 ${c.budget_tracks} 条` : ""),
      },
      en: {
        title: "CatQuest · voice on demand",
        close: "Close",
        turnin: "(turn-in) ",
        queued: (d) => `queued: #${d.position}, ~${d.eta} s`,
        running: (d) => `voicing: ${d.elapsed} s of ~${d.total} s`,
        ready: "ready, playing",
        fetching: "ready, loading audio",
        failed: (e) => `failed: ${e}`,
        limited: (min) => `hourly limit reached, next in ${min} min`,
        budget: "voicing budget is used up: new quests are not voiced for now. Please tell us at https://t.me/warcraft_rus_chat",
        missing: "no quest text for this language",
        waiting: "request sent",
        drag: "Drag to move; double-click to put it back on top",
        addonUpdated: (v) => `CatQuest updated to ${v}: reload the page (F5)`,
        extensionUpdate: (v) => `extension ${v} is available: open the addon manager`,
        identityNotice: (name) =>
          `CatQuest tells the server your character (${name}, realm), ordered quests and errors; turn it off at the bottom of the addon manager`,
        footer: (c) =>
          `queue ${c.queued + c.running} · this hour ${c.used_last_hour}/${c.per_hour}` +
          (c.budget_tracks != null ? ` · budget ≈ ${c.budget_tracks} tracks` : ""),
      },
    };
    // Until the extension knows the addon's languages: the browser's.
    const browser = (navigator.language || "en").slice(0, 2);
    let T = TEXTS[browser === "ru" || browser === "uk" ? "ru" : browser === "zh" ? "zh" : "en"];
    let titleText;

    const items = new Map();
    // One-line notices (updates) shown for a while above the queue.
    const notices = new Map();
    let root, list, footer, capacity, timer;
    // Where the player dragged the panel: {left, top} in px, or null (centre).
    let position = null;
    chrome.storage.local.get("panelPosition").then(({ panelPosition }) => {
      if (Number.isFinite(panelPosition?.left) && Number.isFinite(panelPosition?.top)) {
        position = panelPosition;
        place();
      }
    }).catch(() => {});

    const place = () => {
      if (!root) return;
      if (!position) {
        Object.assign(root.style, { top: "8px", left: "50%", transform: "translateX(-50%)" });
        return;
      }
      // Keep the panel on screen after the window was resized.
      const width = root.offsetWidth || 300, height = root.offsetHeight || 60;
      const left = Math.min(Math.max(0, position.left), Math.max(0, innerWidth - width));
      const top = Math.min(Math.max(0, position.top), Math.max(0, innerHeight - height));
      Object.assign(root.style, { top: top + "px", left: left + "px", transform: "none" });
    };

    // Drag by the title; the rest of the panel lets clicks through to the game.
    const makeDraggable = (handle) => {
      handle.addEventListener("pointerdown", (event) => {
        if (event.button !== 0) return;
        event.preventDefault();
        event.stopPropagation();
        const box = root.getBoundingClientRect();
        const dx = event.clientX - box.left, dy = event.clientY - box.top;
        handle.setPointerCapture(event.pointerId);
        const move = (e) => {
          e.preventDefault();
          e.stopPropagation();
          position = { left: Math.round(e.clientX - dx), top: Math.round(e.clientY - dy) };
          place();
        };
        const up = (e) => {
          e.stopPropagation();
          handle.removeEventListener("pointermove", move);
          handle.removeEventListener("pointerup", up);
          handle.removeEventListener("pointercancel", up);
          if (position) chrome.storage.local.set({ panelPosition: position }).catch(() => {});
        };
        handle.addEventListener("pointermove", move);
        handle.addEventListener("pointerup", up);
        handle.addEventListener("pointercancel", up);
      });
      // Double click: back to the top centre.
      handle.addEventListener("dblclick", (event) => {
        event.stopPropagation();
        position = null;
        place();
        chrome.storage.local.remove("panelPosition").catch(() => {});
      });
      for (const type of ["mousedown", "mouseup", "click", "contextmenu"])
        handle.addEventListener(type, (e) => e.stopPropagation());
    };
    addEventListener("resize", () => place());

    const ensureRoot = () => {
      if (root) return;
      root = document.createElement("div");
      root.setAttribute("role", "status");
      Object.assign(root.style, {
        position: "fixed", top: "8px", left: "50%", transform: "translateX(-50%)",
        zIndex: "2147483647", maxWidth: "440px", minWidth: "260px", padding: "8px 12px",
        background: "rgba(10, 8, 4, 0.86)", border: "1px solid #6b5420", borderRadius: "6px",
        color: "#f1e6c8", font: "12px/1.45 system-ui, sans-serif", pointerEvents: "none",
        boxShadow: "0 2px 10px rgba(0,0,0,0.5)",
      });
      const head = document.createElement("div");
      Object.assign(head.style, { display: "flex", alignItems: "center", gap: "8px", marginBottom: "4px" });
      const title = document.createElement("div");
      titleText = title;
      title.textContent = T.title;
      Object.assign(title.style, {
        flex: "1", color: "#ffd100", fontWeight: "600",
        pointerEvents: "auto", cursor: "move", userSelect: "none", touchAction: "none",
      });
      title.title = T.drag;
      makeDraggable(title);
      // Close: hide what is shown now; a new request opens the panel again.
      const close = document.createElement("button");
      close.type = "button";
      close.textContent = "×";
      close.title = T.close;
      close.setAttribute("aria-label", T.close);
      Object.assign(close.style, {
        pointerEvents: "auto", cursor: "pointer", background: "none", border: "none", padding: "0 2px",
        color: "#b9ab88", font: "16px/1 system-ui, sans-serif",
      });
      for (const type of ["pointerdown", "mousedown", "mouseup", "contextmenu"])
        close.addEventListener(type, (e) => e.stopPropagation());
      close.addEventListener("click", (event) => {
        event.stopPropagation();
        items.clear();
        notices.clear();
        clearInterval(timer);
        timer = null;
        render();
      });
      head.append(title, close);
      list = document.createElement("div");
      footer = document.createElement("div");
      Object.assign(footer.style, { marginTop: "4px", color: "#b9ab88", fontSize: "11px" });
      root.append(head, list, footer);
      (document.body || document.documentElement).append(root);
      place();
    };

    const render = () => {
      if (!items.size && !notices.size) {
        if (root) root.style.display = "none";
        return;
      }
      ensureRoot();
      root.style.display = "block";
      place();
      list.replaceChildren();
      for (const text of notices.values()) {
        const row = document.createElement("div");
        row.textContent = text;
        row.style.color = "#ffd100";
        list.append(row);
      }
      for (const item of items.values()) {
        const row = document.createElement("div");
        const name = item.title || `#${item.quest}`;
        row.textContent = `«${name}» ${item.kind === "COMPLETE" ? T.turnin : ""}· ${item.locale} — ${item.text}`;
        row.style.color = item.state === "failed" ? "#ff8f7a" : item.state === "ready" ? "#9be36d" : "#f1e6c8";
        list.append(row);
      }
      footer.textContent = capacity ? T.footer(capacity) : "";
    };

    const describe = (item, status) => {
      if (!status) return;
      item.title = status.title || item.title;
      if (status.status === "queued") {
        item.state = "queued";
        item.text = T.queued({ position: status.position || 1, eta: status.eta_seconds || "?" });
      } else if (status.status === "running") {
        item.state = "running";
        const elapsed = Math.round(status.elapsed || 0);
        item.text = T.running({ elapsed, total: elapsed + (status.eta_seconds || 0) });
      } else if (status.status === "ready") {
        if (item.state !== "ready" && item.state !== "fetching") {
          item.state = "fetching";
          item.text = T.fetching;
          item.fetchingAt = Date.now();
        }
      } else if (status.status === "failed") {
        item.state = "failed";
        item.text = T.failed(String(status.error || "").slice(0, 80));
        item.doneAt = Date.now();
      } else if (status.status === "limited" && status.reason === "budget") {
        item.state = "failed";
        item.text = T.budget;
        item.doneAt = Date.now();
      } else if (status.status === "limited") {
        item.state = "limited";
        item.text = T.limited(Math.max(1, Math.ceil((status.next_slot_seconds || 60) / 60)));
      } else if (status.status === "missing" && Date.now() - item.since < 20000) {
        // "missing" = no job yet: the panel can ask before the game's read
        // reaches the server and starts the job. Keep asking for a while.
        item.state = "waiting";
        item.text = T.waiting;
      } else if (status.status === "missing") {
        item.state = "failed";
        item.text = T.missing;
        item.doneAt = Date.now();
      }
    };

    const poll = async () => {
      const now = Date.now();
      for (const [key, item] of items) {
        // Finished rows stay a few seconds so the player can read them.
        if (item.doneAt && now - item.doneAt > (item.state === "ready" ? 6000 : 15000)) {
          items.delete(key);
          continue;
        }
        // Voiced on the server, but the game did not confirm the read: do not
        // keep "loading audio" for ever.
        if (item.state === "fetching" && now - item.fetchingAt > 30000) {
          items.delete(key);
          continue;
        }
        // Give up showing a track after 10 minutes.
        if (now - item.since > 600000) {
          items.delete(key);
          continue;
        }
        if (item.state === "ready" || item.state === "failed" || item.state === "fetching") continue;
        const status = await chrome.runtime
          .sendMessage({ kind: "voice-status", quest: item.quest, type: item.kind, locale: item.locale })
          .catch(() => null);
        describe(item, status);
      }
      capacity = await chrome.runtime.sendMessage({ kind: "voice-capacity" }).catch(() => null) || capacity;
      render();
      if (!items.size) {
        clearInterval(timer);
        timer = null;
      }
    };

    const start = () => {
      if (!timer) timer = setInterval(poll, 2000);
      poll();
    };

    return {
      // "ru" | "en" | "zh"; texts already shown switch on the next render.
      setLanguage(lang) {
        if (!TEXTS[lang] || TEXTS[lang] === T) return;
        T = TEXTS[lang];
        if (titleText) {
          titleText.textContent = T.title;
          titleText.title = T.drag;
          const close = titleText.nextSibling;
          if (close) {
            close.title = T.close;
            close.setAttribute("aria-label", T.close);
          }
        }
        render();
      },
      notice(key, kind, version, ms = 20000) {
        notices.set(key, T[kind](String(version).slice(0, 20)));
        render();
        setTimeout(() => {
          notices.delete(key);
          render();
        }, ms);
      },
      onProbe(event) {
        // Gossip has no quest ID and its text is shown in the game's own
        // CatQuest window; the browser panel is reserved for quest tracks.
        if (!event || !Number.isInteger(event.quest) || event.quest <= 0 || event.kind === "GOSSIP") return;
        const key = `${event.locale}|${event.quest}|${event.kind}`;
        // A placeholder fetch or a direct read that started generation.
        if ((event.type === "fetch-start" && event.ok) || event.type === "demand") {
          if (!items.has(key)) {
            items.set(key, {
              quest: event.quest, kind: event.kind, locale: event.locale,
              state: "waiting", text: T.waiting, since: Date.now(),
            });
            start();
          }
        } else if ((event.type === "fetch-done" || event.type === "direct" || event.type === "poll") && items.has(key)) {
          const item = items.get(key);
          if (event.ok) {
            item.state = "ready";
            item.text = T.ready;
            item.doneAt = Date.now();
          }
          render();
        }
      },
    };
  })();
  const CHANNEL = "lh-local-addons-v1",
    DEFAULT_VOICE_API = "https://quester.mvse.ws",
    VOICE_CHANNEL_NAME = "lh-catquest-voice-v1",
    VOICE_CHANNEL = new BroadcastChannel(VOICE_CHANNEL_NAME);
  let payload;

  // Probe events come from the untrusted page: keep only known short fields.
  const PROBE_FIELDS = [
    "type", "via", "ctx", "sync", "quest", "kind", "locale", "cached", "path", "status",
    "bytes", "ms", "ok", "api", "globals", "isolated", "files", "error", "at",
  ];
  const forwardProbe = (event) => {
    if (!event || typeof event !== "object") return;
    const clean = {};
    for (const key of PROBE_FIELDS) {
      const value = event[key];
      if (typeof value === "number" || typeof value === "boolean")
        clean[key] = value;
      else if (typeof value === "string") clean[key] = value.slice(0, 200);
    }
    chrome.runtime.sendMessage({ kind: "probe", event: clean }).catch(() => {});
  };

  // Place lore heard, kept across page loads (SavedVariables are not):
  // updates are chained so two at once do not overwrite each other.
  let heardChain = Promise.resolve();
  const HEARD_MAX = 5000;
  const updateHeard = (change) => {
    heardChain = heardChain
      .then(() => chrome.storage.local.get("placesHeard"))
      .then(({ placesHeard }) => {
        const list = change(Array.isArray(placesHeard) ? placesHeard : []);
        if (list) return chrome.storage.local.set({ placesHeard: list.slice(-HEARD_MAX) });
      })
      .catch(() => {});
  };

  // Messages from the addon (CatQuest's SendBytes), half a byte per marker:
  // kind byte (1 character, 2 Lua error, 3 feedback, 4 place demand,
  // 5 settings), length,
  // payload, checksum.
  const WHO_NIBBLES = 144, WHO_SLOTS = 3;
  // Half bytes per slot as read; a slot is decoded when reads stop for a while.
  // Positions not read again keep the last value: on a relog the game skips
  // files it has read before, and those held the same half byte.
  const whoNibbles = new Map(), whoTimers = new Map();
  let whoLast = "";
  const utf8 = (bytes) => {
    try {
      return new TextDecoder("utf-8", { fatal: true }).decode(new Uint8Array(bytes));
    } catch {
      return null;
    }
  };
  const decodeMessage = (slot) => {
    const nibbles = whoNibbles.get(slot) || [];
    const byte = (k) => (nibbles[2 * k] === undefined || nibbles[2 * k + 1] === undefined
      ? -1 : nibbles[2 * k] * 16 + nibbles[2 * k + 1]);
    const kind = byte(0), length = byte(1);
    if (kind < 1 || kind > 5 || length < 1 || length + 3 > WHO_NIBBLES / 2) return null;
    const bytes = [];
    for (let k = 0; k < length + 3; k++) {
      const b = byte(k);
      if (b < 0) return null;
      bytes.push(b);
    }
    const sum = bytes.slice(0, -1).reduce((a, b) => a + b, 0) % 256;
    if (sum !== bytes[bytes.length - 1]) return null;
    const payload = bytes.slice(2, -1);
    if (kind === 2) {
      const text = utf8(payload);
      return text ? { kind: "error", text } : null;
    }
    if (kind === 3) {
      // Feedback (CatQuest's Feedback.lua): target, id (4 bytes), reason,
      // voice language index, note.
      if (payload.length < 7 || payload[0] < 1 || payload[0] > 3) return null;
      const id = ((payload[1] * 256 + payload[2]) * 256 + payload[3]) * 256 + payload[4];
      const note = utf8(payload.slice(7));
      if (note === null) return null;
      return {
        kind: "feedback",
        target: ["quest", "turnin", "book"][payload[0] - 1],
        id: payload[0] === 3 ? id.toString(16).padStart(8, "0") : id,
        reason: payload[5],
        locale: VOICE_LOCALES[payload[6] - 1] || "",
        note,
      };
    }
    if (kind === 4) {
      // Place demand (Books.lua): UTF-8 zone, subzone and optional 8-char
      // place hash. An empty hash means the player requested missing lore.
      const text = utf8(payload);
      if (text === null) return null;
      const fields = text.split("\t");
      if (fields.length !== 3 && fields.length !== 4) return null;
      const [zone, subzone, hash, areaText = "0"] = fields;
      if (!zone || !subzone || zone.length > 80 || subzone.length > 80 ||
          (hash !== "" && !/^[0-9a-f]{8}$/.test(hash)) || !/^\d{1,7}$/.test(areaText)) return null;
      return { kind: "place-request", zone, subzone, hash, areaId: Number(areaText) };
    }
    if (kind === 5) {
      // Scale and audio ducking are sent immediately because browser-game F5
      // may reload before SavedVariables has been written. This is deliberately
      // a small partial object; telemetry.js merges it with existing settings.
      const text = utf8(payload);
      if (text === null || text.length > 64) return null;
      const settings = {};
      for (const field of text.split("\t")) {
        const match = /^(scale|duck)=(-?\d+(?:\.\d+)?)$/.exec(field);
        if (!match) continue;
        const value = Number(match[2]);
        if (!Number.isFinite(value)) continue;
        if (match[1] === "scale" && value >= 0.5 && value <= 2) settings.scale = value;
        if (match[1] === "duck" && value >= 0 && value <= 100) settings.duck = value;
      }
      return Object.keys(settings).length ? { kind: "addon-settings", settings } : null;
    }
    if (payload.length < 12) return null;
    const guid = payload.slice(-8);
    const text = payload.slice(0, -8);
    if (text[text.length - 1] !== 9) return null;
    const [realm, name] = (utf8(text.slice(0, -1)) || "").split("\t");
    if (!realm || !name) return null;
    return { kind: "character", realm, name,
      guid: "0x" + guid.map((b) => b.toString(16).padStart(2, "0")).join("").toUpperCase() };
  };
  const onCharacter = (who) => {
    const key = [who.realm, who.guid, who.name].join("\t");
    if (key === whoLast) return;
    whoLast = key;
    chrome.runtime.sendMessage({ kind: "character", realm: who.realm, name: who.name, guid: who.guid }).catch(() => {});
    // Said once, the first time a character is sent.
    chrome.storage.local
      .get(["identityNoticed", "identityOff", "telemetryOff"])
      .then(({ identityNoticed, identityOff, telemetryOff }) => {
        if (identityNoticed || identityOff || telemetryOff) return;
        chrome.storage.local.set({ identityNoticed: true }).catch(() => {});
        Panel.notice("identity", "identityNotice", who.name, 20000);
      })
      .catch(() => {});
  };
  const noteWho = (slot, pos, value) => {
    if (!whoNibbles.has(slot)) whoNibbles.set(slot, []);
    whoNibbles.get(slot)[pos] = value;
    clearTimeout(whoTimers.get(slot));
    whoTimers.set(slot, setTimeout(() => {
      const message = decodeMessage(slot);
      if (message?.kind === "character") onCharacter(message);
      // A Lua error of the addon: into diagnostics and the error report.
      else if (message?.kind === "error") forwardProbe({ type: "lua-error", error: message.text });
      else if (message?.kind === "feedback") chrome.runtime.sendMessage(message).catch(() => {});
      else if (message?.kind === "place-request") chrome.runtime.sendMessage(message).catch(() => {});
      else if (message?.kind === "addon-settings")
        chrome.runtime.sendMessage({ kind: "addon-settings-save", settings: message.settings }).catch(() => {});
    }, 2500));
  };

  // Errors of the bridge itself go to the report too.
  const bridgeError = (where, error) =>
    forwardProbe({ type: "bridge-error", error: `${where}: ${String(error?.stack || error).slice(0, 180)}` });

  const handleVoiceRequest = async (request, reply) => {
    if (request?.kind === "probe") Panel.onProbe(request.event);
    if (request?.kind === "place-heard") {
      const hash = String(request.hash || "");
      if (/^[0-9a-f]{8}$/.test(hash)) {
        updateHeard((list) => (list.includes(hash) ? null : [...list, hash]));
        chrome.runtime.sendMessage({ kind: "place-heard-save", hash }).catch(() => {});
      }
      return;
    }
    if (request?.kind === "who") {
      // Who plays, half a byte at a time (runtime-core.js); background.js
      // sends it to the server unless statistics are off.
      const slot = Number(request.slot), pos = Number(request.pos), value = Number(request.value);
      if (slot >= 1 && slot <= WHO_SLOTS && pos >= 0 && pos < WHO_NIBBLES && value >= 0 && value < 16) noteWho(slot, pos, value);
      return;
    }
    if (request?.kind === "ui-locale") {
      if (["ruRU", "enUS", "auto"].includes(request.locale))
        chrome.storage.local.set({ uiLocale: request.locale }).catch(() => {});
      return;
    }
    if (request?.kind === "places-reset") {
      updateHeard(() => []);
      chrome.runtime.sendMessage({ kind: "places-heard-reset" }).catch(() => {});
      return;
    }
    if (request?.kind === "voice-locale") {
      // At login the addon reports the language it runs with; /cq lang and the
      // addon's options report a choice, which wins until the next choice.
      const update = {};
      if (VOICE_LOCALES.includes(request.locale)) update.voiceLocaleAuto = request.locale;
      if (request.choice && (request.locale === "auto" || update.voiceLocaleAuto))
        update.voiceLocale = request.locale;
      if (Object.keys(update).length) chrome.storage.local.set(update).catch(() => {});
      return;
    }
    if (request?.kind === "addon-settings") {
      chrome.runtime.sendMessage({ kind: "addon-settings-save", settings: request.settings }).catch(() => {});
      return;
    }
    if (request?.kind === "probe") {
      forwardProbe(request.event);
      return;
    }
    if (request?.kind !== "voice-fetch" || !request.id) return;
    let response;
    try {
      response = await chrome.runtime.sendMessage({
        kind: "voice-fetch",
        url: String(request.url || ""),
      });
    } catch (error) {
      response = { ok: false, status: 502, error: String(error) };
    }
    reply({
      kind: "voice-response",
      id: request.id,
      ok: !!response?.ok,
      status: Number(response?.status) || 0,
      contentType: String(response?.contentType || ""),
      body64: typeof response?.body64 === "string" ? response.body64 : "",
      error: String(response?.error || ""),
    });
  };

  VOICE_CHANNEL.addEventListener("message", (event) => {
    handleVoiceRequest(event.data, (response) =>
      VOICE_CHANNEL.postMessage(response),
    ).catch((error) => bridgeError(event.data?.kind || "request", error));
  });

  window.addEventListener("message", (event) => {
    if (
      event.source !== window ||
      event.origin !== location.origin ||
      event.data?.channel !== VOICE_CHANNEL_NAME
    )
      return;
    handleVoiceRequest(event.data, (response) =>
      window.postMessage(
        { channel: VOICE_CHANNEL_NAME, ...response },
        location.origin,
      ),
    ).catch((error) => bridgeError(event.data?.kind || "request", error));
  });

  const send = () =>
    payload &&
    window.postMessage(
      { channel: CHANNEL, kind: "payload", payload },
      location.origin,
    );
  window.addEventListener("message", (event) => {
    if (
      event.source !== window ||
      event.origin !== location.origin ||
      event.data?.channel !== CHANNEL
    )
      return;
    if (event.data.kind === "hello") send();
    if (event.data.kind === "status") {
      const s = event.data.status;
      if (!s || !["ready", "error", "pending"].includes(s.state)) return;
      // Page diagnostics are untrusted. They can never change the addon library.
      chrome.runtime
        .sendMessage({
          kind: "diagnostic",
          status: {
            state: s.state,
            message: String(s.message || "").slice(0, 1000),
            revision: String(s.revision || "").slice(0, 80),
            loaded: Array.isArray(s.loaded)
              ? s.loaded.slice(0, 100).map((x) => String(x).slice(0, 120))
              : [],
            at: Date.now(),
          },
        })
        .catch(() => {});
    }
  });
  // The list of ready server tracks goes into the game's file manifest.
  const VOICE_LOCALES = [
    "ruRU", "enUS", "zhCN", "zhTW", "deDE", "frFR",
    "esES", "esMX", "ptBR", "koKR", "itIT",
  ];
  // Voice language: the manager setting, else what the addon saved in game.
  const voiceLocale = ({ voiceLocale, voiceLocaleAuto }) =>
    [voiceLocale, voiceLocaleAuto].find((l) => VOICE_LOCALES.includes(l)) || "ruRU";
  const voiceChoice = ({ voiceLocale }) =>
    voiceLocale === "auto" || VOICE_LOCALES.includes(voiceLocale) ? voiceLocale : "";
  // F5 reloads the game without saving the addon's settings, so a /cq lang
  // choice would be lost. The player's last choice goes into the addon as an
  // extra file, Bridge.lua, listed at the end of its TOC; the addon applies it
  // at login.
  const b64 = (text) => {
    const bytes = new TextEncoder().encode(text);
    let s = "";
    for (const b of bytes) s += String.fromCharCode(b);
    return btoa(s);
  };
  const unb64 = (text) => new TextDecoder().decode(Uint8Array.from(atob(text), (c) => c.charCodeAt(0)));
  // It also lists the tracks that are ready for the prepared voice language:
  // on Lasthavens PlaySoundFile reports success before the file is read, so
  // only this list tells the addon that a quest is still to be voiced.
  // q[quest] = 1 (description) | 2 (turn-in) ready; d[quest] = { seconds, seconds }.
  const readyBody = (tracks, durations) => {
    const bits = new Map();
    for (const [quest, type] of Array.isArray(tracks) ? tracks : [])
      if (Number.isInteger(quest) && (type === "DETAIL" || type === "COMPLETE"))
        bits.set(quest, (bits.get(quest) || 0) | (type === "DETAIL" ? 1 : 2));
    const lengths = new Map();
    for (const [quest, type, seconds] of Array.isArray(durations) ? durations : [])
      if (Number.isInteger(quest) && Number.isFinite(seconds) && seconds > 0) {
        const pair = lengths.get(quest) || [0, 0];
        pair[type === "COMPLETE" ? 1 : 0] = Math.round(seconds * 10) / 10;
        lengths.set(quest, pair);
      }
    const rows = (list) => {
      let out = "";
      for (let i = 0; i < list.length; i += 20) out += list.slice(i, i + 20).join(",") + ",\n";
      return out;
    };
    return (
      "q = {\n" + rows([...bits].map(([q, b]) => `[${q}]=${b}`)) +
      "}, d = {\n" + rows([...lengths].map(([q, [a, b]]) => `[${q}]={${a},${b}}`)) + "}"
    );
  };
  // locale: the language prepared for voicing on demand in this page load;
  // others: ready tracks of every other language, so after /cq lang without
  // F5 the addon knows what can play and what needs a reload; budgetOut: the
  // server's voicing budget was used up when the page loaded.
  const readyLua = (locale, tracks, durations, budgetOut) => {
    if (!VOICE_LOCALES.includes(locale)) return "";
    let out = `CatQuest335_BridgeReady = { locale = "${locale}", ` +
      (budgetOut ? "budgetOut = true, " : "") +
      readyBody(tracks?.[locale], durations?.[locale]) + ", others = {\n";
    for (const other of VOICE_LOCALES)
      if (other !== locale && Array.isArray(tracks?.[other]) && tracks[other].length)
        out += `["${other}"] = { ` + readyBody(tracks[other], durations?.[other]) + " },\n";
    return out + "} }\n";
  };
  const heardLua = (heard) => {
    const list = (Array.isArray(heard) ? heard : []).filter((h) => /^[0-9a-f]{8}$/.test(h));
    if (!list.length) return "";
    let out = "CatQuest335_BridgeHeard = {\n";
    for (let i = 0; i < list.length; i += 12) out += list.slice(i, i + 12).map((h) => `"${h}"`).join(",") + ",\n";
    return out + "}\n";
  };
  // Bridge.lua is the TOC's first file: it only sets globals, and texts the
  // addon makes while loading already follow the interface language.
  const luaString = (value) =>
    `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r?\n/g, "\\n")}"`;
  const settingsLua = (settings) => {
    if (!settings || typeof settings !== "object") return "";
    const bools = [
      "enabled", "auto", "showSubtitle", "books", "turnin", "queue", "readAfterAccept",
      "stopOnClose", "readButton", "bookPages", "head", "headLocked", "keepInBackground",
      "compact", "minimap", "minimapLocked", "storyQuestTitles", "places", "remoteEnabled",
    ];
    const numbers = ["trackGap", "duck", "scale", "minimapAngle", "remoteDuration", "pendingTimeout"];
    const texts = ["volumeChannel", "language", "uiLanguage", "pack"];
    const out = [];
    for (const key of bools) if (typeof settings[key] === "boolean") out.push(`["${key}"] = ${settings[key] ? "true" : "false"}`);
    for (const key of numbers) if (Number.isFinite(Number(settings[key]))) out.push(`["${key}"] = ${Number(settings[key])}`);
    for (const key of texts) if (typeof settings[key] === "string") out.push(`["${key}"] = ${luaString(settings[key])}`);
    const p = settings.headPosition;
    if (p && typeof p === "object" && Number.isFinite(Number(p.x)) && Number.isFinite(Number(p.y)))
      out.push(`["headPosition"] = { ["point"] = ${luaString(p.point)}, ["relativePoint"] = ${luaString(p.relativePoint)}, ["x"] = ${Number(p.x)}, ["y"] = ${Number(p.y)} }`);
    return out.length ? `CatQuest335_BridgeSettings = { ${out.join(", ")} }\n` : "";
  };
  const withBridge = (files, choice, ready, heard = "", ui = "", settings = {}) => {
    const toc = Object.keys(files).find((p) => /^[^/]+\.toc$/i.test(p));
    const settingsText = settingsLua(settings);
    if ((!choice && !ready && !heard && !ui && !settingsText) || !toc || files["Bridge.lua"]) return files;
    const text = unb64(files[toc]);
    const eol = text.includes("\r\n") ? "\r\n" : "\n";
    const lines = text.replace(/\s*$/, "").split(/\r?\n/);
    const first = lines.findIndex((line) => line.trim() && !line.trim().startsWith("#"));
    lines.splice(first < 0 ? lines.length : first, 0, "Bridge.lua");
    return {
      ...files,
      [toc]: b64(lines.join(eol) + eol),
      "Bridge.lua": b64(
        (choice ? `CatQuest335_BridgeChoice = "${choice}"\n` : "") +
          (ui ? `CatQuest335_BridgeUI = "${ui}"\n` : "") +
          settingsText +
          ready +
          heard,
      ),
    };
  };
  const uiChoice = ({ uiLocale }) => (["ruRU", "enUS", "auto"].includes(uiLocale) ? uiLocale : "");
  // The panel speaks the addon's interface language: the choice, else the
  // voice language when it has panel texts.
  const panelLanguage = (stored) => {
    const ui = uiChoice(stored);
    const locale = ui && ui !== "auto" ? ui : voiceLocale(stored);
    return locale === "ruRU" ? "ru" : locale === "enUS" ? "en" : /^zh/.test(locale) ? "zh" : "";
  };
  const loadVoiceIndex = (locale) =>
    Promise.race([
      chrome.runtime.sendMessage({ kind: "voice-index", demand: locale }),
      // The loader waits 10 s for the whole payload.
      new Promise((resolve) => setTimeout(() => resolve(null), 8000)),
    ])
      .then((r) => (r?.ok ? r : {}))
      .catch(() => ({}));

  // Budget state for Bridge.lua; never holds the load up for long.
  const loadBudgetOut = () =>
    Promise.race([
      chrome.runtime.sendMessage({ kind: "voice-capacity" }),
      new Promise((resolve) => setTimeout(() => resolve(null), 3000)),
    ])
      .then((c) => Boolean(c?.generation && c.budget_tracks === 0))
      .catch(() => false);

  const loadAddonSettings = () =>
    Promise.race([
      chrome.runtime.sendMessage({ kind: "addon-settings-get" }),
      new Promise((resolve) => setTimeout(() => resolve(null), 5000)),
    ])
      .then((answer) => (answer?.ok && answer.settings && typeof answer.settings === "object" ? answer.settings : {}))
      .catch(() => ({}));

  const loadHeardPlaces = () =>
    Promise.race([
      chrome.runtime.sendMessage({ kind: "places-heard-get" }),
      new Promise((resolve) => setTimeout(() => resolve(null), 5000)),
    ])
      .then((answer) => (answer?.ok && Array.isArray(answer.heard) ? answer.heard : []))
      .catch(() => []);

  chrome.storage.local
    .get(["library", "voiceLocale", "voiceLocaleAuto", "placesHeard", "uiLocale", "telemetry", "telemetryOff"])
    .then(async (stored) => {
      Panel.setLanguage(panelLanguage(stored));
      const locale = voiceLocale(stored);
      const [index, budgetOut, settings, heard] = await Promise.all([
        loadVoiceIndex(locale), loadBudgetOut(), loadAddonSettings(), loadHeardPlaces(),
      ]);
      return [stored, index, locale, budgetOut, settings, heard];
    })
    .then(([stored, index, locale, budgetOut, settings, heard]) => {
      const { library } = stored;
      const remoteTracks = index.tracks || {};
      const lib = library || { revision: "empty", addons: [] };
      const enabled = lib.addons.filter((a) => a.enabled);
      payload = {
        revision: lib.revision,
        voiceApi: DEFAULT_VOICE_API,
        // The install number in voice URLs, so the server knows whose plays
        // they are; none with statistics off (the server counts a guest).
        player: !stored.telemetryOff && typeof stored.telemetry?.id === "string" ? stored.telemetry.id : "",
        clientVersion: "3.3.5a",
        // Only CatQuest plays server tracks.
        remoteTracks: enabled.some((a) => a.folder.toLowerCase() === "catquest")
          ? remoteTracks
          : {},
        remoteBooks: enabled.some((a) => a.folder.toLowerCase() === "catquest")
          ? index.books || []
          : [],
        remoteGossip:
          enabled.some((a) => a.folder.toLowerCase() === "catquest") && index.gossipPlaceholderSize
            ? { size: index.gossipPlaceholderSize, locale }
            : null,
        remoteDemand:
          enabled.some((a) => a.folder.toLowerCase() === "catquest") &&
          index.placeholderSize && Array.isArray(index.demand)
            ? { locale, size: index.placeholderSize, tracks: index.demand }
            : null,
        addons: enabled.map((a) => ({
          folder: a.folder,
          files:
            a.folder.toLowerCase() === "catquest"
              ? withBridge(
                  a.files,
                  voiceChoice(stored),
                  // Only with an on-demand list: without it nothing is voiced on demand.
                  index.placeholderSize && Array.isArray(index.demand)
                    ? readyLua(locale, remoteTracks, index.durations || {}, budgetOut)
                    : "",
                  heardLua(heard.length ? heard : stored.placesHeard),
                  uiChoice(stored),
                  settings,
                )
              : a.files,
        })),
      };
      send();
    })
    .catch((e) => {
      payload = { revision: "error", addons: [], error: String(e) };
      send();
    });
  // Updates (updates.js): a newer extension is announced once per page load;
  // an addon updated while the game runs asks for a page reload.
  const loadedAt = Date.now();
  chrome.storage.local.get("updateState").then(({ updateState }) => {
    if (updateState?.extension?.version)
      Panel.notice("extension", "extensionUpdate", updateState.extension.version, 15000);
  });
  chrome.storage.onChanged.addListener((changes, area) => {
    const state = area === "local" && changes.updateState?.newValue;
    if (!state) return;
    for (const item of state.installed || [])
      if (item.at > loadedAt && item.folder === "CatQuest")
        Panel.notice("addon", "addonUpdated", item.version, 60000);
  });
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && (changes.uiLocale || changes.voiceLocale || changes.voiceLocaleAuto))
      chrome.storage.local
        .get(["voiceLocale", "voiceLocaleAuto", "uiLocale"])
        .then((stored) => Panel.setLanguage(panelLanguage(stored)))
        .catch(() => {});
  });
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && (changes.library || changes.voiceLocale || changes.voiceLocaleAuto))
      window.postMessage(
        { channel: CHANNEL, kind: "changed" },
        location.origin,
      );
  });
})();
