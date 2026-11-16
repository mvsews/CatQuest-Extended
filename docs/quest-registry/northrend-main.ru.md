# Реестр основных цепочек Нордскола

> Сформирован: `2026-11-14T09:55:32+00:00`; каталог: `azerothcore`, клиент `3.3.5a`.
> В WotLK нет одной линейной кампании: есть два стартовых направления, фракционные хабы и общие сюжетные ветки.
> Поэтому реестр разделяет проверенные приоритетные маршруты и полный локальный список story-квестов по зонам.

## Сводка

- Проверенных цепочек/маршрутов: **11**.
- Уникальных квестов в них: **196**; озвучено **57**, не озвучено **139**.
- Story-квестов вне этих срезок: **1112**; озвучено **1**, не озвучено **1111**.

## Проверенные маршруты

| Маршрут | Фракция | Объём | Озвучено | Нет голоса | Покрытие |
|---|---|---:|---:|---:|---:|
| Borean Tundra / Farshire investigation | Alliance | 8 | 0 | 8 | 0.0% |
| Storm Peaks / The Iron Colossus | Alliance/Horde | 7 | 0 | 7 | 0.0% |
| Dalaran / The Sunreaver Plan | Alliance/Horde | 1 | 0 | 1 | 0.0% |
| Dragonblight / Wyrmrest and Heated Battle route | Alliance/Horde | 15 | 0 | 15 | 0.0% |
| Zul'Drak / Drakuru chain | Alliance/Horde | 10 | 0 | 10 | 0.0% |
| Icecrown / Crusader Bridenbrad | Alliance | 12 | 0 | 12 | 0.0% |
| Sholazar Basin / A Hero's Burden | Alliance/Horde | 18 | 0 | 18 | 0.0% |
| Howling Fjord / We Can Rebuild It | Alliance/Horde | 35 | 0 | 35 | 0.0% |
| Grizzly Hills / Free at Last | Alliance/Horde | 8 | 0 | 8 | 0.0% |
| Wrathgate / Undercity / Storm Peaks conclusion | Alliance/Horde | 23 | 0 | 23 | 0.0% |
| Death knight starting story | Death Knight | 59 | 57 | 2 | 96.6% |

По текущему проверенному срезу:
- `Alliance`: 20 квестов, озвучено 0, нет голоса 20.
- `Horde`: отдельной проверенной срезки пока нет; ордынские хабы и shared-цепочки уже перечислены ниже.
- `Alliance/Horde`: 117 квестов, озвучено 0, нет голоса 117.
- `Death Knight`: 59 квестов, озвучено 57, нет голоса 2.

## Story-реестр по зонам

| Зона | Story-квестов | Озвучено | Нет голоса | Покрытие |
|---|---:|---:|---:|---:|
| Борейская тундра (`Borean Tundra`) | 219 | 0 | 219 | 0.0% |
| Ревущий фьорд (`Howling Fjord`) | 192 | 0 | 192 | 0.0% |
| Драконий Погост (`Dragonblight`) | 203 | 0 | 203 | 0.0% |
| Седые холмы (`Grizzly Hills`) | 131 | 1 | 130 | 0.8% |
| Зул'Драк (`Zul'Drak`) | 95 | 0 | 95 | 0.0% |
| Низина Шолазар (`Sholazar Basin`) | 74 | 0 | 74 | 0.0% |
| Грозовая Гряда (`The Storm Peaks`) | 116 | 0 | 116 | 0.0% |
| Ледяная Корона (`Icecrown`) | 214 | 0 | 214 | 0.0% |
| Даларан (`Dalaran`) | 2 | 0 | 2 | 0.0% |

## Очередь по фракционному признаку

Это техническая подсказка из `allowable_races`; `Shared/unknown` требует ручной проверки по NPC и условиям квеста.

| Зона | Альянс | Орда | Общие/неясные |
|---|---:|---:|---:|
| Борейская тундра | 68 | 82 | 69 |
| Ревущий фьорд | 94 | 63 | 35 |
| Драконий Погост | 76 | 80 | 47 |
| Седые холмы | 56 | 43 | 32 |
| Зул'Драк | 0 | 0 | 95 |
| Низина Шолазар | 0 | 0 | 74 |
| Грозовая Гряда | 25 | 20 | 71 |
| Ледяная Корона | 59 | 61 | 94 |
| Даларан | 1 | 1 | 0 |

## Фракционные маршруты

Хабы ниже фиксируют, где начинается и продолжается фракционная ветка; сами квесты могут переходить в общие цепочки Нордскола.

| Ветка | Основные хабы | Проверенные цепочки в текущем реестре |
|---|---|---|
| Alliance | Borean Tundra: Valiance Keep → Amber Ledge → Coldarra → Fizzcrank Airstrip → Bixie; Howling Fjord: Valgarde → Explorer's League Outpost → Westguard Keep → Kamagua → Fort Wildervar; Dragonblight: Star's Rest → Wintergarde Keep → Wyrmrest Temple → Obsidian Dragonshrine → The Crystal Vice; Grizzly Hills: Amberpine Lodge → Westfall Brigade Encampment → Drakil'jin Ruins → Thor Modan; The Storm Peaks: K3 → Brunnhildar Village → Dun Niffelem → Thorim → Frosthold; Icecrown: Argent Vanguard → Skybreaker (Gunship) → The Shadow Vault → Blackwatch; Dalaran: The Silver Enclave | guide-zone-3537, guide-zone-210 |
| Horde | Borean Tundra: Warsong Hold → Amber Ledge → Coldarra → Bor'gorok Outpost → Taunka'le Village; Howling Fjord: Vengeance Landing → New Agamand → Kamagua → Camp Winterhoof; Dragonblight: Agmar's Hammer → Venomspite → Wyrmrest Temple → Obsidian Dragonshrine → The Crystal Vice; Grizzly Hills: Conquest Hold → Camp Oneqwah → Drakil'jin Ruins → Thor Modan; The Storm Peaks: K3 → Brunnhildar Village → Dun Niffelem → Thorim → Grom'arsh Crash Site; Icecrown: Argent Vanguard → Orgrim's Hammer (Gunship) → The Shadow Vault → Blackwatch; Dalaran: The Sunreaver's Sanctuary | пока нет отдельной срезки |
| Shared | Zul'Drak: The Argent Stand; Sholazar Basin: Nesingwary Base Camp → River's Heart; The Storm Peaks: Dun Niffelem → Ulduar; Icecrown: Argent Tournament Grounds | guide-zone-65, guide-zone-66, guide-zone-67, guide-zone-3711, guide-zone-394, guide-zone-4395, guide-zone-495, wrath-central-cinematics |

## Маршруты из Wowhead

Реестр сверяет порядок хабов с фракционными leveling-гайдами Wowhead. Это порядок прохождения по хабам, а не утверждение, что каждый квест внутри хаба образует одну линейную цепь.

| Зона | Фракция | Порядок хабов | Ветка |
|---|---|---|---|
| Borean Tundra | Alliance | [Valiance Keep → Amber Ledge → Coldarra → Fizzcrank Airstrip → Bixie](https://www.wowhead.com/wotlk/guide/borean-tundra-alliance-best-quest-leveling-route) | — |
| Borean Tundra | Horde | [Warsong Hold → Amber Ledge → Coldarra → Bor'gorok Outpost → Taunka'le Village](https://www.wowhead.com/wotlk/guide/borean-tundra-horde-best-quest-leveling-route) | — |
| Howling Fjord | Alliance | [Valgarde → Explorer's League Outpost → Westguard Keep → Kamagua → Fort Wildervar](https://www.wowhead.com/wotlk/guide/howling-fjord-alliance-best-quest-leveling-route) | — |
| Howling Fjord | Horde | [Vengeance Landing → New Agamand → Kamagua → Camp Winterhoof](https://www.wowhead.com/wotlk/guide/howling-fjord-horde-best-quest-leveling-route) | — |
| Dragonblight | Alliance | [Star's Rest → Wintergarde Keep → Wyrmrest Temple → Obsidian Dragonshrine → The Crystal Vice](https://www.wowhead.com/wotlk/guide/dragonblight-alliance-best-quest-leveling-route) | — |
| Dragonblight | Horde | [Agmar's Hammer → Venomspite → Wyrmrest Temple → Obsidian Dragonshrine → The Crystal Vice](https://www.wowhead.com/wotlk/guide/dragonblight-horde-best-quest-leveling-route) | — |
| Grizzly Hills | Alliance | [Amberpine Lodge → Westfall Brigade Encampment → Drakil'jin Ruins → Thor Modan](https://www.wowhead.com/wotlk/guide/grizzly-hills-alliance-best-quest-leveling-route) | — |
| Grizzly Hills | Horde | [Conquest Hold → Camp Oneqwah → Drakil'jin Ruins → Thor Modan](https://www.wowhead.com/wotlk/guide/grizzly-hills-horde-best-quest-leveling-route) | — |
| Zul'Drak | Alliance | [Ebon's Watch → Light's Breach → The Argent Stand → Kolramas → Zim'torga](https://www.wowhead.com/wotlk/guide/zuldrak-alliance-best-quest-leveling-route) | — |
| Zul'Drak | Horde | [Ebon's Watch → Light's Breach → The Argent Stand → Kolramas → Zim'torga](https://www.wowhead.com/wotlk/guide/zuldrak-horde-best-quest-leveling-route) | — |
| Sholazar Basin | Alliance | [Nesingwary Base Camp → River's Heart → Avatar of Freya](https://www.wowhead.com/wotlk/guide/sholazar-basin-alliance-best-quest-leveling-route) | The Oracles / Frenzyheart Tribe |
| Sholazar Basin | Horde | [Nesingwary Base Camp → River's Heart → Avatar of Freya](https://www.wowhead.com/wotlk/guide/sholazar-basin-horde-best-quest-leveling-route) | The Oracles / Frenzyheart Tribe |
| The Storm Peaks | Alliance | [K3 → Brunnhildar Village → Dun Niffelem → Thorim → Frosthold](https://www.wowhead.com/wotlk/guide/the-storm-peaks-alliance-best-quest-leveling-route) | — |
| The Storm Peaks | Horde | [K3 → Brunnhildar Village → Dun Niffelem → Thorim → Grom'arsh Crash Site](https://www.wowhead.com/wotlk/guide/the-storm-peaks-horde-best-quest-leveling-route) | — |
| Icecrown | Alliance | [Argent Vanguard → Skybreaker (Gunship) → The Shadow Vault → Blackwatch](https://www.wowhead.com/wotlk/guide/icecrown-alliance-best-quest-leveling-route) | — |
| Icecrown | Horde | [Argent Vanguard → Orgrim's Hammer (Gunship) → The Shadow Vault → Blackwatch](https://www.wowhead.com/wotlk/guide/icecrown-horde-best-quest-leveling-route) | — |

## Как читать статусы

- `voiced` — в локальном прогрессе есть русская озвучка квеста.
- `missing` — текст/квест есть в каталоге, но русской дорожки нет.
- `unassigned_story_quests` в JSON — сюжетные квесты зоны, которые не попали в текущие проверенные маршруты; это очередь на ручную разметку, а не автоматически объявленные побочными.

Источники маршрутов: `backend/voice_priority.json`; локальный каталог: `backend/quest_db/quests.sqlite3`; покрытие: `backend/progress.sqlite3` и локальный voice cache.
