local addonName = ...
local ns = CatQuest335 or {}
CatQuest335 = ns
local L = ns.L

local head = CreateFrame("Frame", "CatQuest335TalkingHead", UIParent)
head:SetWidth(520)
head:SetHeight(136)
head:SetPoint("CENTER", UIParent, "CENTER", 0, -180)

local FRAME_STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
local FRAME_STRATA_INDEX = {}
for i = 1, #FRAME_STRATA do
    FRAME_STRATA_INDEX[FRAME_STRATA[i]] = i
end

local function BagStrata()
    local highest
    local count = tonumber(NUM_CONTAINER_FRAMES) or 13
    for i = 1, count do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame.GetFrameStrata then
            local strata = frame:GetFrameStrata()
            if FRAME_STRATA_INDEX[strata]
                and (not highest or FRAME_STRATA_INDEX[strata] > FRAME_STRATA_INDEX[highest]) then
                highest = strata
            end
        end
    end
    -- Blizzard bags normally use HIGH/DIALOG depending on the client skin.
    return highest or "DIALOG"
end

local function ResolveFrameStrata(choice)
    if choice ~= "below-bags" then
        return FRAME_STRATA_INDEX[choice] and choice or "HIGH"
    end
    local bagIndex = FRAME_STRATA_INDEX[BagStrata()] or FRAME_STRATA_INDEX.DIALOG
    return FRAME_STRATA[math.max(1, bagIndex - 1)]
end

function ns.ApplyWindowStrata()
    head:SetFrameStrata(ResolveFrameStrata(ns.db.headStrata or "below-bags"))
end

-- Default: under bag windows, while remaining above the game world.
ns.ApplyWindowStrata()
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
    if ns.AnnouncePosition then
        ns.AnnouncePosition()
    end
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
head.title:SetWidth(322) -- room for the report button (Feedback.lua)
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
head.stopButton:SetWidth(70)
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

local function RefreshStopButton(item)
    if not head.stopButton then return end
    item = item or head.item
    local channel = item and item.playChannel or ns.db.volumeChannel
    head.stopButton:SetText(channel == "Music" and L.BTN_STOP or L.BTN_CLEAR)
end

local function IsNarration(item)
    return item and (item.kind == "npcLore" or item.kind == "dungeon")
end

local function NarrationUnit(item)
    local npc = item and item.npc
    if not npc or not ns.CreatureIDFromUnit then return end
    local function Matches(unit)
        if not UnitExists or not UnitExists(unit) then return false end
        if npc.guid then return UnitGUID and UnitGUID(unit) == npc.guid end
        local id = ns.CreatureIDFromUnit(unit)
        if not id then return false end
        if id == tonumber(npc.id) then return true end
        for _, candidate in ipairs(npc.ids or {}) do
            if id == candidate then return true end
        end
        return false
    end
    for _, unit in ipairs({"target", "focus", "mouseover", "npc"}) do
        if Matches(unit) then return unit end
    end
    local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
    local count = raid > 0 and raid or (GetNumPartyMembers and GetNumPartyMembers() or 0)
    local prefix = raid > 0 and "raid" or "party"
    for i = 1, count do
        local unit = prefix .. i .. "target"
        if Matches(unit) then return unit end
    end
end

-- The quest giver's face while the quest dialog with that NPC is open
-- (the "npc" unit, as the game's own quest frame uses). Otherwise a quest
-- icon: the current target is unrelated to the quest being read.
local function SetPortrait(item)
    head.portrait:SetTexCoord(0, 1, 0, 1)
    if IsNarration(item) then
        local unit = NarrationUnit(item)
        if unit then
            local name = UnitName and UnitName(unit)
            if name and name ~= "" then item.npc.name = name end
            if SetPortraitTexture and pcall(SetPortraitTexture, head.portrait, unit) then return end
        end
        head.portrait:SetTexture("Interface\\Icons\\INV_Misc_Head_Dragon_01")
        return
    end
    if item and item.dialog
        and ((item.kind == "gossip" and ns.state.dialogGossip)
            or (item.kind ~= "gossip" and ns.state.dialogQuest == item.questID))
        and UnitExists and UnitExists("npc") then
        local ok = pcall(SetPortraitTexture, head.portrait, "npc")
        if ok then
            return
        end
    end
    if item and item.kind == "book" then
        head.portrait:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    elseif item and (item.kind == "place" or item.kind == "dungeon") then
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
    if kind == "place" or kind == "dungeon" then
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
    if item.kind == "book" or item.kind == "place" or item.kind == "gossip" or item.kind == "npcLore" or item.kind == "dungeon" then
        identity = item.title or (item.kind == "place" and L.KIND_PLACE or L.BOOK_UNTITLED)
    else
        identity = "ID " .. tostring(item.questID)
    end
    return identity .. "  •  " .. WaitingLabel(item.kind) .. "  •  " .. state
end

local function Title(item)
    if IsNarration(item) and item.npc and item.npc.name then return item.npc.name end
    return item.title or string.format(L.QUEST_N, tostring(item.questID))
end

local function PrepareWindow(item)
    head.item = item
    ns.ApplyWindowSettings()
    SetPortrait(item)
    head.title:SetText(Title(item))
end

function ns.ShowHead(item)
    PrepareWindow(item)
    RefreshStopButton(item)
    ns.SetSubtitle(item.pages and item.pages[1] or item.text or "")
    head.queueText:SetText("")
    head.bar:Show()
    head.timeText:Show()
    head.bar:SetMinMaxValues(0, math.max(item.duration or 0, 1))
    head.bar:SetValue(0)
    head.bar:SetStatusBarColor(0.25, 0.68, 0.95, 0.9)
    head.timeText:SetText("0:00")
    if ns.db.head ~= false or IsNarration(item) then
        head:Show()
    end
    ns.ShowQueueStatus(#ns.state.queue)
end

-- A pending remote line can be skipped and the next queued line can start on
-- the same frame.  Keep the visible title/portrait attached to the item that
-- is actually playing instead of leaving the previous waiting window on
-- screen for one or more frames.
function ns.SyncHead(item)
    if item and head.item ~= item then
        ns.ShowHead(item)
    end
end

-- The window opens at once with the quest text; audio arrives later.
function ns.ShowWaiting(item)
    PrepareWindow(item)
    RefreshStopButton(item)
    head.bar:Show()
    head.timeText:Show()
    if (ns.db.showSubtitle or IsNarration(item)) and item.pages and item.pages[1] then
        head.subtitle:SetText(item.pages[1])
    else
        head.subtitle:SetText(L.LOADING_VOICE)
    end
    head.bar:SetMinMaxValues(0, math.max(item.timeout or 15, 1))
    head.bar:SetValue(0)
    head.bar:SetStatusBarColor(0.95, 0.78, 0.25, 0.9)
    head.timeText:SetText(L.LOADING)
    if ns.db.head ~= false or IsNarration(item) then
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
    PrepareWindow(item)
    RefreshStopButton(item)
    if (ns.db.showSubtitle or IsNarration(item)) and item.pages and item.pages[1] then
        head.subtitle:SetText(item.pages[1])
    else
        head.subtitle:SetText(L.DEMAND_INFO)
    end
    -- There is no playback clock for a track handed over by poll. A full
    -- bar would look frozen while the server is still preparing the audio.
    head.bar:Hide()
    head.timeText:Hide()
    if ns.db.head ~= false or IsNarration(item) then
        head:Show()
    end
    head.queueText:SetText(QuestInfoLine(item, L.DEMAND_INFO))
end

-- Final state of a remote item that never became playable.
function ns.ShowNotice(item, text)
    PrepareWindow(item)
    RefreshStopButton(item)
    head.bar:Show()
    head.timeText:Show()
    head.subtitle:SetText(text or "")
    head.bar:SetMinMaxValues(0, 1)
    head.bar:SetValue(1)
    head.bar:SetStatusBarColor(0.85, 0.3, 0.25, 0.9)
    head.timeText:SetText(L.NO_SOUND)
    head.queueText:SetText(QuestInfoLine(item, L.REPLAY_LATER))
    if ns.db.head ~= false or IsNarration(item) then
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
local VALID_POINTS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

function ns.ApplyWindowPosition()
    local saved = ns.db.headPosition
    head:ClearAllPoints()
    if type(saved) == "table"
        and VALID_POINTS[saved.point]
        and VALID_POINTS[saved.relativePoint]
        and tonumber(saved.x)
        and tonumber(saved.y) then
        head:SetPoint(saved.point, UIParent, saved.relativePoint, tonumber(saved.x), tonumber(saved.y))
    else
        head:SetPoint(DEFAULT_HEAD_POINT, UIParent, DEFAULT_HEAD_POINT, DEFAULT_HEAD_X, DEFAULT_HEAD_Y)
    end
end

function ns.ApplyWindowSettings()
    if ns.ApplyWindowStrata then
        ns.ApplyWindowStrata()
    end
    local scale = tonumber(ns.db.scale) or 1
    scale = math.max(0.6, math.min(1.5, scale))
    ns.db.scale = tonumber(string.format("%.2f", scale))
    head:SetScale(ns.db.scale)
    local compact = ns.db.compact and not IsNarration(head.item)
    head:SetHeight(compact and COMPACT_HEIGHT or FULL_HEIGHT)
    if compact then
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
    if ns.AnnouncePosition then
        ns.AnnouncePosition()
    end
end

function ns.SetSubtitle(text)
    if IsNarration(head.item) or (ns.db.showSubtitle and not ns.db.compact) then
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
    head.item = nil
    ns.ApplyWindowSettings()
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
    if head.bugButton then head.bugButton:SetText(L.FB_REPORT) end
    RefreshStopButton()
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
