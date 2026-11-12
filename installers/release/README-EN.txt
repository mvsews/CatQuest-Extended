CatQuest for Lasthavens - voiced quests, books and place lore in WoW 3.3.5a
==========================================================================

Requires Chrome, Edge or another Chromium browser, version 120 or newer.

Install (once)
--------------
1. Unpack the archive to a folder you will keep, e.g. C:\Games\CatQuest-Lasthavens.
2. Open chrome://extensions (edge://extensions in Edge).
3. Turn on "Developer mode" (top right).
4. Click "Load unpacked" and choose the CatQuest-Lasthavens folder (the one
   with manifest.json).
5. The addon manager opens. In a few seconds CatQuest appears in it: the
   extension downloads it from the server and enables it (needs internet).
6. Click "Play" or open https://lasthavens.com/play (reload it if it was open).

In game
-------
Quests are read when you accept and turn them in.
  /cq options - settings          /cq stop - stop and clear the queue
  /cq next - next line            /cq r - repeat the last line
  /cq lang ru|en|cn|auto - voice language
  /cq story - story of this zone  /cq map - lore of this place
  /cq help - all commands

Voice-over comes from the voice server over the internet. Russian quests are
mostly voiced already. Other languages are voiced on request the first time a
quest opens (usually 30-90 s); it starts playing by itself when ready.

Update
------
The CatQuest addon updates itself; when it does, a note over the game asks
you to reload the page (F5).
The extension itself is updated by hand: when a new version is out, its icon
shows "1". Open the addon manager -> Updates -> Download, unpack the archive
over the same folder, press "Restart extension" and reload the game page.

Statistics
----------
Once an hour the extension sends anonymous statistics to the voice server: a
random install number, extension and addon versions, voice and browser
language, counters (game starts, tracks played, delivery errors). No character
name, realm, IP or quest list. Turn it off in the addon manager -> Updates.

Problems
--------
Open the addon manager (extension icon) -> Diagnostics -> Copy, and send the
text with a short description.

Licenses
--------
Based on CatQuest by daniilcathey (MIT). Voice-over, book and lore texts come
from CatQuest packs (CC BY-NC-SA: non-commercial, with attribution). See the
LICENSES folder. Free to share; do not sell.
