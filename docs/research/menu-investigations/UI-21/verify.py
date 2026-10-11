"""UI-21 same-host visual and direct-flight parity, using isolated source snapshots.

Python standard library; pinned Godot 4.7.2 and a working display. Output must be fresh.
The source snapshots must differ only by the UI-21 implementation. This is software
verification, not GPU performance, fullscreen, radio-hardware or pilot acceptance.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, log, env):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=180, env=env)
    log.write_text(result.stdout, encoding="utf-8")
    if result.returncode or "ERROR:" in result.stdout:
        raise RuntimeError(f"Engine failed: {log}\n{result.stdout}")
    return result.stdout


def verify(args):
    for key in ("before", "after", "godot", "out"):
        setattr(args, key, getattr(args, key).resolve())
    args.out.mkdir(parents=True, exist_ok=False)
    engine = str(args.godot.resolve())
    cases = [(screen, lang, "1280x720", "")
             for lang in ("en", "es") for screen in ("home", "help", "pause")]
    cases += [("home", lang, "1920x1080", "") for lang in ("en", "es")]
    cases += [("weather", lang, "1280x720", tab) for lang in ("en", "es")
              for tab in ("wind", "turbulence", "atmosphere")]
    cases += [("tod", lang, "1280x720", "") for lang in ("en", "es")]
    for label, repo in (("before", args.before), ("after", args.after)):
        destination = args.out / label
        destination.mkdir()
        env = dict(os.environ, XDG_DATA_HOME=str(destination / "capture-user"))
        common = [engine, "--path", str(repo / "app"), "--audio-driver", "Dummy"]
        run(common + ["--headless", "--import"], destination / "import.log", env)
        with tempfile.TemporaryDirectory(prefix="ui21-capture-") as temporary:
            # Wall-time flight waits can capture different physical ticks. Keep the TOD
            # background at the initial pose in both snapshots; no production file changes.
            source = (repo / "app/tests/capture_time_of_day_dialog.gd").read_text(encoding="utf-8")
            assert source.count("await create_timer(0.5).timeout") == 1
            controlled = Path(temporary) / "capture_time_of_day_dialog.gd"
            controlled.write_text(source.replace("await create_timer(0.5).timeout",
                                                 "app.open_pause() # UI-21: freeze before the first physics tick"),
                                  encoding="utf-8")
            for screen, lang, size, tab in cases:
                name = "-".join(part for part in (screen, lang, size, tab) if part)
                script = str(controlled) if screen == "tod" else "res://tests/capture_ui.gd"
                command = common + ["--rendering-driver", "opengl3", "--fixed-fps", "60",
                                    "--script", script, "--", f"--out={destination / (name + '.png')}",
                                    f"--lang={lang}", f"--size={size}"]
                if screen != "tod":
                    command += [f"--screen={screen}"]
                if tab:
                    command += [f"--weather-tab={tab}"]
                run(command, destination / (name + ".log"), env)
                assert (destination / (name + ".png")).is_file(), name
                print(label, name, flush=True)
        trace_user = destination / "trace-user"
        trace = destination / "flight.csv"
        run(common + ["--headless", "--", f"--trace={trace}", "--t=3"],
            destination / "trace.log", dict(os.environ, XDG_DATA_HOME=str(trace_user)))
        assert not list(trace_user.rglob("settings.cfg")), "Direct flight wrote player settings"

    captures = []
    for screen, lang, size, tab in cases:
        name = "-".join(part for part in (screen, lang, size, tab) if part) + ".png"
        before, after = [sha(args.out / label / name) for label in ("before", "after")]
        captures.append({"image": name, "before_sha256": before, "after_sha256": after,
                         "identical": before == after, "initial_pose_background": screen == "tod"})
    assert all(item["identical"] for item in captures), "Capture pixels changed"
    traces = [(args.out / label / "flight.csv").read_bytes() for label in ("before", "after")]
    # Wall-clock creation time is the only deliberately excluded trace metadata.
    canonical = [b"\n".join(line for line in trace.splitlines()
                              if not line.startswith(b"# created_utc: ")) for trace in traces]
    assert canonical[0] == canonical[1], "Flight data or stable metadata changed"
    samples = [line for line in canonical[0].splitlines() if line and not line.startswith(b"#")]
    assert len(samples) - 1 == 721, "Expected initial sample and 720 physics ticks"
    menu_files = ["app/app_root.gd", "app/tests/test_ui_screen_stack.gd"] + [
        f"app/ui/{name}.gd" for name in ("screen", "screen_stack", "widgets", "home", "pause_menu",
                                       "help_screen", "weather_dialog", "time_of_day_dialog")]
    report = {"format": "openrc-ui21-parity v1", "captures": captures,
              "capture_pairs": len(captures), "identical_pairs": len(captures),
              "trace": {"identical_except_created_utc": True, "samples": 721,
                        "canonical_sha256": hashlib.sha256(canonical[0]).hexdigest(),
                        "before_sha256": hashlib.sha256(traces[0]).hexdigest(),
                        "after_sha256": hashlib.sha256(traces[1]).hexdigest(),
                        "direct_route_wrote_settings": False},
              "after_source_sha256": {name: sha(args.after / name) for name in menu_files},
              "performance_claim": False}
    (args.out / "parity.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("16/16 identical capture pairs; 721 identical flight samples and stable metadata")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("before", "after", "godot", "out"):
        parser.add_argument("--" + key, type=Path, required=True)
    verify(parser.parse_args())
