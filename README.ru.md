# CatQuest Extended — CatQuest 3.3.5

[English version](README.md)

[Простая установка и информация о проекте](https://catquest.mvse.ws/)

[Публичный роадмап](ROADMAP.md)

[Исходник публичного сайта](site/)

CatQuest 3.3.5 — текущая сборка аддона CatQuest Extended для классических клиентов
World of Warcraft и самостоятельное продолжение оригинальной идеи CatQuest.
Текущая публичная сборка ориентирована на WoW 3.3.5a и добавляет озвучку
квестов, книги, lore мест, субтитры, сюжетный путеводитель и журнал зон Codex.

Папка аддона называется `CatQuest` для совместимости с WoW. Проект является
самостоятельным продолжением [оригинального CatQuest by Cathey](https://www.curseforge.com/wow/addons/catquest).

## Сайт

Исходник публичной страницы находится в [`site/`](site/). В нём только
статические frontend-файлы и публичные обложки. Рабочая страница —
[catquest.mvse.ws](https://catquest.mvse.ws/).

## Три режима работы

| Режим | Что установить | Интернет | Источник аудио |
| --- | --- | --- | --- |
| **Online** | `CatQuest` + `lasthavens-addon-manager` | Нужен | Удалённые дорожки и озвучка по запросу |
| **Local** | `CatQuest` + совместимый локальный voice-pack | Не нужен | Дорожки, установленные на компьютере |
| **Hybrid** | `CatQuest` + optional voice-pack + `CatQuest Client` | Нужен для sync/companion | Локальные дорожки и live-озвучка через внешний клиент |

Hybrid — самый гибкий режим: локальный voice-pack работает сразу, а
`CatQuest Client` умеет либо скачивать готовые серверные дорожки в локальный
addon-кэш (`sync`), либо работать как live-companion: получать текст от WoW
через пиксельный мост и проигрывать OGG внешним процессом. После нового
скачивания файлового кэша нужен `/reload`.

Подробная схема, ограничения и список следующих доработок описаны в
[документе про Hybrid-режим](docs/HYBRID-MODE.ru.md).

Аудиопаки не хранятся в этом репозитории. Совместимый пак можно скачать на
[странице проекта](https://catquest.mvse.ws/downloads/CatQuestExtended_Voices.zip):
`CatQuestExtended_Voices`. Исходный проект и лицензия указаны на странице
[CatQuest Voices в CurseForge](https://www.curseforge.com/wow/addons/catquest-voices).
Папку `CatQuestExtended_Voices` положите рядом с `CatQuest`. Файлы `.ogg` в этот
репозиторий не добавляются.

## Как предложить озвучку

Хотите помочь проекту? Используйте публичный репозиторий
[CatQuest Extended Voice Packs](https://github.com/mvsews/catquest-voice-packs):

- попросите озвучить отсутствующий квест;
- предложите готовую запись с указанием автора и прав на распространение;
- предложите новый языковой пак.

Выберите подходящий шаблон на [странице нового предложения](https://github.com/mvsews/catquest-voice-packs/issues/new/choose).
Полные аудиопаки в Git не загружаются: одобренные дорожки проверяются и
публикуются как версионные архивы на сайте проекта.

## Установка

### Online

1. Скопируйте `CatQuest` в `World of Warcraft/Interface/AddOns/`.
2. Загрузите `lasthavens-addon-manager` как распакованное расширение Chromium.
3. Откройте страницу игры через менеджер и перезагрузите её после установки или
   обновления аддона.
4. В WoW выполните `/reload`.

### Local

1. Отдельно получите совместимый локальный voice-pack и скопируйте `CatQuest`
   вместе с его папкой `CatQuestExtended_Voices` в
   `World of Warcraft/Interface/AddOns/`.
2. Запустите WoW и выполните `/reload`.

### Hybrid

1. Установите `CatQuest`; совместимый локальный voice-pack можно добавить по
   инструкции Local, если нужны его готовые дорожки.
2. Скачайте `CatQuest Client` из комплекта проекта и выполните:

   ```powershell
   .\CatQuest-Client.cmd sync --wow-dir "D:\Games\World of Warcraft"
   ```

3. Выполните `/reload`. Для дорожки, которой ещё нет на сервере, используйте
   `CatQuest-Client.cmd request <id> DETAIL` и затем снова `/reload`.

Для полностью автоматической озвучки без Lasthavens установите зависимости и
запустите companion на реальной установке WoW:

```powershell
python -m pip install -r client\requirements.txt
.\CatQuest-Client.cmd companion `
  --wow-dir "C:\Games\World of Warcraft\_retail_"
```

Он устанавливает `CatQuestCompanion`, считывает цветные клетки в левом верхнем
углу экрана, запрашивает готовую дорожку у Voice API и проигрывает её через
`pygame`. После установки в уже запущенной игре выполните `/reload`; для
оконного режима задайте координаты через `--x` и `--y`.

Для пользователя скачайте готовый [CatQuest Hybrid для Windows](https://quester.mvse.ws/downloads/CatQuest-Hybrid-Windows.zip), распакуйте архив и запустите `CatQuest-Hybrid.exe`.

Python и `pip` не нужны: они уже встроены в exe. Рядом с exe можно оставить
`CatQuest-Hybrid.cmd` — он запускает тот же standalone-клиент.

Он ждёт обычный WoW или Lasthavens Desktop, определяет активное окно и сам
переключается при закрытии или смене клиента. При запуске и затем раз в шесть
часов он проверяет обновление `CatQuest`; после обновления в игре нужен `/reload`.

Для Windows Desktop-клиента Lasthavens установите приложение по
[официальной инструкции](https://lasthavens.com/guides/windows-desktop-app),
затем запустите `CatQuest-Hybrid.exe`. Он сам найдёт `Lasthavens.exe`, установит аддоны в
`%APPDATA%\Lasthavens\AddOns` и будет обновлять `CatQuest`.

Community voice-packs могут добавлять новые голоса без изменения ядра CatQuest.

## Сборка из исходников

WoW-аддон написан на Lua и не требует компилятора. Выполните эти команды
PowerShell из корня репозитория:

```powershell
New-Item -ItemType Directory -Force dist | Out-Null

# Аддон для Online
Compress-Archive -Path CatQuest -DestinationPath dist/CatQuest-Extended-online.zip -Force

# Комплект аддонов для Local или Hybrid
# Перед упаковкой добавьте отдельно скачанную совместимую папку
# CatQuestExtended_Voices. Аудио намеренно не хранится в Git.
Compress-Archive -Path CatQuest,CatQuestExtended_Voices `
  -DestinationPath dist/CatQuest-Extended-local.zip -Force

# Браузерный менеджер; для разработки лучше загружать папку напрямую
Compress-Archive -Path lasthavens-addon-manager `
  -DestinationPath dist/CatQuest-Addon-Manager.zip -Force

# Консольная прослойка для обычного WoW (нужен Python 3.10+)
Compress-Archive -Path CatQuest-Client.cmd,CatQuest-Hybrid.cmd,client `
  -DestinationPath dist/CatQuest-Client.zip -Force
```

Для разработки загрузите папку `lasthavens-addon-manager` напрямую через
`chrome://extensions` или аналогичную страницу другого Chromium-браузера.

Быстрые проверки:

```powershell
Get-ChildItem lasthavens-addon-manager -Filter *.js -Recurse |
  ForEach-Object { node --check $_.FullName }
python -m py_compile research/quest_guides/*.py
```

## Что входит в проект

- **CatQuest Voices** — описания квестов, прогресс и завершение;
- **NPC-specific quest voices** — если один квест выдают разные NPC, локальный
  пак выбирает дорожку по реальному ID NPC, с fallback на базовый голос;
- **NPC voices** — приветствия и обычные реплики NPC в online-режиме; голос
  выбирается по ID и полу собеседника, поэтому стражники не говорят одним
  общим голосом;
- **CatQuest Books** — книги, письма, таблички и lore мест;
- **CatQuest Codex** — главы зон, места, библиотека и сюжетный путеводитель;
- очередь, история, повтор, пропуск, talking-head и cue-субтитры;
- локальные и удалённые дорожки с fallback по локали;
- локали `ruRU`, `enUS`, `zhCN`, `zhTW`, `deDE`, `frFR`, `esES`, `esMX`,
  `ptBR`, `koKR` и `itIT`.

## Как контрибьютить

### Код, Lua, UI, переводы и путеводители

Используйте этот репозиторий:

1. Сделайте fork `mvsews/catquest-extended`.
2. Создайте отдельную ветку.
3. Проверьте затронутый режим: Online, Local или Hybrid.
4. Откройте Pull Request с кратким описанием и шагами проверки.

Ошибки и небольшие предложения можно создавать через GitHub Issues этого
репозитория. Не прикладывайте персональные данные, приватные логи, токены и
локальные пути компьютера.

### Голоса и аудиопаки

Используйте отдельный публичный [репозиторий CatQuest Voice Packs](https://github.com/mvsews/catquest-voice-packs).
Там находятся каталог, схема манифеста, правила атрибуции и порядок отправки
предложений. Большие аудиоархивы не добавляйте в этот репозиторий. Для каждой
озвучки нужны лицензия, автор, источник и, если применимо, согласие диктора.

## Лицензия

Оригинальный клиентский код распространяется по MIT, если рядом с файлом не
указано иное. Производные аудио и сторонние материалы сохраняют лицензии и
атрибуцию из [NOTICE.md](NOTICE.md) и [THIRD_PARTY.md](THIRD_PARTY.md). Это
неофициальный некоммерческий community-проект. CatQuest Extended не связан с
Cathey или оригинальным проектом CatQuest, не спонсируется и не одобрен ими.
Название `CatQuest` используется для обозначения происхождения и совместимости
проекта. Проект также не связан с Blizzard Entertainment.
