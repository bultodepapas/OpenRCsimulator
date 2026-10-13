# CR-01d mutation harness: python3 mutate.py <scratch dir> <repository root>. Each mutant runs on a disposable copy of app/.
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
 ("Extra left/right tip names swapped", "data/aircraft/gp_extra_300s_60.json", json_labels(swap(0, 1))),
 ("Stik spinner and tail_end swapped", "data/aircraft/jensen_ugly_stik_60.json", json_labels(swap(2, 3))),
 ("P-51 fin_top and canopy swapped", "data/aircraft/p51d_mustang_120.json", json_labels(swap(11, 12))),
 ("Timber stab tip named as wing tip", "data/aircraft/turbo_lumber_evolution.json", json_labels(lambda a: a.__setitem__(4, "left_wing_tip"))),
 ("Avanti belly named canopy (one point)", "data/aircraft/sebart_avanti_s_a200.json", json_labels(lambda a: a.__setitem__(6, "canopy"))),
 ("loader skips the length check", "physics/aircraft_data.gd", text_sub("	if (node as Array).size() != point_count:", "	if false:")),
 ("loader accepts any string", "physics/aircraft_data.gd", text_sub("typeof(name) != TYPE_STRING or not HULL_COMPONENTS.has(name)", "typeof(name) != TYPE_STRING")),
 ("loader vocabulary drifts from contract", "physics/aircraft_data.gd", text_sub('"canopy", "belly"]', '"canopy", "belly", "gear"]')),
 ("director ignores labels", "render/crash/director.gd", text_sub("	if point_index >= 0 and point_index < labels.size():", "	if false:")),
 ("director trusts out-of-range index", "render/crash/director.gd", text_sub("	if point_index >= 0 and point_index < labels.size():", "	if point_index >= 0 and not labels.is_empty():")),
 ("wreck spinner rule removed", "render/crash/wreck.gd", text_sub('normalized.contains("propeller") or normalized.contains("spinner")', 'normalized.contains("propeller")')),
]
work = os.path.join(SP, "mut01d")
for label, rel, edit in MUTS:
    if os.path.exists(work): shutil.rmtree(work)
    shutil.copytree(os.path.join(REPO, "app"), work, ignore=shutil.ignore_patterns("captures"))
    path = os.path.join(work, rel)
    mutated = edit(open(path, encoding="utf-8").read())
    open(path, "w", encoding="utf-8").write(mutated)
    out = subprocess.run([G, "--headless", "--path", work, "--audio-driver", "Dummy", "--script", "res://tests/test_crash_hull_labels.gd"], capture_output=True, text=True, timeout=300)
    fails = [l for l in out.stdout.splitlines() if l.startswith("FAIL")]
    # app/test.sh fails a test on any engine ERROR line; apply the same rule.
    crashed = not fails and (out.returncode != 0 or any(l.startswith(("ERROR:", "SCRIPT ERROR:")) for l in (out.stdout + out.stderr).splitlines()))
    print(("KILLED  " if fails or crashed else "SURVIVED") + f" {label}: {len(fails)} failing checks" + (f" (e.g. {fails[0][5:]})" if fails else (" (engine error, failed by test.sh)" if crashed else "")))
shutil.rmtree(work)
