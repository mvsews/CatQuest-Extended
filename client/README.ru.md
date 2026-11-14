# CatQuest Client

Консольная прослойка для обычного WoW 3.3.5a и Lasthavens Desktop. Она скачивает
обновления `CatQuest`, готовые дорожки Voice API и кладёт их в настоящий
`Interface\AddOns\CatQuest335_ServerVoices` или в `Lasthavens\AddOns\CatQuest335_ServerVoices`.
Затем создаётся `Bridge.lua`,
который сообщает аддону, какие локальные серверные дорожки уже доступны.

Для `sync`, `request` и `watch` нужен Python 3.10 или новее; внешние библиотеки
для них не требуются.

Сообщения утилиты автоматически выбираются по языку Windows: для `ru-*` —
русский, для остальных систем — английский. Для проверки можно временно задать
`CATQUEST_LANG=ru` или `CATQUEST_LANG=en`.

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

## Lasthavens Desktop

Electron-клиент сам подхватывает локальные аддоны из
`%APPDATA%\Lasthavens\AddOns`. Поэтому базовый `CatQuest` и локальный
voice-pack можно скопировать туда вручную — отдельная утилита для этого не
нужна. Для серверного кэша или live-озвучки используйте тот же клиент с
`--lasthavens-dir`:

Для готового запуска скачайте [CatQuest Hybrid для Windows](https://quester.mvse.ws/downloads/CatQuest-Hybrid-Windows.zip), распакуйте архив и запустите `CatQuest-Hybrid.exe`. Python и `pip` не нужны: они уже встроены в exe.

Если запускаете клиент из исходников, для серверного кэша или live-озвучки
используйте Python 3.10+ и зависимости из `client/requirements.txt`:

```powershell
.\CatQuest-Client.cmd sync `
  --lasthavens-dir "$env:APPDATA\Lasthavens"

python -m pip install -r client\requirements.txt
.\CatQuest-Client.cmd companion `
  --lasthavens-dir "$env:APPDATA\Lasthavens" `
  --no-addon-update --x 0 --y 0
```

`--x` и `--y` — координаты левого верхнего угла окна Lasthavens на рабочем
столе. Для этого режима `watch` не используется: Desktop не создаёт обычные
WoW `WTF`/SavedVariables. После установки или обновления аддона перезагрузите
игру через меню `AddOns` → `Reload game`.

## Один запуск для любого клиента

Для пользователя можно использовать `CatQuest-Hybrid.cmd`. Он не требует
пути к игре: ждёт запуск обычного WoW или Lasthavens Desktop, определяет
активное окно и сам выбирает папку аддонов. Если игру закрыть, клиент ждёт
следующий запуск; при переключении между клиентами он переподключается сам.
При запуске и затем раз в шесть часов он проверяет обновление `CatQuest`; после
обновления в игре нужен `/reload`.

```powershell
.\CatQuest-Hybrid.cmd
```

Если одновременно запущены оба клиента, выбирается тот, чьё окно сейчас
активно. Для диагностики можно ограничить поиск:

```powershell
.\CatQuest-Hybrid.cmd --lasthavens-dir "$env:APPDATA\Lasthavens"
```

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
