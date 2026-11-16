local addonName = ...
local ns = CatQuest335 or {}
CatQuest335 = ns
local L = ns.L

-- Zone story: chapters of related quests per zone, progress from the server's
-- completed-quest list, and "Listen" that replays the chapter's voiced quests.
-- Data: StoryData.lua (tools/build_story.py). 3.3.5 APIs only: completed quests
-- come from QueryQuestsCompleted() / QUEST_QUERY_COMPLETE, the zone from GetMapInfo().

local data = CatQuest335Story or { maps = {}, zones = {}, races = {}, classes = {}, voiced = {} }
local guide = CatQuest335QuestGuide or { zones = {} }
local titles = CatQuest335StoryTitles or {}
local fallbackTitles = CatQuest335StoryTitlesFallback or {}

ns.completedQuests = ns.completedQuests or {}
local completedLoaded = false
local currentZone = nil

local RACE_BITS = {
    Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16, Tauren = 32,
    Gnome = 64, Troll = 128, BloodElf = 512, Draenei = 1024,
}
local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, DEATHKNIGHT = 32,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

local player
local function Player()
    if player then
        return player
    end
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    player = {
        side = UnitFactionGroup("player") == "Horde" and "H" or "A",
        race = RACE_BITS[race or ""],
        class = CLASS_BITS[class or ""],
    }
    return player
end

local function Has(mask, value)
    return value and mask % (value * 2) >= value
end

function ns.StoryTitle(questID)
    return titles[questID] or fallbackTitles[questID] or string.format(L.QUEST_N, tostring(questID))
end

function ns.StoryCompleted(questID)
    return ns.completedQuests[questID] and true or false
end

local function Available(questID)
    local me = Player()
    local races = data.races[questID]
    if races and me.race and not Has(races, me.race) then
        return false
    end
    local classes = data.classes[questID]
    if classes and me.class and not Has(classes, me.class) then
        return false
    end
    return true
end

local function InLog(questID)
    if not GetNumQuestLogEntries then
        return false
    end
    for index = 1, GetNumQuestLogEntries() do
        local count = select("#", GetQuestLogTitle(index))
        local values = { GetQuestLogTitle(index) }
        for i = 8, count do
            if values[i] == questID then
                return true
            end
        end
    end
    return false
end

-- Chapters of a zone for this character, in story order.
function ns.StoryChapters(zone)
    local out = {}
    local me = Player()
    for _, chapter in ipairs(data.zones[zone] or {}) do
        if not chapter.s or chapter.s == me.side then
            local quests, done = {}, 0
            for _, questID in ipairs(chapter.q) do
                if Available(questID) then
                    quests[#quests + 1] = questID
                    if ns.StoryCompleted(questID) then
                        done = done + 1
                    end
                end
            end
            if #quests >= 2 then
                out[#out + 1] = { chapter = chapter, quests = quests, done = done, total = #quests }
            end
        end
    end
    return out
end

function ns.StoryChapterName(entry)
    if entry.chapter.n and ns.ClientLocale() == "ruRU" then
        return entry.chapter.n
    end
    return ns.StoryTitle(entry.quests[1])
end

local function StoryDistinctiveness(zone, entry)
    local info = guide.zones and guide.zones[zone]
    if not info or not info.score or not info.quests then
        return nil
    end
    local selected = {}
    for _, questID in ipairs(info.quests) do
        selected[questID] = true
    end
    for _, questID in ipairs(entry.quests) do
        if selected[questID] then
            return info.score
        end
    end
    return nil
end

-- Next step: the earliest chapter in progress, else the first fresh chapter of
-- the player's level. Returns entry, questID.
function ns.StoryNext(zone)
    local level = UnitLevel("player") or 1
    local fresh
    for _, entry in ipairs(ns.StoryChapters(zone)) do
        if entry.done < entry.total then
            for _, questID in ipairs(entry.quests) do
                if not ns.StoryCompleted(questID) then
                    if entry.done > 0 or InLog(questID) then
                        return entry, questID
                    end
                    if not fresh and (entry.chapter.l or 1) <= level + 2 then
                        fresh = { entry, questID }
                    end
                    break
                end
            end
        end
    end
    if fresh then
        return fresh[1], fresh[2]
    end
end

function ns.StoryCurrentZone()
    if GetMapInfo and SetMapToCurrentZone and not (WorldMapFrame and WorldMapFrame:IsShown()) then
        SetMapToCurrentZone()
        currentZone = data.maps[GetMapInfo() or ""]
    end
    return currentZone
end

-- Replay the voiced, completed quests of a chapter in story order.
function ns.StoryListen(entry)
    local queued = 0
    for _, questID in ipairs(entry.quests) do
        if ns.StoryCompleted(questID) and ns.CanPlayQuest(questID, "quest") then
            -- Use the chapter quest's giver, rather than an unrelated NPC
            -- whose dialogue happens to be open while replay is requested.
            local npcID = CatQuest335QuestGiver and CatQuest335QuestGiver[questID]
            -- A chapter is one ordered playlist, even when individual new
            -- dialogues are configured to interrupt the current narration.
            if ns.PlayQuest(questID, "quest", true, false, ns.StoryTitle(questID), npcID, true) then
                queued = queued + 1
            end
        end
    end
    if queued == 0 then
        ns.Print(L.STORY_NOTHING)
    end
    return queued
end

function ns.StoryCanListen(entry)
    for _, questID in ipairs(entry.quests) do
        if ns.StoryCompleted(questID) and ns.CanPlayQuest(questID, "quest") then
            return true
        end
    end
    return false
end

-- Window ---------------------------------------------------------------------

local ROWS = 8
local frame = CreateFrame("Frame", "CatQuest335StoryFrame", UIParent)
frame:SetWidth(480)
frame:SetHeight(392)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
-- Above the full-screen world map, which can open this window.
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
})
frame:SetBackdropColor(0.04, 0.04, 0.04, 0.96)
frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
frame:Hide()
if UISpecialFrames then
    table.insert(UISpecialFrames, "CatQuest335StoryFrame") -- Escape closes it
end

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

frame.heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -20)
frame.heading:SetWidth(400)
frame.heading:SetJustifyH("LEFT")

frame.progress = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
frame.progress:SetPoint("TOPLEFT", frame.heading, "BOTTOMLEFT", 0, -6)
frame.progress:SetWidth(440)
frame.progress:SetJustifyH("LEFT")

frame.next = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
frame.next:SetPoint("TOPLEFT", frame.progress, "BOTTOMLEFT", 0, -6)
frame.next:SetWidth(440)
frame.next:SetJustifyH("LEFT")
frame.next:SetTextColor(1, 0.82, 0)

frame.rows = {}
for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, frame)
    row:SetWidth(440)
    row:SetHeight(30)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -82 - (i - 1) * 32)
    row.count = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.count:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.count:SetWidth(38)
    row.count:SetJustifyH("LEFT")
    row.score = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.score:SetPoint("LEFT", row, "LEFT", 42, 0)
    row.score:SetWidth(48)
    row.score:SetJustifyH("LEFT")
    row.score:SetTextColor(1, 0.82, 0)
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row, "LEFT", 96, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -92, 0)
    row.name:SetHeight(26)
    row.name:SetJustifyH("LEFT")
    row.listen = CreateFrame("Button", "CatQuest335StoryListen" .. i, row, "UIPanelButtonTemplate")
    row.listen:SetWidth(84)
    row.listen:SetHeight(22)
    row.listen:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.listen:SetText(L.STORY_LISTEN)
    row.listen:SetScript("OnClick", function(self)
        if self.entry then
            ns.StoryListen(self.entry)
        end
    end)
    frame.rows[i] = row
end

frame.page = 1
frame.pageText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
frame.pageText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 22)

local function PageButton(label, delta, anchor, x)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetWidth(32)
    button:SetHeight(22)
    button:SetPoint(anchor, frame, "BOTTOM", x, 16)
    button:SetText(label)
    button:SetScript("OnClick", function()
        frame.page = frame.page + delta
        ns.StoryRefresh()
    end)
    return button
end
frame.prev = PageButton("<", -1, "RIGHT", -40)
frame.nextPage = PageButton(">", 1, "LEFT", 40)

function ns.StoryRefresh()
    if not frame:IsShown() then
        return
    end
    -- A zone picked on the world map wins over the zone the player stands in.
    local zone, zoneName = frame.zone, frame.zoneName
    if not zone then
        zone = ns.StoryCurrentZone()
        zoneName = GetRealZoneText and GetRealZoneText() or ""
    end
    frame.heading:SetText(L.STORY_TITLE .. ": " .. tostring(zoneName or ""))
    local chapters = zone and ns.StoryChapters(zone) or {}
    if not completedLoaded then
        frame.progress:SetText(L.STORY_LOADING)
    elseif #chapters == 0 then
        frame.progress:SetText(L.STORY_ZONE_NONE)
    else
        local finished = 0
        for _, entry in ipairs(chapters) do
            if entry.done == entry.total then
                finished = finished + 1
            end
        end
        frame.progress:SetText(string.format(L.STORY_PROGRESS, finished, #chapters))
    end
    local nextQuest
    if zone then
        -- Not "zone and ns.StoryNext(zone)": that keeps only the first return value.
        local _
        _, nextQuest = ns.StoryNext(zone)
    end
    if nextQuest then
        frame.next:SetText(string.format(L.STORY_NEXT, ns.StoryTitle(nextQuest)))
    elseif #chapters > 0 then
        frame.next:SetText(L.STORY_NEXT_NONE)
    else
        frame.next:SetText("")
    end

    local pages = math.max(1, math.ceil(#chapters / ROWS))
    frame.page = math.max(1, math.min(frame.page, pages))
    frame.pageText:SetText(string.format("%d / %d", frame.page, pages))
    if frame.page > 1 then frame.prev:Enable() else frame.prev:Disable() end
    if frame.page < pages then frame.nextPage:Enable() else frame.nextPage:Disable() end

    for i = 1, ROWS do
        local row = frame.rows[i]
        local entry = chapters[(frame.page - 1) * ROWS + i]
        if entry then
            local started = entry.done > 0 or InLog(entry.quests[1])
            local score = StoryDistinctiveness(zone, entry)
            local progress = entry.done .. "/" .. entry.total
            row.count:SetText(progress)
            if score then
                row.score:SetText(tostring(score) .. "/100")
            else
                row.score:SetText("")
            end
            if entry.done == entry.total then
                row.count:SetTextColor(0.3, 0.9, 0.3)
            else
                row.count:SetTextColor(1, 0.82, 0)
            end
            if started then
                row.name:SetText(ns.StoryChapterName(entry))
            elseif ns.db.storyQuestTitles then
                row.name:SetText(ns.StoryTitle(entry.quests[1]) .. "  " .. string.format(L.STORY_LEVEL, entry.chapter.l or 1))
            else
                row.name:SetText(L.STORY_HIDDEN .. "  " .. string.format(L.STORY_LEVEL, entry.chapter.l or 1))
            end
            row.listen.entry = entry
            if ns.StoryCanListen(entry) then row.listen:Enable() else row.listen:Disable() end
            row:Show()
        else
            row.listen.entry = nil
            row:Hide()
        end
    end
end

frame:SetScript("OnShow", function()
    frame.page = 1
    ns.StoryRefresh()
end)

frame:SetScript("OnHide", function()
    frame.zone, frame.zoneName = nil, nil
end)

-- Open the story of a given zone (world map button).
function ns.ShowStory(zone, zoneName)
    frame:Hide()
    frame.zone, frame.zoneName = zone, zoneName
    frame:Show()
end

function ns.StoryZoneForMap(mapFile)
    local zone = data.maps[mapFile or ""]
    return zone and data.zones[zone] and zone or nil
end

function ns.ToggleStory()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- Completed quests -----------------------------------------------------------

local function QueryCompleted()
    if QueryQuestsCompleted then
        QueryQuestsCompleted()
    end
end

-- Chapters each quest belongs to, to announce a finished chapter.
local chaptersOf
local function ChaptersOf(questID)
    if not chaptersOf then
        chaptersOf = {}
        for zone, chapters in pairs(data.zones) do
            for _, chapter in ipairs(chapters) do
                for _, q in ipairs(chapter.q) do
                    chaptersOf[q] = chaptersOf[q] or {}
                    table.insert(chaptersOf[q], { zone = zone, chapter = chapter })
                end
            end
        end
    end
    return chaptersOf[questID] or {}
end

function ns.StoryMarkCompleted(questID)
    if not questID or questID <= 0 or ns.completedQuests[questID] then
        return
    end
    ns.completedQuests[questID] = true
    for _, ref in ipairs(ChaptersOf(questID)) do
        for _, entry in ipairs(ns.StoryChapters(ref.zone)) do
            if entry.chapter == ref.chapter and entry.done == entry.total then
                local message = string.format(L.STORY_DONE_TOAST, ns.StoryChapterName(entry))
                ns.Print(message)
                if UIErrorsFrame and UIErrorsFrame.AddMessage then
                    UIErrorsFrame:AddMessage(message, 1, 0.82, 0.1, 1)
                end
            end
        end
    end
    ns.StoryRefresh()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("QUEST_QUERY_COMPLETE")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        player = nil
        ns.After(5, QueryCompleted)
    elseif event == "QUEST_QUERY_COMPLETE" then
        local list = {}
        if GetQuestsCompleted then
            GetQuestsCompleted(list)
        end
        for questID in pairs(list) do
            ns.completedQuests[questID] = true
        end
        completedLoaded = true
        ns.StoryRefresh()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        ns.StoryRefresh()
    end
end)

-- The reward button turns a quest in: mark it at once instead of re-querying.
if hooksecurefunc and GetQuestReward then
    hooksecurefunc("GetQuestReward", function()
        local questID = GetQuestID and GetQuestID()
        ns.StoryMarkCompleted(questID)
    end)
end
