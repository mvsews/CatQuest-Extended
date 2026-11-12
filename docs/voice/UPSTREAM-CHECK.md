# Upstream CatQuest Voices check

The original [CatQuest Voices project](https://www.curseforge.com/wow/addons/catquest-voices)
is the source of the Russian original-voice pack. Its releases are monitored by
archive size, SHA-256, track count, and quest-ID set. Audio is not copied into Git.

## Current upstream release

CurseForge currently lists `CatQuest_Voices-1.3.0.zip` (file ID `9559250`):

- uploaded/updated: `2026-11-11T15:22:21Z`;
- archive size: `1,424,266,180` bytes;
- SHA-256: `6b76ee548230538c396780c4e03b7b3fcd18f552f63d5ec035dde6db2c44e3f4`;
- 12,830 OGG files;
- 5,574 quest IDs.

Compared with the previously imported 0.7.1 archive, this release contains:

- 1,003 additional track signatures;
- 607 additional quest IDs;
- 8 track signatures no longer present;
- 41 new IDs that exist in the CatQuest Extended 3.3.5a catalog.

The detailed comparison is kept in [`track-inventory.json`](track-inventory.json)
and is regenerated whenever the upstream archive is checked.

## Quick periodic check

The CDN can be checked without downloading the 1+ GB archive:

```text
python research/check_upstream_voice_pack.py
```

The command compares the saved size, ETag, and modification date.  Exit code
`0` means that the saved release is unchanged; exit code `2` means that the
archive should be downloaded and inventoried again.  After a new release is
confirmed, add its metadata to this history and import it only after the
file-level comparison has been reviewed.
