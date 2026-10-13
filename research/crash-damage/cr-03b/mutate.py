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
 ("spherical dust burst again", "render/crash/effects.gd", text_sub("	dust.spread = 30.0", "	dust.spread = 82.0")),
 ("dust on hard surfaces", "render/crash/effects.gd", text_sub("	if HARD_SURFACES.has(s):\n		return []", "	if false:\n		return []")),
 ("sparks for any hard-surface C3 (old rule)", "render/crash/effects.gd", text_sub("	return METAL_GROUPS.has(component_group) and tangential_mps >= SPARK_SLIDE_MPS", "	return level >= 3")),
 ("radial chip fountain again", "render/crash/effects.gd", text_sub("slide.limit_length(80)*0.25 + Vector3(_rng.randf_range(-1.5,1.5),_rng.randf_range(0.5,3.0),_rng.randf_range(-1.5,1.5))*(0.4 + power)", "velocity.limit_length(80)*0.18 + Vector3(_rng.randf_range(-4,4),_rng.randf_range(2,8),_rng.randf_range(-4,4))*power")),
 ("chips below C2", "render/crash/effects.gd", text_sub("	if level < 2:\n		return 0\n	if level == 2:", "	if level < 0:\n		return 0\n	if level <= 2:")),
 ("chips ignore the airframe palette", "render/crash/effects.gd", text_sub("	return debris_colors[index % debris_colors.size()]", "	return DEFAULT_DEBRIS[0]")),
 ("crack at every class", "render/crash/crash_audio.gd", text_sub("	if outcome_class >= 2:\n		layers.append({sample = \"crack_light\"", "	if outcome_class >= 0:\n		layers.append({sample = \"crack_light\"")),
 ("engine cut on any C2", "render/crash/crash_audio.gd", text_sub('(outcome_class == 2 and group in ["propeller", "engine"])', "outcome_class == 2")),
 ("dark hardware colours kept", "render/crash/director.gd", text_sub("			if key.get_luminance() < CHIP_MIN_LUMINANCE:\n				continue", "			if false:\n				continue")),
]
work = os.path.join(SP, "mut03b")
for label, rel, edit in MUTS:
    if os.path.exists(work): shutil.rmtree(work)
    shutil.copytree(os.path.join(REPO, "app"), work, ignore=shutil.ignore_patterns("captures"))
    path = os.path.join(work, rel)
    mutated = edit(open(path, encoding="utf-8").read())
    open(path, "w", encoding="utf-8").write(mutated)
    out = subprocess.run([G, "--headless", "--path", work, "--audio-driver", "Dummy", "--script", "res://tests/test_crash_presentation_ladder.gd"], capture_output=True, text=True, timeout=300)
    fails = [l for l in out.stdout.splitlines() if l.startswith("FAIL")]
    # app/test.sh fails a test on any engine ERROR line; apply the same rule.
    crashed = not fails and (out.returncode != 0 or any(l.startswith(("ERROR:", "SCRIPT ERROR:")) for l in (out.stdout + out.stderr).splitlines()))
    print(("KILLED  " if fails or crashed else "SURVIVED") + f" {label}: {len(fails)} failing checks" + (f" (e.g. {fails[0][5:]})" if fails else (" (engine error, failed by test.sh)" if crashed else "")))
shutil.rmtree(work)
