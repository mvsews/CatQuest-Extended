local ns = CatQuest335
local L = ns.L
local form, sending
local categories = { "CONTACT_ERROR", "CONTACT_SUGGESTION", "CONTACT_OTHER" }
ns.db.contactDraft = ns.db.contactDraft or { category = 1, text = "" }
ns.db.contactPending = ns.db.contactPending or {}
ns.db.contactAttachDiagnostics = ns.db.contactAttachDiagnostics == true
for id in pairs(CatQuest335_BridgeContactReceived or {}) do ns.db.contactPending[id] = nil end

local DIAGNOSTIC_SEPARATOR = "\n\n--- CATQUEST ADDON DIAGNOSTICS ---\n"

local function Utf8Prefix(text, limit)
    text = tostring(text or "")
    if #text <= limit then return text end
    local out, used, at = {}, 0, 1
    while at <= #text do
        local first = string.byte(text, at)
        local size = first < 128 and 1 or first < 224 and 2 or first < 240 and 3 or 4
        if used + size > limit then break end
        out[#out + 1] = string.sub(text, at, at + size - 1)
        used, at = used + size, at + size
    end
    return table.concat(out)
end

local function BuildWire(item)
    local body = item.text
    if item.attachDiagnostics then
        local report = type(ns.BuildDebugReport) == "function" and ns.BuildDebugReport() or ""
        body = body .. DIAGNOSTIC_SEPARATOR .. Utf8Prefix(report, 2200)
    end
    local context = item.context
    local ready = type(CatQuest335_BridgeReady) == "table" and CatQuest335_BridgeReady
    if context and ready.contactContext then
        local who = context.character or {}
        local header = item.attachDiagnostics and "CQ3" or "CQ2"
        local fields = { header, tostring(context.at or 0), context.version or "" }
        if item.attachDiagnostics then fields[#fields + 1] = "1" end
        fields[#fields + 1] = who.realm or ""
        fields[#fields + 1] = who.name or ""
        fields[#fields + 1] = who.guid or ""
        return table.concat(fields, "\t") .. "\n" .. body
    end
    return body
end

local function Progress(percent)
    if form then form.status:SetText(string.format(L.CONTACT_PROGRESS, percent)) end
end

local function Transmit(item, onDone)
    if sending then return false end
    sending = true
    local wire = BuildWire(item)
    local ok = ns.SendContactMessage(item.id, item.category, wire, Progress, function()
        sending = false
        if form then
            form.text:EnableMouse(true)
            if form.text:GetText():find("%S") and #form.text:GetText() <= (form.attachDiagnostics:GetChecked() and 2000 or 4000) then
                form.send:Enable()
            else
                form.send:Disable()
            end
            for _,check in ipairs(form.checks) do check:Enable() end
            form.attachDiagnostics:Enable()
            form.status:SetText(L.CONTACT_QUEUED)
        end
        ns.Print(L.CONTACT_QUEUED)
        if onDone then onDone() end
    end)
    if not ok then sending = false end
    return ok
end

function ns.SubmitContact(category, text, attachDiagnostics)
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local limit = attachDiagnostics and 2000 or 4000
    if not categories[category] or not text:find("%S") or #text > limit then return false end
    -- A persistent nonce prevents retries and double clicks making duplicates.
    ns.db.contactSerial = (tonumber(ns.db.contactSerial) or 0) + 1
    local id = string.format("%08x%04x%04x", (time and time() or 0) % 4294967296,
        math.random(0, 65535), ns.db.contactSerial % 65536)
    local item = { id = id, category = category, text = text, attachDiagnostics = attachDiagnostics == true,
        context={at=time and time() or 0,version=ns.VERSION,character=ns.CharacterSnapshot()} }
    ns.db.contactPending[id] = item
    if not Transmit(item) then
        ns.db.contactPending[id] = nil
        return false
    end
    ns.db.contactDraft = { category = category, text = "" }
    return true
end

local function Build()
    form = CreateFrame("Frame", "CatQuest335Contact", UIParent)
    form:SetWidth(540); form:SetHeight(420)
    form:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    form:SetFrameStrata("FULLSCREEN_DIALOG"); form:SetToplevel(true)
    form:EnableMouse(true); form:SetMovable(true); form:SetClampedToScreen(true)
    form:RegisterForDrag("LeftButton")
    form:SetScript("OnDragStart", form.StartMoving)
    form:SetScript("OnDragStop", form.StopMovingOrSizing)
    form:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=24,
        insets={left=6,right=6,top=6,bottom=6} })
    if UISpecialFrames then table.insert(UISpecialFrames, "CatQuest335Contact") end
    form.title = form:CreateFontString(nil,"ARTWORK","GameFontNormalLarge")
    form.title:SetPoint("TOPLEFT", 20, -20)
    form.help = form:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
    form.help:SetPoint("TOPLEFT",20,-46);form.help:SetWidth(495);form.help:SetJustifyH("LEFT")
    form.checks = {}
    for i = 1, #categories do
        local index = i
        local name = "CatQuest335ContactCategory" .. i
        local check = CreateFrame("CheckButton",name,form,"UICheckButtonTemplate")
        check:SetWidth(24);check:SetHeight(24);check:SetPoint("TOPLEFT",20+(i-1)*165,-78)
        check:SetScript("OnClick",function()
            ns.db.contactDraft.category=index
            for j,c in ipairs(form.checks) do c:SetChecked(j==index) end
        end)
        form.checks[i] = check
    end
    form.panel = CreateFrame("Frame",nil,form)
    form.panel:SetPoint("TOPLEFT",20,-111);form.panel:SetPoint("BOTTOMRIGHT",-20,78)
    form.panel:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3}})
    form.panel:SetBackdropColor(0,0,0,0.8)
    form.scroll=CreateFrame("ScrollFrame","CatQuest335ContactScroll",form.panel,"UIPanelScrollFrameTemplate")
    form.scroll:SetPoint("TOPLEFT",8,-8);form.scroll:SetPoint("BOTTOMRIGHT",-30,8)
    form.text=CreateFrame("EditBox","CatQuest335ContactText",form.scroll)
    form.text:SetWidth(460);form.text:SetHeight(200);form.text:SetMultiLine(true)
    form.text:SetAutoFocus(false);form.text:SetFontObject(ChatFontNormal)
    form.text:SetMaxBytes(4001)
    form.text:SetScript("OnEscapePressed",function(box) box:ClearFocus();form:Hide() end)
    form.text:SetScript("OnEditFocusGained",function(box) if sending then box:ClearFocus() end end)
    form.text:SetScript("OnTextChanged",function(box)
        ns.db.contactDraft.text=box:GetText()
        if not sending then
            local limit = form.attachDiagnostics and form.attachDiagnostics:GetChecked() and 2000 or 4000
            if box:GetText():find("%S") and #box:GetText()<=limit then form.send:Enable() else form.send:Disable() end
        end
    end)
    form.text:SetScript("OnCursorChanged",function(_,x,y,w,h)
        local offset=form.scroll:GetVerticalScroll()
        local cursor=-y
        if cursor<offset then form.scroll:SetVerticalScroll(math.max(0,cursor))
        elseif cursor+h>offset+form.scroll:GetHeight() then
            form.scroll:SetVerticalScroll(math.max(0,cursor+h-form.scroll:GetHeight()))
        end
    end)
    form.scroll:SetScrollChild(form.text)
    form.status=form:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
    form.status:SetPoint("BOTTOMLEFT",20,48);form.status:SetWidth(495);form.status:SetJustifyH("LEFT")
    form.attachDiagnostics=CreateFrame("CheckButton","CatQuest335ContactDiagnostics",form,"UICheckButtonTemplate")
    form.attachDiagnostics:SetWidth(24);form.attachDiagnostics:SetHeight(24);form.attachDiagnostics:SetPoint("BOTTOMLEFT",20,18)
    form.attachDiagnostics:SetScript("OnClick",function(check)
        ns.db.contactAttachDiagnostics = check:GetChecked() and true or false
        form.text:SetMaxBytes(check:GetChecked() and 2001 or 4001)
        local text = form.text:GetText() or ""
        if not sending and text:find("%S") and #text <= (check:GetChecked() and 2000 or 4000) then form.send:Enable() else form.send:Disable() end
    end)
    form.attachDiagnosticsText=form:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
    form.attachDiagnosticsText:SetPoint("LEFT",form.attachDiagnostics,"RIGHT",4,0)
    form.send=CreateFrame("Button",nil,form,"UIPanelButtonTemplate")
    form.send:SetWidth(140);form.send:SetHeight(24);form.send:SetPoint("BOTTOMRIGHT",-20,18)
    form.send:SetScript("OnClick",function()
        if sending then return end
        if ns.SubmitContact(ns.db.contactDraft.category,form.text:GetText(),form.attachDiagnostics:GetChecked()) then
            form.text:SetText("");form.text:ClearFocus();form.send:Disable()
            for _,check in ipairs(form.checks) do check:Disable() end
            form.attachDiagnostics:Disable()
            form.text:EnableMouse(false);form.status:SetText(string.format(L.CONTACT_PROGRESS,0))
        else form.status:SetText(L.CONTACT_UNAVAILABLE) end
    end)
    form.close=CreateFrame("Button",nil,form,"UIPanelButtonTemplate")
    form.close:SetWidth(100);form.close:SetHeight(24);form.close:SetPoint("RIGHT",form.send,"LEFT",-8,0)
    form.close:SetScript("OnClick",function() form.text:ClearFocus();form:Hide() end)
end

function ns.OpenContact()
    if not form then Build() end
    form.title:SetText(L.CONTACT_TITLE);form.help:SetText(L.CONTACT_HELP)
    form.attachDiagnosticsText:SetText(L.CONTACT_ATTACH_DIAGNOSTICS)
    form.attachDiagnostics:SetChecked(ns.db.contactAttachDiagnostics == true)
    form.text:SetMaxBytes(form.attachDiagnostics:GetChecked() and 2001 or 4001)
    if sending then form.attachDiagnostics:Disable() else form.attachDiagnostics:Enable() end
    form.send:SetText(L.FB_SEND);form.close:SetText(L.FB_CANCEL)
    for i,check in ipairs(form.checks) do
        _G["CatQuest335ContactCategory"..i.."Text"]:SetText(L[categories[i]])
        check:SetChecked(i==ns.db.contactDraft.category)
        if sending then check:Disable() else check:Enable() end
    end
    form.text:EnableMouse(not sending);form.text:SetText(ns.db.contactDraft.text or "")
    if sending then form.send:Disable() else form.status:SetText(L.CONTACT_HINT) end
    form:Show();form:Raise()
end

local events=CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent",function()
    ns.After(15,function()
        local function Retry()
            if sending then ns.After(5,Retry);return end
            for _,item in pairs(ns.db.contactPending) do
                if not item.retried then
                    item.retried=true
                    if not Transmit(item,function() ns.After(1,Retry) end) then ns.After(1,Retry) end
                    return
                end
            end
        end
        -- Only one attempt per login; browser storage and the server both
        -- deduplicate by the original id. Do not resend stale drafts.
        for _,item in pairs(ns.db.contactPending) do item.retried=nil end
        Retry()
    end)
end)
SLASH_CATQUEST335CONTACT1="/cqcontact"
SlashCmdList.CATQUEST335CONTACT=function() ns.OpenContact() end
