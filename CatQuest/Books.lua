local addonName = ...
local ns = CatQuest335 or {}
CatQuest335 = ns
local L = ns.L

-- Books, notes, plaques and place lore read by a narrator (CatQuest Books,
-- ruRU). Audio comes from the voice server like quest tracks; the data here
-- (BookData.lua) finds the track and holds the subtitles.
--   * a book or note: by its title and page, or an untitled text by its start;
--   * place lore: by the subzone name the lore text starts with, once per place.

local data = CatQuest335Books or { books = {}, titles = {} }
local REMOTE = "Interface\\AddOns\\CatQuest335_ServerVoices\\ruRU\\Sounds\\b\\"

local function Variant(book)
    if book.g == 1 then
        return ns.IsFemale() and "_f" or "_m"
    end
    return ""
end

local function Cues(book)
    local cues = book.c or {}
    if cues.x then
        return cues.x
    end
    if ns.IsFemale() and cues.f then
        return cues.f
    end
    return cues.m or cues.f or {}
end

local function FirstLine(book)
    local cues = book.c or {}
    local list = cues.x or cues.m or cues.f
    return list and list[1] and list[1][2] or ""
end

-- Text compared by its first bytes, with whitespace collapsed: page text and
-- the pack's first subtitle line start the same way.
local KEY_BYTES = 48
local function ContentKey(text)
    text = string.gsub(text or "", "%s+", " ")
    text = string.gsub(text, "^ ", "")
    if string.len(text) < 16 then
        return nil
    end
    return string.sub(text, 1, KEY_BYTES)
end

-- Lazy indexes: untitled texts by their start, place lore by its first line,
-- every entry by the start of its first subtitle line.
local prefixes, places, byContent
local function BuildIndexes()
    if prefixes then
        return
    end
    prefixes, places, byContent = {}, {}, {}
    for hash, book in pairs(data.books) do
        local key = ContentKey(FirstLine(book))
        if key and not byContent[key] then
            byContent[key] = hash
        end
    end
    local referenced = {}
    for key, hashes in pairs(data.titles) do
        for i = 1, #hashes do
            referenced[hashes[i]] = true
        end
        if string.sub(key, 1, 1) == "^" then
            prefixes[#prefixes + 1] = { text = string.sub(key, 2), hash = hashes[1] }
        end
    end
    for hash, book in pairs(data.books) do
        if not referenced[hash] then
            places[#places + 1] = { line = FirstLine(book), hash = hash }
        end
    end
end

-- Untitled text: compare its start with the pack's prefixes. "$N" in a prefix
-- is the player name; prefixes with other placeholders are skipped.
local function FindByText(text)
    if not text or text == "" then
        return nil
    end
    BuildIndexes()
    local name = UnitName and UnitName("player") or ""
    for i = 1, #prefixes do
        local prefix = string.gsub(prefixes[i].text, "%$[Nn]", function()
            return name
        end)
        if not string.find(prefix, "$", 1, true) and string.sub(text, 1, #prefix) == prefix then
            return prefixes[i].hash
        end
    end
end

-- The same book can be titled "страница 10" in one client and "стр. 10" in
-- another.
local function TitleVariants(title)
    local variants = { title }
    local short = string.gsub(title, "страница (%d+)", "стр. %1")
    local long = string.gsub(title, "стр%. (%d+)", "страница %1")
    if short ~= title then variants[#variants + 1] = short end
    if long ~= title then variants[#variants + 1] = long end
    return variants
end

function ns.FindBook(title, page, text)
    if title and title ~= "" then
        local variants = TitleVariants(title)
        for i = 1, #variants do
            local hashes = data.titles[variants[i]]
            if hashes and hashes[page or 1] then
                return hashes[page or 1]
            end
        end
    end
    local hash = FindByText(text)
    if hash then
        return hash
    end
    -- A book renamed between clients: find the page by what it says.
    BuildIndexes()
    local key = ContentKey(text)
    return key and byContent[key] or nil
end

-- Fallback for places missing from PlaceData.lua: a place lore entry that
-- starts with exactly this name, followed by a comma, a full stop or a dash.
-- Not by a space and a word: "Лагерь экспедиции" (Outland) must not read
-- "Лагерь экспедиции Эрнестуэя" (Stranglethorn Vale).
function ns.FindPlace(name)
    if not name or name == "" then
        return nil
    end
    BuildIndexes()
    for i = 1, #places do
        local line = places[i].line
        if string.sub(line, 1, #name) == name then
            local rest = string.sub(line, #name + 1, #name + 4)
            if rest == "" or string.find(rest, "^[,.:]") or string.find(rest, "^ [-\226]") then
                return places[i].hash
            end
        end
    end
end

-- Place lore of where the player is: exact zone and subzone first
-- (PlaceData.lua, from the original CatQuest's LoreZones), then the zone
-- itself, then the text fallback above. Returns hash, name, zone. The third
-- value is also returned when the place has no voice yet, for demand stats.
function ns.PlaceHere()
    local zone = GetRealZoneText and GetRealZoneText() or ""
    local sub = GetSubZoneText and GetSubZoneText() or ""
    local table_ = data.places and data.places[zone]
    local areas = data.placeAreas and data.placeAreas[zone]
    local liveArea = tonumber(GetCurrentMapAreaID and GetCurrentMapAreaID()) or 0
    -- Instance map IDs are more stable than a localized display name.  The
    -- generated PlaceLore table contains these only for dungeon entries.
    if GetInstanceInfo and data.placeInstances then
        local _, _, _, _, _, _, _, mapID = GetInstanceInfo()
        local instance = data.placeInstances[tonumber(mapID) or 0]
        if instance then
            return instance.h, instance.n, instance.z, instance.a or liveArea
        end
    end
    if sub ~= "" then
        local hash = table_ and table_[sub]
        if not hash and not table_ then
            hash = ns.FindPlace(sub)
        end
        if hash then
            return hash, sub, zone, tonumber(areas and areas[sub]) or tonumber(areas and areas._zone) or liveArea
        end
        -- A known zone with an unvoiced subzone must stay a separate missing
        -- place. Falling back to the parent zone makes an already-heard zone
        -- swallow the request, so places such as Telaari Basin are never
        -- reported to the server and never appear in the demand statistics.
        if table_ then
            return nil, sub, zone, liveArea
        end
    end
    local hash = (table_ and table_._zone) or (not table_ and ns.FindPlace(zone)) or nil
    if hash then
        return hash, zone, zone, tonumber(areas and areas._zone) or liveArea
    end
    if zone ~= "" or sub ~= "" then
        return nil, sub ~= "" and sub or zone, zone, liveArea
    end
end

-- The marker channel has room for 69 bytes. Keep the names useful while
-- never cutting a UTF-8 sequence in half. The extension turns this into a
-- signed /api/v1/place report.
local function Utf8Limit(text, limit)
    text = tostring(text or "")
    if string.len(text) <= limit then
        return text
    end
    text = string.sub(text, 1, limit)
    while string.len(text) > 0 do
        local last = string.byte(text, string.len(text))
        if not last or last < 128 or last >= 192 then
            break
        end
        text = string.sub(text, 1, string.len(text) - 1)
    end
    return text
end

function ns.ReportPlace(zone, name, hash, areaID)
    if not zone or zone == "" or not name or name == "" then
        return false
    end
    ns.state.placeReports = ns.state.placeReports or {}
    local cleanZone = Utf8Limit(zone, 22)
    local cleanName = Utf8Limit(name, 28)
    local cleanHash = string.match(tostring(hash or ""), "^[0-9a-f]{8}$") or ""
    areaID = math.floor(tonumber(areaID) or 0)
    if areaID < 0 or areaID > 9999999 then areaID = 0 end
    local areaText = tostring(areaID)
    local key = cleanZone .. "\t" .. cleanName .. "\t" .. cleanHash .. "\t" .. areaText
    if ns.state.placeReports[key] then
        return false
    end
    local sent = ns.SendMessageBytes(4, { string.byte(cleanZone .. "\t" .. cleanName .. "\t" .. cleanHash .. "\t" .. areaText, 1, -1) })
    if sent then
        ns.state.placeReports[key] = true
    end
    return sent
end

local function BuildBookItem(hash, kind, title)
    local book = data.books[hash]
    if not book then
        return nil
    end
    if CatQuest335_LocalMode then
        return nil
    end
    local cues = Cues(book)
    local text = {}
    for i = 1, #cues do
        if cues[i][2] and cues[i][2] ~= "" then
            text[#text + 1] = cues[i][2]
        end
    end
    return {
        questID = 0,
        kind = kind,
        key = kind .. ":" .. hash,
        file = REMOTE .. hash .. Variant(book) .. ".ogg",
        cues = cues,
        duration = tonumber(book.d) or 0,
        title = title,
        text = table.concat(text, "\n"),
        remote = true,
        cueIndex = 0,
    }
end

local warnedLocale = false
local function VoiceIsRussian()
    if ns.VoiceLocale() == "ruRU" then
        return true
    end
    if not warnedLocale then
        warnedLocale = true
        ns.Print(L.BOOKS_RU_ONLY)
    end
    return false
end

-- Opening a book or turning a page cuts the previous page and any place lore:
-- what the player is reading now comes first.
local function IsNarration(item)
    return item.kind == "book" or item.kind == "place"
end

local function DropBookItems()
    local active = ns.state.active
    if active and IsNarration(active) then
        ns.SilenceVoice()
        ns.state.active = nil
        -- Let the SFX channel come back before the next page starts.
        ns.state.resumeAt = GetTime() + 0.2
    end
    for _, list in ipairs({ ns.state.queue, ns.state.pending }) do
        for i = #list, 1, -1 do
            if IsNarration(list[i]) then
                table.remove(list, i)
            end
        end
    end
end

-- bookPages (settings): when a page is read through, turn to the next one;
-- ITEM_TEXT_READY then reads it like the button would.
local function TurnPage()
    if ns.db.bookPages == false or not (ItemTextFrame and ItemTextFrame:IsShown()) then
        return
    end
    if ItemTextHasNextPage and ItemTextHasNextPage() and ItemTextNextPage then
        ns.state.turningPage = true
        ItemTextNextPage()
    end
end

local function StopBooks()
    local active = ns.state.active
    if active and active.kind == "book" then
        ns.SilenceVoice()
        ns.state.active = nil
        ns.state.resumeAt = GetTime() + 0.2
        if ns.HideHead then
            ns.HideHead()
        end
    end
    for _, list in ipairs({ ns.state.queue, ns.state.pending }) do
        for i = #list, 1, -1 do
            if list[i].kind == "book" then
                table.remove(list, i)
            end
        end
    end
end

function ns.ReadOpenBook(manual)
    if not ns.db.enabled or not (ns.db.books or manual) or not VoiceIsRussian() then
        return false
    end
    local title = ItemTextGetItem and ItemTextGetItem()
    local page = ItemTextGetPage and ItemTextGetPage() or 1
    local hash = ns.FindBook(title, page, ItemTextGetText and ItemTextGetText())
    if not hash then
        return false
    end
    local item = BuildBookItem(hash, "book", title or L.BOOK_UNTITLED)
    if not item then
        return false
    end
    item.onFinish = TurnPage
    DropBookItems()
    return ns.PlayItem(item, true)
end

function ns.ResetPlaces()
    ns.db.placesHeard = {}
    if ns.db.remoteEnabled and not CatQuest335_LocalMode then
        pcall(PlaySoundFile, "Interface\\AddOns\\CatQuest335_ServerVoices\\places\\reset.ogg", "Master")
    end
    ns.Print(L.LORE_RESET)
end

-- force: /cq place replays the lore of the current place even if heard.
function ns.ReadPlace(force)
    if not ns.db.enabled or not (ns.db.places or force) then
        return false
    end
    -- As in the original: a story does not start in the middle of a fight.
    if not force and InCombatLockdown and InCombatLockdown() then
        ns.state.placeAfterCombat = true
        return false
    end
    if ns.VoiceLocale() ~= "ruRU" then
        if force then
            ns.Print(L.BOOKS_RU_ONLY)
        end
        return false
    end
    local hash, name, zone, areaID = ns.PlaceHere()
    ns.ReportPlace(zone, name, hash or "", areaID)
    ns.db.placesHeard = ns.db.placesHeard or {}
    -- Lasthavens: saved settings are lost on F5; the extension keeps the
    -- places heard and lists them in Bridge.lua.
    if not ns.state.bridgeHeardMerged then
        ns.state.bridgeHeardMerged = true
        if type(CatQuest335_BridgeHeard) == "table" then
            for _, heard in ipairs(CatQuest335_BridgeHeard) do
                ns.db.placesHeard[heard] = true
            end
        end
    end
    if not hash then
        if force then
            ns.Print(L.PLACE_NONE)
        end
        return false
    end
    -- Heard once is enough: coming back to a place stays quiet.
    if ns.db.placesHeard[hash] and not force then
        return false
    end
    local item = BuildBookItem(hash, "place", name)
    if not item then
        return false
    end
    ns.db.placesHeard[hash] = true
    return ns.PlayItem(item, force)
end

-- "Voice" button in the book window: replay the page, or read it when
-- automatic reading is off. Shown only for pages that have a track.
local button
local function OpenPageHash()
    return ns.FindBook(
        ItemTextGetItem and ItemTextGetItem(),
        ItemTextGetPage and ItemTextGetPage() or 1,
        ItemTextGetText and ItemTextGetText()
    )
end

local function UpdateButton()
    if not ItemTextFrame then
        return
    end
    if not button then
        button = CreateFrame("Button", "CatQuest335BookButton", ItemTextFrame, "UIPanelButtonTemplate")
        button:SetWidth(96)
        button:SetHeight(22)
        if ItemTextScrollFrame then
            button:SetPoint("TOPRIGHT", ItemTextScrollFrame, "BOTTOMRIGHT", 0, -6)
        else
            button:SetPoint("BOTTOMRIGHT", ItemTextFrame, "BOTTOMRIGHT", -40, 80)
        end
        button:SetText(L.BTN_READ)
        button:SetScript("OnClick", function()
            ns.ReadOpenBook(true)
        end)
    end
    if ns.db.readButton ~= false and OpenPageHash() then button:Show() else button:Hide() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ITEM_TEXT_READY")
events:RegisterEvent("ITEM_TEXT_CLOSED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_INDOORS")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(_, event)
    local ok, err = pcall(function()
        if event == "ITEM_TEXT_READY" then
            UpdateButton()
            -- A page turned by bookPages goes on reading as the button would.
            local turning = ns.state.turningPage
            ns.state.turningPage = nil
            ns.ReadOpenBook(turning)
        elseif event == "ITEM_TEXT_CLOSED" then
            ns.state.turningPage = nil
            if ns.db.stopOnClose then
                StopBooks()
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if ns.state.placeAfterCombat then
                ns.state.placeAfterCombat = nil
                ns.ReadPlace()
            end
        else
            ns.ReadPlace()
        end
    end)
    if not ok then
        ns.Print(string.format(L.HANDLER_ERROR, tostring(event), tostring(err)))
    end
end)
