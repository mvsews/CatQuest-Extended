# Публичная документация CatQuest Extended

Эта папка содержит только пользовательскую и проектную документацию. В ней нет
секретов, ключей, локальных путей, имён серверов и инструкций по развёртыванию
backend. Операционные материалы хранятся в приватном backend-репозитории.

## Документы

- [Публичный роадмап](../ROADMAP.md)
- [Установка клиента](INSTALL.ru.md)
- [Как работает Hybrid-режим](HYBRID-MODE.ru.md)
- [Лор мест](PLACES-LORE-GUIDE.ru.md)
- [План мест и инстансов](PLACES-INSTANCES-PLAN.ru.md)
- [Версии контента мест](PLACES-CONTENT-VERSIONS.ru.md)
- [Лицензии и сторонние материалы](../THIRD_PARTY.md)
- [Спецификация community voice-pack](VOICE-PACK-SPEC.md)

## Варианты клиента

- **online:** аддон `CatQuest` и Lasthavens Addon Manager; адрес backend задаётся
  отдельно оператором сервера;
- **local:** аддон `CatQuest` и [CatQuestExtended_Voices](https://catquest.mvse.ws/downloads/CatQuestExtended_Voices.zip), полностью без
  backend и браузерного расширения.
- **hybrid для обычного WoW:** аддон `CatQuest`, локальный voice-pack и
  консольный `CatQuest Client`: `sync` материализует готовые серверные дорожки
  в локальном addon-кэше, а `companion` передаёт live-текст через пиксельный
  мост и проигрывает OGG внешним процессом.

Исходный код addon/frontend находится в публичном репозитории. Backend и
операционные настройки публиковать не нужно.
