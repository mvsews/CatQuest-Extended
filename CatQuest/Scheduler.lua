local addonName = ...
local ns = CatQuest335 or {}
CatQuest335 = ns

ns._jobs = ns._jobs or {}
ns._nextJobID = ns._nextJobID or 0

local scheduler = CreateFrame("Frame", "CatQuest335Scheduler", UIParent)

function ns.After(delay, callback)
    ns._nextJobID = ns._nextJobID + 1
    local id = ns._nextJobID
    ns._jobs[id] = {
        at = GetTime() + (delay or 0),
        callback = callback,
    }
    return id
end

function ns.CancelAfter(id)
    if id then
        ns._jobs[id] = nil
    end
end

scheduler:SetScript("OnUpdate", function(_, elapsed)
    local now = GetTime()
    local due = {}

    for id, job in pairs(ns._jobs) do
        if now >= job.at then
            due[#due + 1] = job
            ns._jobs[id] = nil
        end
    end

    for i = 1, #due do
        due[i].callback()
    end

    if ns.OnUpdate then
        ns.OnUpdate(elapsed)
    end
end)
