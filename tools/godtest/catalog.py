"""Versioned benchmark workloads; requested options never imply supported flight profiles."""
from __future__ import annotations

import copy
import json
import math
import re
from pathlib import Path

SCHEMA = "openrc-godtest-scenario-v1"
STIK = "jensen-das-ugly-stik-60"
JET = "sebart-avanti-s-a200-p100rx"
PHASES = {"startup", "home", "selection", "loading", "takeoff", "climb_right", "farmhouse", "flag", "pause", "right_circuit", "roll", "recover", "large_loop", "approach", "landing", "stop", "settings", "environment", "shutdown"}
FULL = ["startup", "selection", "loading", "takeoff", "climb_right", "farmhouse", "flag", "pause", "right_circuit", "roll", "recover", "large_loop", "recover", "approach", "landing", "stop", "settings", "environment", "home", "shutdown"]
BASE = dict(schema=SCHEMA, aircraft=STIK, start="runway", landscape="club_field", time="day", weather="calm", sky="clear", seed=20261110, entry="continuous", resolution=[1920, 1080], scene_detail="medium", camera="pilot", timeout_s=900, phase_timeout_s=180, headless=False, cycles=1, sample_s=10, pause_s=5)
SCENARIOS = {
    "startup": dict(phases=["startup", "shutdown"]),
    "loading": dict(phases=["startup", "selection", "loading", "home", "shutdown"], start="airborne"),
    "smoke": dict(phases=["startup", "selection", "loading", "recover", "pause", "home", "shutdown"], start="airborne", timeout_s=240),
    "ugly-standard": dict(phases=FULL),
    "ugly-night": dict(phases=FULL, time="night"),
    "ugly-club-short": dict(phases=["startup", "selection", "loading", "takeoff", "climb_right", "flag", "pause", "right_circuit", "home", "shutdown"]),
    "jet-circuit": dict(aircraft=JET, start="airborne", phases=["startup", "selection", "loading", "recover", "right_circuit", "pause", "home", "shutdown"]),
    "transitions": dict(start="airborne", phases=["startup", "selection", "loading", "recover", "settings", "environment", "home", "shutdown"]),
    "green-paradise": dict(landscape="green_paradise", start="airborne", phases=["startup", "selection", "loading", "recover", "pause", "home", "shutdown"]),
    "memory": dict(start="airborne", cycles=10, timeout_s=1800, phases=["startup", "selection", "loading", "recover", "home", "shutdown"]),
    "soak": dict(start="airborne", timeout_s=2400, phase_timeout_s=1900, sample_s=1800, phases=["startup", "selection", "loading", "right_circuit", "home", "shutdown"]),
}
ALL_V1 = ["ugly-standard", "ugly-night", "jet-circuit", "transitions", "green-paradise", "memory"]
AIRCRAFT = [STIK, "stik-electric-6s", "gp-extra-300s-60", "p51d-mustang-120", "f4u-corsair-250", JET, "turbo-lumber-evolution", "moonrunner-x99"]
TIMES = {"day", "dawn", "golden_hour", "sunset", "blue_hour", "evening", "moonrise", "night", "night_dark"}
WEATHER = {"calm", "steady", "crosswind", "gusty", "updraft", "turbulent", "hot-high", "cool-dense"}
SKIES = {"classic", "clear", "cirrus", "fair_cumulus", "broken", "overcast", "prestorm", "distant_storm", "electrical_storm"}
RESOLUTIONS = {(1920, 1080), (1920, 1200), (2560, 1440), (2560, 1600), (3440, 1440), (3840, 2160), (1280, 720), (1280, 800), (1600, 900)}
NUMBERS = {"seed": (0, 2147483647, True), "timeout_s": (10, 3600, False), "phase_timeout_s": (1, 3600, False), "cycles": (1, 50, True), "sample_s": (1, 1800, False), "pause_s": (5, 60, False)}


def scenario(name: str, overrides: dict | None = None) -> dict:
    if name not in SCENARIOS:
        raise ValueError(f"unknown scenario {name!r}; use list")
    result = copy.deepcopy(BASE)
    result.update(copy.deepcopy(SCENARIOS[name]))
    result["id"] = name
    result.update({k: v for k, v in (overrides or {}).items() if v is not None})
    validate(result)
    return result


def validate(value: dict, *, resolved: bool = False) -> None:
    if not isinstance(value, dict):
        raise ValueError("manifest must be an object")
    allowed = set(BASE) | {"id", "phases", "output_dir"}
    if set(value) - allowed:
        raise ValueError(f"unknown manifest fields: {sorted(set(value) - allowed)}")
    missing = set(BASE) | {"id", "phases"}
    if missing - set(value):
        raise ValueError(f"missing manifest fields: {sorted(missing - set(value))}")
    if value["schema"] != SCHEMA:
        raise ValueError("unsupported manifest schema")
    if not isinstance(value["id"], str) or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,95}", value["id"]) is None:
        raise ValueError("id must be a short nonempty string")
    for key, choices in {"aircraft": AIRCRAFT, "start": {"runway", "airborne", "hand_launch"}, "landscape": {"club_field", "green_paradise"}, "time": TIMES, "weather": WEATHER, "sky": SKIES, "entry": {"continuous", "isolated"}, "scene_detail": {"low", "medium", "high", "extreme"}, "camera": {"pilot", "chase", "flyby", "orbit", "closeup"}}.items():
        if not isinstance(value[key], str) or value[key] not in choices:
            raise ValueError(f"unsupported {key}: {value[key]!r}")
    if type(value["headless"]) is not bool:
        raise ValueError("headless must be boolean")
    for key, (minimum, maximum, integer) in NUMBERS.items():
        item = value[key]
        if type(item) not in (float, int) or not math.isfinite(item) or not minimum <= item <= maximum or (integer and int(item) != item):
            raise ValueError(f"{key} must be {'an integer' if integer else 'finite'} in [{minimum}, {maximum}]")
    if value["phase_timeout_s"] > value["timeout_s"]:
        raise ValueError("phase deadline cannot exceed scenario deadline")
    size = value["resolution"]
    if not isinstance(size, list) or len(size) != 2 or any(type(n) is not int for n in size) or tuple(size) not in RESOLUTIONS:
        raise ValueError("resolution must be an admitted product window resolution")
    phases = value["phases"]
    if not isinstance(phases, list) or not 1 <= len(phases) <= 64 or any(type(p) is not str or p not in PHASES for p in phases):
        raise ValueError("phases must contain 1..64 supported phase names")
    if value["entry"] == "isolated" and len([p for p in phases if p not in ("startup", "home", "selection", "loading", "shutdown")]) > 1:
        raise ValueError("isolated mode requires one target phase; use --phase")
    if value["entry"] == "isolated" and any(p in phases for p in ("approach", "landing", "stop")) and (value["aircraft"] != STIK or value["start"] != "airborne" or value["weather"] != "calm" or value["landscape"] != "club_field"):
        raise ValueError("isolated landing requires airborne stock Stik at Club Field in calm weather")
    if value["aircraft"] != STIK and any(p in phases for p in ("takeoff", "roll", "large_loop", "approach", "landing", "stop")):
        raise ValueError("this aircraft has no calibrated maneuver/landing profile; use the airborne navigation scenario")
    if value["aircraft"] == "moonrunner-x99" and value["start"] == "runway":
        raise ValueError("MoonRunner has no wheel-runway start")
    if value["landscape"] != "club_field" and value["start"] == "runway":
        raise ValueError("runway scenario requires Club Field")
    if value["landscape"] != "club_field" and any(p in phases for p in ("farmhouse", "flag", "approach", "landing", "stop")):
        raise ValueError("landmark and runway profiles require Club Field")
    if resolved:
        path = value.get("output_dir")
        if not isinstance(path, str) or not Path(path).is_absolute():
            raise ValueError("resolved output_dir must be absolute")


def load(path: Path) -> dict:
    if path.stat().st_size > 65536:
        raise ValueError("manifest exceeds 64 KiB")
    result = json.loads(path.read_text(encoding="utf-8"), parse_constant=lambda item: (_ for _ in ()).throw(ValueError(f"nonfinite JSON {item}")))
    validate(result)
    return result


def matrix(overrides: dict | None = None) -> list[dict]:
    """A fixed risk-based screen; explicitly not a claim of exhaustive pair coverage."""
    cases = []
    for time, weather, sky, detail in [("day", "calm", "clear", "medium"), ("night", "calm", "clear", "high"), ("sunset", "gusty", "broken", "medium"), ("day", "turbulent", "overcast", "low"), ("night_dark", "calm", "electrical_storm", "high")]:
        case = scenario("smoke", {"time": time, "weather": weather, "sky": sky, "scene_detail": detail, **(overrides or {})})
        case["id"] = f"matrix-{time}-{weather}-{sky}-{detail}"
        cases.append(case)
    return cases
