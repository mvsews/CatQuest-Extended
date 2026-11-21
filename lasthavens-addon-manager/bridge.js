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
        collapse: "Свернуть",
        expand: "Развернуть",
        turnin: "(сдача) ",
        queued: (d) => `в очереди: ${d.position}-я, ~${d.eta} с`,
        running: (d) => `озвучивается: ${d.elapsed} с из ~${d.total} с`,
        ready: "готово, файл передан игре",
        fetching: "готово, загружаю звук",
        downloaded: "звук загружен, ожидаю запуска в игре",
        failed: (e) => `не удалось: ${e}`,
        limited: (min) => `лимит часа исчерпан, новая через ${min} мин`,
        budget: "бюджет озвучки исчерпан, новые квесты пока не озвучиваются — напишите об этом в https://t.me/warcraft_rus_chat",
        missing: "нет текста квеста для этого языка",
        waiting: "запрос отправлен",
        accepted: "сервер принял запрос, дорожка готовится — повторите «Прослушать» позже",
        serverError: (s) => `сервер вернул ошибку ${s}; повторите позже`,
        rateLimited: "сервер ограничил новые запросы озвучки; ожидаем возможности повторить",
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
        collapse: "收起",
        expand: "展开",
        turnin: "（交任务）",
        queued: (d) => `排队中：第 ${d.position} 位，约 ${d.eta} 秒`,
        running: (d) => `正在配音：${d.elapsed} / 约 ${d.total} 秒`,
        ready: "已完成，音频已传给游戏",
        fetching: "已完成，正在加载音频",
        downloaded: "音频已加载，等待游戏播放",
        failed: (e) => `失败：${e}`,
        limited: (min) => `本小时额度已用完，${min} 分钟后可用`,
        budget: "配音预算已用完，暂时无法生成新配音。请在 https://t.me/warcraft_rus_chat 告知我们",
        missing: "该语言没有任务文本",
        waiting: "已发送请求",
        accepted: "服务器已接受请求，正在生成；稍后再次点击“试听”",
        serverError: (s) => `服务器返回错误 ${s}，请稍后重试`,
        rateLimited: "服务器暂时限制了新的配音请求，等待重试",
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
        collapse: "Collapse",
        expand: "Expand",
        turnin: "(turn-in) ",
        queued: (d) => `queued: #${d.position}, ~${d.eta} s`,
        running: (d) => `voicing: ${d.elapsed} s of ~${d.total} s`,
        ready: "ready, audio delivered to the game",
        fetching: "ready, loading audio",
        downloaded: "audio loaded, waiting for the game",
        failed: (e) => `failed: ${e}`,
        limited: (min) => `hourly limit reached, next in ${min} min`,
        budget: "voicing budget is used up: new quests are not voiced for now. Please tell us at https://t.me/warcraft_rus_chat",
        missing: "no quest text for this language",
        waiting: "request sent",
        accepted: "server accepted the request; the track is being generated — click Listen again later",
        serverError: (s) => `server returned error ${s}; try again later`,
        rateLimited: "server is limiting new voice requests; waiting to retry",
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
    let root, list, footer, capacity, collapsed = false, visible = false;
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
      if (root) {
        if (!root.isConnected) (document.body || document.documentElement).append(root);
        return;
      }
      root = document.createElement("div");
      root.id = "catquest-voice-panel";
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
      const toggle = document.createElement("button");
      toggle.type = "button";
      toggle.textContent = "−";
      toggle.title = T.collapse;
      toggle.setAttribute("aria-label", T.collapse);
      Object.assign(toggle.style, {
        pointerEvents: "auto", cursor: "pointer", background: "none", border: "none", padding: "0 2px",
        color: "#b9ab88", font: "16px/1 system-ui, sans-serif",
      });
      for (const type of ["pointerdown", "mousedown", "mouseup", "contextmenu"])
        toggle.addEventListener(type, (e) => e.stopPropagation());
      toggle.addEventListener("click", (event) => {
        event.stopPropagation();
        collapsed = !collapsed;
        toggle.textContent = collapsed ? "+" : "−";
        toggle.title = collapsed ? T.expand : T.collapse;
        toggle.setAttribute("aria-label", toggle.title);
        list.style.display = collapsed ? "none" : "block";
        footer.style.display = collapsed ? "none" : "block";
      });
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
        render();
      });
      head.append(title, toggle, close);
      list = document.createElement("div");
      footer = document.createElement("div");
      Object.assign(footer.style, { marginTop: "4px", color: "#b9ab88", fontSize: "11px" });
      root.append(head, list, footer);
      (document.body || document.documentElement).append(root);
      place();
    };

    const render = () => {
      if (!visible) {
        if (root) root.style.display = "none";
        return;
      }
      if (!items.size && !notices.size) {
        if (root) root.style.display = "none";
        return;
      }
      ensureRoot();
      root.style.display = "block";
      place();
      list.style.display = collapsed ? "none" : "block";
      footer.style.display = collapsed ? "none" : "block";
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
      // Rows can change height; clamp using the completed layout, too.
      place();
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
      } else if (status.status === "missing" && item.state === "limited") {
        // A rejected request creates no job. Preserve the real 429 reason;
        // "missing" here is not evidence that the quest has no text.
      } else if (status.status === "missing") {
        item.state = "failed";
        item.text = T.missing;
        item.doneAt = Date.now();
      }
    };

    // Status polling used to run every four seconds for every queued track.
    // In a browser game the addon retries reads itself; polling here only
    // duplicated requests and kept the tab busy. The panel is now event-driven:
    // it shows request/fetch/read events and never asks the server in a loop.
    const start = () => {};

    return {
      setVisible(value) {
        visible = value === true;
        if (!visible) {
          items.clear();
          notices.clear();
        }
        render();
      },
      // "ru" | "en" | "zh"; texts already shown switch on the next render.
      setLanguage(lang) {
        if (!TEXTS[lang] || TEXTS[lang] === T) return;
        T = TEXTS[lang];
        if (titleText) {
          titleText.textContent = T.title;
          titleText.title = T.drag;
          const toggle = titleText.nextSibling;
          if (toggle) {
            toggle.title = collapsed ? T.expand : T.collapse;
            toggle.setAttribute("aria-label", toggle.title);
          }
          const close = toggle?.nextSibling;
          if (close) {
            close.title = T.close;
            close.setAttribute("aria-label", T.close);
          }
        }
        render();
      },
      notice(key, kind, version, ms = 20000) {
        if (!visible) return;
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
        if (event.type === "limited") {
          items.set(key, {quest:event.quest,kind:event.kind,locale:event.locale,
            state:"limited",text:T.rateLimited,since:Date.now()});
          trimItems();render();return;
        }
        // Requests also arrive through shared-memory prefetch now, including
        // already generated tracks. Show immediately, before any status HTTP.
        if (["prefetch-sent", "fetch-start", "demand"].includes(event.type)) {
          if (!items.has(key) || items.get(key).doneAt) {
            items.set(key, {
              quest: event.quest, kind: event.kind, locale: event.locale,
              state: "waiting", text: T.waiting, since: Date.now(),
            });
          }
          trimItems();
          render();
        } else if (event.type === "missing-text" && items.has(key)) {
          const item = items.get(key);
          item.state = "failed";
          item.text = T.missing;
          item.doneAt = Date.now();
          render();
        } else if ((event.type === "fetch-done" || event.type === "prefetch") && items.has(key)) {
          const item = items.get(key);
          if (event.ok) {
            item.state = "fetching";
            item.text = T.downloaded;
            item.fetchingAt = Date.now();
          } else if (Number(event.status) === 202) {
            // Auto-retry is intentionally disabled: do not poll the backend
            // from the game tab. The server accepted generation and the next
            // explicit Listen click will retry the file read.
            item.state = "waiting";
            item.text = T.accepted;
          } else if (Number(event.status) === 404) {
            item.state = "failed";
            item.text = T.missing;
            item.doneAt = Date.now();
          } else if (Number(event.status) === 429) {
            item.state = "limited";
            item.text = T.rateLimited;
          } else if (Number(event.status) >= 400) {
            item.state = "failed";
            item.text = T.serverError(Number(event.status));
            item.doneAt = Date.now();
          }
          render();
        } else if ((event.type === "direct" || event.type === "poll" ||
            (event.type === "read" && event.cached)) && items.has(key)) {
          const item = items.get(key);
          if (event.ok || event.cached) {
            item.state = "ready";
            item.text = T.ready;
            item.doneAt = Date.now();
          }
          render();
        }
      },
    };

    function trimItems() {
      while (items.size > 24) items.delete(items.keys().next().value);
    }
  })();
  const CHANNEL = "lh-local-addons-v1",
    DEFAULT_VOICE_API = "https://quester.mvse.ws",
    VOICE_CHANNEL_NAME = "lh-catquest-voice-v1",
    VOICE_CHANNEL = new BroadcastChannel(VOICE_CHANNEL_NAME);
  let payload;
  const diagnosticSession = crypto.randomUUID();

  // Probe events come from the untrusted page: keep only known short fields.
  const PROBE_FIELDS = [
    "type", "via", "ctx", "sync", "quest", "kind", "locale", "cached", "path", "status",
    "bytes", "ms", "ok", "api", "globals", "isolated", "files", "error", "at", "slot",
    "run", "ext", "addon", "request", "stage", "attempt", "hash", "gossipSlot", "detail",
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
    clean.run = clean.run || diagnosticSession;
    clean.ext = clean.ext || chrome.runtime.getManifest().version;
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
  let gossipHeardChain = Promise.resolve();
  const updateGossipHeard = (key) => {
    if (!/^\d{1,7}:[a-z]{2}[A-Z]{2}:[0-9a-f]{16}$/.test(key || "")) return;
    gossipHeardChain = gossipHeardChain.then(async () => {
      const {gossipHeard=[]} = await chrome.storage.local.get("gossipHeard");
      const keys = new Set(Array.isArray(gossipHeard) ? gossipHeard : []);
      keys.add(key);
      await chrome.storage.local.set({gossipHeard:[...keys].slice(-20000)});
    }).catch(() => {});
  };

  // Messages from the addon (CatQuest's SendBytes), half a byte per marker:
  // kind byte (1 character, 2 Lua error, 3 feedback, 4 place demand,
  // 5 settings), length,
  // payload, checksum.
  const WHO_NIBBLES = 512, WHO_SLOTS = 3;
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
    if (kind < 1 || kind > 6 || length < 1 || length + 3 > WHO_NIBBLES / 2) return null;
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
      if (payload.length < 7 || payload[0] < 1 || payload[0] > 4) return null;
      const id = ((payload[1] * 256 + payload[2]) * 256 + payload[3]) * 256 + payload[4];
      const note = utf8(payload.slice(7));
      if (note === null) return null;
      return {
        kind: "feedback",
        target: ["quest", "turnin", "book", "npc"][payload[0] - 1],
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
    if (kind === 6) {
      if ((payload.length !== 6 && payload.length < 18) || ![1, 2].includes(payload[4])) return null;
      const quest = ((payload[0] * 256 + payload[1]) * 256 + payload[2]) * 256 + payload[3];
      if (!Number.isInteger(quest) || quest <= 0 || quest >= 1e7) return null;
      const message = { kind: "quest-vote", quest, vote: payload[4] === 1 ? 1 : -1,
        locale: VOICE_LOCALES[payload[5] - 1] || "" };
      if (payload.length >= 18) {
        message.event_id = payload.slice(6,14).map((b)=>b.toString(16).padStart(2,"0")).join("");
        message.submitted_at = payload.slice(14,18).reduce((a,b)=>a*256+b,0);
        if (payload.length > 18) {
          const actor = payload.slice(18), raw = utf8(actor.slice(0,-8));
          if (actor.length < 12 || raw === null || !raw.endsWith("\t")) return null;
          const [realm,name,extra] = raw.slice(0,-1).split("\t");
          if (!realm || !name || extra !== undefined) return null;
          message.character = {realm,name,guid:"0x"+actor.slice(-8).map((b)=>b.toString(16).padStart(2,"0")).join("").toUpperCase()};
        }
      }
      return message;
    }
    if (kind === 5) {
      // Window settings arrive before browser-game SavedVariables are written.
      // Each marker is a partial update merged with the account settings.
      const text = utf8(payload);
      if (text === null || text.length > 64) return null;
      const settings = {};
      for (const field of text.split("\t")) {
        const rating = /^questRatings=(0|1)$/.exec(field);
        if (rating) { settings.questRatings = rating[1] === "1"; continue; }
        const panel = /^panel=(0|1)$/.exec(field);
        if (panel) { settings.requestPanel = panel[1] === "1"; continue; }
        const channel = /^channel=(Master|SFX|Music|Ambience)$/.exec(field);
        if (channel) {
          settings.volumeChannel = channel[1];
          continue;
        }
        const layer = /^layer=(below-bags|HIGH|DIALOG|FULLSCREEN_DIALOG)$/.exec(field);
        if (layer) {
          settings.headStrata = layer[1];
          continue;
        }
        const position = /^position=(CENTER|TOP|BOTTOM|LEFT|RIGHT|TOPLEFT|TOPRIGHT|BOTTOMLEFT|BOTTOMRIGHT),(CENTER|TOP|BOTTOM|LEFT|RIGHT|TOPLEFT|TOPRIGHT|BOTTOMLEFT|BOTTOMRIGHT),(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$/.exec(field);
        if (position) {
          const x = Number(position[3]), y = Number(position[4]);
          if (Number.isFinite(x) && Number.isFinite(y) && Math.abs(x) <= 10000 && Math.abs(y) <= 10000)
            settings.headPosition = { point: position[1], relativePoint: position[2], x, y };
          continue;
        }
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
      else if (message?.kind === "quest-vote") chrome.runtime.sendMessage(message).catch(() => {});
      else if (message?.kind === "place-request") chrome.runtime.sendMessage(message).catch(() => {});
      else if (message?.kind === "addon-settings") {
        if (Object.prototype.hasOwnProperty.call(message.settings || {}, "requestPanel"))
          Panel.setVisible(message.settings.requestPanel === true);
        chrome.runtime.sendMessage({ kind: "addon-settings-save", settings: message.settings }).catch(() => {});
      }
    }, 2500));
  };

  // Errors of the bridge itself go to the report too.
  const bridgeError = (where, error) =>
    forwardProbe({ type: "bridge-error", error: `${where}: ${String(error?.stack || error).slice(0, 180)}` });

  const handleVoiceRequest = async (request, reply) => {
    if (request?.kind === "gossip-heard") { updateGossipHeard(request.key); return; }
    if (request?.kind === "contact-part") {
      // The background worker acknowledges only after durable storage. Retry
      // waking it if the page races a worker restart.
      for (let attempt = 0; attempt < 3; attempt++) {
        try { if ((await chrome.runtime.sendMessage(request))?.ok) return; } catch {}
        await new Promise((resolve) => setTimeout(resolve, 1000 * (attempt + 1)));
      }
      return;
    }
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
      chrome.runtime.sendMessage({ kind: "addon-settings-import", settings: request.settings }).catch(() => {});
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
        request: request.id,
        run: diagnosticSession,
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
      terminal: response?.terminal === true,
      retryAfter: Number.isFinite(Number(response?.retryAfter))
        ? Math.max(0, Math.min(3600, Number(response.retryAfter)))
        : 0,
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

  const send = () => {
    if (!payload) return false;
    window.postMessage(
      { channel: CHANNEL, kind: "payload", payload },
      location.origin,
    );
    return true;
  };
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
  const readyBooks = (books) => {
    const hashes = new Set();
    for (const row of Array.isArray(books) ? books : []) {
      const hash = Array.isArray(row) ? String(row[0] || "").toLowerCase() : "";
      if (/^[0-9a-f]{8}$/.test(hash)) hashes.add(hash);
    }
    const list = [...hashes].sort();
    let out = "b = {\n";
    for (let i = 0; i < list.length; i += 24)
      out += list.slice(i, i + 24).map((hash) => `[\"${hash}\"]=true`).join(",") + ",\n";
    return out + "}";
  };
  // locale: the language prepared for voicing on demand in this page load;
  // others: ready tracks of every other language, so after /cq lang without
  // F5 the addon knows what can play and what needs a reload; budgetOut: the
  // server's voicing budget was used up when the page loaded.
  const readyLua = (locale, tracks, durations, books, budgetOut, readinessFont) => {
    if (!VOICE_LOCALES.includes(locale)) return "";
    // Signal 2 uses the dedicated prefetch marker paths. Signal 1 remains a
    // compatibility fallback for sessions where the readiness-font manifest
    // is unavailable, because those sessions do not contain /prefetch/*.
    const prefetchSignal = readinessFont?.body64 ? 2 : 1;
    let out = `CatQuest335_BridgeReady = { contact = true, contactContext = true, voteContext = true, gossipOnce = true, clientTrace = 1, prefetchSignal = ${prefetchSignal}, ${readinessFont?.body64 ? "fontReady = 1, readyMetrics = 2, waitingFont = 1, " : ""} extVersion = "${chrome.runtime.getManifest().version}", contactPage = "${diagnosticSession}", locale = "${locale}", ` +
      (budgetOut ? "budgetOut = true, " : "") +
      readyBody(tracks?.[locale], durations?.[locale]) + ", " + readyBooks(books) + ", others = {\n";
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
      "compact", "minimap", "minimapLocked", "storyQuestTitles", "places", "remoteEnabled", "remoteAutoRetry", "requestPanel", "questRatings",
    ];
    const numbers = ["trackGap", "duck", "scale", "minimapAngle", "remoteDuration", "pendingTimeout"];
    const texts = ["volumeChannel", "language", "uiLanguage", "pack", "headStrata"];
    const out = [];
    for (const key of bools) if (typeof settings[key] === "boolean") out.push(`["${key}"] = ${settings[key] ? "true" : "false"}`);
    for (const key of numbers) if (Number.isFinite(Number(settings[key]))) out.push(`["${key}"] = ${Number(settings[key])}`);
    for (const key of texts) if (typeof settings[key] === "string") out.push(`["${key}"] = ${luaString(settings[key])}`);
    const p = settings.headPosition;
    if (p && typeof p === "object" && Number.isFinite(Number(p.x)) && Number.isFinite(Number(p.y)))
      out.push(`["headPosition"] = { ["point"] = ${luaString(p.point)}, ["relativePoint"] = ${luaString(p.relativePoint)}, ["x"] = ${Number(p.x)}, ["y"] = ${Number(p.y)} }`);
    return out.length ? `CatQuest335_BridgeSettings = { ${out.join(", ")} }\n` : "";
  };
  const voteLua = (votes) => {
    const rows = Object.entries(votes || {}).filter(([id, row]) => /^\d{1,7}$/.test(id) && +id > 0 && [1, -1].includes(row?.vote));
    return rows.length ? `CatQuest335_BridgeQuestVotes = { ${rows.slice(0, 2000).map(([id, row]) => `[${+id}]=${row.vote}`).join(",")} }\n` : "";
  };
  const withBridge = (files, choice, ready, heard = "", ui = "", settings = {}, votes = {}, receipts = {}, gossipHeard = []) => {
    const toc = Object.keys(files).find((p) => /^[^/]+\.toc$/i.test(p));
    const settingsText = settingsLua(settings);
    const votesText = voteLua(votes);
    const received = Object.keys(receipts || {}).filter((id) => /^[0-9a-f]{16}$/.test(id)).slice(-500);
    const contactText = received.length ? `CatQuest335_BridgeContactReceived = { ${received.map((id)=>`["${id}"]=true`).join(",")} }\n` : "";
    const gossipKeys = (Array.isArray(gossipHeard) ? gossipHeard : []).filter((k)=>/^\d{1,7}:[a-z]{2}[A-Z]{2}:[0-9a-f]{16}$/.test(k)).slice(-20000);
    const gossipText = gossipKeys.length ? `CatQuest335_BridgeGossipHeard = {${gossipKeys.map((k)=>`["${k}"]=true`).join(",")}}\n` : "";
    if ((!choice && !ready && !heard && !ui && !settingsText && !votesText && !gossipText) || !toc || files["Bridge.lua"]) return files;
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
          votesText +
          contactText +
          gossipText +
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

  const loadReadinessFont = async () => {
    try {
      const [binary, metadata] = await Promise.all([
        fetch(chrome.runtime.getURL("vendor/catquest-ready.ttf")),
        fetch(chrome.runtime.getURL("vendor/catquest-ready.json")),
      ]);
      if (!binary.ok || !metadata.ok) return null;
      const bytes = new Uint8Array(await binary.arrayBuffer()), info = await metadata.json();
      if (bytes.length !== info.bytes || bytes.length > 65536) return null;
      return { ...info, body64: btoa(String.fromCharCode(...bytes)) };
    } catch { return null; }
  };
  chrome.storage.local
    .get(["library", "voiceLocale", "voiceLocaleAuto", "placesHeard", "uiLocale", "telemetry", "telemetryOff", "questVoteCache", "contactReceived", "gossipHeard"])
    .then(async (stored) => {
      Panel.setLanguage(panelLanguage(stored));
      const locale = voiceLocale(stored);
      const [index, budgetOut, settings, heard, readinessFont] = await Promise.all([
        loadVoiceIndex(locale), loadBudgetOut(), loadAddonSettings(), loadHeardPlaces(), loadReadinessFont(),
      ]);
      return [stored, index, locale, budgetOut, settings, heard, readinessFont];
    })
    .then(([stored, index, locale, budgetOut, settings, heard, readinessFont]) => {
      Panel.setVisible(settings.requestPanel === true);
      const { library } = stored;
      const remoteTracks = index.tracks || {};
      const lib = library || { revision: "empty", addons: [] };
      const enabled = lib.addons.filter((a) => a.enabled);
      payload = {
        runId: diagnosticSession,
        extensionVersion: chrome.runtime.getManifest().version,
        addonVersion: enabled.find((a) => a.folder.toLowerCase() === "catquest")?.version || "",
        revision: lib.revision,
        voiceApi: DEFAULT_VOICE_API,
        // The install number in voice URLs, so the server knows whose plays
        // they are; none with statistics off (the server counts a guest).
        player: !stored.telemetryOff && typeof stored.telemetry?.id === "string" ? stored.telemetry.id : "",
        clientVersion: "3.3.5a",
        readinessFont,
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
        remoteAutoRetry: settings.remoteAutoRetry === true,
        addons: enabled.map((a) => ({
          folder: a.folder,
          files:
            a.folder.toLowerCase() === "catquest"
              ? withBridge(
                  a.files,
                  voiceChoice(stored),
                  // Only with an on-demand list: without it nothing is voiced on demand.
                  index.placeholderSize && Array.isArray(index.demand)
                     ? readyLua(locale, remoteTracks, index.durations || {}, index.books || [], budgetOut, readinessFont)
                    : "",
                  heardLua(heard.length ? heard : stored.placesHeard),
                  uiChoice(stored),
                  settings,
                  stored.questVoteCache,
                  stored.contactReceived,
                  stored.gossipHeard,
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
