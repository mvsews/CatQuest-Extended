"""Build a tiny licensed font for the browser -> Lua readiness handshake.

GetFont distinguishes a loaded file from a failed load on the target 3.3.5
client. Four glyph advances carry deciseconds, with M as the calibration unit.
No characters are rendered to the player's UI.
"""
import json
import shutil
from pathlib import Path
import matplotlib.font_manager as fm
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'lasthavens-addon-manager/vendor'
source=Path(fm.findfont('DejaVu Sans'))
font=TTFont(source)
options=subset.Options();options.hinting=False
subsetter=subset.Subsetter(options=options);subsetter.populate(text='ABCDMN')
subsetter.subset(font)
# Transport metrics must not be adjusted by kerning or substitutions.
for table in ('GDEF','GPOS','GSUB','MATH'):
 if table in font:del font[table]
units=font['head'].unitsPerEm
for i,char in enumerate('ABCDMN'):
 glyph=font.getBestCmap()[ord(char)]
 advance=1 if char=='M' else 10 if char=='N' else i+2
 font['hmtx'].metrics[glyph]=(advance*units,0)
font['hhea'].advanceWidthMax=10*units
renames={1:'CatQuest Readiness',2:'Regular',3:'CatQuestReadiness-2',4:'CatQuest Readiness',6:'CatQuestReadiness',16:'CatQuest Readiness',17:'Regular'}
for record in font['name'].names:
 if record.nameID in renames:record.string=renames[record.nameID].encode(record.getEncoding())
target=OUT/'catquest-ready.ttf';font.recalcBBoxes=False;font.save(target);font.close()
font=TTFont(target)
assert font['hhea'].numberOfHMetrics==font['maxp'].numGlyphs
records={}
data=target.read_bytes()
for n in range(int.from_bytes(data[4:6],'big')):
 pos=12+n*16;records[data[pos:pos+4].decode('ascii')]=pos
info={'metrics_version':2,'glyph_offsets':[font.reader.tables['hmtx'].offset+font.getGlyphID(font.getBestCmap()[ord(c)])*4 for c in 'ABCD'],
      'hmtx_checksum_offset':records['hmtx']+4,'hmtx_offset':font.reader.tables['hmtx'].offset,
      'hmtx_length':font.reader.tables['hmtx'].length,'head_adjustment_offset':font.reader.tables['head'].offset+8,
      'units_per_em':units,'bytes':len(data)}
(OUT/'catquest-ready.json').write_text(json.dumps(info,indent=2)+'\n',encoding='utf-8')
license_path=source.parents[1]/'LICENSE_DEJAVU'
if not license_path.is_file():license_path=source.parent/'LICENSE_DEJAVU'
assert license_path.is_file(),license_path
shutil.copyfile(license_path,OUT/'catquest-ready.LICENSE')
print(json.dumps(info))
