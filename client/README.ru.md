# CatQuest Client

Консольная прослойка для обычного WoW 3.3.5a без Lasthavens. Она скачивает
обновления `CatQuest`, готовые дорожки Voice API и кладёт их в настоящий
`Interface\AddOns\CatQuest335_ServerVoices`. Затем создаётся `Bridge.lua`,
который сообщает аддону, какие локальные серверные дорожки уже доступны.

Для `sync`, `request` и `watch` нужен Python 3.10 или новее; внешние библиотеки
для них не требуются.

## Быстрый запуск

Запустите из корня проекта:

```powershell
.\CatQuest-Client.cmd sync --wow-dir "D:\Games\World of Warcraft"
```

Для другого языка:

```powershell
.\CatQuest-Client.cmd sync --wow-dir "D:\Games\World of Warcraft" --locale enUS
```

После завершения закройте/перезапустите игру или выполните `/reload`.
Утилита обновляет только аддоны и не трогает `WTF`/SavedVariables.

## Дорожка по запросу

Если нужной готовой дорожки ещё нет в локальном кэше:

```powershell
.\CatQuest-Client.cmd request 606 DETAIL `
  --wow-dir "D:\Games\World of Warcraft"
```

После сообщения об успехе выполните `/reload`. Типы: `DETAIL` и `COMPLETE`.

## Фоновый режим

```powershell
.\CatQuest-Client.cmd watch `
  --wow-dir "D:\Games\World of Warcraft" `
  --interval 300
```

`watch` периодически подтягивает новые готовые дорожки и после сохранения
`CatQuest.lua` ищет записи в `CatQuest335DB.missing`. Это происходит после
выхода из игры или `/reload`, когда WoW записал SavedVariables. Повторный
запрос той же записи не создаётся.

## Живой companion без Lasthavens

У обычного WoW нет события для внешней программы на вызов `PlaySoundFile`,
поэтому для live-режима используется отдельный аддон-маячок:
CatQuest рисует в левом верхнем углу цветные клетки, а консольная утилита
считывает их с экрана, запрашивает дорожку у Voice API и проигрывает OGG через
`pygame`. Текст из WoW передаётся автоматически — Ctrl+C, буфер обмена и
OpenRouter не нужны.

Установите зависимости:

```powershell
python -m pip install -r client\requirements.txt
```

Запустите для указанной установки:

```powershell
.\CatQuest-Client.cmd companion `
  --wow-dir "C:\Games\World of Warcraft\_retail_"
```

Команда обновит `CatQuest`, установит `CatQuestCompanion` и начнёт слушать
экран. Если игра уже запущена, после первой установки выполните `/reload`.
Для оконного режима, где клиент WoW находится не в координатах `(0, 0)`:

```powershell
.\CatQuest-Client.cmd companion `
  --wow-dir "C:\Games\World of Warcraft\_retail_" --x 120 --y 40
```

Параметры `--x`, `--y` — левый верхний угол окна WoW на рабочем столе.
`--no-addon-update` запускает companion с уже установленным CatQuest.

Старый `AiQuestVoice\bridge.py` — это отдельный clipboard/OpenRouter-мост с
ручным Ctrl+C. Его лучше не запускать одновременно с `CatQuest Client companion`,
иначе два процесса могут проигрывать одну реплику.

## Важное ограничение

Обычный WoW не даёт Lua-аддону HTTP, доступа к диску или события «файл был
запрошен». Режим `sync` поэтому остаётся файловым кэшем: новый файл становится
виден игре после `/reload`, а ещё не готовая дорожка запрашивается командой
`request` или через сохранённый список `missing`. Для полностью автоматической
озвучки используйте `companion`; Lasthavens Addon Manager при этом не нужен.

Для тестового backend можно передать `--api http://127.0.0.1:8765`.
