# Voice inventory

`track-inventory.json` is a generated, audio-free snapshot that joins the
published voice pack with the 3.3.5a quest catalog, the public progress snapshot,
and approved server-generated tracks.

Для следующего обновления offline-архива можно добавить готовые
нормализованные `ruRU`-дорожки, которых ещё нет в опубликованном пакете:

```text
python research/build_offline_voice_pack.py \
  --base dist/CatQuestExtended_Voices-2.0.0-extended.1.zip \
  --cache .tmp/server-normalized \
  --server-export .tmp/production-voice-export.json \
  --output dist/CatQuestExtended_Voices-2.0.0-extended.2.zip
```

Existing original recordings are kept unchanged. Only physically available
normalized OGG files are added; a database row marked ready without an audio
file is reported and is not silently put into the offline pack.

Regenerate it with:

```text
python research/voice_inventory.py \
  --pack dist/CatQuestExtended_Voices-2.0.0-extended.1.zip \
  --server-export .tmp/production-voice-export.json \
  --upstream-pack .tmp-catquest-original/CatQuest_Voices-2.0.0.zip \
  --upstream-version 2.0.0 \
  --upstream-file-id 9667108 \
  --upstream-last-modified 2026-11-17T00:00:00Z \
  --output docs/voice/track-inventory.json \
  --markdown docs/voice/INVENTORY.md
```

The production export is intentionally not stored in Git. It contains only the
track metadata needed for the audit; account data, telemetry, quest text, secrets,
and server paths are excluded.

The report also stores the upstream archive size and SHA-256. A change in those
values triggers a file-level comparison, so new and removed voice tracks can be
reviewed before importing them into CatQuest Extended.

## Реестр квестов и покрытие

Покрытие считаем не по числу OGG, а по полному каталогу квестов 3.3.5a.
`research/voice_inventory.py` сопоставляет каталог AzerothCore с индексом
пакета, готовыми серверными дорожками и снимком прогресса. В
`docs/voice/track-inventory.json` сохраняется запись по каждому квесту:
название, зона и цепочка, наличие `DETAIL`/`COMPLETE`, серверный статус,
заявки и расхождения.

На бэкенде источники разделены по назначению: `quest_texts` — сохранённый
каноничный текст после единого резолвера, `voice_requests` — полный журнал
запросов игроков, `missing_voice_requests` — агрегированный приоритетный
список того, что нужно найти или доозвучить. Поэтому новый запрос не заменяет
каталог, а увеличивает приоритет конкретной пары `quest_id + тип + locale`.

Текущий расчёт сохранён в [`INVENTORY.md`](INVENTORY.md): 9 464 квеста в
каталоге, 4 344 с эффективной озвучкой и 5 120 без неё. Версия пакета 2.0.0
не добавила новых безопасно сопоставимых квестов — это отдельно зафиксировано
в [`ORIGINAL-2.0-TRANSFER.ru.md`](ORIGINAL-2.0-TRANSFER.ru.md).

For a lightweight periodic check that does not download the archive, run
`python research/check_upstream_voice_pack.py`. It compares the saved CDN size,
ETag, and modification date and returns exit code `2` when a re-import review
is needed.
