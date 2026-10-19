"""Build frozen, read-only timing instrumentation from the detached r3 baseline."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASELINE = HERE.parent / "baseline" / "app"
OUT = HERE / "executed_sources" / "app"
COMMIT_FILE = HERE.parent / "READY"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_record(path: Path) -> dict[str, str]:
    raw = path.read_bytes()
    return {"sha256": sha256(raw), "path": str(path.resolve())}


def load_text(relative: str) -> tuple[str, bytes]:
    raw = (BASELINE / relative).read_bytes()
    text = raw.decode("utf-8")
    return text.replace("\r\n", "\n"), raw


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"freeze refused: {label} anchor count {count}, expected 1")
    return text.replace(old, new, 1)


def instrument_main(text: str) -> str:
    text = replace_once(
        text,
        "var _frame_times := PackedFloat64Array()\n",
        """var _frame_times := PackedFloat64Array()
## FRAME-R3: read-only callback spans, consumed by the external observer.
var _audit_main_frame_end_usec := 0
var _audit_main_total_usec := 0
var _audit_main_world_usec := 0
var _audit_main_audio_usec := 0
var _audit_main_panel_usec := 0
var _audit_main_pose_usec := 0
var _audit_main_hud_usec := 0
var _audit_main_overlay_usec := 0
var _audit_main_other_usec := 0
""",
        "Main probe fields",
    )
    text = replace_once(
        text,
        "func _process(delta: float) -> void:\n",
        "func _process(delta: float) -> void:\n\tvar audit_main_started_usec := Time.get_ticks_usec()\n",
        "Main process entry",
    )
    text = replace_once(
        text,
        "\tWorld.update(_env, visual_clock_s, _render_wind(visual_clock_s), _last_render_pose.get(\"pos\"), _camera) # deterministic wind and field-world adaptation\n",
        "\tvar audit_world_started_usec := Time.get_ticks_usec()\n"
        "\tWorld.update(_env, visual_clock_s, _render_wind(visual_clock_s), _last_render_pose.get(\"pos\"), _camera) # deterministic wind and field-world adaptation\n"
        "\t_audit_main_world_usec = Time.get_ticks_usec() - audit_world_started_usec\n",
        "Main world span",
    )
    text = replace_once(
        text,
        "\tif _engine_audio != null and _soundscape_audio == null:\n",
        "\tvar audit_audio_started_usec := Time.get_ticks_usec()\n"
        "\tif _engine_audio != null and _soundscape_audio == null:\n",
        "Main audio span start",
    )
    text = replace_once(
        text,
        "\t\t_lake_ambience.stream_paused = not session.holds.is_empty()\n\tvar surfaces: Dictionary = session.surfaces()\n",
        "\t\t_lake_ambience.stream_paused = not session.holds.is_empty()\n"
        "\t_audit_main_audio_usec = Time.get_ticks_usec() - audit_audio_started_usec\n"
        "\tvar surfaces: Dictionary = session.surfaces()\n",
        "Main audio span end",
    )
    text = replace_once(
        text,
        "\tInputPanel.update(_panel, session.raw, session.commands, _view_name(), _status(), surfaces, session.throws_deg())\n",
        "\tvar audit_panel_started_usec := Time.get_ticks_usec()\n"
        "\tInputPanel.update(_panel, session.raw, session.commands, _view_name(), _status(), surfaces, session.throws_deg())\n"
        "\t_audit_main_panel_usec = Time.get_ticks_usec() - audit_panel_started_usec\n",
        "Main panel span",
    )
    text = replace_once(
        text,
        "\t_render_pose(_current_pose(), surfaces, _prop_angle)\n",
        "\tvar audit_pose_started_usec := Time.get_ticks_usec()\n"
        "\t_render_pose(_current_pose(), surfaces, _prop_angle)\n",
        "Main pose span start",
    )
    text = replace_once(
        text,
        "\t_update_hud()\n\tif _overlays != null:\n",
        "\t_audit_main_pose_usec = Time.get_ticks_usec() - audit_pose_started_usec\n"
        "\tvar audit_hud_started_usec := Time.get_ticks_usec()\n"
        "\t_update_hud()\n"
        "\t_audit_main_hud_usec = Time.get_ticks_usec() - audit_hud_started_usec\n"
        "\tvar audit_overlay_started_usec := Time.get_ticks_usec()\n"
        "\tif _overlays != null:\n",
        "Main HUD and overlay span start",
    )
    text = replace_once(
        text,
        "\t\t_overlays.refresh_sticks(OverlayManager.sticks(session) if not _scripted and _visual_pose.is_empty() else {})\n",
        "\t\t_overlays.refresh_sticks(OverlayManager.sticks(session) if not _scripted and _visual_pose.is_empty() else {})\n"
        "\t_audit_main_overlay_usec = Time.get_ticks_usec() - audit_overlay_started_usec\n"
        "\tvar audit_main_end_usec := Time.get_ticks_usec()\n"
        "\t_audit_main_frame_end_usec = audit_main_end_usec\n"
        "\t_audit_main_total_usec = audit_main_end_usec - audit_main_started_usec\n"
        "\t_audit_main_other_usec = _audit_main_total_usec - _audit_main_world_usec - _audit_main_audio_usec - _audit_main_panel_usec - _audit_main_pose_usec - _audit_main_hud_usec - _audit_main_overlay_usec\n",
        "Main process span end",
    )
    return text


def instrument_simulation(text: str) -> str:
    text = replace_once(
        text,
        "var step_usec := 0.0\n",
        """var step_usec := 0.0
## FRAME-R3: outer wall time around actual successful/failed step() calls.
var _audit_step_callbacks := 0
var _audit_step_tick_count := 0
var _audit_step_total_usec := 0
var _audit_step_max_usec := 0
var _audit_step_last_usec := 0
""",
        "Simulation probe fields",
    )
    text = replace_once(
        text,
        "\tstep()\n\n\n## State between the previous and current step:",
        """\tvar audit_tick_before := tick
\tvar audit_step_started_usec := Time.get_ticks_usec()
\tstep()
\tvar audit_step_elapsed_usec := Time.get_ticks_usec() - audit_step_started_usec
\t_audit_step_callbacks += 1
\t_audit_step_tick_count += maxi(0, tick - audit_tick_before)
\t_audit_step_total_usec += audit_step_elapsed_usec
\t_audit_step_max_usec = maxi(_audit_step_max_usec, audit_step_elapsed_usec)
\t_audit_step_last_usec = audit_step_elapsed_usec


## State between the previous and current step:""",
        "Simulation physics step span",
    )
    return text


def instrument_app_root(text: str) -> str:
    text = replace_once(
        text,
        "var _wm_close_pending := false\n",
        "var _wm_close_pending := false\n"
        "## FRAME-R3: records only native focus notifications; it does not change focus/pause handling.\n"
        "var _audit_focus_events: Array[Dictionary] = []\n",
        "AppRoot focus event field",
    )
    text = replace_once(
        text,
        "func _notification(what: int) -> void:\n\tif what == NOTIFICATION_WM_CLOSE_REQUEST:\n",
        "func _notification(what: int) -> void:\n"
        "\tif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_OUT:\n"
        "\t\t_audit_focus_events.append({\"usec\": Time.get_ticks_usec(), \"what\": what, \"focused\": DisplayServer.window_is_focused()})\n"
        "\tif what == NOTIFICATION_WM_CLOSE_REQUEST:\n",
        "AppRoot focus notification tap",
    )
    return text


def main() -> None:
    if (HERE / "READY").exists():
        raise SystemExit("freeze refused: frame/READY is immutable; use a new run directory")
    commit = COMMIT_FILE.read_text(encoding="utf-8").strip()
    if not commit.startswith("122889b8e"):
        raise SystemExit(f"freeze refused: unexpected baseline commit {commit!r}")
    sources: dict[str, dict[str, str]] = {}
    for name, relative, transform in (
        ("main.gd", "main.gd", instrument_main),
        ("simulation.gd", "sim/simulation.gd", instrument_simulation),
        ("app_root.gd", "app_root.gd", instrument_app_root),
    ):
        text, original = load_text(relative)
        patched = transform(text).encode("utf-8")
        target = OUT / ("sim" if name == "simulation.gd" else "") / name if name == "simulation.gd" else OUT / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(patched)
        sources[relative] = {
            "baseline_sha256": sha256(original),
            "executed_sha256": sha256(patched),
            "executed_path": str(target.resolve()),
        }
    context_sources: dict[str, dict[str, str]] = {}
    for relative in (
        "project.godot",
        "app_root.tscn",
        "main.tscn",
        "sim/flight_session.gd",
        "input/commands.gd",
    ):
        raw = (BASELINE / relative).read_bytes()
        context_sources[relative] = {
            "baseline_sha256": sha256(raw),
            "executed_sha256": sha256(raw),
            "path": str((BASELINE / relative).resolve()),
        }
    native_dir = BASELINE / "native" / "ground_vehicle"
    native_files = {
        name: file_record(native_dir / name)
        for name in (
            "openrc_ground_vehicle.dll",
            "openrc_ground_vehicle.gdextension",
            "build-receipt.json",
        )
    }
    correction = HERE.parent / "native-environment-correction.json"
    engine = HERE.parent / "baseline" / ".tools" / "Godot_v4.7.2-stable_win64_console.exe"
    manifest = {
        "format": "frame-stall-source-freeze v1",
        "baseline_commit": commit,
        "scope": "FRAME-R3 timing spans/focus-event recording plus the established diagnostic input_enabled=false fixed-trim route; no application source files are changed.",
        "baseline_app": str(BASELINE.resolve()),
        "sources": sources,
        "context_sources": context_sources,
        "probe": file_record(HERE / "native_frame_probe.gd"),
        "invocation": file_record(HERE / "run_native_probe.ps1"),
        "reducer": file_record(HERE / "reduce_frame_trace.py"),
        "protocol": file_record(HERE / "README.md"),
        "freeze_script": file_record(HERE / "freeze_sources.py"),
        "native_environment": {
            "godot_console_binary": file_record(engine),
            "correction_receipt": file_record(correction),
            "files": native_files,
        },
    }
    out = HERE / "source-freeze.json"
    out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"manifest": str(out.resolve()), "sources": sources}, indent=2))


if __name__ == "__main__":
    main()
