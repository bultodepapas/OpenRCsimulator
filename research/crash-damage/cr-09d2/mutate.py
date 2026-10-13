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
 ("wreck ground ignores the surface", "render/crash/wreck.gd", text_sub('	_set_ground_surface(str(severity.get("surface", "unknown")))', '	_set_ground_surface("unknown")')),
 ("rebound fixed at 0.12", "render/crash/wreck.gd", text_sub("		body.linear_velocity.y = minf(-body.linear_velocity.y * float(_ground_contact.bounce), 5.0)", "		body.linear_velocity.y = minf(-body.linear_velocity.y * 0.12, 5.0)")),
 ("ground material never applied", "render/crash/wreck.gd", text_sub("	_ground.physics_material_override = material", "	pass")),
 ("glow fuel flashes", "render/crash/effects.gd", text_sub("	if not out.fire_kind.is_empty():\n		# A fuel fire starts", "	if not out.fire_kind.is_empty() or glow > 0.0:\n		# A fuel fire starts")),
 ("flash lasts forever", "render/crash/effects.gd", text_sub("		_flash_end_s = _age + _flash_s", "		_flash_end_s = INF")),
 ("flash ignores the fuel mass", "render/crash/effects.gd", text_sub("		out.flash_radius_m = minf(0.5 * 5.8 * cube, FLASH_MAX_RADIUS_M)", "		out.flash_radius_m = 0.5")),
 ("no fireball particles", "render/crash/effects.gd", text_sub("		fireball.restart()\n		fireball.emitting = true", "		pass")),
]
work = os.path.join(SP, "mut09d2")
for label, rel, edit in MUTS:
    if os.path.exists(work): shutil.rmtree(work)
    shutil.copytree(os.path.join(REPO, "app"), work, ignore=shutil.ignore_patterns("captures"))
    path = os.path.join(work, rel)
    mutated = edit(open(path, encoding="utf-8").read())
    open(path, "w", encoding="utf-8").write(mutated)
    outs = [subprocess.run([G, "--headless", "--path", work, "--audio-driver", "Dummy", "--script", f"res://tests/{t}.gd"], capture_output=True, text=True, timeout=400) for t in ("test_crash_wreck_surface", "test_crash_energy")]
    class R: pass
    out = R(); out.stdout = "".join(o.stdout for o in outs); out.stderr = "".join(o.stderr for o in outs); out.returncode = max(o.returncode for o in outs)
    fails = [l for l in out.stdout.splitlines() if l.startswith("FAIL")]
    # app/test.sh fails a test on any engine ERROR line; apply the same rule.
    crashed = not fails and (out.returncode != 0 or any(l.startswith(("ERROR:", "SCRIPT ERROR:")) for l in (out.stdout + out.stderr).splitlines()))
    print(("KILLED  " if fails or crashed else "SURVIVED") + f" {label}: {len(fails)} failing checks" + (f" (e.g. {fails[0][5:]})" if fails else (" (engine error, failed by test.sh)" if crashed else "")))
shutil.rmtree(work)
