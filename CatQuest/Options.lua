local addonName = ...
local ns = CatQuest335 or {}
CatQuest335 = ns
local L = ns.L

-- Settings panel: Game Menu > Interface > AddOns > CatQuest (/cq options).
-- Sections follow the original CatQuest: what is voiced, books and places,
-- the speech window, sound. 3.3.5 templates only.
local panel = CreateFrame("Frame", "CatQuest335Options", UIParent)
panel.name = "CatQuest"

-- The settings list is taller than the options panel, so the controls live
-- in a scrolling area.
local scroll = CreateFrame("ScrollFrame", "CatQuest335OptionsScroll", panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, -4)
scroll:SetPoint("BOTTOMRIGHT", -27, 4)
local content = CreateFrame("Frame", "CatQuest335OptionsContent", scroll)
content:SetWidth(600)
content:SetHeight(560)
scroll:SetScrollChild(content)

local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -12)
title:SetText("CatQuest " .. tostring(ns.VERSION or ""))

local description = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
description:SetText(L.OPT_DESC)

local controls = {}

local function Header(text, anchor, x, y)
    local header = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -16)
    header:SetText(text)
    return header
end

local function AddCheck(key, label, anchor, onChange)
    local name = "CatQuest335Option_" .. key
    local check = CreateFrame("CheckButton", name, content, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -1)
    _G[name .. "Text"]:SetText(label)
    check:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        if onChange then
            onChange(ns.db[key])
        end
    end)
    check.refresh = function()
        check:SetChecked(ns.db[key] and true or false)
    end
    controls[#controls + 1] = check
    return check
end

local function AddSlider(key, label, anchor, low, high, step, format, onChange)
    local name = "CatQuest335Option_" .. key
    local slider = CreateFrame("Slider", name, content, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -22)
    slider:SetWidth(200)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    _G[name .. "Low"]:SetText(string.format(format, low))
    _G[name .. "High"]:SetText(string.format(format, high))
    local function Label(value)
        _G[name .. "Text"]:SetText(label .. ": " .. string.format(format, value))
    end
    slider:SetScript("OnValueChanged", function(_, value)
        -- Snap to the step and drop float noise (24 * 0.05 = 1.2000000000000002).
        value = tonumber(string.format("%.4f", math.floor(value / step + 0.5) * step))
        ns.db[key] = value
        Label(value)
        if onChange then
            onChange(value)
        end
    end)
    slider.refresh = function()
        slider:SetValue(tonumber(ns.db[key]) or low)
        Label(tonumber(ns.db[key]) or low)
    end
    controls[#controls + 1] = slider
    return slider
end

local function AddDropDown(name, label, anchor, values, current, onSelect)
    local caption = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    caption:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -10)
    caption:SetText(label)
    local dropdown = CreateFrame("Frame", name, content, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", -20, -2)
    UIDropDownMenu_SetWidth(dropdown, 200)
    UIDropDownMenu_Initialize(dropdown, function()
        local selected = current()
        for i = 1, #values do
            local entry = values[i]
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.text
            info.value = entry.value
            info.checked = entry.value == selected
            info.func = function(button)
                onSelect(button.value)
                UIDropDownMenu_SetSelectedValue(dropdown, button.value)
                UIDropDownMenu_SetText(dropdown, entry.text)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    dropdown.refresh = function()
        local selected = current()
        for i = 1, #values do
            if values[i].value == selected then
                UIDropDownMenu_SetSelectedValue(dropdown, selected)
                UIDropDownMenu_SetText(dropdown, values[i].text)
            end
        end
    end
    controls[#controls + 1] = dropdown
    return dropdown
end

-- Sections and captions follow the original CatQuest 1.0.6 settings, as far
-- as 3.3.5 allows (no 3D portrait, Dialog channel or mob barks here).
local function ApplyWindow()
    if ns.ApplyWindowSettings then
        ns.ApplyWindowSettings()
    end
    if ns.AnnounceSettings then
        ns.AnnounceSettings()
    end
end

-- One list, top to bottom: what to read, how to read, lore of places,
-- head and subtitles, sound. (Two columns did not fit the panel.)
local what = Header(L.OPT_SECTION_VOICE, description, 0, -10)
local enabled = AddCheck("enabled", L.OPT_ENABLED, what, function(on)
    if not on and ns.Stop then
        ns.Stop()
    end
end)
local auto = AddCheck("auto", L.OPT_AUTO, enabled)
local gossipAuto = AddCheck("gossipAuto", L.OPT_GOSSIP_AUTO, auto)
local npcLore = AddCheck("npcLore", L.OPT_NPC_LORE, gossipAuto)
local npcTriggers = {
    { value = "target", text = L.OPT_NPC_TRIGGER_TARGET },
    { value = "kill", text = L.OPT_NPC_TRIGGER_KILL },
    { value = "manual", text = L.OPT_NPC_TRIGGER_MANUAL },
}
local npcTrigger = AddDropDown("CatQuest335NpcLoreTriggerDropDown", L.OPT_NPC_TRIGGER, npcLore,
    npcTriggers,
    function() return ns.db.npcLoreTrigger or "target" end,
    function(value) ns.db.npcLoreTrigger = value end)
local turnin = AddCheck("turnin", L.OPT_TURNIN, npcTrigger)
local books = AddCheck("books", L.OPT_BOOKS, turnin)
local bookPages = AddCheck("bookPages", L.OPT_BOOK_PAGES, books)
local remote = AddCheck("remoteEnabled", L.OPT_REMOTE, bookPages)

local how = Header(L.OPT_SECTION_HOW, remote, 0, -8)
local queue = AddCheck("queue", L.OPT_QUEUE, how)
local afterAccept = AddCheck("readAfterAccept", L.OPT_AFTER_ACCEPT, queue)
local greetDelay = AddCheck("greetDelay", L.OPT_GREET_DELAY, afterAccept)
local stopOnClose = AddCheck("stopOnClose", L.OPT_STOP_ON_CLOSE, greetDelay)
local readButton = AddCheck("readButton", L.OPT_READ_BUTTON, stopOnClose, function()
    if ns.UpdateQuestFrameButton then
        ns.UpdateQuestFrameButton()
    end
end)

local languages = { { value = "auto", text = string.format(L.OPT_LANG_AUTO, ns.LanguageName(ns.ClientLocale())) } }
for i = 1, #ns.VOICE_LOCALES do
    local locale = ns.VOICE_LOCALES[i]
    languages[#languages + 1] = { value = locale, text = ns.LanguageName(locale) .. " (" .. ns.ShortLocale(locale) .. ")" }
end
local language = AddDropDown("CatQuest335LanguageDropDown", L.OPT_LANGUAGE, readButton, languages,
    function() return ns.db.language or "auto" end,
    function(value) ns.SetLanguage(value) end)

local uiLanguages = {
    { value = "auto", text = string.format(L.OPT_LANG_AUTO, ns.LanguageName(ns.ClientLocale())) },
    { value = "ruRU", text = ns.LanguageName("ruRU") },
    { value = "enUS", text = ns.LanguageName("enUS") },
}
local uiLanguage = AddDropDown("CatQuest335UILanguageDropDown", L.OPT_UI_LANGUAGE, language, uiLanguages,
    function() return ns.UIChoice() end,
    function(value) ns.SetUILanguage(value) end)

local lore = Header(L.OPT_SECTION_BOOKS, uiLanguage, 20, -8)
local places = AddCheck("places", L.OPT_PLACES, lore)
local resetPlaces = CreateFrame("Button", "CatQuest335OptionResetPlaces", content, "UIPanelButtonTemplate")
resetPlaces:SetWidth(240)
resetPlaces:SetHeight(22)
resetPlaces:SetPoint("TOPLEFT", places, "BOTTOMLEFT", -4, -4)
resetPlaces:SetText(L.OPT_RESET_PLACES)
resetPlaces:SetScript("OnClick", function()
    if ns.ResetPlaces then
        ns.ResetPlaces()
    end
end)
local minimap = AddCheck("minimap", L.OPT_MINIMAP, resetPlaces, function()
    if ns.UpdateMinimapButton then
        ns.UpdateMinimapButton()
    end
end)
local minimapLocked = AddCheck("minimapLocked", L.OPT_MINIMAP_LOCKED, minimap)
local storyQuestTitles = AddCheck("storyQuestTitles", L.OPT_STORY_QUEST_TITLES, minimapLocked)

local window = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
window:SetPoint("TOPLEFT", storyQuestTitles, "BOTTOMLEFT", 0, -10)
window:SetText(L.OPT_SECTION_WINDOW)
local headCheck = AddCheck("head", L.OPT_HEAD, window, function(on)
    if not on and ns.HideHead then
        ns.HideHead()
    end
end)
local subtitles = AddCheck("showSubtitle", L.OPT_SUBTITLES, headCheck)
local compact = AddCheck("compact", L.OPT_COMPACT, subtitles, ApplyWindow)
local locked = AddCheck("headLocked", L.OPT_HEAD_LOCKED, compact)
local scale = AddSlider("scale", L.OPT_SCALE, locked, 0.6, 1.5, 0.05, "%.2f", ApplyWindow)
local reset = CreateFrame("Button", "CatQuest335OptionResetWindow", content, "UIPanelButtonTemplate")
reset:SetWidth(200)
reset:SetHeight(22)
reset:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", -4, -16)
reset:SetText(L.OPT_RESET_WINDOW)
reset:SetScript("OnClick", function()
    if ns.ResetWindowPosition then
        ns.ResetWindowPosition()
    end
end)

local sound = Header(L.OPT_SECTION_SOUND, reset, 0, -10)
local channels = {
    { value = "SFX", text = L.OPT_CHANNEL_SFX },
    { value = "Master", text = L.OPT_CHANNEL_MASTER },
    { value = "Ambience", text = L.OPT_CHANNEL_AMBIENCE },
}
local channel = AddDropDown("CatQuest335ChannelDropDown", L.OPT_CHANNEL, sound, channels,
    function() return ns.db.volumeChannel or "SFX" end,
    function(value) ns.db.volumeChannel = value end)
local duck = AddSlider("duck", L.OPT_DUCK, channel, 0, 100, 10, "%d", function()
    if ns.AnnounceSettings then
        ns.AnnounceSettings()
    end
end)
duck:ClearAllPoints()
duck:SetPoint("TOPLEFT", channel, "BOTTOMLEFT", 24, -22)
local gap = AddSlider("trackGap", L.OPT_GAP, duck, 0, 5, 0.5, "%.1f")
local background = AddCheck("keepInBackground", L.OPT_BACKGROUND, gap)
background:ClearAllPoints()
background:SetPoint("TOPLEFT", gap, "BOTTOMLEFT", -4, -18)

-- The scrolling area is exactly as tall as the list.
local function FitContent()
    local top = content:GetTop()
    local bottom = background:GetBottom() or math.huge
    if top and bottom < math.huge then
        content:SetHeight(math.max(1, top - bottom + 12))
    end
    content:SetWidth(math.max(1, (scroll:GetWidth() or 600)))
end

function panel.refresh()
    for i = 1, #controls do
        controls[i].refresh()
    end
    FitContent()
    -- The first time the panel opens, sizes are known only after a frame.
    if ns.After then
        ns.After(0, FitContent)
    end
end
panel:SetScript("OnShow", panel.refresh)

if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

function ns.OpenOptions()
    if InterfaceOptionsFrame_OpenToCategory then
        -- 3.3.5 needs the call twice the first time the frame opens.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
