local function object(name)
    local v={scripts={},text="",shown=false,enabled=true}
    function v:SetScript(k,fn) self.scripts[k]=fn end
    function v:SetText(t) self.text=t;if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
    function v:GetText() return self.text end
    function v:CreateFontString() return object() end
    function v:CreateTexture() return object() end
    function v:Show() self.shown=true end
    function v:Hide() self.shown=false end
    function v:Enable() self.enabled=true end
    function v:Disable() self.enabled=false end
    setmetatable(v,{__index=function(_,k) if k:match('^[A-Z]') then return function() end end end})
    if name then _G[name]=v end
    return v
end
function CreateFrame(kind,name)
    if kind=='CheckButton' then _G[name..'Text']=object() end
    return object(name)
end
local timers={}
function time() return 1000 end
function GetTime() return 1000 end
SlashCmdList={};UISpecialFrames={}
CONTACT_MARKERS={}
function PlaySoundFile(path) CONTACT_MARKERS[#CONTACT_MARKERS+1]=path;return true end
CatQuest335={L=setmetatable({CONTACT_PROGRESS='Progress %d'},{__index=function(_,k)return k end}),
    ClientLocale=function()return 'ruRU' end,After=function(_,fn)timers[#timers+1]=fn end}
dofile(ROOT..'/CatQuest/Core.lua')
local ns=CatQuest335
ns.Print=function()end
ns.db.remoteEnabled=false
dofile(ROOT..'/CatQuest/Contact.lua')
ns.OpenContact()
local form=CatQuest335Contact
form.text:SetText('Черновик\nвторая строка')
form.checks[2].scripts.OnClick()
form.close.scripts.OnClick()
ns.OpenContact()
assert(form.text:GetText()=='Черновик\nвторая строка' and ns.db.contactDraft.category==2)
assert(not ns.SubmitContact(1,'   '))
assert(not ns.SubmitContact(4,'bad category'))
assert(not ns.SubmitContact(1,string.rep('a',4001)))
CatQuest335_BridgeReady={}
assert(not ns.SubmitContact(1,'old extension'))
assert(next(ns.db.contactPending)==nil)
CatQuest335_BridgeReady={contact=true,contactContext=true,contactPage='isolated-page'}
local text=string.rep('Ж',1997)..'\n🙂'
form.text:SetText(text)
form.send.scripts.OnClick()
assert(not form.send.enabled and ns.db.contactDraft.text=='')
local pending=0
for _,item in pairs(ns.db.contactPending) do assert(item.text==text and item.category==2);pending=pending+1 end
assert(pending==1)
form.send.scripts.OnClick() -- A double click cannot send twice.
while #timers>0 do local batch=timers;timers={};for _,fn in ipairs(batch)do fn()end end
assert(form.status.text=='CONTACT_QUEUED')
local count=#CONTACT_MARKERS
assert(count>7900 and count<=10000)
-- Cached paths must not be reused silently. A second over-budget message
-- stays in the textarea and no extra marker gets played.
form.text:SetText(string.rep('a',1000));form.send.scripts.OnClick()
assert(#CONTACT_MARKERS==count and form.text:GetText()==string.rep('a',1000))
assert(form.status.text=='CONTACT_UNAVAILABLE')
-- A Lua UI reload on the same browser page must not reuse cached paths.
dofile(ROOT..'/CatQuest/Core.lua')
assert(not ns.SendContactMessage('1234567890abcdef',1,string.rep('b',1000)))

-- Right click keeps the existing actions and adds the contact form.
Minimap=object('Minimap')
local entries,menuInit,opened={},nil,false
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) entries[#entries+1]=info end
function UIDropDownMenu_Initialize(_,fn) menuInit=fn end
function ToggleDropDownMenu() menuInit(nil,1) end
function CloseDropDownMenus() end
local reads=0
ns.ReadPlace=function() reads=reads+1 end
ns.OpenContact=function() opened=true end
dofile(ROOT..'/CatQuest/MinimapButton.lua')
CatQuestExtendedMinimapButton.scripts.OnClick(nil,'RightButton')
assert(#entries==3 and entries[3].text=='CONTACT_TITLE')
entries[3].func();assert(opened)
CatQuestExtendedMinimapButton.scripts.OnClick(nil,'LeftButton');assert(reads==1)
