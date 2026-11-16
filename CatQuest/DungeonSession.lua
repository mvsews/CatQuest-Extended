local ns = CatQuest335
local GAP = 30 * 60

function ns.DungeonAreaKey(name)
    name = (ns.DungeonAreaAliases or {})[name] or name or ""
    name = name:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end)
    name = name:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end)
    return (name:gsub("\208\129", "\208\181"):gsub("\209\145", "\208\181"):lower())
end

-- Original scenario events, with 3.3.5 combat detection supplied by Dungeon.lua.
function ns.NewDungeonSession(data, saved, now, fresh)
    saved = saved or {}
    local previousDone = saved.done or next(saved.killed or {}) ~= nil
    if fresh or not saved.played or (saved.leftAt and now - saved.leftAt >= GAP)
        or (not saved.leftAt and now - (saved.t or now) >= GAP) then
        saved = { played = {}, killed = {}, pulled = {}, deaths = {}, base = {}, ready = {},
            runs = (saved.runs or 0) + 1, serial = (saved.serial or 0) + 1, done = previousDone,
            completedRuns = saved.completedRuns or 0 }
    end
    -- Upgrade the 0.10.58 pilot without forgetting its four victories.
    if saved.schema ~= 2 then
        local kills = {}
        for id, v in pairs(saved.killed) do kills[tonumber(id) or id] = v end
        saved.killed, saved.ready, saved.base = kills, {}, {}
        for _, e in ipairs(data.events) do
            if (e.trig == "prolog" or e.trig == "repeat") and saved.played.entry then saved.played[e.id] = true end
            if e.trig == "kill" and saved.played["win:" .. tostring(e.enc)] then saved.played[e.id] = true end
        end
        saved.schema = 2
    end
    saved.leftAt, saved.t = nil, now
    local s = { data = data, saved = saved, active = {}, byID = {}, byNpc = {}, now = now }
    for _, e in ipairs(data.events) do s.byID[e.id] = e end
    for _, b in ipairs(data.bosses) do for _, npc in ipairs(b.npcs) do s.byNpc[npc] = b end end
    local function Alive(e) return not e.enc or not saved.killed[e.enc] end
    local function HasQuest(e, ctx) return not e.q or (ctx.quests or {})[e.q] end
    local function Present(e, ctx)
        if e.trig == "bag" then return (ctx.items or {})[e.item] end
        for _, q in ipairs(e.quests or {}) do if (ctx.quests or {})[q] then return true end end
        return false
    end
    local function Any(list)
        for _, id in ipairs(list or {}) do if saved.killed[id] then return true end end
        return false
    end
    function s:Boss(npc) return self.byNpc[npc] end
    function s:Queue(e, priority)
        if saved.played[e.id] or saved.ready[e.id] then return end
        saved.sequence = (saved.sequence or 0) + 1
        saved.ready[e.id] = { at = self.now, sequence = priority or saved.sequence }
    end
    function s:Finish(id, ctx, dismiss)
        local parent = self.byID[id]
        local slot = saved.ready[id] and saved.ready[id].sequence or (saved.sequence or 0)
        saved.played[id], saved.ready[id] = true, nil
        if dismiss or not parent then return end
        local hooks = {}
        for _, e in ipairs(data.events) do
            local follow = e.trig == "follows" and e.follows == id and HasQuest(e, ctx)
            local prolog = (parent.trig == "prolog" or parent.trig == "repeat") and e.trig == "prologHook"
                and ((e.q and (ctx.quests or {})[e.q]) or (e.faction and e.faction == ctx.faction))
            if follow or prolog then hooks[#hooks + 1] = e end
        end
        table.sort(hooks, function(a, b) return (a.prio or 99) < (b.prio or 99) end)
        for i = 1, math.min(2, #hooks) do self:Queue(hooks[i], slot + i / 100) end
    end
    function s:Pull(npc, timestamp)
        self.now = timestamp or self.now
        local b = self:Boss(npc)
        if not b then return end
        self.active[b.id] = true
        if saved.killed[b.id] then return b, true end
        if not saved.pulled[b.id] then
            saved.pulled[b.id] = true
            if self.now - (self.lastPull or -100) >= 4 then
                self.lastPull = self.now
                for _, e in ipairs(data.events) do if e.trig == "start" and e.enc == b.id then self:Queue(e) end end
            end
        end
        return b, false
    end
    function s:Kill(npc, timestamp)
        self.now = timestamp or self.now
        local b = self:Boss(npc)
        if not b or not self.active[b.id] or saved.killed[b.id] then return end
        saved.deaths[npc] = true
        if b.required then for _, id in ipairs(b.required) do if not saved.deaths[id] then return end end end
        saved.killed[b.id], saved.done, self.active[b.id] = true, true, nil
        if not saved.counted then
            saved.counted = true
            saved.completedRuns = (saved.completedRuns or 0) + 1
        end
        for _, e in ipairs(data.events) do if e.trig == "kill" and e.enc == b.id then self:Queue(e) end end
        return b
    end
    function s:Calm()
        self.active = {}
        for _, b in ipairs(data.bosses) do
            if not saved.killed[b.id] then for _, npc in ipairs(b.npcs) do saved.deaths[npc] = nil end end
        end
    end
    function s:Observe(ctx)
        self.now = ctx.now
        if not saved.entrySelected then
            saved.entrySelected = true
            local trigger = saved.done and "repeat" or "prolog"
            for _, e in ipairs(data.events) do if e.trig == trigger then self:Queue(e) end end
        end
        local baseline = not saved.baseline
        saved.baseline = true
        for _, e in ipairs(data.events) do
            if e.trig == "bag" or e.trig == "qlog" then
                if baseline and Present(e, ctx) then saved.base[e.id] = true end
                if not saved.base[e.id] and Present(e, ctx) then self:Queue(e) end
            elseif e.trig == "sub" and Alive(e) and ns.DungeonAreaKey(ctx.subzone) == ns.DungeonAreaKey(e.sub) then
                self:Queue(e)
            elseif e.trig == "afterAll" and Alive(e) then
                local all = true
                for _, id in ipairs(e.encs or {}) do if not saved.killed[id] then all = false end end
                if all then self:Queue(e) end
            end
        end
        if (data.layout == "linear" or data.layout == "linear_with_side") and next(saved.killed) then
            for _, id in ipairs(data.order or {}) do
                if not saved.killed[id] then
                    for _, e in ipairs(data.events) do
                        if e.trig == "after" and e.enc == id then
                            local ahead = false
                            for _, p in ipairs(data.events) do
                                if p.trig == "sub" and p.role ~= "side" and p.role ~= "rare" and Alive(p)
                                    and not saved.played[p.id] and (p.pos or 0) < (e.pos or 0) then ahead = true end
                            end
                            if not ahead then self:Queue(e) end
                        end
                    end
                    break
                end
            end
        end
    end
    function s:IsValid(id, ctx)
        local e, waiting = self.byID[id], saved.ready[id]
        if not e or not waiting or saved.played[id] then return false end
        local elapsed = ctx.now - waiting.at
        if (e.trig == "prolog" or e.trig == "repeat") and elapsed < 3 then return false end
        if e.trig == "start" then
            return Alive(e) and self.active[e.enc] and elapsed >= 3 and elapsed < 12
        end
        if ctx.combat or elapsed >= 120 then return false end
        if e.k == "pod" and not Alive(e) then return false end
        if e.noKills and Any(e.noKills) then return false end
        if e.anyKill and not Any(e.anyKill) then return false end
        return true
    end
    function s:Scenes(ctx)
        self:Observe(ctx)
        local out = {}
        for id, waiting in pairs(saved.ready) do
            local e = self.byID[id]
            if self:IsValid(id, ctx) then
                out[#out + 1] = {key = id, event = e, track = e.track, combat = e.trig == "start",
                    boss = e.enc, sequence = waiting.sequence}
            elseif not e or ctx.now - waiting.at >= (e.trig == "start" and 12 or 120)
                or (e.k == "pod" and not Alive(e))
                or (e.trig == "kill" and not ctx.combat
                    and ((e.noKills and Any(e.noKills)) or (e.anyKill and not Any(e.anyKill)))) then
                saved.played[id], saved.ready[id] = true, nil
            end
        end
        table.sort(out, function(a, b) return a.sequence < b.sequence end)
        return out
    end
    return s
end

function ns.DungeonCreatureID(guid)
    if type(guid) ~= "string" then return end
    local hex = guid:match("^0[xX](%x+)$")
    if hex then
        local prefix = hex:sub(1, 3):upper()
        if prefix ~= "F13" and prefix ~= "F15" then return end
        return tonumber(hex:sub(7, 10), 16)
    end
    if guid:match("^Creature%-") or guid:match("^Vehicle%-") then
        return tonumber(guid:match("^[^%-]+%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)%-"))
    end
end
