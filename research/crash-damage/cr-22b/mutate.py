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
 ("glow fuel burns like kerosene", "render/crash/effects.gd", text_sub("	if kerosene > 0.0 and hot_turbine and ruptured and level >= 3:", "	if (kerosene > 0.0 or glow > 0.0) and ruptured and level >= 3:")),
 ("gasoline burns in any structural crash", "render/crash/effects.gd", text_sub("	elif gasoline > 0.0 and engine_running and level == 4 and central:", "	elif gasoline > 0.0 and level >= 3:")),
 ("no fuel stain", "render/crash/effects.gd", text_sub("		out.stain = true # methanol", "		out.stain = false # methanol")),
 ("LiPo vents immediately", "render/crash/effects.gd", text_sub("		out.vent_delay_s = lerpf(VENT_DELAY_MAX_S, VENT_DELAY_MIN_S, severity)", "		out.vent_delay_s = 0.0")),
 ("LiPo vents on any hit", "render/crash/effects.gd", text_sub("	if lipo > 0.0 and level >= 3 and central:", "	if lipo > 0.0:")),
 ("every LiPo crash flares", "render/crash/effects.gd", text_sub("		out.flare = level == 4 and severity >= FLARE_MIN_SEVERITY", "		out.flare = true")),
 ("venting never stops", "render/crash/effects.gd", text_sub("	var venting := _age >= _vent_start_s and _age < _vent_end_s", "	var venting := _age >= _vent_start_s")),
 ("reset keeps pending venting", "render/crash/effects.gd", text_sub("	_fire_duration = 0\n	_vent_start_s = INF", "	_fire_duration = 0")),
 ("P-51 fuel tagged as glow", "data/aircraft/p51d_mustang_120.json", text_sub('"energy_source": "gasoline"', '"energy_source": "glow_fuel"')),
 ("synthetic donor ballast tagged as fuel", "data/aircraft/synthetic_stik_electric_4s.json", json_labels(lambda a: None) if False else text_sub('"name": "donor mass at the fuel station (no fuel)",', '"name": "donor mass at the fuel station (no fuel)",\n      "energy_source": "glow_fuel",')),
]
work = os.path.join(SP, "mut22b")
for label, rel, edit in MUTS:
    if os.path.exists(work): shutil.rmtree(work)
    shutil.copytree(os.path.join(REPO, "app"), work, ignore=shutil.ignore_patterns("captures"))
    path = os.path.join(work, rel)
    mutated = edit(open(path, encoding="utf-8").read())
    open(path, "w", encoding="utf-8").write(mutated)
    out = subprocess.run([G, "--headless", "--path", work, "--audio-driver", "Dummy", "--script", "res://tests/test_crash_energy.gd"], capture_output=True, text=True, timeout=300)
    fails = [l for l in out.stdout.splitlines() if l.startswith("FAIL")]
    # app/test.sh fails a test on any engine ERROR line; apply the same rule.
    crashed = not fails and (out.returncode != 0 or any(l.startswith(("ERROR:", "SCRIPT ERROR:")) for l in (out.stdout + out.stderr).splitlines()))
    print(("KILLED  " if fails or crashed else "SURVIVED") + f" {label}: {len(fails)} failing checks" + (f" (e.g. {fails[0][5:]})" if fails else (" (engine error, failed by test.sh)" if crashed else "")))
shutil.rmtree(work)
