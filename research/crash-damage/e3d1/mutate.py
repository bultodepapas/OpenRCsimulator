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
 ("no friction", "physics/hull_contact.gd", text_sub("		var scale := FRICTION_MU * f_up / maxf(slip, SLIP_REGULARIZATION_MPS)", "		var scale := 0.0")),
 ("stiffness from the whole mass", "physics/hull_contact.gd", text_sub("		k.append(smallest * OMEGA_RAD_S * OMEGA_RAD_S)", "		k.append(mass * OMEGA_RAD_S * OMEGA_RAD_S)")),
 ("damper may pull into the ground", "physics/hull_contact.gd", text_sub("		if f_up <= 0.0:\n			continue # a damper never pulls the airframe into the ground", "		if false:\n			continue")),
 ("terminal cut far too lenient", "physics/hull_contact.gd", text_sub("const TERMINAL_J_PER_KG := 2.5", "const TERMINAL_J_PER_KG := 250.0")),
 ("terminal cut far too strict", "physics/hull_contact.gd", text_sub("const TERMINAL_J_PER_KG := 2.5", "const TERMINAL_J_PER_KG := 0.001")),
 ("resting points graded as new impacts", "physics/hull_contact.gd", text_sub("		if depth_before > 0.0:\n			continue # already in contact", "		if false:\n			continue # already in contact")),
 ("depth backstop removed", "physics/hull_contact.gd", text_sub("		if depth > CRASH_DEPTH_M:", "		if false:")),
 ("hull loads not applied", "sim/flight_session.gd", text_sub("	var hull: PackedFloat64Array = HullContact.loads(s, _hull_contact) if soft_hull_contacts else PackedFloat64Array()", "	var hull := PackedFloat64Array()")),
 ("soft contacts on by default", "sim/flight_session.gd", text_sub("var soft_hull_contacts := false", "var soft_hull_contacts := true")),
 ("legacy route also soft", "sim/flight_session.gd", text_sub("		elif touches_ground(sim.state):\n			_crash(ImpactSnapshot.hull_contact(", "		elif false:\n			_crash(ImpactSnapshot.hull_contact(")),
 ("production does not enable soft contacts", "main.gd", text_sub('str(args.get("soft-contacts", "on")) != "off"', 'false')),
 ("director gives no touch feedback", "render/crash/director.gd", text_sub("		_touch_feedback()\n		return", "		return")),
 ("touch feedback never clears on restart", "render/crash/effects.gd", text_sub("	for item in marks:\n		item.visible = false", "	for item in marks:\n		pass")),
]
work = os.path.join(SP, "mute3d1")
for label, rel, edit in MUTS:
    if os.path.exists(work): shutil.rmtree(work)
    shutil.copytree(os.path.join(REPO, "app"), work, ignore=shutil.ignore_patterns("captures"))
    path = os.path.join(work, rel)
    mutated = edit(open(path, encoding="utf-8").read())
    open(path, "w", encoding="utf-8").write(mutated)
    outs = [subprocess.run([G, "--headless", "--path", work, "--audio-driver", "Dummy", "--script", f"res://tests/{t}.gd"], capture_output=True, text=True, timeout=400) for t in ("test_soft_contacts", "test_soft_contact_feedback")]
    class R: pass
    out = R(); out.stdout = "".join(o.stdout for o in outs); out.stderr = "".join(o.stderr for o in outs); out.returncode = max(o.returncode for o in outs)
    fails = [l for l in out.stdout.splitlines() if l.startswith("FAIL")]
    # app/test.sh fails a test on any engine ERROR line; apply the same rule.
    crashed = not fails and (out.returncode != 0 or any(l.startswith(("ERROR:", "SCRIPT ERROR:")) for l in (out.stdout + out.stderr).splitlines()))
    print(("KILLED  " if fails or crashed else "SURVIVED") + f" {label}: {len(fails)} failing checks" + (f" (e.g. {fails[0][5:]})" if fails else (" (engine error, failed by test.sh)" if crashed else "")))
shutil.rmtree(work)
