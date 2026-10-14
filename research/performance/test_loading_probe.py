"""Exercise loading-probe teardown with real mixer playback and an intentional retained reference.

python research/performance/test_loading_probe.py --godot <pinned-engine>
Fixtures stay outside app/ and cannot modify user settings.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "research/performance/loading_probe.gd"

FIXTURE = '''extends "{probe}"
var _held: AudioStreamPlayback

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0]
	_settings_path = args[1] + ".settings.cfg"
	var settings := FileAccess.open(_settings_path, FileAccess.WRITE)
	settings.store_string("owned by test")
	settings.close()
	_app = Node3D.new()
	root.add_child(_app)
	var player := AudioStreamPlayer3D.new()
	var stream: AudioStreamMP3 = load("res://assets/audio/water/randommind-vistula-short.mp3").duplicate()
	stream.loop = true
	player.stream = stream
	_app.add_child(player)
	player.play()
	await physics_frame
	await process_frame
	if not player.has_stream_playback():
		_fail("fixture has no playback")
		return
	var node_ref: WeakRef = weakref(_app)
	if mode == "failure":
		_fail("intentional failure after settings and audio creation")
		return
	if mode == "retained":
		_held = player.get_stream_playback()
	var shutdown := await _cleanup()
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	output.store_string(JSON.stringify({{shutdown = shutdown, app_freed = node_ref.get_ref() == null}}))
	output.close()
	_held = null
	await create_timer(0.2).timeout
	if mode == "retained":
		_fail("intentional retained playback timeout")
		return
	quit(0)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    engine = str(args.godot.resolve())
    with tempfile.TemporaryDirectory(prefix="openrc-loading-probe-") as directory:
        folder = Path(directory)
        script = folder / "fixture.gd"
        script.write_text(FIXTURE.format(probe=PROBE.as_posix()), encoding="utf-8")
        for mode in ("success", "failure", "retained"):
            output = folder / (mode + ".json")
            command = [engine, "--headless", "--path", str(ROOT / "app"), "--audio-driver", "Dummy",
                       "--verbose", "--script", str(script), "--", mode, str(output)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=15)
            log = result.stdout + result.stderr
            assert result.returncode == (0 if mode == "success" else 1), log
            assert not Path(str(output) + ".settings.cfg").exists(), log
            assert "instances were leaked" not in log, log
            if mode == "failure":
                assert "intentional failure after settings and audio creation" in log, log
                assert '"audio_released":true' in log and '"settings_removed":true' in log, log
                assert not output.exists(), "Failure must not emit a successful timing report"
                assert log.count("ERROR:") == 1, log
            else:
                if mode == "success":
                    assert not re.search(r"(?m)^(?:SCRIPT )?ERROR:", log), log
                else:
                    assert "intentional retained playback timeout" in log and log.count("ERROR:") == 1, log
                report = json.loads(output.read_text())
                state = report["shutdown"]
                assert report["app_freed"] and state["settings_removed"], report
                assert state["tracked_playbacks"] == 1, report
                assert state["audio_released"] == (mode == "success"), report
                assert state["remaining_playbacks"] == (0 if mode == "success" else 1), report
                if mode == "retained":
                    assert 1_000_000 <= state["elapsed_usec"] < 2_000_000, report
            print("PASS", mode, flush=True)
        # A rejected invocation must never remove an existing output or settings file.
        output = folder / "existing.json"
        settings = Path(str(output) + ".settings.cfg")
        output.write_bytes(b"existing report")
        settings.write_bytes(b"existing settings")
        rejected = subprocess.run([engine, "--headless", "--path", str(ROOT / "app"), "--audio-driver",
                                   "Dummy", "--script", str(PROBE), "--", "--output=" + str(output)],
                                  capture_output=True, timeout=15)
        assert rejected.returncode == 1
        assert output.read_bytes() == b"existing report" and settings.read_bytes() == b"existing settings"
        print("PASS existing files preserved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
