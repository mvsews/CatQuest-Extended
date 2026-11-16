local frames = {}
local function object(name)
    local v = {points={}, scripts={}, text="", shown=false}
    function v:SetPoint(...) self.points[#self.points+1]={...} end
    function v:SetScript(key, fn) self.scripts[key]=fn end
    function v:SetText(text) self.text=text end
    function v:SetWidth(width) self.width=width end
    function v:SetHeight(height) self.height=height end
    function v:SetChecked() end
    function v:SetJustifyH() end
    function v:SetTextColor() end
    function v:CreateFontString() return object() end
    function v:RegisterEvent() end
    function v:Enable() self.enabled=true end
    function v:Disable() self.enabled=false end
    function v:Hide() self.shown=false end
    function v:Show() self.shown=true end
    function v:IsShown() return self.shown end
    setmetatable(v,{__index=function() return function() end end})
    if name then _G[name]=v end
    frames[#frames+1]=v
    return v
end
function CreateFrame(_,name) return object(name) end
function GetTime() return 100 end
function UnitSex() return 2 end
function UnitRace() return "Human","Human" end
function UnitClass() return "Mage","MAGE" end
function UnitFactionGroup() return "Alliance" end
function UnitLevel() return 70 end
function GetNumQuestLogEntries() return 0 end
SlashCmdList={}
DEFAULT_CHAT_FRAME={AddMessage=function() end}
local locale="ruRU"
CatQuest335={L=setmetatable({QUEST_N="Quest %s",STORY_LEVEL="level %d",STORY_PROGRESS="%d/%d",STORY_NEXT="Next: %s"},
    {__index=function(_,k) return k end}),VoiceLocale=function() return locale end,
    ClientLocale=function() return "ruRU" end,After=function() end}
dofile(ROOT.."/CatQuest/Core.lua")
local ns=CatQuest335
local actualPlayQuest=ns.PlayQuest
CatQuest335QuestGiver={[9923]=1,[9924]=2}
-- No static Codex recording is required for online TBC and non-Russian tracks.
assert(ns.CanPlayQuest(9923))
locale="enUS";assert(ns.CanPlayQuest(9923));locale="ruRU"
ns.db.remoteEnabled=false;assert(not ns.CanPlayQuest(9923))
CatQuestExtendedVoicePack={quests={[9923]={d=.1,c={x={}}}}}
assert(not ns.CanPlayQuest(9923)) -- Placeholder must not masquerade as real audio.
CatQuestExtendedVoicePack.quests[9923]={d=15,c={x={{0,"recorded"}}}}
assert(ns.CanPlayQuest(9923))
ns.db.remoteEnabled=true
CatQuest335_BridgeReady={mode="local",locale="ruRU",q={[9924]=1}}
assert(ns.CanPlayQuest(9924) and not ns.CanPlayQuest(9954))
assert(not ns.CanPlayQuest(9924,"turnin"))
CatQuest335_BridgeReady.q[9924]=3;assert(ns.CanPlayQuest(9924,"turnin"))
CatQuest335_LocalMode=true;assert(not ns.CanPlayQuest(9924));CatQuest335_LocalMode=nil
CatQuest335_BridgeReady=nil

CatQuest335Story={maps={},zones={[3518]={{l=64,q={9923,9924,9954,9955}}}},races={},classes={},voiced={}}
CatQuest335StoryTitles={[9923]="HELP!",[9924]="Continuation"}
CatQuest335QuestGuide={zones={[3518]={score=62,quests={9923}}}}
ns.completedQuests={[9923]=true,[9924]=true}
local queued={}
ns.PlayQuest=function(id,kind,force,text,title,npc)
    queued[#queued+1]={id=id,npc=npc}
    return true
end
ns.Print=function() end
dofile(ROOT.."/CatQuest/Story.lua")
local entry=ns.StoryChapters(3518)[1]
assert(entry.done==2 and entry.total==4 and ns.StoryCanListen(entry))
assert(ns.StoryListen(entry)==2 and #queued==2)
assert(queued[1].id==9923 and queued[2].id==9924 and queued[1].npc==1 and queued[2].npc==2)
locale="enUS";assert(ns.StoryCanListen(entry));locale="ruRU"
ns.db.remoteEnabled=false
assert(ns.StoryListen(entry)==1) -- Only the installed recording remains available.
CatQuestExtendedVoicePack=nil;assert(not ns.StoryCanListen(entry))
ns.db.remoteEnabled=true;ns.completedQuests={};assert(not ns.StoryCanListen(entry))
ns.completedQuests={[9923]=true,[9924]=true}
local frame=CatQuest335StoryFrame
frame.shown=true;frame.zone=3518;frame.zoneName="Nagrand";ns.StoryRefresh()
local row=frame.rows[1]
assert(row.count.text=="2/4" and row.listen.enabled)
assert(row.score.text=="62/100" and not row.score.text:find("[^%d/]"))
assert(row.count.width==38 and row.score.points[1][4]>=row.count.width)
assert(row.score.points[1][4]+row.score.width<=row.name.points[1][4])
print("Story: Nagrand replay, partial progress, online/local/language modes, placeholders and rating columns passed")
ns.PlayQuest=actualPlayQuest
dofile(ROOT.."/validation/voice-queue.lua")
