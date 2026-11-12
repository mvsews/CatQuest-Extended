local addonName = ...
local ns = CatQuest335 or {}
CatQuest335 = ns
local L = ns.L

-- "Something is wrong with this voice-over": a bug button in the speech
-- window opens a small form (a reason and a short note). On Lasthavens the
-- report goes to the extension as a message of kind 3 and from there to the
-- server, with the character when the player allowed statistics.
--
-- Payload: target (1 quest, 2 turn-in, 3 book or place), id (4 bytes: quest
-- ID or the book hash), reason (1..#REASONS), voice language (index in
-- VOICE_LOCALES), then the note in UTF-8.
local REASONS = {
    "FB_WRONG_TEXT", "FB_STRESS", "FB_VOICE", "FB_VOLUME", "FB_BROKEN", "FB_LANGUAGE", "FB_OTHER",
}
ns.FEEDBACK_REASONS = REASONS
local NOTE_MAX_BYTES = 62

local function Target(item)
    if not item then
        return nil
    end
    if item.kind == "book" or item.kind == "place" then
        local hash = item.key and string.match(item.key, ":(%x%x%x%x%x%x%x%x)$")
        return hash and 3, hash and tonumber(hash, 16)
    end
    local id = tonumber(item.questID)
    if not id or id <= 0 then
        return nil
    end
    return item.kind == "turnin" and 2 or 1, id
end

function ns.FeedbackBytes(item, reason, note)
    local target, id = Target(item)
    if not target or not REASONS[reason] then
        return nil
    end
    local locale = 0
    for i = 1, #ns.VOICE_LOCALES do
        if ns.VOICE_LOCALES[i] == ns.VoiceLocale() then
            locale = i
        end
    end
    local payload = {
        target,
        math.floor(id / 16777216) % 256, math.floor(id / 65536) % 256, math.floor(id / 256) % 256, id % 256,
        reason, locale,
    }
    note = string.gsub(tostring(note or ""), "%s+", " ")
    note = string.gsub(note, "^ ", "")
    note = string.sub(note, 1, NOTE_MAX_BYTES)
    -- A note cut inside a UTF-8 character loses that character.
    while string.len(note) > 0 do
        local last = string.byte(note, -1)
        if last < 128 then
            break
        end
        local start = string.len(note)
        while start > 1 and string.byte(note, start) >= 128 and string.byte(note, start) < 192 do
            start = start - 1
        end
        local lead = string.byte(note, start)
        local need = lead >= 240 and 4 or lead >= 224 and 3 or lead >= 192 and 2 or 1
        if string.len(note) - start + 1 == need then
            break
        end
        note = string.sub(note, 1, start - 1)
    end
    for i = 1, string.len(note) do
        payload[#payload + 1] = string.byte(note, i)
    end
    return payload
end

local form = CreateFrame("Frame", "CatQuest335Feedback", UIParent)
form:SetWidth(340)
form:SetHeight(306)
form:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
form:SetFrameStrata("FULLSCREEN_DIALOG")
form:SetFrameLevel(50)
form:SetToplevel(true)
form:EnableMouse(true)
form:SetMovable(true)
form:RegisterForDrag("LeftButton")
form:SetScript("OnDragStart", form.StartMoving)
form:SetScript("OnDragStop", form.StopMovingOrSizing)
form:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
})
form:Hide()
-- Escape closes it.
if UISpecialFrames then
    table.insert(UISpecialFrames, "CatQuest335Feedback")
end

form.title = form:CreateFontString(nil, "ARTWORK", "GameFontNormal")
form.title:SetPoint("TOPLEFT", form, "TOPLEFT", 18, -18)
form.title:SetWidth(304)
form.title:SetJustifyH("LEFT")
form.title:SetText(L.FB_TITLE)

form.quest = form:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
form.quest:SetPoint("TOPLEFT", form.title, "BOTTOMLEFT", 0, -4)
form.quest:SetWidth(304)
form.quest:SetJustifyH("LEFT")

form.checks = {}
local function Choose(index)
    form.reason = index
    for i = 1, #form.checks do
        form.checks[i]:SetChecked(i == index)
    end
    form.send:Enable()
end
local anchor = form.quest
for i = 1, #REASONS do
    local name = "CatQuest335FeedbackReason" .. i
    local check = CreateFrame("CheckButton", name, form, "UICheckButtonTemplate")
    check:SetWidth(24)
    check:SetHeight(24)
    check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", i == 1 and -4 or 0, i == 1 and -6 or 2)
    local label = _G[name .. "Text"]
    if label then
        label:SetText(L[REASONS[i]])
    end
    check:SetScript("OnClick", function()
        Choose(i)
    end)
    form.checks[i] = check
    anchor = check
end

form.noteLabel = form:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
form.noteLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -6)
form.noteLabel:SetText(L.FB_NOTE)

form.note = CreateFrame("EditBox", "CatQuest335FeedbackNote", form, "InputBoxTemplate")
form.note:SetWidth(296)
form.note:SetHeight(20)
form.note:SetPoint("TOPLEFT", form.noteLabel, "BOTTOMLEFT", 4, -2)
form.note:SetAutoFocus(false)
form.note:SetMaxBytes(NOTE_MAX_BYTES + 1)
form.note:SetScript("OnEscapePressed", function(box)
    box:ClearFocus()
end)
form.note:SetScript("OnEnterPressed", function(box)
    box:ClearFocus()
end)

form.send = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
form.send:SetWidth(110)
form.send:SetHeight(22)
form.send:SetPoint("BOTTOMRIGHT", form, "BOTTOMRIGHT", -16, 14)
form.send:SetText(L.FB_SEND)

form.cancel = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
form.cancel:SetWidth(90)
form.cancel:SetHeight(22)
form.cancel:SetPoint("RIGHT", form.send, "LEFT", -6, 0)
form.cancel:SetText(L.FB_CANCEL)
form.cancel:SetScript("OnClick", function()
    form:Hide()
end)

form.send:SetScript("OnClick", function()
    local payload = ns.FeedbackBytes(form.item, form.reason, form.note:GetText())
    if payload and ns.SendMessageBytes and ns.SendMessageBytes(3, payload) then
        ns.Print(L.FB_SENT)
    else
        ns.Print(L.FB_NOT_SENT)
    end
    form:Hide()
end)

function ns.OpenFeedback(item)
    item = item or ns.state.active or ns.state.lastItem
    if not Target(item) then
        ns.Print(L.FB_NOTHING)
        return false
    end
    form.item = item
    form.reason = nil
    for i = 1, #form.checks do
        form.checks[i]:SetChecked(false)
    end
    form.send:Disable()
    form.note:SetText("")
    local name = item.title or (item.questID and item.questID > 0 and string.format(L.QUEST_N, item.questID)) or ""
    form.quest:SetText(name .. ((item.questID or 0) > 0 and ("  (ID " .. item.questID .. ")") or ""))
    form:Show()
    return true
end

-- The bug button: top right corner of the speech window.
local head = CatQuest335TalkingHead
if head then
    local bug = CreateFrame("Button", "CatQuest335FeedbackButton", head)
    bug:SetWidth(20)
    bug:SetHeight(20)
    bug:SetPoint("TOPRIGHT", head, "TOPRIGHT", -10, -10)
    -- HelpIcon-Bug is not present in every 3.3.5 client. Use a regular
    -- inventory icon that exists in the game data, so the report button is
    -- visible on both stock and custom clients.
    bug:SetNormalTexture("Interface\\Icons\\INV_Misc_Bug_01")
    bug:SetPushedTexture("Interface\\Icons\\INV_Misc_Bug_01")
    bug:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    bug:SetFrameLevel((head:GetFrameLevel() or 0) + 20)
    bug:SetScript("OnClick", function()
        ns.OpenFeedback(head.item)
    end)
    bug:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(L.FB_BUTTON)
            GameTooltip:Show()
        end
    end)
    bug:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    head.bugButton = bug
end
