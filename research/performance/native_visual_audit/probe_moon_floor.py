#!/usr/bin/env python3
"""Compare lunar texture LOD in two pinned shaders and the current worktree.

Run with Python 3 on a host with surfaceless EGL/OpenGL. JSON goes to stdout.
A failing scalar check exits nonzero. The shader returns before sampling textures.
"""
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/graphics"))
from shader_math_probe import OffscreenGL

SHADER = "app/render/world/moon_disc.gdshaderinc"
REVISIONS = {
    "baseline": "71306784a250d634854f0c8bab3a927cc46a61b8",
    "first_candidate": "9d4569310ef223fc129472a20e21aada8ea624f0",
    "corrected": "worktree",
}
FIXTURES = {
    "center": {
        "projection": "(gl_FragCoord.xy - vec2(17.0)) * sin(moon_radius) * 0.2",
        "pixels": [(16, 16), (17, 16), (16, 17), (17, 17)],
        "description": "Four equal-radius samples straddle the disc center in one derivative quad.",
    },
    "upper_right": {
        "projection": "(vec2(206.5,149.5) + gl_FragCoord.xy - vec2(16.5)) * sin(moon_radius) / 254.9",
        "pixels": [(16, 16)],
        "description": "Local circular projection at native image pixel (1166,390), relative to center "
                       "(959.5,539.5) with y up and 254.9 px radius. Approximates the 1.2-degree full_high close view.",
    },
}


def observe(gl, source, fixture):
    # Strip Godot sampler hints, then read out actual shader intermediates before the first texture fetch.
    source = re.sub(r"(uniform sampler2D\s+\w+)\s*:[^;]+;", r"\1;", source)
    source, count = re.subn(r"(float lod = [^;]+;)", r"\1\nreturn vec3(lod, aa, rr);", source)
    if count != 1:
        raise ValueError("Expected one lunar texture LOD observation point")
    body = source + """
void main() {
    vec2 xy = PROJECTION;
    vec3 direction = vec3(xy, -sqrt(max(1.0 - dot(xy, xy), 0.0)));
    result = vec4(moon_disc(direction), 1.0);
}
""".replace("PROJECTION", fixture["projection"])
    pixels = gl.render(body, width=32, height=32, uniforms={
        "moon_dir": (0, 0, -1), "moon_lin": (1, 1, 1), "moon_textured": True,
    })
    return [dict(zip(("texture_lod", "radial_aa", "disc_radius"), pixels[y * 32 + x][:3]))
            for x, y in fixture["pixels"]]


def main():
    gl = OffscreenGL()
    report = {
        "format": "openrc-native-moon-floor-v1",
        "command": "python3 research/performance/native_visual_audit/probe_moon_floor.py",
        "scope": "Two synthetic local projections and three actual shader sources. Measures pre-fetch texture "
                 "LOD, radial AA width and normalized radius. Texture response, lighting, edge color, motion "
                 "and performance require independent evidence.",
        "shader": SHADER, "opengl": gl.identity, "sources": {}, "fixtures": {},
    }
    samples = {}
    try:
        for label, revision in REVISIONS.items():
            if revision == "worktree":
                data = (ROOT / SHADER).read_bytes()
            else:
                data = subprocess.check_output(["git", "show", f"{revision}:{SHADER}"], cwd=ROOT)
            report["sources"][label] = {"revision": revision, "sha256": hashlib.sha256(data).hexdigest()}
            samples[label] = {name: observe(gl, data.decode(), fixture) for name, fixture in FIXTURES.items()}
    finally:
        gl.close()
    for name, fixture in FIXTURES.items():
        measurements = {label: values[name] for label, values in samples.items()}
        report["fixtures"][name] = {**fixture, "measurements": measurements}

    expected_center = math.log2(512 * 0.2 / math.sqrt(0.98))
    tolerance = 2e-5
    limb_lod = {label: values["upper_right"][0]["texture_lod"] for label, values in samples.items()}
    geometry_errors = []
    for label in ("first_candidate", "corrected"):
        for name in FIXTURES:
            for sample, baseline in zip(samples[label][name], samples["baseline"][name]):
                geometry_errors.extend(abs(sample[key] - baseline[key]) for key in ("radial_aa", "disc_radius"))
    report["expected_center_lod"] = expected_center
    report["absolute_tolerance"] = tolerance
    report["checks"] = {
        "baseline_center_selects_mip_zero":
            all(s["texture_lod"] == 0.0 for s in samples["baseline"]["center"]),
        "first_and_corrected_center_match_oracle":
            all(abs(s["texture_lod"] - expected_center) < tolerance
                for label in ("first_candidate", "corrected") for s in samples[label]["center"]),
        "first_candidate_selects_finer_limb_lod_by_at_least_quarter_mip":
            limb_lod["baseline"] - limb_lod["first_candidate"] > 0.25,
        "corrected_limb_lod_matches_baseline":
            0.0 <= limb_lod["corrected"] - limb_lod["baseline"] < tolerance,
        "radial_aa_and_radius_match_baseline": max(geometry_errors) < tolerance,
    }
    report["ok"] = all(report["checks"].values())
    print(json.dumps(report, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
