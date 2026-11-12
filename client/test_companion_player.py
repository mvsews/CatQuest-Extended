"""Regression checks for stopping the external companion player."""

import importlib.util
import threading
from pathlib import Path
from types import SimpleNamespace


CLIENT = Path(__file__).resolve().parent / "catquest_client.py"
spec = importlib.util.spec_from_file_location("catquest_client", CLIENT)
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)


class Music:
    def __init__(self):
        self.calls = []
        self.playing = False
        self.started = threading.Event()
        self.release = threading.Event()

    def stop(self):
        self.calls.append("stop")
        self.playing = False

    def load(self, path):
        self.calls.append("load")

    def play(self):
        self.started.set()
        self.release.wait(timeout=2)
        self.calls.append("play")
        self.playing = True


def player_with(music, monkeypatch, fetch):
    monkeypatch.setattr(client, "fetch_companion_audio", fetch)
    mixer = SimpleNamespace(music=music, init=lambda: None, quit=lambda: None)
    player = client.CompanionPlayer(None, Path("."), 1, 1, SimpleNamespace(mixer=mixer))
    player.start()
    return player


def test_stop_while_fetching_does_not_start_audio(monkeypatch):
    music = Music()
    fetched = threading.Event()
    release = threading.Event()

    def fetch(*args):
        fetched.set()
        release.wait(timeout=2)
        return Path("voice.ogg")

    player = player_with(music, monkeypatch, fetch)
    try:
        player.enqueue({"kind": "quest"})
        assert fetched.wait(timeout=2)
        player.stop()
        release.set()
        player.jobs.put(None)
        player.thread.join(timeout=2)
        assert not player.thread.is_alive()
        assert "play" not in music.calls
    finally:
        player.close()


def test_stop_during_play_leaves_audio_stopped(monkeypatch):
    music = Music()
    player = player_with(music, monkeypatch, lambda *args: Path("voice.ogg"))
    try:
        player.enqueue({"kind": "quest"})
        assert music.started.wait(timeout=2)
        stopped = threading.Thread(target=player.stop)
        stopped.start()
        music.release.set()
        stopped.join(timeout=2)
        assert not stopped.is_alive()
        assert music.calls[-1] == "stop"
        assert not music.playing
    finally:
        player.close()
