-- CatQuest Companion pixel bridge.
--
-- The ordinary WoW client cannot make HTTP requests, access files, or notify
-- another process when PlaySoundFile is called.  This addon therefore draws a
-- tiny encoded frame in the top-left corner.  client/catquest_client.py reads
-- those pixels and plays the server track outside WoW.
--
-- Protocol: 96 x 8 cells, each cell is 4 physical pixels and contains three
-- nibbles (R/G/B, nibble * 17). Cells 0..3 are sync, 4..19 calibration,
-- 20..24 are msgId/chunk/index/count/length/checksum, and 25.. contain data.
local ADDON, ns = ...

CatQuest335Companion = ns or {}
ns = CatQuest335Companion
CatQuest335_CompanionReady = true

local COLS, ROWS, CELL = 96, 8, 4
local HEADER = 25
local CHUNK_BYTES = math.floor((COLS * ROWS - HEADER) * 3 / 2)
local CHUNK_TIME = 0.05
local MIN_SHOW = 2.5
local MIN_CYCLES = 5

local function Value12(value)
    return {
        math.floor(value / 256) % 16,
        math.floor(value / 16) % 16,
        value % 16,
    }
end

function ns.Encode(payload, msgID)
    local count = math.max(1, math.ceil(#payload / CHUNK_BYTES))
    local chunks = {}
    for chunkIndex = 0, count - 1 do
        local data = payload:sub(chunkIndex * CHUNK_BYTES + 1, (chunkIndex + 1) * CHUNK_BYTES)
        local checksum = 0
        for i = 1, #data do
            checksum = (checksum + data:byte(i)) % 4096
        end

        local cells = {
            { 15, 0, 15 }, { 0, 15, 0 }, { 15, 0, 15 }, { 0, 15, 0 },
        }
        for value = 0, 15 do
            cells[#cells + 1] = { value, value, value }
        end
        cells[#cells + 1] = Value12(msgID)
        cells[#cells + 1] = Value12(chunkIndex)
        cells[#cells + 1] = Value12(count)
        cells[#cells + 1] = Value12(#data)
        cells[#cells + 1] = Value12(checksum)

        local nibbles = {}
        for i = 1, #data do
            local byte = data:byte(i)
            nibbles[#nibbles + 1] = math.floor(byte / 16)
            nibbles[#nibbles + 1] = byte % 16
        end
        for i = 1, #nibbles, 3 do
            cells[#cells + 1] = { nibbles[i], nibbles[i + 1] or 0, nibbles[i + 2] or 0 }
        end
        chunks[#chunks + 1] = cells
    end
    return chunks
end

local bridge = { msgID = 0 }
ns.bridge = bridge

local function EnsureFrame()
    if bridge.frame then
        return bridge.frame
    end
    local frame = CreateFrame("Frame", "CatQuestCompanionBridge", UIParent)
    if frame.SetIgnoreParentScale then
        frame:SetIgnoreParentScale(true)
    end
    if frame.SetScale then
        frame:SetScale(1)
    end
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(10000)
    frame:Hide()
    frame.cells = {}
    for i = 1, COLS * ROWS do
        local texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetColorTexture(0, 0, 0, 1)
        frame.cells[i] = texture
    end
    bridge.frame = frame
    return frame
end

local function Layout(frame)
    local physicalHeight = 768
    if GetPhysicalScreenSize then
        local _, height = GetPhysicalScreenSize()
        physicalHeight = tonumber(height) or physicalHeight
    end
    local unit = 768 / physicalHeight * CELL
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    frame:SetSize(COLS * unit, ROWS * unit)
    for index, texture in ipairs(frame.cells) do
        local cell = index - 1
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", (cell % COLS) * unit,
            -math.floor(cell / COLS) * unit)
        texture:SetSize(unit, unit)
    end
end

local function Draw(frame, cells)
    for index, texture in ipairs(frame.cells) do
        local color = cells[index]
        if color then
            texture:SetColorTexture(color[1] * 17 / 255, color[2] * 17 / 255,
                color[3] * 17 / 255, 1)
        else
            texture:SetColorTexture(0, 0, 0, 1)
        end
    end
end

local function OnUpdate(frame, elapsed)
    bridge.elapsed = bridge.elapsed + elapsed
    bridge.total = bridge.total + elapsed
    if bridge.total >= bridge.duration then
        frame:Hide()
        frame:SetScript("OnUpdate", nil)
        return
    end
    if bridge.elapsed >= CHUNK_TIME then
        bridge.elapsed = 0
        bridge.index = bridge.index % #bridge.chunks + 1
        Draw(frame, bridge.chunks[bridge.index])
    end
end

function ns.Send(payload)
    payload = tostring(payload or "")
    local frame = EnsureFrame()
    bridge.msgID = (bridge.msgID + 1) % 4096
    bridge.chunks = ns.Encode(payload, bridge.msgID)
    bridge.index, bridge.elapsed, bridge.total = 1, 0, 0
    bridge.duration = math.max(MIN_SHOW, #bridge.chunks * CHUNK_TIME * MIN_CYCLES)
    Layout(frame)
    Draw(frame, bridge.chunks[1])
    frame:SetScript("OnUpdate", OnUpdate)
    frame:Show()
    return true
end

function ns.Stop()
    return ns.Send("X")
end
