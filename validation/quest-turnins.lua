local function object(name)
    local v={scripts={},shown=false,text=''}
    function v:SetScript(k,fn)self.scripts[k]=fn end
    function v:CreateFontString()return object()end
    function v:CreateTexture()return object()end
    function v:SetText(text)self.text=text end
    function v:Show()self.shown=true end
    function v:Hide()self.shown=false end
    function v:IsShown()return self.shown end
    setmetatable(v,{__index=function(_,k)if k:match('^[A-Z]')then return function()end end end})
    if name then _G[name]=v end
    return v
end
function CreateFrame(_,name)return object(name)end
local now,dialog=1000,{}
local played,music,cvars={},{},{Sound_EnableMusic='1',Sound_MusicVolume='0.4',Sound_EnableSFX='1'}
local hooks={}
function GetTime()return now end
function time()return math.floor(now)end
function GetQuestID()return dialog.id end
function GetTitleText()return dialog.title end
function GetRewardText()return dialog.text end
function GetQuestText()return dialog.text end
function GetNumQuestLogEntries()return 0 end
function GetCVar(k)return cvars[k] or '1' end
function SetCVar(k,v)cvars[k]=tostring(v)end
function PlaySoundFile(path,channel)played[#played+1]={path=path,channel=channel};return true end
function PlayMusic(path)music[#music+1]=path end
function StopMusic()end
function GetQuestReward()end
function hooksecurefunc(name,fn)
    hooks[name]=hooks[name] or {};table.insert(hooks[name],fn)
end
SlashCmdList={};DEFAULT_CHAT_FRAME={AddMessage=function()end}
CatQuest335={L=setmetatable({QUEST_N='Quest %s'},{__index=function(_,k)return k end}),
    VoiceLocale=function()return 'ruRU' end,ClientLocale=function()return 'ruRU' end}
dofile(ROOT..'/CatQuest/Scheduler.lua')
dofile(ROOT..'/CatQuest/Core.lua')
dofile(ROOT..'/CatQuest/QuestRatings.lua')
local ns=CatQuest335
ns.Print=function()end
ns.db.auto=true;ns.db.turnin=true;ns.db.greetDelay=true;ns.db.queue=true;ns.db.stopOnClose=false;ns.db.trackGap=0
CatQuest335_BridgeReady={locale='ruRU',q={[110]=3,[111]=3,[112]=3},d={[110]={10,12},[111]={10,14},[112]={10,16}}}
local function event(name)CatQuest335Events.scripts.OnEvent(nil,name)end
local function tick(dt)now=now+dt;CatQuest335Scheduler.scripts.OnUpdate(nil,dt)end
local function show(id)
    dialog={id=id,title='Turn-in '..id,text='Completion text '..id}
    event('QUEST_PROGRESS');event('QUEST_COMPLETE')
end
local function claim()
    local completed=dialog.id
    event('QUEST_FINISHED');dialog={}
    for _,fn in ipairs(hooks.GetQuestReward or {})do fn()end
    ns.CheckQuestRatingCompletion({[completed]=true})
end

-- Two hand-ins inside the NPC greeting delay must retain the first line and
-- its captured text/title, even though the quest window has moved on.
show(110);claim();tick(0.1);show(111);claim()
tick(1.5)
assert(ns.state.active and ns.state.active.questID==110,'First completion was cancelled by the second reward dialog')
assert(ns.state.active.title=='Turn-in 110' and ns.state.active.text=='Completion text 110')
assert(#ns.state.queue==1 and ns.state.queue[1].questID==111)
tick(12.2);tick(0)
assert(ns.state.active and ns.state.active.questID==111)
tick(14.2);tick(0);assert(not ns.state.active and #ns.state.queue==0)
print('Consecutive turn-ins: greeting delay, immutable text/title and FIFO passed')

local function reset(channel,queue,stopOnClose)
    ns.Stop(true);tick(0.2);now=now+10
    played={};music={};dialog={}
    ns.state.lastRequestKey=nil;ns.state.dialogEventKey=nil;ns.state.recentAutoQuest=nil;ns.state.dialogKey=nil
    ns.db.volumeChannel=channel;ns.db.queue=queue;ns.db.stopOnClose=stopOnClose
end
local function voices()
    local count=0
    for _,item in ipairs(played)do if item.path:find('_t%.ogg$')then count=count+1 end end
    for _,path in ipairs(music)do if path:find('_t%.ogg$')then count=count+1 end end
    return count
end
for _,channel in ipairs({'SFX','Music'})do
for _,queueEnabled in ipairs({true,false})do
for _,stopOnClose in ipairs({true,false})do
    reset(channel,queueEnabled,stopOnClose)
    show(110);event('QUEST_COMPLETE');claim();tick(0.1);show(111);claim();show(112);claim()
    assert(voices()==0,'Greeting delay must not let a later line jump ahead')
    tick(1.5)
    assert(ns.state.active.questID==110 and #ns.state.queue==2 and voices()==1)
    -- A new NPC greeting/description must wait behind committed endings even
    -- with the ordinary dialogue queue disabled.
    ns.PlayItem({key='greeting-test',kind='gossip',questID=0,file='greeting.ogg',duration=5,cues={}},false)
    assert(ns.state.active.questID==110 and #ns.state.queue==3)
    tick(12.2);tick(0);assert(ns.state.active.questID==111 and voices()==2)
    tick(14.2);tick(0);assert(ns.state.active.questID==112 and voices()==3)
    tick(16.2);tick(0);assert(ns.state.active.key=='greeting-test')
    tick(5.2);tick(0);assert(not ns.state.active and #ns.state.queue==0)
end
end
end

-- Stop still cancels the greeting wait; later timer ticks cannot revive it.
reset('SFX',true,false);show(110);ns.Stop(true);tick(3)
assert(not ns.state.active and #ns.state.queue==0 and voices()==0)
-- Closing a preview without claiming the reward retains stop-on-close.
reset('SFX',true,true);show(110);event('QUEST_FINISHED');dialog={};tick(2)
assert(not ns.state.active and #ns.state.queue==0 and voices()==0)

-- A missing first file retains ownership and later endings stay in FIFO.
-- Use the explicit playback API here: the event fixture above also exercises
-- stop-on-close and reward hooks, while this block isolates scheduler order.
reset('SFX',true,false)
local ready=false
function PlaySoundFile(path,channel)
    played[#played+1]={path=path,channel=channel}
    return (ready or path:find('111_t%.ogg')) and not path:find('poll')
end
assert(ns.PlayQuest(110,'turnin',true,'Completion text 110','Turn-in 110',1))
assert(ns.PlayQuest(111,'turnin',true,'Completion text 111','Turn-in 111',1))
assert(ns.PlayQuest(112,'turnin',true,'Completion text 112','Turn-in 112',1))
assert(ns.state.active and ns.state.active.questID==111
    and #ns.state.pending==1 and ns.state.pending[1].questID==110 and #ns.state.queue==1)
ready=true;tick(1.1)
assert(ns.state.active.questID==111 and #ns.state.pending==1)
tick(15);tick(0);assert(ns.state.active.questID==110 and #ns.state.pending==0 and #ns.state.queue==1)
tick(13);tick(0);assert(ns.state.active.questID==112)
print('Turn-in regressions: both channels, queue on/off, close on/off, committed versus cancelled rewards, loading, greetings and Stop passed')
reset('SFX',true,false)
dialog={id=110,title='Old description',text='Old intro'};event('QUEST_DETAIL')
show(110);claim();tick(2)
assert(ns.state.active.kind=='turnin' and #ns.state.queue==0,'Obsolete intro timer survived reward dialog')
reset('SFX',true,false)
dialog={id=110,title='Description',text='Intro'};event('QUEST_DETAIL')
ns.Stop(true);tick(3)
assert(not ns.state.active and #ns.state.queue==0,'Description timer revived after Stop')

-- Restore a normal local read after the missing-file scheduler scenario.
function PlaySoundFile(path,channel)
    played[#played+1]={path=path,channel=channel}
    return true
end

-- A greeting may still be transferring marker frames when the player selects
-- a quest. Its late callback must not insert an obsolete automatic line.
reset('SFX',true,false)
assert(ns.PlayGossipText('An automatic greeting','NPC',{id=10,gender='male'},true))
show(110);claim()
for _=1,25 do tick(.2) end
assert(ns.state.active and ns.state.active.questID==110)
assert(#ns.state.queue==0 and #ns.state.pending==0,'A late automatic greeting survived the quest transition')

-- Explicit Read is different: the player asked for it, so keep it behind the
-- committed completion even when its marker transfer ends later.
reset('SFX',true,false)
assert(ns.PlayGossipText('An explicit greeting','NPC',{id=10,gender='male'},false))
show(110);claim()
for _=1,25 do tick(.2) end
assert(ns.state.active and ns.state.active.questID==110)
assert(#ns.state.queue==1 and ns.state.queue[1].kind=='gossip' and not ns.state.queue[1].autoGossip)

-- A greeting already waiting for generation must not hold a selected quest
-- hostage for pendingTimeout seconds.
reset('SFX',true,false)
function PlaySoundFile(path,channel)
 played[#played+1]={path=path,channel=channel}
 return not path:find('gossip')
end
ns.PlayItem({key='auto-greeting-pending',kind='gossip',questID=0,remote=true,
 file='Interface\\AddOns\\CatQuest335_ServerVoices\\gossip\\1.ogg',duration=10,cues={},autoGossip=true},false)
assert(#ns.state.pending==1 and not ns.state.active)
show(110);claim();tick(1.6)
assert(ns.state.active and ns.state.active.questID==110 and #ns.state.pending==0)
print('Greeting regressions: late automatic transfer cancelled, explicit Read retained, pending greeting yields to quests')

-- A first greeting that actually started finishes once before the selected
-- quest. Only obsolete transfers/waiting greetings are cancelled.
reset('SFX',true,false)
ns.PlayItem({key='started-greeting',kind='gossip',questID=0,file='intro.ogg',
 duration=5,cues={},autoGossip=true,gossipHeardKey='10:ruRU:0000000000000001'},false)
show(110);claim()
assert(ns.state.active.key=='started-greeting' and #ns.state.queue==1)
tick(5.2);tick(0)
assert(ns.db.gossipHeard['10:ruRU:0000000000000001'])
assert(ns.state.active.questID==110)
print('First greeting: completes once and the queued quest follows')
