"""Decode runtime-generated TTFs through real Lua + FreeType ink/advance metrics."""
import json
import sys
from pathlib import Path
from PIL import ImageFont

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / '.tmp/test-python'))
from lupa.lua51 import LuaRuntime

samples = json.loads(Path(sys.argv[1]).read_text())
fixture = (root / 'validation/prefetch-wire.lua').read_text(encoding='utf-8')
tested = 0
for sample in samples:
    font = ImageFont.truetype(sample['file'], 12)
    # Pillow's getbbox may include advance whitespace. Use nonzero raster
    # bounds + bearing, as the client's terminal-glyph path does.
    ink = {}
    for char in 'ABCDMN':
        mask, offset = font.getmask2(char)
        ink[char] = offset[0] + mask.getbbox()[2]
    for scale, spacing, padding in [(1, 0, 0), (.7844739, 1, 2), (.6, 1, 4), (1.5, 2, 7)]:
        def measure(text):
            # GxuFont's terminal-glyph path uses bearing + bitmap width.
            # Earlier glyphs contribute their advances, including extra spacing.
            return (font.getlength(text[:-1]) + ink[text[-1]] + spacing * (len(text)-1)) * scale + padding
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().ROOT = root.as_posix()
        lua.globals().CQ_TEST_WIDTH = measure
        lua.globals().CQ_TEST_METRICS = 2
        lua.globals().CQ_TEST_DURATION = sample['seconds']
        lua.execute(fixture)
        assert lua.globals().CatQuest335.state.pending[1] is None
        tested += 1
    if sample['seconds'] == 36.8:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().ROOT = root.as_posix()
        lua.globals().CQ_TEST_WIDTH = lambda text: font.getlength(text[:-1]) + ink[text[-1]]
        lua.globals().CQ_TEST_METRICS = 1
        # Metrics v1 is retained for older bridges.  The current fixture must
        # complete its request without crashing; it no longer asserts the old
        # zero-duration failure because the queue no longer probes in a tight
        # loop and the v2 bridge is the production path.
        lua.execute(fixture)
        assert lua.globals().CatQuest335.state.active is None
print(f'Native glyph-ink regression: {tested} real Lua/TTF duration, scale and spacing cases passed; legacy metrics path completed safely')
