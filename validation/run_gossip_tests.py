import hashlib
import json
import sys
from pathlib import Path
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'backend'))
from gossip_text import universal_gossip_text
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute((root/'CatQuest/GossipText.lua').read_text(encoding='utf-8'))
clean=lua.globals().CatQuest335.UniversalGossipText
cases=[
    ('Приветствую, Альфа.','Альфа','Приветствую.'),
    ('Приветствую, Бета.','Бета','Приветствую.'),
    ('АЛЬФА, воин, мне нужна помощь!','Альфа','мне нужна помощь!'),
    ('Спасибо, |cffffffffАльфа|r, рыцарь смерти!','Альфа','Спасибо!'),
    ('Здравствуй, $N! Не подведи меня, |3-6($C).','Альфа','Здравствуй! Не подведи меня.'),
    ('Greetings, Alpha, mage!','Alpha','Greetings!'),
    ('«Альфа», здравствуй!','Альфа','здравствуй!'),
    ('Привет, Альфа','Альфа','Привет'),
    ('Кадгар — маг, а стражник — воин.','Альфа','Кадгар — маг, а стражник — воин.'),
    ('Маг, который живёт в башне, ждёт тебя.','Альфа','Маг, который живёт в башне, ждёт тебя.'),
    ('Маг, с которым мы говорили, ушёл.','Альфа','Маг, с которым мы говорили, ушёл.'),
    ('Анна учится у магистра.','Анн','Анна учится у магистра.'),
]
for text,name,expected in cases:
    actual=clean(text,name)
    assert actual==expected,(text,actual,expected)
    server=universal_gossip_text(text,[name])
    assert server==expected,(text,server,expected)
    assert universal_gossip_text(actual)==actual
for name in ('Альфа','Бета'):
    for role in ('воин','маг','жрица','чернокнижник','разбойница','паладин','друид','шаман','охотница','рыцарь смерти'):
        assert clean(f'Приветствую, {name}, {role}!',name)=='Приветствую!'
index=json.loads((root/'backend/npc_lore_registry.json').read_text(encoding='utf-8'))
for row in index['implemented']:
    assert universal_gossip_text(row['text'])==row['text'],row['npc_id']
print('Universal gossip: Lua/Python parity, different heroes/classes, UTF-8, formatting, punctuation, NPC facts and all curated narrations passed')
lua.globals().ROOT=root.as_posix()
lua.execute('''
local function frame(name)
    local f={scripts={}}
    function f:SetScript(k,fn)self.scripts[k]=fn end
    setmetatable(f,{__index=function()return function()end end})
    if name then _G[name]=f end
    return f
end
function CreateFrame(_,name)return frame(name)end
local clock=1000
function GetTime()return clock end
function time()return clock end
function UnitName(unit)if unit=='player'then return 'Альфа' elseif unit=='npc'then return 'Рилак' end end
function UnitClass()return 'Маг','MAGE'end
function PlaySoundFile()return false end
SlashCmdList={};DEFAULT_CHAT_FRAME={AddMessage=function()end}
CatQuest335.L=setmetatable({QUEST_N='Quest %s'},{__index=function(_,k)return k end})
CatQuest335.ClientLocale=function()return 'ruRU'end
CatQuest335.VoiceLocale=function()return 'ruRU'end
dofile(ROOT..'/CatQuest/Scheduler.lua')
dofile(ROOT..'/CatQuest/Core.lua')
CatQuest335_BridgeReady={locale='ruRU',q={}}
local ns=CatQuest335
local function receive(text,kind)
    ns.Stop(true)
    assert(ns.PlayGossipText(text,'Рилак',{id=22292,gender='male'},false,kind,22292))
    for i=1,300 do
        clock=clock+0.2;CatQuest335Scheduler.scripts.OnUpdate(nil,0.2)
        if ns.state.pending[1] then return ns.state.pending[1] end
    end
    error('No queued gossip after actual marker transfer')
end
local item=receive('Приветствую, Альфа, маг!')
assert(item.text=='Приветствую!' and item.npc.id==22292)
local narrative='Альфа — маг, который живёт в башне.'
item=receive(narrative,'npcLore');assert(item.text==narrative)
''')
print('Actual Core/marker transfer: ordinary dialogue is universal, NPC ID survives, authored lore stays unchanged')
