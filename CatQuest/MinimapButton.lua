local addonName = ...
local ns = CatQuest335 or {}
CatQuest335 = ns
local L = ns.L

-- Scroll button on the minimap edge, as in the original CatQuest:
-- left click replays the lore of this place, right click opens settings.
-- Hold Shift while dragging it around the minimap; the angle is saved.
if not Minimap then
    return
end

-- Keep both the texture path and the global frame names unique: other addons
-- often reuse Blizzard's scroll icon and generic minimap globals.
local button = CreateFrame("Button", "CatQuestExtendedMinimapButton", Minimap)
button:SetWidth(31)
button:SetHeight(31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:EnableMouse(true)
button:SetMovable(true)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = button:CreateTexture(nil, "BACKGROUND")
icon:SetWidth(20)
icon:SetHeight(20)
icon:SetTexture("Interface\\AddOns\\CatQuest\\CatQuestIcon")
icon:SetPoint("TOPLEFT", 7, -5)

local border = button:CreateTexture(nil, "OVERLAY")
border:SetWidth(53)
border:SetHeight(53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

local menu = CreateFrame("Frame", "CatQuestExtendedMinimapMenu", UIParent, "UIDropDownMenuTemplate")
local function InitializeMenu(_, level)
    if level ~= 1 then
        return
    end
    local lock = UIDropDownMenu_CreateInfo()
    lock.text = ns.db.minimapLocked and L.MINIMAP_UNLOCK or L.MINIMAP_LOCK
    lock.checked = ns.db.minimapLocked and true or false
    lock.isNotRadio = true
    lock.func = function()
        ns.db.minimapLocked = not ns.db.minimapLocked
        if CloseDropDownMenus then
            CloseDropDownMenus()
        end
    end
    UIDropDownMenu_AddButton(lock, level)

    local options = UIDropDownMenu_CreateInfo()
    options.text = L.MINIMAP_OPTIONS
    options.notCheckable = true
    options.func = function()
        if CloseDropDownMenus then
            CloseDropDownMenus()
        end
        if ns.OpenOptions then
            ns.OpenOptions()
        end
    end
    UIDropDownMenu_AddButton(options, level)
end
UIDropDownMenu_Initialize(menu, InitializeMenu, "MENU")

local function Place()
    local angle = math.rad(tonumber(ns.db.minimapAngle) or 135)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
end

local dragActive = false
local suppressClick = false

button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then
        ToggleDropDownMenu(1, nil, menu, "cursor", 0, 0)
    elseif suppressClick then
        suppressClick = false
        return
    else
        ns.ReadPlace(true)
    end
end)

local function EndDrag(self)
    dragActive = false
    self:SetScript("OnUpdate", nil)
end

local function BeginDrag(self)
    if dragActive or ns.db.minimapLocked or not IsShiftKeyDown() then
        return
    end
    dragActive = true
    -- Shift is a deliberate move gesture, so do not also replay the place
    -- lore when the button is released after the gesture.
    suppressClick = true
    self:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        local cx, cy = Minimap:GetCenter()
        ns.db.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
        Place()
    end)
end

-- OnDragStart is the normal path, but a few 3.3.5 clients do not emit it for
-- a button attached to Minimap. MouseDown keeps dragging reliable there too.
button:SetScript("OnDragStart", BeginDrag)
button:SetScript("OnDragStop", EndDrag)
button:SetScript("OnMouseDown", function(self, mouse)
    if mouse == "LeftButton" then
        if not IsShiftKeyDown() then
            -- If the client did not emit OnClick after the previous drag,
            -- the next ordinary click must still remain a normal replay.
            suppressClick = false
        end
        BeginDrag(self)
    end
end)
button:SetScript("OnMouseUp", function(self, mouse)
    if mouse == "LeftButton" then
        EndDrag(self)
    end
end)

button:SetScript("OnEnter", function(self)
    if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("CatQuest")
        GameTooltip:AddLine(L.MINIMAP_TIP_LEFT, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TIP_RIGHT, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TIP_DRAG, 1, 1, 1)
        GameTooltip:Show()
    end
end)
button:SetScript("OnLeave", function()
    if GameTooltip then
        GameTooltip:Hide()
    end
end)

function ns.UpdateMinimapButton()
    Place()
    if ns.db.minimap then
        button:Show()
    else
        button:Hide()
    end
end
ns.UpdateMinimapButton()
