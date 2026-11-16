import { readFile } from "node:fs/promises";
import { importZip } from "../lasthavens-addon-manager/archive.js";
const file = process.argv[2];
if (!file) throw new Error("Pass the addon ZIP filename");
const addons = await importZip(new Uint8Array(await readFile(file)));
if (addons.length !== 1 || addons[0].folder !== "CatQuest") throw new Error("Addon root mismatch");
const audio = Object.keys(addons[0].files).filter(p => p.startsWith("Sounds/dungeon/") && p.endsWith(".ogg"));
if (audio.length !== 669) throw new Error(`Expected 669 recordings, found ${audio.length}`);
console.log(`Manager import: ${addons[0].version}, ${audio.length} recordings, ${addons[0].size} expanded bytes`);
