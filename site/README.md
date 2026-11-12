# CatQuest Extended website

This directory contains the public landing page source for CatQuest Extended.
It contains only static frontend files and public cover images. It does not
contain private service code, secrets, deployment settings, server data, or
generated audio archives.

## Local preview

From the repository root:

```powershell
python -m http.server 8765 --directory site
```

Open <http://127.0.0.1:8765/> in a browser.

The page uses the public CatQuest service URLs for installation links and audio
previews. Change those URLs only when the public service address changes.

## Public progress snapshot

`progress.json` is a generated, safe aggregate snapshot used by the landing
page. It contains quest counts, coverage by sector and category, supported
locales, and priority zones where community help is useful. It does not contain
quest text, audio, server paths, player data, credentials, or the private
quest-level database.

The detailed progress database is built locally in the private backend from the
read-only AzerothCore/TrinityCore inspection catalog and the current production
track index. Refresh the snapshot only through the private progress-report
tool, then review the JSON before committing it to the public repository.

## Publishing

Keep `site/index.html` as the public page source of truth. The HTML and the two
cover images are copied to the public web directory during a release. Never add
`.env` files, credentials, private server configuration, databases, generated
audio, or private operational notes to this directory.

## Русская версия

`site/` — исходник публичной статической страницы CatQuest Extended. Здесь нет
кода закрытых сервисов, секретов, баз данных и конфигурации сервера.
