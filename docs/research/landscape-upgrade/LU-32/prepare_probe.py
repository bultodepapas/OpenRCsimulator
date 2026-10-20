from pathlib import Path

root = Path.cwd()
target = root / "tmp/landscape-perf-r2"
replacements = {
    "res://render/landscape_upgrade/airfield_lighting.gd": target / "baseline_airfield_lighting.gd",
    "res://render/weather/storm_bank.gd": target / "baseline_storm_bank.gd",
    "res://render/world/world.gd": target / "baseline_world.gd",
}
for name in ["airfield_lighting", "storm_bank", "world"]:
    source = target / f"{name}.before.gd" if name != "world" else root / "app/render/world/world.gd"
    code = source.read_text().replace("class_name AirfieldLighting\n", "")
    for old, new in replacements.items():
        code = code.replace(f'"{old}"', f'"{new.as_posix()}"')
    (target / f"baseline_{name}.gd").write_text(code)
for name, source in [
    ("storm_capture", root / "tools/atmosphere/storm_bank_capture.gd"),
    ("landscape_capture", root / "app/tests/capture_landscape_upgrade.gd"),
]:
    code = source.read_text()
    for old, new in replacements.items():
        code = code.replace(f'"{old}"', f'"{new.as_posix()}"')
    (target / f"baseline_{name}.gd").write_text(code)
