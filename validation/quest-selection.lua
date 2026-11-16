-- Reuse the real Core fixture, then leave a stale NPC quest in GetTitleText.
dofile(ROOT..'/validation/prefetch-wire.lua')
local ns=CatQuest335
ns.Stop(true)
local selected=1
local entries={{12001,'Other quest one','Description one'},{12002,'Other quest two','Description two'}}
function GetTitleText()return 'Alice old quest'end
function GetQuestID()return 11451 end
function GetQuestLogSelection()return selected end
function SelectQuestLogEntry(index)selected=index end
function GetNumQuestLogEntries()return #entries end
function GetQuestLogTitle(index)
 local q=entries[index]
 return q[2],70,nil,0,false,false,nil,false,q[1]
end
function GetQuestLogQuestText()return entries[selected][3]end
ns.PlaySelectedQuest()
assert(ns.state.pending[1].questID==12001 and ns.state.pending[1].title=='Other quest one')
assert(ns.state.pending[1].text=='Description one')
selected=2;ns.PlaySelectedQuest()
assert(#ns.state.queue==1 and ns.state.queue[1].questID==12002)
assert(ns.state.queue[1].title=='Other quest two' and ns.state.queue[1].text=='Description two')
ns.Stop(true)
ns.state.lastRequestKey=nil
ns.PlayQuest(12002,'quest',true)
assert(ns.state.pending[1].title=='Other quest two','General ID-based title lookup must ignore stale NPC title, too')
print('Journal selection: current ID/title/description, different queued quests and stale NPC globals passed')
