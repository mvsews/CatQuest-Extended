local addonName = ...
local ns = CatQuest335 or {}
CatQuest335 = ns
ns.VERSION = "0.10.51"
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
    greetDelay = true, -- let the game's standard NPC greeting finish first
    showSubtitle = true,
    -- SFX, not Master: Stop silences the SFX channel for a moment, which
    -- leaves music and ambience untouched.
    volumeChannel = "SFX",
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
    minimap = true,      -- scroll button on the minimap
    -- Start in the upper-left quadrant; the old 200-degree default commonly
    -- overlapped other minimap-button addons.
    minimapAngle = 135,
    minimapLocked = false, -- do not move the minimap button by dragging
    storyQuestTitles = false, -- show the first quest title before a chapter starts
    places = true,       -- tell the lore of a place on the first visit
    placesHeard = {},
    pack = "auto",
    history = {},
    missing = {},
    remoteEnabled = true,
    remoteDuration = 90, -- upper bound for an estimated server track, seconds
    pendingTimeout = 300, -- how long a requested track may take before giving up, s
    remoteRetry = 0.5,   -- PlaySoundFile retry interval while the bridge fetches audio
    language = "auto",   -- voice language: "auto" follows the client, or a locale such as "zhCN"
    gossipAudioSlot = 0,  -- rotating virtual files for NPC gossip speech
    gossipMarkerSlot = 0, -- rotating marker slots used to send gossip text
    npcLoreHeard = {}, -- NPCID:locale -> true; source-backed history is heard once
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
-- On an online first install, restore the safe user-facing settings supplied
-- by the authorized extension. Existing SavedVariables always win: replacing
-- an addon must never reset a player's local choices.
local hadSavedSettings = next(CatQuest335DB) ~= nil
if not CatQuest335_LocalMode and not hadSavedSettings and type(CatQuest335_BridgeSettings) == "table" then
    for key, value in pairs(CatQuest335_BridgeSettings) do
        if defaults[key] ~= nil and type(defaults[key]) == type(value) then
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
ns.db = CatQuest335DB

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
        if cues then
            return quest, candidate.folder, track, cues, genderSuffix, npcSuffix, npcID
        end
    end
    return nil, nil, nil, nil, nil, "", npcID
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

    -- The client can return "" for the title; fall back to the quest log.
    local title = titleOverride or quest.title
    if (not title or title == "") and GetTitleText then
        title = GetTitleText()
    end
    if (not title or title == "") and GetNumQuestLogEntries and GetQuestLogTitle then
        for index = 1, GetNumQuestLogEntries() do
            -- Returns can contain nil (quest tag, completion), so # is unreliable.
            local count = select("#", GetQuestLogTitle(index))
            local values = { GetQuestLogTitle(index) }
            for i = 8, count do
                if values[i] == questID then
                    title = values[1]
                end
            end
        end
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

local function CallPlaySound(path)
    local channel = ns.db.volumeChannel or "Master"
    local ok, result = pcall(PlaySoundFile, path, channel)
    -- The original 3.3.5a API may return nothing even when playback starts.
    -- Local pack tracks were selected from its index; nil is not a reason to
    -- play the same file a second time on SFX.
    if ok and result ~= false then
        return channel
    end

    local fallbackOK, fallbackResult = pcall(PlaySoundFile, path, "SFX")
    if fallbackOK and fallbackResult ~= false then
        return "SFX"
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

local function ApplySoundTweaks()
    if ns.state.tweaked or not GetCVar or not SetCVar then
        return
    end
    ns.state.tweaked = true
    local saved = {}
    local duck = tonumber(ns.db.duck) or 0
    if duck > 0 then
        local cvars = { "Sound_MusicVolume" }
        if ns.db.volumeChannel ~= "Ambience" then
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
    ns.state.demandShown = nil
    ns.state.lastItem = item
    ns.state.lastPlayedKey = item.key
    ns.state.lastPlayedAt = item.startedAt
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
-- Tracks the server is still voicing wait here instead of blocking the queue.
-- When nothing plays, one of them is tried per second; the first that has
-- arrived starts by itself, so the player never has to ask twice.
ns.state.pending = ns.state.pending or {}

local function TryPlay(item)
    -- One call per attempt: every miss is a file read that reaches the bridge.
    local ok, result = pcall(PlaySoundFile, item.file, ns.db.volumeChannel or "Master")
    local ready = CatQuest335_BridgeReady
    if type(ready) == "table" and ready.mode == "local" then
        -- The local manifest established that this file is installed; the
        -- original client does not have a useful success return value.
        return ok and result ~= false
    end
    -- Lasthavens' virtual filesystem uses a truthy result to signal a ready
    -- read. Preserve that distinction for online retries.
    return ok and result
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

local function PollDemand()
    local times = ns.state.pollTimes
    local now = GetTime()
    if not times or not times[1] or times[1] > now then
        return
    end
    -- Polls that came due together are one poll.
    while times[1] and times[1] <= now do
        table.remove(times, 1)
    end
    local n = (tonumber(ns.db.pollSeq) or 0) % POLL_SLOTS + 1
    ns.db.pollSeq = n
    pcall(PlaySoundFile, "Interface\\AddOns\\CatQuest335_ServerVoices\\poll\\" .. n .. ".ogg",
        ns.db.volumeChannel or "Master")
end

local function StartItem(item)
    local trackState = item.remote and TrackState(item)
    if item.remote and trackState == "missing" then
        ns.state.lastItem = item
        Print(string.format(L.NO_LOCAL_TRACK or L.NO_TRACK, tostring(item.questID),
            "https://t.me/warcraft_rus_chat"))
        return false
    end
    if item.remote and trackState == "companion" then
        if not CompanionSpeak(item) then
            ns.state.lastItem = item
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
        return false
    end
    if item.remote and IsOnDemand(item) then
        TryPlay(item)
        -- Keep the request in the normal retry queue as well.
        if not FindPending(item.key) then
            AddPending(item, true)
            -- The game caches the quest path after the first miss. Poll with
            -- fresh filenames so a track generated later is handed to WoW.
            SchedulePolls()
        end
        -- Keep every requested item in the same pending retry queue. The old
        -- poll-only path could play the newly ready track outside active and
        -- then leave the head window stuck; retrying the actual item lets the
        -- queue own the start and the end of the sound.
        ns.state.lastItem = item
        ns.state.lastPlayedKey = item.key
        ns.state.lastPlayedAt = GetTime()
        Remember(item)
        if ns.ShowDemand and not ns.state.active and not CatQuest335_BridgeReady.budgetOut then
            ns.ShowDemand(item)
            ns.state.demandShown = item
            item.demandHideAt = GetTime() + DEMAND_WINDOW_SECONDS
            -- Voicing takes up to a minute or two, then the track plays.
            ns.After(DEMAND_WINDOW_SECONDS, function()
                ClearDemandWindow(item)
            end)
        end
        if CatQuest335_BridgeReady.budgetOut then
            -- The server would not voice it now. The request above still goes
            -- out, so a topped-up budget voices it after all.
            if not ns.state.budgetHinted then
                ns.state.budgetHinted = true
                Print(L.BUDGET_OUT)
            end
        else
            Print(string.format(L.REQUESTED, item.title or tostring(item.questID)))
        end
        return false
    end
    if item.remote then
        if TryPlay(item) then
            BeginPlaying(item)
            return true
        end
        -- Not ready: the read above asked the server to voice it.
        AddPending(item)
        return false
    end

    local channel = CallPlaySound(item.file)
    if not channel then
        if ns.state.active == item then
            ns.state.active = nil
        end
        if ns.HideHead then
            ns.HideHead()
        end
        Print(string.format(L.PLAY_FAILED, item.file))
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
    local pages = SplitPages(text)
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
        npc = npc,
        npcLoreID = tonumber(loreID),
        remote = true,
        dialog = kind ~= "npcLore",
        text = text,
    }
end
ns.BuildGossipItem = BuildGossipItem

local nextPendingAt, pendingCursor = 0, 0
local function ProcessPending()
    local pending = ns.state.pending
    local now = GetTime()
    if #pending == 0 or now < nextPendingAt then
        return
    end
    nextPendingAt = now + 1
    local limit = tonumber(ns.db.pendingTimeout) or 300
    for i = #pending, 1, -1 do
        local item = pending[i]
        if now - item.requestedAt >= limit then
            table.remove(pending, i)
            RememberMissing(item.questID, item.kind)
            Print(string.format(L.NOTICE_TIMEOUT, item.title or tostring(item.questID), math.floor(limit)))
        end
    end
    if #pending == 0 then
        return
    end
    pendingCursor = pendingCursor % #pending + 1
    local item = pending[pendingCursor]
    if TryPlay(item) then
        table.remove(pending, pendingCursor)
        BeginPlaying(item)
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
        local item = table.remove(ns.state.queue, 1)
        if not item then
            break
        end
        if StartItem(item) then
            return
        end
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
    return item and (item.kind == "place" or item.kind == "npcLore")
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

function ns.PlayQuest(questID, kind, force, text, title, npcID)
    kind = kind or "quest"
    if text == nil then
        text = QuestTextFor(nil, kind)
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
    return ns.PlayItem(item, force)
end

-- Queue any prepared item (quest, book page, place lore): one queue, one
-- pause between tracks, one Stop for all of them.
function ns.PlayItem(item, force, replay)
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
    if ns.db.queue == false and (ns.state.active or #ns.state.queue > 0 or #ns.state.pending > 0) then
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
    if not GetCVar or not SetCVar then
        return
    end
    local channel = (ns.state.active and ns.state.active.playChannel)
        or ns.state.lastAudioChannel or ns.db.volumeChannel
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
    SilenceVoice()
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
        StartNext()
        -- Only when nothing plays: a waiting track must not overlap another.
        if not ns.state.active and #ns.state.queue == 0 and GetTime() >= (ns.state.resumeAt or 0) then
            ProcessPending()
            PollDemand()
        end
        if ns.state.tweaked and not ns.state.active and #ns.state.queue == 0 then
            RestoreSoundTweaks()
        end
        return
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
    if duration > 0 and elapsed >= duration + 0.15 then
        ns.state.active = nil
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
    local title = GetTitleText and GetTitleText() or nil
    local questID = CurrentQuestID()
    if not questID and title and title ~= "" then
        questID = QuestIDFromTitle(title)
    end
    if not questID then
        questID = SelectedQuestID()
    end
    if not title or title == "" then
        title = SelectedQuestTitle()
    end
    if questID then
        Print(string.format(L.CURRENT_QUEST, tostring(title or L.NO_TITLE), tostring(questID)))
    else
        Print(L.NO_CURRENT)
    end
end

function ns.PlaySelectedQuest()
    local questID = SelectedQuestID()
    if questID then
        ns.PlayQuest(questID, "quest", true)
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

local function OnQuestEvent(event, manual)
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
    local function play()
        if not ns.db.enabled then
            return
        end
        if ns.db.stopOnClose and ns.state.dialogQuest ~= questID then
            return
        end
        ns.state.recent[questID .. ":" .. kind] = GetTime()
        ns.state.dialogKey = QuestDialogKey(questID, kind, npcID)
        ns.PlayQuest(questID, kind, manual and true or false, text, nil, npcID)
    end
    ScheduleDialog("dialogTimer", manual and 0 or GreetingDelay(), play)
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
    if type(questIndexOrID) == "number" and GetQuestData(questIndexOrID) then
        questID = questIndexOrID
    elseif type(questIndexOrID) == "number" and GetQuestLogTitle then
        questID = QuestIDFromValues({ GetQuestLogTitle(questIndexOrID) })
    end

    -- QUEST_ACCEPTED is a fallback for builds without GetQuestID: the quest
    -- dialog usually voiced this quest already, so do not read it twice.
    local heard = questID and ns.state.recent[questID .. ":quest"]
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
            local ok, a, b = pcall(PlaySoundFile, paths[i], ns.db.volumeChannel or "Master")
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
local function Frame(kind, payload)
    if #payload + 3 > WHO_MAX_BYTES then
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

function ns.CharacterBytes()
    local realm = GetRealmName and GetRealmName() or ""
    local name = UnitName and UnitName("player") or ""
    local guid = UnitGUID and UnitGUID("player") or ""
    local hex = string.match(guid, "^0[xX](%x+)$")
    if realm == "" or name == "" or not hex or string.len(hex) ~= 16 then
        return nil
    end
    local payload = { string.byte(realm .. "\t" .. name .. "\t", 1, -1) }
    for i = 1, 16, 2 do
        payload[#payload + 1] = tonumber(string.sub(hex, i, i + 1), 16)
    end
    return Frame(1, payload)
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

local function SendMarkerFiles(files, onDone)
    if not files or not ns.db.remoteEnabled or CatQuest335_LocalMode
        or type(CatQuest335_BridgeReady) ~= "table"
        or CatQuest335_BridgeReady.mode == "local" then
        return false
    end
    local index = 1
    local function Next()
        for _ = 1, 8 do
            local file = files[index]
            if not file then
                return
            end
            index = index + 1
            pcall(PlaySoundFile, "Interface\\AddOns\\CatQuest335_ServerVoices\\" .. file .. ".ogg", "Master")
        end
        if files[index] then
            ns.After(0.2, Next)
        elseif onDone then
            ns.After(0.5, onDone)
        end
    end
    Next()
    return true
end

local function SendBytes(bytes)
    if not bytes or not ns.db.remoteEnabled or CatQuest335_LocalMode
        or type(CatQuest335_BridgeReady) ~= "table"
        or CatQuest335_BridgeReady.mode == "local" then
        return false
    end
    local slot = (tonumber(ns.db.whoSlot) or 0) % WHO_SLOTS + 1
    ns.db.whoSlot = slot
    return SendMarkerFiles(MarkerFiles(bytes, slot, "who"))
end

-- The browser game does not reliably write SavedVariables on F5. Keep the
-- two settings that affect the speech window/audio ducking in sync as soon
-- as the player changes them, using the same small marker channel as the
-- character report. The bridge accepts a partial settings object and merges
-- it with the rest of the account settings.
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
        local text = string.format("scale=%.2f\tduck=%d", scale, duck)
        return SendBytes(Frame(5, { string.byte(text, 1, -1) }))
    end)
    return true
end

function ns.AnnounceCharacter()
    return SendBytes(ns.CharacterBytes())
end

-- A message of another kind (3: feedback, Feedback.lua). False when it
-- cannot go out (not Lasthavens, server voices off, too long).
function ns.SendMessageBytes(kind, payload)
    return SendBytes(Frame(kind, payload))
end
ns.MESSAGE_MAX_PAYLOAD = WHO_MAX_BYTES - 3

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

local function SendGossipText(title, text, npc, onReady)
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
    title = CleanGossipText(title or L.GOSSIP_TITLE)
    if text == "" then
        Print(L.NO_GOSSIP_TEXT)
        return false
    end
    if kind ~= "npcLore" then
        ns.state.dialogGossip = true
    end
    if directCompanion then
        local item = BuildGossipItem(text, title, nil, npc, kind, loreID)
        if not item then
            if not quiet then
                Print(string.format(L.NO_LOCAL_GOSSIP, "https://t.me/warcraft_rus_chat"))
            end
            return false
        end
        ns.state.dialogKey = item.key
        local ok = ns.PlayItem(item, false)
        if ok and not quiet then
            Print(string.format(L.REQUESTED, title))
        end
        return ok
    end
    local ok = SendGossipText(title, text, npc, function(audioSlot)
        local item = BuildGossipItem(text, title, audioSlot, npc, kind, loreID)
        if item then
            ns.state.dialogKey = item.key
            ns.PlayItem(item, false)
        end
    end)
    if not ok then
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
    ns.After(0, function()
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

local function HandleSlash(message)
    local command, argument = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")

    if command == "stop" then
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
        ns.After(6, ns.AnnounceSettings)
        -- Volumes ducked before a reload come back.
        RestoreSoundTweaks()
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
            ns.DropItem(ns.state.dialogKey)
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
