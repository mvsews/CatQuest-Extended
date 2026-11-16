local addonName = ...
local ns = CatQuest335 or {}
CatQuest335 = ns
ns.VERSION = "0.10.112"
local L = ns.L

local eventFrame = CreateFrame("Frame", "CatQuest335Events", UIParent)
local VOICE_PACKS = {
    -- The original CatQuest Voices recording is Russian.
    { key = "original", globalName = "CatQuestExtendedVoicePack", folder = "CatQuestExtended_Voices", locale = "ruRU" },
}

local defaults = {
    enabled = true,
    auto = true,
    gossipAuto = true, -- read the NPC greeting when the gossip window opens
    npcLore = true, -- read source-backed history when a named NPC is targeted
    npcLoreTrigger = "target", -- first target: after 1.5 s; kill: after combat; manual
    questRatings = true,
    questVotes = {},
    questVotePending = {},
    greetDelay = true, -- let the game's standard NPC greeting finish first
    showSubtitle = true,
    -- Music is the default because it has a reliable StopMusic API. SFX is
    -- available as an explicit one-shot option.
    volumeChannel = "Music",
    trackGap = 2,        -- pause between queued tracks, seconds
    books = false,       -- read books and notes as soon as they open; otherwise by the Read button
    turnin = true,       -- read the turn-in text on the reward screen
    -- As in the original CatQuest 1.0.6:
    queue = true,        -- lines wait their turn; off: a new line cuts the current one
    readAfterAccept = false, -- read the quest after "Accept" instead of in the dialog
    stopOnClose = false, -- closing the quest or book window stops its line
    readButton = true,   -- "Read" button in the quest and book windows
    bookPages = true,    -- after a page is read, turn to the next one and go on
    head = true,         -- the talking head window
    headLocked = false,  -- the window cannot be dragged
    duck = 0,            -- lower music and ambience while a line plays, %
    keepInBackground = true, -- keep sound on when the game is in the background
    compact = false,     -- compact speech window: title and progress only
    scale = 1,           -- speech window scale
    headStrata = "below-bags", -- layer relative to the game's bag windows
    minimap = true,      -- scroll button on the minimap
    -- Start in the upper-left quadrant; the old 200-degree default commonly
    -- overlapped other minimap-button addons.
    minimapAngle = 135,
    minimapLocked = false, -- do not move the minimap button by dragging
    storyQuestTitles = false, -- show the first quest title before a chapter starts
    places = true,       -- tell the lore of a place on the first visit
    dungeonMaster = true, -- dungeon narrator pilot
    placesHeard = {},
    pack = "auto",
    history = {},
    missing = {},
    remoteEnabled = true,
    remoteDuration = 90, -- upper bound for an estimated server track, seconds
    pendingTimeout = 300, -- how long a requested track may take before giving up, s
    remoteAutoRetry = true, -- retry a missing server track in the background
    requestPanel = false, -- show the browser's on-demand voice status panel
    voiceLog = {}, -- compact request/playback diagnostics, kept in SavedVariables
    remoteRetry = 0.5,   -- PlaySoundFile retry interval while the bridge fetches audio
    language = "auto",   -- voice language: "auto" follows the client, or a locale such as "zhCN"
    gossipAudioSlot = 0,  -- rotating virtual files for NPC gossip speech
    gossipMarkerSlot = 0, -- rotating marker slots used to send gossip text
    npcLoreHeard = {}, -- NPCID:locale -> true; source-backed history is heard once
    gossipHeard = {}, -- NPC + locale + universal paragraph; completed playback only
}

local function MergeDefaults(target, source)
    for key, value in pairs(source) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                MergeDefaults(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            MergeDefaults(target[key], value)
        end
    end
end

CatQuest335DB = CatQuest335DB or {}
local savedMinimapAngle = tonumber(CatQuest335DB.minimapAngle)
local savedMinimapPositionVersion = tonumber(CatQuest335DB.minimapPositionVersion)
-- On an online first install, restore the settings supplied by the extension.
-- The browser game may return an older SavedVariables snapshot after F5, so
-- its stored speech-window scale, position and sound channel take priority.
local hadSavedSettings = next(CatQuest335DB) ~= nil
if not CatQuest335_LocalMode and type(CatQuest335_BridgeSettings) == "table" then
    for key, value in pairs(CatQuest335_BridgeSettings) do
        if (not hadSavedSettings or key == "scale" or key == "volumeChannel"
            or key == "headStrata" or key == "questRatings")
            and defaults[key] ~= nil and type(defaults[key]) == type(value) then
            CatQuest335DB[key] = value
        elseif key == "headPosition" and type(value) == "table" then
            CatQuest335DB[key] = {
                point = tostring(value.point or "CENTER"),
                relativePoint = tostring(value.relativePoint or "CENTER"),
                x = tonumber(value.x) or 0,
                y = tonumber(value.y) or 0,
            }
        end
    end
end
MergeDefaults(CatQuest335DB, defaults)
-- 0.10.50: move the default icon away from the old lower-left cluster. Only
-- migrate accounts that have not yet acknowledged a minimap position; a
-- manually chosen position is preserved.
if not savedMinimapPositionVersion then
    if savedMinimapAngle == 200 then
        CatQuest335DB.minimapAngle = defaults.minimapAngle
    end
    CatQuest335DB.minimapPositionVersion = 2
end
-- 0.7.1: the fixed wait was replaced by the pending queue (pendingTimeout).
if (CatQuest335DB.schema or 0) < 3 then
    CatQuest335DB.remoteTimeout = nil
    CatQuest335DB.schema = 3
end
-- 0.7.7: voice moves to the SFX channel so that Stop can really stop it.
if (CatQuest335DB.schema or 0) < 4 then
    if CatQuest335DB.volumeChannel == "Master" then
        CatQuest335DB.volumeChannel = "SFX"
    end
    CatQuest335DB.schema = 4
end
-- 0.9.0: books are read by the button; reading on open is a setting, off by default.
if (CatQuest335DB.schema or 0) < 5 then
    CatQuest335DB.books = false
    CatQuest335DB.schema = 5
end
-- 0.11.0: make the default one-shot channel explicit. Existing installs that
-- still have the old default Music are moved to SFX; a later manual choice of
-- Music is preserved because this migration runs only once.
if (CatQuest335DB.schema or 0) < 6 then
    if CatQuest335DB.volumeChannel == nil or CatQuest335DB.volumeChannel == "Music" then
        CatQuest335DB.volumeChannel = "SFX"
    end
    CatQuest335DB.schema = 6
end
-- 0.11.1: restore Music as the default channel. The previous release moved
-- the old default to SFX; migrate that automatic choice back once.
if (CatQuest335DB.schema or 0) < 7 then
    if CatQuest335DB.volumeChannel == "SFX" then
        CatQuest335DB.volumeChannel = "Music"
    end
    CatQuest335DB.schema = 7
end
-- 0.11.2: automatically check on-demand requests until the server track is
-- ready, so accepting a quest needs no second manual click.
if (CatQuest335DB.schema or 0) < 8 then
    CatQuest335DB.remoteAutoRetry = true
    CatQuest335DB.schema = 8
end
ns.db = CatQuest335DB
if type(CatQuest335_BridgeGossipHeard) == "table" then
    for key, value in pairs(CatQuest335_BridgeGossipHeard) do
        if value == true and type(key) == "string" and #key < 100 then ns.db.gossipHeard[key] = true end
    end
end

ns.state = {
    recent = {}, -- "questID:kind" -> GetTime() when the quest dialog voiced it
    queue = {},
    active = nil,
    lastItem = nil,
    lastPlayedKey = nil,
    lastPlayedAt = 0,
    dialogTimer = nil,
    gossipTimer = nil,
    npcLoreTimer = nil,
    npcLoreKillTimer = nil,
    npcLoreKillPending = nil,
    npcLoreTargetPending = nil,
    npcLoreTarget = nil,
    npcLoreHeard = {},
}

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff6bdcffCatQuest|r: " .. tostring(message))
end

ns.Print = Print

local VOICE_LOG_LIMIT = 300
local function VoiceLog(item, status, detail)
    if not item then return end
    local log = ns.db.voiceLog
    if type(log) ~= "table" then
        log = {}
        ns.db.voiceLog = log
    end
    log[#log + 1] = {
        at = time and time() or 0,
        uptime = GetTime(),
        version = ns.VERSION,
        page = type(CatQuest335_BridgeReady) == "table" and CatQuest335_BridgeReady.contactPage or nil,
        status = tostring(status or ""),
        questID = tonumber(item.questID) or 0,
        kind = tostring(item.kind or ""),
        title = tostring(item.title or ""),
        detail = tostring(detail or ""):sub(1, 140),
        file = tostring(item.file or ""):sub(1, 180),
        slot = item.prefetchSlot,
        key = tostring(item.key or ""):sub(1, 180),
        channel = item.playChannel or ns.db.volumeChannel,
        duration = item.duration,
        attempt = item.readySignalAttempts,
        requestedFont = item.readyFontRequested,
        observedFont = item.readyFontObserved,
        fontUnit = item.readyFontUnit,
        fontMetrics = item.readyFontMetrics,
        fontWidths = item.readyFontWidths,
        verified = item.bridgeVerified and true or false,
        queue = #ns.state.queue,
        pending = #ns.state.pending,
    }
    while #log > VOICE_LOG_LIMIT do
        table.remove(log, 1)
    end
    if ns.SendDiagnosticStage then pcall(ns.SendDiagnosticStage, item, status) end
end
ns.VoiceLog = VoiceLog

function ns.VoiceLocale()
    if ns.db.language and ns.db.language ~= "auto" then
        return ns.NormalizeLocale(ns.db.language) or ns.ClientLocale()
    end
    return ns.ClientLocale()
end

-- Lasthavens: what the browser extension knows about server tracks
-- (Bridge.lua). locale is the language prepared for voicing on demand in
-- this page load; others has the ready tracks of the other languages.
-- Returns { q = ready bits, d = lengths } for a language, or nil.
local function BridgeInfo(locale)
    local ready = CatQuest335_BridgeReady
    if type(ready) ~= "table" then
        return nil
    end
    if ready.locale == locale then
        return type(ready.q) == "table" and ready or nil
    end
    local other = type(ready.others) == "table" and ready.others[locale]
    return type(other) == "table" and type(other.q) == "table" and other or nil
end

-- A normal 3.3.5 client cannot tell a desktop process that PlaySoundFile was
-- called.  CatQuestCompanion uses a small screen-pixel side channel instead:
-- the companion addon draws a short-lived encoded frame and the console
-- client reads it from the screen.  Keep this separate from BridgeReady so an
-- installed local cache still wins for tracks that are already on disk.
local function CompanionBridge()
    local bridge = CatQuest335Companion
    if CatQuest335_CompanionReady and type(bridge) == "table"
        and type(bridge.Send) == "function" and type(bridge.Stop) == "function" then
        return bridge
    end
end

ns.CompanionBridge = CompanionBridge

local function PackCandidates()
    local selected = ns.db.pack or "auto"
    local voiceLocale = ns.VoiceLocale()
    local result = {}
    for i = 1, #VOICE_PACKS do
        local descriptor = VOICE_PACKS[i]
        local pack = _G[descriptor.globalName]
        if (selected == "auto" or selected == descriptor.key) and pack and pack.quests
            and (descriptor.locale or "ruRU") == voiceLocale then
            result[#result + 1] = {
                pack = pack,
                folder = descriptor.folder,
                key = descriptor.key,
            }
        end
    end
    return result
end

local function HasVoiceData()
    local candidates = PackCandidates()
    if candidates[1] then
        return candidates[1].pack, candidates[1].folder
    end
end

local function GetQuestData(questID)
    questID = tonumber(questID)
    local candidates = PackCandidates()
    for i = 1, #candidates do
        local candidate = candidates[i]
        local quest = candidate.pack.quests[questID]
        if quest then
            return quest, candidate.folder
        end
    end
    return nil, nil
end

local function IsFemale()
    return UnitSex and UnitSex("player") == 3
end

local function SelectVariant(track)
    if not track then
        return nil, nil
    end

    local cues = track.c
    if not cues then
        return nil, nil
    end

    if IsFemale() and cues.f then
        return cues.f, "_f"
    end

    if not IsFemale() and cues.m then
        return cues.m, "_m"
    end

    if cues.x then
        return cues.x, ""
    end

    if cues.m then
        return cues.m, "_m"
    end

    if cues.f then
        return cues.f, "_f"
    end

    return nil, nil
end

local function CreatureIDFromUnit(unit)
    if UnitCreatureID then
        local id = tonumber(UnitCreatureID(unit))
        if id and id > 0 then
            return id
        end
    end
    local guid = UnitGUID and UnitGUID(unit) or nil
    if type(guid) ~= "string" then
        return nil
    end
    local hex = string.match(guid, "^0[xX](%x+)$")
    if hex then
        -- WotLK 3.3.5 creature GUIDs store the NPC ID in hex digits
        -- 7..10 after the 0x prefix (the 3.3.0 layout).
        local id = tonumber(string.sub(hex, 7, 10), 16)
        if id and id > 0 then
            return id
        end
    else
        local creatureID = string.match(guid, "^[^%-]+%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)%-")
        local id = tonumber(creatureID)
        if id and id > 0 then
            return id
        end
    end
end

ns.CreatureIDFromUnit = CreatureIDFromUnit

local function QuestNpcID(questID, kind, explicitID)
    local id = tonumber(explicitID) or CreatureIDFromUnit("npc")
    if id and id > 0 then
        return id
    end
    questID = tonumber(questID)
    if kind == "turnin" then
        return CatQuest335QuestFinisher and CatQuest335QuestFinisher[questID]
    end
    return CatQuest335QuestGiver and CatQuest335QuestGiver[questID]
end

ns.QuestNpcID = QuestNpcID

local function GetTrackData(questID, kind, npcID)
    questID = tonumber(questID)
    local candidates = PackCandidates()
    for i = 1, #candidates do
        local candidate = candidates[i]
        local quest = candidate.pack.quests[questID]
        local track = quest and (kind == "turnin" and quest.t or quest)
        local npcSuffix = ""
        if track and npcID and track.npc then
            local npcTrack = track.npc[tonumber(npcID)]
            if npcTrack then
                track = npcTrack
                npcSuffix = "_n" .. tostring(npcID)
            end
        end
        local cues, genderSuffix = SelectVariant(track)
        -- Empty 0.1-second entries are manifest placeholders, not local audio.
        if cues and (#cues > 0 or (tonumber(track.d) or 0) > 0.1) then
            return quest, candidate.folder, track, cues, genderSuffix, npcSuffix, npcID
        end
    end
    return nil, nil, nil, nil, nil, "", npcID
end

-- The story window and playback use the same pack selection. Server tracks
-- are requested on demand; their IDs need not occur in the old Codex index.
function ns.CanPlayQuest(questID, kind)
    questID = tonumber(questID)
    if not questID then return false end
    kind = kind or "quest"
    local npcID = kind == "turnin" and CatQuest335QuestFinisher and CatQuest335QuestFinisher[questID]
        or CatQuest335QuestGiver and CatQuest335QuestGiver[questID]
    local _, _, _, cues = GetTrackData(questID, kind, npcID)
    if cues then return true end
    if not ns.db.remoteEnabled or CatQuest335_LocalMode then return false end
    local ready = CatQuest335_BridgeReady
    if type(ready) == "table" and ready.mode == "local" then
        if CompanionBridge() then return true end
        local info = BridgeInfo(ns.VoiceLocale())
        local bits = info and tonumber(info.q[questID]) or 0
        local flag = kind == "turnin" and 2 or 1
        return math.floor(bits / flag) % 2 == 1
    end
    return true
end

local function Utf8Len(text)
    local _, count = string.gsub(text or "", "[^\128-\191]", "")
    return count
end

-- 3.3.5 cannot tell when a sound ends, so a server track gets an estimate
-- from the quest text: about 14 characters per second, 4.5 for CJK.
local function EstimateDuration(text)
    local cap = tonumber(ns.db.remoteDuration) or 90
    local chars = Utf8Len(text)
    if chars == 0 then
        return math.min(30, cap)
    end
    local locale = ns.VoiceLocale()
    local rate = (locale == "zhCN" or locale == "zhTW" or locale == "koKR") and 4.5 or 14
    return math.max(3, math.min(cap, chars / rate + 1.5))
end

local function QuestTextFor(event, kind)
    local text
    if event == "QUEST_PROGRESS" and GetProgressText then
        text = GetProgressText()
    elseif event == "QUEST_COMPLETE" and GetRewardText then
        text = GetRewardText()
    elseif kind == "quest" and GetQuestText then
        text = GetQuestText()
    end
    if (not text or text == "") and GetQuestLogQuestText then
        local description = GetQuestLogQuestText()
        text = description
    end
    if text and text ~= "" then
        return text
    end
end

-- Subtitle pages: the window shows about four lines, so long quest text is
-- split into pages that follow the speech. Budgets are in characters for the
-- client's font: CJK glyphs are about twice as wide.
local SENTENCE_END = { ["."] = true, ["!"] = true, ["?"] = true, ["…"] = true,
    ["。"] = true, ["！"] = true, ["？"] = true }

local function PageBudget()
    local locale = ns.ClientLocale()
    if locale == "zhCN" or locale == "zhTW" or locale == "koKR" then
        return 90
    end
    return 210
end

local function SplitPages(text, budget)
    text = string.gsub(text or "", "%s+", " ")
    local pages, page, length = {}, {}, 0
    local function Flush()
        if length > 0 then
            pages[#pages + 1] = (string.gsub(table.concat(page), "^%s+", ""))
        end
        page, length = {}, 0
    end
    -- Walk UTF-8 characters; break at a space or after a sentence end.
    local lastSpace = nil
    for char in string.gmatch(text, "[\1-\127\194-\244][\128-\191]*") do
        page[#page + 1] = char
        length = length + 1
        if char == " " then
            lastSpace = #page
        end
        if SENTENCE_END[char] and length >= budget * 0.6 then
            Flush()
            lastSpace = nil
        elseif length >= budget then
            if lastSpace and lastSpace > 1 then
                -- Move the unfinished word to the next page.
                local rest = {}
                for i = lastSpace + 1, #page do
                    rest[#rest + 1] = page[i]
                end
                for i = #page, lastSpace, -1 do
                    page[i] = nil
                end
                length = lastSpace - 1
                Flush()
                page, length = rest, #rest
            else
                Flush()
            end
            lastSpace = nil
        end
    end
    Flush()
    return pages
end

-- Each page starts at a time proportional to the text spoken before it.
local function TextCues(pages, duration)
    local total = 0
    for i = 1, #pages do
        total = total + Utf8Len(pages[i])
    end
    local cues, before = {}, 0
    for i = 1, #pages do
        cues[i] = { total > 0 and duration * before / total or 0, pages[i] }
        before = before + Utf8Len(pages[i])
    end
    return cues
end

local function CuesHaveText(cues)
    for i = 1, #(cues or {}) do
        if cues[i][2] and cues[i][2] ~= "" then
            return true
        end
    end
    return false
end

ns.SplitPages = SplitPages

-- Description of a quest in the player's log, read without changing the
-- log selection. Fills subtitles when a quest is voiced outside its dialog
-- (after accepting it, from the map or the zone story).
local function QuestLogText(questID)
    if not questID or not GetNumQuestLogEntries or not SelectQuestLogEntry or not GetQuestLogQuestText then
        return nil
    end
    for index = 1, GetNumQuestLogEntries() do
        local count = select("#", GetQuestLogTitle(index))
        local values = { GetQuestLogTitle(index) }
        if count >= 9 and values[9] == questID then
            local previous = GetQuestLogSelection and GetQuestLogSelection() or 0
            SelectQuestLogEntry(index)
            local description = GetQuestLogQuestText()
            SelectQuestLogEntry(previous)
            if description and description ~= "" then
                return description
            end
            return nil
        end
    end
end
ns.QuestLogText = QuestLogText

local function BuildItem(questID, kind, text, titleOverride, npcID)
    questID = tonumber(questID)
    if (not text or text == "") and kind == "quest" then
        text = QuestLogText(questID)
    end
    npcID = QuestNpcID(questID, kind, npcID)
    local quest, packFolder, track, cues, genderSuffix, npcSuffix = GetTrackData(questID, kind, npcID)
    local remote = false
    if not cues then
        if not ns.db.remoteEnabled or CatQuest335_LocalMode then
            return nil
        end
        remote = true
        packFolder = "CatQuest335_ServerVoices\\" .. ns.VoiceLocale()
        local known = CatQuest335Story and CatQuest335Story.durations
            and CatQuest335Story.durations[questID]
        local seconds = known and ns.VoiceLocale() == "ruRU"
            and (kind == "turnin" and known[2] or known[1]) or 0
        -- Lasthavens: real lengths of generated tracks from the extension
        -- (Bridge.lua); a generated track replaces the pack one on the server.
        local bridge = BridgeInfo(ns.VoiceLocale())
        local real = bridge and type(bridge.d) == "table" and bridge.d[questID]
        if type(real) == "table" then
            local value = tonumber(kind == "turnin" and real[2] or real[1]) or 0
            if value > 0 then
                seconds = value
            end
        end
        track = { e = "ogg", d = seconds > 0 and seconds or EstimateDuration(text), v = "server" }
        cues = {}
        genderSuffix = ""
        -- Server tracks are published under the manifest-safe base name
        -- (<quest>.ogg / <quest>_t.ogg).  Adding the local NPC id here makes
        -- map/list playback ask for an unlisted <quest>_n<npc>.ogg file;
        -- PlaySoundFile may still return a handle, leaving the subtitle bar
        -- running while no audio is ever read.  NPC-specific variants remain
        -- supported for local voice packs above; generated server tracks use
        -- the stable base path.
        npcSuffix = ""
        quest = {}
    end

    local fileName = tostring(questID)
    if kind == "turnin" then
        fileName = fileName .. "_t"
    end
    fileName = fileName .. npcSuffix
    fileName = fileName .. genderSuffix .. "." .. (track.e or "ogg")
    local relativePath = track.p or ("Sounds\\q\\" .. fileName)
    relativePath = string.gsub(relativePath, "/", "\\")

    -- Closed NPC dialogs keep their last GetTitleText value. Prefer the
    -- quest log's ID-matched title rather than the last NPC quest's title.
    local title = titleOverride or quest.title
    if (not title or title == "") and GetNumQuestLogEntries and GetQuestLogTitle then
        for index = 1, GetNumQuestLogEntries() do
            -- Returns can contain nil (quest tag, completion), so # is unreliable.
            local values = { GetQuestLogTitle(index) }
            if values[9] == questID then
                title = values[1]
            end
        end
    end
    if (not title or title == "") and ns.state.dialogQuest == questID and GetTitleText then
        title = GetTitleText()
    end
    if title == "" then
        title = nil
    end

    return {
        questID = questID,
        kind = kind,
        key = tostring(questID) .. ":" .. kind .. ":" .. ns.VoiceLocale() .. ":" .. tostring(npcID or 0),
        file = "Interface\\AddOns\\" .. packFolder .. "\\" .. relativePath,
        cues = cues,
        duration = tonumber(track.d) or 0,
        voice = track.v,
        npc = track.n,
        npcID = npcID,
        title = title or string.format(L.QUEST_N, tostring(questID)),
        remote = remote,
        dialog = ns.state.dialogQuest == questID,
        text = text,
        pages = text and SplitPages(text, PageBudget()) or nil,
        cueIndex = 0,
    }
end

local function Remember(item)
    local history = ns.db.history
    history[#history + 1] = {
        questID = item.questID,
        kind = item.kind,
        title = item.title,
        at = time(),
    }
    while #history > 50 do
        table.remove(history, 1)
    end
end

local function RememberMissing(questID, kind)
    ns.db.missing = ns.db.missing or {}
    local key = tostring(questID) .. ":" .. tostring(kind)
    if not ns.db.missing[key] then
        ns.db.missing[key] = {
            questID = tonumber(questID),
            kind = kind,
            at = time(),
        }
    end
end

local function SoundChannel()
    -- File-based bridge markers need a sound channel even in Music mode.
    return ns.db.volumeChannel == "Music" and "SFX" or (ns.db.volumeChannel or "SFX")
end

local function CallPlaySound(path)
    local channel = SoundChannel()
    local ok, result = pcall(PlaySoundFile, path, channel)
    -- The original 3.3.5a API may return nothing even when playback starts.
    -- Local pack tracks were selected from its index; nil is not a reason to
    -- play the same file a second time on SFX.
    if ok and result ~= false then
        return channel
    end

    return nil
end

-- Settings from the original CatQuest: duck music and ambience while a line
-- plays, and keep sound on when the game window is in the background. The
-- old values are saved in the DB, so a reload in the middle restores them.
local function SafeGetCVar(name)
    local ok, value = pcall(GetCVar, name)
    if ok and value ~= nil then
        return tostring(value)
    end
end

local function RestoreMusicVoice()
    ns.state.musicPlaying = nil
    local saved = ns.db.musicSaved
    ns.db.musicSaved = nil
    if saved and SetCVar then
        for name, value in pairs(saved) do
            pcall(SetCVar, name, value)
        end
    end
end

local function StopMusicVoice()
    if not ns.state.musicPlaying then
        return
    end
    -- In 3.3.5 StopMusic fades scripted music. Replacing it first cuts the
    -- voice immediately; this deliberately absent path is never played.
    pcall(PlayMusic, "Interface\\AddOns\\CatQuest\\Sounds\\stop-voice.wav")
    pcall(StopMusic)
    RestoreMusicVoice()
end

local function CallPlayMusic(path)
    if not PlayMusic or not StopMusic or not GetCVar or not SetCVar then
        return nil
    end
    ns.RestoreSoundTweaks()
    ns.db.musicSaved = {
        Sound_EnableMusic = SafeGetCVar("Sound_EnableMusic") or "1",
        Sound_MusicVolume = SafeGetCVar("Sound_MusicVolume") or "1",
    }
    -- Music may be disabled or turned down by the player. Restore both values
    -- after this voice, including when /reload happens during playback.
    pcall(SetCVar, "Sound_EnableMusic", "1")
    pcall(SetCVar, "Sound_MusicVolume", "1")
    local ok = pcall(PlayMusic, path)
    if not ok then
        RestoreMusicVoice()
        return nil
    end
    ns.state.musicPlaying = true
    return "Music"
end

local function ApplySoundTweaks()
    if ns.state.tweaked or not GetCVar or not SetCVar then
        return
    end
    ns.state.tweaked = true
    local saved = {}
    local duck = tonumber(ns.db.duck) or 0
    if duck > 0 then
        local cvars = {}
        if not (ns.state.active and ns.state.active.playChannel == "Music") then
            cvars[#cvars + 1] = "Sound_MusicVolume"
        end
        if not (ns.state.active and ns.state.active.playChannel == "Ambience") then
            cvars[#cvars + 1] = "Sound_AmbienceVolume"
        end
        for i = 1, #cvars do
            local value = SafeGetCVar(cvars[i])
            if tonumber(value) then
                saved[cvars[i]] = value
                pcall(SetCVar, cvars[i], string.format("%.2f", tonumber(value) * (1 - math.min(duck, 100) / 100)))
            end
        end
    end
    if ns.db.keepInBackground then
        local value = SafeGetCVar("Sound_EnableSoundWhenGameIsInBG")
        if value and value ~= "1" then
            saved.Sound_EnableSoundWhenGameIsInBG = value
            pcall(SetCVar, "Sound_EnableSoundWhenGameIsInBG", "1")
        end
    end
    if next(saved) then
        ns.db.soundSaved = saved
    end
end

local function RestoreSoundTweaks()
    ns.state.tweaked = nil
    local saved = ns.db.soundSaved
    if not saved then
        return
    end
    ns.db.soundSaved = nil
    if SetCVar then
        for name, value in pairs(saved) do
            pcall(SetCVar, name, value)
        end
    end
end
ns.RestoreSoundTweaks = RestoreSoundTweaks

local function BeginPlaying(item)
    item.phase = "playing"
    item.startedAt = GetTime()
    item.cueIndex = 0
    ns.state.active = item
    ns.state.lastAudioChannel = item.playChannel or ns.db.volumeChannel or "SFX"
    if item.playChannel == "Music" and (tonumber(item.duration) or 0) <= 0 then
        item.duration = EstimateDuration(item.text)
    end
    ns.state.demandShown = nil
    ns.state.lastItem = item
    ns.state.lastPlayedKey = item.key
    ns.state.lastPlayedAt = item.startedAt
    VoiceLog(item, "playing", item.bridgeVerified and "server-ready" or item.companion and "companion" or "local/manifest")
    Remember(item)
    ApplySoundTweaks()

    if ns.ShowHead then
        ns.ShowHead(item)
    end
    -- Tracks without their own subtitle text page through the quest text.
    if not CuesHaveText(item.cues) and item.pages and item.pages[1] then
        item.cues = TextCues(item.pages, item.duration)
    end
    -- Show the first cue at once instead of a blank frame.
    local first = item.cues and item.cues[1]
    if first and (tonumber(first[1]) or 0) <= 0 and ns.SetSubtitle then
        ns.SetSubtitle(first[2] or "")
        item.cueIndex = 1
    end
    if ns.ShowQueueStatus then
        ns.ShowQueueStatus(#ns.state.queue)
    end
end

-- A server track may not exist yet: the first read asks the browser bridge
-- to fetch it, later reads find it in the bridge cache. Retry until timeout.
-- The first loading track keeps its place in the queue. Later tracks must
-- not issue playback reads until it starts or times out.
ns.state.pending = ns.state.pending or {}

local function ReadyFontEnabled(item)
    local ready = CatQuest335_BridgeReady
    return item.demandAudio and type(ready) == "table" and ready.fontReady == 1
        and ready.mode ~= "local"
end

local function PrefetchSignalEnabled(item)
    local ready = CatQuest335_BridgeReady
    return item.readySignalPath and type(ready) == "table"
        and (tonumber(ready.prefetchSignal) or 0) >= 1 and ready.fontReady == 1 and ready.mode ~= "local"
end

-- The last glyph can contribute its ink bounds instead of its hmtx advance.
-- Keep that last glyph identical and calibrate two fixed advances (M=1em,
-- N=10em). Subtraction removes both the terminal bounds and fixed padding.
local function MeasureReadyDuration(item, measure)
    local widths = {}
    item.readySignalError = nil
    item.readyFontUnit, item.readyFontWidths = nil, nil
    item.readyFontMetrics = tonumber(CatQuest335_BridgeReady and CatQuest335_BridgeReady.readyMetrics) or 1
    local function width(text)
        local ok, observed = pcall(function() measure:SetText(text); return measure:GetStringWidth() end)
        local result = ok and tonumber(observed) or nil
        if not result or result ~= result or result == math.huge or result < 0 then
            item.readySignalError = "width(" .. text .. ") failed: " .. tostring(observed)
            return nil
        end
        widths[#widths+1] = text .. ":" .. string.format("%.4f", result)
        return result
    end
    local function fail(reason)
        item.readyFontWidths = table.concat(widths, " ")
        item.readySignalError = item.readySignalError or reason
        VoiceLog(item, "font-invalid", item.readySignalError)
        return nil
    end
    local unit, low, span
    if item.readyFontMetrics >= 2 then
        -- M alone is retained in diagnostics to identify terminal-ink widths.
        if not width("M") then return fail("missing terminal width") end
        low = width("MM")
        local high = width("NM")
        if not low or not high then return fail("missing calibration") end
        span = high-low
        if span <= 0 then return fail("calibration span <= 0") end
        unit = span/9
    else
        unit = width("M")
    end
    item.readyFontUnit = unit
    if not unit or unit <= 0 then return fail("calibration unit <= 0") end
    local deciseconds = 0
    for _, char in ipairs({"A","B","C","D"}) do
        local measured = width(item.readyFontMetrics >= 2 and (char .. "M") or char)
        if not measured then return fail("missing digit " .. char) end
        local raw = item.readyFontMetrics >= 2 and ((measured-low)/unit) or (measured/unit-1)
        local digit = math.floor(raw+0.5)
        if digit < 0 or digit > 9 or math.abs(raw-digit) > 0.20 then
            return fail("invalid digit " .. char .. "=" .. string.format("%.4f",raw))
        end
        deciseconds = deciseconds*10+digit
    end
    item.readyFontWidths = table.concat(widths, " ")
    if deciseconds <= 0 then
        if item.readyFontMetrics >= 2 and CatQuest335_BridgeReady.waitingFont == 1 then
            VoiceLog(item, "font-waiting", "локальный сигнал: аудио ещё не загружено")
            return nil
        end
        return fail("decoded duration is zero")
    end
    return deciseconds/10+0.25
end

local function ConfirmPrefetchSignal(item)
    if not PrefetchSignalEnabled(item) then return false end
    if item.prefetchReady then return true end
    -- Even a local ready-signal font is a synchronous virtual-file lookup in
    -- the 3.3.5 client. Never probe it from every queue tick: the extension
    -- fetch is async, so an increasing retry interval avoids render freezes.
    local now = GetTime()
    if now < (item.nextReadySignalAt or 0) then return false end
    -- SetFont performs a synchronous virtual-file lookup in 3.3.5.  The
    -- bridge has already started the async fetch; probing immediately only
    -- adds a visible hitch while the file is guaranteed to be absent.  Defer
    -- the first probe and serialize later probes across all queued items.
    if not item.readySignalAttempts then
        item.readySignalAttempts = 1
        item.nextReadySignalAt = now + 8
        VoiceLog(item, "font-waiting", "первичная проверка отложена, чтобы не блокировать кадр")
        return false
    end
    if now < (ns.state.readySignalProbeAt or 0) then return false end
    local attempt = (tonumber(item.readySignalAttempts) or 0) + 1
    item.readySignalAttempts = attempt
    local delays = CatQuest335_BridgeReady.waitingFont == 1 and {2,4,8,15,30} or {6,10,18,30,45}
    item.nextReadySignalAt = now + delays[math.min(attempt, #delays)]
    ns.state.readySignalProbeAt = now + 8
    if not ns.state.prefetchSignalFont then
        ns.state.prefetchSignalFont = CreateFont("CatQuest335PrefetchSignalFont")
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:Hide()
        ns.state.prefetchSignalMeasure = frame:CreateFontString(nil, "OVERLAY")
        if GameFontNormal then
            ns.state.prefetchSignalMeasure:SetFontObject(GameFontNormal)
        end
    end
    local font = ns.state.prefetchSignalFont
    -- Missing files may be cached by the client. Each probe needs a fresh path.
    local path = item.readySignalPath
    if (tonumber(CatQuest335_BridgeReady.prefetchSignal) or 0) >= 2 then
        if attempt > 16 then return false end
        path = string.gsub(path, "%.ttf$", "\\" .. attempt .. ".ttf")
    end
    item.readyFontRequested = path
    VoiceLog(item, "font-probe", path)
    local clock = type(debugprofilestop) == "function" and debugprofilestop or function() return GetTime()*1000 end
    local probeStarted = clock()
    local ok = pcall(font.SetFont, font, path, 12)
    local actual = ok and font:GetFont()
    item.readyFontObserved = actual
    local function canonical(path) return string.lower((string.gsub(path or "", "\\", "/"))) end
    if type(actual) ~= "string" or canonical(actual) ~= canonical(path) then
        VoiceLog(item, "font-missing", string.format("SetFont ok=%s; %.0f ms; observed=%s", tostring(ok), clock()-probeStarted, tostring(actual)))
        return false
    end
    local measure = ns.state.prefetchSignalMeasure
    -- Bind only after the FontObject actually loaded. Never measure an
    -- uninitialised FontString: the client raises "Font not set" on SetText.
    local bound, bindError = pcall(measure.SetFontObject, measure, font)
    if not bound then
        item.readySignalError = tostring(bindError)
        VoiceLog(item, "font-invalid", item.readySignalError)
        return false
    end
    local duration = MeasureReadyDuration(item, measure)
    if not duration then return false end
    item.prefetchReady = true
    item.bridgeVerified = true
    item.duration = duration
    VoiceLog(item, "font-ready", string.format("duration=%.2f; unit=%.3f; %.0f ms", item.duration, item.readyFontUnit, clock()-probeStarted))
    return true
end

-- SetFont is the only reliable readiness acknowledgement in the browser
-- client, but on 3.3.5 it performs a synchronous virtual-file read. A
-- two-second retry therefore freezes the game every time the server is still
-- generating a track. The first read starts the request immediately; later
-- reads back off so waiting for a long TTS job does not turn into a stutter.
local READY_FONT_RETRY_DELAYS = { 8, 15, 30 }

local function ConfirmRemoteReady(item)
    local ready = CatQuest335_BridgeReady
    if ns.db.readyFontPage ~= ready.contactPage then
        ns.db.readyFontPage, ns.db.readyFontAliases, ns.db.readyFontPoll = ready.contactPage, {}, 0
    end
    ns.state.verifiedAudio = ns.state.verifiedAudio or {}
    local verified = ns.state.verifiedAudio[item.file]
    if verified then
        item.duration, item.bridgeVerified = verified, true
        return true
    end
    local now = GetTime()
    if now < (item.nextReadyFontAt or 0) then return false end
    local attempt = (tonumber(item.readyFontAttempts) or 0) + 1
    item.readyFontAttempts = attempt
    local delay = READY_FONT_RETRY_DELAYS[math.min(attempt, #READY_FONT_RETRY_DELAYS)]
    item.nextReadyFontAt = now + delay
    local root = "Interface\\AddOns\\CatQuest335_ServerVoices\\ready\\"
    local path
    if not item.readyFontPath then
        local aliases = ns.db.readyFontAliases or {}
        ns.db.readyFontAliases = aliases
        local n = (tonumber(aliases[item.file]) or 0) + 1
        if n > 4 then
            if not item.readyReloadHinted then Print(L.BRIDGE_NEEDS_RELOAD); item.readyReloadHinted = true end
            return false
        end
        aliases[item.file] = n
        local slot = string.match(item.file, "\\gossip\\(%d+)%.ogg$")
        path = slot and (root .. "gossip\\" .. slot .. "\\" .. n .. ".ttf")
            or (root .. ns.VoiceLocale() .. "\\q\\" .. item.questID .. "_"
                .. (item.kind == "turnin" and "COMPLETE" or "DETAIL") .. "\\" .. n .. ".ttf")
        item.readyFontPath = path
    else
        local n = (tonumber(ns.db.readyFontPoll) or 0) + 1
        if n > 2048 then
            if not item.readyReloadHinted then Print(L.BRIDGE_NEEDS_RELOAD); item.readyReloadHinted = true end
            return false
        end
        ns.db.readyFontPoll = n
        path = root .. "poll\\" .. n .. ".ttf"
    end
    if not ns.state.readyFont then
        ns.state.readyFont = CreateFont("CatQuest335ReadinessFont")
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:Hide()
        ns.state.readyMeasure = frame:CreateFontString(nil, "OVERLAY")
        ns.state.readyMeasure:SetFontObject(ns.state.readyFont)
    end
    local font, measure = ns.state.readyFont, ns.state.readyMeasure
    item.readyFontRequested = path
    local ok = pcall(font.SetFont, font, path, 12)
    local actual = ok and font:GetFont()
    item.readyFontObserved = actual
    local function canonical(p) return string.lower((string.gsub(p or "", "\\", "/"))) end
    if type(actual) ~= "string" or canonical(actual) ~= canonical(path) then return false end
    local duration = MeasureReadyDuration(item, measure)
    if not duration then return false end
    item.duration, item.bridgeVerified = duration, true
    ns.state.verifiedAudio[item.file] = item.duration
    return true
end

local function TryPlay(item, skipReadiness)
    local asyncBridge = item.readySignalPath and type(CatQuest335_BridgeReady) == "table"
        and (tonumber(CatQuest335_BridgeReady.prefetchSignal) or 0) >= 1
    if not skipReadiness and asyncBridge then
        if not ConfirmPrefetchSignal(item) then return false end
    elseif not skipReadiness and ReadyFontEnabled(item) and not ConfirmRemoteReady(item) then
        return false
    end
    if ns.db.volumeChannel == "Music" and (not item.demandAudio or item.bridgeVerified) then
        VoiceLog(item, "play-call", "PlayMusic; слышимость не подтверждена")
        item.playChannel = CallPlayMusic(item.file)
        if not item.playChannel then VoiceLog(item, "play-failed", "PlayMusic failed/unavailable") end
        if item.playChannel and item.remote and item.demandAudio then
            VoiceLog(item, "ready", "server confirmed readiness")
        end
        return item.playChannel ~= nil
    end
    item.playChannel = SoundChannel()
    -- One call per attempt: every miss is a file read that reaches the bridge.
    VoiceLog(item, "play-call", "PlaySoundFile " .. SoundChannel())
    local ok, result = pcall(PlaySoundFile, item.file, SoundChannel())
    if not ok or result == false then VoiceLog(item, "play-failed", "ok=" .. tostring(ok) .. " result=" .. tostring(result)) end
    local ready = CatQuest335_BridgeReady
    if item.bridgeVerified or (type(ready) == "table" and ready.mode == "local") then
        -- The local manifest established that this file is installed; the
        -- original client does not have a useful success return value.
        if ok and result ~= false and item.remote and item.demandAudio then
            VoiceLog(item, "ready", "server confirmed readiness")
        end
        return ok and result ~= false
    end
    -- Lasthavens' virtual filesystem uses a truthy result to signal a ready
    -- read. Preserve that distinction for online retries.
    if ok and result and item.remote and item.demandAudio then
        VoiceLog(item, "ready", "server confirmed readiness")
    end
    return ok and result
end

-- Request a completion track as soon as a quest is accepted, but do not put
-- it in the playback queue.  The readiness-font handshake asks the browser
-- bridge/backend for the file without audible playback; when the quest is
-- later turned in, the normal COMPLETE path can start immediately.
function ns.PrefetchQuestCompletion(questID, title, npcID)
    questID = tonumber(questID)
    if not questID or not ns.db.enabled or not ns.db.auto or not ns.db.remoteEnabled
        or CatQuest335_LocalMode then
        return false
    end
    ns.state.prefetch = ns.state.prefetch or {}
    local key = tostring(questID) .. ":COMPLETE:" .. ns.VoiceLocale()
    if ns.state.prefetch[key] then
        return false
    end
    local item = BuildItem(questID, "turnin", false, title, npcID)
    if not item or not item.remote then
        return false
    end
    ns.state.prefetch[key] = GetTime()
    item.demandAudio = true
    if ns.RequestVoicePrefetch(item) then
        VoiceLog(item, "preload", "фоновая COMPLETE; воспроизведение не запрашивалось")
        VoiceLog(item, "requested", "предзагрузка COMPLETE отправлена асинхронно")
        return true
    end
    -- Older bridges cannot probe a remote file without playing it. Do not
    -- start the completion line early; the normal turn-in request remains a
    -- safe fallback and the diagnostic log records why prefetch was skipped.
    VoiceLog(item, "error", "предзагрузка ждёт readiness-мост расширения")
    return false
end

local function FindPending(key)
    for i = 1, #ns.state.pending do
        if ns.state.pending[i].key == key then
            return i
        end
    end
end

local function AddPending(item, quiet)
    item.phase = "pending"
    item.requestedAt = GetTime()
    ns.state.pending[#ns.state.pending + 1] = item
    VoiceLog(item, "waiting", "дорожка ещё не готова")
    if not quiet then
        Print(string.format(L.REQUESTED, item.title or tostring(item.questID)))
    end
end

-- Lasthavens: the browser extension lists the tracks ready on the server in
-- Bridge.lua. PlaySoundFile reports success there before the file is read,
-- so a quest missing from the list is still to be voiced: the extension waits
-- for the server inside that first read and the voice starts by itself. No
-- head window then, since its bar would run long before the voice starts.
-- "ready": the server has the track; "demand": it is voiced on request in
-- this page load; "reload": the language was switched in game (/cq lang)
-- after the page loaded, and requests for it work only after F5; nil: no
-- information (not Lasthavens, or an older extension).
local function IsQuestItem(item)
    return item.kind == "quest" or item.kind == "turnin"
end

local function TrackState(item)
    local ready = CatQuest335_BridgeReady
    local companion = CompanionBridge()
    -- BridgeReady.q contains quest tracks only. Books and place lore are
    -- already listed separately in the extension manifest and must use the
    -- normal queue; treating them as on-demand quest tracks lets their audio
    -- start outside ns.state.active and overlap the next line.
    if not item.remote then
        return nil
    end
    -- The console client writes a real local addon and marks its manifest as
    -- local. There is no browser bridge to receive an on-demand read, so a
    -- missing local file must fail immediately instead of entering the
    -- Lasthavens retry/poll loop.
    if type(ready) == "table" and ready.mode == "local" then
        if IsQuestItem(item) then
            local info = BridgeInfo(ns.VoiceLocale())
            local bit = item.kind == "turnin" and 2 or 1
            local have = info and type(info.q) == "table" and tonumber(info.q[item.questID]) or 0
            return math.floor(have / bit) % 2 == 1 and "ready"
                or (companion and "companion" or "missing")
        end
        if item.kind == "book" or item.kind == "place" then
            local hash = string.match(item.key or "", "^[^:]+:([0-9a-fA-F]+)")
            local books = ready.b
            return hash and type(books) == "table" and books[string.lower(hash)]
                and "ready" or (companion and "companion" or "missing")
        end
        return companion and "companion" or "missing"
    end
    if type(ready) ~= "table" then
        return companion and "companion" or nil
    end
    if item.kind == "book" or item.kind == "place" then
        local hash = string.match(item.key or "", "^[^:]+:([0-9a-fA-F]+)")
        local books = ready.b
        return hash and type(books) == "table" and books[string.lower(hash)]
            and "ready" or (companion and "companion" or nil)
    end
    if not IsQuestItem(item) then
        return nil
    end
    local locale = ns.VoiceLocale()
    local info = BridgeInfo(locale)
    if ready.locale ~= locale and type(ready.others) ~= "table" then
        return nil
    end
    local bit = item.kind == "turnin" and 2 or 1
    local have = info and tonumber(info.q[item.questID]) or 0
    if math.floor(have / bit) % 2 == 1 then
        return "ready"
    end
    return ready.locale == locale and "demand" or "reload"
end
ns.TrackState = TrackState

local function CompanionField(value)
    return (tostring(value or ""):gsub("[\t\r\n]", " "))
end

local function CompanionText(value)
    value = tostring(value or "")
    value = string.gsub(value, "|c%x%x%x%x%x%x%x%x", "")
    value = string.gsub(value, "|r", "")
    value = string.gsub(value, "|n", "\n")
    return value
end

local function CompanionGender(item)
    local gender = item.npc and item.npc.gender or ""
    if gender ~= "male" and gender ~= "female" and UnitSex then
        local sex = UnitSex("npc")
        gender = sex == 3 and "female" or sex == 2 and "male" or ""
    end
    return gender
end

local function CompanionSpeak(item)
    local bridge = CompanionBridge()
    local text = CompanionText(item.text)
    if not bridge or text == "" then
        return false
    end
    local locale = ns.VoiceLocale()
    local npcID = item.npcID or (item.npc and item.npc.id) or 0
    local gender = CompanionGender(item)
    local title = CompanionField(item.title or "")
    local header
    if IsQuestItem(item) then
        local questType = item.kind == "turnin" and "COMPLETE" or "DETAIL"
        header = table.concat({
            "Q", CompanionField(item.kind), CompanionField(item.questID), questType,
            CompanionField(locale), CompanionField(npcID), CompanionField(gender), title,
        }, "\t")
    else
        header = table.concat({
            "G", CompanionField(locale), CompanionField(npcID), CompanionField(gender), title,
        }, "\t")
    end
    local ok, result = pcall(bridge.Send, header .. "\n" .. text)
    return ok and result ~= false
end

ns.CompanionSpeak = CompanionSpeak

local function IsOnDemand(item)
    return item.kind == "gossip" or item.kind == "npcLore" or TrackState(item) == "demand"
end
ns.IsOnDemand = IsOnDemand

-- While quests are being voiced, "play" a poll file now and then: the
-- extension answers with the first track that became ready (each one once)
-- and with a missing file otherwise. The game caches a played sound by its
-- file name, so every poll uses a new one: poll\<n>.ogg, n counts up (kept in
-- the saved settings, so /reload does not reuse names) and wraps at 2048.
-- Polls follow a request at these offsets (generation takes 10-30 s), only
-- when nothing else plays.
local POLL_SLOTS = 2048
-- How long the window shows a quest voiced on demand.
local DEMAND_WINDOW_SECONDS = 150
local POLL_OFFSETS = { 8, 14, 20, 27, 35, 45, 60, 80, 105, 135, 170, 210, 255, 300 }
-- PlayMusic loops at EOF on the 3.3.5 client. Keep a tiny post-roll so the
-- final syllable is not clipped, but do not leave the old 0.8 s repeat window.
local MUSIC_EOF_GRACE = 0.10

local function SchedulePolls()
    local now = GetTime()
    local times = ns.state.pollTimes or {}
    for i = 1, #POLL_OFFSETS do
        times[#times + 1] = now + POLL_OFFSETS[i]
    end
    table.sort(times)
    ns.state.pollTimes = times
end

local function ClearDemandWindow(item)
    if ns.state.demandShown ~= item then
        return
    end
    ns.state.demandShown = nil
    if not ns.state.active and #ns.state.queue == 0 and ns.HideHead then
        ns.HideHead()
    end
end

local function PollDemand(item)
    -- The async signal handshake never attempts a network-backed poll. Legacy
    -- audio polls remain available only for older browser extensions.
    if PrefetchSignalEnabled(item) or ReadyFontEnabled(item) then return end
    local times = ns.state.pollTimes
    local now = GetTime()
    if not item or ns.state.active or ns.state.pending[1] ~= item
        or not times or not times[1] or times[1] > now then
        return
    end
    -- Polls that came due together are one poll.
    while times[1] and times[1] <= now do
        table.remove(times, 1)
    end
    local n = (tonumber(ns.db.pollSeq) or 0) % POLL_SLOTS + 1
    ns.db.pollSeq = n
    local path = "Interface\\AddOns\\CatQuest335_ServerVoices\\poll\\" .. n .. ".ogg"
    -- PlayMusic has no readiness result. Dynamic generation keeps the
    -- existing file/poll transport until the bridge can acknowledge a start.
    local ok, result = pcall(PlaySoundFile, path, SoundChannel())
    local played = ok and result
    item.playChannel = SoundChannel()
    if played then
        table.remove(ns.state.pending, 1)
        BeginPlaying(item)
    end
end

local function StartItem(item)
    if item.valid and not item.valid() then return false end
    local trackState = item.remote and TrackState(item)
    if item.remote and trackState == "missing" then
        ns.state.lastItem = item
        VoiceLog(item, "error", "нет локальной дорожки")
        Print(string.format(L.NO_LOCAL_TRACK or L.NO_TRACK, tostring(item.questID),
            "https://t.me/warcraft_rus_chat"))
        return false
    end
    if item.remote and trackState == "companion" then
        if not CompanionSpeak(item) then
            ns.state.lastItem = item
            VoiceLog(item, "error", "компаньон не получил текст")
            Print("компаньон не получил текст для озвучки")
            return false
        end
        item.companion = true
        item.duration = tonumber(item.duration) or EstimateDuration(item.text)
        BeginPlaying(item)
        return true
    end
    if item.remote and trackState == "reload" then
        -- No silent window: say once per language what to do.
        local locale = ns.VoiceLocale()
        ns.state.reloadHinted = ns.state.reloadHinted or {}
        if not ns.state.reloadHinted[locale] then
            ns.state.reloadHinted[locale] = true
            Print(string.format(L.LANG_NEEDS_RELOAD, ns.LanguageName(locale)))
        end
        ns.state.lastItem = item
        VoiceLog(item, "error", "нужна перезагрузка страницы игры")
        return false
    end
    if item.remote and IsOnDemand(item) then
        item.demandAudio = true
        -- Keep the player informed while a generated track is on the server.
        -- This is also the visible Stop button for world-boss/NPC narration.
        ns.state.demandShown = item
        if ns.ShowDemand then
            ns.ShowDemand(item)
        end
        ns.state.manualRemoteRequests = ns.state.manualRemoteRequests or {}
        local requestedBefore = ns.state.manualRemoteRequests[item.key]
        if item.gossipAudioSlot then
            ns.RequestGossipPrefetch(item)
        else
            ns.RequestVoicePrefetch(item)
        end
        -- On-demand audio is deliberately manual now. The first click only
        -- requests it. A later click may start playback only after the
        -- readiness handshake confirms the VFS file. The old direct attempt
        -- bypassed that check, so a backend 404 was shown as playing while
        -- PlaySoundFile silently read a missing path.
        if requestedBefore and TryPlay(item) then
            -- A cached/generated track may already play even though the
            -- startup index still calls it on-demand. It owns the same slot
            -- as every other sound; do not start the rest of a chapter here.
            BeginPlaying(item)
            return true
        end
        ns.state.manualRemoteRequests[item.key] = GetTime()
        ns.state.manualRemoteBlocked = true
        ns.state.lastItem = item
        ns.state.lastPlayedKey = item.key
        ns.state.lastPlayedAt = GetTime()
        if CatQuest335_BridgeReady.budgetOut then
            -- The server would not voice it now. The request above still goes
            -- out, so a topped-up budget voices it after all.
            if not ns.state.budgetHinted then
                ns.state.budgetHinted = true
                Print(string.format(L.MANUAL_REVIEW or L.BUDGET_OUT,
                    item.title or tostring(item.questID)))
            end
            VoiceLog(item, "requested", "сервер сообщил об исчерпанном бюджете")
        else
            VoiceLog(item, "requested", "запрос отправлен на сервер")
            local requestedText = ns.db.remoteAutoRetry and L.REQUESTED or L.REQUESTED_MANUAL
            Print(string.format(requestedText, item.title or tostring(item.questID)))
        end
        if ns.db.remoteAutoRetry and not FindPending(item.key) then
            -- One server request, followed by local readiness checks. This
            -- does not submit another generation job on every poll.
            AddPending(item, true)
        end
        return false
    end
    if item.remote then
        -- The server manifest says that a track exists, but after an
        -- extension/game reload it may still be absent from the browser VFS.
        -- Do not call PlayMusic in that gap: PlayMusic can return normally
        -- while the file read is still being started, leaving a silent player
        -- window.  The ready-signal handshake also refreshes an already
        -- server-ready track into the current VFS session.
        local ready = CatQuest335_BridgeReady
        local needsVfsPrefetch = type(ready) == "table"
            and (tonumber(ready.prefetchSignal) or 0) >= 1
            and ready.mode ~= "local"
        if trackState ~= "ready" or needsVfsPrefetch then
            if IsQuestItem(item) then
                ns.RequestVoicePrefetch(item)
            end
            if (item.kind == "book" or item.kind == "place") then
                ns.RequestNarrationPrefetch(item)
            end
        end
        if TryPlay(item) then
            BeginPlaying(item)
            return true
        end
        -- Keep a server-ready item in the pending queue while the browser
        -- materializes the file in the current game VFS.  Without this, the
        -- item was removed immediately after the first PlayMusic race and a
        -- second click reused the client's cached failed read.
        if not item.demandAudio and not FindPending(item.key) then
            AddPending(item)
        else
            VoiceLog(item, "requested", "запрос отправлен на сервер")
        end
        ns.state.manualRemoteBlocked = true
        ns.state.manualRemoteRequests = ns.state.manualRemoteRequests or {}
        ns.state.manualRemoteRequests[item.key] = GetTime()
        return false
    end

    local channel
    if ns.db.volumeChannel == "Music" then
        channel = CallPlayMusic(item.file)
    else
        channel = CallPlaySound(item.file)
    end
    if not channel then
        if ns.state.active == item then
            ns.state.active = nil
        end
        if ns.HideHead then
            ns.HideHead()
        end
        Print(string.format(L.PLAY_FAILED, item.file))
        VoiceLog(item, "error", "PlaySoundFile не запустил файл")
        return false
    end

    item.playChannel = channel
    BeginPlaying(item)
    return true
end

-- NPC gossip is a free-form paragraph, not a quest: it has no quest ID and
-- therefore cannot use the quest track route. The browser bridge receives the
-- text through marker files and serves the generated track from gossip/<slot>.
local function BuildGossipItem(text, title, audioSlot, npc, kind, loreID)
    if not ns.db.remoteEnabled or CatQuest335_LocalMode
        or (not CompanionBridge() and (type(CatQuest335_BridgeReady) ~= "table"
            or CatQuest335_BridgeReady.mode == "local")) then
        return nil
    end
    text = string.gsub(tostring(text or ""), "%s+", " ")
    if text == "" or (not audioSlot and not CompanionBridge()) then
        return nil
    end
    local companionKey = 0
    if not audioSlot then
        for i = 1, #text do
            companionKey = (companionKey * 31 + text:byte(i)) % 2147483647
        end
        companionKey = tostring(companionKey)
    end
    local pages = SplitPages(text, PageBudget())
    local duration = EstimateDuration(text)
    return {
        questID = 0,
        kind = kind or "gossip",
        key = (kind == "npcLore" and "npcLore:" .. tostring(loreID or (npc and npc.id) or 0)
            or "gossip:" .. tostring(audioSlot or ("companion-" .. companionKey))) .. ":" .. ns.VoiceLocale(),
        file = "Interface\\AddOns\\CatQuest335_ServerVoices\\gossip\\"
            .. tostring(audioSlot) .. ".ogg",
        cues = TextCues(pages, duration),
        pages = pages,
        duration = duration,
        voice = "server",
        title = title or L.GOSSIP_TITLE,
        gossipAudioSlot = tonumber(audioSlot),
        npc = npc,
        npcLoreID = tonumber(loreID),
        remote = true,
        dialog = kind ~= "npcLore" and kind ~= "dungeon",
        text = text,
    }
end
ns.BuildGossipItem = BuildGossipItem

local nextPendingAt = 0
local READY_ATTEMPT_LIMIT = 8
local function ProcessPending()
    if ns.state.active then return end
    local pending = ns.state.pending
    local now = GetTime()
    if #pending == 0 or now < nextPendingAt then
        return
    end
    nextPendingAt = now + 1
    local limit = tonumber(ns.db.pendingTimeout) or 300
    for i = #pending, 1, -1 do
        local item = pending[i]
        if item.valid and not item.valid() then
            table.remove(pending, i)
        elseif item.remote and not item.prefetchReady
            and math.max(tonumber(item.readySignalAttempts) or 0,
                tonumber(item.readyFontAttempts) or 0) >= READY_ATTEMPT_LIMIT then
            local attempts = math.max(tonumber(item.readySignalAttempts) or 0,
                tonumber(item.readyFontAttempts) or 0)
            table.remove(pending, i)
            if ns.state.demandShown == item then ClearDemandWindow(item) end
            RememberMissing(item.questID, item.kind)
            VoiceLog(item, "timeout", string.format("готовность не подтверждена после %d проверок", attempts))
            Print(string.format(L.NOTICE_READY_RETRY or L.NOTICE_TIMEOUT,
                item.title or tostring(item.questID), attempts))
        elseif now - item.requestedAt >= limit then
            table.remove(pending, i)
            if ns.state.demandShown == item then ClearDemandWindow(item) end
            RememberMissing(item.questID, item.kind)
            VoiceLog(item, "timeout", string.format("сервер не ответил за %d с", math.floor(limit)))
            Print(string.format(L.MANUAL_REVIEW or L.NOTICE_TIMEOUT,
                item.title or tostring(item.questID)))
        end
    end
    if #pending == 0 then
        return
    end
    -- Do not let one slow server request block every track behind it. A ready
    -- item may overtake an older pending item; this is preferable to leaving
    -- the whole voice stream silent while one generation job is still running.
    for i = 1, #pending do
        local item = pending[i]
        if TryPlay(item) then
            table.remove(pending, i)
            BeginPlaying(item)
            return
        end
    end
    -- A fresh poll filename bypasses WoW's cached miss for the quest path. It
    -- belongs to the oldest waiting item, never an anonymous sound.
    if pending[1] then
        PollDemand(pending[1])
    end
end

local function StartNext()
    if ns.state.active or not ns.db.enabled then
        return
    end
    -- A short pause after each track so that lines never run into each other.
    if GetTime() < (ns.state.resumeAt or 0) then
        return
    end

    while not ns.state.active and ns.db.enabled do
        -- A reward line enters the FIFO immediately, even while the NPC's
        -- greeting delay is running. Later dialogs must not cancel/overtake it.
        local first=ns.state.queue[1]
        if first and GetTime() < (first.notBefore or 0) then return end
        local item = table.remove(ns.state.queue, 1)
        if not item then
            break
        end
        if StartItem(item) then
            return
        end
        -- A pending server item must not block later queue entries. ProcessPending
        -- will pick it up when it becomes ready, potentially after this item.
    end
    -- A quest being voiced on demand keeps its window (ns.ShowDemand).
    if not ns.state.active and not ns.state.demandShown and ns.HideHead then
        ns.HideHead()
    end
    if ns.ShowQueueStatus and not ns.state.demandShown then
        ns.ShowQueueStatus(#ns.state.queue)
    end
end

-- text: quest text for subtitles; nil reads the open quest frame, false means none
-- (a story replays quests that are not on screen). title overrides the title.
local function HasQuestItem(questID, kind)
    questID = tonumber(questID)
    local function same(item)
        return item and tonumber(item.questID) == questID and item.kind == kind
    end
    if same(ns.state.active) then
        return true
    end
    for _, list in ipairs({ ns.state.queue, ns.state.pending }) do
        for i = 1, #list do
            if same(list[i]) then
                return true
            end
        end
    end
    return false
end

local function IsDialogueItem(item)
    return item and (item.kind == "quest" or item.kind == "turnin" or item.kind == "gossip")
end

local function IsAmbientLoreItem(item)
    return item and (item.kind == "place" or item.kind == "npcLore" or item.kind == "dungeon")
end

-- A quest or a normal NPC dialog has priority over automatically started
-- ambient lore. The shared queue prevents a new item from being started while
-- another one is active, but that is not enough for companion/browser audio:
-- the old external track can keep playing after the game-side state changes.
-- Cut the lower-priority narration before enqueueing the dialog so both audio
-- backends follow the same single-voice rule.
local function InterruptAmbientLoreFor(item)
    if ns.db.queue == false or not IsDialogueItem(item) then
        return
    end
    local active = ns.state.active
    if not IsAmbientLoreItem(active) then
        return
    end
    ns.SilenceVoice()
    ns.state.active = nil
    ns.state.resumeAt = GetTime() + 0.2
    if ns.HideHead then
        ns.HideHead()
    end
end

function ns.PlayQuest(questID, kind, force, text, title, npcID, sequence, delay)
    kind = kind or "quest"
    -- Quest frames can emit QUEST_DETAIL/QUEST_ACCEPTED or reward refreshes
    -- more than once.  The normal queue guard is not enough when the first
    -- line has already finished before the duplicate event arrives; that
    -- would start the same audio a second time, often at the restored volume.
    if not force then
        local recent = ns.state.recentAutoQuest
        local now = GetTime and GetTime() or 0
        local key = tostring(tonumber(questID) or 0) .. ":" .. kind .. ":"
            .. ns.VoiceLocale() .. ":" .. tostring(npcID or 0)
        if recent and recent.key == key and now - (recent.at or 0) < 30 then
            return false
        end
    end
    if text == nil then
        if ns.state.dialogQuest == tonumber(questID) then
            text = QuestTextFor(nil, kind)
        elseif kind == "quest" then
            text = QuestLogText(tonumber(questID))
        end
    end
    local item = BuildItem(questID, kind, text or nil, title, npcID)
    if not item then
        RememberMissing(questID, kind)
        local message = ((not ns.db.remoteEnabled or CatQuest335_LocalMode) and L.NO_LOCAL_TRACK) or L.NO_TRACK
        Print(string.format(message or L.NO_TRACK, tostring(questID), "https://t.me/warcraft_rus_chat"))
        return false
    end
    -- The quest log and world-map buttons both use force=true. Some clients
    -- can deliver two click/event paths for one press, and the generated
    -- item key is not the right boundary for that case. Quest identity is.
    if HasQuestItem(questID, kind) then
        return false
    end
    item.notBefore=GetTime()+(tonumber(delay) or 0)
    local started = ns.PlayItem(item, force, nil, sequence)
    if started and not force then
        ns.state.recentAutoQuest = {
            key = item.key,
            at = GetTime and GetTime() or 0,
        }
    end
    return started
end

local function HasTurninWork()
    if ns.state.active and ns.state.active.kind=="turnin" then return true end
    for _,list in ipairs({ns.state.queue,ns.state.pending}) do
        for _,item in ipairs(list) do if item.kind=="turnin" then return true end end
    end
    return false
end

-- Queue any prepared item (quest, book page, place lore): one queue, one
-- pause between tracks, one Stop for all of them.
function ns.PlayItem(item, force, replay, sequence)
    local now = GetTime()
    -- A double click on a manual "Voice/Read" button used to pass force=true
    -- and bypass the active/queue duplicate checks below. Keep a tiny input
    -- debounce as a final guard, including when a very short track just ended.
    if ns.state.lastRequestKey == item.key and now - (ns.state.lastRequestAt or 0) < 2 then
        return false
    end
    if not force and ns.state.lastPlayedKey == item.key and now - ns.state.lastPlayedAt < 2 then
        return false
    end
    if FindPending(item.key) then
        Print(string.format(L.ALREADY_PENDING, item.title or tostring(item.questID)))
        return false
    end
    -- Map/list buttons use force=true, but force must not bypass quest
    -- identity deduplication. Otherwise a second click can enqueue the same
    -- quest while its first request is still pending on the server.
    if not replay and IsQuestItem(item) and HasQuestItem(item.questID, item.kind) then
        return false
    end
    if not force and ns.state.demandShown and ns.state.demandShown.key == item.key then
        return false
    end
    if not replay then
        if ns.state.active and ns.state.active.key == item.key then
            return false
        end
        for i = 1, #ns.state.queue do
            if ns.state.queue[i].key == item.key then
                return false
            end
        end
    end
    ns.state.lastRequestKey = item.key
    ns.state.lastRequestAt = now

    InterruptAmbientLoreFor(item)

    -- Queue off (settings): a new line cuts the one playing and those waiting.
    if not sequence and item.kind~="turnin" and not HasTurninWork() and ns.db.queue == false
        and (ns.state.active or #ns.state.queue > 0 or #ns.state.pending > 0) then
        if ns.state.active then
            ns.SilenceVoice()
            ns.state.active = nil
            ns.state.resumeAt = GetTime() + 0.2
        end
        ns.state.queue = {}
        -- A requested remote NPC/quest line must not wake up after a newer
        -- line was explicitly chosen with queueing disabled.
        ns.state.pending = {}
        ns.state.demandShown = nil
    end

    local waitingBefore = #ns.state.queue
    if ns.state.active then
        waitingBefore = waitingBefore + 1
    end
    local position = #ns.state.queue + 1
    if item.kind ~= "npcLore" then
        -- Active quest/NPC dialogue takes precedence over a target-history
        -- line that is still waiting (a line already playing finishes).
        for i = 1, #ns.state.queue do
            if ns.state.queue[i].kind == "npcLore"
                or ((item.kind == "quest" or item.kind == "turnin")
                    and ns.state.queue[i].kind == "place") then
                position = i
                break
            end
        end
    end
    table.insert(ns.state.queue, position, item)
    VoiceLog(item, "queued", "добавлено в очередь воспроизведения")
    if waitingBefore > 0 then
        local position = waitingBefore + 1
        Print(string.format(L.QUEUED, item.title or tostring(item.questID), position))
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage(string.format(L.QUEUED_SHORT, position), 1, 0.82, 0.1, 1)
        end
    end
    if ns.ShowQueueStatus then
        ns.ShowQueueStatus(#ns.state.queue)
    end
    StartNext()
    return true
end

-- 3.3.5 has no StopSound(handle). A short channel toggle may interrupt a
-- PlaySoundFile track on some clients, but is not a guaranteed stop. The
-- companion has its own explicit stop command. Preserve channels the player
-- turned off.
local function SilenceVoice()
    -- Stop the companion unconditionally. The external player can still be
    -- speaking after the game-side active item was cleared (for example when
    -- a remote track finished with an estimated duration).
    local bridge = CompanionBridge()
    if bridge then
        pcall(bridge.Stop)
    end
    if ns.state.musicPlaying then
        StopMusicVoice()
        return
    end
    if not GetCVar or not SetCVar then
        return
    end
    local channel = (ns.state.active and ns.state.active.playChannel)
        or ns.state.lastAudioChannel or ns.db.volumeChannel
    if channel == "Music" then
        return
    end
    local cvar = ({ Master = "Sound_EnableAllSound", Ambience = "Sound_EnableAmbience" })[channel or ""]
        or "Sound_EnableSFX"
    if tostring(GetCVar(cvar)) ~= "1" then
        return
    end
    SetCVar(cvar, "0")
    ns.After(0.1, function()
        SetCVar(cvar, "1")
    end)
end
ns.SilenceVoice = SilenceVoice
ns.IsFemale = IsFemale

function ns.Stop(quiet)
    ns.state.stopEpoch = (ns.state.stopEpoch or 0) + 1
    for _,slot in ipairs({"dialogTimer","gossipTimer"}) do
        if ns.state[slot] then ns.CancelAfter(ns.state[slot]);ns.state[slot]=nil end
    end
    ns.state.turninClaimCandidate=nil
    if ns.DungeonStop then ns.DungeonStop() end
    if ns.state.npcLoreTimer then
        ns.CancelAfter(ns.state.npcLoreTimer)
        ns.state.npcLoreTimer = nil
    end
    if ns.state.npcLoreKillTimer then
        ns.CancelAfter(ns.state.npcLoreKillTimer)
        ns.state.npcLoreKillTimer = nil
    end
    ns.state.npcLoreKillPending = nil
    ns.state.npcLoreTargetPending = nil
    if ns.state.active then
        VoiceLog(ns.state.active, "stopped", "остановлено пользователем")
    end
    -- Try to interrupt any in-game audio even when an estimated duration has
    -- already cleared active; the companion stop is independent of active.
    SilenceVoice()
    RestoreSoundTweaks()
    ns.state.queue = {}
    ns.state.pending = {}
    ns.state.pollTimes = {}
    ns.state.active = nil
    ns.state.demandShown = nil
    ns.state.resumeAt = 0
    if ns.HideHead then
        ns.HideHead()
    end
    if ns.ShowQueueStatus then
        ns.ShowQueueStatus(0)
    end
    if not quiet then
        Print(L.STOPPED)
    end
end

function ns.Skip()
    local skipped = ns.state.active or ns.state.pending[1]
    if skipped then
        VoiceLog(skipped, "skipped", "пропущено пользователем")
    end
    SilenceVoice()
    if not ns.state.active and ns.state.pending[1] then
        local waiting = table.remove(ns.state.pending, 1)
        if ns.state.demandShown == waiting then ns.state.demandShown = nil end
        ns.state.pollTimes = {}
    end
    ns.state.active = nil
    -- After the channel comes back on.
    ns.state.resumeAt = GetTime() + 0.2
    if ns.HideHead then
        ns.HideHead()
    end
    StartNext()
end

-- Drop one line wherever it is: playing, queued or waiting for the server.
function ns.DropItem(key)
    for _, list in ipairs({ ns.state.queue, ns.state.pending }) do
        for i = #list, 1, -1 do
            if list[i].key == key then
                table.remove(list, i)
            end
        end
    end
    if ns.state.active and ns.state.active.key == key then
        ns.Skip()
    end
end

function ns.Replay()
    local item = ns.state.lastItem
    if not item then
        Print(L.HISTORY_EMPTY)
        return
    end
    -- Books and place lore are not quests: replay the item itself.
    if item.kind == "book" or item.kind == "place" then
        return ns.PlayItem(item, true, true)
    end
    if item.kind == "gossip" then
        return ns.PlayGossipText(item.text, item.title, item.npc)
    end
    if item.kind == "dungeon" then
        local replay = {}
        for k, v in pairs(item) do replay[k] = v end
        replay.valid, replay.onFinish = nil, nil
        return ns.PlayItem(replay, true, true)
    end
    if item.kind == "npcLore" then
        return ns.PlayGossipText(item.text, item.title, item.npc, false, "npcLore", item.npcLoreID)
    end
    ns.PlayQuest(item.questID, item.kind, true, nil, item.title, item.npcID)
end

function ns.OnUpdate()
    local item = ns.state.active
    if not item then
        local demand = ns.state.demandShown
        if demand and demand.demandHideAt and GetTime() >= demand.demandHideAt then
            ClearDemandWindow(demand)
        end
        -- Resolve the current loading item before touching the next chapter
        -- entry. File reads can themselves start audio in the browser client.
        if GetTime() >= (ns.state.resumeAt or 0) then ProcessPending() end
        StartNext()
        -- Only when nothing plays: a waiting track must not overlap another.
        if ns.state.tweaked and not ns.state.active and #ns.state.queue == 0 then
            RestoreSoundTweaks()
        end
        return
    end

    if ns.SyncHead then
        ns.SyncHead(item)
    end

    local elapsed = GetTime() - item.startedAt
    local cues = item.cues or {}
    local nextCue = cues[item.cueIndex + 1]

    while nextCue and elapsed >= (tonumber(nextCue[1]) or 0) do
        item.cueIndex = item.cueIndex + 1
        if ns.SetSubtitle then
            ns.SetSubtitle(nextCue[2] or "")
        end
        nextCue = cues[item.cueIndex + 1]
    end

    if ns.UpdateHead then
        ns.UpdateHead(item, elapsed)
    end

    local duration = item.duration
    -- PlayMusic loops a file when it reaches EOF. Give the decoder a tiny
    -- post-roll for the last syllable; a long grace period exposes the start
    -- of a quiet second loop.
    if duration > 0 and elapsed >= duration + MUSIC_EOF_GRACE then
        if item.playChannel == "Music" then
            StopMusicVoice()
        end
        ns.state.active = nil
        if ns.MarkGossipHeard then ns.MarkGossipHeard(item) end
        VoiceLog(item, "finished", "таймер длительности завершён; слышимость API не подтверждает")
        ns.state.resumeAt = GetTime() + (tonumber(ns.db.trackGap) or 2)
        if ns.HideHead then
            ns.HideHead()
        end
        -- A book page turns to the next one (settings: bookPages).
        if item.onFinish then
            pcall(item.onFinish, item)
        end
    end
end

local function CurrentQuestID()
    if GetQuestID then
        local id = GetQuestID()
        if id and id > 0 then
            return id
        end
    end
    return nil
end

-- 3.3.5 GetQuestLogTitle returns: title, level, tag, suggestedGroup, isHeader,
-- isCollapsed, isComplete, isDaily, questID. Only the 9th value is the ID; the
-- 8th is isDaily (1), which must never be taken for quest 1.
local function QuestIDFromValues(values)
    local questID = values[9]
    if type(questID) == "number" and questID > 0 then
        return questID
    end
end

-- A quest shown by title only (a quest shared by another player is not in
-- our log yet): find it in the bundled quest titles if the title is unique.
local function QuestIDFromKnownTitles(title)
    if not title or title == "" then
        return nil
    end
    local found
    for _, titles in ipairs({ CatQuest335StoryTitles or {}, CatQuest335StoryTitlesFallback or {} }) do
        for questID, known in pairs(titles) do
            if known == title then
                if found and found ~= questID then
                    return nil -- ambiguous: several quests share this title
                end
                found = questID
            end
        end
        if found then
            return found
        end
    end
end

local function SelectedQuestID()
    if not GetQuestLogSelection or not GetQuestLogTitle then
        return nil
    end

    local index = GetQuestLogSelection()
    if not index or index == 0 then
        return nil
    end

    return QuestIDFromValues({ GetQuestLogTitle(index) })
end

-- While the world map is open, its quest list has its own selection. It does
-- not necessarily match the quest-log selection (or the quest in an NPC
-- dialog), so /cq id must prefer the map's quest when the player is looking
-- at the map.
local function SelectedMapQuest()
    if not WorldMapFrame or not WorldMapFrame.IsShown or not WorldMapFrame:IsShown() then
        return nil, nil
    end

    local selected = WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.selectedQuest
    local questID = selected and tonumber(selected.questId)
    if not questID or questID <= 0 then
        return nil, nil
    end

    local title
    local logIndex = selected and tonumber(selected.questLogIndex)
    if logIndex and logIndex > 0 and GetQuestLogTitle then
        title = GetQuestLogTitle(logIndex)
    end
    return questID, title
end

local function QuestIDFromTitle(title)
    if not title or title == "" or not GetNumQuestLogEntries then
        return nil
    end

    for index = 1, GetNumQuestLogEntries() do
        local values = { GetQuestLogTitle(index) }
        local logTitle = values[1]
        if logTitle == title then
            return QuestIDFromValues(values)
        end
    end
end

function ns.QuestIDForDialog()
    local title = GetTitleText and GetTitleText()
    return CurrentQuestID() or QuestIDFromTitle(title) or QuestIDFromKnownTitles(title), title
end

local function SelectedQuestTitle()
    if not GetQuestLogSelection or not GetQuestLogTitle then
        return nil
    end
    local index = GetQuestLogSelection()
    if not index or index == 0 then
        return nil
    end
    local title = GetQuestLogTitle(index)
    return title
end

local function PrintCurrentQuest()
    local mapQuestID, mapTitle = SelectedMapQuest()
    local title = GetTitleText and GetTitleText() or nil
    local questID
    if mapQuestID then
        questID = mapQuestID
        title = mapTitle or title
    else
        questID = CurrentQuestID()
        if not questID and title and title ~= "" then
            questID = QuestIDFromTitle(title)
        end
        if not questID then
            questID = SelectedQuestID()
        end
        if not title or title == "" then
            title = SelectedQuestTitle()
        end
    end
    if questID then
        Print(string.format(L.CURRENT_QUEST, tostring(title or L.NO_TITLE), tostring(questID)))
    else
        Print(L.NO_CURRENT)
    end
end

function ns.PlaySelectedQuest()
    local index = GetQuestLogSelection and GetQuestLogSelection()
    local values = index and GetQuestLogTitle and { GetQuestLogTitle(index) } or {}
    local questID = QuestIDFromValues(values)
    if questID then
        local text = GetQuestLogQuestText and GetQuestLogQuestText()
        ns.PlayQuest(questID, "quest", true, text or false, values[1])
    else
        Print(L.NO_SELECTED)
    end
end

-- manual: the "Read" button in the quest window reads even with automatic
-- reading off.
local lastNpcDialogAt = 0
local function GreetingDelay()
    if not ns.db.greetDelay then
        return 0
    end
    local now = GetTime()
    local fresh = now - lastNpcDialogAt > 4
    lastNpcDialogAt = now
    -- 3.3.5 has no reliable greeting-duration API. The original CatQuest
    -- uses per-NPC timings; use a short safe fallback for this client.
    return fresh and 1.5 or 0
end

local function ScheduleDialog(slot, delay, callback)
    if ns.CancelAfter and ns.state[slot] then
        ns.CancelAfter(ns.state[slot])
        ns.state[slot] = nil
    end
    if not delay or delay <= 0 then
        callback()
        return
    end
    local timer
    timer = ns.After(delay, function()
        if ns.state[slot] ~= timer then
            return
        end
        ns.state[slot] = nil
        callback()
    end)
    ns.state[slot] = timer
end

local function QuestDialogKey(questID, kind, npcID)
    return tostring(questID) .. ":" .. kind .. ":" .. ns.VoiceLocale() .. ":" .. tostring(npcID or 0)
end

local function CancelAutomaticGossip()
    ns.state.autoGossipEpoch = (ns.state.autoGossipEpoch or 0) + 1
    if ns.state.gossipTimer then
        ns.CancelAfter(ns.state.gossipTimer)
        ns.state.gossipTimer = nil
    end
    for _, list in ipairs({ ns.state.queue, ns.state.pending }) do
        for i = #list, 1, -1 do
            if list[i].autoGossip then table.remove(list, i) end
        end
    end
    -- A first greeting already playing may finish once before the quest.
    -- Cancel only greetings that have not actually started yet.
    if ns.state.demandShown and ns.state.demandShown.autoGossip then
        ns.state.demandShown = nil
        if not ns.state.active and ns.HideHead then ns.HideHead() end
    end
end

local function OnQuestEvent(event, manual)
    if event=="QUEST_COMPLETE" then ns.state.turninClaimCandidate=nil end
    if ns.state.npcLoreTimer then
        ns.CancelAfter(ns.state.npcLoreTimer)
        ns.state.npcLoreTimer = nil
    end
    if not ns.db.enabled or not (ns.db.auto or manual) then
        return
    end

    -- Turning a quest in shows two screens: items with "Continue"
    -- (QUEST_PROGRESS), then the reward (QUEST_COMPLETE). The turn-in track is
    -- the completion text, so it plays once, on the reward screen.
    local kind
    if event == "QUEST_DETAIL" then
        kind = "quest"
    elseif event == "QUEST_COMPLETE" then
        if not ns.db.turnin and not manual then
            return
        end
        kind = "turnin"
    end

    if not kind then
        return
    end
    -- Selecting a quest supersedes the automatic greeting, including a
    -- greeting whose marker transfer has not finished yet. Explicit Read
    -- requests and committed turn-ins retain their normal queue positions.
    CancelAutomaticGossip()

    -- Never fall back to the quest selected in the log: a quest shared by a
    -- party member is shown in this window but is not that quest.
    local title = GetTitleText and GetTitleText()
    local questID = CurrentQuestID()
        or QuestIDFromTitle(title)
        or QuestIDFromKnownTitles(title)
    if not questID then
        -- Some 3.3.5 servers show repeatable/gossip NPC windows through the
        -- quest frame. They have real dialogue text but no quest ID. Route
        -- those windows through the gossip voice path instead of reporting a
        -- missing quest and trying to guess another quest.
        if ns.OpenGossipData and ns.PlayGossipText then
            local gossipText, gossipTitle, gossipNpc = ns.OpenGossipData()
            if gossipText and gossipText ~= "" then
                return ns.PlayGossipText(gossipText, gossipTitle, gossipNpc, not manual)
            end
        end
        Print(string.format(L.NO_QUEST_ID, tostring(title or "?")))
        return
    end
    -- A duplicate reward refresh must retain the claim context even when
    -- its audio is already queued and the event is deduplicated below.
    if kind=="turnin" then ns.state.turninClaimCandidate={questID=questID,at=GetTime()} end
    -- Some 3.3.5 clients can emit QUEST_DETAIL more than once while the
    -- dialog is being refreshed. Do not enqueue the same automatic read
    -- again while this quest window is still open. Manual "Read" calls are
    -- intentionally allowed through the normal PlayItem duplicate guard.
    local npcID = QuestNpcID(questID, kind)
    local dialogEventKey = QuestDialogKey(questID, kind, npcID)
    if not manual and ns.state.dialogEventKey == dialogEventKey then
        return
    end
    if not manual then
        ns.state.dialogEventKey = dialogEventKey
    end
    -- The quest dialog with this NPC is open: the window can show its face.
    ns.state.dialogQuest = questID
    local text = QuestTextFor(event, kind)
    -- Read after "Accept" (settings): keep the text until the quest is taken.
    if kind == "quest" and ns.db.readAfterAccept and not manual then
        ns.state.acceptPending = { questID = questID, text = text, npcID = npcID }
        return
    end
    if kind=="turnin" then
        if ns.state.dialogTimer then
            ns.CancelAfter(ns.state.dialogTimer);ns.state.dialogTimer=nil
        end
        -- Snapshot the reward while this dialog still owns its text/title.
        -- GreetingDelay belongs to this queued item, never a replaceable
        -- shared dialog timer. Completing another quest cannot erase it.
        ns.state.recent[questID..":"..kind]=GetTime()
        ns.state.dialogKey=QuestDialogKey(questID,kind,npcID)
        ns.state.turninClaimCandidate={questID=questID,at=GetTime()}
        return ns.PlayQuest(questID,kind,manual and true or false,text,title,npcID,true,
            manual and 0 or GreetingDelay())
    end
    local function play()
        if not ns.db.enabled then
            return
        end
        if ns.db.stopOnClose and ns.state.dialogQuest ~= questID then
            return
        end
        ns.state.recent[questID .. ":" .. kind] = GetTime()
        ns.state.dialogKey = QuestDialogKey(questID, kind, npcID)
        ns.PlayQuest(questID, kind, manual and true or false, text, title, npcID)
    end
    ScheduleDialog("dialogTimer", manual and 0 or GreetingDelay(), play)
end

-- A committed hand-in keeps its final line after the reward window closes.
-- QUEST_FINISHED can run inside GetQuestReward, before this secure post-hook;
-- the close handler defers cancellation until the following scheduler tick.
if hooksecurefunc and GetQuestReward then
    hooksecurefunc("GetQuestReward",function()
        local candidate=ns.state.turninClaimCandidate
        if not candidate or GetTime()-candidate.at>60 then return end
        local function Mark(item)
            if item and item.kind=="turnin" and item.questID==candidate.questID then item.turninClaimed=true end
        end
        Mark(ns.state.active)
        for _,list in ipairs({ns.state.queue,ns.state.pending}) do for _,item in ipairs(list) do Mark(item) end end
        ns.state.turninClaimCandidate=nil
    end)
end

-- "Read" button in the quest window: the quest on screen.
function ns.ReadOpenQuest()
    if ns.state.dialogTimer then
        ns.CancelAfter(ns.state.dialogTimer)
        ns.state.dialogTimer = nil
    end
    if QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown() then
        return OnQuestEvent("QUEST_COMPLETE", true)
    end
    -- A gossip/turn-in style NPC dialog can use QuestFrame on custom 3.3.5
    -- clients and therefore lands on this button. It has no quest ID, so use
    -- the text currently visible in that NPC window.
    if ns.OpenGossipData and ns.PlayGossipText and not CurrentQuestID() then
        local gossipText, gossipTitle, gossipNpc = ns.OpenGossipData()
        if gossipText and gossipText ~= "" then
            return ns.PlayGossipText(gossipText, gossipTitle, gossipNpc)
        end
    end
    return OnQuestEvent("QUEST_DETAIL", true)
end

-- readAfterAccept: the quest kept by OnQuestEvent starts when it is taken.
if hooksecurefunc and AcceptQuest then
    hooksecurefunc("AcceptQuest", function()
        local pending = ns.state.acceptPending
        ns.state.acceptPending = nil
        if pending and ns.db.enabled then
            ns.PrefetchQuestCompletion(pending.questID, nil, pending.npcID)
            ns.state.recent[pending.questID .. ":quest"] = GetTime()
            ns.PlayQuest(pending.questID, "quest", false, pending.text, nil, pending.npcID)
        end
    end)
end

local function OnQuestAccepted(questIndexOrID)
    if not ns.db.enabled or not ns.db.auto then
        return
    end

    local questID
    if type(questIndexOrID) == "number" and GetQuestLogTitle then
        questID = QuestIDFromValues({ GetQuestLogTitle(questIndexOrID) })
    end
    -- Some custom 3.3.5 builds send the quest ID rather than the log index.
    -- The old code rejected server-only quests because they are absent from
    -- the local CatQuest pack. WotLK quest IDs are safely above this range.
    if not questID and type(questIndexOrID) == "number" and questIndexOrID > 1000 then
        questID = questIndexOrID
    end

    -- QUEST_ACCEPTED is a fallback for builds without GetQuestID: the quest
    -- dialog usually voiced this quest already, so do not read it twice.
    local heard = questID and ns.state.recent[questID .. ":quest"]
    if questID then
        ns.PrefetchQuestCompletion(questID)
    end
    if questID and not (heard and GetTime() - heard < 600) then
        ns.After(0.8, function()
            if ns.db.enabled and ns.db.auto then
                ns.PlayQuest(questID, "quest", false, false)
            end
        end)
    end
end

-- Experiment (Lasthavens): can the browser extension tell the addon whether
-- a file exists? The extension serves probe\yes.tga, answers "missing" for
-- probe\no.tga, and probe\none.tga is not in the game's file list at all.
-- Prints what SetTexture and GetTexture return, at once and 1 s later.
function ns.ProbeTextures()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(1, 1)
    frame:SetPoint("TOPLEFT")
    frame:SetAlpha(0)
    local base = "Interface\\AddOns\\CatQuest335_ServerVoices\\probe\\"
    local names = { "yes", "no", "none" }
    local textures = {}
    local function Describe(texture, result)
        local ok, current = pcall(texture.GetTexture, texture)
        local width = select(2, pcall(texture.GetWidth, texture))
        return "SetTexture=" .. tostring(result) .. " GetTexture=" .. (ok and tostring(current) or "error")
            .. " w=" .. tostring(width)
    end
    for i, name in ipairs(names) do
        local texture = frame:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints(frame)
        local started = GetTime()
        local ok, result = pcall(texture.SetTexture, texture, base .. name .. ".tga")
        if not ok then
            result = "error " .. tostring(result)
        end
        textures[i] = { texture = texture, result = result }
        Print(string.format("probe tex %s: %s (%.0f ms)", name, Describe(texture, textures[i].result),
            (GetTime() - started) * 1000))
    end
    ns.After(1, function()
        for i, name in ipairs(names) do
            Print("probe tex " .. name .. " after 1 s: " .. Describe(textures[i].texture, textures[i].result))
        end
    end)
end

-- Phase 0: call PlaySoundFile twice, 2 s apart, for both path layouts the
-- browser bridge understands, and print what the client returned. The
-- extension's diagnostics block shows whether each call reached the network.
function ns.Probe(questID)
    local locale = ns.VoiceLocale()
    local paths = {
        "Interface\\AddOns\\CatQuest335_ServerVoices\\" .. locale .. "\\Sounds\\q\\" .. questID .. ".ogg",
        "Interface\\AddOns\\CatQuest\\Sounds\\" .. locale .. "\\q" .. questID .. "_DETAIL.ogg",
    }
    local function Attempt(round)
        for i = 1, #paths do
            local ok, a, b = pcall(PlaySoundFile, paths[i], SoundChannel())
            Print(string.format("probe %d/%d: ok=%s ret=%s,%s %s", round, i,
                tostring(ok), tostring(a), tostring(b), paths[i]))
        end
    end
    Print(string.format(L.PROBE_START, tostring(questID)))
    Attempt(1)
    ns.After(2, function()
        Attempt(2)
    end)
end

function ns.LanguageName(locale)
    return L["LANG_" .. tostring(locale)] or tostring(locale)
end

function ns.PrintLanguage()
    Print(string.format(L.LANG_SET, ns.LanguageName(ns.VoiceLocale()) .. " (" .. ns.ShortLocale(ns.VoiceLocale()) .. ")",
        ns.ShortLocale(ns.ClientLocale())))
end

-- Tell the Lasthavens browser bridge which voice language to prepare: it
-- serves a silent marker file per language and notices which one is read.
-- In a normal client the file does not exist and nothing happens.
function ns.AnnounceLanguage()
    if not ns.db.remoteEnabled or CatQuest335_LocalMode
        or (type(CatQuest335_BridgeReady) == "table" and CatQuest335_BridgeReady.mode == "local") then
        return
    end
    pcall(PlaySoundFile, "Interface\\AddOns\\CatQuest335_ServerVoices\\lang\\" .. ns.VoiceLocale() .. ".ogg", "Master")
end

-- The player chose a language: the bridge keeps the choice and puts it back
-- into the saved settings on the next page load (F5 does not save them).
function ns.AnnounceChoice()
    if not ns.db.remoteEnabled or CatQuest335_LocalMode
        or (type(CatQuest335_BridgeReady) == "table" and CatQuest335_BridgeReady.mode == "local") then
        return
    end
    local value = ns.db.language == "auto" and "auto" or ns.VoiceLocale()
    pcall(PlaySoundFile, "Interface\\AddOns\\CatQuest335_ServerVoices\\lang\\set\\" .. value .. ".ogg", "Master")
    ns.AnnounceLanguage()
end

-- Lasthavens: messages for the extension (who plays: realm, name, GUID;
-- Lua errors of this addon). A 3.3.5 addon cannot send data, so it "plays"
-- silent marker files, one per half byte: who/<slot>/<position>/<0-f>.ogg.
-- The extension sends them on only when the player has not turned
-- statistics off.
local WHO_MAX_BYTES = 72
local WHO_SLOTS = 3
local GOSSIP_MARKER_SLOTS = 16
local GOSSIP_MAX_BYTES = 800
local GOSSIP_CHUNK_BYTES = WHO_MAX_BYTES - 3 - 3 -- frame + id/index/total
-- A message for the extension: kind byte (1 character, 2 error), length,
-- payload, checksum.
local function Frame(kind, payload, limit)
    if not payload or #payload + 3 > (limit or WHO_MAX_BYTES) then
        return nil
    end
    local bytes = { kind, #payload }
    for i = 1, #payload do
        bytes[#bytes + 1] = payload[i]
    end
    local sum = 0
    for i = 1, #bytes do
        sum = sum + bytes[i]
    end
    bytes[#bytes + 1] = sum % 256
    return bytes
end

function ns.CharacterSnapshot()
    local realm = GetRealmName and GetRealmName() or ""
    local name = UnitName and UnitName("player") or ""
    local guid = UnitGUID and UnitGUID("player") or ""
    if realm=="" or name=="" or not guid:match("^0[xX]%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$")
        or realm:find("[\t\r\n]") or name:find("[\t\r\n]") then return nil end
    return {realm=realm,name=name,guid=guid}
end

function ns.CharacterPayload(character)
    local who=character or ns.CharacterSnapshot()
    if not who then return nil end
    local realm,name,guid=who.realm,who.name,who.guid
    local hex = string.match(guid, "^0[xX](%x+)$")
    if realm == "" or name == "" or not hex or string.len(hex) ~= 16 then
        return nil
    end
    local payload = { string.byte(realm .. "\t" .. name .. "\t", 1, -1) }
    for i = 1, 16, 2 do
        payload[#payload + 1] = tonumber(string.sub(hex, i, i + 1), 16)
    end
    return payload
end

function ns.CharacterBytes()
    return Frame(1, ns.CharacterPayload())
end

function ns.NewActionID()
    ns.db.actionSerial=(tonumber(ns.db.actionSerial) or 0)+1
    return string.format("%08x%04x%04x", (time and time() or 0)%4294967296,
        math.random(0,65535),ns.db.actionSerial%65536)
end

-- Plays one message as markers, a few at a time (a burst of sounds may lose
-- some). Each message takes the next slot: the game reads a file only the
-- first time in a page load.
local function MarkerFiles(bytes, slot, folder)
    local files = {}
    for i = 1, #bytes do
        local b = bytes[i]
        local pos = (i - 1) * 2
        files[#files + 1] = string.format("%s\\%d\\%d\\%x", folder, slot, pos, math.floor(b / 16))
        files[#files + 1] = string.format("%s\\%d\\%d\\%x", folder, slot, pos + 1, b % 16)
    end
    return files
end

local function SendMarkerFiles(files, onDone, explicitVote, onProgress)
    if not files or (not explicitVote and not ns.db.remoteEnabled) or CatQuest335_LocalMode
        or type(CatQuest335_BridgeReady) ~= "table"
        or CatQuest335_BridgeReady.mode == "local" then
        return false
    end
    local index = 1
    local function Next()
        for _ = 1, 8 do
            local file = files[index]
            if not file then
                break
            end
            index = index + 1
            pcall(PlaySoundFile, "Interface\\AddOns\\CatQuest335_ServerVoices\\" .. file .. ".ogg", "Master")
        end
        if onProgress then onProgress(math.floor((index - 1) * 100 / #files)) end
        if files[index] then
            ns.After(0.2, Next)
        elseif onDone then
            ns.After(0.5, onDone)
        end
    end
    Next()
    return true
end

local function SendPrefetchFrame(frame, signalSlot)
    if not frame then return false end
    if (tonumber(CatQuest335_BridgeReady.prefetchSignal) or 0) >= 2 then
        return SendMarkerFiles(MarkerFiles(frame, signalSlot, "prefetch"), nil)
    end
    local slot = (tonumber(ns.db.gossipMarkerSlot) or 0) % GOSSIP_MARKER_SLOTS + 1
    ns.db.gossipMarkerSlot = slot
    return SendMarkerFiles(MarkerFiles(frame, slot, "gossip-msg"), nil)
end

-- One local silent marker per stage: no synchronous network polling.
local DIAGNOSTIC_STAGES = {requested=1,waiting=2,ready=3,playing=4,finished=5,["font-invalid"]=9,["font-waiting"]=33,
    stopped=6,skipped=7,timeout=8,error=9,queued=10,["font-ready"]=11,
    ["font-missing"]=12,["play-call"]=13,["play-failed"]=14,packet=15,preload=16}
function ns.SendDiagnosticStage(item, status)
    local ready = CatQuest335_BridgeReady
    if not item or not item.prefetchSlot or not ns.db.remoteEnabled or CatQuest335_LocalMode
        or type(ready) ~= "table" or ready.clientTrace ~= 1 or ready.mode == "local" then return end
    local stage = DIAGNOSTIC_STAGES[status]
    if status == "font-probe" then
        local attempt = tonumber(item.readySignalAttempts) or 0
        if attempt >= 1 and attempt <= 16 then stage = 16 + attempt end
    end
    if not stage then return end
    item.diagnosticStages = item.diagnosticStages or {}
    if item.diagnosticStages[stage] then return end
    item.diagnosticStages[stage] = true
    local slot = item.prefetchSlot
    ns.After(0.7, function()
        pcall(PlaySoundFile, "Interface\\AddOns\\CatQuest335_ServerVoices\\trace\\" .. slot .. "\\" .. stage .. ".ogg", "Master")
    end)
end

local function SendBytes(bytes, explicitVote)
    if not bytes or (not explicitVote and not ns.db.remoteEnabled) or CatQuest335_LocalMode
        or type(CatQuest335_BridgeReady) ~= "table"
        or CatQuest335_BridgeReady.mode == "local" then
        return false
    end
    local slot = (tonumber(ns.db.whoSlot) or 0) % WHO_SLOTS + 1
    ns.db.whoSlot = slot
    return SendMarkerFiles(MarkerFiles(bytes, slot, "who"), nil, explicitVote)
end

-- The browser extension consumes this small frame in the game worker. It
-- starts an async fetch and exposes the result through ready-signal/<slot>.ttf.
-- The addon only checks that local signal file, so it never performs a
-- network-backed SetFont while the game is rendering or processing the queue.
local function ReadySignalPath(slot)
    local ready = CatQuest335_BridgeReady
    local root = (tonumber(ready and ready.prefetchSignal) or 0) >= 3
        and "Interface\\AddOns\\CatQuest\\r\\"
        or "Interface\\AddOns\\CatQuest335_ServerVoices\\ready-signal\\"
    return root .. slot .. ".ttf"
end

function ns.RequestVoicePrefetch(item)
    if not item or not item.remote or not IsQuestItem(item) then return false end
    local ready = CatQuest335_BridgeReady
    if type(ready) ~= "table" or (tonumber(ready.prefetchSignal) or 0) < 1 or ready.mode == "local" then
        return false
    end
    if item.prefetchSent then return true end
    local questID = tonumber(item.questID)
    if not questID or questID <= 0 or questID >= 10000000 then return false end
    local locale = ns.VoiceLocale()
    local localeIndex = {
        ruRU=1, enUS=2, zhCN=3, zhTW=4, deDE=5, frFR=6,
        esES=7, esMX=8, ptBR=9, koKR=10, itIT=11,
    }
    local typeCode = item.kind == "turnin" and 2 or item.kind == "quest" and 1 or 0
    local localeCode = localeIndex[locale] or 0
    if typeCode == 0 or localeCode == 0 then return false end
    local slot = (tonumber(ns.db.readySignalSlot) or 0) % 512 + 1
    ns.db.readySignalSlot = slot
    local payload = {
        math.floor(questID / 16777216) % 256,
        math.floor(questID / 65536) % 256,
        math.floor(questID / 256) % 256,
        questID % 256,
        typeCode, localeCode,
        math.floor(slot / 256) % 256, slot % 256,
    }
    local frame = Frame(8, payload)
    if not frame then return false end
    item.prefetchSlot = slot
    item.readySignalPath = ReadySignalPath(slot)
    item.prefetchSent = SendPrefetchFrame(frame, slot)
    VoiceLog(item, "packet", "quest marker sent=" .. tostring(item.prefetchSent))
    return item.prefetchSent
end

function ns.RequestNarrationPrefetch(item)
    if not item or not item.remote or item.prefetchSent then return false end
    local ready = CatQuest335_BridgeReady
    if type(ready) ~= "table" or (tonumber(ready.prefetchSignal) or 0) < 1 or ready.mode == "local" then
        return false
    end
    local stem = string.match(item.file or "", "\\b\\([%x_mf]+)%.ogg$")
    if not stem then return false end
    local hash, suffix = string.match(stem, "^(%x%x%x%x%x%x%x%x)(_[mf])$")
    if not hash and string.len(stem) == 8 and string.match(stem, "^%x+$") then hash = stem end
    if not hash then return false end
    local variantCode = suffix == "_m" and 1 or suffix == "_f" and 2 or 0
    local slot = (tonumber(ns.db.readySignalSlot) or 0) % 512 + 1
    ns.db.readySignalSlot = slot
    local payload = {}
    for i = 1, 8, 2 do
        payload[#payload + 1] = tonumber(string.sub(hash, i, i + 1), 16)
    end
    payload[#payload + 1] = variantCode
    payload[#payload + 1] = math.floor(slot / 256) % 256
    payload[#payload + 1] = slot % 256
    local frame = Frame(9, payload)
    if not frame then return false end
    item.prefetchSlot = slot
    item.readySignalPath = ReadySignalPath(slot)
    item.prefetchSent = SendPrefetchFrame(frame, slot)
    VoiceLog(item, "packet", "narration marker sent=" .. tostring(item.prefetchSent))
    return item.prefetchSent
end

function ns.RequestGossipPrefetch(item)
    if not item or not item.remote or item.prefetchSent or not item.gossipAudioSlot then return false end
    local ready = CatQuest335_BridgeReady
    if type(ready) ~= "table" or (tonumber(ready.prefetchSignal) or 0) < 1 or ready.mode == "local" then
        return false
    end
    local audioSlot = tonumber(item.gossipAudioSlot)
    if not audioSlot or audioSlot < 1 or audioSlot > 255 then return false end
    local slot = (tonumber(ns.db.readySignalSlot) or 0) % 512 + 1
    ns.db.readySignalSlot = slot
    local frame = Frame(10, { audioSlot, math.floor(slot / 256) % 256, slot % 256 })
    if not frame then return false end
    item.prefetchSlot = slot
    item.readySignalPath = ReadySignalPath(slot)
    item.prefetchSent = SendPrefetchFrame(frame, slot)
    VoiceLog(item, "packet", "gossip marker sent=" .. tostring(item.prefetchSent))
    return item.prefetchSent
end

-- The browser game does not reliably write SavedVariables on F5. Send window
-- settings through markers when they change; the extension merges each partial
-- update with the account settings.
function ns.AnnounceSettings()
    if not ns.db.remoteEnabled or CatQuest335_LocalMode
        or type(CatQuest335_BridgeReady) ~= "table"
        or CatQuest335_BridgeReady.mode == "local" then
        return false
    end
    if ns.state.settingsAnnounceTimer then
        ns.CancelAfter(ns.state.settingsAnnounceTimer)
        ns.state.settingsAnnounceTimer = nil
    end
    ns.state.settingsAnnounceTimer = ns.After(0.35, function()
        ns.state.settingsAnnounceTimer = nil
        local scale = tonumber(ns.db.scale) or 1
        local duck = tonumber(ns.db.duck) or 0
        local channel = ns.db.volumeChannel or "SFX"
        local layer = ns.db.headStrata or "below-bags"
        local panel = ns.db.requestPanel and 1 or 0
        local text = string.format("scale=%.2f\tduck=%d\tchannel=%s\tlayer=%s\tpanel=%d", scale, duck, channel, layer, panel)
        return SendBytes(Frame(5, { string.byte(text, 1, -1) }))
    end)
    return true
end

function ns.AnnouncePosition()
    local saved = ns.db.headPosition
    local point = saved and saved.point or "CENTER"
    local relativePoint = saved and saved.relativePoint or "CENTER"
    local x = saved and tonumber(saved.x) or 0
    local y = saved and tonumber(saved.y) or -180
    local text = string.format("position=%s,%s,%.2f,%.2f", point, relativePoint, x, y)
    return SendBytes(Frame(5, { string.byte(text, 1, -1) }))
end

function ns.AnnounceCharacter()
    return SendBytes(ns.CharacterBytes())
end

-- A message of another kind (3: feedback, Feedback.lua). False when it
-- cannot go out (not Lasthavens, server voices off, too long).
function ns.SendMessageBytes(kind, payload)
    -- Feedback is an explicit player action too. It must not depend on the
    -- server-voice toggle: a player can report a broken local/original track
    -- even when remote voice generation is disabled.
    return SendBytes(Frame(kind, payload, (kind == 3 or kind == 6) and 256 or nil), kind == 3 or kind == 6 or kind == 5)
end
ns.MESSAGE_MAX_PAYLOAD = WHO_MAX_BYTES - 3

-- Explicit player messages have their own marker pool, independent of audio
-- and telemetry. Keep the same conservative burst size as other messages.
function ns.SendContactMessage(id, category, text, onProgress, onDone)
    if type(CatQuest335_BridgeReady) ~= "table" or not CatQuest335_BridgeReady.contact then return false end
    if ns.db.contactPage ~= CatQuest335_BridgeReady.contactPage then
        ns.db.contactPage = CatQuest335_BridgeReady.contactPage
        ns.db.contactSlotsUsed = 0
    end
    local contactSlotsUsed = tonumber(ns.db.contactSlotsUsed) or 0
    if not string.match(tostring(id), "^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$")
        or not category or category < 1 or category > 3
        or type(text) ~= "string" or #text < 1 or #text > 4500 then return false end
    local header = {}
    for i = 1, 16, 2 do header[#header + 1] = tonumber(string.sub(id, i, i + 1), 16) end
    local total = math.ceil(#text / 58)
    -- The client caches reads by filename for the page lifetime. Never wrap
    -- this pool silently: reusing cached markers would lose a new message.
    if contactSlotsUsed + total > 80 then return false end
    local files = {}
    for part = 1, total do
        local payload = {}
        for i = 1, #header do payload[i] = header[i] end
        payload[9], payload[10], payload[11] = part, total, category
        local chunk = string.sub(text, (part - 1) * 58 + 1, part * 58)
        for i = 1, #chunk do payload[#payload + 1] = string.byte(chunk, i) end
        local slot = contactSlotsUsed + part
        local markers = MarkerFiles(Frame(7, payload), slot, "contact")
        for i = 1, #markers do files[#files + 1] = markers[i] end
    end
    local ok = SendMarkerFiles(files, onDone, true, onProgress)
    if ok then ns.db.contactSlotsUsed = contactSlotsUsed + total end
    return ok
end

local function TextChunks(text, limit)
    local chunks, start = {}, 1
    while start <= string.len(text) do
        local at, bytes = start, 0
        while at <= string.len(text) do
            local first = string.byte(text, at)
            local size = first < 128 and 1 or first < 224 and 2 or first < 240 and 3 or 4
            if bytes + size > limit then
                break
            end
            bytes = bytes + size
            at = at + size
        end
        if at == start then
            at = math.min(string.len(text) + 1, start + 1)
        end
        chunks[#chunks + 1] = string.sub(text, start, at - 1)
        start = at
    end
    return chunks
end

local function TrimUtf8(text, limit)
    if string.len(text) <= limit then
        return text
    end
    local at = limit
    while at > 0 do
        local byte = string.byte(text, at)
        if byte < 128 then
            return string.sub(text, 1, at)
        end
        if byte >= 192 then
            local need = byte >= 240 and 4 or byte >= 224 and 3 or 2
            return string.sub(text, 1, at + need - 1 <= limit and limit or at - 1)
        end
        at = at - 1
    end
    return ""
end

-- Gossip text is sent in small UTF-8 frames. The runtime reconstructs it
-- before the addon opens the fixed virtual gossip/<slot>.ogg path.
local function CleanGossipText(text)
    text = tostring(text or "")
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    return string.gsub(text, "%s+", " ")
end

local function SendGossipText(title, text, npc, onReady, heardKey)
    if not ns.db.remoteEnabled or CatQuest335_LocalMode
        or type(CatQuest335_BridgeReady) ~= "table"
        or CatQuest335_BridgeReady.mode == "local" then
        return nil
    end
    local audioSlot = (tonumber(ns.db.gossipAudioSlot) or 0) % 255 + 1
    ns.db.gossipAudioSlot = audioSlot
    title = CleanGossipText(title or L.GOSSIP_TITLE)
    text = CleanGossipText(text)
    -- The first line is a compact protocol header consumed by the browser
    -- bridge. Keeping the metadata in the marker payload avoids putting a
    -- user-controlled GUID in an addon path while still letting the server
    -- select the voice for this exact NPC.
    local npcID = npc and tonumber(npc.id) or 0
    local gender = npc and tostring(npc.gender or "") or ""
    local header = "v2\t" .. tostring(npcID or 0) .. "\t" .. gender
    if heardKey then header = header .. "\t" .. heardKey end
    local combined = header .. "\n" .. title .. "\n" .. text
    if string.len(combined) > GOSSIP_MAX_BYTES then
        combined = TrimUtf8(combined, GOSSIP_MAX_BYTES)
    end
    local chunks = TextChunks(combined, GOSSIP_CHUNK_BYTES)
    if #chunks == 0 or #chunks > GOSSIP_MARKER_SLOTS then
        return nil
    end
    local files = {}
    for index = 1, #chunks do
        local slot = (tonumber(ns.db.gossipMarkerSlot) or 0) % GOSSIP_MARKER_SLOTS + 1
        ns.db.gossipMarkerSlot = slot
        local payload = { audioSlot, index, #chunks }
        local chunkBytes = { string.byte(chunks[index], 1, -1) }
        for i = 1, #chunkBytes do
            payload[#payload + 1] = chunkBytes[i]
        end
        local frame = Frame(4, payload)
        if not frame then
            return nil
        end
        local marker = MarkerFiles(frame, slot, "gossip-msg")
        for i = 1, #marker do
            files[#files + 1] = marker[i]
        end
    end
    SendMarkerFiles(files, function()
        if onReady then
            onReady(audioSlot)
        end
    end)
    return audioSlot
end

local function GossipHeardKey(text, npc, title)
    local id = tonumber(npc and npc.id) or 0
    local input = (id > 0 and tostring(id) or tostring(npc and npc.name or title or "")) .. "\n" .. text
    local a, b = 5381, 0
    for i = 1, #input do
        local byte = string.byte(input, i)
        a = (a * 33 + byte) % 4294967296
        b = (b * 65599 + byte) % 4294967296
    end
    return tostring(id) .. ":" .. ns.VoiceLocale() .. ":" .. string.format("%08x%08x", a, b)
end

function ns.MarkGossipHeard(item)
    if item.kind ~= "gossip" or not item.gossipHeardKey then return end
    ns.db.gossipHeard[item.gossipHeardKey] = true
    local ready = CatQuest335_BridgeReady
    if item.gossipAudioSlot and type(ready) == "table" and ready.gossipOnce then
        pcall(PlaySoundFile, "Interface\\AddOns\\CatQuest335_ServerVoices\\heard\\gossip\\"
            .. item.gossipAudioSlot .. ".ogg", "Master")
    end
end

function ns.PlayGossipText(text, title, npc, quiet, kind, loreID)
    local companion = CompanionBridge()
    local ready = CatQuest335_BridgeReady
    local directCompanion = companion and (type(ready) ~= "table" or ready.mode == "local")
    if not ns.db.remoteEnabled or CatQuest335_LocalMode
        or (not directCompanion and (type(ready) ~= "table" or ready.mode == "local")) then
        if not quiet then
            Print(string.format(L.NO_LOCAL_GOSSIP, "https://t.me/warcraft_rus_chat"))
        end
        return false
    end
    text = CleanGossipText(text)
    if kind~="npcLore" and kind~="dungeon" and ns.UniversalGossipText then text=ns.UniversalGossipText(text) end
    title = CleanGossipText(title or L.GOSSIP_TITLE)
    if text == "" then
        Print(L.NO_GOSSIP_TEXT)
        return false
    end
    local automatic = quiet and (not kind or kind == "gossip")
    local heardKey = (not kind or kind == "gossip") and GossipHeardKey(text, npc, title) or nil
    if automatic and ns.db.gossipHeard[heardKey] then return false end
    ns.state.gossipTransfers = ns.state.gossipTransfers or {}
    local transfer = heardKey and ns.state.gossipTransfers[heardKey]
    local stopEpoch = ns.state.stopEpoch or 0
    local gossipEpoch = ns.state.autoGossipEpoch or 0
    if transfer and transfer.stop == stopEpoch and
        (not transfer.automatic or transfer.epoch == gossipEpoch) then return false end
    if heardKey then
        for _, list in ipairs({ns.state.queue, ns.state.pending}) do
            for _, queued in ipairs(list) do if queued.gossipHeardKey == heardKey then return false end end
        end
        if ns.state.active and ns.state.active.gossipHeardKey == heardKey then return false end
    end
    if kind ~= "npcLore" and kind ~= "dungeon" then ns.state.dialogGossip = true end
    local function decorate(item, slot)
        item.autoGossip, item.gossipHeardKey, item.gossipAudioSlot = automatic, heardKey, slot
        if heardKey then item.key = "gossip:" .. heardKey end
    end
    if directCompanion then
        local item = BuildGossipItem(text, title, nil, npc, kind, loreID)
        if not item then
            if not quiet then
                Print(string.format(L.NO_LOCAL_GOSSIP, "https://t.me/warcraft_rus_chat"))
            end
            return false
        end
        decorate(item)
        ns.state.dialogKey = item.key
        local ok = ns.PlayItem(item, false)
        if ok and not quiet then
            Print(string.format(L.REQUESTED, title))
        end
        return ok
    end
    local token = {stop=stopEpoch,epoch=gossipEpoch,automatic=automatic}
    if heardKey then ns.state.gossipTransfers[heardKey] = token end
    local ok = SendGossipText(title, text, npc, function(audioSlot)
        if heardKey and ns.state.gossipTransfers[heardKey] == token then ns.state.gossipTransfers[heardKey] = nil end
        -- A target/boss request may still be sending its marker frames when
        -- Stop is pressed. Its delayed callback must not revive the voice.
        if (ns.state.stopEpoch or 0) ~= stopEpoch then return end
        if automatic and (ns.state.autoGossipEpoch or 0) ~= gossipEpoch then return end
        local item = BuildGossipItem(text, title, audioSlot, npc, kind, loreID)
        if item then
            decorate(item, audioSlot)
            ns.state.dialogKey = item.key
            ns.PlayItem(item, false)
        end
    end, heardKey)
    if not ok then
        if heardKey and ns.state.gossipTransfers[heardKey] == token then ns.state.gossipTransfers[heardKey] = nil end
        if not quiet then
            Print(string.format(L.NO_LOCAL_GOSSIP, "https://t.me/warcraft_rus_chat"))
        end
        return false
    end
    if not quiet then
        Print(string.format(L.REQUESTED, title))
    end
    return true
end

local function OpenGossipData()
    local text
    -- Prefer the panel that is actually visible. Some custom clients reuse
    -- QuestFrame for a gossip-style repeatable NPC window.
    if QuestFrameProgressPanel and QuestFrameProgressPanel.IsShown
        and QuestFrameProgressPanel:IsShown() and GetProgressText then
        text = GetProgressText()
    elseif QuestFrameRewardPanel and QuestFrameRewardPanel.IsShown
        and QuestFrameRewardPanel:IsShown() and GetRewardText then
        text = GetRewardText()
    elseif QuestFrameDetailPanel and QuestFrameDetailPanel.IsShown
        and QuestFrameDetailPanel:IsShown() and GetQuestText then
        text = GetQuestText()
    end
    if (not text or text == "") and GetGossipText then
        text = GetGossipText()
    end
    if (not text or text == "") and GossipGreetingText and GossipGreetingText.GetText then
        text = GossipGreetingText:GetText()
    end
    local title = GossipFrameNpcNameText and GossipFrameNpcNameText.GetText
        and GossipFrameNpcNameText:GetText() or nil
    if (not title or title == "") and QuestFrameNpcNameText and QuestFrameNpcNameText.GetText then
        title = QuestFrameNpcNameText:GetText()
    end
    if not title or title == "" then
        title = UnitName and UnitName("npc") or L.GOSSIP_TITLE
    end
    local npc = {
        id = CreatureIDFromUnit("npc"),
        name = UnitName and UnitName("npc") or title,
        gender = "",
    }
    if not npc.id and UnitName and title==UnitName("target") then
        npc.id=CreatureIDFromUnit("target")
    end
    if npc.id and npc.id >= 10000000 then
        npc.id = nil
    end
    if UnitSex then
        local sex = UnitSex("npc")
        npc.gender = sex == 3 and "female" or sex == 2 and "male" or ""
    end
    return text, title, npc
end

ns.OpenGossipData = OpenGossipData

function ns.ReadOpenGossip()
    if ns.state.gossipTimer then
        ns.CancelAfter(ns.state.gossipTimer)
        ns.state.gossipTimer = nil
    end
    local text, title, npc = OpenGossipData()
    return ns.PlayGossipText(text, title, npc)
end

function ns.OnGossipShow()
    if ns.state.npcLoreTimer then
        ns.CancelAfter(ns.state.npcLoreTimer)
        ns.state.npcLoreTimer = nil
    end
    if not ns.db.enabled or not ns.db.auto or not ns.db.gossipAuto then
        return
    end
    -- The classic client can fire GOSSIP_SHOW before the greeting fontstring
    -- has been populated. Read it on the next frame and deduplicate refreshes.
    local gossipEpoch = ns.state.autoGossipEpoch or 0
    ns.After(0, function()
        if (ns.state.autoGossipEpoch or 0) ~= gossipEpoch or ns.state.dialogQuest then return end
        local text, title, npc = OpenGossipData()
        text = CleanGossipText(text)
        title = CleanGossipText(title or L.GOSSIP_TITLE)
        if text == "" then
            return
        end
        local key = tostring(npc and npc.id or "") .. "\31" .. title .. "\31" .. text
        if ns.state.gossipEventKey == key then
            return
        end
        ns.state.gossipEventKey = key
        ns.state.dialogGossip = true
        ScheduleDialog("gossipTimer", GreetingDelay(), function()
            if ns.db.enabled and ns.db.auto and ns.db.gossipAuto then
                ns.PlayGossipText(text, title, npc, true)
            end
        end)
    end)
end

-- Some 3.3.5 clients update a multi-page NPC story after SelectGossipOption
-- without emitting another GOSSIP_SHOW. Fizzcrank's "The Mechagnomes" tale is
-- one such conversation: every "Go on" opens a new text page. Re-sample the
-- visible window after the server response so every page gets its own gossip
-- voice request; OnGossipShow's key still suppresses duplicate reads.
local function RefreshGossipAfterSelection()
    for _, delay in ipairs({ 0.15, 0.60 }) do
        ns.After(delay, function()
            if not ns.db.enabled or not ns.db.auto or not ns.db.gossipAuto then
                return
            end
            if GossipFrame and GossipFrame.IsShown and not GossipFrame:IsShown() then
                return
            end
            ns.OnGossipShow()
        end)
    end
end

-- The function name differs between the stock 3.3.5 client and a few custom
-- clients. Hook whichever one is present; duplicate hooks are harmless because
-- the gossip text key is deduplicated above.
if hooksecurefunc then
    for _, name in ipairs({ "SelectGossipOption", "GossipSelectOption" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, RefreshGossipAfterSelection)
        end
    end
end

-- Source-backed NPC histories use the same remote gossip transport as a
-- visible NPC greeting. The distinction is only the item kind: target lore
-- is lower priority than quest/gossip dialogue and is never tied to a quest
-- window, so it cannot replace the text the player is currently reading.
local function CancelNpcLoreTimer()
    if ns.state.npcLoreTimer then
        ns.CancelAfter(ns.state.npcLoreTimer)
        ns.state.npcLoreTimer = nil
    end
end

local function TargetNpc(id)
    if not UnitExists or not UnitExists("target") then
        return nil
    end
    if CreatureIDFromUnit("target") ~= id then
        return nil
    end
    local npc = {
        id = id,
        name = UnitName and UnitName("target") or nil,
        gender = "",
        guid = UnitGUID and UnitGUID("target") or nil,
    }
    if UnitSex then
        local sex = UnitSex("target")
        npc.gender = sex == 3 and "female" or sex == 2 and "male" or ""
    end
    return npc
end

local function TargetNpcSnapshot(id)
    local npc = TargetNpc(id)
    if not npc then
        return nil
    end
    return npc
end

function ns.ResetNpcLore()
    ns.db.npcLoreHeard = {}
    ns.state.npcLoreHeard = {}
    Print(L.NPC_LORE_RESET)
end

function ns.PlayNpcLore(npcID, force, npcOverride, afterKill)
    npcID = tonumber(npcID) or CreatureIDFromUnit("target")
    local lore = ns.GetNpcLore and ns.GetNpcLore(npcID)
    if not lore then
        Print(L.NPC_NO_LORE)
        return false
    end
    if not force and (not ns.db.enabled or not ns.db.auto or not ns.db.npcLore) then
        return false
    end
    if not force and afterKill and ns.db.npcLoreTrigger ~= "kill" then
        return false
    end
    if not force and not afterKill and ns.db.npcLoreTrigger ~= "target" then
        return false
    end

    local key = tostring(npcID) .. ":" .. ns.VoiceLocale()
    ns.db.npcLoreHeard = ns.db.npcLoreHeard or {}
    if not force and ns.db.npcLoreHeard[key] then
        return false
    end
    local npc = npcOverride or TargetNpc(npcID) or { id = npcID, name = lore.name, gender = "" }
    if lore.voiceGender == "male" or lore.voiceGender == "female" then
        -- These histories use a prepared narrator voice. The model's sex
        -- must not select a different cache entry for the same narration.
        local narrator = {}
        for field, value in pairs(npc) do narrator[field] = value end
        narrator.gender = lore.voiceGender
        npc = narrator
    end
    local title = lore.title or lore.name or L.NPC_LORE_TITLE
    local function play()
        ns.state.npcLoreTimer = nil
        if not ns.db.enabled or (not force and (not ns.db.auto or not ns.db.npcLore)) then
            return
        end
        if not force then
            if not afterKill and not TargetNpc(npcID) then
                return
            end
            if not afterKill and UnitAffectingCombat and UnitAffectingCombat("player") then
                ns.state.npcLoreTargetPending = {
                    npcID = npcID,
                    npc = npc,
                    guid = npc.guid,
                }
                return
            end
            -- Opening a normal NPC/quest dialog wins over an automatic
            -- target-history request. GOSSIP_SHOW/QUEST_DETAIL also cancel
            -- this timer, but keep this guard for custom 3.3.5 clients.
            if not afterKill and ((GossipFrame and GossipFrame.IsShown and GossipFrame:IsShown())
                or (QuestFrame and QuestFrame.IsShown and QuestFrame:IsShown())) then
                return
            end
            -- With queueing disabled, automatic lore must not cut a line the
            -- player explicitly started or a standard greeting in flight.
            if ns.db.queue == false
                and (ns.state.active or #ns.state.queue > 0 or #ns.state.pending > 0) then
                return
            end
        end
        local ok = ns.PlayGossipText(lore.text, title, npc, not force, "npcLore", npcID)
        if ok then
            ns.db.npcLoreHeard[key] = true
            ns.state.npcLoreHeard[key] = true
        end
    end

    if force or afterKill then
        play()
    else
        local delay = ns.db.greetDelay and 1.5 or 0
        ScheduleDialog("npcLoreTimer", delay, play)
    end
    return true
end

function ns.OnTargetChanged()
    CancelNpcLoreTimer()
    ns.state.npcLoreTargetPending = nil
    local npcID = CreatureIDFromUnit("target")
    local snapshot = npcID and ns.GetNpcLore and ns.GetNpcLore(npcID)
        and TargetNpcSnapshot(npcID) or nil
    ns.state.npcLoreTarget = snapshot
    if not ns.db.enabled or not ns.db.auto or not ns.db.npcLore
        or ns.db.npcLoreTrigger ~= "target" then
        return
    end
    if snapshot then
        ns.PlayNpcLore(npcID, false)
    end
end

local function ScheduleNpcLoreAfterKill()
    local pending = ns.state.npcLoreKillPending
    if not pending or ns.db.npcLoreTrigger ~= "kill" then
        return
    end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        return
    end
    if ns.state.npcLoreKillTimer then
        ns.CancelAfter(ns.state.npcLoreKillTimer)
    end
    ns.state.npcLoreKillTimer = ns.After(0.75, function()
        ns.state.npcLoreKillTimer = nil
        if ns.state.npcLoreKillPending ~= pending then
            return
        end
        ns.state.npcLoreKillPending = nil
        ns.PlayNpcLore(pending.npcID, false, pending.npc, true)
    end)
end

local function ScheduleNpcLoreAfterTarget()
    local pending = ns.state.npcLoreTargetPending
    if not pending or ns.db.npcLoreTrigger ~= "target" then
        return
    end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        return
    end
    local target = TargetNpc(pending.npcID)
    if not target or (pending.guid and target.guid and pending.guid ~= target.guid) then
        ns.state.npcLoreTargetPending = nil
        return
    end
    ns.state.npcLoreTargetPending = nil
    ns.PlayNpcLore(pending.npcID, false, target, false)
end

function ns.OnNpcLoreCombatEvent(...)
    if not ns.db.enabled or not ns.db.auto or not ns.db.npcLore
        or ns.db.npcLoreTrigger ~= "kill" then
        return
    end
    local subEvent, destGUID
    if CombatLogGetCurrentEventInfo then
        local _, eventType, _, _, _, _, _, destinationGUID = CombatLogGetCurrentEventInfo()
        subEvent, destGUID = eventType, destinationGUID
    else
        subEvent, destGUID = select(2, ...), select(8, ...)
    end
    if subEvent ~= "UNIT_DIED" then
        return
    end
    local target = ns.state.npcLoreTarget
    if not target or not target.guid or destGUID ~= target.guid then
        return
    end
    ns.state.npcLoreKillPending = {
        npcID = target.id,
        npc = target,
    }
    ScheduleNpcLoreAfterKill()
end

function ns.OnNpcLoreCombatEnded()
    ScheduleNpcLoreAfterKill()
    ScheduleNpcLoreAfterTarget()
end

-- Lua errors of this addon go to the extension, which reports them to the
-- server (unless statistics are off). The text is cut to what one message
-- holds, at a whole UTF-8 character. Each error once per page load, at most
-- a few: the slots are few.
local ERRORS_PER_LOAD = 4
function ns.ErrorBytes(text)
    text = tostring(text or "")
    text = string.gsub(text, "Interface\\AddOns\\", "")
    text = string.gsub(text, "Interface/AddOns/", "")
    text = string.gsub(text, "%s+", " ")
    local limit = WHO_MAX_BYTES - 3
    if string.len(text) > limit then
        text = string.sub(text, 1, limit)
        -- Drop a cut UTF-8 sequence at the end.
        while string.len(text) > 0 do
            local last = string.byte(text, -1)
            if last < 128 then
                break
            end
            local start = string.len(text)
            while start > 1 and string.byte(text, start) >= 128 and string.byte(text, start) < 192 do
                start = start - 1
            end
            local lead = string.byte(text, start)
            local need = lead >= 240 and 4 or lead >= 224 and 3 or lead >= 192 and 2 or 1
            if string.len(text) - start + 1 == need then
                break
            end
            text = string.sub(text, 1, start - 1)
        end
    end
    if text == "" then
        return nil
    end
    return Frame(2, { string.byte(text, 1, -1) })
end

function ns.ReportError(text)
    ns.state.errorsSent = ns.state.errorsSent or {}
    local key = tostring(text)
    if ns.state.errorsSent[key] or (ns.state.errorsCount or 0) >= ERRORS_PER_LOAD then
        return false
    end
    VoiceLog(ns.state.active or ns.state.pending[1] or {kind="lua"}, "lua-error", tostring(text))
    if SendBytes(ns.ErrorBytes(text)) then
        ns.state.errorsSent[key] = true
        ns.state.errorsCount = (ns.state.errorsCount or 0) + 1
        return true
    end
    return false
end

-- Errors outside the event handler (timers, frame scripts): the game's error
-- handler sees them; ours passes them on and keeps the game's behaviour.
if geterrorhandler and seterrorhandler then
    local previous = geterrorhandler()
    seterrorhandler(function(message, ...)
        if type(message) == "string" and string.find(message, "CatQuest", 1, true) then
            pcall(ns.ReportError, message)
        end
        if previous then
            return previous(message, ...)
        end
    end)
end

function ns.SetLanguage(value)
    value = tostring(value or "")
    if string.lower(value) == "auto" or string.lower(value) == "a" then
        ns.db.language = "auto"
    else
        local locale = ns.NormalizeLocale(value)
        if not locale then
            Print(L.LANG_USAGE)
            return false
        end
        ns.db.language = locale
    end
    ns.PrintLanguage()
    ns.AnnounceChoice()
    return true
end

-- Interface language (Russian or English). The bridge keeps the choice and
-- writes it into Bridge.lua on the next page load, and its panel over the
-- game uses the same language.
function ns.SetUILanguage(value)
    value = string.lower(tostring(value or ""))
    local locale
    if value == "auto" or value == "a" then
        locale = "auto"
    else
        locale = ns.NormalizeLocale(value)
        if locale ~= "ruRU" and locale ~= "enUS" then
            Print(L.UI_USAGE)
            return false
        end
    end
    ns.db.uiLanguage = locale
    if ns.RefreshTexts then
        ns.RefreshTexts()
    end
    Print(string.format(L.UI_SET, ns.LanguageName(ns.UILocale())))
    if ns.db.remoteEnabled then
        pcall(PlaySoundFile, "Interface\\AddOns\\CatQuest335_ServerVoices\\ui\\" .. locale .. ".ogg", "Master")
    end
    return true
end

local function PrintHistory()
    local history = ns.db.history or {}
    if #history == 0 then
        Print(L.HISTORY_EMPTY)
        return
    end
    Print(L.HISTORY_TITLE)
    for i = #history, math.max(1, #history - 9), -1 do
        local entry = history[i]
        local when = date and entry.at and date("%H:%M", entry.at) or ""
        Print(when .. "  " .. (entry.title or string.format(L.QUEST_N, tostring(entry.questID))))
    end
end

local function PrintVoiceLog(argument)
    if string.lower(argument or "") == "clear" then
        ns.db.voiceLog = {}
        Print(L.LOG_CLEARED)
        return
    end
    local log = ns.db.voiceLog or {}
    if #log == 0 then
        Print(L.LOG_EMPTY)
        return
    end
    Print(L.LOG_HEADER)
    local active = ns.state.active and "playing" or ns.state.pending[1] and "waiting" or "idle"
    Print(string.format("state=%s queue=%d pending=%d", active, #ns.state.queue, #ns.state.pending))
    for _, list in ipairs({ ns.state.pending, ns.state.queue }) do
        for index, item in ipairs(list) do
            if index > 5 then break end
            Print(string.format("%s #%d q%s %s: %s", list == ns.state.pending and "pending" or "queue",
                index, tostring(item.questID or 0), tostring(item.kind), tostring(item.title or "")))
        end
    end
    for i = #log, math.max(1, #log - 19), -1 do
        local entry = log[i]
        local when = date and entry.at and date("%H:%M:%S", entry.at) or "--:--:--"
        local id = tonumber(entry.questID) or 0
        local identity = id > 0 and ("q" .. tostring(id)) or (entry.kind ~= "" and entry.kind or "item")
        local title = entry.title ~= "" and entry.title or "без названия"
        local detail = entry.detail ~= "" and (" — " .. entry.detail) or ""
        Print(string.format("%s [%s] %s: %s%s", when, tostring(entry.status or "?"), identity, title, detail))
    end
    if #log > 20 then
        Print(string.format("... ещё %d записей; /cq log clear — очистить", #log - 20))
    end
end

local function HandleSlash(message)
    local command, argument = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")

    if command == "debug" then
        if ns.OpenDebug then ns.OpenDebug() end
    elseif command == "status" then
        local a, p = ns.state.active, ns.state.pending[1]
        local item = a or p or ns.state.queue[1] or ns.state.lastItem
        Print(string.format("v%s phase=%s quest=%s queue=%d pending=%d channel=%s", ns.VERSION,
            a and "playing" or p and "waiting" or "idle", tostring(item and item.questID or "-"),
            #ns.state.queue, #ns.state.pending, tostring(ns.db.volumeChannel)))
        if item then
            Print(string.format("file=%s duration=%s font=%s unit=%s verified=%s", tostring(item.file),
                tostring(item.duration), tostring(item.readyFontObserved), tostring(item.readyFontUnit), tostring(item.bridgeVerified)))
            Print(string.format("signal=%s attempts=%s requestedFont=%s error=%s", tostring(item.prefetchSlot),
                tostring(item.readySignalAttempts), tostring(item.readyFontRequested), tostring(item.readySignalError)))
        end
    elseif command == "stop" then
        ns.Stop()
    elseif command == "next" or command == "skip" then
        ns.Skip()
    elseif command == "replay" or command == "repeat" or command == "r" then
        ns.Replay()
    elseif command == "auto" then
        ns.db.auto = not ns.db.auto
        Print(string.format(L.AUTO, ns.db.auto and L.ON or L.OFF))
    elseif command == "pack" then
        local pack = string.lower(argument or "")
        if pack == "auto" or pack == "original" then
            ns.db.pack = pack
            Print(string.format(L.PACK_SET, pack))
        else
            Print("/cq pack auto | original")
        end
    elseif command == "subtitle" then
        local value = string.lower(argument or "")
        if value == "on" or value == "off" then
            ns.db.showSubtitle = value == "on"
        else
            ns.db.showSubtitle = not ns.db.showSubtitle
        end
        Print(string.format(L.SUBTITLES, ns.db.showSubtitle and L.ON or L.OFF))
    elseif command == "missing" then
        local count = 0
        for _, item in pairs(ns.db.missing or {}) do
            count = count + 1
            Print(tostring(item.questID) .. " " .. tostring(item.kind))
        end
        Print(string.format(L.MISSING_COUNT, count))
    elseif command == "clear-missing" then
        ns.db.missing = {}
        Print(L.MISSING_CLEARED)
    elseif command == "on" then
        ns.db.enabled = true
        Print(L.ADDON_ON)
    elseif command == "off" then
        ns.db.enabled = false
        ns.Stop()
        Print(L.ADDON_OFF)
    elseif command == "remote" then
        local value = string.lower(argument or "")
        if value == "on" or value == "off" then
            ns.db.remoteEnabled = value == "on"
        else
            ns.db.remoteEnabled = not ns.db.remoteEnabled
        end
        Print(string.format(L.REMOTE, ns.db.remoteEnabled and L.ON or L.OFF))
    elseif command == "dm" then
        if ns.DungeonCommand then ns.DungeonCommand(string.lower(argument or "")) end
    elseif command == "npc" or command == "npc-lore" then
        local value = string.lower(argument or "")
        if value == "on" or value == "off" then
            ns.db.npcLore = value == "on"
            Print(string.format(L.NPC_LORE, ns.db.npcLore and L.ON or L.OFF))
        elseif value == "reset" then
            ns.ResetNpcLore()
        else
            ns.PlayNpcLore(nil, true)
        end
    elseif command == "rate" then
        if ns.OpenQuestRating then ns.OpenQuestRating(tonumber(argument)) end
    elseif command == "bug" or command == "report" then
        if ns.OpenFeedback then
            ns.OpenFeedback()
        end
    elseif command == "ui" then
        if argument ~= "" then
            ns.SetUILanguage(argument)
        else
            Print(string.format(L.UI_SET, ns.LanguageName(ns.UILocale())))
            Print(L.UI_USAGE)
        end
    elseif command == "lang" or command == "language" then
        if argument ~= "" then
            ns.SetLanguage(argument)
        else
            ns.PrintLanguage()
            Print(L.LANG_USAGE)
        end
    elseif command == "story" or command == "history" then
        if ns.ToggleStory then
            ns.ToggleStory()
        end
    elseif command == "options" or command == "config" then
        if ns.OpenOptions then
            ns.OpenOptions()
        end
    elseif command == "map" or command == "place" or command == "here" or command == "places" or command == "lore" then
        -- /cq map: replay the lore of this place; /cq map on|off: switch it.
        -- "places" and "place" are older names of the same command.
        local value = string.lower(argument or "")
        if value == "on" or value == "off" then
            ns.db.places = value == "on"
            Print(string.format(L.PLACES, ns.db.places and L.ON or L.OFF))
        elseif value == "reset" then
            -- /cq lore reset (original): forget the places already heard.
            if ns.ResetPlaces then
                ns.ResetPlaces()
            else
                ns.db.placesHeard = {}
                Print(L.LORE_RESET)
            end
        elseif command == "places" then
            ns.db.places = not ns.db.places
            Print(string.format(L.PLACES, ns.db.places and L.ON or L.OFF))
        else
            ns.ReadPlace(true)
        end
    elseif command == "books" then
        local value = string.lower(argument or "")
        if value == "on" or value == "off" then
            ns.db[command] = value == "on"
        else
            ns.db[command] = not ns.db[command]
        end
        Print(string.format(command == "books" and L.BOOKS or L.PLACES, ns.db[command] and L.ON or L.OFF))
    elseif command == "play" then
        -- Original /cq play: replay the last line, or stop the one playing.
        if ns.state.active then
            ns.Stop()
        else
            ns.Replay()
        end
    elseif command == "h" then
        PrintHistory()
    elseif command == "log" then
        if argument == "play" or argument == "quest" then
            -- Compatibility with the old meaning of /cq log.
            ns.PlaySelectedQuest()
        else
            PrintVoiceLog(argument)
        end
    elseif command == "selected" then
        ns.PlaySelectedQuest()
    elseif command == "probe" and argument == "tex" then
        ns.ProbeTextures()
    elseif command == "probe" then
        ns.Probe(tonumber(argument) or 606)
    elseif command == "test" then
        ns.PlayQuest(tonumber(argument) or 2, "quest", true)
    elseif command == "current" or command == "id" then
        PrintCurrentQuest()
    elseif tonumber(command) then
        ns.PlayQuest(tonumber(command), "quest", true)
    else
        -- /cq, /cq help or anything unknown: what a player needs, short.
        Print(L.HELP_LIST)
        Print(L.HELP_OPTIONS)
        Print(L.HELP_LANG)
        Print(L.UI_USAGE)
        Print(L.FB_USAGE)
        Print(L.HELP_STORY)
        Print(L.HELP_BOOKS)
        Print(L.HELP_LORE)
        Print(L.HELP_NPC_LORE)
        Print(L.HELP_PROBE)
    end
end

SLASH_CATQUEST3351 = "/cq"
SlashCmdList.CATQUEST335 = HandleSlash

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("QUEST_DETAIL")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_PROGRESS")
eventFrame:RegisterEvent("QUEST_COMPLETE")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("QUEST_FINISHED")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("GOSSIP_CLOSED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
local lastErrorAt = 0
local function OnEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        -- Lasthavens: the browser extension adds Bridge.lua with the player's
        -- last /cq lang choice, since reloading the page (F5) does not save
        -- the addon's settings.
        local choice = CatQuest335_BridgeChoice
        if type(choice) == "string" then
            if string.lower(choice) == "auto" then
                ns.db.language = "auto"
            elseif ns.NormalizeLocale(choice) then
                ns.db.language = ns.NormalizeLocale(choice)
            end
        end
        ns.After(2, ns.AnnounceLanguage)
        ns.After(5, ns.AnnounceCharacter)
        -- Volumes ducked before a reload come back.
        RestoreSoundTweaks()
        RestoreMusicVoice()
        if ns.ApplyWindowPosition then
            ns.ApplyWindowPosition()
        end
        if ns.ApplyWindowSettings then
            ns.ApplyWindowSettings()
        end
        if ns.InstallQuestFrameButton then
            ns.InstallQuestFrameButton()
        end
        if ns.InstallGossipButton then
            ns.InstallGossipButton()
        end
        local _, packFolder = HasVoiceData()
        if packFolder then
            Print(L.LOADED_PACK)
        else
            Print(L.LOADED)
        end
        if ns.InstallQuestLogButton then
            ns.InstallQuestLogButton()
        end
        return
    end
    if event == "QUEST_ACCEPTED" then
        OnQuestAccepted(select(1, ...))
        return
    end
    if event == "QUEST_FINISHED" then
        -- The quest dialog closed: the NPC unit is gone.
        ns.state.dialogQuest = nil
        ns.state.dialogEventKey = nil
        ns.state.acceptPending = nil
        if ns.db.stopOnClose and ns.state.dialogTimer then
            ns.CancelAfter(ns.state.dialogTimer)
            ns.state.dialogTimer = nil
        end
        -- stopOnClose (settings): closing the window stops its line.
        if ns.db.stopOnClose and ns.state.dialogKey then
            local key,epoch=ns.state.dialogKey,ns.state.stopEpoch or 0
            ns.After(0,function()
                if (ns.state.stopEpoch or 0)~=epoch then return end
                local claimed=ns.state.active and ns.state.active.key==key and ns.state.active.turninClaimed
                for _,list in ipairs({ns.state.queue,ns.state.pending}) do
                    for _,item in ipairs(list) do if item.key==key and item.turninClaimed then claimed=true end end
                end
                if not claimed then ns.DropItem(key) end
            end)
        end
        ns.state.dialogKey = nil
        return
    end
    if event == "QUEST_LOG_UPDATE" then
        if ns.InstallQuestLogButton then
            ns.InstallQuestLogButton()
        end
        return
    end
    if event == "GOSSIP_SHOW" then
        if ns.InstallGossipButton then
            ns.InstallGossipButton()
        end
        ns.OnGossipShow()
        return
    end
    if event == "GOSSIP_CLOSED" then
        ns.state.dialogGossip = nil
        ns.state.gossipEventKey = nil
        if ns.db.stopOnClose and ns.state.gossipTimer then
            ns.CancelAfter(ns.state.gossipTimer)
            ns.state.gossipTimer = nil
        end
        if ns.db.stopOnClose and ns.state.dialogKey
            and string.sub(ns.state.dialogKey, 1, 7) == "gossip:" then
            ns.DropItem(ns.state.dialogKey)
        end
        if ns.state.dialogKey and string.sub(ns.state.dialogKey, 1, 7) == "gossip:" then
            ns.state.dialogKey = nil
        end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        ns.OnTargetChanged()
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        ns.OnNpcLoreCombatEvent(...)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        ns.OnNpcLoreCombatEnded()
        return
    end
    OnQuestEvent(event)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(OnEvent, event, ...)
    if not ok and GetTime() - lastErrorAt > 10 then
        lastErrorAt = GetTime()
        Print(string.format(L.HANDLER_ERROR, tostring(event), tostring(err)))
    end
    if not ok and ns.ReportError then
        pcall(ns.ReportError, tostring(event) .. ": " .. tostring(err))
    end
end)
