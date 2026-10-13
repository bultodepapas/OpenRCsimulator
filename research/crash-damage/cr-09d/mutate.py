import shutil, subprocess, sys, os, json
SP, REPO = sys.argv[1], sys.argv[2]
G = os.path.join(REPO, ".tools/Godot_v4.7.2-stable_linux.x86_64")
def text_sub(old, new):
    def f(src):
        assert src.count(old) == 1, old
        return src.replace(old, new)
    return f
def json_labels(fn):
    def f(src):
        d = json.loads(src); fn(d["crash_hull_components"]); return json.dumps(d, indent=2, ensure_ascii=False) + "\n"
    return f
def swap(i, j):
    def f(a): a[i], a[j] = a[j], a[i]
    return f
MUTS = [
 ("inventory ignored (fixed shares)", "render/crash/wreck.gd", text_sub('	_section_masses = _inventory_masses(severity.get("inventory_boxes", []), total_mass)', "	_section_masses = {}")),
 ("no custom centre of mass", "render/crash/wreck.gd", text_sub("	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM\n	body.center_of_mass = Vector3(moment) / mass - origin", "	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_AUTO")),
 ("overlap ignores the box size", "render/crash/wreck.gd", text_sub("			fraction *= clampf((minf(hi, b_hi) - maxf(lo, b_lo)) / size[axis], 0.0, 1.0)", "			fraction *= 1.0 if center[axis] >= b_lo and center[axis] <= b_hi else 0.0")),
 ("section floor creates mass", "render/crash/wreck.gd", text_sub("			out.core.mass -= missing\n", "")),
 ("union box instead of member boxes", "render/crash/wreck.gd", text_sub('			for member_box: AABB in _groups[i].get("member_bounds", [_groups[i].bounds]):', '			for member_box: AABB in [_groups[i].bounds]:')),
 ("model frame axes swapped", "render/crash/director.gd", text_sub("		size = Vector3(absf(float(size[1])), absf(float(size[2])), absf(float(size[0])))}", "		size = Vector3(absf(float(size[0])), absf(float(size[1])), absf(float(size[2])))}")),
 ("director passes no inventory", "render/crash/director.gd", text_sub('	report["inventory_boxes"] = inventory_boxes', '	report["inventory_boxes"] = []')),
]
work = os.path.join(SP, "mut09d")
for label, rel, edit in MUTS:
    if os.path.exists(work): shutil.rmtree(work)
    shutil.copytree(os.path.join(REPO, "app"), work, ignore=shutil.ignore_patterns("captures"))
    path = os.path.join(work, rel)
    mutated = edit(open(path, encoding="utf-8").read())
    open(path, "w", encoding="utf-8").write(mutated)
    out = subprocess.run([G, "--headless", "--path", work, "--audio-driver", "Dummy", "--script", "res://tests/test_crash_masses.gd"], capture_output=True, text=True, timeout=300)
    fails = [l for l in out.stdout.splitlines() if l.startswith("FAIL")]
    # app/test.sh fails a test on any engine ERROR line; apply the same rule.
    crashed = not fails and (out.returncode != 0 or any(l.startswith(("ERROR:", "SCRIPT ERROR:")) for l in (out.stdout + out.stderr).splitlines()))
    print(("KILLED  " if fails or crashed else "SURVIVED") + f" {label}: {len(fails)} failing checks" + (f" (e.g. {fails[0][5:]})" if fails else (" (engine error, failed by test.sh)" if crashed else "")))
shutil.rmtree(work)
