#!/usr/bin/env python3
"""Drive the exported app's Home-to-runway route with native X11 keyboard events."""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from typing import Any


class X11:
    XK_RETURN = 0xFF0D
    XK_UP = 0xFF52
    XK_DOWN = 0xFF54
    XK_ESCAPE = 0xFF1B

    def __init__(self) -> None:
        x11_path = ctypes.util.find_library("X11")
        xtst_path = ctypes.util.find_library("Xtst")
        if not x11_path or not xtst_path:
            raise RuntimeError("libX11 and libXtst are required for native keyboard injection")
        self.x11 = ctypes.CDLL(x11_path)
        self.xtst = ctypes.CDLL(xtst_path)
        self._bind()
        self.display = self.x11.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError(f"cannot open X display {os.environ.get('DISPLAY', '')!r}")

    def _bind(self) -> None:
        self.x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.x11.XOpenDisplay.restype = ctypes.c_void_p
        self.x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        self.x11.XDefaultRootWindow.restype = ctypes.c_ulong
        self.x11.XQueryTree.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulong,
            ctypes.POINTER(ctypes.c_ulong),
            ctypes.POINTER(ctypes.c_ulong),
            ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)),
            ctypes.POINTER(ctypes.c_uint),
        ]
        self.x11.XQueryTree.restype = ctypes.c_int
        self.x11.XFetchName.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_void_p)]
        self.x11.XFetchName.restype = ctypes.c_int
        self.x11.XFree.argtypes = [ctypes.c_void_p]
        self.x11.XFree.restype = ctypes.c_int
        self.x11.XSetInputFocus.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
        self.x11.XSetInputFocus.restype = ctypes.c_int
        self.x11.XFlush.argtypes = [ctypes.c_void_p]
        self.x11.XFlush.restype = ctypes.c_int
        self.x11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        self.x11.XKeysymToKeycode.restype = ctypes.c_uint
        self.xtst.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
        self.xtst.XTestFakeKeyEvent.restype = ctypes.c_int
        self.x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
        self.x11.XCloseDisplay.restype = ctypes.c_int

    def close(self) -> None:
        if self.display:
            self.x11.XCloseDisplay(self.display)
            self.display = None

    def _children(self, window: int) -> list[int]:
        root = ctypes.c_ulong()
        parent = ctypes.c_ulong()
        children = ctypes.POINTER(ctypes.c_ulong)()
        count = ctypes.c_uint()
        if not self.x11.XQueryTree(
            self.display,
            window,
            ctypes.byref(root),
            ctypes.byref(parent),
            ctypes.byref(children),
            ctypes.byref(count),
        ):
            return []
        result = [int(children[index]) for index in range(count.value)] if children else []
        if children:
            self.x11.XFree(ctypes.cast(children, ctypes.c_void_p))
        return result

    def _title(self, window: int) -> str:
        raw_name = ctypes.c_void_p()
        if not self.x11.XFetchName(self.display, window, ctypes.byref(raw_name)) or not raw_name.value:
            return ""
        try:
            return ctypes.string_at(raw_name.value).decode("utf-8", errors="replace")
        finally:
            self.x11.XFree(raw_name)

    def find_window(self, title_fragment: str) -> tuple[int, str] | None:
        queue = self._children(int(self.x11.XDefaultRootWindow(self.display)))
        while queue:
            window = queue.pop(0)
            title = self._title(window)
            if title_fragment.casefold() in title.casefold():
                return window, title
            queue.extend(self._children(window))
        return None

    def focus(self, window: int) -> None:
        # X11's RevertToParent is 2; CurrentTime is zero.
        self.x11.XSetInputFocus(self.display, window, 2, 0)
        self.x11.XFlush(self.display)

    def _fake(self, keysym: int, pressed: bool) -> None:
        keycode = int(self.x11.XKeysymToKeycode(self.display, keysym))
        if keycode == 0:
            raise RuntimeError(f"X server has no keycode for keysym 0x{keysym:x}")
        if not self.xtst.XTestFakeKeyEvent(self.display, keycode, int(pressed), 0):
            raise RuntimeError(f"XTestFakeKeyEvent failed for keycode {keycode}")
        self.x11.XFlush(self.display)

    def tap(self, keysym: int, settle_s: float = 0.3) -> None:
        self._fake(keysym, True)
        time.sleep(0.08)
        self._fake(keysym, False)
        time.sleep(settle_s)

    def hold(self, keysym: int, duration_s: float) -> None:
        self._fake(keysym, True)
        time.sleep(duration_s)
        self._fake(keysym, False)
        self.x11.XFlush(self.display)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def capture(path: Path) -> None:
    from PIL import ImageGrab

    image = ImageGrab.grab(xdisplay=os.environ["DISPLAY"])
    image.save(path)


def grab_screen():
    from PIL import ImageGrab

    return ImageGrab.grab(xdisplay=os.environ["DISPLAY"])


def screen_brightness(image) -> float:
    from PIL import ImageStat

    return sum(ImageStat.Stat(image.convert("RGB").resize((80, 45))).mean) / 3.0


def changed_pixel_fraction(before, after, threshold: int = 35) -> float:
    from PIL import ImageChops

    delta = ImageChops.difference(before.convert("RGB").resize((80, 45)), after.convert("RGB").resize((80, 45)))
    return sum(1 for pixel in delta.getdata() if max(pixel) > threshold) / (80 * 45)


def wait_for_home(timeout_s: float = 90.0):
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        image = grab_screen()
        if screen_brightness(image) > 70.0:
            time.sleep(1.0)
            return grab_screen()
        time.sleep(0.5)
    raise TimeoutError(f"the Godot splash did not transition to Home within {timeout_s:.0f}s")


def wait_for_screen_change(before, timeout_s: float = 45.0):
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        image = grab_screen()
        if changed_pixel_fraction(before, image) > 0.4:
            time.sleep(0.5)
            return grab_screen()
        time.sleep(0.5)
    raise TimeoutError("Home did not transition to the flight scene; inspect exported-gui.log and screenshots")


def find_traces(trace_dir: Path) -> list[Path]:
    return sorted(trace_dir.glob("*.csv"), key=lambda item: item.stat().st_mtime_ns) if trace_dir.exists() else []


def wait_for_trace(trace_dir: Path, previous: set[Path], timeout_s: float = 10.0) -> Path:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        found = [path for path in find_traces(trace_dir) if path not in previous]
        if found:
            return found[-1]
        time.sleep(0.1)
    raise TimeoutError(f"Recorder did not save a new trace under {trace_dir}")


def seed_settings(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        '[meta]\nschema=1\n\n[ui]\nlanguage="en"\nfirst_flight_hint_seen=true\n'
        '\n[flight]\naircraft="jensen-das-ugly-stik-60"\nstart_choice="airborne"\n',
        encoding="utf-8",
    )


def read_start_choice(path: Path) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("start_choice="):
            return line.partition("=")[2].strip().strip('"')
    return ""


def parse_trace(path: Path) -> tuple[dict[str, str], list[str], list[dict[str, str]]]:
    import csv

    metadata: dict[str, str] = {}
    header: list[str] = []
    rows: list[dict[str, str]] = []
    with path.open(newline="", encoding="utf-8") as source:
        for line in source:
            if line.startswith("# "):
                key, separator, value = line[2:].rstrip("\r\n").partition(": ")
                if separator:
                    metadata[key] = value
                continue
            if not line.strip():
                continue
            if not header:
                header = next(csv.reader([line]))
            else:
                values = next(csv.reader([line]))
                rows.append(dict(zip(header, values, strict=True)))
    if not header or not rows:
        raise ValueError(f"{path} does not contain a trace row")
    return metadata, header, rows


def record_short_trace(
    x11: X11,
    trace_dir: Path,
    output: Path,
    hold_s: float,
    taxi_capture: Path | None = None,
) -> dict[str, Any]:
    prior = set(find_traces(trace_dir))
    x11.tap(ord("t"))
    x11._fake(ord("w"), True)
    if taxi_capture is not None:
        time.sleep(min(0.5, hold_s))
        capture(taxi_capture)
        if hold_s > 0.5:
            time.sleep(hold_s - 0.5)
    else:
        time.sleep(hold_s)
    x11._fake(ord("w"), False)
    x11.x11.XFlush(x11.display)
    time.sleep(0.3)
    x11.tap(ord("t"))
    saved = wait_for_trace(trace_dir, prior)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(saved.read_bytes())
    metadata, header, rows = parse_trace(output)
    first = rows[0]
    last = rows[-1]
    recording_aux = json.loads(metadata["recording_start_aux"])
    aux_columns = ["engine_rpm", "srv_roll", "srv_pitch", "srv_yaw"]
    aux_match = len(recording_aux) == len(aux_columns) and all(
        abs(float(recording_aux[index]) - float(first[column])) <= 1.0e-8
        for index, column in enumerate(aux_columns)
    )
    return {
        "path": str(output),
        "sha256": sha256_file(output),
        "rows": len(rows),
        "column_count": len(header),
        "recorded_sim_seconds": float(last["t_s"]) - float(first["t_s"]),
        "metadata": metadata,
        "recording_start_tick": int(metadata.get("recording_start_tick", -1)),
        "first_row_tick": int(float(first["tick"])),
        "recording_start_engine_running": metadata.get("recording_start_engine_running", ""),
        "recording_start_aux": recording_aux,
        "recording_aux_matches_first_row": aux_match,
        "throttle_command_start": float(first["cmd_throttle"]),
        "throttle_command_max": max(float(row["cmd_throttle"]) for row in rows),
        "north_delta_m": float(last["north_m"]) - float(first["north_m"]),
        "east_delta_m": float(last["east_m"]) - float(first["east_m"]),
        "horizontal_speed_end_mps": (
            float(last["u_mps"]) ** 2 + float(last["v_mps"]) ** 2
        ) ** 0.5,
    }


def run(binary: Path, out: Path, settings_path: Path, taxi_seconds: float, boot_timeout: float) -> dict[str, Any]:
    report: dict[str, Any] = {
        "format": "openrc-ui06c-export-gui-smoke v1",
        "binary": str(binary),
        "binary_sha256": sha256_file(binary),
        "display": os.environ.get("DISPLAY", ""),
        "screen_size": [1280, 720],
        "home_start_choice_before": "airborne",
        "native_input": "XTestFakeKeyEvent through libXtst",
        "passed": False,
    }
    x11: X11 | None = None
    process: subprocess.Popen[bytes] | None = None
    log_path = out / "exported-gui.log"
    log_handle = None
    copied_traces: list[Path] = []
    try:
        seed_settings(settings_path)
        trace_dir = settings_path.parent / "traces"
        for trace in find_traces(trace_dir):
            trace.unlink()
        x11 = X11()
        log_handle = log_path.open("wb")
        process = subprocess.Popen(
            [str(binary), "--audio-driver", "Dummy"],
            env=os.environ.copy(),
            stdin=subprocess.DEVNULL,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
        )
        report["process_pid"] = process.pid
        deadline = time.monotonic() + boot_timeout
        window: tuple[int, str] | None = None
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError(f"exported app exited during startup with code {process.returncode}")
            window = x11.find_window("OpenRC Simulator")
            if window:
                break
            time.sleep(0.25)
        if not window:
            raise TimeoutError(f"no OpenRC Simulator X11 window appeared within {boot_timeout:.0f}s")
        window_id, title = window
        report["window_title"] = title
        report["window_id"] = window_id
        x11.focus(window_id)
        home_image = wait_for_home()
        home_capture = out / "home-airborne.png"
        home_image.save(home_capture)
        report["home_airborne_capture"] = {"path": str(home_capture), "sha256": sha256_file(home_capture)}

        # Wait through the Godot loading splash before driving Home. Home focuses Fly; Up selects Start and Enter
        # chooses runway, then Down returns focus to Fly.
        x11.tap(X11.XK_UP)
        x11.tap(X11.XK_RETURN)
        time.sleep(0.5)
        runway_capture = out / "home-runway.png"
        capture(runway_capture)
        report["home_runway_capture"] = {"path": str(runway_capture), "sha256": sha256_file(runway_capture)}
        x11.tap(X11.XK_DOWN)
        x11.tap(X11.XK_RETURN, settle_s=1.0)

        # A successful Home Fly writes this choice; a failed launch returns Home and leaves it airborne.
        flight_deadline = time.monotonic() + 45.0
        while time.monotonic() < flight_deadline:
            if process.poll() is not None:
                raise RuntimeError(f"exported app exited during Home Fly with code {process.returncode}")
            if settings_path.is_file() and read_start_choice(settings_path) == "runway":
                break
            time.sleep(0.25)
        if not settings_path.is_file() or read_start_choice(settings_path) != "runway":
            raise TimeoutError("Home Fly did not save the runway preference; inspect exported-gui.log and capture")
        report["saved_start_choice_after_fly"] = read_start_choice(settings_path)
        flight_image = wait_for_screen_change(home_image)
        flight_capture = out / "flight-runway.png"
        flight_image.save(flight_capture)
        report["flight_capture"] = {"path": str(flight_capture), "sha256": sha256_file(flight_capture)}

        initial_trace = record_short_trace(
            x11, trace_dir, out / "runway-manual.csv", taxi_seconds, out / "flight-taxi.png"
        )
        copied_traces.append(Path(initial_trace["path"]))
        report["manual_trace"] = initial_trace
        report["taxi_capture"] = {
            "path": str(out / "flight-taxi.png"),
            "sha256": sha256_file(out / "flight-taxi.png"),
        }

        # R uses the selected product choice. A newly started recording captures the restarted first row.
        x11.tap(ord("r"), settle_s=0.4)
        time.sleep(1.1)
        r_trace = record_short_trace(x11, trace_dir, out / "runway-r-restart.csv", 0.2)
        copied_traces.append(Path(r_trace["path"]))
        report["r_restart_trace"] = r_trace

        # Esc opens the pause menu, Down focuses Restart, and Enter activates that real menu button.
        x11.tap(X11.XK_ESCAPE)
        x11.tap(X11.XK_DOWN)
        x11.tap(X11.XK_RETURN, settle_s=0.5)
        time.sleep(1.1)
        pause_capture = out / "flight-pause-restart.png"
        capture(pause_capture)
        report["pause_restart_capture"] = {"path": str(pause_capture), "sha256": sha256_file(pause_capture)}
        pause_trace = record_short_trace(x11, trace_dir, out / "runway-pause-restart.csv", 0.2)
        copied_traces.append(Path(pause_trace["path"]))
        report["pause_restart_trace"] = pause_trace

        for trace_name, trace_report in [
            ("manual_trace", initial_trace),
            ("r_restart_trace", r_trace),
            ("pause_restart_trace", pause_trace),
        ]:
            meta = trace_report["metadata"]
            if meta.get("selected_start_choice") != "runway" or meta.get("launch_choice") != "runway":
                raise RuntimeError(f"{trace_name} does not identify the selected and actual runway start")
            if meta.get("launch_kind") != "runway_threshold" or meta.get("launch_field_id") != "default":
                raise RuntimeError(f"{trace_name} has unexpected runway launch kind or field")
            if meta.get("launch_engine_running") != "true" or meta.get("launch_error"):
                raise RuntimeError(f"{trace_name} has an invalid engine state or launch error")
            if len(json.loads(meta.get("launch_state", "[]"))) == 0:
                raise RuntimeError(f"{trace_name} lacks the launch state snapshot")
            if len(json.loads(meta.get("launch_aux", "[]"))) != 4:
                raise RuntimeError(f"{trace_name} lacks the launch auxiliary snapshot")
            if trace_report["recording_start_tick"] != trace_report["first_row_tick"]:
                raise RuntimeError(f"{trace_name} recording tick does not match its first CSV row")
            if not trace_report["recording_aux_matches_first_row"]:
                raise RuntimeError(f"{trace_name} recording auxiliary snapshot differs from its first row")
            if trace_report["recording_start_engine_running"] != "true":
                raise RuntimeError(f"{trace_name} recording snapshot says the engine is stopped")

        if initial_trace["throttle_command_max"] <= 0.1:
            raise RuntimeError(
                "W did not raise throttle in the recorded runway session "
                f"(max {initial_trace['throttle_command_max']:.3f}; "
                f"recorded {initial_trace['recorded_sim_seconds']:.3f} simulation seconds)"
            )
        if initial_trace["horizontal_speed_end_mps"] <= 0.05:
            raise RuntimeError("W did not produce forward ground movement in the recorded runway session")
        if initial_trace["recorded_sim_seconds"] < 0.5:
            raise RuntimeError("manual runway trace recorded less than 0.5 seconds of simulation time")
        if initial_trace["rows"] <= 20:
            raise RuntimeError("manual runway trace has too few rows")
        if r_trace["throttle_command_start"] > 1.0e-9 or pause_trace["throttle_command_start"] > 1.0e-9:
            raise RuntimeError("a restart trace did not start at idle throttle")

        report["saved_settings"] = settings_path.read_text(encoding="utf-8")
        report["saved_settings_sha256"] = sha256_file(settings_path)
        report["trace_directory"] = str(trace_dir)
        report["passed"] = True
    except Exception as exc:  # persist a useful failure record for the exported black-box route
        report["failure"] = f"{type(exc).__name__}: {exc}"
        if process is not None and process.poll() is not None:
            report["process_exit_code"] = process.returncode
    finally:
        if process is not None and process.poll() is None:
            process.send_signal(signal.SIGTERM)
            try:
                process.wait(timeout=10.0)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5.0)
        if x11 is not None:
            x11.close()
        if log_handle is not None:
            log_handle.close()
        report["binary_log"] = str(log_path)
        report["binary_log_sha256"] = sha256_file(log_path) if log_path.is_file() else ""
        report_path = out / "manual-launch.json"
        report["report_path"] = str(report_path)
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--settings", type=Path, required=True)
    parser.add_argument("--taxi-seconds", type=float, default=1.2)
    parser.add_argument("--boot-timeout", type=float, default=60.0)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    report = run(args.binary.resolve(), args.out.resolve(), args.settings.resolve(), args.taxi_seconds, args.boot_timeout)
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report.get("passed") else 1


if __name__ == "__main__":
    raise SystemExit(main())
