# CatQuest Voice Pack Specification

Статус: draft / community preview.

Этот документ описывает формат пользовательских голосовых пакетов для CatQuest
Extended. Сначала публикуются метаданные и заявки, а выдача аудио игрокам
происходит только после проверки и публикации пакета backend-сервером.

## Коротко

- Сырой звук не добавляется в историю основного репозитория аддона.
- В репозитории `voice-packs/` хранятся каталог, схема и одобренные манифесты.
- Аудио размещается в GitHub Release, CDN или объектном хранилище автора.
- Для каждого пакета обязательны автор, лицензия, источник и сведения о
  согласии диктора.
- Публикуемый backend выбирает только одобренные пакеты и проверяет SHA-256
  перед выдачей трека.

## Структура пакета

```text
catquest-community-pack/
├── manifest.json
└── audio/
    ├── quest/12345/DETAIL.ogg
    ├── quest/12345/PROGRESS.ogg
    ├── book/000409bf.ogg
    └── place/000409bf.ogg
```

Рекомендуемый формат аудио — OGG Vorbis. Один трек должен содержать одну
реплику, без фоновой музыки и длинной тишины. Backend проверяет длительность,
размер, декодируемость и нормализует технические параметры при необходимости.

## Манифест

Минимальный пример:

```json
{
  "$schema": "https://raw.githubusercontent.com/mvsews/catquest-extended/main/voice-packs/pack.schema.json",
  "schema_version": 1,
  "pack_id": "community-enus-anna",
  "title": "Anna English Voices",
  "version": "1.0.0",
  "author": {
    "display_name": "Anna",
    "contact_url": "https://example.com/anna"
  },
  "license": {
    "spdx": "CC-BY-4.0",
    "url": "https://creativecommons.org/licenses/by/4.0/"
  },
  "locales": ["enUS"],
  "client_versions": ["3.3.5a"],
  "modules": ["voices"],
  "source_url": "https://github.com/example/catquest-voice-pack",
  "download": {
    "url": "https://github.com/example/catquest-voice-pack/releases/download/v1.0.0/pack.zip",
    "sha256": "put-the-sha256-of-the-archive-here"
  },
  "speaker_consent": "confirmed",
  "generation": {
    "kind": "human",
    "provider": "",
    "model": "",
    "voice_id": ""
  },
  "tracks": [
    {
      "content": {
        "kind": "quest",
        "id": "12345",
        "event": "DETAIL"
      },
      "locale": "enUS",
      "file": "audio/quest/12345/DETAIL.ogg",
      "text_hash": "optional-hash-from-the-server-text",
      "duration_ms": 8420,
      "sha256": "sha256-of-the-ogg-file"
    }
  ]
}
```

`content.kind` может быть `quest`, `book`, `place` или `gossip`. Для квестов
`event` — `DETAIL`, `PROGRESS` или `COMPLETE`; для книг и мест обычно достаточно
`id` и `file`. Текстовый hash позволяет не проигрывать старую запись после
изменения текста квеста.

Полная проверяемая схема находится в
[`voice-packs/pack.schema.json`](../voice-packs/pack.schema.json).

## Как предложить пакет

1. Создайте пакет и разместите архив в GitHub Release, CDN или другом URL.
2. Добавьте `manifest.json` и проверьте его по схеме.
3. Заполните форму [Voice pack submission](../.github/ISSUE_TEMPLATE/voice-submission.yml).
4. Укажите, кто записал голос, какая лицензия разрешает распространение и
   является ли голос человеческим, TTS или гибридным.
5. После проверки сопровождающий добавляет пакет в
   [`voice-packs/index.json`](../voice-packs/index.json).

Не прикладывайте большие архивы и секреты к Issue. До одобрения ссылка может
быть временной; после одобрения она должна быть стабильной и иметь SHA-256.

## Требования к правам

- Нельзя отправлять чужую запись без разрешения и атрибуции.
- Для клонированного голоса нужно подтверждение диктора и разрешение на
  распространение результата.
- Для TTS указываются провайдер, модель и идентификатор голоса; условия
  провайдера не должны запрещать публикацию аудио.
- Нельзя переиздавать полный сторонний CatQuest-пак без соблюдения его
  лицензии. Для оригинальных пакетов CatQuest сохраняется CC BY-NC-SA 4.0.
- Лицензия пакета не может быть пустой, а изменение лицензии требует новой
  версии пакета.

## Совместимость с backend

Текущий backend уже публикует индекс готовых треков по quest ID и типу. Для
community-пакетов он будет дополнительно учитывать `pack_id`, локаль, hash
текста и статус модерации. Игроку будет виден только выбранный одобренный
вариант, поэтому несколько авторов смогут озвучить один и тот же квест без
конфликта файлов.

---

## English summary

This is a metadata-first format for community voice packs. Audio stays outside
the main addon Git history, while manifests, licenses, attribution, hashes, and
approved catalog entries remain reviewable in GitHub. Submit a pack through the
voice submission issue form; do not upload large archives or secrets to an
issue. Human recordings, TTS, and hybrid packs are supported, but every pack
must identify its license, source, speaker consent, and generation method.
