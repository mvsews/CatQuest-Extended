# Голоса оригинального CatQuest и подключение ElevenLabs

Проверено 14 ноября 2026 года (Asia/Shanghai).

## Результат поиска

Оригинальный CatQuest использует заранее подготовленные записи ElevenLabs.
В исследованных индексах модель помечена как `eleven_v4`. Это метаданные
исходного пака, а не проверка доступности модели для нашего аккаунта.

Проверены локальные копии официальных архивов:

| Пак | Поле голоса | Число разных обозначений | Настоящие API voice_id |
|---|---|---:|---|
| CatQuest Voices 1.3.0, `index.json` | `v` | 154 | Не найдены |
| CatQuest Books 1.2.0, `index_books.json` | `v` | 32 | Не найдены |

Примеры обозначений: `human-male`, `scourge-male#83`, `narrator`,
`named/thrall`, `named/sylvanas`, `creature/rexxar`.
`named/13717` и похожие значения — внутренние обозначения именных персонажей;
их нельзя подставлять вместо ElevenLabs `voice_id`.

В JSON нет полей `voice_id`/`voiceId` и ссылок на ElevenLabs API.
В выборке примерно по 200 OGG каждого архива комментарии содержат только
`Lavf62.3.100` и `encoder=Lavc62.11.100 libvorbis`.
Публичного соответствия «обозначение CatQuest → ElevenLabs voice_id»
на страницах проекта и в выполненном веб-поиске не найдено.

Полный перечень обозначений, число записей и примеры ключей сохранены в
[`voices/catquest-original-catalog.json`](voices/catquest-original-catalog.json).
Значение `elevenlabs_voice_id: null` означает «не установлен», а не отсутствие
голоса в аккаунте автора. Число обозначений не доказывает число уникальных
моделей голосов в ElevenLabs.

## Попытки через официальный API

- `GET /v1/shared-voices?search=Medivh` и `search=CatQuest` без ключа:
  HTTP 401; содержимое библиотеки не получено.
- `POST /v1/similar-voices` без ключа с 15-секундным публичным образцом
  `narrator` (квест 100, описание): HTTP 401; совпадение не установлено.
- Первая проверка общего каталога OpenRouter без фильтра речевых моделей
  пропустила ElevenLabs. Повторная проверка
  `GET /api/v1/models?output_modalities=speech` подтвердила девять моделей
  ElevenLabs, включая `elevenlabs/eleven-v4`, `elevenlabs/eleven-v4-turbo`,
  `elevenlabs/eleven-v3` и `elevenlabs/eleven-multilingual-v2`.

Из HTTP 401 нельзя делать вывод, что голоса не опубликованы. Для продолжения
поиска по образцам нужен доступ к штатному API ElevenLabs. Поиск похожих
голосов возвращает кандидатов из общей библиотеки и сам по себе не доказывает,
что найден именно исходный голос CatQuest.

## Что можем подключить

В нашем генераторе сейчас используется OpenRouter: основной TTS — Gemini,
резервный — Grok. Клиент получает готовый OGG; для смены поставщика синтеза
менять игровой API 3.3.5a не требуется.

Для стандартных голосов через OpenRouter отдельный ключ ElevenLabs не требуется:
`POST /api/v1/audio/speech` использует ключ и баланс OpenRouter. Например:

```json
{
  "model": "elevenlabs/eleven-v4",
  "input": "Приветствую, путник.",
  "voice": "george",
  "response_format": "mp3"
}
```

Это пример запроса по документации; платная генерация им не выполнялась.
На момент проверки все девять моделей объявляют один список `supported_voices`:
`george`, `sarah`, `adam`, `alice`, `bella`, `bill`, `brian`, `callum`,
`charlie`, `chris`, `daniel`, `eric`, `harry`, `jessica`, `laura`, `liam`,
`lily`, `matilda`, `river`, `roger`, `will`.

Это стандартные значения параметра `voice` в OpenRouter, а не полный предел
поддерживаемых голосов. В официальном анонсе интеграции прямо разрешено
передавать ElevenLabs voice ID других голосов из библиотеки в поле `voice`.
Для собственных клонированных и созданных через Voice Design голосов анонс
указывает BYOK: подключение своего ключа ElevenLabs к OpenRouter.
Следовательно, кастомные голоса поддерживаются; список `supported_voices`
сам по себе не является запретом на них. Конкретный голос CatQuest ещё не
проверен: его реальный voice_id и доступ к нему пока не установлены.

Для прямого API ElevenLabs потребуется отдельный ключ ElevenLabs и проверенная
таблица «NPC / расовый голос / рассказчик → доступный voice_id». Лимит ключа
OpenRouter не является балансом прямого API ElevenLabs. При любом варианте
очередь, очистку персональных обращений, проверку языка, учёт расходов и
готовый OGG-кэш следует сохранить.

Чтобы получить именно голоса автора, нужны его таблица ID и доступ к голосам
через предусмотренный ElevenLabs механизм. Самого ID приватного голоса
недостаточно. По текущей документации профессиональные клоны можно открыть
по ссылке; Instant Voice Clones и Voice Design доступны для совместного
использования только внутри workspace. Тип голосов CatQuest не установлен.

Альтернатива — подобрать доступные голоса из библиотеки ElevenLabs и сохранить
собственную таблицу. Точное совпадение с оригиналом при этом не обещается.

## Проба собственного клона

После сообщения пользователя о разрешении автора использовать семплы создан
один собственный Instant Voice Clone рассказчика. Две короткие русские пробы
через прямой API (`eleven_v4`, `eleven_flash_v2_5`) успешно вернули аудио.
Запрос с ID нашего клона через OpenRouter без добавления ElevenLabs BYOK
вернул HTTP 400 `Unknown voice`. Это результат конкретной проверки,
а не общий запрет кастомных голосов. Исходный voice_id автора не установлен.
Конфигурация тестового клона и расход сохранены в приватном backend-репозитории.

## Источники

- [CatQuest Voices — автор, пак и поставщик синтеза](https://www.curseforge.com/wow/addons/catquest-voices).
- [CatQuest Books — рассказчик и голоса авторов книг](https://www.curseforge.com/wow/addons/catquest-books).
- [Create speech: voice_id и авторизация](https://elevenlabs.io/docs/api-reference/text-to-speech/convert).
- [Речевые модели OpenRouter и supported_voices](https://openrouter.ai/api/v1/models?output_modalities=speech).
- [Единый TTS API OpenRouter](https://openrouter.ai/docs/guides/overview/multimodal/tts).
- [Официальный анонс ElevenLabs: другие voice ID и BYOK для своих голосов](https://openrouter.ai/blog/announcements/elevenlabs-on-openrouter/).
- [List shared voices](https://elevenlabs.io/docs/api-reference/voices/voice-library/get-shared).
- [Поиск похожих голосов по аудио](https://elevenlabs.io/docs/api-reference/voices/find-similar-voices).
- [Кому доступны созданные голоса](https://elevenlabs.io/docs/help-center/product/voices/my-voices/who-has-access-to-my-voices).
- [Как поделиться голосом](https://elevenlabs.io/docs/help-center/product/voices/my-voices/how-do-i-share-a-voice).

Происхождение каталога: CatQuest Voices / CatQuest Books, Cathey
(daniilcathey), CC BY-NC-SA 4.0. Извлечённые обозначения и их индекс сохраняют
эту атрибуцию и лицензию. Аудио в каталог не включено.
