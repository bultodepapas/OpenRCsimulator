#!/usr/bin/env python3
"""Summarize tools/scenery/attribute_views.gd output per subsystem and view class (stdlib only).

Cost(subsystem, view) = complete - without(subsystem): submitted primitives and draw calls, including the
shadow pass. The v2 primitive estimate applies the per-instance correction observed on Godot 4.7.2
Compatibility; counter_primitives retains the raw engine value. The sun-shadow delta remains a raw
counter, with no per-instance estimate. The correction requires separate validation on other engines.
Reports each subsystem's full-detail source triangles beside its estimated drawn cost. Usage:
  attribution_report.py <attribution dir> [--json <out.json>] [--markdown <out.md>] [--budget <budget.json>]
With --budget it exits nonzero when a view class, subsystem allocation, shadow-caster, full-detail mesh or
memory limit is exceeded or the measurement identity differs (openrc-scene-budget v1).
"""
import argparse
import json
import re
import statistics
from pathlib import Path

# View classes: what the pilot sees in flight, ground-level club views, and raised/aerial overviews.
VIEW_CLASSES = {
    "pilot": ("pilot_north", "pilot_south", "pilot_east", "pilot_west", "runway_zoom_100", "runway_zoom_300",
              "birds_watch", "turbines_zoom"),
    "ground": ("car_park", "fleet_close", "postcard_club", "postcard_pavilion", "postcard_pits", "postcard_meadow",
               "postcard_farm", "runway_threshold"),
    "aerial": ("aerial_overview", "top_140", "top_140_b", "top_140_c"),
}


def instanced_lod_correction(rows: list) -> int:
    """Primitives the engine counter misses: every instance draws the node's LOD."""
    return sum(row["instances"] * row["one_instance"] - row["counted"] for row in rows)


def summarize(report: dict) -> dict:
    views = report["views"]
    groups = report["groups"]
    corrected = report.get("format") == "openrc-view-attribution v2"
    stable = {name: row["complete"] == row["complete_repeat"] for name, row in views.items()}
    corrections = {name: {group: instanced_lod_correction(rows) for group, rows in row.get("instanced_lod", {}).items()}
                   for name, row in views.items()}
    totals = {name: dict(row["complete"], counter_primitives=row["complete"]["primitives"],
                         primitives=row["complete"]["primitives"] + sum(corrections[name].values()))
              for name, row in views.items()}
    cost = {}
    for group in groups:
        cost[group] = {}
        for name, row in views.items():
            complete, without = row["complete"], row["without"][group]
            counted = complete["primitives"] - without["primitives"]
            cost[group][name] = {"draws": complete["draws"] - without["draws"], "counter_primitives": counted,
                                 "primitives": counted + corrections[name].get(group, 0)}
    classes = {}
    for class_name, names in VIEW_CLASSES.items():
        present = [name for name in names if name in views]
        if not present:
            continue
        class_rows = {}
        for group, per_view in cost.items():
            prims = [per_view[name]["primitives"] for name in present]
            draws = [per_view[name]["draws"] for name in present]
            class_rows[group] = {"primitives_max": max(prims), "primitives_median": statistics.median(prims),
                                 "draws_max": max(draws), "draws_median": statistics.median(draws)}
        view_prims = [totals[name]["primitives"] for name in present]
        view_draws = [totals[name]["draws"] for name in present]
        sun = [totals[name]["counter_primitives"] - views[name]["without_sun_shadows"]["primitives"] for name in present]
        sun_draws = [totals[name]["draws"] - views[name]["without_sun_shadows"]["draws"] for name in present]
        classes[class_name] = {
            "views": present,
            "total": {"primitives_max": max(view_prims), "primitives_median": statistics.median(view_prims),
                      "draws_max": max(view_draws), "draws_median": statistics.median(view_draws)},
            # Keep the old primitives_max alias for existing summary consumers. It is a raw counter,
            # not the per-instance estimate used by the total and subsystem primitive fields.
            "sun_shadow_pass": {"primitives_max": max(sun), "counter_primitives_max": max(sun),
                                "corrected_primitives_max": None, "primitives_kind": "raw_engine_counter",
                                "draws_max": max(sun_draws)},
            "groups": class_rows,
        }
    return {"viewport": report["viewport"], "adapter": report["adapter"], "godot": report["godot"],
            "renderer": report.get("renderer"), "rendering_driver": report.get("rendering_driver"),
            "godot_hash": report.get("godot_hash"),
            "measurement_scope": report.get("measurement_scope"),
            "measurement_settings": report.get("measurement_settings"),
            "viewport_settings": report.get("viewport_settings"),
            "mesh_lod_threshold": report.get("mesh_lod_threshold"),
            "field_sha256": report.get("field_sha256"), "scenery_sha256": report.get("scenery_sha256"),
            "primitive_estimate_basis": "Godot 4.7.2 Compatibility instanced LOD correction" if corrected else None,
            "memory": report.get("memory", {}), "instanced_lod_corrected": corrected,
            "scene_detail": report.get("scene_detail"),
            "source_triangles": {group: data["source_triangles"] for group, data in groups.items()},
            "full_detail_triangles": {group: data.get("full_detail_triangles") for group, data in groups.items()},
            "shadow_caster_triangles": {group: data.get("shadow_caster_triangles") for group, data in groups.items()},
            "stable_repeat": stable, "view_totals": totals, "cost": cost, "classes": classes}


def check_budget(summary: dict, report: dict, budget: dict) -> list[str]:
    """Return identity mismatches and exceeded limits; an empty list passes."""
    if budget.get("format") != "openrc-scene-budget v1":
        raise SystemExit("unsupported budget format")
    failures = []
    if not report["groups"]:
        failures.append("no measured subsystems")
    if not summary["instanced_lod_corrected"]:
        failures.append("v1 attribution undercounts instanced LOD meshes; re-run attribute_views.gd")
    for name, row in report["views"].items():
        if not isinstance(row.get("instanced_lod"), dict):
            failures.append(f"{name}: missing instanced LOD measurements")
        if not summary["stable_repeat"][name]:
            failures.append(f"{name}: unstable repeated measurement")
    # Historic budgets are tied to the behavior that produced their numbers. An absent identity is
    # not a wildcard; legacy attributions can still be summarized without claiming a budget pass.
    identity = budget.get("measurement") or {}
    for key, summary_key in (("scope", "measurement_scope"), ("godot", "godot"),
                             ("renderer", "renderer"), ("mesh_lod_threshold", "mesh_lod_threshold")):
        if key not in identity:
            failures.append(f"budget lacks required measurement identity: {key}")
        elif summary.get(summary_key) != identity[key]:
            failures.append(f"measurement {key} {summary.get(summary_key)!r} differs from budget {identity[key]!r}")
    if not identity.get("godot_hash_prefix"):
        failures.append("budget lacks required measurement identity: godot_hash_prefix")
    elif not (summary.get("godot_hash") or "").startswith(identity["godot_hash_prefix"]):
        failures.append(f"measurement godot_hash {summary.get('godot_hash')!r} differs from budget prefix "
                        f"{identity['godot_hash_prefix']!r}")
    for identity_key, summary_key in (("settings", "measurement_settings"),
                                      ("viewport_settings", "viewport_settings")):
        if not identity.get(identity_key):
            failures.append(f"budget lacks required measurement identity: {identity_key}")
            continue
        actual_settings = summary.get(summary_key) or {}
        for key, expected in identity[identity_key].items():
            if key not in actual_settings or actual_settings[key] != expected:
                failures.append(f"measurement {identity_key}.{key} {actual_settings.get(key)!r} "
                                f"differs from budget {expected!r}")
    # VQ-06b: the budget guards one Scene detail preset (High, the default); others are measured, not capped.
    if summary["scene_detail"] != budget.get("scene_detail", "high"):
        failures.append(f"scene detail {summary['scene_detail']} measured; this budget applies to "
                        f"{budget.get('scene_detail', 'high')}")
    if summary["viewport"] != budget["viewport"]:
        failures.append(f"viewport {summary['viewport']} differs from the budget's {budget['viewport']}")
    default = budget.get("default_subsystem", {})
    for class_name, limits in budget["classes"].items():
        data = summary["classes"].get(class_name)
        if data is None:
            failures.append(f"{class_name}: no measured views")
            continue
        missing = [name for name in VIEW_CLASSES[class_name] if name not in data["views"]]
        if missing:
            failures.append(f"{class_name}: missing views {missing}")
        for key, limit in (("primitives_max", limits["max_primitives"]), ("draws_max", limits["max_draws"])):
            if data["total"][key] > limit:
                failures.append(f"{class_name}: total {key} {data['total'][key]:,} > {limit:,}")
        for group, row in data["groups"].items():
            allocation = budget["subsystems"].get(group, {}).get(class_name, default.get(class_name))
            if allocation is None:
                failures.append(f"{class_name}/{group}: no subsystem allocation or default")
                continue
            for key, limit in (("primitives_max", allocation["primitives"]), ("draws_max", allocation["draws"])):
                if row[key] > limit:
                    failures.append(f"{class_name}/{group}: {key} {row[key]:,} > {limit:,}")
    shadow = budget.get("shadow_casters", {})
    shadow_total = 0
    for group, data in report["groups"].items():
        triangles = data.get("shadow_caster_triangles")
        if triangles is None:
            if shadow:
                failures.append(f"{group}: missing shadow-caster triangle measurement")
            continue
        shadow_total += triangles
        if triangles and group not in shadow.get("allowed", []):
            failures.append(f"{group}: {triangles:,} shadow-caster triangles without an approved allowance")
        if "full_detail_exceptions" in budget and "full_detail_meshes_over_5000" not in data:
            failures.append(f"{group}: missing full-detail mesh inventory")
        for mesh in data.get("full_detail_meshes_over_5000", []):
            # An exception names a mesh; ImportedVegetation cell batches append _Cell_<x>_<z>.
            name = re.sub(r"_Cell_-?\d+_-?\d+$", "", mesh.split(":")[0])
            if name not in budget.get("full_detail_exceptions", {}).get(group, []):
                failures.append(f"{group}: full-detail mesh {mesh} needs generated LODs or a recorded exception")
    if shadow and shadow_total > shadow["max_triangles"]:
        failures.append(f"shadow-caster triangles {shadow_total:,} > {shadow['max_triangles']:,}")
    memory = summary.get("memory") or {}
    if "max_texture_mib" in budget:
        if "texture_bytes" not in memory:
            failures.append("missing texture memory measurement")
        elif memory["texture_bytes"] / 2**20 > budget["max_texture_mib"]:
            failures.append(f"texture memory {memory['texture_bytes'] / 2**20:.0f} MiB > {budget['max_texture_mib']} MiB")
    return failures


def markdown(summary: dict) -> str:
    width, height = summary["viewport"]
    lines = [f"Viewport {int(width)}×{int(height)}, {summary['adapter']}, Godot {summary['godot']}, "
             f"renderer {summary['renderer'] or 'unknown'}, scene detail {summary['scene_detail'] or 'unknown'}.",
             f"Measurement scope: {summary['measurement_scope'] or 'unknown (legacy attribution)'}. "
             "No complete flight or hardware qualification is implied.",
             "Total and subsystem primitives are per-instance estimates using the Godot 4.7.2 Compatibility "
             "instanced-LOD correction; its applicability on other engines requires validation."
             if summary["instanced_lod_corrected"] else
             "Engine counter only (v1): instanced meshes with LODs are counted once per draw.", ""]
    for class_name, data in summary["classes"].items():
        total = data["total"]
        lines.append(f"**{class_name}** ({len(data['views'])} views): total primitives max "
                     f"{total['primitives_max']:,} (median {total['primitives_median']:,.0f}), draws max "
                     f"{total['draws_max']} (median {total['draws_median']:.0f}); raw sun-shadow counter delta up to "
                     f"{data['sun_shadow_pass']['counter_primitives_max']:,} primitives / "
                     f"{data['sun_shadow_pass']['draws_max']} draws (no corrected shadow estimate).")
    memory = summary.get("memory") or {}
    if memory:
        lines.append(f"Renderer estimates after the first frame: textures {memory['texture_bytes'] / 2**20:.0f} MiB, "
                     f"buffers {memory['buffer_bytes'] / 2**20:.0f} MiB, video {memory['video_bytes'] / 2**20:.0f} MiB.")
    lines += ["", "| Subsystem | Source triangles | Without LOD | Pilot prims max | Pilot draws max | Ground prims max | "
              "Ground draws max | Aerial prims max | Aerial draws max |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    order = sorted(summary["source_triangles"], key=lambda group: -max(
        summary["classes"][name]["groups"][group]["primitives_max"] for name in summary["classes"]))
    for group in order:
        full_detail = summary["full_detail_triangles"].get(group)
        cells = [f"{summary['source_triangles'][group]:,}", "" if full_detail is None else f"{full_detail:,}"]
        for class_name in ("pilot", "ground", "aerial"):
            row = summary["classes"].get(class_name, {}).get("groups", {}).get(group)
            cells += [f"{row['primitives_max']:,}", f"{row['draws_max']}"] if row else ["", ""]
        lines.append(f"| {group} | " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("attribution", type=Path)
    parser.add_argument("--json", type=Path)
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--budget", type=Path)
    args = parser.parse_args()
    report = json.loads((args.attribution / "attribution.json").read_text(encoding="utf-8"))
    if report.get("format") not in ("openrc-view-attribution v1", "openrc-view-attribution v2"):
        raise SystemExit("unsupported attribution format")
    summary = summarize(report)
    text = markdown(summary)
    if args.json:
        args.json.write_text(json.dumps(summary, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    if args.markdown:
        args.markdown.write_text(text, encoding="utf-8")
    print(text)
    unstable = [name for name, same in summary["stable_repeat"].items() if not same]
    if unstable:
        raise SystemExit("unstable repeated measurement: " + ", ".join(unstable))
    if args.budget:
        failures = check_budget(summary, report, json.loads(args.budget.read_text(encoding="utf-8")))
        if failures:
            raise SystemExit("scene budget not qualified:\n  " + "\n  ".join(failures))
        print(f"scene budget {args.budget.name}: historical workload limits pass; not hardware qualification")


if __name__ == "__main__":
    main()
