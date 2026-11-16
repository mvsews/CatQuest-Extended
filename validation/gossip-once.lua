local now,player,locale=1000,'Alpha','ruRU'
local sent=0
local function frame(name)
 local f={scripts={}}
 function f:SetScript(k,fn)self.scripts[k]=fn end
 setmetatable(f,{__index=function()return function()end end})
 if name then _G[name]=f end
 return f
end
function CreateFrame(_,name)return frame(name)end
function GetTime()return now end
function time()return math.floor(now)end
function UnitName(unit)return unit=='player' and player or 'NPC'end
function UnitClass()return 'Mage','MAGE'end
function GetCVar()return '1'end
function SetCVar()end
function GetNumQuestLogEntries()return 0 end
function PlaySoundFile()return true end
SlashCmdList={};DEFAULT_CHAT_FRAME={AddMessage=function()end}
CatQuest335={L=setmetatable({QUEST_N='Quest %s'},{__index=function(_,k)return k end}),
 VoiceLocale=function()return locale end,ClientLocale=function()return locale end}
CatQuest335Companion={Send=function()sent=sent+1;return true end,Stop=function()end}
CatQuest335_CompanionReady=true
CatQuest335_BridgeReady={mode='local',locale='ruRU',q={}}
dofile(ROOT..'/CatQuest/Scheduler.lua');dofile(ROOT..'/CatQuest/GossipText.lua');dofile(ROOT..'/CatQuest/Core.lua')
local ns=CatQuest335;ns.db.trackGap=0
local npc={id=22292,name='NPC',gender='male'}
local function tick(dt)now=now+dt;ns.OnUpdate()end
local function finish()local duration=ns.state.active.duration;tick(duration+1);tick(0)end
assert(ns.PlayGossipText('Greetings, Alpha, mage!','NPC',npc,true))
local key=ns.state.active.gossipHeardKey
assert(key and not ns.db.gossipHeard[key])
assert(not ns.PlayGossipText('Greetings, Alpha, mage!','NPC',npc,true) and sent==1)
ns.Stop(true);tick(3)
assert(not ns.db.gossipHeard[key],'Interrupted dialogue must not be counted as heard')
assert(ns.PlayGossipText('Greetings, Alpha, mage!','NPC',npc,true));finish()
assert(ns.db.gossipHeard[key] and sent==2)
player='Beta'
assert(not ns.PlayGossipText('Greetings, Beta, mage!','NPC',npc,true) and sent==2,'Character name/class must not create a new paragraph')
assert(ns.PlayGossipText('Greetings, Beta, mage!','NPC',npc,false),'Explicit Read must remain available');finish()
assert(sent==3)
assert(ns.PlayGossipText('A new paragraph about the Scourge.','NPC',npc,true));finish()
assert(sent==4,'New paragraph at the same NPC must play once')
assert(ns.PlayGossipText('Greetings, Beta, mage!','Other NPC',{id=22293,name='Other NPC',gender='male'},true));finish()
assert(sent==5,'Same text from a different NPC has its own history')
locale='enUS'
assert(ns.PlayGossipText('Greetings, Beta, mage!','NPC',npc,true));finish()
assert(sent==6,'Voice language has a separate history')
-- Simulate a browser F5 that loses SavedVariables: extension restores only
-- confirmed completed keys through Bridge.lua before Core loads.
locale='ruRU';CatQuest335DB={};CatQuest335_BridgeGossipHeard={[key]=true}
dofile(ROOT..'/CatQuest/Core.lua');ns=CatQuest335
assert(not ns.PlayGossipText('Greetings, Beta, mage!','NPC',npc,true) and sent==6)
assert(ns.PlayGossipText('An authored NPC history.','NPC',npc,true,'npcLore',22292));finish()
assert(sent==7,'NPC lore uses its existing policy and must not be classified as a greeting')
print('Gossip once: completed only, Stop, return visit, manual Read, new text/NPC/locale, universal names and F5 restore passed')
