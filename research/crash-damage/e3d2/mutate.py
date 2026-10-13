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
 ("a strike needs an impossible rpm", "physics/hull_contact.gd", text_sub("const STRIKE_MIN_RPM := 300.0", "const STRIKE_MIN_RPM := 1.0e9")),
 ("a strike also needs no rotation", "physics/hull_contact.gd", text_sub("const STRIKE_MIN_RPM := 300.0", "const STRIKE_MIN_RPM := -1.0")),
 ("disc lowest point ignores the radius", "physics/hull_contact.gd", text_sub("		lowest = M.add(lowest, M.scale(p, float(disc.radius) / p_len))", "		pass")),
 ("strike keeps the engine running", "sim/flight_session.gd", text_sub("	engine_running = false\n	print(\"PROP STRIKE", "	print(\"PROP STRIKE")),
 ("strike checked before the crash", "sim/flight_session.gd", text_sub("		if soft_hull_contacts:\n			soft_contacts =", "		if soft_hull_contacts:\n			_check_prop_strike()\n			soft_contacts =")),
 ("blades stay visible", "render/crash/director.gd", text_sub("		_hidden_propeller.visible = false", "		pass")),
 ("wreck throws the broken propeller", "render/crash/wreck.gd", text_sub('	if class_level < 2 or (kind == "propeller" and _prop_broken):', "	if class_level < 2:")),
 ("restart keeps the propeller hidden", "render/crash/director.gd", text_sub("	if is_instance_valid(_hidden_propeller):\n		_hidden_propeller.visible = true", "	if false:\n		pass")),
]
work = os.path.join(SP, "mute3d2")
for label, rel, edit in MUTS:
    if os.path.exists(work): shutil.rmtree(work)
    shutil.copytree(os.path.join(REPO, "app"), work, ignore=shutil.ignore_patterns("captures"))
    path = os.path.join(work, rel)
    mutated = edit(open(path, encoding="utf-8").read())
    open(path, "w", encoding="utf-8").write(mutated)
    outs = [subprocess.run([G, "--headless", "--path", work, "--audio-driver", "Dummy", "--script", f"res://tests/{t}.gd"], capture_output=True, text=True, timeout=400) for t in ("test_prop_strike", "test_prop_strike_feedback", "test_crash_integration")]
    class R: pass
    out = R(); out.stdout = "".join(o.stdout for o in outs); out.stderr = "".join(o.stderr for o in outs); out.returncode = max(o.returncode for o in outs)
    fails = [l for l in out.stdout.splitlines() if l.startswith("FAIL")]
    # app/test.sh fails a test on any engine ERROR line; apply the same rule.
    crashed = not fails and (out.returncode != 0 or any(l.startswith(("ERROR:", "SCRIPT ERROR:")) for l in (out.stdout + out.stderr).splitlines()))
    print(("KILLED  " if fails or crashed else "SURVIVED") + f" {label}: {len(fails)} failing checks" + (f" (e.g. {fails[0][5:]})" if fails else (" (engine error, failed by test.sh)" if crashed else "")))
shutil.rmtree(work)
