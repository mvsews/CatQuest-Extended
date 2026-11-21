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
-- Feedback frames support up to 256 bytes in the bridge. Seven bytes are
-- reserved for target/id/reason/locale, leaving room for about 120 Cyrillic
-- characters (240 UTF-8 bytes).
local NOTE_MAX_BYTES = 240

local function Target(item)
    if not item then
        return nil
    end
    if item.kind == "npcLore" then
        local id = tonumber(item.npcLoreID or (item.npc and item.npc.id))
        if id and id > 0 then return 4, id end
        return nil
    end
    if item.kind == "book" or item.kind == "place" or item.kind == "dungeon" then
        local hash = item.bookHash or (item.key and string.match(item.key, ":(%x%x%x%x%x%x%x%x)$"))
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
form:SetHeight(330)
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

form.attachDiagnostics = CreateFrame("CheckButton", "CatQuest335FeedbackDiagnostics", form, "UICheckButtonTemplate")
form.attachDiagnostics:SetWidth(24)
form.attachDiagnostics:SetHeight(24)
form.attachDiagnostics:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 14, 42)
local diagnosticsLabel = _G["CatQuest335FeedbackDiagnosticsText"]
if diagnosticsLabel then
    diagnosticsLabel:SetText(L.FB_ATTACH_DIAGNOSTICS)
end

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
    if form.attachDiagnostics:GetChecked() and ns.SubmitContact then
        local item = form.item or {}
        local id = item.questID or item.npcLoreID or item.bookHash or "?"
        local title = item.title or item.name or "?"
        local reason = form.reason and L[REASONS[form.reason]] or "?"
        local note = form.note:GetText() or ""
        local context = string.format(L.FB_DEBUG_CONTEXT, tostring(title), tostring(id), tostring(reason), note ~= "" and note or "—")
        ns.SubmitContact(1, context, true)
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
    form.attachDiagnostics:SetChecked(false)
    local name = (item.npc and item.npc.name) or item.title
        or (item.questID and item.questID > 0 and string.format(L.QUEST_N, item.questID)) or ""
    local label = name .. ((item.questID or 0) > 0 and ("  (ID " .. item.questID .. ")") or "")
    if item.kind == "npcLore" then
        label = label .. "  (NPC ID " .. tostring(item.npcLoreID or (item.npc and item.npc.id)) .. ")"
    end
    if (item.kind == "book" or item.kind == "place" or item.kind == "dungeon") and item.file then
        local file = string.match(item.file, "([^\\/]+)$") or item.file
        label = label .. "\n" .. (L.FB_FILE or "File") .. ": " .. file
    end
    form.quest:SetText(label)
    form:Show()
    return true
end

-- A text button remains visible without relying on a client-specific icon.
local head = CatQuest335TalkingHead
if head then
    local mark = CreateFrame("Button", "CatQuest335VoiceMarkButton", head, "UIPanelButtonTemplate")
    mark:SetWidth(24)
    mark:SetHeight(22)
    mark:SetPoint("TOPRIGHT", head, "TOPRIGHT", -130, -16)
    mark:SetText(L.FB_MARK)
    mark:SetFrameLevel((head:GetFrameLevel() or 0) + 20)
    mark:SetScript("OnClick", function()
        if ns.MarkCurrentVoice then ns.MarkCurrentVoice() end
    end)
    mark:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(L.HELP_MARK)
            GameTooltip:Show()
        end
    end)
    mark:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    head.markButton = mark
    local bug = CreateFrame("Button", "CatQuest335FeedbackButton", head, "UIPanelButtonTemplate")
    bug:SetWidth(112)
    bug:SetHeight(22)
    bug:SetPoint("TOPRIGHT", head, "TOPRIGHT", -12, -16)
    bug:SetText(L.FB_REPORT)
    head.title:SetWidth(322)
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
