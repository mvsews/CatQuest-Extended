local now=1000
local ready={}
local durations={[11710]=43.8,[11712]=8.1,[11645]=12.3}
local selected,lastFont=0,nil
local pollIndex=0
local sounds,music={},{}
local function object(name)
 local o={scripts={},text=''}
 function o:SetScript(k,fn)self.scripts[k]=fn end
 function o:CreateFontString()return object()end
 function o:SetText(t)self.text=t end
 function o:GetStringWidth()
  if self.text=='M'then return 12 end
  local index=string.find('ABCD',self.text,1,true)
  local digits=string.format('%04d',math.floor((lastFont.seconds or 0)*10+.5))
  return (tonumber(digits:sub(index,index))+1)*12
 end
 setmetatable(o,{__index=function()return function()end end})
 if name then _G[name]=o end
 return o
end
function CreateFrame(_,name)return object(name)end
function CreateFont()
 local f={}
 function f:SetFont(p)
  selected=tonumber(p:match('q\\(%d+)_')) or selected
  if p:find('poll\\',1,true) then
   selected=0
   if pollIndex==0 and ready[11710] then selected=11710;pollIndex=1
   elseif pollIndex<=1 and ready[11712] then selected=11712;pollIndex=2
   elseif pollIndex<=2 and ready[11645] then selected=11645;pollIndex=3 end
  end
  if ready[selected]then self.path=p;self.seconds=durations[selected];lastFont=self end
  -- Real client returns nil for both success and failure.
 end
 function f:GetFont()return self.path end
 return f
end
function GetTime()return now end
function time()return math.floor(now)end
function GetCVar()return '1'end
function SetCVar()end
function PlaySoundFile(p) sounds[#sounds+1]=p;return 1 end -- deliberately unreliable
function PlayMusic(p)music[#music+1]=p end
function StopMusic()end
function GetNumQuestLogEntries()return 0 end
SlashCmdList={};DEFAULT_CHAT_FRAME={AddMessage=function()end}
CatQuest335={L=setmetatable({QUEST_N='Quest %s'},{__index=function(_,k)return k end}),VoiceLocale=function()return 'ruRU'end,ClientLocale=function()return 'ruRU'end}
dofile(ROOT..'/CatQuest/Scheduler.lua');dofile(ROOT..'/CatQuest/Core.lua')
local ns=CatQuest335
CatQuest335_BridgeReady={locale='ruRU',q={},d={},fontReady=1,contactPage='test-page'}
ns.db.trackGap=0;ns.db.volumeChannel='SFX';ns.db.queue=true;ns.db.remoteAutoRetry=true
local function tick(n)now=now+n;ns.OnUpdate()end
assert(ns.PlayQuest(11710,'quest',true,'Quest text','First',25702))
assert(ns.PlayQuest(11712,'quest',true,'Next text','Second',25747))
assert(not ns.state.active and #ns.state.pending==2 and #ns.state.queue==0 and #sounds==0)
tick(2);assert(not ns.state.active and #sounds==0,'A native truthy return must not fake a start')
ready[11710]=true;tick(2)
assert(not ns.state.active and #sounds==0,'Readiness retries must be throttled while the track is missing')
tick(6)
assert(ns.state.active.questID==11710 and #sounds==1 and #ns.state.pending==1)
assert(math.abs(ns.state.active.duration-44.05)<.001,'Use acknowledged real duration, not the text estimate')
tick(43);assert(#sounds==1 and ns.state.active.questID==11710)
tick(1.3);tick(0)
assert(not ns.state.active and #ns.state.pending==1 and #sounds==1,'The next missing track must stay pending')
ready[11712]=true;tick(17);tick(0)
assert(ns.state.active.questID==11712 and #sounds==2)
ns.Stop(true);tick(.2)
ns.db.volumeChannel='Music'
assert(ns.PlayQuest(11645,'quest',true,'Music text','Third',25477))
assert(not ns.state.active and #music==0)
ready[11645]=true;tick(8)
assert(ns.state.active.questID==11645 and ns.state.active.playChannel=='Music' and #music==1)
assert(#sounds==2,'Music mode must not fall back to a second SFX playback')
ns.Stop(true);local count=#sounds+#music;tick(400)
assert(#sounds+#music==count and not ns.state.active and #ns.state.pending==0)
ns.db.volumeChannel='SFX'
assert(ns.PlayQuest(20001,'quest',true,'Waiting first','Skipped',1))
assert(ns.PlayQuest(20002,'quest',true,'Waiting next','Next',2))
assert(#ns.state.pending==2 and #ns.state.queue==0)
ns.Skip();tick(.3)
assert(ns.state.pending[1].questID==20002 and #ns.state.queue==0,'Next must skip the loading head too')
count=#sounds+#music;ready[20001]=true;tick(2)
assert(#sounds+#music==count and not ns.state.active,'A skipped generation must not start later')
print('Core readiness: nil setters, unreliable sound return, delayed generation, exact duration, FIFO, Music and Stop passed')
