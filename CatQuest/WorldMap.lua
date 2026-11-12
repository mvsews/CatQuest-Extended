local addonName = ...
local ns = CatQuest335 or {}
CatQuest335 = ns
local L = ns.L

-- World map buttons (3.3.5 map with the quest list on the right):
--   "Voice" plays the quest selected in the map's quest list;
--   "Zone story" opens the story of the zone shown on the map.
if not WorldMapFrame then
    return
end

local function ZoneShownOnMap()
    local mapFile = GetMapInfo and GetMapInfo()
    local name
    if GetMapZones and GetCurrentMapContinent and GetCurrentMapZone then
        local zoneIndex = GetCurrentMapZone()
        if zoneIndex and zoneIndex > 0 then
            name = select(zoneIndex, GetMapZones(GetCurrentMapContinent()))
        end
    end
    return ns.StoryZoneForMap and ns.StoryZoneForMap(mapFile), name
end

-- The selected quest of the map's list: { questId, questLogIndex } in 3.3.5.
local function SelectedMapQuest()
    local selected = WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.selectedQuest
    if selected and selected.questId and selected.questId > 0 then
        return selected.questId, selected.questLogIndex
    end
end

-- Read title and description of a quest log entry without changing the
-- player's selection in the quest log.
local function QuestLogText(index)
    if not index or not SelectQuestLogEntry or not GetQuestLogQuestText then
        return nil, nil
    end
    local previous = GetQuestLogSelection and GetQuestLogSelection() or 0
    SelectQuestLogEntry(index)
    local description = GetQuestLogQuestText()
    local title = GetQuestLogTitle and GetQuestLogTitle(index)
    SelectQuestLogEntry(previous)
    if description == "" then
        description = nil
    end
    return title, description
end

local voice = CreateFrame("Button", "CatQuest335MapVoiceButton", WorldMapFrame, "UIPanelButtonTemplate")
voice:SetWidth(110)
voice:SetHeight(22)
voice:SetText(L.BTN_VOICE)
if WorldMapTrackQuestText then
    voice:SetPoint("LEFT", WorldMapTrackQuestText, "RIGHT", 16, 0)
else
    voice:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMLEFT", 180, 8)
end
voice:SetScript("OnClick", function()
    local questID, logIndex = SelectedMapQuest()
    if not questID then
        ns.Print(L.MAP_NO_QUEST)
        return
    end
    local title, text = QuestLogText(logIndex)
    -- false: no subtitles rather than text of an unrelated quest frame.
    ns.PlayQuest(questID, "quest", true, text or false, title)
end)

local story = CreateFrame("Button", "CatQuest335MapStoryButton", WorldMapFrame, "UIPanelButtonTemplate")
story:SetWidth(90)
story:SetHeight(22)
story:SetText(L.MAP_STORY)
if WorldMapZoomOutButton then
    story:SetPoint("LEFT", WorldMapZoomOutButton, "RIGHT", 8, 0)
else
    story:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -60, -36)
end
story:SetScript("OnClick", function()
    local zone, name = ZoneShownOnMap()
    if zone then
        ns.ShowStory(zone, name)
    else
        ns.Print(L.STORY_ZONE_NONE)
    end
end)

-- Buttons follow the map: the quest button only with the quest list, the
-- story button only for zones that have chapters.
function ns.UpdateMapButtons()
    local listShown = not WorldMapQuestScrollFrame or WorldMapQuestScrollFrame:IsVisible()
    if listShown then voice:Show() else voice:Hide() end
    if SelectedMapQuest() then voice:Enable() else voice:Disable() end
    local zone = ZoneShownOnMap()
    if WorldMapZoomOutButton and not WorldMapZoomOutButton:IsVisible() then
        story:Hide()
    else
        story:Show()
    end
    if zone then story:Enable() else story:Disable() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("WORLD_MAP_UPDATE")
events:SetScript("OnEvent", function()
    if WorldMapFrame:IsShown() then
        ns.UpdateMapButtons()
    end
end)
WorldMapFrame:HookScript("OnShow", function() ns.UpdateMapButtons() end)
if hooksecurefunc and WorldMapFrame_SelectQuestFrame then
    hooksecurefunc("WorldMapFrame_SelectQuestFrame", function() ns.UpdateMapButtons() end)
end
