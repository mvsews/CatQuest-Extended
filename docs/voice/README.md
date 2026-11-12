# Voice inventory

`track-inventory.json` is a generated, audio-free snapshot that joins the
published voice pack with the 3.3.5a quest catalog, the public progress snapshot,
and approved server-generated tracks.

The published offline archive is built by merging the upstream pack with the
ready normalized `ruRU` tracks that are absent from the original index:

```text
python research/build_offline_voice_pack.py \
  --base dist/CatQuestExtended_Voices-1.3.0-full.zip \
  --cache .tmp/server-normalized \
  --server-export .tmp/production-voice-export.json \
  --output dist/CatQuestExtended_Voices-1.3.0-full-with-community.zip
```

Existing original recordings are kept unchanged. Only physically available
normalized OGG files are added; a database row marked ready without an audio
file is reported and is not silently put into the offline pack.

Regenerate it with:

```text
python research/voice_inventory.py \
  --pack dist/CatQuestExtended_Voices-1.3.0-full-with-community.zip \
  --server-export .tmp/production-voice-export.json \
  --upstream-pack .tmp/CatQuest_Voices-1.3.0.zip \
  --upstream-version 1.3.0 \
  --upstream-file-id 9559250 \
  --upstream-last-modified 2026-11-11T15:22:21Z
```

The production export is intentionally not stored in Git. It contains only the
track metadata needed for the audit; account data, telemetry, quest text, secrets,
and server paths are excluded.

The report also stores the upstream archive size and SHA-256. A change in those
values triggers a file-level comparison, so new and removed voice tracks can be
reviewed before importing them into CatQuest Extended.

For a lightweight periodic check that does not download the archive, run
`python research/check_upstream_voice_pack.py`. It compares the saved CDN size,
ETag, and modification date and returns exit code `2` when a re-import review
is needed.
