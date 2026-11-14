#!/usr/bin/env python3
"""CatQuest Client: local and live bridge for WoW and Lasthavens Desktop.

The game client cannot make HTTP requests itself.  ``sync`` turns ready server
tracks into real files in Interface/AddOns (or Lasthavens' userData/AddOns) and writes the small Bridge.lua
manifest that CatQuest reads on the next /reload.  ``companion`` uses an
addon-rendered screen-pixel protocol and plays on-demand OGG outside WoW, so
it does not depend on a PlaySoundFile notification that the client cannot
provide.
"""

from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import hashlib
import io
import json
import locale
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
SUPPORT_CHAT_URL = "https://t.me/warcraft_rus_chat"
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
DEFAULT_UPDATE_INTERVAL = 6 * 60 * 60
CURRENT_ADDONS_DIR: Path | None = None


def detect_ui_language() -> str:
    override = os.environ.get("CATQUEST_LANG", "").strip().lower()
    if override in {"ru", "en"}:
        return override
    locale_name = ""
    if os.name == "nt":
        try:
            kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
            get_locale = kernel32.GetUserDefaultLocaleName
            get_locale.argtypes = [wintypes.LPWSTR, ctypes.c_int]
            get_locale.restype = ctypes.c_int
            buffer = ctypes.create_unicode_buffer(85)
            if get_locale(buffer, len(buffer)):
                locale_name = buffer.value
        except (AttributeError, OSError):
            pass
    if not locale_name:
        locale_name = str(locale.getlocale()[0] or os.environ.get("LANG", ""))
    return "ru" if locale_name.lower().startswith("ru") else "en"


UI_LANGUAGE = detect_ui_language()


class ClientError(RuntimeError):
    """An expected, user-facing utility error."""


class RunningGame:
    """A detected game window and the addon directory it exposes."""

    __slots__ = ("kind", "pid", "hwnd", "executable", "root", "addons_dir")

    def __init__(
        self,
        kind: str,
        pid: int,
        hwnd: int,
        executable: Path,
        root: Path,
        addons_dir: Path,
    ) -> None:
        self.kind = kind
        self.pid = pid
        self.hwnd = hwnd
        self.executable = executable
        self.root = root
        self.addons_dir = addons_dir


EN_TEXT = {
    "не определена": "not detected",
    "не установлен": "not installed",
    "авто-режим сейчас поддерживается только в Windows": "automatic mode is currently supported only on Windows",
    "API URL не должен содержать query или fragment": "the API URL must not contain a query or fragment",
    "ответ сервера превышает допустимый размер": "the server response is too large",
    "истёк таймаут запроса к серверу": "the server request timed out",
    "сервер вернул JSON не-объект": "the server returned a non-object JSON value",
    "архив аддона слишком большой": "the addon archive is too large",
    "в архиве слишком много файлов": "the archive contains too many files",
    "сервер прислал повреждённый ZIP": "the server returned a damaged ZIP archive",
    "в release нет списка addons": "the release has no addons list",
    "релиз не содержит аддон CatQuest": "the release does not contain the CatQuest addon",
    "у CatQuest в release нет версии или URL": "the CatQuest release has no version or URL",
    "release содержит небезопасный URL аддона": "the release contains an unsafe addon URL",
    "размер ZIP CatQuest не совпал с release": "the CatQuest ZIP size does not match the release",
    "SHA-256 ZIP CatQuest не совпал с release": "the CatQuest ZIP SHA-256 does not match the release",
    "некорректный ID квеста": "invalid quest ID",
    "тип должен быть DETAIL или COMPLETE": "the type must be DETAIL or COMPLETE",
    "для Lasthavens нужен --lasthavens-dir": "Lasthavens requires --lasthavens-dir",
    "режим watch запущен; Ctrl+C для выхода": "watch mode started; press Ctrl+C to exit",
    "watch остановлен": "watch stopped",
    "готово. Перезагрузите игру или выполните /reload": "done. Reload the game or run /reload",
    "готово. Выполните /reload, чтобы WoW увидел новый файл": "done. Run /reload so WoW can see the new file",
    "авто-гибрид запущен; ожидаю окно WoW или Lasthavens Desktop": "automatic hybrid started; waiting for a WoW or Lasthavens Desktop window",
    "игра закрыта или свёрнута; жду следующий запуск": "the game was closed or minimized; waiting for the next launch",
    "игра не найдена; жду запуска...": "no supported game found; waiting for launch...",
    "CatQuest обновлён; выполните /reload в игре": "CatQuest was updated; run /reload in the game",
    "воспроизведение остановлено": "playback stopped",
    "companion остановлен": "companion stopped",
    "авто-гибрид остановлен": "automatic hybrid stopped",
    "поддержка": "support",
    "текущая версия аддона": "current addon version",
    "корень обычного WoW с Interface\\AddOns": "ordinary WoW root with Interface\\AddOns",
    "userData Lasthavens Desktop, например %%APPDATA%%\\Lasthavens": "Lasthavens Desktop userData, e.g. %%APPDATA%%\\Lasthavens",
    "обновить CatQuest и скачать готовые серверные дорожки": "update CatQuest and download ready server tracks",
    "скачать заново даже файлы того же размера": "download files again even if their size is unchanged",
    "скачать также книги и лор мест": "also download books and place lore",
    "ограничить число квестовых дорожек за запуск": "limit the number of quest tracks per run",
    "запросить одну серверную дорожку и сохранить её локально": "request one server track and save it locally",
    "сколько секунд ждать генерацию": "how many seconds to wait for generation",
    "синхронизировать готовые дорожки и читать SavedVariables": "sync ready tracks and read SavedVariables",
    "запустить живой экранный мост и проигрывать серверную озвучку вне WoW": "start the live screen bridge and play server audio outside WoW",
    "X области захвата экрана": "X coordinate of the capture area",
    "Y области захвата экрана": "Y coordinate of the capture area",
    "размер пиксельной клетки": "pixel cell size",
    "частота чтения экрана": "screen capture frequency",
    "автоматически найти запущенный WoW/Lasthavens и запустить Hybrid": "find a running WoW/Lasthavens client and start Hybrid",
    "ограничить поиск указанной установкой обычного WoW": "limit detection to the specified WoW installation",
    "интервал поиска игры": "game detection interval",
    "интервал проверки обновления CatQuest в секундах": "CatQuest update check interval in seconds",
    "ожидание одного запроса gossip": "wait time for one gossip request",
}


def localize_text(text: str) -> str:
    if UI_LANGUAGE == "ru":
        return text
    if text in EN_TEXT:
        return EN_TEXT[text]
    patterns = (
        (r"^ошибка: (.*)$", lambda m: f"error: {localize_text(m.group(1))}"),
        (r"^CatQuest (.+) уже актуален$", lambda m: f"CatQuest {m.group(1)} is up to date"),
        (r"^CatQuest обновлён до (.+) \((\d+) файлов\)$", lambda m: f"CatQuest updated to {m.group(1)} ({m.group(2)} files)"),
        (r"^некорректный API URL: (.+)$", lambda m: f"invalid API URL: {m.group(1)}"),
        (r"^сервер недоступен: (.+)$", lambda m: f"server unavailable: {m.group(1)}"),
        (r"^сервер вернул не JSON \(HTTP (\d+)\)$", lambda m: f"the server returned non-JSON data (HTTP {m.group(1)})"),
        (r"^сервер ответил HTTP (\d+)$", lambda m: f"the server returned HTTP {m.group(1)}"),
        (r"^опасный путь в ZIP: (.+)$", lambda m: f"unsafe path in ZIP: {m.group(1)}"),
        (r"^файл в архиве слишком большой: (.+)$", lambda m: f"a file in the archive is too large: {m.group(1)}"),
        (r"^дубликат файла в архиве: (.+)$", lambda m: f"duplicate file in the archive: {m.group(1)}"),
        (r"^в архиве нет (.+)\.toc$", lambda m: f"the archive has no {m.group(1)}.toc"),
        (r"^не удалось скачать CatQuest: HTTP (\d+)$", lambda m: f"could not download CatQuest: HTTP {m.group(1)}"),
        (r"^не удалось обновить (.+): файл занят\. Закройте WoW и повторите$", lambda m: f"could not update {m.group(1)}: the file is in use; close WoW and try again"),
        (r"^SHA-256 ZIP CatQuest не совпал с release$", lambda m: "the CatQuest ZIP SHA-256 does not match the release"),
        (r"^установлен (.+) \((\d+) файлов\)$", lambda m: f"installed {m.group(1)} ({m.group(2)} files)"),
        (r"^скачана дорожка (\d+) (.+)$", lambda m: f"downloaded track {m.group(1)} {m.group(2)}"),
        (r"^пропуск (\d+) (.+): (.+)$", lambda m: f"skipped {m.group(1)} {m.group(2)}: {m.group(3)}"),
        (r"^дорожка (\d+) (.+) уже готова$", lambda m: f"track {m.group(1)} {m.group(2)} is already ready"),
        (r"^запрос (\d+) (.+) принят; жду готовность$", lambda m: f"request {m.group(1)} {m.group(2)} accepted; waiting for completion"),
        (r"^дорожка (\d+) (.+) скачана; нужен /reload$", lambda m: f"track {m.group(1)} {m.group(2)} downloaded; /reload is required"),
        (r"^сервер завершил запрос статусом (.+)$", lambda m: f"the server finished the request with status {m.group(1)}"),
        (r"^не найдена папка Interface\\AddOns в (.+)$", lambda m: f"Interface\\AddOns was not found in {m.group(1)}"),
        (r"^не найдена папка Lasthavens userData: (.+)$", lambda m: f"Lasthavens userData folder was not found: {m.group(1)}"),
        (r"^не удалось открыть папку AddOns в (.+)$", lambda m: f"could not open the AddOns folder in {m.group(1)}"),
        (r"^не найдены файлы (.+): (.+)$", lambda m: f"{m.group(1)} files were not found: {m.group(2)}"),
        (r"^пустой пакет (.+)$", lambda m: f"empty package: {m.group(1)}"),
        (r"^не удалось открыть аудиоустройство: (.+)$", lambda m: f"could not open the audio device: {m.group(1)}"),
        (r"^не удалось установить (.+): файл занят или нет прав$", lambda m: f"could not install {m.group(1)}: the file is in use or access was denied"),
        (r"^запрос (\d+) (.+) не выполнен: (.+)$", lambda m: f"request {m.group(1)} {m.group(2)} failed: {m.group(3)}"),
        (r"^озвучка не запущена: (.+)$", lambda m: f"voice playback did not start: {m.group(1)}"),
        (r"^аудиопроигрыватель: (.+)$", lambda m: f"audio player: {m.group(1)}"),
        (r"^не удалось подготовить (.+): (.+); повтор через 10 с$", lambda m: f"could not prepare {m.group(1)}: {m.group(2)}; retrying in 10 s"),
        (r"^проверка обновления CatQuest не выполнена: (.+)$", lambda m: f"CatQuest update check failed: {m.group(1)}"),
        (r"^для квеста (\d+) нет текста или дорожки$", lambda m: f"no text or track is available for quest {m.group(1)}"),
        (r"^дорожка (\d+) пока не готова; повторите request позже$", lambda m: f"track {m.group(1)} is not ready; run request again later"),
        (r"^--(.+) должен быть положительным$", lambda m: f"--{m.group(1)} must be positive"),
        (r"^--cell должен быть от 1 до 32$", lambda m: "--cell must be between 1 and 32"),
        (r"^--x и --y не могут быть отрицательными$", lambda m: "--x and --y cannot be negative"),
        (r"^получен запрос: (.+)$", lambda m: f"request received: {m.group(1)}"),
        (r"^воспроизведение: (.+)$", lambda m: f"playing: {m.group(1)}"),
        (r"^обнаружен (.+): (.+)$", lambda m: f"detected {m.group(1)}: {m.group(2)}"),
        (r"^установлен CatQuestCompanion \((\d+) файлов\)$", lambda m: f"CatQuestCompanion installed ({m.group(1)} files)"),
        (r"^текущая версия аддона: (.+)$", lambda m: f"current addon version: {localize_text(m.group(1))}"),
        (r"^поддержка: (.+)$", lambda m: f"support: {m.group(1)}"),
        (r"^Voice API \(по умолчанию (.+)\)$", lambda m: f"Voice API (default: {m.group(1)})"),
        (r"^язык дорожек, например (.+)$", lambda m: f"track language, e.g. {m.group(1).replace(' или ', ' or ')}"),
    )
    for pattern, replacement in patterns:
        match = re.match(pattern, text)
        if match:
            return replacement(match)
    return text


def log(message: str) -> None:
    print(f"[CatQuest] {localize_text(message)}", flush=True)


def installed_addon_version(addons_dir: Path | None = None) -> str:
    directory = addons_dir or CURRENT_ADDONS_DIR
    if directory is None:
        return "не определена"
    try:
        return addon_version(directory, ADDON_FOLDER) or "не установлен"
    except (OSError, NameError):
        return "не определена"


def log_error(message: str, addons_dir: Path | None = None) -> None:
    """Print a recoverable error together with the support chat."""

    log(f"ошибка: {message}")
    log(f"текущая версия аддона: {installed_addon_version(addons_dir)}")
    log(f"поддержка: {SUPPORT_CHAT_URL}")


def print_fatal_error(message: str, addons_dir: Path | None = None) -> None:
    error_line = localize_text("ошибка: " + message)
    version_line = localize_text(
        "текущая версия аддона: " + installed_addon_version(addons_dir)
    )
    support_line = localize_text("поддержка: " + SUPPORT_CHAT_URL)
    print(f"[CatQuest] {error_line}", file=sys.stderr, flush=True)
    print(
        f"[CatQuest] {version_line}",
        file=sys.stderr,
        flush=True,
    )
    print(f"[CatQuest] {support_line}", file=sys.stderr, flush=True)


WOW_PROCESS_NAMES = {
    "wow.exe",
    "wow-64.exe",
    "wowclassic.exe",
    "wowclassic-64.exe",
    "turtlewow.exe",
}


if os.name == "nt":
    _user32 = ctypes.WinDLL("user32", use_last_error=True)
    _kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _EnumWindowsProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    _user32.EnumWindows.argtypes = [_EnumWindowsProc, wintypes.LPARAM]
    _user32.EnumWindows.restype = wintypes.BOOL
    _user32.GetForegroundWindow.restype = wintypes.HWND
    _user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    _user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    _user32.IsWindowVisible.argtypes = [wintypes.HWND]
    _user32.IsWindowVisible.restype = wintypes.BOOL
    _user32.IsIconic.argtypes = [wintypes.HWND]
    _user32.IsIconic.restype = wintypes.BOOL
    _user32.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
    _user32.GetClientRect.restype = wintypes.BOOL
    _user32.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.POINT)]
    _user32.ClientToScreen.restype = wintypes.BOOL
    _user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
    _user32.GetWindowTextLengthW.restype = ctypes.c_int
    _user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    _user32.GetWindowTextW.restype = ctypes.c_int
    _kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    _kernel32.OpenProcess.restype = wintypes.HANDLE
    _kernel32.QueryFullProcessImageNameW.argtypes = [
        wintypes.HANDLE,
        wintypes.DWORD,
        wintypes.LPWSTR,
        ctypes.POINTER(wintypes.DWORD),
    ]
    _kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL
    _kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    _kernel32.CloseHandle.restype = wintypes.BOOL


def _process_executable(pid: int) -> Path | None:
    """Read a process image path without adding a Windows-only dependency."""

    if os.name != "nt":
        return None
    handle = _kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return None
    try:
        buffer = ctypes.create_unicode_buffer(32768)
        size = wintypes.DWORD(len(buffer))
        if not _kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            return None
        return Path(buffer.value)
    finally:
        _kernel32.CloseHandle(handle)


def _visible_windows() -> list[tuple[int, int, bool]]:
    """Return visible, non-minimized top-level windows as hwnd/pid/foreground."""

    if os.name != "nt":
        return []
    foreground = int(_user32.GetForegroundWindow() or 0)
    result: list[tuple[int, int, bool]] = []

    @_EnumWindowsProc
    def callback(hwnd: int, _lparam: int) -> bool:
        if not _user32.IsWindowVisible(hwnd) or _user32.IsIconic(hwnd):
            return True
        pid = wintypes.DWORD()
        _user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value:
            result.append((int(hwnd), int(pid.value), int(hwnd) == foreground))
        return True

    _user32.EnumWindows(callback, 0)
    return result


def _client_rect(hwnd: int) -> tuple[int, int, int, int] | None:
    """Return the physical client-area rectangle on the desktop."""

    if os.name != "nt":
        return None
    rect = wintypes.RECT()
    point = wintypes.POINT()
    if not _user32.GetClientRect(hwnd, ctypes.byref(rect)):
        return None
    if not _user32.ClientToScreen(hwnd, ctypes.byref(point)):
        return None
    width = int(rect.right - rect.left)
    height = int(rect.bottom - rect.top)
    if width < PIXEL_COLS * PIXEL_CELL or height < PIXEL_ROWS * PIXEL_CELL:
        return None
    return int(point.x), int(point.y), width, height


def _wow_root_for_executable(executable: Path) -> Path | None:
    """Find the nearest ordinary WoW root with an Interface directory."""

    name = executable.name.lower()
    for candidate in (executable.parent, *executable.parents):
        addons = candidate / "Interface" / "AddOns"
        if addons.is_dir():
            return candidate
        if name in WOW_PROCESS_NAMES and (candidate / "Interface").is_dir():
            try:
                addons.mkdir(exist_ok=True)
            except OSError:
                return None
            return candidate
    return None


def detect_running_game(args: argparse.Namespace) -> RunningGame | None:
    """Detect the active supported game client on Windows."""

    if os.name != "nt":
        raise ClientError("авто-режим сейчас поддерживается только в Windows")
    configured_lh = (
        Path(args.lasthavens_dir).expanduser().resolve()
        if args.lasthavens_dir
        else Path(os.environ.get("APPDATA", "")) / "Lasthavens"
    )
    configured_wow = (
        Path(args.wow_dir).expanduser().resolve() if args.wow_dir else None
    )
    candidates: list[tuple[bool, RunningGame]] = []
    seen_pids: set[int] = set()
    for hwnd, pid, foreground in _visible_windows():
        if pid in seen_pids:
            continue
        seen_pids.add(pid)
        executable = _process_executable(pid)
        if not executable:
            continue
        name = executable.name.lower()
        if name == "lasthavens.exe":
            root = configured_lh
            if not root.is_dir() or not (root / "AddOns").is_dir():
                continue
            candidate = RunningGame("lasthavens", pid, hwnd, executable, root, root / "AddOns")
        else:
            root = _wow_root_for_executable(executable)
            if not root:
                continue
            if configured_wow and root != configured_wow:
                continue
            candidate = RunningGame(
                "wow", pid, hwnd, executable, root, root / "Interface" / "AddOns"
            )
        if _client_rect(hwnd) is not None:
            candidates.append((foreground, candidate))
    if not candidates:
        return None
    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1]


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


def resolve_lasthavens_dir(value: str | None) -> Path:
    """Return an existing Lasthavens userData directory."""

    if not value:
        raise ClientError("для Lasthavens нужен --lasthavens-dir")
    path = Path(value).expanduser().resolve()
    if not path.is_dir():
        raise ClientError(f"не найдена папка Lasthavens userData: {path}")
    addons = path / "AddOns"
    try:
        addons.mkdir(exist_ok=True)
    except OSError as error:
        raise ClientError(f"не удалось открыть папку AddOns в {path}") from error
    return path


def resolve_target_dirs(args: argparse.Namespace) -> tuple[Path, Path]:
    """Return (install root, addon directory) for WoW or Lasthavens."""

    global CURRENT_ADDONS_DIR
    if args.lasthavens_dir:
        root = resolve_lasthavens_dir(args.lasthavens_dir)
        addons_dir = root / "AddOns"
        CURRENT_ADDONS_DIR = addons_dir
        return root, addons_dir
    root = resolve_wow_dir(args.wow_dir)
    addons_dir = root / "Interface" / "AddOns"
    CURRENT_ADDONS_DIR = addons_dir
    return root, addons_dir


def command_sync(args: argparse.Namespace) -> int:
    _, addons_dir = resolve_target_dirs(args)
    api = Api(args.api, args.timeout)
    if not args.no_addon_update:
        release_addon(api, addons_dir, args.channel, args.force)
    server_dir = addons_dir / SERVER_FOLDER
    sync_tracks(api, server_dir, normalize_locale(args.locale), args.books, args.force, args.limit)
    log("готово. Перезагрузите игру или выполните /reload")
    return 0


def command_request(args: argparse.Namespace) -> int:
    _, addons_dir = resolve_target_dirs(args)
    api = Api(args.api, args.timeout)
    locale = normalize_locale(args.locale)
    server_dir = addons_dir / SERVER_FOLDER
    server_dir.mkdir(parents=True, exist_ok=True)
    ok = request_track(api, server_dir, locale, int(args.quest_id), args.quest_type, args.wait)
    if ok:
        refresh_manifest(api, server_dir, locale, [(int(args.quest_id), args.quest_type)])
        save_state(server_dir, load_state(server_dir))
        log("готово. Выполните /reload, чтобы WoW увидел новый файл")
    return 0 if ok else 2


def command_watch(args: argparse.Namespace) -> int:
    if args.lasthavens_dir:
        raise ClientError(
            "watch не поддерживается для Lasthavens: Desktop не хранит WoW SavedVariables в WTF"
        )
    wow_dir, addons_dir = resolve_target_dirs(args)
    api = Api(args.api, args.timeout)
    locale = normalize_locale(args.locale)
    server_dir = addons_dir / SERVER_FOLDER
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
                    log_error(f"запрос {quest_id} {request_type} не выполнен: {error}")
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


def load_companion_dependencies() -> tuple[Any, Any]:
    try:
        import mss
        import pygame
    except ImportError as error:
        raise ClientError(
            "для companion нужны зависимости: python -m pip install -r client\\requirements.txt"
        ) from error
    return mss, pygame


def validate_companion_options(args: argparse.Namespace) -> None:
    if args.cell < 1 or args.cell > 32:
        raise ClientError("--cell должен быть от 1 до 32")
    if args.fps <= 0:
        raise ClientError("--fps должен быть положительным")


def prepare_companion_target(
    api: Api, args: argparse.Namespace, addons_dir: Path
) -> Path:
    global CURRENT_ADDONS_DIR
    CURRENT_ADDONS_DIR = addons_dir
    if not args.no_addon_update:
        release_addon(api, addons_dir, args.channel, args.force)
    install_companion_addon(addons_dir)
    server_dir = addons_dir / SERVER_FOLDER
    server_dir.mkdir(parents=True, exist_ok=True)
    return server_dir


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
                log_error(f"озвучка не запущена: {error}", self.server_dir.parent)
            except Exception as error:
                log_error(f"аудиопроигрыватель: {error}", self.server_dir.parent)

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
    validate_companion_options(args)
    if args.x < 0 or args.y < 0:
        raise ClientError("--x и --y не могут быть отрицательными")
    _, addons_dir = resolve_target_dirs(args)
    api = Api(args.api, args.timeout)
    server_dir = prepare_companion_target(api, args, addons_dir)
    mss, pygame = load_companion_dependencies()

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


def command_hybrid(args: argparse.Namespace) -> int:
    """Wait for a supported game and run the companion against its active window."""

    validate_companion_options(args)
    if args.poll <= 0:
        raise ClientError("--poll должен быть положительным")
    if args.update_interval <= 0:
        raise ClientError("--update-interval должен быть положительным")
    api = Api(args.api, args.timeout)
    mss, pygame = load_companion_dependencies()
    player: CompanionPlayer | None = None
    active_key: tuple[str, int, str] | None = None
    decoder = CompanionDecoder()
    last_wait_log = 0.0
    retry_after = 0.0
    next_update_at = 0.0
    log("авто-гибрид запущен; ожидаю окно WoW или Lasthavens Desktop")
    try:
        with mss.mss() as capture:
            while True:
                now = time.monotonic()
                target = detect_running_game(args)
                if target is None:
                    if player is not None:
                        player.close()
                        player = None
                        active_key = None
                        decoder = CompanionDecoder()
                        log("игра закрыта или свёрнута; жду следующий запуск")
                    if now - last_wait_log >= 5.0:
                        log("игра не найдена; жду запуска...")
                        last_wait_log = now
                    time.sleep(max(0.25, args.poll))
                    continue

                key = (target.kind, target.pid, str(target.root))
                if key != active_key and now >= retry_after:
                    if player is not None:
                        player.close()
                        player = None
                    try:
                        server_dir = prepare_companion_target(api, args, target.addons_dir)
                        player = CompanionPlayer(api, server_dir, args.timeout, args.wait, pygame)
                        player.start()
                    except (ClientError, OSError) as error:
                        log_error(
                            f"не удалось подготовить {target.kind}: {error}; повтор через 10 с",
                            target.addons_dir,
                        )
                        retry_after = now + 10.0
                        time.sleep(1.0)
                        continue
                    active_key = key
                    decoder = CompanionDecoder()
                    next_update_at = (
                        float("inf")
                        if args.no_addon_update
                        else now + args.update_interval
                    )
                    label = "Lasthavens Desktop" if target.kind == "lasthavens" else "обычный WoW"
                    log(f"обнаружен {label}: {target.executable}")

                if player is None:
                    time.sleep(0.25)
                    continue
                if now >= next_update_at:
                    try:
                        changed = release_addon(
                            api, target.addons_dir, args.channel, args.force
                        )
                        install_companion_addon(target.addons_dir)
                        if changed:
                            log("CatQuest обновлён; выполните /reload в игре")
                    except (ClientError, OSError) as error:
                        log_error(
                            f"проверка обновления CatQuest не выполнена: {error}",
                            target.addons_dir,
                        )
                    finally:
                        next_update_at = now + args.update_interval
                bounds = _client_rect(target.hwnd)
                if bounds is None:
                    time.sleep(0.25)
                    continue
                left, top, _, _ = bounds
                monitor = {
                    "left": left,
                    "top": top,
                    "width": PIXEL_COLS * args.cell,
                    "height": PIXEL_ROWS * args.cell,
                }
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
                time.sleep(1.0 / max(10.0, min(120.0, args.fps)))
    except KeyboardInterrupt:
        log("авто-гибрид остановлен")
        return 0
    finally:
        if player is not None:
            player.close()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", action="version", version=f"CatQuest Client {APP_VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)

    def common(command: argparse.ArgumentParser) -> None:
        target = command.add_mutually_exclusive_group(required=True)
        target.add_argument(
            "--wow-dir",
            help=localize_text("корень обычного WoW с Interface\\AddOns"),
        )
        target.add_argument(
            "--lasthavens-dir",
            help=localize_text("userData Lasthavens Desktop, например %%APPDATA%%\\Lasthavens"),
        )
        command.add_argument("--api", default=DEFAULT_API, help=localize_text(f"Voice API (по умолчанию {DEFAULT_API})"))
        command.add_argument("--locale", default="ruRU", help=localize_text("язык дорожек, например ruRU или enUS"))
        command.add_argument("--timeout", type=float, default=30.0)

    sync = sub.add_parser("sync", help=localize_text("обновить CatQuest и скачать готовые серверные дорожки"))
    common(sync)
    sync.add_argument("--channel", choices=("stable", "beta"), default="stable")
    sync.add_argument("--force", action="store_true", help=localize_text("скачать заново даже файлы того же размера"))
    sync.add_argument("--books", action="store_true", help=localize_text("скачать также книги и лор мест"))
    sync.add_argument("--limit", type=int, help=localize_text("ограничить число квестовых дорожек за запуск"))
    sync.add_argument("--no-addon-update", action="store_true")
    sync.set_defaults(handler=command_sync)

    request = sub.add_parser("request", help=localize_text("запросить одну серверную дорожку и сохранить её локально"))
    common(request)
    request.add_argument("quest_id", type=int)
    request.add_argument("quest_type", choices=("DETAIL", "COMPLETE"))
    request.add_argument("--wait", type=float, default=180.0, help=localize_text("сколько секунд ждать генерацию"))
    request.set_defaults(handler=command_request)

    watch = sub.add_parser("watch", help=localize_text("синхронизировать готовые дорожки и читать SavedVariables"))
    common(watch)
    watch.add_argument("--books", action="store_true")
    watch.add_argument("--limit", type=int)
    watch.add_argument("--interval", type=float, default=300.0)
    watch.add_argument("--wait", type=float, default=15.0)
    watch.set_defaults(handler=command_watch)

    companion = sub.add_parser(
        "companion",
        help=localize_text("запустить живой экранный мост и проигрывать серверную озвучку вне WoW"),
    )
    common(companion)
    companion.add_argument("--channel", choices=("stable", "beta"), default="stable")
    companion.add_argument("--force", action="store_true")
    companion.add_argument("--no-addon-update", action="store_true")
    companion.add_argument("--wait", type=float, default=20.0, help=localize_text("ожидание одного запроса gossip"))
    companion.add_argument("--x", type=int, default=0, help=localize_text("X области захвата экрана"))
    companion.add_argument("--y", type=int, default=0, help=localize_text("Y области захвата экрана"))
    companion.add_argument("--cell", type=int, default=PIXEL_CELL, help=localize_text("размер пиксельной клетки"))
    companion.add_argument("--fps", type=float, default=60.0, help=localize_text("частота чтения экрана"))
    companion.set_defaults(handler=command_companion)

    hybrid = sub.add_parser(
        "hybrid",
        aliases=["auto"],
        help=localize_text("автоматически найти запущенный WoW/Lasthavens и запустить Hybrid"),
    )
    target = hybrid.add_mutually_exclusive_group()
    target.add_argument(
        "--wow-dir",
        help=localize_text("ограничить поиск указанной установкой обычного WoW"),
    )
    target.add_argument(
        "--lasthavens-dir",
        help=localize_text("userData Lasthavens Desktop, например %%APPDATA%%\\Lasthavens"),
    )
    hybrid.add_argument("--api", default=DEFAULT_API, help=localize_text(f"Voice API (по умолчанию {DEFAULT_API})"))
    hybrid.add_argument("--locale", default="ruRU", help=localize_text("язык дорожек, например ruRU или enUS"))
    hybrid.add_argument("--timeout", type=float, default=30.0)
    hybrid.add_argument("--channel", choices=("stable", "beta"), default="stable")
    hybrid.add_argument("--force", action="store_true")
    hybrid.add_argument("--no-addon-update", action="store_true")
    hybrid.add_argument("--wait", type=float, default=20.0, help=localize_text("ожидание одного запроса gossip"))
    hybrid.add_argument("--cell", type=int, default=PIXEL_CELL, help=localize_text("размер пиксельной клетки"))
    hybrid.add_argument("--fps", type=float, default=60.0, help=localize_text("частота чтения экрана"))
    hybrid.add_argument("--poll", type=float, default=1.0, help=localize_text("интервал поиска игры"))
    hybrid.add_argument(
        "--update-interval",
        type=float,
        default=DEFAULT_UPDATE_INTERVAL,
        help=localize_text("интервал проверки обновления CatQuest в секундах"),
    )
    hybrid.set_defaults(handler=command_hybrid)
    return parser


def main(argv: list[str] | None = None) -> int:
    try:
        args = build_parser().parse_args(argv)
        return int(args.handler(args))
    except ClientError as error:
        print_fatal_error(str(error))
        return 1
    except KeyboardInterrupt:
        print("\n[CatQuest] остановлено", file=sys.stderr)
        return 130
    except Exception as error:
        print_fatal_error(f"непредвиденная ошибка: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
