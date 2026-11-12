# CatQuest Extended — CatQuest 3.3.5

[Русская версия](README.ru.md)

[Simple installation and project information](https://catquest.mvse.ws/)

[Public roadmap](ROADMAP.md)

[Public website source](site/)

CatQuest 3.3.5 is the current World of Warcraft addon build of CatQuest Extended,
an independent community continuation for classic clients.
The current public build targets WoW 3.3.5a and adds quest voices, books, place
lore, subtitles, story guides, and a Codex-style zone journal.

The addon directory is named `CatQuest` for compatibility with WoW. The project
is an independent continuation of [the original CatQuest by Cathey](https://www.curseforge.com/wow/addons/catquest).

## Website

The public landing page source is in [`site/`](site/). It contains only static
frontend files and public cover images. The live page is
[catquest.mvse.ws](https://catquest.mvse.ws/).

## Three ways to use it

| Mode | Install | Internet | Audio source |
| --- | --- | --- | --- |
| **Online** | `CatQuest` + `lasthavens-addon-manager` | Required | Remote tracks and on-demand voices |
| **Local** | `CatQuest` + a compatible local voice pack | Not required | Tracks installed on the computer |
| **Hybrid** | `CatQuest` + optional voice pack + `CatQuest Client` | Needed for sync/companion | Local tracks plus live external playback |

Hybrid is the most flexible mode: the local pack works immediately, while
`CatQuest Client` can either download ready tracks into a local addon cache
(`sync`) or run as a live companion that receives text through a pixel bridge
and plays OGG outside WoW. A reload is needed after new cache files are
downloaded.

Audio packs are not stored in this repository. Download the compatible
[CatQuest Extended Voices pack](https://catquest.mvse.ws/downloads/CatQuestExtended_Voices.zip)
from the project site. The upstream source and license are documented on
[CatQuest Voices on CurseForge](https://www.curseforge.com/wow/addons/catquest-voices).
Place the `CatQuestExtended_Voices` folder next to `CatQuest`. Do not commit
`.ogg` files to this repository.

## Contributing voices

Want to help expand the project? Use the public
[CatQuest Extended Voice Packs repository](https://github.com/mvsews/catquest-voice-packs):

- request a missing quest voice;
- submit a ready recording with credits and redistribution rights;
- propose a new language pack.

Choose the matching template on the [new issue page](https://github.com/mvsews/catquest-voice-packs/issues/new/choose).
Full audio packs are not uploaded to Git; approved tracks are reviewed and
published as versioned downloads on the project site.

## Installation

### Online

1. Copy `CatQuest` to `World of Warcraft/Interface/AddOns/`.
2. Load `lasthavens-addon-manager` as an unpacked Chromium extension.
3. Open the supported game page through the manager and reload the page after
   the addon has been installed or updated.
4. In WoW, run `/reload`.

### Local

1. Obtain a compatible local voice pack separately and copy `CatQuest` and its
   `CatQuestExtended_Voices` folder to `World of Warcraft/Interface/AddOns/`.
2. Start WoW and run `/reload`.

### Hybrid

1. Install `CatQuest`. A compatible local voice pack is optional and can be
   added as described in the Local instructions if its ready-made tracks are
   needed.
2. Download `CatQuest Client` and run:

   ```powershell
   .\CatQuest-Client.cmd sync --wow-dir "D:\Games\World of Warcraft"
   ```

3. Run `/reload`. For a track that is not ready yet, use
   `CatQuest-Client.cmd request <id> DETAIL`, then reload again.

For fully automatic playback without Lasthavens, install the dependencies and
run the companion against the real WoW installation:

```powershell
python -m pip install -r client\requirements.txt
.\CatQuest-Client.cmd companion `
  --wow-dir "C:\Games\World of Warcraft\_retail_"
```

It installs `CatQuestCompanion`, reads the colored cells in the top-left screen
area, requests the track from the Voice API, and plays it through `pygame`. If
WoW is already running, run `/reload` after the first installation; use `--x`
and `--y` for a windowed client.

Community packs can add more voices without changing the CatQuest core addon.

## Build from source

The WoW addon is plain Lua: no compiler is required. Run these PowerShell
commands from the repository root to create development archives:

```powershell
New-Item -ItemType Directory -Force dist | Out-Null

# Online addon
Compress-Archive -Path CatQuest -DestinationPath dist/CatQuest-Extended-online.zip -Force

# Local or Hybrid addon bundle
# Add a separately downloaded, compatible CatQuestExtended_Voices folder
# before creating this archive. Audio is intentionally not kept in Git.
Compress-Archive -Path CatQuest,CatQuestExtended_Voices `
  -DestinationPath dist/CatQuest-Extended-local.zip -Force

# Browser manager; for development, loading the unpacked folder is preferred
Compress-Archive -Path lasthavens-addon-manager `
  -DestinationPath dist/CatQuest-Addon-Manager.zip -Force

# Console bridge for ordinary WoW (requires Python 3.10+)
Compress-Archive -Path CatQuest-Client.cmd,client `
  -DestinationPath dist/CatQuest-Client.zip -Force
```

For development, load the `lasthavens-addon-manager` folder directly from
`chrome://extensions` or the equivalent page in another Chromium browser.

Quick checks:

```powershell
Get-ChildItem lasthavens-addon-manager -Filter *.js -Recurse |
  ForEach-Object { node --check $_.FullName }
python -m py_compile research/quest_guides/*.py
```

## What is included

- **CatQuest Voices** — quest descriptions, progress, and turn-ins;
- **NPC-specific quest voices** — when a quest has different speakers, the local
  pack selects the track by the live NPC ID and falls back to the base voice;
- **NPC voices** — online NPC greetings and free-form dialogue; the voice is
  selected by the speaker's NPC ID and gender instead of one generic voice;
- **CatQuest Books** — books, letters, plaques, and place lore;
- **CatQuest Codex** — zone chapters, places, library entries, and story guides;
- queue, history, replay, skip, talking-head, and cue subtitles;
- local and remote tracks with locale fallback;
- locales including `ruRU`, `enUS`, `zhCN`, `zhTW`, `deDE`, `frFR`, `esES`,
  `esMX`, `ptBR`, `koKR`, and `itIT`.

## Contributing

### Code, Lua, UI, translations, and guides

Use this repository:

1. Fork `mvsews/catquest-extended`.
2. Create a focused branch.
3. Test the affected mode: Online, Local, or Hybrid.
4. Open a Pull Request with a short description and test steps.

Bug reports and small suggestions can be opened as GitHub Issues in this
repository. Do not include personal data, private logs, access tokens, or local
machine paths in issues.

### Voices and audio packs

Use the separate public [CatQuest Voice Packs repository](https://github.com/mvsews/catquest-voice-packs).
It contains the catalog, manifest schema, attribution rules, and the submission
process. Do not add large audio archives to this repository. Every contribution
must state its license, author, source, and speaker consent where applicable.

## License

Original client code is MIT-licensed unless a file says otherwise. Derived audio
and third-party materials keep the licenses and attribution listed in
[NOTICE.md](NOTICE.md) and [THIRD_PARTY.md](THIRD_PARTY.md). This is an
unofficial, non-commercial community project. CatQuest Extended is not
affiliated with, sponsored by, or endorsed by Cathey or the original CatQuest
project. The name `CatQuest` is used to identify the project's origin and
compatibility. The project is also not affiliated with Blizzard Entertainment.
