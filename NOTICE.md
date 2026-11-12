# Third-party content and license boundaries

The root `LICENSE` applies to original source code in this repository unless a
file or directory carries a different notice. It is not a blanket license for
every data file, audio file, or third-party-derived artifact.

## CatQuest code and packs

- The original CatQuest addon code is MIT-licensed:
  <https://www.curseforge.com/wow/addons/catquest>.
- `CatQuestExtended_Voices/` contains integration metadata for a compatible
  pack derived from CatQuest Voices 0.7.1. Audio is not redistributed here;
  compatible packs remain CC BY-NC-SA 4.0 and keep attribution in
  `CatQuestExtended_Voices/ATTRIBUTION.md`:
  <https://creativecommons.org/licenses/by-nc-sa/4.0/>.
- `CatQuest/BookData.lua` and related Book/Lore data include material derived
  from CatQuest Books and CatQuest LoreZones. The source notices and links are
  recorded in `THIRD_PARTY.md`; these files must not be treated as plain MIT
  source code.

## Project name and affiliation

CatQuest Extended is an unofficial community continuation for WoW 3.3.5a. It is
not affiliated with, sponsored by, or endorsed by Cathey or the original
CatQuest project. The name `CatQuest` is used to identify the project's origin
and compatibility; this project does not claim official status.

## Quest, story, and place data

`CatQuest/StoryData.lua`, `CatQuest/StoryTitles_*.lua`,
`CatQuest/QuestGuideData.lua`, `CatQuest/Place*.lua`, and related files under
`docs/places/` are generated or curated project data. Parts are derived from
CatQuest Codex, AzerothCore, TrinityCore, and World of Warcraft data. Their
source terms and attribution are described in `THIRD_PARTY.md`; the files are
not relicensed as MIT by the presence of the root `LICENSE`.

Forks and redistributions must preserve this notice and the corresponding
attribution. When adding new generated data, record its source and license next
to the generated file or in `THIRD_PARTY.md`.

## Blizzard notice

CatQuest Extended is an unofficial project and is not affiliated with or
endorsed by Blizzard Entertainment. World of Warcraft names and game content
remain the property of their respective owners. The project is intended for
non-commercial use.
