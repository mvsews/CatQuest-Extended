from pathlib import Path
import json
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True);lua.globals().ROOT=root.as_posix()
lua.execute((root/'validation/gossip-once.lua').read_text(encoding='utf-8'))
lua.execute('''
CatQuest335_CompanionReady=nil
CatQuest335_BridgeReady={locale='ruRU',q={},gossipOnce=true}
local clock=5000
function GetTime()return clock end
function time()return math.floor(clock)end
captured={}
function PlaySoundFile(path)table.insert(captured,path);return true end
local ns=CatQuest335;ns.Stop(true)
assert(ns.PlayGossipText('A bridge greeting.','NPC',{id=45678,gender='male'},false))
for _=1,100 do
 clock=clock+.2;CatQuest335Scheduler.scripts.OnUpdate(nil,.2)
 if ns.state.active then break end
end
assert(ns.state.active and ns.state.active.gossipHeardKey)
capturedKey=ns.state.active.gossipHeardKey
capturedAudio=ns.state.active.file
clock=clock+ns.state.active.duration+1
ns.OnUpdate()
''')
out=root/'.tmp/gossip-once-frames.json'
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps({'paths':list(lua.globals().captured.values()),'key':lua.globals().capturedKey,
 'audio':lua.globals().capturedAudio},indent=2)+'\n',encoding='utf-8')
