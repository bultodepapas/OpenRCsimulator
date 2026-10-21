from pathlib import Path

root = Path(__file__).resolve().parents[2]
target = root / "tmp/landscape-perf"
copies = {
    "population": target / "population.before.gd",
    "imported_vegetation": target / "imported_vegetation.before.gd",
    "botanical_habitats": target / "botanical/botanical_habitats.before.gd",
    "scenery": root / "app/scenery/scenery.gd",
}
for name, path in copies.items():
    text = path.read_text()
    text = text.replace("class_name ImportedVegetation\n", "")
    for dependency in copies:
        text = text.replace(f'res://scenery/{dependency}.gd',
                            (target / f"baseline_{dependency}.gd").as_posix())
    (target / f"baseline_{name}.gd").write_text(text)

field = (root / "app/render/field.gd").read_text().replace(
    "res://scenery/scenery.gd", (target / "baseline_scenery.gd").as_posix())
(target / "baseline_field.gd").write_text(field)
world = (root / "app/render/world/world.gd").read_text().replace(
    "res://render/field.gd", (target / "baseline_field.gd").as_posix())
(target / "baseline_world.gd").write_text(world)
for name in ["test_landscape_scenery_grass_mask", "capture_landscape_upgrade"]:
    text = (root / f"app/tests/{name}.gd").read_text()
    for old, new in [("res://render/field.gd", "baseline_field.gd"),
                     ("res://scenery/scenery.gd", "baseline_scenery.gd"),
                     ("res://render/world/world.gd", "baseline_world.gd")]:
        text = text.replace(old, (target / new).as_posix())
    (target / f"baseline_{name}.gd").write_text(text)
