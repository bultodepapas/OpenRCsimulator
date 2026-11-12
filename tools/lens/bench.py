"""LENS-12 (docs/plans/lens-screen-effects.md): lens-effects cost bench through the debug bridge.

Prints one JSON line per scenario (lens off, heavy rain in chase/pilot/close-up views, a held full curtain, a cracked
lens with dust and mud) with the bridge's GPU and CPU medians at the running window size. Launch the app first at
1920x1080 on an otherwise idle machine (AGENTS.md: never benchmark alongside other GPU/CPU work):

    python tools/debug/debugctl.py launch --mute
    OPENRC_DEBUG_BRIDGE=<port> python tools/lens/bench.py . [time_of_day]
"""
import json
import pathlib
import sys
import time

REPO = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(REPO / "tools" / "debug"))
import debugctl  # noqa: E402

STACK = "Main/LensStack"
TOD = sys.argv[2] if len(sys.argv) > 2 else "day"


def req(cmd: str, **args) -> dict:
    r = debugctl.request(cmd, args)
    return r.get("result", r) if isinstance(r, dict) else {}


def ev(expr: str):
    return req("eval", expr=expr)


def measure(label: str) -> None:
    req("wait", seconds=1.5)
    r = req("render", frames=240, measure=True)
    row = {"scenario": label, "gpu_ms": r.get("gpu_ms"), "gpu_p95": r.get("gpu_p95_ms"),
           "cpu_ms": r.get("root_cpu_ms"), "canvas_draws": r.get("canvas_draw_calls"), "fps": r.get("fps")}
    if label != "lens_off":
        snap = ev(f"app.get_node('{STACK}').snapshot()")
        if isinstance(snap, dict):
            snap = snap.get("value", snap)
            row["state"] = {k: snap.get(k) for k in ("view", "drops", "stamps", "blood", "wetness", "rain_mmph", "cracked")}
    print(json.dumps(row), flush=True)


def _run() -> None:
    req("setup", start="airborne", time_of_day=TOD)
    req("fly")
    for _ in range(3):
        try:
            req("close")
        except Exception:
            pass
    req("resume")
    req("wait", seconds=2)
    print(json.dumps({k: req("state").get(k) for k in ("route", "screens")}), flush=True)
    # A true baseline: stop the stack and hide everything it could draw.
    ev(f"app.get_node('{STACK}').set('configured', false)")
    ev(f"app.get_node('{STACK}/LensLayer').set('visible', false)")
    measure("lens_off")
    ev(f"app.get_node('{STACK}/LensLayer').set('visible', true)")
    ev(f"app.get_node('{STACK}').set('configured', true)")
    req("view", name="chase")
    ev(f"app.get_node('{STACK}').debug_rain(16.0)")
    req("wait", seconds=6)
    measure("rain16_chase")
    req("view", name="pilot")
    req("wait", seconds=3)
    measure("rain16_pilot")
    req("view", name="closeup")
    req("wait", seconds=4)
    measure("rain16_closeup")
    ev(f"app.get_node('{STACK}').debug_rain(0.0)")
    ev(f"app.get_node('{STACK}').reset()")
    req("view", name="chase")
    req("time_scale", value=0.05)
    ev(f"app.get_node('{STACK}').debug_blood(1.0, true)")
    time.sleep(1.5)
    measure("curtain_full")
    req("time_scale", value=1.0)  # always restore: a left-over 0.05 makes every later reading meaningless
    req("wait", seconds=8)
    ev(f"app.get_node('{STACK}').reset()")
    req("view", name="closeup")
    ev(f"app.get_node('{STACK}').debug_grime('dust', 20.0)")
    ev(f"app.get_node('{STACK}').debug_grime('rough', 20.0)")
    measure("crack_dust_mud")
    ev(f"app.get_node('{STACK}').reset()")
    measure("after_reset")


def main() -> None:
    try:
        _run()
    finally:
        req("time_scale", value=1.0)


if __name__ == "__main__":
    main()
