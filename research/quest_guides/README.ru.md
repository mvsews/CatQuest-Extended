# Исследование цепочек квестов

## Локальный источник Pop

Исходный snapshot популярности и расшифрованный CSV не хранятся в публичном
репозитории. Это намеренная граница: проект публикует готовые производные
отчёты и ручную проверку, но не переиздаёт raw-выгрузку стороннего сайта.

`decode_wowhead_popularity.py` не подключается к Wowhead и не скачивает данные.
Он работает только с локальным файлом, который пользователь имеет право
использовать:

    python research/quest_guides/decode_wowhead_popularity.py \
      --input C:\path\to\wowhead_popularity.compact \
      --output C:\path\to\wowhead_popularity.csv

Готовые `recalculated_quest_guides.*` и `community_validation.*` — это наши
производные исследовательские результаты, а не полный экспорт базы Wowhead.

## Техническая сложность

Скрипт analyze_technical_complexity.py читает локальный TrinityCore dump и
считает прямые связи квестов со SmartAI, area triggers, trigger scripts,
conditions, а также структурные признаки вроде ограничений и нескольких
объективов. Результат сохраняется в technical_complexity.json.

Финальный score цепочки считается скриптом
`recalculate_quest_guides.py` по локально переданному CSV:

    python research/quest_guides/recalculate_quest_guides.py \
      --popularity-csv C:\path\to\wowhead_popularity.csv

    effective_pop = pop_score * pop_trust_weight
    final = min(100, 80% base_score + 20% effective_pop + 10% technical_score)

Техническая сложность даёт до десяти баллов. Поэтому даже максимальный
Wowhead Pop не может изменить итог больше чем на 20%, а ручной trust-weight
дополнительно уменьшает только вклад Pop, не саму исходную статистику.

## Проверка мнением игроков

community_validation.ru.md — ручная проверка самых заметных Pop-цепочек по
обсуждениям игроков и гайдам. Она разделяет положительную популярность,
практическую известность, полярные отзывы и внимание из-за проблем.

community_validation.json — те же данные в машиночитаемом виде.

В каждой проверенной записи `pop_trust_weight` (0–1) вручную определяет,
сколько Pop разрешено использовать в оценке цепочки. Ноль означает, что
внимание игроков объясняется проблемой или поиском решения; единица — что
положительный интерес подтверждён. Пересчёт использует
`pop_effective_score = pop_score × pop_trust_weight`.

Проверить, что ID цепочек и Pop не устарели после нового локального пересчёта:

    python research/quest_guides/validate_community_evidence.py \
      --popularity-csv C:\path\to\wowhead_popularity.csv

Получить следующую очередь для ручной проверки самых заметных необработанных
квестов:

    python research/quest_guides/review_popularity_queue.py --limit 20 \
      --popularity-csv C:\path\to\wowhead_popularity.csv

Скрипт только печатает очередь. После изучения источников нужно добавить в
community_validation.json запись с pop_trust_weight, а затем снова запустить
recalculate_quest_guides.py.

На снимке от 2026-11-11 вручную проверены все 70/70 цепочек, а очередь
review_popularity_queue.py пуста. При обновлении Pop нужно снова пройти
валидатор: новые или изменившиеся зоны появятся в очереди как raw_default=1.0.

Ссылки на обсуждения не являются полноценным опросом: их задача — проверить,
что высокий Pop действительно соответствует живому интересу игроков и понять,
почему именно квест обсуждают.
