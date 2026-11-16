"""Import all original 3.3.5-compatible Dungeon Master scenarios (lupa.lua51).

Requires official CatQuest_Books-1.2.0.zip and AzerothCore instance_encounters.sql.
Never invents a recording or accepts an unresolved encounter mapping.
"""
import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SQL_SOURCE = "https://raw.githubusercontent.com/azerothcore/azerothcore-wotlk/master/data/sql/base/db_world/instance_encounters.sql"


def normal(text):
    return re.sub(r"[^a-zа-яё0-9]", "", text.lower()).replace("ё", "е")


def plain(value):
    if hasattr(value, "items"):
        keys = list(value.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [plain(value[i]) for i in range(1, len(keys) + 1)]
        return {k: plain(v) for k, v in value.items()}
    return value


def lua_value(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (float, int)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{ " + ", ".join(lua_value(x) for x in value) + " }"
    return "{ " + ", ".join("[%s] = %s" % (lua_value(k), lua_value(v)) for k, v in value.items()) + " }"


# Credit entities absent from the base SQL or renamed between Classic and 3.3.5.
# Multiple participants can start a fight; required lists describe actual victory.
OVERRIDES = {
    "weaver": ([5720], None), "plaguemaw": ([7356], None),
    "theka": ([7272], None), "gahzrilla": ([7273], None), "tendris": ([11489], None),
    "sneed": ([642, 643], [643]),
    "johnson": ([3586], None), "rhahkzor": ([644], None),
    "vancleef": ([639], None), "kam": ([1666], None),
    "hamhock": ([1717], None), "dextren": ([1663], None), "bazil": ([1716], None),
    "rethilgore": ([3914], None), "razorclaw": ([3886], None),
    "silverlaine": ([3887], None), "springvale": ([4278], None), "odo": ([4279], None),
    "fenrus": ([4274], None), "nandos": ([3927], None), "arugal": ([4275], None),
    "oggleflint": ([11517], None), "taragaman": ([11520], None),
    "jergosh": ([11518], None), "bazzalan": ([11519], None),
    "grubbis": ([7361], None), "fallout": ([7079], None), "electro": ([6235], None),
    "pummeler": ([6229], None), "therma": ([7800], None),
    "dwarves": ([6906, 6907, 6908], [6906, 6907, 6908]),
    "obsidian": ([7023], None), "keeper": ([7206], None),
    "avatar": ([8443], None), "atal": ([8580], None),
    "jammalan": ([5710, 5711], [5710, 5711]), "eranikus": ([5709], None),
    "tuten": ([7355], None), "raggle": ([7354], None),
    "whitemane": ([3976, 3977], [3977]),
    "ring": ([9027, 9028, 9029, 9030, 9031, 9032], None),
    "seven": ([9034, 9035, 9036, 9037, 9038, 9039, 9040], [9034, 9035, 9036, 9037, 9038, 9039, 9040]),
    "emperor": ([9019], None), "moira": ([8929], None), "vault": ([9476], None),
    "emberseer": ([9816], None), "rend": ([10429, 10339], [10429]),
    "valthalak": ([16042], None), "beast": ([10430], None),
    "skul": ([10393], None), "ezra": ([11058], None), "postmaster": ([11143], None),
    "malor": ([11032], None), "hammersmith": ([11120], None),
    "stonespine": ([10809], None), "swordsmith": ([11121], None),
    "ramstein": ([10439], None), "rivendare": ([10440], None),
    "kirtonos": ([10506], None), "rattlegore": ([11622], None),
    "jandice": ([10503], None), "vectus": ([10432], None),
    "marduk": ([10433], None), "ras": ([10508], None), "kormok": ([16118], None),
    "polkelt": ([10901], None), "illucia": ([10502], None), "krastinov": ([11261], None),
    "alexei": ([10504], None), "malicia": ([10505], None), "ravenian": ([10507], None),
    "gandling": ([1853], None), "pusillin": ([14354], None), "tsuzee": ([11467], None),
    "helnurath": ([14506], None), "ukorz": ([7267, 7797], [7267, 7797]),
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("--encounters", type=Path, default=ROOT / ".tmp/instance_encounters.sql")
    parser.add_argument("--audit", action="store_true")
    parser.add_argument("--creatures", type=Path, default=ROOT / ".tmp/creature_template.sql")
    args = parser.parse_args()
    credits = {}
    creature_names = {int(k): v.replace("\\'", "'") for k, v in re.findall(
        r"^\((\d+),(?:\d+,){5}'((?:\\.|[^'])*)'", args.creatures.read_text(encoding="utf-8"), re.M)}
    for enc, npc, name in re.findall(r"\((\d+),0,(\d+),\d+,'((?:\\.|[^'])*)'\)", args.encounters.read_text(encoding="utf-8")):
        credits[int(enc)] = (int(npc), name.replace("\\'", "'"))
    lua = LuaRuntime(unpack_returned_tuples=True)
    with zipfile.ZipFile(args.archive) as archive:
        lua.execute(archive.read("CatQuest_Books/DungeonData.lua").decode("utf-8-sig"))
        lua.execute(archive.read("CatQuest_Books/Index.lua").decode("utf-8-sig"))
        raw = plain(lua.globals().CatQuestDungeonData)
        compatible = {k: v for k, v in raw.items() if k < 1000}
        mappings, unresolved = {}, []
        npc_names = lua.eval("function(s) local ns={}; assert(loadstring(s))('CatQuest',ns); return ns.NpcData end")(
            (ROOT / ".tmp-catquest-original/v1.1.2/CatQuest/NpcData.lua").read_text(encoding="utf-8-sig"))
        for map_id, data in sorted(compatible.items()):
            bosses = {}
            ordered = sorted(data["ev"], key=lambda e: e["trig"] != "start")
            for event in ordered:
                if event["trig"] not in ("start", "kill") or event.get("enc") in bosses:
                    continue
                token = event["id"][len("dm_" + data["key"] + "_"):]
                if event["trig"] == "start":
                    token = token[:-len("_pull")]
                enc = event["enc"]
                if token in OVERRIDES:
                    npcs, required = OVERRIDES[token]
                else:
                    candidates = {npc for npc, name in credits.values() if normal(token) in normal(name)}
                    if len(candidates) != 1:
                        unresolved.append((map_id, enc, token, sorted(candidates)))
                        continue
                    npcs, required = list(candidates), None
                names = [name for npc, name in credits.values() if npc == npcs[-1]]
                for npc in npcs:
                    assert npc in creature_names, (map_id, token, npc)
                npc_name = npc_names[npcs[-1]]
                name = npc_name[4] if npc_name and npc_name[4] else (names[0] if names else token)
                bosses[enc] = {"id": enc, "npcs": npcs, "name": name,
                               "required": required, "token": token,
                               "names335": [creature_names[npc] for npc in npcs]}
            owners = {}
            for enc, boss in bosses.items():
                for npc in boss["npcs"]:
                    assert npc not in owners, (map_id, npc, owners.get(npc), enc)
                    owners[npc] = enc
            mappings[map_id] = bosses
            assert {e["enc"] for e in data["ev"] if e.get("enc")} <= set(bosses), map_id
            event_ids = {e["id"] for e in data["ev"]}
            for e in data["ev"]:
                assert not e.get("follows") or e["follows"] in event_ids, e["id"]
                for field in ("encs", "noKills", "anyKill"):
                    assert set(e.get(field, [])) <= set(bosses), (map_id, e["id"], field)
        if args.audit or unresolved:
            for row in unresolved:
                print("UNRESOLVED", row)
            print("maps", len(compatible), "encounters", sum(map(len, mappings.values())), "unresolved", len(unresolved))
            if unresolved:
                raise SystemExit(1)
            if args.audit:
                return
        tracks = {}
        for key, book in lua.globals().CatQuestVoicePack.books.items():
            cues = book.c and book.c.x
            if cues:
                cue_list = plain(cues)
                text = normal(" ".join(c[1] for c in cue_list))
                tracks[text] = (key, book.d, cue_list)
        manifest, output = {}, {}
        stage = ROOT / "dist/dungeon-audio"
        stage.mkdir(parents=True, exist_ok=True)
        for map_id, data in sorted(compatible.items()):
            for event in data["ev"]:
                raw_hash = 0
                for byte in event["text"].strip().encode("utf-8"):
                    raw_hash = (raw_hash * 31 + byte) % 4294967296
                key = f"{raw_hash:08x}"
                book = lua.globals().CatQuestVoicePack.books[key]
                if book:
                    duration = book.d
                    cues = plain(book.c.x) if book.c and book.c.x else [[0, event["text"]]]
                else:
                    key, duration, cues = tracks[normal(event["text"])]
                audio = archive.read(f"CatQuest_Books/Sounds/b/{key}.ogg")
                (stage / f"{key}.ogg").write_bytes(audio)
                manifest[key] = {"bytes": len(audio), "sha256": hashlib.sha256(audio).hexdigest(),
                                 "event": event["id"], "duration": duration}
                event["track"] = {"hash": key, "text": event["text"], "duration": duration, "cues": cues}
                del event["text"]
            data["events"] = data.pop("ev")
            data["bosses"] = list(mappings[map_id].values())
            output[map_id] = data
        aliases = lua.eval("function(s) local ns={}; assert(loadstring(s))('CatQuest',ns); return ns.AreaRu end")(
            (ROOT / ".tmp-catquest-original/v1.1.2/CatQuest/AreaNames.lua").read_text(encoding="utf-8-sig"))
        wanted = {normal(e["sub"]) for d in output.values() for e in d["events"] if e.get("sub")}
        area_aliases = {en: ru for en, ru in aliases.items() if normal(ru) in wanted}
        rows = ["-- Generated by scripts/import_dungeons.py from CatQuest Books & Lore 1.2.0.",
                "-- Scenario text, subtitles and recordings: Cathey / daniilcathey, CC BY-NC-SA 4.0.",
                "CatQuest335.DungeonData = {"]
        rows += ["[%d] = %s," % (k, lua_value(v)) for k, v in output.items()]
        rows += ["}", "CatQuest335.DungeonAreaAliases = " + lua_value(area_aliases), ""]
        (ROOT / "CatQuest/DungeonData.lua").write_text("\n".join(rows), encoding="utf-8")
        (stage / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        report = {"source": "CatQuest Books & Lore 1.2.0 / file 9568747", "npc_source": SQL_SOURCE,
                  "maps": {str(k): {"name": d["name"], "events": len(d["events"]),
                                      "bosses": d["bosses"]} for k, d in output.items()},
                  "excluded": {str(k): v["name"] for k, v in raw.items() if k not in compatible},
                  "recordings": len(manifest), "bytes": sum(v["bytes"] for v in manifest.values())}
        (ROOT / "docs/dungeon-coverage.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        lines = ["# Покрытие Мастера подземелий", "", "Сгенерировано `scripts/import_dungeons.py` из оригинального Books & Lore 1.2.0.", "",
                 "| Карта | Инстанс | Бои/встречи | События сценария |", "| --- | --- | --- | --- |"]
        for k, d in output.items():
            lines.append(f"| {k} | {d['name']} | {len(d['bosses'])} | {len(d['events'])} |")
        lines += ["", f"Всего: {len(output)} карт, {sum(len(d['bosses']) for d in output.values())} встреч, "
                  f"{sum(len(d['events']) for d in output.values())} событий, {len(manifest)} аудиозаписей.", "",
                  "## Карты оригинала, отсутствующие в 3.3.5a", "",
                  "Эти сценарии сохранены в исходном паке, но не включены в активный реестр клиента 3.3.5a.", ""]
        lines += [f"- {k}: {name}" for k, name in sorted(report["excluded"].items())]
        lines += ["", "Точные NPC, составные встречи и источник соответствий — [dungeon-coverage.json](dungeon-coverage.json).", ""]
        (ROOT / "docs/DUNGEON-COVERAGE.ru.md").write_text("\n".join(lines), encoding="utf-8")
        print("Imported", len(output), "maps;", len(manifest), "recordings;", report["bytes"], "bytes")


if __name__ == "__main__":
    main()
