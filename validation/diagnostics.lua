-- Real Lua 5.1 core, then a small UI harness for the copyable report.
dofile(ROOT .. '/validation/prefetch-wire.lua')
local ns = CatQuest335
local callbacks, markers = {}, {}
ns.After=function(delay,fn) callbacks[#callbacks+1]=fn end
PlaySoundFile=function(path) markers[#markers+1]=path end
CatQuest335_BridgeReady.clientTrace=1
local sample={remote=true,kind='turnin',questID=12009,prefetchSlot=42,file='voice.ogg',title='Quest',key='12009:turnin'}
ns.SendDiagnosticStage(sample,'font-probe')
sample.readySignalAttempts=1
ns.SendDiagnosticStage(sample,'font-probe');ns.SendDiagnosticStage(sample,'font-probe')
ns.SendDiagnosticStage(sample,'playing');ns.SendDiagnosticStage(sample,'playing')
assert(#callbacks==2,'Client diagnostics must deduplicate repeated stages')
for _,fn in ipairs(callbacks)do fn()end
assert(markers[1]:find('\\trace\\42\\17.ogg',1,true))
assert(markers[2]:find('\\trace\\42\\4.ogg',1,true))
for i=1,350 do ns.VoiceLog(sample,'test','event '..i)end
assert(#ns.db.voiceLog==300,'Bounded game history')
ns.db.voiceLog[300].requestedFont='requested.ttf'
ns.db.voiceLog[300].observedFont='different.ttf'
local widgets,all={},{ }
local function widget(name)
 local box={scripts={}}
 all[#all+1]=box
 function box:SetScript(kind,fn) self.scripts[kind]=fn end
 function box:CreateFontString() return widget() end
 function box:SetText(text) self.text=text end
 function box:GetText() return self.text end
 function box:SetFocus() self.focus=true end
 function box:HighlightText() self.highlight=true end
 function box:SetFontObject(font) assert(font,'Font must exist before SetText') end
 if name then widgets[name]=box end
 return setmetatable(box,{__index=function()return function()end end})
end
CreateFrame=function(_,name) return widget(name) end
ChatFontNormal={};GameFontNormal={}
dofile(ROOT .. '/CatQuest/Diagnostics.lua')
ns.OpenDebug()
local box=widgets.CatQuest335DebugText
assert(box.text:find('questID=12009',1,true))
assert(box.text:find('requestedFont=requested.ttf',1,true))
assert(box.text:find('observedFont=different.ttf',1,true))
assert(box.text:find('slot=42',1,true))
assert(box.text:find('audible sound',1,true),'Never claim audible playback from API return')
assert(not widgets.CatQuest335Debug.scripts.OnUpdate,'No continuous report rebuilding')
assert(box.scripts.OnEscapePressed)
local function click(key)
 for _,w in ipairs(all)do if w.text==ns.L[key] and w.scripts.OnClick then w.scripts.OnClick();return end end
 error('Missing diagnostic button: '..key)
end
click('DEBUG_SELECT');assert(box.focus and box.highlight,'Copy action must focus and select the report')
ns.VoiceLog(sample,'new-event','after opening')
assert(not box.text:find('after opening',1,true),'Snapshot stays stable while copying')
click('DEBUG_REFRESH');assert(box.text:find('after opening',1,true))
click('DEBUG_CLEAR');assert(#ns.db.voiceLog==0)
print('Game diagnostics: bounded ring, identity, font mismatch, UI snapshot and stage dedup passed')
