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
 ("scatter bursts outward from the core again", "render/crash/wreck.gd", text_sub("		if travel.length_squared() > 1.0:", "		if false:")),
 ("C2 never releases a part", "render/crash/wreck.gd", text_sub("	if class_level < 2:\n		return false", "	if class_level < 3:\n		return false")),
 ("C3 ignores the struck component", "render/crash/wreck.gd", text_sub("	if not _release_kinds.is_empty():\n		return _release_kinds.has(kind)", "	if false:\n		return false")),
 ("contact point ignored for delays", "render/crash/wreck.gd", text_sub("		elif _has_contact:", "		elif false:")),
 ("farther sections release first", "render/crash/wreck.gd", text_sub("clampf(distance / BREAK_PROPAGATION_MPS,", "clampf(1.0 / maxf(distance, 0.01) / BREAK_PROPAGATION_MPS,")),
 ("C3 nose hit releases wings too", "render/crash/wreck.gd", text_sub('kinds = ["propeller", "engine", "canopy"]', 'kinds = ["propeller", "engine", "canopy", "wing_left"]')),
 ("C2 wing tip releases the wing", "render/crash/wreck.gd", text_sub('		elif h.contains("canopy") or h.contains("hatch"):', '		elif h.contains("wing"):\n			kinds = ["wing_left"]\n		elif h.contains("canopy") or h.contains("hatch"):')),
]
work = os.path.join(SP, "mut09b")
for label, rel, edit in MUTS:
    if os.path.exists(work): shutil.rmtree(work)
    shutil.copytree(os.path.join(REPO, "app"), work, ignore=shutil.ignore_patterns("captures"))
    path = os.path.join(work, rel)
    mutated = edit(open(path, encoding="utf-8").read())
    open(path, "w", encoding="utf-8").write(mutated)
    out = subprocess.run([G, "--headless", "--path", work, "--audio-driver", "Dummy", "--script", "res://tests/test_crash_breakup.gd"], capture_output=True, text=True, timeout=300)
    fails = [l for l in out.stdout.splitlines() if l.startswith("FAIL")]
    # app/test.sh fails a test on any engine ERROR line; apply the same rule.
    crashed = not fails and (out.returncode != 0 or any(l.startswith(("ERROR:", "SCRIPT ERROR:")) for l in (out.stdout + out.stderr).splitlines()))
    print(("KILLED  " if fails or crashed else "SURVIVED") + f" {label}: {len(fails)} failing checks" + (f" (e.g. {fails[0][5:]})" if fails else (" (engine error, failed by test.sh)" if crashed else "")))
shutil.rmtree(work)
