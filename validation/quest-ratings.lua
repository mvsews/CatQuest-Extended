local function object(name)
    local v={scripts={},shown=false,text=""}
    function v:SetScript(k,fn) self.scripts[k]=fn end
    function v:SetText(text) self.text=text end
    function v:SetWidth(value) self.width=value end
    function v:SetHeight(value) self.height=value end
    function v:SetPoint(...) self.point={...} end
    function v:SetTexture(value) self.texture=value end
    function v:CreateTexture() return object() end
    function v:CreateFontString() return object() end
    function v:Show() self.shown=true end
    function v:Hide() self.shown=false end
    function v:IsShown() return self.shown end
    setmetatable(v,{__index=function(_,k) if k:match("^[A-Z]") then return function() end end end})
    if name then _G[name]=v end
    return v
end
function CreateFrame(_,name) return object(name) end
local now,combat,dead=1000,false,false
local log,completed,dialog,timers,hooks={},{},{},{},{}
function GetTime() return now end
function time() return now end
function GetNumQuestLogEntries() return #log end
function GetQuestLogTitle(i) return "Quest "..log[i],65,nil,0,nil,nil,1,nil,log[i] end
local selected=0
function GetQuestLogSelection() return selected end
function SelectQuestLogEntry(i) selected=i end
function GetQuestLogQuestText() return "Description", "Objective from log for quest "..log[selected] end
function GetQuestID() return dialog.id end
function GetTitleText() return dialog.title end
function GetObjectiveText() return dialog.objective end
function UnitAffectingCombat() return combat end
function UnitIsDeadOrGhost() return dead end
function GetQuestsCompleted(out) for id in pairs(completed) do out[id]=true end end
local queried=0
function QueryQuestsCompleted() queried=queried+1 end
function GetQuestReward() end
function AbandonQuest() end
function hooksecurefunc(name,fn) hooks[name]=fn end
function PlaySoundFile() return true end
SlashCmdList={};DEFAULT_CHAT_FRAME={AddMessage=function() end}
CatQuest335={L=setmetatable({QUEST_N="Quest %s",RATE_CURRENT="Current %s",RATE_OBJECTIVE="Objective: %s"},{__index=function(_,k)return k end}),
    ClientLocale=function()return "ruRU" end,VoiceLocale=function()return "ruRU" end,
    VOICE_LOCALES={"ruRU"},After=function(delay,fn) timers[#timers+1]={at=now+delay,fn=fn} end}
CatQuest335DB={questRatings=false}
CatQuest335_BridgeSettings={questRatings=true}
dofile(ROOT.."/CatQuest/Core.lua")
local ns=CatQuest335
assert(ns.db.questRatings==true) -- Browser opt-out/opt-in beats stale SavedVariables.
ns.Print=function() end
ns.db.questVotePending={[902]=-1}
CatQuest335_BridgeQuestVotes={[901]=1,[902]=1}
dofile(ROOT.."/CatQuest/Feedback.lua")
dofile(ROOT.."/CatQuest/QuestRatings.lua")
assert(ns.db.questVotes[901]==1 and ns.db.questVotePending[902]==-1)
local frame,events=CatQuest335QuestRating,CatQuest335QuestRatingEvents
local sent={}
local actualSend=ns.SendMessageBytes
ns.SendMessageBytes=function(kind,payload) sent[#sent+1]={kind=kind,payload=payload};return true end
local function event(name) events.scripts.OnEvent(events,name) end
local function tick(seconds)
    now=now+(seconds or 1)
    local due=timers;timers={}
    for _,item in ipairs(due) do if item.at<=now then item.fn() else timers[#timers+1]=item end end
    events.scripts.OnUpdate(events,seconds or 1)
end
local function reward(id,inLog)
    dialog={id=id,title="Quest "..id,objective="Find relic for quest "..id};log=inLog==false and {} or {id}
    event("QUEST_COMPLETE")
end
local function claim()
    dialog={} -- GetQuestID is already gone when the secure post-hook runs.
    event("QUEST_FINISHED")
    hooks.GetQuestReward()
end

-- Reward screen/open/close is not a completion. A rejected claim and an
-- abandoned quest must also produce no rating window.
reward(10);event("QUEST_FINISHED");tick();assert(not frame:IsShown())
reward(11);claim();tick();assert(not frame:IsShown())
hooks.AbandonQuest();log={};event("QUEST_LOG_UPDATE");tick();assert(not frame:IsShown())

reward(12);claim();log={};event("QUEST_LOG_UPDATE")
assert(frame:IsShown() and frame.item.id==12 and frame.quest.text=="Quest 12")
assert(frame.item.objective=='Objective from log for quest 12')
assert(frame.objective.text:find('Objective from log for quest 12',1,true))
frame.up.scripts.OnClick()
assert(ns.db.questVotes[12]==1 and ns.db.questVotePending[12]==1 and not frame:IsShown())
assert(sent[#sent].kind==6 and sent[#sent].payload[4]==12 and sent[#sent].payload[5]==1)
assert(not ns.SubmitQuestVote(-1)) -- Double click cannot vote for another quest.
event("QUEST_LOG_UPDATE");tick();assert(not frame:IsShown())

-- Independent buttons: a voice complaint must not become a quest vote or
-- refer to another quest that happens to be playing.
ns.OpenQuestRating(12,"Quest 12")
ns.state.active={kind="quest",questID=99,title="Unrelated"}
local before=#sent
frame.report.scripts.OnClick()
assert(CatQuest335Feedback.item.questID==12 and CatQuest335Feedback.item.kind=="turnin")
assert(#sent==before and ns.db.questVotes[12]==1)
CatQuest335Feedback:Hide()
frame.down.scripts.OnClick();assert(ns.db.questVotes[12]==-1 and sent[#sent].payload[5]==2)
tick()

-- Several rapid hand-ins preserve their IDs and do not overwrite the
-- currently visible quest. Closing is a skip, not an implicit dislike.
reward(20);claim();log={};event("QUEST_LOG_UPDATE")
reward(21);claim();log={};event("QUEST_LOG_UPDATE")
assert(frame.item.id==20)
frame.close.scripts.OnClick();assert(not ns.db.questVotes[20])
tick(0.1);assert(not frame:IsShown())
tick(0.5);assert(frame.item.id==21)
frame.up.scripts.OnClick();tick()

-- Quests not present in the log wait for the completed-quest server reply.
reward(30,false);claim();tick();assert(not frame:IsShown() and queried>0)
completed[30]=true;event("QUEST_QUERY_COMPLETE");assert(frame.item.id==30)
frame.close.scripts.OnClick();tick()
completed[31]=true;reward(31,false);claim();event("QUEST_QUERY_COMPLETE");tick()
assert(not frame:IsShown()) -- Existing completed list must not prompt old quests.

-- The setting suppresses automatic prompts; explicit review still works.
ns.SetQuestRatingPrompts(false)
assert(sent[#sent].kind==5)
reward(40);claim();log={};event("QUEST_LOG_UPDATE");tick();assert(not frame:IsShown())
ns.OpenQuestRating(12);tick();assert(frame:IsShown() and frame.item.id==12)
frame.close.scripts.OnClick();ns.db.questRatings=true;tick()

combat=true;reward(50);claim();log={};event("QUEST_LOG_UPDATE");tick();assert(not frame:IsShown())
combat=false;tick();assert(frame.item.id==50);frame.close.scripts.OnClick();tick()

reward(60);claim();tick(61);log={};event("QUEST_LOG_UPDATE");tick();assert(not frame:IsShown())
-- Explicit quest votes are independent of server voice enablement.
ns.db.remoteEnabled=false;CatQuest335_BridgeReady={locale="ruRU",q={}}
assert(actualSend(6,ns.QuestVoteBytes(12,1)))
assert(not ns.QuestVoteBytes(0,1) and not ns.QuestVoteBytes(12,0))
-- The pending click retains its original actor across a later character
-- switch/retry. The packet is self-contained and does not use global last-who.
local actor={realm='Длинное имя сервера для проверки',name='Первыйгерой',guid='0x000000000000002A'}
local bytes=ns.QuestVoteBytes(12,1,{id='1234567890abcdef',at=1794550000,character=actor})
assert(#bytes>69 and #bytes<253 and bytes[7]==0x12 and bytes[14]==0xef)
assert(actualSend(6,bytes))
local legacy=ns.QuestVoteBytes(12,1);assert(#legacy==6)
print("Quest rating UI: confirmed hand-ins, rejected/abandoned/instant quests, duplicates, queue, thumbs, complaints, opt-out, manual changes and voice-off transport passed")
