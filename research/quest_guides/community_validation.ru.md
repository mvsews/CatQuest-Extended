# Проверка популярности квестов по мнению игроков

Снимок проверки: 2026-11-11. Снимок Wowhead Pop: 2026-11-10.

## Короткий вывод

`Pop` действительно находит квесты, о которых игроки часто вспоминают, ищут информацию или сталкиваются с ними. Но это не оценка «любят ли квест»: высокий сигнал может быть вызван любимой историей, обязательным dungeon-маршрутом, сложным элитным боем, багом или раздражающим RNG.

Поэтому текущий предел влияния Wowhead в 20% оставляем. Для аддона полезно считать `★` оценкой внимания/популярности, а не обещанием, что цепочка понравится всем.

Локальная выборка содержит 70 цепочек и 438 квестов; Pop найден для 437 из 438. `pop_score` цепочки — среднее лог-нормализованных значений Pop её квестов, а не количество игроков и не процент положительных отзывов.

## Ручной вес доверия Pop

В каждой проверенной записи есть `pop_trust_weight` от 0 до 1. Он не меняет
исходную статистику Wowhead, а только определяет, сколько этой статистики можно
использовать в итоговой оценке цепочки:

`pop_effective_score = pop_score × pop_trust_weight`

- `1.0` — игроки действительно рекомендуют или любят цепочку;
- `0.5–0.6` — полезная или обязательная цепочка, но это не оценка качества сюжета;
- `0.25–0.4` — цепочку помнят, но отзывы полярны или положительный интерес не доказан;
- `0.0` — Pop в основном объясняется проблемой, багом или поиском решения.

Непроверенные зоны используют `1.0` как временный `raw_default`, чтобы ручная
проверка могла идти постепенно. После анализа зоны её вес нужно заменить явно.

## Что подтвердилось

| Место по Pop | Цепочка | Pop | Trust | Что говорят игроки | Вывод |
|---:|---|---:|---:|---|---|
| 1 | Westfall — The Defias Brotherhood | 92.59 | 1.0 | Часто называют культовой, любимой и одной из лучших цепочек; помнят финал в Deadmines. | Настоящая положительная популярность |
| 2 | Barrens — The Stagnant Oasis | 90.28 | 0.0 | Много внимания из-за случайного появления Verog, ожидания и раздражения. | Не повышаем рейтинг |
| 3 | Orgrimmar — Hidden Enemies | 85.82 | 0.6 | Регулярная Horde/Ragefire Chasm-цепочка, которую советуют не пропускать; тесная пещера и drop обсуждаются отдельно. | Умеренный вклад |
| 4 | Isle of Quel’Danas — Thalorien Dawnseeker | 81.35 | 0.25 | В найденной выборке нет достаточно сильного подтверждения именно любимой цепочки. | Почти не доверяем Pop |
| 5 | Arathi — Summoning the Princess | 77.32 | 0.35 | Помнят как масштабную, весёлую и опасную цепочку; часть игроков считает её ловушкой. | Только умеренный вклад |
| 6 | Ashenvale — Raene’s Cleansing | 76.96 | 0.5 | Рекомендуют как заметную сюжетную цепочку, но ругают за длину, беготню и случайные предметы. | Частичный вклад |
| 7 | Hillsbrad — Battle of Hillsbrad | 74.05 | 1.0 | Называют одной из лучших Classic-цепочек; последние шаги считают опасными и групповыми. | Настоящая положительная популярность |
| 8 | Durotar — The Demon Seed | 73.55 | 0.35 | Цепочку проходят намеренно ради линии Burning Blade и финального таймера, но массового статуса «любимая» не видно. | Только умеренный вклад |
| 9 | Ghostlands — The Traitor’s Destruction | 70.51 | 0.35 | Помнят как кульминацию Ghostlands, но обсуждения в основном про сложную комнату и необходимость группы. | Только умеренный вклад |
| 10 | Sholazar — A Hero’s Burden | 69.61 | 0.4 | Часто ищут из-за выбора фракции и последствий для маунта. | Частичный вклад |
| 11 | Storm Peaks — The Iron Colossus | 69.33 | 0.0 | Обсуждения в основном о баге с транспортом и невозможности пройти. | Не повышаем рейтинг |
| — | Grizzly Hills — Free at Last | 60.30 | 0.0 | В основном видны страницы базы и walkthrough; независимого положительного мнения мало. | Не повышаем рейтинг |

## Второй полу-ручной проход по высоким raw Pop

После первого прохода проверены ещё 12 цепочек с наиболее заметными отдельными
квестами. Здесь Pop чаще оказался сигналом сложности, маршрутизации или
необычной механики, поэтому полные `1.0` получили только цепочки с более
убедительным сюжетным или интерактивным интересом.

| Цепочка | Самый заметный квест | Raw Pop | Trust | Решение |
|---|---|---:|---:|---|
| Silverpine — The Weaver | The Weaver | 48 | 0.2 | Запоминаемая сложность, но не доказанная любовь |
| Burning Steppes — Broodling Essence | Broodling Essence | 46 | 0.35 | Необычный предмет, но сильная dungeon/guide-составляющая |
| Blasted Lands — The Stones That Bind Us | The Stones That Bind Us | 44 | 0.5 | Основная цепочка и необычная механика камней |
| Darkshore — A Lost Master | A Lost Master | 42 | 0.3 | Много внимания из-за cave-run, смертей и багов |
| Howling Fjord — We Can Rebuild It | We Can Rebuild It | 40 | 0.5 | Интерактивное продолжение, но мало прямых рекомендаций |
| Un’Goro — The Videre Elixir / Linken | The Videre Elixir | 40 | 0.7 | Узнаваемая и необычная сюжетная цепочка |
| Zul’Drak — Drakuru | Fuel for the Fire / So Far, So Bad | 39 | 0.7 | Длинная сюжетная линия с реальным прогрессом зоны |
| Loch Modan — In Defense of the King’s Lands | In Defense of the King’s Lands | 38 | 0.3 | Ранний маршрут, внимание в основном из-за опасности |
| Swamp of Sorrows — Pool of Tears | Pool of Tears | 36 | 0.0 | Навигационная фрустрация, Pop не повышает интересность |
| Silithus — The Spirits of Southwind | The Spirits of Southwind | 36 | 0.2 | Нишевый и сложный эпизод, мало положительной выборки |
| Tirisfal — The Prodigal Lich Returns | The Prodigal Lich Returns | 35 | 0.5 | Узнаваемая Horde-история, но в основном гайды |
| Wetlands — The Cursed Crew | The Cursed Crew | 33 | 0.0 | В основном предупреждения об опасности и совет пропустить |

Источники второго прохода: [The Weaver](https://www.reddit.com/r/wowhardcore/comments/130fgvj/does_anyone_actually_do_the_quest_achievement_the/), [Broodling Essence](https://www.wowhead.com/classic/quest=4726/broodling-essence), [The Stones That Bind Us](https://warcraft.wiki.gg/wiki/The_Stones_That_Bind_Us), [A Lost Master](https://www.wowhead.com/classic/quest=993/a-lost-master), [The Videre Elixir и цепочка Linken](https://theforeverguides.com/quests/linkens-quest-chain/), [Drakuru в Zul’Drak](https://warcraft.wiki.gg/wiki/Zul%27Drak_quests), [In Defense of the King’s Lands](https://warcraft.wiki.gg/wiki/In_Defense_of_the_King%27s_Lands), [Pool of Tears](https://www.wowhead.com/classic-ptr/quest=1424/pool-of-tears), [The Cursed Crew](https://warcraft.wiki.gg/wiki/The_Cursed_Crew_%28Classic%29).

## Третий проход по следующей группе

Здесь проверены цепочки с raw Pop примерно от 32 до 25. Основной результат:
высокий raw Pop часто связан с тем, что игроки ищут координаты, дроп или
решение бага; сильный положительный вес оставлен только для цепочек с заметной
историей.

| Цепочка | Ключевой квест | Raw Pop | Trust | Решение |
|---|---|---:|---:|---|
| Alterac — Dark Council | Dark Council | 32 | 0.25 | Слишком мало прямых положительных отзывов |
| Mulgore — Rites of the Earthmother | Rites of the Earthmother | 31 | 0.5 | Узнаваемая духовная стартовая линия |
| Stranglethorn — Saving Yenniku | Saving Yenniku | 31 | 0.25 | Необычная механика, но много старых bug/how-to обсуждений |
| Netherstorm — A Not-So-Modest Proposal | A Not-So-Modest Proposal | 30 | 0.25 | В основном локация, батарея и баги |
| Stonetalon — Goblin Invaders | Goblin Invaders | 30 | 0.5 | Реальная Horde-цепочка, но стартовый kill-and-return |
| Dun Morogh — Frostmane Hold | Frostmane Hold | 30 | 0.3 | Запоминаемая пещера, не сюжетный фаворит |
| Hellfire — Disrupt Their Reinforcements | Disrupt Their Reinforcements | 28 | 0.2 | Интерактивный портал, но много friction-поиска |
| Eastern Plaguelands — Fragments of the Past | Fragments of the Past | 28 | 0.5 | Длинный межзонный маршрут с Dire Maul |
| Western Plaguelands — Scarlet Subterfuge | Scarlet Subterfuge | 28 | 0.8 | Сильная часть линии Тириона и Тэлена |
| Dustwallow — Secondhand Diving Gear | Secondhand Diving Gear | 27 | 0.1 | Подводный поиск и проблемы появления предметов |
| Elwynn — Jasperlode and starter mines | The Jasperlode Mine | 27 | 0.25 | Опасная стартовая разведка, не отдельная история |
| Dalaran — The Sunreaver Plan | The Sunreaver Plan | 26 | 0.1 | Почти чистая проблема дропа/поиска NPC |
| Tanaris — Rise of the Silithid | The Scrimshank Redemption | 26 | 0.5 | Узнаваемая межзонная линия и необычная пещера |
| Dragonblight — Wyrmrest route | Heated Battle | 26 | 0.3 | История зоны есть, но топовый шаг довольно обычный |
| Azshara — The Name of the Beast | The Name of the Beast | 26 | 0.6 | Связная линия Лорамуса и Felbane |
| Moonglade — A Reliquary of Purity | A Reliquary of Purity | 25 | 0.4 | Интересный маршрут, но много dungeon-инструкций |
| Icecrown — Crusader Bridenbrad | A Tale of Valor | 25 | 0.9 | Подтверждённая запоминающаяся история WotLK |

## Четвёртый проход: raw Pop 22–17

Проверен следующий блок из очереди. Здесь особенно хорошо видно, почему один
Pop нельзя трактовать как «квест понравился»: рядом стоят сильная линия
спасения в Felwood, мистическая цепочка в Winterspring и обычные сборы,
аттюны, почтовые поручения и поиск редкого дропа.

| Цепочка | Ключевой квест | Raw Pop | Trust | Решение |
|---|---|---:|---:|---|
| Zangarmarsh — Gathering the Reagents | Gathering the Reagents | 22 | 0.15 | Обычный сбор реагентов, почти без самостоятельной истории |
| Felwood — A Strange Red Key | A Strange Red Key | 22 | 0.85 | Сильная компактная линия спасения, эскорта и мести |
| Deadwind Pass — Digging Up the Past | Digging Up the Past | 21 | 0.15 | В основном Karazhan/Nightbane-аттюн и поиск объекта |
| Blade’s Edge — Harvesting the Fel Ammunition | Harvesting the Fel Ammunition | 20 | 0.25 | Интересный контекст Death’s Door, но шаг в основном сборочный |
| Eversong — The Dwarven Spy | The Dwarven Spy | 20 | 0.4 | Ранний шпионский эпизод с интерактивной целью |
| Desolace — Search for Tyranis | Search for Tyranis | 19 | 0.7 | Связная трагическая история с коррупцией и эскортом |
| Feralas — Delivering the Relic | Delivering the Relic | 19 | 0.45 | Узнаваемая археологическая цепочка, но без массового статуса фаворита |
| Azuremyst — Totem of Coo | Totem of Coo | 18 | 0.65 | Необычная интерактивная духовная линия с последовательностью тотемов |
| Terokkar — What Are These Things? | What Are These Things? | 18 | 0.3 | Сюжетная ветка есть, но верхний шаг — обычная доставка |
| Thunder Bluff — Un’Goro Soil | Un’Goro Soil | 18 | 0.1 | Реагенты и репутационная польза, не история |
| Redridge — Messenger to Darkshire | Messenger to Darkshire | 18 | 0.05 | Длинная пересылка писем и маршрутная полезность |
| Nagrand — Vision of the Dead | Vision of the Dead | 17 | 0.35 | Необычная награда, но Pop сильно подпитан редким дропом |
| Winterspring — The Crystal of Zin-Malor | The Crystal of Zin-Malor | 17 | 0.65 | Хороший мистический лор и необычный предмет |
| Thousand Needles — Goblin Sponsorship | Goblin Sponsorship | 17 | 0.55 | Длинная узнаваемая гоблинская линия с инженерными эпизодами |
| Searing Gorge — The Torch of Retribution | The Torch of Retribution | 17 | 0.45 | Длинная цепочка со скриптовым шагом, но с сильной маршрутной составляющей |

Источники этого прохода: [A Strange Red Key](https://questing.wiki/wow-forever/quests/5202/), [Digging Up the Past](https://www.lootxphub.com/karazhan-quest-guide-attunement-nightbane-summoning-and-violet-signet-rings/), [The Dwarven Spy](https://warcraft.wiki.gg/wiki/Eversong_Woods_quests), [Search for Tyranis](https://warcraft.wiki.gg/wiki/Desolace_storyline_%28Classic%29), [Totem of Coo](https://www.wowhead.com/tbc/quest=9539/totem-of-coo), [Vision of the Dead](https://www.wowhead.com/tbc/quest=10252/vision-of-the-dead), [The Crystal of Zin-Malor](https://www.wowhead.com/classic/quest=5253/the-crystal-of-zin-malor), [Goblin Sponsorship](https://warcraft.wiki.gg/wiki/Thousand_Needles_quests) и [The Torch of Retribution](https://eternadex.com/en/quests/3453/).

## Пятый проход: raw Pop 17–12

Здесь закрыты последние зоны, в которых ещё оставался заметный raw Pop.
Особенно выделяются Oronok/Ar'tor, Windsor и Titan-диски: это уже кандидаты
на сюжетный путеводитель, а не просто популярные страницы с подсказками.

| Цепочка | Ключевой квест | Raw Pop | Trust | Решение |
|---|---|---:|---:|---|
| The Hinterlands — Rhapsody’s Tale | Rhapsody’s Tale | 17 | 0.6 | Узнаваемое межзонное исследование с выходом к храму Атал’ай |
| Badlands — A Sign of Hope / Prospect of Faith | A Sign of Hope | 17 | 0.65 | Длинная линия дворфийского лора и Uldaman |
| Shadowmoon Valley — The Cipher of Damnation | The Second Fragment Recovered | 16 | 0.9 | Большая семейная история Орoнока и его сыновей |
| Zangarmarsh — The Second Sample | The Second Sample | 15 | 0.2 | Рутинный сбор образцов на фоне полезной Cenarion-ветки |
| Uldaman — The Platinum Discs | Seeing What Happens | 15 | 0.65 | Титановый лор и интерактивная сцена у ворот Uldum |
| Stormwind — The Great Masquerade | The Great Masquerade | 15 | 0.85 | Иконическая скриптовая кульминация линии Onyxia |
| Teldrassil — Crown of the Earth | Crown of the Earth | 15 | 0.35 | Узнаваемый стартовый маршрут, но не сильная самостоятельная история |
| Desolace — Nothing But The Truth | Nothing But The Truth | 15 | 0.1 | В основном поиск странствующей цели и дропа |
| Borean Tundra — Farshire investigation | Pernicious Evidence | 14 | 0.35 | Локальное расследование с полезностью для маршрута прокачки |
| Darnassus — March of the Silithid | Calm Before the Storm | 13 | 0.55 | Связная межзонная линия расследования угрозы силитидов |

Источники этого прохода: [Rhapsody’s Tale](https://www.wowhead.com/classic/quest=1469/rhapsodys-tale), [A Sign of Hope](https://theforeverera.com/en/quests/720/), [The Cipher of Damnation](https://www.wowhead.com/tbc/quest=10541/the-cipher-of-damnation-the-second-fragment-recovered), [The Platinum Discs](https://questing.wiki/wow-forever/quests/2439/), [The Great Masquerade](https://www.wowhead.com/classic/quest=6403/the-great-masquerade), [Crown of the Earth](https://forever-xp.com/quests/929/), [Nothing But The Truth](https://www.wowhead.com/classic/quest=1383/nothing-but-the-truth), [Borean Tundra investigation](https://www.wow-pro.com/source-code-borean-tundra-alliance/) и [Calm Before the Storm](https://forever-xp.com/quests/4510/).

## Финальная проверка: оставшиеся зоны

Последние четыре записи тоже переведены на ручной вес. Так в отчёте больше
нет зон, которые молча используют необработанный raw_default=1.0.

| Цепочка | Raw Pop | Trust | Решение |
|---|---:|---:|---|
| Undercity — Seeping Corruption | 9 | 0.4 | Маленькая, но запоминающаяся мрачная развязка |
| Silvermoon — Allegiance to the Horde | 7 | 0.2 | Важный переход фракции, но одно короткое поручение |
| Shattrath — The Tempest Key | 6 | 0.15 | В основном аттюн и доступ к Heroic/raid-прогрессии |
| Ironforge — A Donation of Runecloth | 0 | 0.0 | Репутационный turn-in, не сюжетный материал |

Источники: [Seeping Corruption](https://www.wowhead.com/classic/quest=3570/seeping-corruption), [Allegiance to the Horde](https://www.wowhead.com/tbc/quest=9627/allegiance-to-the-horde), [The Tempest Key](https://warcraft.wiki.gg/wiki/The_Tempest_Key) и [A Donation of Runecloth](https://wowforever.gg/en/atlas/knowledge/quests/a-donation-of-runecloth-q7824/).

Все источники и полные ID сохранены в [community_validation.json](community_validation.json).

## Как использовать это в оценке

1. Оставить Pop вспомогательным фактором максимум на 20%, как сейчас.
2. Для `★` использовать подпись вроде «интерес по данным Wowhead», чтобы не смешивать популярность и качество.
3. Не штрафовать цепочку автоматически за негативные отзывы: «ненавижу этот квест» всё равно означает, что он запоминается и о нём спрашивают. Но в исследовательских данных хранить тип сигнала: `positive`, `utility`, `polarized`, `problem_driven`, `insufficient`.
4. Для будущего «сюжетного путеводителя» отбирать в первую очередь `confirmed_positive` и `confirmed_polarized`; `problem_driven` оставлять как предупреждение или отдельный список, а не как «самое интересное».
5. Для следующих пересчётов сравнивать не только цепочку целиком, но и отдельные квесты: один очень высокий Pop, например The Demon Seed, может заметно поднимать среднее цепочки.

Подробные машиночитаемые результаты и URL источников находятся в [community_validation.json](community_validation.json).

## Источники

- [Wowhead: списки квестов WotLK](https://www.wowhead.com/wotlk/quests) — исходный сигнал Pop.
- [The Defias Brotherhood — обсуждение цепочек](https://www.reddit.com/r/classicwow/comments/182mwe2), [любимые квесты Classic](https://www.reddit.com/r/classicvanillawow/comments/1u9kp4h/your_favourite_quest_from_classicvanilla_wow/).
- [The Stagnant Oasis на Wowhead](https://www.wowhead.com/classic/quest=877/the-stagnant-oasis) и обсуждение проблемного появления Verog на [Reddit](https://www.reddit.com/r/wowhardcore/comments/1v8vps/verog_the_dervished_is_bugged/).
- [Hidden Enemies на Wowhead](https://www.wowhead.com/classic/quest=5726/hidden-enemies) и [гайд по Ragefire Chasm](https://www.warcrafttavern.com/wow-classic/guides/ragefire-chasm).
- [Summoning the Princess на Wowhead](https://www.wowhead.com/classic/quest=656/summoning-the-princess) и обсуждение больших цепочек с dungeon-этапами на [Reddit](https://www.reddit.com/r/classicwow/comments/1x31tki/massive_multi_zone_encompassing_quest_chains_especially_ones_involving_dungeons_deserve_better_rewards/).
- [Raene’s Cleansing на Wowhead](https://www.wowhead.com/classic/quest=1046/raenes-cleansing) и рекомендации цепочек для новичков на [Reddit](https://www.reddit.com/r/classicwow/comments/1ph13je/questline_suggestions_for_new_players/).
- [Battle of Hillsbrad в Warcraft Wiki](https://warcraft.wiki.gg/wiki/Battle_of_Hillsbrad_quest_chain) и обсуждение любимых квестов на [Reddit](https://www.reddit.com/r/classicvanillawow/comments/1u9kp4h/your_favourite_quest_from_classicvanilla_wow/).
