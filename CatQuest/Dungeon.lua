local ns = CatQuest335
local current, key, busyUntil = nil, nil, 0
local flight, epoch = {}, 0
local cinematic, calmAt = false, nil
local function Enabled()
    return ns.db.enabled and ns.db.dungeonMaster and ns.VoiceLocale() == "ruRU"
end
local function Dead() return UnitIsDeadOrGhost("player") end
local function GroupCombat()
    if UnitAffectingCombat("player") then return true end
    local count = GetNumRaidMembers and GetNumRaidMembers() or 0
    local prefix = count > 0 and "raid" or "party"
    if count == 0 then count = GetNumPartyMembers and GetNumPartyMembers() or 0 end
    for i = 1, count do
        if UnitAffectingCombat(prefix .. i) then return true end
    end
    return false
end
local function Context(data)
    local ctx = {now = time(), combat = GroupCombat(), quests = {}, items = {},
        subzone = GetSubZoneText and GetSubZoneText() or "",
        faction = UnitFactionGroup and UnitFactionGroup("player") or ""}
    for i = 1, (GetNumQuestLogEntries and GetNumQuestLogEntries() or 0) do
        local _, _, _, header, _, _, _, id = GetQuestLogTitle(i)
        if not header and id then ctx.quests[id] = true end
    end
    for _, e in ipairs((data or (current and current.data) or {}).events or {}) do
        if e.item then ctx.items[e.item] = GetItemCount and GetItemCount(e.item) > 0 or false end
    end
    return ctx
end
local function Cancel(dismiss)
    epoch = epoch + 1
    for sceneKey, item in pairs(flight) do
        if dismiss and current then current:Finish(sceneKey, Context(), true) end
        ns.DropItem(item.key)
    end
    flight = {}
end
ns.DungeonStop = function()
    Cancel(true)
    if current then current.muted = true end
end
ns.DungeonSettingsChanged = function()
    Cancel(false)
    if current then current.muted = false end
end
function ns.DungeonOwnsPlace(mapID)
    return Enabled() and ns.DungeonData[tonumber(mapID)] ~= nil
end
local function Enter()
    local _, kind, difficulty, _, _, _, _, mapID = GetInstanceInfo()
    local data = (kind == "party" or kind == "raid") and ns.DungeonData[mapID]
    local nextKey = data and (tostring(mapID) .. ":" .. tostring(difficulty))
    if nextKey == key then return end
    Cancel(false)
    if current then current.saved.leftAt = time() end
    current, key = nil, nextKey
    if not data then return end
    if Dead() then key = nil; return end
    ns.db.dungeonSessions = ns.db.dungeonSessions or {}
    current = ns.NewDungeonSession(data, ns.db.dungeonSessions[key], time())
    ns.db.dungeonSessions[key] = current.saved
    current:Observe(Context())
end
local function ResetCopy()
    local data, saved = current.data, current.saved
    Cancel(false)
    current = ns.NewDungeonSession(data, saved, time(), true)
    -- A reset detected by a pull must not put a long entrance speech in battle.
    current.saved.entrySelected = true
    ns.db.dungeonSessions[key] = current.saved
end
local function Tick()
    Enter()
    if not current then return end
    current.saved.t = time()
    current.saved.subzone = GetSubZoneText and GetSubZoneText() or ""
    if not Enabled() then Cancel(false); return end
    if Dead() or cinematic then Cancel(false); return end
    local ctx = Context()
    current:Observe(ctx)
    local combat = ctx.combat
    if not combat then current:Calm(); current.pullStarted = nil end
    if combat then calmAt = nil else calmAt = calmAt or GetTime() end
    if current.muted then return end
    for sceneKey, item in pairs(flight) do
        local found = ns.state.active == item
        for _, list in ipairs({ns.state.queue, ns.state.pending}) do
            for _, queued in ipairs(list) do if queued == item then found = true end end
        end
        if found and (not item.valid or item.valid()) then return end
        if found then ns.DropItem(item.key) end
        -- An explicit interruption/skip must not restart the same speech.
        current:Finish(sceneKey, ctx, true)
        flight[sceneKey] = nil
    end
    if GetTime() < busyUntil and (not calmAt or GetTime() - calmAt < 10) then return end
    -- Automatic narration never cuts another line, including with queue off.
    if ns.state.active or #ns.state.queue > 0 or #ns.state.pending > 0 then return end
    for _, scene in ipairs(current:Scenes(ctx)) do
        if scene.combat or not combat then
        local owner, generation = current, epoch
        local function Valid()
            return current == owner and epoch == generation and Enabled() and not Dead() and not cinematic
                and owner:IsValid(scene.key, Context(owner.data))
        end
        local track = scene.track
        local npc
        for _, boss in ipairs(current.data.bosses) do
            if boss.id == scene.boss then
                npc = {id = boss.npcs[1], ids = boss.npcs, name = boss.name}
                break
            end
        end
        local item = {
            key = "dungeon:" .. key .. ":" .. owner.saved.serial .. ":" .. scene.key,
            questID = 0, kind = "dungeon", title = current.data.name, npc = npc,
            file = "Interface\\AddOns\\CatQuest\\Sounds\\dungeon\\" .. track.hash .. ".ogg",
            duration = track.duration, cues = track.cues, cueIndex = 0,
            text = track.text, valid = Valid,
            bookHash = track.hash,
            onFinish = function()
                owner:Finish(scene.key, Context(owner.data))
                flight[scene.key] = nil
            end,
        }
        flight[scene.key] = item
        local ok = ns.PlayItem(item, false)
        if not ok then flight[scene.key] = nil end
        return
        end
    end
end
function ns.DungeonCommand(argument)
    if argument == "on" or argument == "off" then
        ns.db.dungeonMaster = argument == "on"
        if current then current.muted = false end
        if not ns.db.dungeonMaster then Cancel(false) end
        ns.Print("Мастер подземелий: " .. (ns.db.dungeonMaster and "включён" or "выключен"))
        return
    end
    if argument == "list" or argument == "history" then
        local ids = {}
        for map in pairs(ns.DungeonData) do ids[#ids + 1] = map end
        table.sort(ids)
        for _, map in ipairs(ids) do
            ns.Print(tostring(map) .. ": " .. ns.DungeonData[map].name)
            if argument == "history" then
                for savedKey, saved in pairs(ns.db.dungeonSessions or {}) do
                    if savedKey:match("^(%d+):") == tostring(map) then
                        ns.Print(savedKey .. ": заходов " .. saved.runs .. ", с победами " .. (saved.completedRuns or 0))
                    end
                end
            end
        end
        return
    end
    Enter()
    if not current then ns.Print("Мастер подземелий: /cq dm list — доступные инстансы."); return end
    if argument == "reset" then
        Cancel(false)
        current = ns.NewDungeonSession(current.data, current.saved, time(), true)
        ns.db.dungeonSessions[key] = current.saved
    end
    ns.Print(current.data.name .. ": заход " .. current.saved.runs)
    for _, b in ipairs(current.data.bosses) do
        ns.Print(b.name .. ": " .. (current.saved.killed[b.id] and "победа"
            or current.active[b.id] and "бой" or "не пройден"))
    end
end
local function GroupFlags(flags)
    return flags and bit.band(flags, 7) ~= 0
end
local function Combat(...)
    if not current or not Enabled() then return end
    -- Native 3.3.5: timestamp,event,srcGUID,srcName,srcFlags,dstGUID,dstName,dstFlags.
    local _, event, src, _, sf, dst, _, df = ...
    if event == "UNIT_DIED" then
        local b = current:Kill(ns.DungeonCreatureID(dst), time())
        if b then busyUntil = GetTime() + 5 end
        return
    end
    -- Damage and misses establish engagement; proximity/auras/deaths do not.
    if not (event and (event:match("_DAMAGE$") or event:match("_MISSED$"))) then return end
    local npc
    if GroupFlags(sf) then npc = ns.DungeonCreatureID(dst) end
    if not npc and GroupFlags(df) then npc = ns.DungeonCreatureID(src) end
    if not npc or not current:Boss(npc) then return end
    local first = not current.active[current:Boss(npc).id]
    local b, reset = current:Pull(npc, time())
    if reset then ResetCopy(); b = current:Pull(npc, time()) end
    if first then current.muted = false end
    if b and not current.pullStarted then
        current.pullStarted = true
        busyUntil = math.max(busyUntil, GetTime() + 3)
    end
end
local frame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
    "COMBAT_LOG_EVENT_UNFILTERED", "BAG_UPDATE", "QUEST_LOG_UPDATE", "CINEMATIC_START", "CINEMATIC_STOP",
    "PLAYER_DEAD", "PLAYER_LOGOUT", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_SAY" }) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then Combat(...)
    elseif event == "PLAYER_DEAD" then Cancel(false)
    elseif event == "CINEMATIC_START" then cinematic = true; Cancel(false)
    elseif event == "CINEMATIC_STOP" then cinematic = false
    elseif event == "BAG_UPDATE" or event == "QUEST_LOG_UPDATE" then
        if current then current:Observe(Context()) end
    elseif event == "PLAYER_LOGOUT" then if current then current.saved.t = time() end
    elseif event == "CHAT_MSG_MONSTER_YELL" or event == "CHAT_MSG_MONSTER_SAY" then
        busyUntil = GetTime() + 5
        local item = ns.state.active
        if item and item.kind == "dungeon" then ns.DropItem(item.key) end
    else Enter() end
end)
local elapsed = 0
frame:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 1 then return end
    elapsed = 0
    local ok, err = pcall(Tick)
    if not ok and ns.ReportError then ns.ReportError("Dungeon: " .. tostring(err)) end
end)
