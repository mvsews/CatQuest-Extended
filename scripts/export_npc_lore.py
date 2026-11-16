"""Export the addon's curated narrator texts for low-priority server prewarming."""
import hashlib
import json
from collections import Counter
from pathlib import Path
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parents[1]
lua=LuaRuntime()
lua.execute('CatQuest335={}')
for file in ('NpcLoreData.lua','NpcLoreOutland.lua'):
    lua.execute((root/'CatQuest'/file).read_text(encoding='utf-8'))
entries=[]
coverage=[]
registry=[]
for npc,row in sorted(lua.globals().CatQuest335NpcLore.items()):
    if row.voiceGender:
        entry=dict(npc_id=npc,npc_gender=row.voiceGender,title=row.title,text=row.text,locale='ruRU')
        wire=f"v2\t{npc}\t{row.voiceGender}\n{row.title}\n{row.text}"
        assert len(wire.encode('utf-8'))<=800,npc
        entries.append(entry)
    coverage.append(dict(npc_id=npc,name=row.name,zone=row.zone,source=row.source,quest_source=row.questSource))
    registry.append(dict(npc_id=npc,name=row.name,zone=row.zone,title=row.title,text=row.text,
        voice_gender=row.voiceGender,source=row.source,quest_source=row.questSource))
(root/'backend/npc_lore_catalog.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(root/'docs/npc-lore-coverage.json').write_text(json.dumps(coverage,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
planned=json.loads((root/'docs/npc-lore-planned.json').read_text(encoding='utf-8'))
ids={row['npc_id'] for row in registry}
assert len({row['npc_id'] for row in planned})==len(planned),'Duplicate planned NPC'
assert not ids.intersection(row['npc_id'] for row in planned),'Implemented NPC must leave the backlog'
version=next(line.split(':',1)[1].strip() for line in
    (root/'CatQuest/CatQuest.toc').read_text().splitlines() if line.startswith('## Version:'))
index=dict(schema=1,addon_version=version,locale='ruRU',client='3.3.5a',
    addon_source_sha256={file:hashlib.sha256((root/'CatQuest'/file).read_bytes()).hexdigest()
        for file in ('NpcLoreData.lua','NpcLoreOutland.lua')},implemented=registry,planned=planned)
(root/'backend/npc_lore_registry.json').write_text(json.dumps(index,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'{len(entries)} curated Russian narrations exported; {len(coverage)} total NPC histories')
for zone,count in Counter(row['zone'] for row in coverage).items():
    print(f'{zone}: {count}')
