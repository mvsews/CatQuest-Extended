local ns = CatQuest335
local L = ns.L
local window
local function value(v)
    if v == nil then return "nil" end
    return tostring(v):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[\r\n\t]", " "):sub(1, 240)
end
local function fields(row, keys)
    local parts = {}
    for _, key in ipairs(keys) do parts[#parts+1] = key .. "=" .. value(row[key]) end
    return table.concat(parts, " ")
end
local ITEM_KEYS = {"key","questID","kind","prefetchSlot","file","duration","playChannel",
    "prefetchSent","prefetchReady","bridgeVerified","readySignalAttempts","readyFontRequested",
    "readyFontObserved","readyFontUnit","readyFontMetrics","readyFontWidths","readySignalError","nextReadySignalAt","requestedAt","startedAt"}
function ns.BuildDebugReport()
    local state, db, bridge = ns.state or {}, ns.db or {}, CatQuest335_BridgeReady or {}
    local function countMap(map)
        local n = 0
        if type(map) == "table" then for _ in pairs(map) do n = n + 1 end end
        return n
    end
    local out = {"CatQuest diagnostic report v1", "generated=" .. (date and date("%Y-%m-%d %H:%M:%S") or "?") ..
        " uptime=" .. value(GetTime()) .. " addon=" .. value(ns.VERSION),
        "client=" .. (GetBuildInfo and value(GetBuildInfo()) or "?") .. " locale=" .. value(ns.VoiceLocale()),
        "settings " .. fields(db, {"enabled","auto","remoteEnabled","volumeChannel","head","pendingTimeout"}),
        "playbackModes quest=" .. value(db.playbackModes and db.playbackModes.quest)
            .. " turnin=" .. value(db.playbackModes and db.playbackModes.turnin)
            .. " book=" .. value(db.playbackModes and db.playbackModes.book)
            .. " place=" .. value(db.playbackModes and db.playbackModes.place)
            .. " dungeon=" .. value(db.playbackModes and db.playbackModes.dungeon)
            .. " gossip=" .. value(db.playbackModes and db.playbackModes.gossip)
            .. " npcLore=" .. value(db.playbackModes and db.playbackModes.npcLore)
            .. " played=" .. tostring(countMap(db.played))
            .. " marks=" .. tostring(type(db.marks) == "table" and #db.marks or 0),
        "bridge " .. fields(bridge, {"mode","fontReady","prefetchSignal","readyMetrics","waitingFont","clientTrace","contactPage","extVersion"}),
        "state=" .. (state.active and "playing" or state.pending and state.pending[1] and "waiting" or "idle") ..
            " queue=" .. #(state.queue or {}) .. " pending=" .. #(state.pending or {}),
        "NOTE: playing = Lua API call; finished = duration timer. Neither confirms audible sound.",
        "NOTE: HTTP/backend results are in the extension report; correlate bridge page + slot + quest/kind.", ""}
    local function item(label, row)
        if row then out[#out+1] = label .. " " .. fields(row, ITEM_KEYS) end
    end
    if GetCVar then
        for _, name in ipairs({"Sound_EnableAllSound","Sound_EnableSFX","Sound_EnableMusic","Sound_MusicVolume","Sound_MasterVolume","Sound_SFXVolume"}) do
            local ok, setting = pcall(GetCVar,name)
            out[#out+1] = name .. "=" .. (ok and value(setting) or "unavailable")
        end
    end
    item("active", state.active); item("last", state.lastItem)
    for _, name in ipairs({"pending","queue"}) do
        local list = state[name] or {}
        for i = 1, math.min(#list, 30) do item(name .. "[" .. i .. "]", list[i]) end
        if #list > 30 then out[#out+1] = name .. " truncated=" .. (#list-30) end
    end
    local marks = db.marks or {}
    if #marks > 0 then
        out[#out+1] = "\nMARKS newest first:"
        for i = #marks, math.max(1, #marks - 19), -1 do
            local mark = marks[i]
            out[#out+1] = (date and date("%Y-%m-%d %H:%M:%S", tonumber(mark.at) or 0) or value(mark.at))
                .. " key=" .. value(mark.key) .. " questID=" .. value(mark.questID)
                .. " kind=" .. value(mark.kind) .. " title=" .. value(mark.title)
                .. " elapsed=" .. value(mark.elapsed)
        end
    end
    out[#out+1] = "\nEVENTS oldest first (bounded to 300; previous sessions include addon version):"
    local log = db.voiceLog or {}
    for i = math.max(1, #log-299), #log do
        local row = log[i]
        local stamp = date and date("%Y-%m-%d %H:%M:%S", tonumber(row.at) or 0) or value(row.at)
        out[#out+1] = stamp .. " " .. fields(row, {"uptime","version","page","status","questID","kind","slot","title",
            "detail","queue","pending","channel","duration","attempt","verified"})
        if row.file ~= "" or row.requestedFont then
            out[#out+1] = "  " .. fields(row, {"key","file","requestedFont","observedFont","fontUnit","fontMetrics","fontWidths"})
        end
    end
    return table.concat(out, "\n")
end

function ns.OpenDebug()
    if not window then
        window = CreateFrame("Frame", "CatQuest335Debug", UIParent)
        window:SetWidth(740); window:SetHeight(490); window:SetPoint("CENTER")
        window:SetFrameStrata("FULLSCREEN_DIALOG"); window:SetClampedToScreen(true)
        window:EnableMouse(true); window:SetMovable(true); window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", window.StartMoving)
        window:SetScript("OnDragStop", window.StopMovingOrSizing)
        window:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=24,
            insets={left=6,right=6,top=6,bottom=6}})
        if UISpecialFrames then table.insert(UISpecialFrames, "CatQuest335Debug") end
        local title = window:CreateFontString(nil,"ARTWORK","GameFontNormalLarge")
        title:SetPoint("TOPLEFT",20,-18); title:SetText(L.DEBUG_TITLE)
        local help = window:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
        help:SetPoint("TOPLEFT",20,-44); help:SetWidth(695); help:SetJustifyH("LEFT"); help:SetText(L.DEBUG_HELP)
        local close = CreateFrame("Button",nil,window,"UIPanelCloseButton")
        close:SetPoint("TOPRIGHT",-5,-5); close:SetScript("OnClick",function() window:Hide() end)
        local scroll = CreateFrame("ScrollFrame","CatQuest335DebugScroll",window,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",20,-88);scroll:SetPoint("BOTTOMRIGHT",-42,55)
        local text = CreateFrame("EditBox","CatQuest335DebugText",scroll)
        text:SetWidth(665);text:SetHeight(300);text:SetMultiLine(true);text:SetAutoFocus(false)
        text:SetFontObject(ChatFontNormal or GameFontNormal);text:SetMaxBytes(1048576)
        text:SetScript("OnEscapePressed",function(box) box:ClearFocus();window:Hide() end)
        text:SetScript("OnCursorChanged",function(_,x,y,w,h)
            local offset = scroll:GetVerticalScroll()
            if -y < offset then scroll:SetVerticalScroll(math.max(0,-y))
            elseif -y+h > offset+scroll:GetHeight() then scroll:SetVerticalScroll(math.max(0,-y+h-scroll:GetHeight())) end
        end)
        scroll:SetScrollChild(text);window.text=text;window.scroll=scroll
        local function button(label,x,action)
            local b=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
            b:SetWidth(170);b:SetHeight(24);b:SetPoint("BOTTOMLEFT",20+x,18);b:SetText(label);b:SetScript("OnClick",action)
        end
        button(L.DEBUG_REFRESH,0,function() window.text:SetText(ns.BuildDebugReport());window.scroll:SetVerticalScroll(0) end)
        button(L.DEBUG_SELECT,180,function() window.text:SetFocus();window.text:HighlightText() end)
        button(L.DEBUG_CLEAR,360,function() ns.db.voiceLog={};window.text:SetText(ns.BuildDebugReport()) end)
    end
    window.text:SetText(ns.BuildDebugReport());window.scroll:SetVerticalScroll(0);window:Show()
end
