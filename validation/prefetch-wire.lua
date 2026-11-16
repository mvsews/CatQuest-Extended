local now, selectedFont = 1000, nil
local timers={}
local paths, probes, ready, missing = {}, {}, {}, {}
local function object()
 local o={}
 function o:CreateFontString() return object() end
 function o:SetText(t) self.text=t end
 function o:GetStringWidth()
  if CQ_TEST_WIDTH then return CQ_TEST_WIDTH(self.text) end
  if self.text=='M' then return 12 end
  local i=string.find('ABCD',self.text,1,true)
  return (tonumber(('0043'):sub(i,i))+1)*12
 end
 return setmetatable(o,{__index=function()return function()end end})
end
function CreateFrame() return object() end
function CreateFont()
 local f={}
 function f:SetFont(p)
  probes[#probes+1]=p
  -- The game resolves font paths as MPQ names, before any browser VFS read.
  -- A mixed separator must not be silently accepted by the Lua fixture.
  if p:find('/',1,true) then return end
  local slot=tonumber(p:match('ready%-signal\\(%d+)') or p:match('\\r\\(%d+)'))
  if not ready[slot] then missing[p]=true end
  if ready[slot] and not missing[p] then self.path=p;selectedFont=self end
 end
 function f:GetFont() return self.path end
 return f
end
function GetTime() return now end
function time() return now end
function GetCVar() return '1' end
function SetCVar() end
function PlaySoundFile(p) paths[#paths+1]=p;return 1 end
local played={}
function PlayMusic(p) played[#played+1]=p end
function StopMusic() end
function GetNumQuestLogEntries() return 0 end
SlashCmdList={};DEFAULT_CHAT_FRAME={AddMessage=function()end}
CatQuest335={L=setmetatable({QUEST_N='Quest %s'},{__index=function(_,k)return k end}),ClientLocale=function()return 'ruRU'end,
 After=function(delay,fn)timers[#timers+1]={at=now+delay,fn=fn}end}
dofile(ROOT..'/CatQuest/Core.lua')
local ns=CatQuest335
CatQuest335_BridgeReady={locale='ruRU',q={},d={},prefetchSignal=3,fontReady=1,readyMetrics=CQ_TEST_METRICS or 1}
ns.db.trackGap=0;ns.db.volumeChannel='Music'
local function tick(n)
 now=now+n
 for i=#timers,1,-1 do
  if timers[i].at<=now then local t=table.remove(timers,i);t.fn()end
 end
 ns.OnUpdate()
end
assert(ns.PrefetchQuestCompletion(11451,'Quest',0))
assert(ns.PlayQuest(11451,'quest',true,'Text','Quest',0))
assert(not ns.state.active and #ns.state.pending==1 and #played==0,
  'First on-demand click must request and enter the retry queue')
local item=ns.state.lastItem
assert(item and ns.state.manualRemoteRequests[item.key], 'Request must be remembered for a manual retry')
tick(2.1)
assert(not ns.PlayQuest(11451,'quest',true,'Text','Quest',0),
  'A duplicate click must not create a second pending request')
assert(not ns.state.active and #ns.state.pending==1 and #played==0,
  'Duplicate click must leave the original readiness check intact')
ns.Stop(true)
for _,suffix in ipairs({'','_m','_f'}) do
 assert(ns.RequestNarrationPrefetch({remote=true,file='Interface\\AddOns\\CatQuest335_ServerVoices\\ruRU\\Sounds\\b\\a1b2c3d4'..suffix..'.ogg'}),'Lua book/place path parsing')
end
assert(not ns.RequestNarrationPrefetch({remote=true,file='Interface\\AddOns\\Other\\b\\invalid.ogg'}))
local gossip=ns.BuildGossipItem('Greeting text','NPC',1,{id=123})
assert(gossip.gossipAudioSlot==1,'Gossip items must retain their audio slot for async prefetch')
assert(ns.RequestGossipPrefetch(gossip))
-- More than the old sixteen marker slots: no shared header filenames.
for id=20001,20045 do assert(ns.RequestVoicePrefetch({remote=true,kind='quest',questID=id}))end
for i=1,5 do tick(.25)end
local count=#played;tick(400)
assert(#played==count,'Stop must prevent late playback')
return {paths=paths,played=played,probes=probes}
