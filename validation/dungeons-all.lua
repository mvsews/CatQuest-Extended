CatQuest335 = {}
dofile(ROOT .. "/CatQuest/DungeonData.lua")
dofile(ROOT .. "/CatQuest/DungeonSession.lua")
local ns = CatQuest335
local function ctx(now) return {now=now or 100, combat=false, quests={}, items={}, subzone="", faction="Horde"} end
local function has(scenes, id) for _, x in ipairs(scenes) do if x.key == id then return x end end end
local maps, battles, events, types = 0, 0, 0, {}
for map, data in pairs(ns.DungeonData) do
    maps = maps + 1
    local s, c, entry = ns.NewDungeonSession(data, nil, 100), ctx()
    s:Observe(c); c.now = 104
    for _, e in ipairs(data.events) do
        events = events + 1; types[e.trig] = true
        assert(e.track.hash:match("^%x%x%x%x%x%x%x%x$") and e.track.duration > 0 and #e.track.cues > 0)
        if e.trig == "prolog" then entry = e end
    end
    assert(has(s:Scenes(c), entry.id), data.name)
    s:Finish(entry.id, c)
    for _, b in ipairs(data.bosses) do
        battles = battles + 1
        assert(not s:Kill(b.npcs[1]))
        c.now, c.combat = c.now + 20, true
        local boss, reset = s:Pull(b.npcs[1], c.now)
        assert(boss == b and not reset)
        c.now = c.now + 4
        local pull
        for _, e in ipairs(data.events) do if e.trig == "start" and e.enc == b.id then pull = e end end
        if pull then
            assert(has(s:Scenes(c), pull.id), data.name .. ": " .. b.name)
            s:Finish(pull.id, c)
        end
        local credit
        for _, npc in ipairs(b.required or {b.npcs[1]}) do credit = s:Kill(npc, c.now) end
        assert(credit == b and s.saved.killed[b.id], data.name .. ": kill " .. b.name)
        assert(not s:Kill(b.npcs[1], c.now))
        c.combat, c.now = false, c.now + 6
        for _, scene in ipairs(s:Scenes(c)) do if scene.event.trig == "kill" then s:Finish(scene.key, c) end end
        s:Calm()
    end
    assert(s.saved.completedRuns == 1)
    local _, reset = s:Pull(data.bosses[1].npcs[1], c.now + 20); assert(reset)
    s.saved.t = c.now
    assert(ns.NewDungeonSession(data, s.saved, c.now + 10).saved == s.saved)
    s.saved.leftAt = c.now + 10
    local again = ns.NewDungeonSession(data, s.saved, c.now + 1810)
    local ac = ctx(c.now + 1810); again:Observe(ac); ac.now = ac.now + 4
    assert(again.saved.runs == 2 and again:Scenes(ac)[1].event.trig == "repeat")
    for _, e in ipairs(data.events) do
        if e.trig == "sub" then
            local sub, sc = ns.NewDungeonSession(data, nil, 100), ctx(104)
            sc.subzone = e.sub; assert(has(sub:Scenes(sc), e.id), e.id)
            for en, ru in pairs(ns.DungeonAreaAliases) do
                if ns.DungeonAreaKey(ru) == ns.DungeonAreaKey(e.sub) then
                    sc.subzone = en; assert(has(sub:Scenes(sc), e.id), en)
                end
            end
        elseif e.trig == "bag" or e.trig == "qlog" then
            local function present(c1) if e.item then c1.items[e.item]=true else c1.quests[e.quests[1]]=true end end
            local s1,c1 = ns.NewDungeonSession(data,nil,100),ctx()
            present(c1); s1:Observe(c1); assert(not has(s1:Scenes(c1),e.id), "baseline "..e.id)
            local s2,c2 = ns.NewDungeonSession(data,nil,100),ctx()
            s2:Observe(c2); present(c2); c2.now=104; assert(has(s2:Scenes(c2),e.id), "new "..e.id)
        end
    end
    -- Every parent queues exactly the eligible first two follow hooks.
    local parents = {}
    for _, e in ipairs(data.events) do if e.trig == "follows" then parents[e.follows] = true end end
    for parent in pairs(parents) do
        for _, withQuests in ipairs({false,true}) do
            local fs,fc = ns.NewDungeonSession(data,nil,100),ctx(104)
            local eligible = {}
            for _, e in ipairs(data.events) do
                if withQuests and e.q then fc.quests[e.q]=true end
                if e.trig=="follows" and e.follows==parent and (withQuests or not e.q) then eligible[#eligible+1]=e end
            end
            table.sort(eligible,function(a,b) return (a.prio or 99)<(b.prio or 99) end)
            fs:Finish(parent,fc)
            local got=0
            for _, e in ipairs(data.events) do
                if e.trig=="follows" and e.follows==parent and fs.saved.ready[e.id] then got=got+1 end
            end
            assert(got==math.min(2,#eligible),parent)
        end
    end
end
assert(maps==19 and battles==183 and events==670)
for _, k in ipairs({"prolog","repeat","prologHook","sub","start","kill","follows","after","afterAll","bag","qlog"}) do assert(types[k],k) end
for _, guard in ipairs({false,true}) do
    local s,c = ns.NewDungeonSession(ns.DungeonData[429],nil,100),ctx(110)
    s:Observe(c); if guard then s.saved.killed[362]=true end
    s:Pull(11501,111); s:Kill(11501,112); c.now=120
    assert((has(s:Scenes(c),"dm_dire_maul_gordok_tribute")~=nil)==not guard)
    assert((has(s:Scenes(c),"dm_dire_maul_gordok")~=nil)==guard)
end
local wc,c = ns.NewDungeonSession(ns.DungeonData[43],nil,100),ctx(104)
local prerequisite
for _,e in ipairs(wc.data.events) do if e.trig=="afterAll" then prerequisite=e end end
assert(not has(wc:Scenes(c),prerequisite.id))
for _,id in ipairs(prerequisite.encs) do wc.saved.killed[id]=true end
assert(has(wc:Scenes(c),prerequisite.id))
local s,c = ns.NewDungeonSession(ns.DungeonData[389],nil,100),ctx(104)
s:Observe(c)
for _,e in ipairs(s.data.events) do if e.q then c.quests[e.q]=true end end
s:Finish("dm_ragefire_prolog",c)
local n=0
for _,scene in ipairs(s:Scenes(c)) do if scene.event.trig=="prologHook" then n=n+1 end end
assert(n==2)
local uld=ns.NewDungeonSession(ns.DungeonData[70],nil,100)
uld:Pull(6906); assert(not uld:Kill(6906) and not uld:Kill(6907))
uld:Calm(); uld:Pull(6908); assert(not uld:Kill(6908) and not uld:Kill(6906)); assert(uld:Kill(6907))
local mines=ns.NewDungeonSession(ns.DungeonData[36],nil,100)
mines:Pull(642); assert(not mines:Kill(642) and mines:Kill(643))
local progression,pc=ns.NewDungeonSession(ns.DungeonData[389],nil,100),ctx(104)
assert(not has(progression:Scenes(pc),"dm_ragefire_bazzalan_intro"))
progression.saved.killed[2732]=true;progression.saved.killed[2733]=true;progression.saved.killed[2734]=true
assert(has(progression:Scenes(pc),"dm_ragefire_bazzalan_intro"))
local expired,ec=ns.NewDungeonSession(ns.DungeonData[389],nil,100),ctx(113)
expired:Pull(11517,100);ec.combat=true
assert(not has(expired:Scenes(ec),"dm_ragefire_oggleflint_pull"))
assert(ns.DungeonCreatureID("0xF13000439A000001")==17306)
assert(ns.DungeonCreatureID("Creature-0-1-543-1-17306-000001")==17306)
assert(not ns.DungeonCreatureID("0x000000439A000001"))

-- Runtime ownership and safety against stale narration.
local frames,now,wall,inside,dead,combat={},0,100,true,true,false
function CreateFrame()
    local f={events={}}
    function f:RegisterEvent(e) self.events[e]=true end
    function f:SetScript(k,v) self[k]=v end
    frames[#frames+1]=f; return f
end
function GetTime() return now end
function time() return wall end
function GetInstanceInfo() return "Ragefire","party",1,nil,nil,nil,nil,inside and 389 or 0 end
function UnitIsDeadOrGhost() return dead end
function UnitAffectingCombat() return combat end
function GetNumRaidMembers() return 0 end
function GetNumPartyMembers() return 0 end
function GetNumQuestLogEntries() return 0 end
function GetItemCount() return 0 end
function UnitFactionGroup() return "Horde" end
bit={band=function(a,b) return a%(b+1) end}
ns.db={enabled=true,dungeonMaster=true}; ns.state={queue={},pending={}}
ns.VoiceLocale=function() return "ruRU" end
ns.DropItem=function(k) if ns.state.active and ns.state.active.key==k then ns.state.active=nil end end
ns.ReportError=function(e) error(e) end; ns.Print=function() end
local spoken,item={},nil
ns.PlayItem=function(v) item=v; ns.state.active=v; spoken[#spoken+1]=v; return true end
dofile(ROOT .. "/CatQuest/Dungeon.lua")
local f=frames[#frames]
local function tick(n) for i=1,n or 1 do now=now+1;wall=wall+1;f.OnUpdate(f,1) end end
local function event(e,...) f.OnEvent(f,e,...) end
tick(5); assert(#spoken==0 and not ns.db.dungeonSessions)
dead=false;tick(5);assert(#spoken==1)
local old=item;inside=false;event("ZONE_CHANGED_NEW_AREA");assert(not old.valid() and not ns.state.active)
inside=true;tick(5);assert(#spoken==2);item.onFinish();ns.state.active=nil
combat=true
event("COMBAT_LOG_EVENT_UNFILTERED",wall,"SWING_DAMAGE","stranger","other",0,"0xF130002CFD000001","boss",0)
tick(4);assert(#spoken==2)
event("COMBAT_LOG_EVENT_UNFILTERED",wall,"SWING_DAMAGE","player","me",1,"0xF130002CFD000001","boss",0)
tick(4);assert(#spoken==3 and item.text==ns.DungeonData[389].events[6].track.text)
assert(item.npc and item.npc.id==11517 and #item.npc.ids>0 and item.npc.name)
dead=true;event("PLAYER_DEAD");tick();assert(not item.valid() and not ns.state.active)
dead=false;combat=false;tick();ns.DungeonStop();tick(3);assert(not ns.state.active)
event("CINEMATIC_START");tick();event("CINEMATIC_STOP");inside=false;event("ZONE_CHANGED_NEW_AREA")
assert(not ns.state.active)
inside=true;tick(5)
if ns.state.active then item.onFinish();ns.state.active=nil end
local before=#spoken
ns.state.active={key="quest",kind="quest"};combat=true
local guid=string.format("0xF130%06X000001",11520)
event("COMBAT_LOG_EVENT_UNFILTERED",wall,"SWING_DAMAGE","player","me",1,guid,"boss",0)
tick(14);assert(#spoken==before)
ns.state.active=nil;tick();assert(#spoken==before) -- A stale pull must not follow a long quest.
event("COMBAT_LOG_EVENT_UNFILTERED",wall,"UNIT_DIED",nil,nil,0,guid,"boss",0)
combat=false;tick(6);assert(#spoken==before+1 and item.kind=="dungeon")
print("19 maps / 183 encounters / 670 events: all trigger types, sessions, compound kills, tribute, quests, subzones, lifecycle OK")
