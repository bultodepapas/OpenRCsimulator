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
 ("stall threshold ignores the aircraft data", "render/crash/cause.gd", text_sub('	var stall_alpha := float(reference.get("stall_alpha_deg", INF)) - Telemetry.STALL_MARGIN_DEG', "	var stall_alpha := 12.0")),
 ("no minimum stall duration", "render/crash/cause.gd", text_sub("	if _duration(stalled) >= MIN_STALL_S:", "	if not stalled.is_empty():")),
 ("spin never detected", "render/crash/cause.gd", text_sub("		if _duration(spinning) >= SPIN_MIN_S:", "		if false:")),
 ("bank change from the first stalled sample", "render/crash/cause.gd", text_sub("		var bank_reference := float((before.back() if not before.is_empty() else first).bank_deg)", "		var bank_reference := float(first.bank_deg)")),
 ("dive judged on the final path only", "render/crash/cause.gd", text_sub("	if steepest <= DIVE_PATH_DEG and", "	if path_deg <= DIVE_PATH_DEG and")),
 ("gear collapse checked before flight conditions", "render/crash/cause.gd", text_sub('	if samples.is_empty():\n		if trigger == "gear_limit":', '	if trigger == "gear_limit":\n		return _cause("gear_collapse", "x", "", factors)\n	if samples.is_empty():\n		if trigger == "gear_limit":')),
 ("dead stick on any engine stop", "render/crash/cause.gd", text_sub("	if _all_within(samples, t_end - DEAD_STICK_S, func(s: Dictionary) -> bool: return not bool(s.engine_running)):", "	if not bool(last.engine_running):")),
 ("director records no history", "render/crash/director.gd", text_sub("		_record_sample()\n		_touch_feedback()", "		_touch_feedback()")),
 ("card omits the cause", "render/crash/director.gd", text_sub('"\\nCause: %s" % CrashCause.line(report.cause) if report.has("cause") else ""', '""')),
]
work = os.path.join(SP, "mut01e")
for label, rel, edit in MUTS:
    if os.path.exists(work): shutil.rmtree(work)
    shutil.copytree(os.path.join(REPO, "app"), work, ignore=shutil.ignore_patterns("captures"))
    path = os.path.join(work, rel)
    mutated = edit(open(path, encoding="utf-8").read())
    open(path, "w", encoding="utf-8").write(mutated)
    out = subprocess.run([G, "--headless", "--path", work, "--audio-driver", "Dummy", "--script", "res://tests/test_crash_cause.gd"], capture_output=True, text=True, timeout=300)
    fails = [l for l in out.stdout.splitlines() if l.startswith("FAIL")]
    # app/test.sh fails a test on any engine ERROR line; apply the same rule.
    crashed = not fails and (out.returncode != 0 or any(l.startswith(("ERROR:", "SCRIPT ERROR:")) for l in (out.stdout + out.stderr).splitlines()))
    print(("KILLED  " if fails or crashed else "SURVIVED") + f" {label}: {len(fails)} failing checks" + (f" (e.g. {fails[0][5:]})" if fails else (" (engine error, failed by test.sh)" if crashed else "")))
shutil.rmtree(work)
