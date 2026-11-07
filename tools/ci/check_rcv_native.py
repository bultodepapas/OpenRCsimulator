#!/usr/bin/env python3
"""Run installed ground-vehicle native integration checks with retained diagnostics.

Stage both matching native builds with build.py --install-only before invoking.
The ordinary unit suite may skip native-only branches; this gate requires them.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("openrc_checked_runner", ROOT / "tools/godot/run_checked.py")
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Cannot load the checked Godot runner")
checked = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checked)

CASES = (
    ("rcv-native-session", "res://tests/test_rcv_session.gd", "RCV_NATIVE_SESSION_GUARDS verdict=pass"),
    ("rcv-native-trajectory", "res://tests/test_rcv_vehicle_dynamics.gd", "RCV_NATIVE_TRAJECTORY verdict=pass"),
)


def editor_pins(root: Path) -> tuple[str, str, list[str]]:
    """Read the editor version and executable hashes from the maintained getter."""
    text = (root / "app/get-godot.sh").read_text(encoding="utf-8")
    release = re.findall(r"^VERSION=([0-9A-Za-z][0-9A-Za-z.+-]*)$", text, re.MULTILINE)
    version = re.findall(r"^ENGINE_VERSION=([0-9A-Za-z][0-9A-Za-z.+-]*)$", text, re.MULTILINE)
    arrays = re.findall(r"^\s*BINARY_SHA512=\(([^)]*)\)\s*$", text, re.MULTILINE)
    hashes = [entry.split() for entry in arrays]
    if (len(release) != 1 or len(version) != 1 or len(hashes) != 2
            or [len(row) for row in hashes] != [1, 2]
            or any(not re.fullmatch(r"[0-9a-f]{128}", digest) for row in hashes for digest in row)):
        raise ValueError("Could not read the pinned Linux and Windows editor identities")
    lock = json.loads((root / "research/rc-monster-truck/native/toolchain-lock.json").read_text(encoding="utf-8"))
    if lock["godot"]["version"] != version[0]:
        raise ValueError("Ground-native and editor version pins disagree")
    return release[0], version[0], [hashes[0][0], *hashes[1]]


def sha512(path: Path) -> str:
    digest = hashlib.sha512()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def check_editor(root: Path, godot: Path, host: str) -> str:
    release, version, hashes = editor_pins(root)
    if host.startswith("linux"):
        inputs = ((godot, hashes[0]),)
    elif host == "win32":
        # The console launcher starts the sibling graphical executable.
        gui = godot.parent / f"Godot_v{release}_win64.exe"
        inputs = ((godot, hashes[2]), (gui, hashes[1]))
    else:
        raise ValueError("Installed ground-native checks require Linux or Windows x86_64")
    for path, expected in inputs:
        if not path.is_file() or path.is_symlink() or sha512(path) != expected:
            raise ValueError(f"Godot executable is missing or differs from the pinned editor: {path}")
    return version


def _check(command: list[str], out: Path, *, label: str, timeout: int,
           required: list[str] | None = None) -> dict:
    result = checked.run_checked(command, out, label=label, timeout=timeout, required=required)
    print(f"{label}: {'pass' if result['ok'] else 'FAIL'}; report: {result['report']}", flush=True)
    if not result["ok"]:
        print(f"  reason: {result.get('reason')}; missing markers: {result.get('missing_required_text', [])}",
              file=sys.stderr, flush=True)
    return result


def run(root: Path, godot: Path, out: Path, *, host: str = sys.platform) -> bool:
    """Create fresh evidence, then require import and both native-only branches."""
    root, godot, out = root.resolve(), godot.resolve(), out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    try:
        version = check_editor(root, godot, host)
        engine = [str(godot)]
        version_check = _check([*engine, "--version"], out, label="rcv-editor-version", timeout=30,
                               required=[version])
        if not version_check["ok"] or Path(version_check["log"]).read_text(encoding="utf-8").strip() != version:
            raise ValueError("Godot did not report the exact pinned engine version")
        base = [*engine, "--headless", "--path", str(root / "app"), "--audio-driver", "Dummy"]
        imported = _check([*base, "--import"], out, label="rcv-native-import", timeout=600)
        if not imported["ok"]:
            return False
        results = []
        for label, script, marker in CASES:
            result = _check([*base, "--script", script], out, label=label, timeout=600, required=[marker])
            results.append(result["ok"])
        # Do not accept evidence if the editor changed during its execution.
        if check_editor(root, godot, host) != version:
            raise ValueError("Godot editor identity changed during the native checks")
        return all(results)
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        (out / "failure.txt").write_text(str(error) + "\n", encoding="utf-8")
        print(f"RC native check failed: {error}", file=sys.stderr, flush=True)
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True, help="pinned host Godot editor (console executable on Windows)")
    parser.add_argument("--out-dir", type=Path, required=True, help="new directory for checked logs and reports")
    args = parser.parse_args()
    try:
        return 0 if run(ROOT, args.godot, args.out_dir) else 1
    except OSError as error:
        print(f"RC native check output error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
