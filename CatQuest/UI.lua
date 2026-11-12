local addonName = ...
local ns = CatQuest335 or {}
CatQuest335 = ns
local L = ns.L

local head = CreateFrame("Frame", "CatQuest335TalkingHead", UIParent)
head:SetWidth(520)
head:SetHeight(136)
head:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
-- Above the world map: quests can be voiced from the map.
head:SetFrameStrata("FULLSCREEN_DIALOG")
head:SetMovable(true)
head:EnableMouse(true)
head:RegisterForDrag("LeftButton")
head:SetClampedToScreen(true)
head:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
head:SetBackdropColor(0.03, 0.03, 0.03, 0.94)
head:Hide()

head:SetScript("OnDragStart", function(frame)
    if ns.db.headLocked then
        return
    end
    frame:StartMoving()
end)

local function SaveWindowPosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not point or not relativePoint or not x or not y then
        return
    end
    ns.db.headPosition = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

head:SetScript("OnDragStop", function(frame)
    frame:StopMovingOrSizing()
    SaveWindowPosition(frame)
end)

head.portrait = head:CreateTexture(nil, "ARTWORK")
-- 32 px: the quest "!" icon read too heavy at 58 px.
head.portrait:SetWidth(32)
head.portrait:SetHeight(32)
head.portrait:SetPoint("TOPLEFT", head, "TOPLEFT", 18, -20)
head.portrait:SetTexCoord(0.12, 0.88, 0.12, 0.88)
head.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

head.title = head:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
head.title:SetPoint("TOPLEFT", head.portrait, "TOPRIGHT", 12, -2)
head.title:SetWidth(418) -- room for the bug button (Feedback.lua)
head.title:SetHeight(24)
head.title:SetJustifyH("LEFT")
head.title:SetTextColor(1, 0.82, 0)

head.subtitle = head:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
head.subtitle:SetPoint("TOPLEFT", head.title, "BOTTOMLEFT", 0, -4)
head.subtitle:SetWidth(434)
head.subtitle:SetHeight(52)
head.subtitle:SetJustifyH("LEFT")
head.subtitle:SetJustifyV("TOP")
head.subtitle:SetWordWrap(true)

head.queueText = head:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
head.queueText:SetPoint("TOPLEFT", head.subtitle, "BOTTOMLEFT", 0, -2)
head.queueText:SetWidth(434)
head.queueText:SetHeight(16)
head.queueText:SetJustifyH("LEFT")
head.queueText:SetTextColor(0.95, 0.78, 0.25)

head.bar = CreateFrame("StatusBar", nil, head)
head.bar:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 12, 13)
head.bar:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -116, 13)
head.bar:SetHeight(8)
head.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
head.bar:SetStatusBarColor(0.25, 0.68, 0.95, 0.9)
head.bar:SetMinMaxValues(0, 1)
head.bar:SetValue(0)

head.timeText = head:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
head.timeText:SetPoint("BOTTOMRIGHT", head.bar, "TOPRIGHT", 0, 2)
head.timeText:SetWidth(70)
head.timeText:SetHeight(16)
head.timeText:SetJustifyH("RIGHT")
head.timeText:SetTextColor(0.7, 0.7, 0.7)

head.stopButton = CreateFrame("Button", nil, head, "UIPanelButtonTemplate")
head.stopButton:SetWidth(44)
head.stopButton:SetHeight(22)
head.stopButton:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -64, 7)
head.stopButton:SetText(L.BTN_STOP)
head.stopButton:SetScript("OnClick", function()
    ns.Stop()
end)

head.nextButton = CreateFrame("Button", nil, head, "UIPanelButtonTemplate")
head.nextButton:SetWidth(52)
head.nextButton:SetHeight(22)
head.nextButton:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -8, 7)
head.nextButton:SetText(L.BTN_NEXT)
head.nextButton:SetScript("OnClick", function()
    ns.Skip()
end)

-- The quest giver's face while the quest dialog with that NPC is open
-- (the "npc" unit, as the game's own quest frame uses). Otherwise a quest
-- icon: the current target is unrelated to the quest being read.
local function SetPortrait(item)
    head.portrait:SetTexCoord(0, 1, 0, 1)
    if item and item.dialog
        and ((item.kind == "gossip" and ns.state.dialogGossip)
            or (item.kind ~= "gossip" and ns.state.dialogQuest == item.questID))
        and UnitExists and UnitExists("npc") then
        local ok = pcall(SetPortraitTexture, head.portrait, "npc")
        if ok then
            return
        end
    end
    if item and item.kind == "npcLore" and UnitExists and UnitExists("target") then
        local ok = pcall(SetPortraitTexture, head.portrait, "target")
        if ok then
            return
        end
    end
    if item and item.kind == "book" then
        head.portrait:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    elseif item and item.kind == "place" then
        head.portrait:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    elseif item and item.kind == "turnin" then
        head.portrait:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
    elseif item and item.kind == "gossip" then
        head.portrait:SetTexture("Interface\\GossipFrame\\GossipGossipIcon")
    else
        head.portrait:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    end
end

local function WaitingLabel(kind)
    if kind == "turnin" then
        return L.KIND_TURNIN
    end
    if kind == "book" then
        return L.KIND_BOOK
    end
    if kind == "place" then
        return L.KIND_PLACE
    end
    if kind == "gossip" then
        return L.KIND_GOSSIP
    end
    if kind == "npcLore" then
        return L.KIND_NPC_LORE
    end
    return L.KIND_QUEST
end

local function QuestInfoLine(item, state)
    local identity
    if item.kind == "book" or item.kind == "place" or item.kind == "gossip" or item.kind == "npcLore" then
        identity = item.title or (item.kind == "place" and L.KIND_PLACE or L.BOOK_UNTITLED)
    else
        identity = "ID " .. tostring(item.questID)
    end
    return identity .. "  •  " .. WaitingLabel(item.kind) .. "  •  " .. state
end

local function Title(item)
    return item.title or string.format(L.QUEST_N, tostring(item.questID))
end

function ns.ShowHead(item)
    head.item = item
    head.title:SetText(Title(item))
    head.subtitle:SetText("")
    head.queueText:SetText("")
    head.bar:Show()
    head.timeText:Show()
    head.bar:SetMinMaxValues(0, math.max(item.duration or 0, 1))
    head.bar:SetValue(0)
    head.bar:SetStatusBarColor(0.25, 0.68, 0.95, 0.9)
    head.timeText:SetText("0:00")
    SetPortrait(item)
    if ns.db.head ~= false then
        head:Show()
    end
    ns.ShowQueueStatus(#ns.state.queue)
end

-- The window opens at once with the quest text; audio arrives later.
function ns.ShowWaiting(item)
    head.item = item
    head.title:SetText(Title(item))
    head.bar:Show()
    head.timeText:Show()
    if ns.db.showSubtitle and item.pages and item.pages[1] then
        head.subtitle:SetText(item.pages[1])
    else
        head.subtitle:SetText(L.LOADING_VOICE)
    end
    head.bar:SetMinMaxValues(0, math.max(item.timeout or 15, 1))
    head.bar:SetValue(0)
    head.bar:SetStatusBarColor(0.95, 0.78, 0.25, 0.9)
    head.timeText:SetText(L.LOADING)
    SetPortrait(item)
    if ns.db.head ~= false then
        head:Show()
    end
    head.queueText:SetText(QuestInfoLine(item, L.LOADING_SOUND))
end

function ns.UpdateWaiting(item, elapsed)
    if not head:IsShown() then
        return
    end
    head.bar:SetValue(math.min(elapsed, item.timeout or elapsed))
    head.timeText:SetText(string.format(L.SECONDS, math.floor(elapsed)))
end

-- Lasthavens, voiced on demand: the track plays by itself once the server has
-- it, and the addon does not learn when. The window shows the quest from the
-- request on, without a running bar.
function ns.ShowDemand(item)
    head.item = item
    head.title:SetText(Title(item))
    if ns.db.showSubtitle and item.pages and item.pages[1] then
        head.subtitle:SetText(item.pages[1])
    else
        head.subtitle:SetText(L.DEMAND_INFO)
    end
    -- There is no playback clock for a track handed over by poll. A full
    -- bar would look frozen while the server is still preparing the audio.
    head.bar:Hide()
    head.timeText:Hide()
    SetPortrait(item)
    if ns.db.head ~= false then
        head:Show()
    end
    head.queueText:SetText(QuestInfoLine(item, L.DEMAND_INFO))
end

-- Final state of a remote item that never became playable.
function ns.ShowNotice(item, text)
    head.item = item
    head.title:SetText(Title(item))
    head.bar:Show()
    head.timeText:Show()
    head.subtitle:SetText(text or "")
    head.bar:SetMinMaxValues(0, 1)
    head.bar:SetValue(1)
    head.bar:SetStatusBarColor(0.85, 0.3, 0.25, 0.9)
    head.timeText:SetText(L.NO_SOUND)
    head.queueText:SetText(QuestInfoLine(item, L.REPLAY_LATER))
    if ns.db.head ~= false then
        head:Show()
    end
end

function ns.ShowQueueStatus(count)
    if not head.queueText then
        return
    end
    count = tonumber(count) or 0
    if count > 0 then
        head.queueText:SetText(string.format(L.IN_QUEUE, count))
    else
        head.queueText:SetText("")
    end
end

-- Settings from the panel: compact window (title and progress only) and scale.
local FULL_HEIGHT, COMPACT_HEIGHT = 136, 76
local DEFAULT_HEAD_POINT = "CENTER"
local DEFAULT_HEAD_X, DEFAULT_HEAD_Y = 0, -180

function ns.ApplyWindowPosition()
    local saved = ns.db.headPosition
    head:ClearAllPoints()
    if type(saved) == "table"
        and type(saved.point) == "string"
        and type(saved.relativePoint) == "string"
        and tonumber(saved.x)
        and tonumber(saved.y) then
        head:SetPoint(saved.point, UIParent, saved.relativePoint, tonumber(saved.x), tonumber(saved.y))
    else
        head:SetPoint(DEFAULT_HEAD_POINT, UIParent, DEFAULT_HEAD_POINT, DEFAULT_HEAD_X, DEFAULT_HEAD_Y)
    end
end

function ns.ApplyWindowSettings()
    local scale = tonumber(ns.db.scale) or 1
    scale = math.max(0.6, math.min(1.5, scale))
    ns.db.scale = tonumber(string.format("%.2f", scale))
    head:SetScale(ns.db.scale)
    head:SetHeight(ns.db.compact and COMPACT_HEIGHT or FULL_HEIGHT)
    if ns.db.compact then
        head.subtitle:Hide()
        head.queueText:Hide()
    else
        head.subtitle:Show()
        head.queueText:Show()
    end
end

function ns.ResetWindowPosition()
    ns.db.headPosition = nil
    ns.ApplyWindowPosition()
    if head.SetUserPlaced then
        head:SetUserPlaced(false)
    end
end

function ns.SetSubtitle(text)
    if ns.db.showSubtitle and not ns.db.compact then
        head.subtitle:SetText(text or "")
    else
        head.subtitle:SetText("")
    end
end

function ns.UpdateHead(item, elapsed)
    if not head:IsShown() then
        return
    end
    head.bar:SetValue(math.min(elapsed, item.duration or elapsed))
    head.timeText:SetText(string.format("%d:%02d", math.floor(elapsed / 60), math.floor(elapsed % 60)))
end

function ns.HideHead()
    head:Hide()
    ns.ShowQueueStatus(0)
end

function ns.InstallQuestLogButton()
    if not QuestLogFrame or head.questButton then
        return
    end

    head.questButton = CreateFrame("Button", "CatQuest335QuestLogButton", QuestLogFrame, "UIPanelButtonTemplate")
    head.questButton:SetWidth(84)
    head.questButton:SetHeight(23)
    head.questButton:SetPoint("BOTTOMRIGHT", QuestLogFrame, "BOTTOMRIGHT", -88, 12)
    head.questButton:SetText(L.BTN_VOICE)
    head.questButton:SetScript("OnClick", function()
        ns.PlaySelectedQuest()
    end)
end

-- "Read" button in the quest window, as in the original CatQuest (setting
-- readButton): reads the quest on screen even with automatic reading off.
function ns.InstallQuestFrameButton()
    if not QuestFrame or head.questFrameButton then
        return
    end
    local button = CreateFrame("Button", "CatQuest335QuestFrameButton", QuestFrame, "UIPanelButtonTemplate")
    button:SetWidth(80)
    button:SetHeight(20)
    button:SetPoint("TOPRIGHT", QuestFrame, "TOPRIGHT", -40, -46)
    button:SetText(L.BTN_READ)
    button:SetScript("OnClick", function()
        ns.ReadOpenQuest()
    end)
    head.questFrameButton = button
    ns.UpdateQuestFrameButton()
end

-- GossipFrame is the NPC greeting window (the one with a single "Goodbye"
-- button), separate from QuestFrame. It has no quest ID, so the button sends
-- its visible greeting through the generic online gossip voice route.
local function PositionGossipButton()
    local button = head.gossipButton
    if not button or not GossipFrame then
        return
    end

    -- Blizzard creates/repositions the goodbye button while GOSSIP_SHOW is
    -- being handled. Re-anchor ours every time so it is not left at the
    -- fallback position from addon load.
    button:ClearAllPoints()
    -- In the 3.3.5 GossipFrame.xml the stock button is named
    -- GossipFrameGreetingGoodbyeButton. Keep the older name as a fallback
    -- for custom clients that expose it differently.
    local goodbye = _G.GossipFrameGreetingGoodbyeButton or _G.GossipFrameGoodbyeButton
    if goodbye then
        button:SetPoint("RIGHT", goodbye, "LEFT", -4, 0)
    else
        -- The stock anchor is BOTTOMRIGHT (-39, 73), width 78. Put our
        -- 88-pixel button immediately to its left even if the custom client
        -- does not expose the stock button global.
        button:SetPoint("BOTTOMRIGHT", GossipFrame, "BOTTOMRIGHT", -121, 73)
    end
    button:SetFrameStrata(GossipFrame:GetFrameStrata())
    button:SetFrameLevel((GossipFrame:GetFrameLevel() or 0) + 10)
end

function ns.InstallGossipButton()
    if not GossipFrame then
        return
    end
    if head.gossipButton then
        PositionGossipButton()
        ns.UpdateGossipButton()
        -- Some 3.3.5 clients finish building the greeting panel one frame
        -- after GOSSIP_SHOW. Refresh once more after that layout pass so the
        -- button is visible on the first opening as well.
        ns.After(0, function()
            PositionGossipButton()
            ns.UpdateGossipButton()
        end)
        return
    end
    local button = CreateFrame("Button", "CatQuest335GossipButton", GossipFrame, "UIPanelButtonTemplate")
    button:SetWidth(88)
    button:SetHeight(20)
    button:SetText(L.BTN_LISTEN)
    button:SetScript("OnClick", function()
        ns.ReadOpenGossip()
    end)
    head.gossipButton = button
    PositionGossipButton()
    if GossipFrame.HookScript and not head.gossipFrameHooked then
        head.gossipFrameHooked = true
        GossipFrame:HookScript("OnShow", function()
            -- Let the stock gossip frame finish laying out its bottom button.
            ns.After(0, function()
                PositionGossipButton()
                ns.UpdateGossipButton()
            end)
        end)
    end
    ns.UpdateGossipButton()
    ns.After(0, function()
        PositionGossipButton()
        ns.UpdateGossipButton()
    end)
end

function ns.UpdateGossipButton()
    if head.gossipButton then
        PositionGossipButton()
        -- Gossip has its own explicit "Listen" action. Do not hide it when
        -- the user disables the quest/book Read button: that setting does not
        -- turn off NPC dialogue controls.
        if GossipFrame and GossipFrame:IsShown() then
            head.gossipButton:Show()
        else
            head.gossipButton:Hide()
        end
    end
end

function ns.UpdateQuestFrameButton()
    local button = head.questFrameButton
    if not button then
        return
    end
    if ns.db.readButton ~= false then
        button:Show()
    else
        button:Hide()
    end
end

ns.ApplyWindowPosition()
ns.ApplyWindowSettings()
ns.InstallQuestFrameButton()
ns.InstallGossipButton()

-- Interface language switched in game: buttons made at load follow it.
function ns.RefreshTexts()
    head.stopButton:SetText(L.BTN_STOP)
    head.nextButton:SetText(L.BTN_NEXT)
    if head.questButton then
        head.questButton:SetText(L.BTN_VOICE)
    end
    if head.questFrameButton then
        head.questFrameButton:SetText(L.BTN_READ)
    end
    if head.gossipButton then
        head.gossipButton:SetText(L.BTN_LISTEN)
    end
    ns.UpdateGossipButton()
end
