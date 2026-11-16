from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().ROOT = root.as_posix()
lua.execute((root / 'validation/narration-window.lua').read_text(encoding='utf-8'))
