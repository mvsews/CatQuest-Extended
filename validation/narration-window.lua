local function object(name)
    local v={scripts={},shown=false,text=""}
    function v:SetScript(k,fn) self.scripts[k]=fn end
    function v:SetText(text) self.text=text end
    function v:GetText() return self.text end
    function v:SetTexture(texture) self.texture=texture;self.unit=nil end
    function v:SetHeight(height) self.height=height end
    function v:SetScale(scale) self.scale=scale end
    function v:GetStringWidth() return #self.text*5 end
    function v:GetStringHeight() return 16 end
    function v:Show() self.shown=true end
    function v:Hide() self.shown=false end
    function v:IsShown() return self.shown end
    function v:CreateTexture() return object() end
    function v:CreateFontString() return object() end
    setmetatable(v,{__index=function(_,key)
        if key:match("^[A-Z]") then return function() end end
    end})
    if name then _G[name]=v end
    return v
end
function CreateFrame(_,name) return object(name) end
local now=1000
function GetTime() return now end
function time() return now end
function UnitSex() return 2 end
function UnitRace() return "Human","Human" end
function UnitClass() return "Mage","MAGE" end
function UnitFactionGroup() return "Alliance" end
function GetNumQuestLogEntries() return 0 end
function GetNumRaidMembers() return 0 end
function GetNumPartyMembers() return 1 end
local units={}
function UnitExists(unit) return units[unit]~=nil end
function UnitCreatureID(unit) return units[unit] and units[unit].id end
function UnitGUID(unit) return units[unit] and units[unit].guid end
function UnitName(unit) return units[unit] and units[unit].name end
function SetPortraitTexture(texture,unit) texture.unit=unit;texture.texture="portrait:"..unit end
local available=true
function PlaySoundFile() return available end
SlashCmdList={}
DEFAULT_CHAT_FRAME={AddMessage=function() end}
local timers={}
CatQuest335={L=setmetatable({QUEST_N="Quest %s"},{__index=function(_,k) return k end}),
    VoiceLocale=function() return "ruRU" end,
    ClientLocale=function() return "ruRU" end,
    After=function(_,fn) timers[#timers+1]=fn end}
dofile(ROOT.."/CatQuest/Core.lua")
dofile(ROOT.."/CatQuest/UI.lua")
local ns,head=CatQuest335,CatQuest335TalkingHead
-- This fixture uses PlaySoundFile's missing-file result to model loading.
ns.db.volumeChannel="SFX"
CatQuest335_BridgeReady={locale="ruRU",q={}}
ns.db.head=false;ns.db.compact=true;ns.db.showSubtitle=false;ns.db.scale=1.2
local function npc() return {id=18411,name="Дурн Ненасытный",guid="durn"} end
local function lore()
    return ns.BuildGossipItem("История Дурна. Он обитает в Награнде.","История: Дурн",1,npc(),"npcLore",18411)
end
local function reset()
    ns.Stop(true);now=now+1000;ns.state.lastRequestKey=nil;timers={};available=true;units={}
end

-- World boss lore always exposes its text and Stop, even with the generic
-- quest head/subtitles disabled and compact layout enabled.
units.target=npc()
assert(ns.PlayItem(lore(),true))
assert(head:IsShown() and head.height==136 and head.scale==1.2 and head.subtitle:IsShown())
assert(head.title.text=="Дурн Ненасытный" and head.subtitle.text:find("История Дурна"))
assert(head.portrait.unit=="target" and ns.state.demandShown.kind=="npcLore")
assert(ns.db.head==false and ns.db.compact==true and ns.db.showSubtitle==false)
ns.state.queue={{key="next"}}
head.stopButton.scripts.OnClick()
assert(not head:IsShown() and not ns.state.active and #ns.state.queue==0 and #ns.state.pending==0)
assert(head.height==76 and not head.subtitle:IsShown())

-- The current target may be unrelated by the time a queued history starts.
-- Use the boss in focus/a group member's target, or a boss icon when absent.
for _,unit in ipairs({"focus","party1target"}) do
    reset();units.target={id=1,name="Unrelated",guid="other"};units[unit]=npc()
    assert(ns.PlayItem(lore(),true))
    assert(head.portrait.unit==unit and head.title.text=="Дурн Ненасытный")
end
reset();units.target={id=18411,name="Different spawn",guid="other"}
assert(ns.PlayItem(lore(),true))
assert(not head.portrait.unit and head.portrait.texture:find("Head_Dragon"))
assert(head.title.text=="Дурн Ненасытный")

-- The loading state also stays visible, with the boss's actual text.
reset();available=false;units.mouseover=npc()
assert(ns.PlayItem(lore(),true))
assert(head:IsShown() and head.height==136 and head.subtitle.text:find("История Дурна"))
assert(head.portrait.unit=="mouseover" and #ns.state.pending==1)
head.stopButton.scripts.OnClick()
assert(not head:IsShown() and #ns.state.pending==0)

-- Dungeon encounters carry all NPC identities for compound bosses, and a
-- unit's localized name wins over the source encounter's English name.
reset();units.focus={id=17308,name="Омор Неодолимый",guid="omor"}
local dungeon={key="dungeon:test",questID=0,kind="dungeon",title="Hellfire Ramparts",
    npc={id=17306,ids={17306,17308},name="Encounter"},file="test.ogg",duration=10,
    text="История босса",cues={{0,"История босса"}}}
assert(ns.PlayItem(dungeon,true))
assert(head:IsShown() and head.title.text=="Омор Неодолимый" and head.portrait.unit=="focus")
assert(head.subtitle.text=="История босса")

-- Normal quest settings recover after the narration; no DB settings change.
reset()
ns.ShowHead({kind="quest",questID=1,title="Quest",duration=10,text="Quest text"})
assert(not head:IsShown() and head.height==76 and head.subtitle.text=="")

-- Stop while a world-boss request is still transmitting marker files must
-- also prevent its delayed callback from opening a new voice/window.
reset()
assert(ns.PlayGossipText("История Дурна.","Дурн",npc(),true,"npcLore",18411))
assert(#timers>0)
ns.Stop(true)
local n=0
while #timers>0 do
    local fn=table.remove(timers,1);fn();n=n+1;assert(n<1000)
end
assert(not ns.state.active and #ns.state.queue==0 and #ns.state.pending==0 and not head:IsShown())
-- A final marker burst shorter than eight files must still invoke the
-- onReady callback. Otherwise many NPC histories silently never start.
for tail=0,7 do
    reset()
    assert(ns.PlayGossipText("История Дурна."..string.rep("a",tail),"Дурн",npc(),true,"npcLore",18411))
    local steps=0
    while #timers>0 do
        local fn=table.remove(timers,1);fn();steps=steps+1;assert(steps<1000)
    end
    assert(ns.state.active and ns.state.active.kind=="npcLore","partial marker burst lost its callback")
end
print("Narration window: world bosses, loading, matching portraits, group targets, dungeon identity, forced text, settings and Stop passed")

-- The visible report button opens a form bound to the exact track. Changing
-- the playing track while filling it out must not change the report target.
ns.L.FB_REPORT="Пожаловаться";ns.VOICE_LOCALES={"ruRU"}
dofile(ROOT.."/CatQuest/Feedback.lua")
assert(head.bugButton.text=="Пожаловаться")
local place={kind="place",key="place:1234abcd",bookHash="1234abcd",questID=0,
    title="Лес Тероккар",file="1234abcd.ogg",duration=40}
ns.ShowHead(place);head.bugButton.scripts.OnClick()
local form=CatQuest335Feedback
assert(form:IsShown() and form.item==place and form.quest.text:find("Лес Тероккар"))
ns.ShowDemand(lore())
local payload
ns.SendMessageBytes=function(kind,bytes) assert(kind==3);payload=bytes;return true end
form.checks[6].scripts.OnClick();form.note:SetText("Не тот язык")
form.send.scripts.OnClick()
assert(payload[1]==3 and payload[2]==0x12 and payload[3]==0x34 and payload[4]==0xab and payload[5]==0xcd)
assert(payload[6]==6 and payload[7]==1 and not form:IsShown())
head.bugButton.scripts.OnClick()
assert(form:IsShown() and form.item.kind=="npcLore" and form.quest.text:find("18411"))
form.checks[1].scripts.OnClick();form.send.scripts.OnClick()
assert(payload[1]==4 and payload[4]*256+payload[5]==18411)
ns.L.FB_REPORT="Report";ns.RefreshTexts();assert(head.bugButton.text=="Report")
assert(ns.FeedbackBytes({kind="quest",questID=9851},1,"")[1]==1)
assert(ns.FeedbackBytes({kind="turnin",questID=9851},6,"")[1]==2)
print("Feedback window: visible label, place/boss/quest targets, reasons, immutable form target and language refresh passed")

-- Prepared beast histories use the same narrator/cache signature when the
-- target model reports another sex, or no unit is available after a kill.
dofile(ROOT.."/CatQuest/NpcLoreData.lua")
dofile(ROOT.."/CatQuest/NpcLoreOutland.lua")
local captured
ns.PlayGossipText=function(text,title,npc,quiet,kind,id)
    captured={text=text,title=title,npc=npc,kind=kind,id=id};return true
end
local count=0
local zones={}
for id,lore in pairs(CatQuest335NpcLore) do
if lore.voiceGender then
    count=count+1;zones[lore.zone]=true
    local source={id=id,name=ns.GetNpcLore(id).name,gender="female",guid="spawn"}
    assert(ns.PlayNpcLore(id,true,source))
    assert(captured.id==id and captured.kind=="npcLore" and captured.npc.gender=="male")
    assert(source.gender=="female" and captured.npc.guid==source.guid)
    local wire="v2\t"..id.."\tmale\n"..captured.title.."\n"..captured.text
    assert(#wire<=800,id..": narration would be truncated")
end
end
assert(count==23)
for _,zone in ipairs({"Полуостров Адского Пламени","Зангартопь","Лес Тероккар","Награнд",
    "Острогорье","Пустоверть","Долина Призрачной Луны"}) do assert(zones[zone],zone) end
print("NPC lore: all seven Outland zones, 23 complete marker payloads and stable narrator cache keys passed")
-- Manual dialogue attaches the actual NPC, even when only a matching target
-- is available. An unrelated target must not donate its identity.
GossipFrameNpcNameText=object();GossipFrameNpcNameText:SetText('Собеседник')
function GetGossipText()return 'Реплика текущего собеседника.' end
units.npc={id=12345,name='Собеседник',guid='dialogue'}
local text,title,actor=ns.OpenGossipData()
assert(actor.id==12345 and title=='Собеседник')
units.npc=nil;units.target={id=12346,name='Собеседник',guid='target'}
text,title,actor=ns.OpenGossipData();assert(actor.id==12346)
units.target={id=999,name='Посторонний',guid='wrong'}
text,title,actor=ns.OpenGossipData();assert(not actor.id)
print('Manual dialogue: current NPC ID, matching-target fallback, unrelated-target rejection passed')
