"""Exercise actual Lua transport/UI, export its frames for the JS receiver."""
import json
from pathlib import Path
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().ROOT=root.as_posix()
lua.execute((root/'validation/contact.lua').read_text(encoding='utf-8'))
frames=[value for _,value in lua.globals().CONTACT_MARKERS.items()]
(root/'.tmp/contact-markers.json').write_text(json.dumps(frames),encoding='utf-8')
print('Contact Lua: large UTF-8 message, categories, draft, duplicate-click guard, progress, opt-out independence, cache pool exhaustion passed')
