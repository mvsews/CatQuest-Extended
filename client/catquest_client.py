#!/usr/bin/env python3
"""CatQuest Client: local and live bridge for ordinary WoW 3.3.5a installs.

The game client cannot make HTTP requests itself.  ``sync`` turns ready server
tracks into real files in Interface/AddOns and writes the small Bridge.lua
manifest that CatQuest reads on the next /reload.  ``companion`` uses an
addon-rendered screen-pixel protocol and plays on-demand OGG outside WoW, so
it does not depend on a PlaySoundFile notification that the client cannot
provide.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import queue
import re
import shutil
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path
from typing import Any, Iterable


for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass


APP_VERSION = "0.1.0"
DEFAULT_API = "https://quester.mvse.ws"
CLIENT_VERSION = "3.3.5a"
ADDON_FOLDER = "CatQuest"
SERVER_FOLDER = "CatQuest335_ServerVoices"
COMPANION_FOLDER = "CatQuestCompanion"
SUPPORTED_LOCALES = {
    "ruRU",
    "enUS",
    "zhCN",
    "zhTW",
    "deDE",
    "frFR",
    "esES",
    "esMX",
    "ptBR",
    "koKR",
    "itIT",
}
QUEST_TYPES = {"DETAIL", "COMPLETE"}
MAX_DOWNLOAD_BYTES = 256 * 1024 * 1024
MAX_ZIP_FILES = 32_000
MAX_ZIP_MEMBER_BYTES = 64 * 1024 * 1024
PIXEL_COLS = 96
PIXEL_ROWS = 8
PIXEL_CELL = 4
PIXEL_HEADER = 25
PIXEL_CHUNK_BYTES = ((PIXEL_COLS * PIXEL_ROWS - PIXEL_HEADER) * 3) // 2
MAX_COMPANION_CHUNKS = 128
MAX_COMPANION_PAYLOAD = PIXEL_CHUNK_BYTES * MAX_COMPANION_CHUNKS


class ClientError(RuntimeError):
    """An expected, user-facing utility error."""


def log(message: str) -> None:
    print(f"[CatQuest] {message}", flush=True)


def normalize_api(value: str) -> str:
    origin = value.strip().rstrip("/")
    parsed = urllib.parse.urlparse(origin)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ClientError(f"некорректный API URL: {value}")
    if parsed.query or parsed.fragment:
        raise ClientError("API URL не должен содержать query или fragment")
    return origin


def normalize_locale(value: str) -> str:
    locale = value.strip()
    if locale not in SUPPORTED_LOCALES:
        raise ClientError(
            f"неподдерживаемая локаль {locale!r}; доступно: "
            + ", ".join(sorted(SUPPORTED_LOCALES))
        )
    return locale


def parse_version(text: str | None) -> tuple[int, ...]:
    values = [int(part) for part in re.findall(r"\d+", str(text or ""))]
    return tuple(values or [0])


def same_or_newer(left: str | None, right: str | None) -> bool:
    """Return whether ``left`` is at least ``right`` by numeric version."""

    return parse_version(left) >= parse_version(right)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_zip_member(name: str) -> Path:
    normalized = name.replace("\\", "/")
    path = Path(normalized)
    if (
        not normalized
        or normalized.startswith("/")
        or ":" in normalized
        or any(part in {"", ".", ".."} for part in path.parts)
    ):
        raise ClientError(f"опасный путь в ZIP: {name}")
    return path


def write_atomic(path: Path, data: bytes | str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = data.encode("utf-8") if isinstance(data, str) else data
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except OSError:
            pass
        raise


def read_json(path: Path, fallback: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return fallback


class Api:
    def __init__(self, origin: str, timeout: float = 30.0) -> None:
        self.origin = normalize_api(origin)
        self.timeout = timeout

    def url(self, path: str, **query: Any) -> str:
        if not path.startswith("/"):
            path = "/" + path
        encoded = urllib.parse.urlencode(
            [(key, value) for key, value in query.items() if value is not None]
        )
        return self.origin + path + ("?" + encoded if encoded else "")

    def get(self, path: str, **query: Any) -> tuple[int, str, bytes]:
        request = urllib.request.Request(
            self.url(path, **query),
            headers={
                "Accept": "application/json, audio/ogg, application/zip, */*",
                "User-Agent": f"CatQuest-Client/{APP_VERSION}",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                content_type = response.headers.get("Content-Type", "")
                body = response.read(MAX_DOWNLOAD_BYTES + 1)
                if len(body) > MAX_DOWNLOAD_BYTES:
                    raise ClientError("ответ сервера превышает допустимый размер")
                return response.status, content_type, body
        except urllib.error.HTTPError as error:
            body = error.read(MAX_DOWNLOAD_BYTES + 1)
            content_type = error.headers.get("Content-Type", "")
            return error.code, content_type, body
        except urllib.error.URLError as error:
            raise ClientError(f"сервер недоступен: {error.reason}") from error
        except TimeoutError as error:
            raise ClientError("истёк таймаут запроса к серверу") from error

    def json(self, path: str, **query: Any) -> dict[str, Any]:
        status, _, body = self.get(path, **query)
        try:
            payload = json.loads(body.decode("utf-8"))
        except (UnicodeError, json.JSONDecodeError) as error:
            raise ClientError(f"сервер вернул не JSON (HTTP {status})") from error
        if status < 200 or status >= 300:
            message = payload.get("error") if isinstance(payload, dict) else None
            raise ClientError(message or f"сервер ответил HTTP {status}")
        if not isinstance(payload, dict):
            raise ClientError("сервер вернул JSON не-объект")
        return payload


def extract_single_addon(archive: bytes, expected_folder: str) -> dict[str, bytes]:
    """Validate a release ZIP and return files relative to its addon folder."""

    if len(archive) > MAX_DOWNLOAD_BYTES:
        raise ClientError("архив аддона слишком большой")
    result: dict[str, bytes] = {}
    expected = expected_folder.lower()
    try:
        with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
            infos = bundle.infolist()
            if len(infos) > MAX_ZIP_FILES:
                raise ClientError("в архиве слишком много файлов")
            for info in infos:
                member = safe_zip_member(info.filename)
                if info.is_dir():
                    continue
                if info.file_size > MAX_ZIP_MEMBER_BYTES:
                    raise ClientError(f"файл в архиве слишком большой: {info.filename}")
                parts = member.parts
                if len(parts) < 2 or parts[0].lower() != expected:
                    raise ClientError(
                        f"архив должен содержать только папку {expected_folder}: {info.filename}"
                    )
                relative = Path(*parts[1:]).as_posix()
                if not relative or relative.lower() in {".catquest-client.json"}:
                    continue
                if relative.lower() in {key.lower() for key in result}:
                    raise ClientError(f"дубликат файла в архиве: {relative}")
                result[relative] = bundle.read(info)
    except zipfile.BadZipFile as error:
        raise ClientError("сервер прислал повреждённый ZIP") from error
    if not any(path.lower() == expected + ".toc" for path in result):
        raise ClientError(f"в архиве нет {expected_folder}.toc")
    return result


def install_addon(addons_dir: Path, folder: str, files: dict[str, bytes]) -> int:
    """Install a validated addon file set without touching SavedVariables."""

    target = addons_dir / folder
    target.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{folder}-", dir=str(addons_dir)))
    try:
        for relative, data in files.items():
            destination = staging / Path(relative)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
        for source in staging.rglob("*"):
            if source.is_dir():
                continue
            relative = source.relative_to(staging)
            destination = target / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            os.replace(source, destination) if not destination.exists() else shutil.copy2(source, destination)
        return len(files)
    except PermissionError as error:
        raise ClientError(
            f"не удалось обновить {folder}: файл занят. Закройте WoW и повторите"
        ) from error
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def addon_version(addons_dir: Path, folder: str) -> str:
    toc = addons_dir / folder / f"{folder}.toc"
    try:
        text = toc.read_text(encoding="utf-8-sig", errors="replace")
    except OSError:
        return ""
    match = re.search(r"^##\s*Version\s*:\s*(.+?)\s*$", text, re.MULTILINE | re.IGNORECASE)
    return match.group(1).strip() if match else ""


def release_addon(api: Api, addons_dir: Path, channel: str, force: bool) -> bool:
    release = api.json("/api/v1/release", channel=channel)
    entries = release.get("addons")
    if not isinstance(entries, list):
        raise ClientError("в release нет списка addons")
    entry = next(
        (
            item
            for item in entries
            if isinstance(item, dict)
            and str(item.get("folder", "")).lower() == ADDON_FOLDER.lower()
        ),
        None,
    )
    if not entry:
        raise ClientError("релиз не содержит аддон CatQuest")
    version = str(entry.get("version", "")).strip()
    url = str(entry.get("url", "")).strip()
    if not version or not url:
        raise ClientError("у CatQuest в release нет версии или URL")
    current = addon_version(addons_dir, ADDON_FOLDER)
    if not force and current and same_or_newer(current, version):
        log(f"CatQuest {current} уже актуален")
        return False
    parsed = urllib.parse.urlparse(urllib.parse.urljoin(api.origin + "/", url))
    if parsed.scheme + "://" + parsed.netloc != api.origin or not parsed.path.startswith("/downloads/"):
        raise ClientError("release содержит небезопасный URL аддона")
    status, _, archive = api.get(parsed.path, **dict(urllib.parse.parse_qsl(parsed.query)))
    if status != 200:
        raise ClientError(f"не удалось скачать CatQuest: HTTP {status}")
    if entry.get("bytes") is not None and len(archive) != int(entry["bytes"]):
        raise ClientError("размер ZIP CatQuest не совпал с release")
    expected_sha = str(entry.get("sha256", "")).lower()
    if expected_sha and sha256(archive) != expected_sha:
        raise ClientError("SHA-256 ZIP CatQuest не совпал с release")
    files = extract_single_addon(archive, ADDON_FOLDER)
    count = install_addon(addons_dir, ADDON_FOLDER, files)
    log(f"CatQuest обновлён до {version} ({count} файлов)")
    return True


def track_key(quest_id: int, quest_type: str) -> str:
    return f"{quest_id}:{quest_type}"


def parse_tracks(index: dict[str, Any], locale: str) -> list[tuple[int, str, int]]:
    tracks = index.get("tracks")
    raw = tracks.get(locale, []) if isinstance(tracks, dict) else []
    result = []
    if not isinstance(raw, list):
        return result
    for row in raw:
        if not isinstance(row, list) or len(row) < 3:
            continue
        try:
            quest_id, quest_type, size = int(row[0]), str(row[1]).upper(), int(row[2])
        except (TypeError, ValueError):
            continue
        if 0 < quest_id <= 0xFFFFFFFF and quest_type in QUEST_TYPES and size >= 0:
            result.append((quest_id, quest_type, size))
    return result


def parse_durations(index: dict[str, Any], locale: str) -> dict[str, list[float]]:
    result: dict[str, list[float]] = {}
    durations = index.get("durations")
    raw = durations.get(locale, []) if isinstance(durations, dict) else []
    if not isinstance(raw, list):
        return result
    for row in raw:
        if not isinstance(row, list) or len(row) < 3:
            continue
        try:
            quest_id, quest_type, seconds = int(row[0]), str(row[1]).upper(), float(row[2])
        except (TypeError, ValueError):
            continue
        if quest_id > 0 and quest_type in QUEST_TYPES and seconds > 0:
            pair = result.setdefault(str(quest_id), [0.0, 0.0])
            pair[1 if quest_type == "COMPLETE" else 0] = round(seconds, 1)
    return result


def parse_books(index: dict[str, Any], locale: str) -> list[tuple[str, str, int]]:
    books = index.get("books")
    raw = books.get(locale, []) if isinstance(books, dict) else []
    result = []
    if not isinstance(raw, list):
        return result
    for row in raw:
        if not isinstance(row, list) or len(row) < 3:
            continue
        book_hash, variant = str(row[0]).lower(), str(row[1])
        try:
            size = int(row[2])
        except (TypeError, ValueError):
            continue
        if re.fullmatch(r"[0-9a-f]{8}", book_hash) and variant in {"", "m", "f"} and size >= 0:
            result.append((book_hash, variant, size))
    return result


def track_file(server_dir: Path, locale: str, quest_id: int, quest_type: str) -> Path:
    suffix = "_t" if quest_type == "COMPLETE" else ""
    return server_dir / locale / "Sounds" / "q" / f"{quest_id}{suffix}.ogg"


def book_file(server_dir: Path, locale: str, book_hash: str, variant: str) -> Path:
    suffix = f"_{variant}" if variant else ""
    return server_dir / locale / "Sounds" / "b" / f"{book_hash}{suffix}.ogg"


def ready_bits(files: Iterable[tuple[int, str, int]], server_dir: Path, locale: str) -> dict[int, int]:
    result: dict[int, int] = {}
    for quest_id, quest_type, _ in files:
        if not track_file(server_dir, locale, quest_id, quest_type).is_file():
            continue
        result[quest_id] = result.get(quest_id, 0) | (2 if quest_type == "COMPLETE" else 1)
    return result


def lua_number(value: float) -> str:
    return f"{value:.1f}".rstrip("0").rstrip(".")


def render_bridge(
    locale: str,
    tracks: Iterable[tuple[int, str, int]],
    durations: dict[str, list[float]],
    server_dir: Path,
    books: Iterable[tuple[str, str, int]] = (),
) -> str:
    downloaded = ready_bits(tracks, server_dir, locale)
    q_lines = [f"    [{quest_id}] = {bits}," for quest_id, bits in sorted(downloaded.items())]
    d_lines = []
    for quest_id, pair in sorted(durations.items(), key=lambda row: int(row[0])):
        if int(quest_id) in downloaded and any(pair):
            d_lines.append(
                f"    [{quest_id}] = {{{lua_number(pair[0])}, {lua_number(pair[1])}}},"
            )
    book_hashes = sorted(
        {
            book_hash
            for book_hash, variant, _ in books
            if book_file(server_dir, locale, book_hash, variant).is_file()
        }
    )
    b_lines = [f'    ["{book_hash}"] = true,' for book_hash in book_hashes]
    lines = [
        "-- Generated by CatQuest Client. Do not edit while the utility is running.",
        f'CatQuest335_BridgeChoice = "{locale}"',
        "CatQuest335_BridgeReady = {",
        '    mode = "local",',
        f'    locale = "{locale}",',
        "    q = {",
        *q_lines,
        "    },",
        "    d = {",
        *d_lines,
        "    },",
        "    b = {",
        *b_lines,
        "    },",
        "}",
        "",
    ]
    return "\n".join(lines)


def server_toc() -> str:
    return "\n".join(
        [
            "## Interface: 30300",
            "## Title: CatQuest Server Voices (local bridge)",
            "## Notes: Files downloaded by CatQuest Client",
            f"## Version: {APP_VERSION}",
            "## Dependencies: CatQuest",
            "Bridge.lua",
            "",
        ]
    )


def download_track(
    api: Api,
    destination: Path,
    quest_id: int,
    quest_type: str,
    locale: str,
    expected_size: int | None = None,
) -> str:
    status, content_type, body = api.get(
        f"/api/v1/voice/{quest_id}/{quest_type}",
        client=CLIENT_VERSION,
        locale=locale,
        wait=0,
    )
    if status != 200 or not re.search(r"(?:audio/|application/ogg)", content_type, re.IGNORECASE):
        try:
            payload = json.loads(body.decode("utf-8"))
        except (UnicodeError, json.JSONDecodeError):
            payload = {}
        status_name = payload.get("status") if isinstance(payload, dict) else None
        return f"not-ready:{status_name or status}"
    if expected_size is not None and len(body) != expected_size:
        return f"size-mismatch:{len(body)}"
    write_atomic(destination, body)
    return "downloaded"


def download_book(api: Api, destination: Path, book_hash: str, variant: str, locale: str) -> str:
    status, content_type, body = api.get(
        f"/api/v1/book/{book_hash}", locale=locale, variant=variant
    )
    if status != 200 or not re.search(r"(?:audio/|application/ogg)", content_type, re.IGNORECASE):
        return f"not-ready:{status}"
    write_atomic(destination, body)
    return "downloaded"


def load_state(server_dir: Path) -> dict[str, Any]:
    state = read_json(server_dir / ".catquest-client.json", {})
    return state if isinstance(state, dict) else {}


def save_state(server_dir: Path, state: dict[str, Any]) -> None:
    write_atomic(server_dir / ".catquest-client.json", json.dumps(state, ensure_ascii=False, indent=2) + "\n")


def sync_tracks(
    api: Api,
    server_dir: Path,
    locale: str,
    include_books: bool,
    force: bool,
    limit: int | None,
) -> tuple[int, int]:
    index = api.json("/api/v1/index", client=CLIENT_VERSION, demand=locale)
    tracks = parse_tracks(index, locale)
    durations = parse_durations(index, locale)
    all_books = parse_books(index, locale)
    books = all_books if include_books else []
    state = load_state(server_dir)
    known = state.setdefault("tracks", {})
    if not isinstance(known, dict):
        known = {}
        state["tracks"] = known
    downloaded = 0
    skipped = 0
    selected = tracks if limit is None else tracks[: max(0, limit)]
    for quest_id, quest_type, expected_size in selected:
        key = track_key(quest_id, quest_type)
        destination = track_file(server_dir, locale, quest_id, quest_type)
        cached = known.get(key, {}) if isinstance(known, dict) else {}
        if (
            not force
            and destination.is_file()
            and destination.stat().st_size == expected_size
            and isinstance(cached, dict)
            and cached.get("size") == expected_size
        ):
            skipped += 1
            continue
        outcome = download_track(api, destination, quest_id, quest_type, locale, expected_size)
        if outcome == "downloaded":
            known[key] = {"size": destination.stat().st_size, "updated": int(time.time())}
            downloaded += 1
            log(f"скачана дорожка {quest_id} {quest_type}")
        else:
            log(f"пропуск {quest_id} {quest_type}: {outcome}")

    book_state = state.setdefault("books", {})
    if not isinstance(book_state, dict):
        book_state = {}
        state["books"] = book_state
    if include_books:
        for book_hash, variant, expected_size in books:
            key = f"{book_hash}:{variant}"
            destination = book_file(server_dir, locale, book_hash, variant)
            cached = book_state.get(key, {}) if isinstance(book_state, dict) else {}
            if (
                not force
                and destination.is_file()
                and destination.stat().st_size == expected_size
                and isinstance(cached, dict)
                and cached.get("size") == expected_size
            ):
                skipped += 1
                continue
            outcome = download_book(api, destination, book_hash, variant, locale)
            if outcome == "downloaded":
                book_state[key] = {"size": destination.stat().st_size, "updated": int(time.time())}
                downloaded += 1
                log(f"скачана книга/лор {book_hash}{('_' + variant) if variant else ''}")
            else:
                log(f"пропуск книги {book_hash}: {outcome}")

    server_dir.mkdir(parents=True, exist_ok=True)
    write_atomic(server_dir / f"{SERVER_FOLDER}.toc", server_toc())
    write_atomic(
        server_dir / "Bridge.lua",
        render_bridge(locale, tracks, durations, server_dir, all_books),
    )
    state["locale"] = locale
    state["client_version"] = CLIENT_VERSION
    state["synced_at"] = int(time.time())
    save_state(server_dir, state)
    log(f"локальный мост готов: {len(ready_bits(tracks, server_dir, locale))} квестов, пропущено {skipped}")
    return downloaded, skipped


def refresh_manifest(
    api: Api,
    server_dir: Path,
    locale: str,
    extra_tracks: Iterable[tuple[int, str]] = (),
) -> None:
    """Refresh Bridge.lua, including a freshly generated track not in index yet."""

    index = api.json("/api/v1/index", client=CLIENT_VERSION, demand=locale)
    tracks = parse_tracks(index, locale)
    existing = {(row[0], row[1]) for row in tracks}
    for quest_id, quest_type in extra_tracks:
        if (quest_id, quest_type) not in existing:
            path = track_file(server_dir, locale, quest_id, quest_type)
            if path.is_file():
                tracks.append((quest_id, quest_type, path.stat().st_size))
    server_dir.mkdir(parents=True, exist_ok=True)
    write_atomic(server_dir / f"{SERVER_FOLDER}.toc", server_toc())
    write_atomic(
        server_dir / "Bridge.lua",
        render_bridge(
            locale,
            tracks,
            parse_durations(index, locale),
            server_dir,
            parse_books(index, locale),
        ),
    )
    return None


def request_track(api: Api, server_dir: Path, locale: str, quest_id: int, quest_type: str, timeout: float) -> bool:
    if quest_id <= 0 or quest_id > 0xFFFFFFFF:
        raise ClientError("некорректный ID квеста")
    quest_type = quest_type.upper()
    if quest_type not in QUEST_TYPES:
        raise ClientError("тип должен быть DETAIL или COMPLETE")
    status, content_type, body = api.get(
        f"/api/v1/voice/{quest_id}/{quest_type}",
        client=CLIENT_VERSION,
        locale=locale,
        wait=0,
    )
    if status == 200 and re.search(r"(?:audio/|application/ogg)", content_type, re.IGNORECASE):
        write_atomic(track_file(server_dir, locale, quest_id, quest_type), body)
        log(f"дорожка {quest_id} {quest_type} уже готова")
        return True
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        payload = {}
    if status == 404 or payload.get("status") == "missing":
        raise ClientError(f"для квеста {quest_id} нет текста или дорожки")
    if status != 202:
        message = payload.get("error") or payload.get("reason") if isinstance(payload, dict) else None
        raise ClientError(message or f"сервер ответил HTTP {status}")
    log(f"запрос {quest_id} {quest_type} принят; жду готовность")
    deadline = time.monotonic() + max(1.0, timeout)
    while time.monotonic() < deadline:
        current = api.json(
            f"/api/v1/status/{quest_id}/{quest_type}",
            client=CLIENT_VERSION,
            locale=locale,
        )
        state = str(current.get("status", ""))
        if state == "ready":
            status, content_type, body = api.get(
                f"/api/v1/voice/{quest_id}/{quest_type}",
                client=CLIENT_VERSION,
                locale=locale,
                wait=0,
            )
            if status == 200 and re.search(r"(?:audio/|application/ogg)", content_type, re.IGNORECASE):
                write_atomic(track_file(server_dir, locale, quest_id, quest_type), body)
                log(f"дорожка {quest_id} {quest_type} скачана; нужен /reload")
                return True
        elif state in {"failed", "limited", "missing"}:
            raise ClientError(f"сервер завершил запрос статусом {state}")
        time.sleep(3)
    log(f"дорожка {quest_id} пока не готова; повторите request позже")
    return False


def savedvariable_missing(wow_dir: Path) -> list[tuple[int, str]]:
    found: set[tuple[int, str]] = set()
    root = wow_dir / "WTF" / "Account"
    if not root.is_dir():
        return []
    for path in root.rglob("CatQuest.lua"):
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for match in re.finditer(r'\["(\d+):(quest|turnin)"\]\s*=\s*\{', text):
            found.add((int(match.group(1)), match.group(2)))
    return sorted(found)


def resolve_wow_dir(value: str | None) -> Path:
    if value:
        path = Path(value).expanduser().resolve()
    else:
        path = Path.cwd().resolve()
    addons = path / "Interface" / "AddOns"
    if not addons.is_dir():
        raise ClientError(f"не найдена папка Interface\\AddOns в {path}")
    return path


def command_sync(args: argparse.Namespace) -> int:
    wow_dir = resolve_wow_dir(args.wow_dir)
    addons_dir = wow_dir / "Interface" / "AddOns"
    api = Api(args.api, args.timeout)
    if not args.no_addon_update:
        release_addon(api, addons_dir, args.channel, args.force)
    server_dir = addons_dir / SERVER_FOLDER
    sync_tracks(api, server_dir, normalize_locale(args.locale), args.books, args.force, args.limit)
    log("готово. Перезагрузите игру или выполните /reload")
    return 0


def command_request(args: argparse.Namespace) -> int:
    wow_dir = resolve_wow_dir(args.wow_dir)
    api = Api(args.api, args.timeout)
    locale = normalize_locale(args.locale)
    server_dir = wow_dir / "Interface" / "AddOns" / SERVER_FOLDER
    server_dir.mkdir(parents=True, exist_ok=True)
    ok = request_track(api, server_dir, locale, int(args.quest_id), args.quest_type, args.wait)
    if ok:
        refresh_manifest(api, server_dir, locale, [(int(args.quest_id), args.quest_type)])
        save_state(server_dir, load_state(server_dir))
        log("готово. Выполните /reload, чтобы WoW увидел новый файл")
    return 0 if ok else 2


def command_watch(args: argparse.Namespace) -> int:
    wow_dir = resolve_wow_dir(args.wow_dir)
    api = Api(args.api, args.timeout)
    locale = normalize_locale(args.locale)
    server_dir = wow_dir / "Interface" / "AddOns" / SERVER_FOLDER
    state = load_state(server_dir)
    requested = state.setdefault("requested_missing", {})
    log("режим watch запущен; Ctrl+C для выхода")
    try:
        while True:
            sync_tracks(api, server_dir, locale, args.books, False, args.limit)
            for quest_id, quest_type in savedvariable_missing(wow_dir):
                request_type = "COMPLETE" if quest_type == "turnin" else "DETAIL"
                key = f"{locale}:{track_key(quest_id, request_type)}"
                if key in requested:
                    continue
                try:
                    if request_track(api, server_dir, locale, quest_id, request_type, args.wait):
                        requested[key] = int(time.time())
                        refresh_manifest(api, server_dir, locale, [(quest_id, request_type)])
                except ClientError as error:
                    log(f"запрос {quest_id} {request_type} не выполнен: {error}")
            save_state(server_dir, state)
            time.sleep(max(10.0, args.interval))
    except KeyboardInterrupt:
        log("watch остановлен")
        return 0


def install_companion_addon(addons_dir: Path) -> int:
    """Install the small pixel-bridge addon shipped with this client."""

    source_dir = Path(__file__).resolve().parent / "companion_addon"
    if not source_dir.is_dir():
        raise ClientError(f"не найдены файлы {COMPANION_FOLDER}: {source_dir}")
    files = [path for path in source_dir.rglob("*") if path.is_file()]
    if not files:
        raise ClientError(f"пустой пакет {COMPANION_FOLDER}")
    target = addons_dir / COMPANION_FOLDER
    try:
        for source in files:
            relative = source.relative_to(source_dir)
            write_atomic(target / relative, source.read_bytes())
    except PermissionError as error:
        raise ClientError(
            f"не удалось установить {COMPANION_FOLDER}: файл занят или нет прав"
        ) from error
    log(f"установлен {COMPANION_FOLDER} ({len(files)} файлов)")
    return len(files)


def _screen_pixel(frame: Any, x: int, y: int) -> tuple[int, int, int]:
    """Read RGB from an mss screenshot across mss versions."""

    pixel = getattr(frame, "pixel", None)
    if callable(pixel):
        value = pixel(x, y)
        if len(value) >= 3:
            return int(value[0]), int(value[1]), int(value[2])
    raw = frame.raw
    offset = (y * frame.width + x) * 4
    blue, green, red = raw[offset : offset + 3]
    return int(red), int(green), int(blue)


def _screen_nibble(value: int) -> int:
    return max(0, min(15, int(value / 17.0 + 0.5)))


def decode_companion_frame(frame: Any, cell: int = PIXEL_CELL) -> tuple[int, int, int, int, bytes] | None:
    """Decode one complete 96x8 screen frame from the Lua bridge."""

    width = int(getattr(frame, "width", 0))
    height = int(getattr(frame, "height", 0))
    required_width = PIXEL_COLS * cell
    required_height = PIXEL_ROWS * cell
    if width < required_width or height < required_height:
        return None

    cells: list[tuple[int, int, int]] = []
    for index in range(PIXEL_COLS * PIXEL_ROWS):
        x = (index % PIXEL_COLS) * cell + cell // 2
        y = (index // PIXEL_COLS) * cell + cell // 2
        rgb = _screen_pixel(frame, x, y)
        cells.append(tuple(_screen_nibble(channel) for channel in rgb))

    if cells[:4] != [(15, 0, 15), (0, 15, 0), (15, 0, 15), (0, 15, 0)]:
        return None

    def value12(cell_value: tuple[int, int, int]) -> int:
        return cell_value[0] * 256 + cell_value[1] * 16 + cell_value[2]

    message_id = value12(cells[20])
    chunk_index = value12(cells[21])
    chunk_count = value12(cells[22])
    length = value12(cells[23])
    checksum = value12(cells[24])
    if not (1 <= chunk_count <= MAX_COMPANION_CHUNKS):
        return None
    if not (0 <= chunk_index < chunk_count and 0 <= length <= PIXEL_CHUNK_BYTES):
        return None

    needed_nibbles = length * 2
    needed_cells = (needed_nibbles + 2) // 3
    nibbles: list[int] = []
    for cell_value in cells[PIXEL_HEADER : PIXEL_HEADER + needed_cells]:
        nibbles.extend(cell_value)
    data = bytes(
        (nibbles[index] << 4) | nibbles[index + 1]
        for index in range(0, needed_nibbles, 2)
    )
    if sum(data) % 4096 != checksum:
        return None
    return message_id, chunk_index, chunk_count, length, data


class CompanionDecoder:
    def __init__(self) -> None:
        self.messages: dict[int, dict[str, Any]] = {}
        self.last_message_id: int | None = None

    def push(self, frame: Any, cell: int = PIXEL_CELL) -> str | None:
        decoded = decode_companion_frame(frame, cell)
        if not decoded:
            return None
        message_id, chunk_index, chunk_count, _, data = decoded
        if message_id == self.last_message_id:
            return None
        current = self.messages.get(message_id)
        if not current or current["count"] != chunk_count:
            current = {"count": chunk_count, "chunks": {}}
            self.messages[message_id] = current
        current["chunks"][chunk_index] = data
        if len(current["chunks"]) != chunk_count:
            return None
        payload = b"".join(current["chunks"][index] for index in range(chunk_count))
        del self.messages[message_id]
        self.last_message_id = message_id
        if len(payload) > MAX_COMPANION_PAYLOAD:
            return None
        try:
            return payload.decode("utf-8")
        except UnicodeDecodeError:
            return None


def parse_companion_payload(payload: str) -> dict[str, Any] | None:
    if payload == "X":
        return {"kind": "stop"}
    header, separator, text = payload.partition("\n")
    if not separator or not text:
        return None
    fields = header.split("\t")
    if not fields:
        return None
    try:
        if fields[0] == "Q" and len(fields) >= 8:
            quest_id = int(fields[2])
            quest_type = fields[3].upper()
            kind = fields[1]
            locale = normalize_locale(fields[4])
            npc_id = int(fields[5] or 0)
            gender = fields[6] if fields[6] in {"", "male", "female"} else ""
            if kind not in {"quest", "turnin"} or quest_type not in QUEST_TYPES:
                return None
            if not (0 < quest_id <= 0xFFFFFFFF and 0 <= npc_id < 10_000_000):
                return None
            title = re.sub(r"\s+", " ", fields[7]).strip()[:120]
            if len(text.encode("utf-8")) > 20_000:
                return None
            return {
                "kind": "quest",
                "quest_id": quest_id,
                "quest_type": quest_type,
                "locale": locale,
                "npc_id": npc_id,
                "npc_gender": gender,
                "title": title or "Quest",
                "text": text,
            }
        if fields[0] == "G" and len(fields) >= 5:
            locale = normalize_locale(fields[1])
            npc_id = int(fields[2] or 0)
            gender = fields[3] if fields[3] in {"", "male", "female"} else ""
            if not (0 <= npc_id < 10_000_000):
                return None
            title = re.sub(r"\s+", " ", fields[4]).strip()[:120] or "NPC"
            text = re.sub(r"\s+", " ", text).strip()
            if not text or len(text.encode("utf-8")) > 20_000:
                return None
            return {
                "kind": "gossip",
                "locale": locale,
                "npc_id": npc_id,
                "npc_gender": gender,
                "title": title,
                "text": text,
            }
    except (TypeError, ValueError, ClientError):
        return None
    return None


def companion_cache_path(server_dir: Path, message: dict[str, Any]) -> Path:
    locale = str(message["locale"])
    if message["kind"] == "quest":
        name = f'{message["quest_id"]}_{message["quest_type"]}.ogg'
    else:
        raw = "\x00".join(
            str(message.get(key, ""))
            for key in ("locale", "npc_id", "npc_gender", "title", "text")
        ).encode("utf-8")
        name = hashlib.sha256(raw).hexdigest()[:32] + ".ogg"
    return server_dir / "companion-cache" / locale / name


def _json_body(body: bytes) -> dict[str, Any]:
    try:
        value = json.loads(body.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _is_audio(content_type: str, body: bytes) -> bool:
    return bool(body) and bool(re.search(r"(?:audio/|application/ogg)", content_type, re.IGNORECASE))


def fetch_companion_audio(
    api: Api,
    server_dir: Path,
    message: dict[str, Any],
    timeout: float,
    wait: float,
) -> Path | None:
    destination = companion_cache_path(server_dir, message)
    if destination.is_file() and destination.stat().st_size > 0:
        return destination
    deadline = time.monotonic() + max(1.0, timeout)
    while time.monotonic() < deadline:
        remaining = max(0.0, deadline - time.monotonic())
        if message["kind"] == "quest":
            path = f'/api/v1/voice/{message["quest_id"]}/{message["quest_type"]}'
            status, content_type, body = api.get(
                path,
                client=CLIENT_VERSION,
                locale=message["locale"],
                npc_id=message["npc_id"] or None,
                wait=0,
            )
            if status == 200 and _is_audio(content_type, body):
                write_atomic(destination, body)
                return destination
            payload = _json_body(body)
            if status == 404 or payload.get("status") in {"missing", "failed", "limited"}:
                raise ClientError(
                    str(payload.get("error") or payload.get("reason") or f"дорожка недоступна (HTTP {status})")
                )
            if status != 202:
                raise ClientError(str(payload.get("error") or f"сервер ответил HTTP {status}"))
            current = api.json(
                f'/api/v1/status/{message["quest_id"]}/{message["quest_type"]}',
                client=CLIENT_VERSION,
                locale=message["locale"],
            )
            state = str(current.get("status", ""))
            if state in {"missing", "failed", "limited"}:
                raise ClientError(str(current.get("error") or f"сервер завершил запрос статусом {state}"))
            if state == "ready":
                continue
        else:
            status, content_type, body = api.get(
                "/api/v1/gossip",
                client=CLIENT_VERSION,
                locale=message["locale"],
                npc_id=message["npc_id"] or None,
                npc_gender=message["npc_gender"] or None,
                title=message["title"],
                text=message["text"],
                wait=min(20.0, remaining, max(0.0, wait)),
            )
            if status == 200 and _is_audio(content_type, body):
                write_atomic(destination, body)
                return destination
            payload = _json_body(body)
            if status == 404 or payload.get("status") in {"missing", "failed", "limited"}:
                raise ClientError(
                    str(payload.get("error") or payload.get("reason") or f"gossip недоступен (HTTP {status})")
                )
            if status != 202:
                raise ClientError(str(payload.get("error") or f"сервер ответил HTTP {status}"))
        time.sleep(min(3.0, max(0.2, deadline - time.monotonic())))
    raise ClientError("истёк таймаут генерации дорожки")


class CompanionPlayer:
    def __init__(self, api: Api, server_dir: Path, timeout: float, wait: float, pygame_module: Any) -> None:
        self.api = api
        self.server_dir = server_dir
        self.timeout = timeout
        self.wait = wait
        self.pygame = pygame_module
        self.jobs: queue.Queue[dict[str, Any] | None] = queue.Queue()
        self.stop_event = threading.Event()
        self.playback_lock = threading.Lock()
        self.generation = 0
        self.thread = threading.Thread(target=self._run, name="CatQuestAudio", daemon=True)

    def start(self) -> None:
        try:
            self.pygame.mixer.init()
        except Exception as error:
            raise ClientError(f"не удалось открыть аудиоустройство: {error}") from error
        self.thread.start()

    def stop(self) -> None:
        with self.playback_lock:
            self.generation += 1
            try:
                self.pygame.mixer.music.stop()
            except Exception:
                pass
        while True:
            try:
                self.jobs.get_nowait()
            except queue.Empty:
                break

    def enqueue(self, message: dict[str, Any]) -> None:
        self.stop()
        token = self.generation
        message = dict(message)
        message["_token"] = token
        self.jobs.put(message)

    def _run(self) -> None:
        while not self.stop_event.is_set():
            try:
                message = self.jobs.get(timeout=0.25)
            except queue.Empty:
                continue
            if message is None:
                return
            token = message.get("_token")
            try:
                path = fetch_companion_audio(
                    self.api, self.server_dir, message, self.timeout, self.wait
                )
                with self.playback_lock:
                    if not path or token != self.generation or self.stop_event.is_set():
                        continue
                    self.pygame.mixer.music.stop()
                    self.pygame.mixer.music.load(str(path))
                    self.pygame.mixer.music.play()
                log(f"воспроизведение: {path.name}")
            except ClientError as error:
                log(f"озвучка не запущена: {error}")
            except Exception as error:
                log(f"ошибка аудиопроигрывателя: {error}")

    def close(self) -> None:
        self.stop_event.set()
        self.stop()
        self.jobs.put(None)
        self.thread.join(timeout=2.0)
        try:
            self.pygame.mixer.quit()
        except Exception:
            pass


def command_companion(args: argparse.Namespace) -> int:
    if args.cell < 1 or args.cell > 32:
        raise ClientError("--cell должен быть от 1 до 32")
    if args.x < 0 or args.y < 0:
        raise ClientError("--x и --y не могут быть отрицательными")
    if args.fps <= 0:
        raise ClientError("--fps должен быть положительным")
    wow_dir = resolve_wow_dir(args.wow_dir)
    addons_dir = wow_dir / "Interface" / "AddOns"
    api = Api(args.api, args.timeout)
    if not args.no_addon_update:
        release_addon(api, addons_dir, args.channel, args.force)
    install_companion_addon(addons_dir)
    server_dir = addons_dir / SERVER_FOLDER
    server_dir.mkdir(parents=True, exist_ok=True)

    try:
        import mss
        import pygame
    except ImportError as error:
        raise ClientError(
            "для companion нужны зависимости: python -m pip install -r client\\requirements.txt"
        ) from error

    player = CompanionPlayer(api, server_dir, args.timeout, args.wait, pygame)
    player.start()
    decoder = CompanionDecoder()
    log(
        f"companion запущен; читаю область {args.x},{args.y} "
        f"размером {PIXEL_COLS * args.cell}x{PIXEL_ROWS * args.cell}. Ctrl+C для выхода"
    )
    try:
        with mss.mss() as capture:
            monitor = {
                "left": args.x,
                "top": args.y,
                "width": PIXEL_COLS * args.cell,
                "height": PIXEL_ROWS * args.cell,
            }
            interval = 1.0 / max(10.0, min(120.0, args.fps))
            while True:
                frame = capture.grab(monitor)
                payload = decoder.push(frame, args.cell)
                if payload is not None:
                    message = parse_companion_payload(payload)
                    if message and message["kind"] == "stop":
                        player.stop()
                        log("воспроизведение остановлено")
                    elif message:
                        player.enqueue(message)
                        label = (
                            f'{message["quest_id"]} {message["quest_type"]}'
                            if message["kind"] == "quest"
                            else message["title"]
                        )
                        log(f"получен запрос: {label}")
                time.sleep(interval)
    except KeyboardInterrupt:
        log("companion остановлен")
        return 0
    finally:
        player.close()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", action="version", version=f"CatQuest Client {APP_VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)

    def common(command: argparse.ArgumentParser) -> None:
        command.add_argument("--wow-dir", required=True, help="корень обычного WoW с Interface\\AddOns")
        command.add_argument("--api", default=DEFAULT_API, help=f"Voice API (по умолчанию {DEFAULT_API})")
        command.add_argument("--locale", default="ruRU", help="язык дорожек, например ruRU или enUS")
        command.add_argument("--timeout", type=float, default=30.0)

    sync = sub.add_parser("sync", help="обновить CatQuest и скачать готовые серверные дорожки")
    common(sync)
    sync.add_argument("--channel", choices=("stable", "beta"), default="stable")
    sync.add_argument("--force", action="store_true", help="скачать заново даже файлы того же размера")
    sync.add_argument("--books", action="store_true", help="скачать также книги и лор мест")
    sync.add_argument("--limit", type=int, help="ограничить число квестовых дорожек за запуск")
    sync.add_argument("--no-addon-update", action="store_true")
    sync.set_defaults(handler=command_sync)

    request = sub.add_parser("request", help="запросить одну серверную дорожку и сохранить её локально")
    common(request)
    request.add_argument("quest_id", type=int)
    request.add_argument("quest_type", choices=("DETAIL", "COMPLETE"))
    request.add_argument("--wait", type=float, default=180.0, help="сколько секунд ждать генерацию")
    request.set_defaults(handler=command_request)

    watch = sub.add_parser("watch", help="синхронизировать готовые дорожки и читать SavedVariables")
    common(watch)
    watch.add_argument("--books", action="store_true")
    watch.add_argument("--limit", type=int)
    watch.add_argument("--interval", type=float, default=300.0)
    watch.add_argument("--wait", type=float, default=15.0)
    watch.set_defaults(handler=command_watch)

    companion = sub.add_parser(
        "companion",
        help="запустить живой экранный мост и проигрывать серверную озвучку вне WoW",
    )
    common(companion)
    companion.add_argument("--channel", choices=("stable", "beta"), default="stable")
    companion.add_argument("--force", action="store_true")
    companion.add_argument("--no-addon-update", action="store_true")
    companion.add_argument("--wait", type=float, default=20.0, help="ожидание одного запроса gossip")
    companion.add_argument("--x", type=int, default=0, help="X области захвата экрана")
    companion.add_argument("--y", type=int, default=0, help="Y области захвата экрана")
    companion.add_argument("--cell", type=int, default=PIXEL_CELL, help="размер пиксельной клетки")
    companion.add_argument("--fps", type=float, default=60.0, help="частота чтения экрана")
    companion.set_defaults(handler=command_companion)
    return parser


def main(argv: list[str] | None = None) -> int:
    try:
        args = build_parser().parse_args(argv)
        return int(args.handler(args))
    except ClientError as error:
        print(f"[CatQuest] ошибка: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\n[CatQuest] остановлено", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
