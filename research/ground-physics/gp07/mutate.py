#!/usr/bin/env python3
"""GP-07 mutation check: each deliberate defect must make test_airframe_contacts.gd (or the named test) fail.

Copies app/ once into a disposable directory (assets/ linked read-only beside it), applies one mutation at a time and
restores the file afterwards; a baseline run of each test must pass first.
Usage: python3 research/ground-physics/gp07/mutate.py <scratch dir> [label text]   (needs about 2.5 GB free)
"""
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "../../.."))
GODOT = subprocess.run([os.path.join(REPO, "app/get-godot.sh")], capture_output=True, text=True, check=True).stdout.strip()
OLD_HULL = os.path.join(HERE, "mutation-old-hull.json")


def text_sub(old, new):
    def edit(src):
        assert src.count(old) == 1, old
        return src.replace(old, new)
    return edit


def old_hull(src):
    """The 2026-10 plan-estimate hull (8 points) back in the base Stik."""
    data = json.loads(src)
    data.update(json.load(open(OLD_HULL)))
    return json.dumps(data, indent=2, ensure_ascii=False).replace("\n", "\r\n") + "\r\n"


MAIN = "test_airframe_contacts"
MUTATIONS = [
    ("plan-estimate hull restored", "data/aircraft/jensen_ugly_stik_60.json", old_hull, MAIN),
    ("one friction for every surface", "physics/hull_contact.gd",
     text_sub("			return surfaces[i + 4]\n		i += AIRFRAME_STRIDE", "			return FRICTION_MU\n		i += AIRFRAME_STRIDE"), MAIN),
    ("friction looked up under the CG", "physics/hull_contact.gd",
     text_sub("			mu = friction_at(surfaces, s[RB.POS] + north[0] * rx + north[1] * ry + north[2] * rz,\n				s[RB.POS + 1] + east[0] * rx + east[1] * ry + east[2] * rz)",
              "			mu = friction_at(surfaces, s[RB.POS], s[RB.POS + 1])"), MAIN),
    ("north and east swapped in the lookup", "physics/hull_contact.gd",
     text_sub("			mu = friction_at(surfaces, s[RB.POS] + north[0] * rx + north[1] * ry + north[2] * rz,\n				s[RB.POS + 1] + east[0] * rx + east[1] * ry + east[2] * rz)",
              "			mu = friction_at(surfaces, s[RB.POS + 1] + east[0] * rx + east[1] * ry + east[2] * rz,\n				s[RB.POS] + north[0] * rx + north[1] * ry + north[2] * rz)"), MAIN),
    ("fixed E3d1 regularization band", "physics/hull_contact.gd",
     text_sub("	return maxf(SLIP_REGULARIZATION_MIN_MPS, float(touching) * mu * f_up / (m_min * FRICTION_RATE_MAX))", "	return 0.2"), MAIN),
    ("regularization ignores the load", "physics/hull_contact.gd",
     text_sub("	return maxf(SLIP_REGULARIZATION_MIN_MPS, float(touching) * mu * f_up / (m_min * FRICTION_RATE_MAX))",
              "	return SLIP_REGULARIZATION_MIN_MPS"), MAIN),
    ("regularization sized on the whole mass", "physics/hull_contact.gd",
     text_sub("		var m_min: float = prepared.stiffness[point] / (OMEGA_RAD_S * OMEGA_RAD_S)", "		var m_min: float = float(prepared.mass)"), MAIN),
    ("touching points not shared in the rate bound", "physics/hull_contact.gd",
     text_sub("		var scale := mu * f_up / maxf(slip, slip_regularization(mu, f_up, m_min, touching))",
              "		var scale := mu * f_up / maxf(slip, slip_regularization(mu, f_up, m_min))"), MAIN),
    ("session never installs the airframe table", "sim/flight_session.gd",
     text_sub("	airframe_surfaces = airframe.rects\n", "	airframe_surfaces = PackedFloat64Array()\n"), MAIN),
    ("setting the table does not re-prepare the hull", "sim/flight_session.gd",
     text_sub("		_airframe_surfaces = value.duplicate()\n		if sim != null and aircraft.get(\"ok\", false):",
              "		_airframe_surfaces = value.duplicate()\n		if false:"), MAIN),
    ("airframe table missing from the soft hash", "sim/flight_session.gd",
     text_sub("		parts.append(airframe_surfaces)\n", ""), MAIN),
    ("airframe table leaks into the legacy hash", "sim/flight_session.gd",
     text_sub("	var parts: Array = [aircraft.model, ground_surfaces]", "	var parts: Array = [aircraft.model, ground_surfaces, airframe_surfaces]"), MAIN),
    ("flight log header drops the airframe table", "sim/flight_log.gd",
     text_sub("		airframe_surfaces = _session.airframe_surfaces.duplicate(),\n", ""), MAIN),
    ("replay ignores the logged airframe table", "tools/flight_log_cli.gd",
     text_sub("	flight.set(\"airframe_surfaces\", header.get(\"airframe_surfaces\", PackedFloat64Array()))\n", ""), MAIN),
    ("presentation keeps the paving runway friction", "render/crash/severity.gd",
     text_sub('	"runway": 0.40,', '	"runway": 0.55,'), MAIN),
    ("presentation keeps the paving runway rebound", "render/crash/severity.gd",
     text_sub('"dirt": 0.08, "runway": 0.06,', '"dirt": 0.08, "runway": 0.18,'), MAIN),
    ("runway strip throws no dust again", "render/crash/effects.gd",
     text_sub('const HARD_SURFACES := ["asphalt",', 'const HARD_SURFACES := ["runway", "asphalt",'), "test_crash_presentation_ladder"),
    ("runway strip sounds like paving again", "render/crash/crash_audio.gd",
     text_sub('	if surface.contains("asphalt") or surface.contains("concrete")', '	if surface.contains("runway") or surface.contains("asphalt") or surface.contains("concrete")'),
     "test_crash_audio"),
]


def run(work, test):
    out = subprocess.run([GODOT, "--headless", "--path", work, "--audio-driver", "Dummy", "--script", f"res://tests/{test}.gd"],
                         capture_output=True, text=True, timeout=600)
    # Some tests print their failures to stderr (test_crash_audio).
    fails = [line for line in (out.stdout + out.stderr).splitlines() if line.startswith("FAIL")]
    crashed = not fails and (out.returncode != 0 or any(line.startswith(("ERROR:", "SCRIPT ERROR:"))
                                                        for line in (out.stdout + out.stderr).splitlines()))
    return fails, crashed


def main():
    only = sys.argv[2] if len(sys.argv) > 2 else ""  # optional: run only mutations whose label contains this text
    top = os.path.join(sys.argv[1], "gp07-mutants")
    if os.path.exists(top):
        shutil.rmtree(top)
    os.makedirs(top)
    work = os.path.join(top, "app")
    shutil.copytree(os.path.join(REPO, "app"), work, ignore=shutil.ignore_patterns("captures"))
    # The aircraft builders read the repository's assets/ next to app/ (read-only here).
    os.symlink(os.path.join(REPO, "assets"), os.path.join(top, "assets"))
    try:
        for test in sorted({m[3] for m in MUTATIONS}):
            fails, crashed = run(work, test)
            print(("baseline ok   " if not fails and not crashed else "BASELINE FAIL ") + test)
            if fails or crashed:
                sys.exit("GP-07 mutations: the unmutated copy fails %s; fix the copy before judging mutants" % test)
        killed = 0
        selected = [m for m in MUTATIONS if only in m[0]]
        for label, rel, edit, test in selected:
            path = os.path.join(work, rel)
            original = open(path, "rb").read()
            open(path, "wb").write(edit(original.decode("utf-8")).encode("utf-8"))
            fails, crashed = run(work, test)
            open(path, "wb").write(original)
            killed += bool(fails or crashed)
            print(("KILLED   " if fails or crashed else "SURVIVED ") + f"{label}: {len(fails)} failing checks"
                  + (f" (e.g. {fails[0][5:].strip()})" if fails else (" (engine error)" if crashed else "")))
        print(f"{killed}/{len(selected)} mutations killed")
    finally:
        shutil.rmtree(top)


if __name__ == "__main__":
    main()
