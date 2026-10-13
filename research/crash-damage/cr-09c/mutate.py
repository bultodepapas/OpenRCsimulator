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
 ("release keeps sections the model lacks", "render/crash/wreck.gd", text_sub("		if present.has(resolved) and not available.has(resolved):", "		if not available.has(resolved):")),
 ("glTF extras ignored", "render/crash/wreck.gd", text_sub("	if extras is Dictionary and (extras as Dictionary).has(SECTION_EXTRAS_KEY):", "	if false:")),
 ("core tag stops the search", "render/crash/wreck.gd", text_sub("			if not part_kind.is_empty() and part_kind != CORE_SECTION:", "			if not part_kind.is_empty():")),
 ("splitter never runs", "render/crash/wreck.gd", text_sub("	var split := SectionSplitter.apply(_twin)", "	var split := {ok = true}")),
 ("splitter drops the last run", "render/crash/section_splitter.gd", text_sub("		for r in range(0, runs.size(), 2):\n			var section := int(runs[r])", "		for r in range(0, runs.size() - 2, 2):\n			var section := int(runs[r])")),
 ("splitter skips map validation", "render/crash/section_splitter.gd", text_sub("	var check := validate(mesh, map)\n	if not check.ok:", "	var check := validate(mesh, map)\n	if false:")),
 ("sections lose their materials", "render/crash/section_splitter.gd", text_sub("			target.surface_set_material(target.get_surface_count() - 1, mesh_instance.get_active_material(s))", "			pass")),
 ("Timber hinges not tagged", "aircraft/timber_model.gd", text_sub("			pivot.set_meta(SectionSplitter.SECTION_META, String(pair[1]))", "			pass")),
 ("Timber map not attached", "aircraft/timber_model.gd", text_sub("		airframe.set_meta(SectionSplitter.META, CrashSections.DATA)", "		pass")),
]
work = os.path.join(SP, "mut09c")
for label, rel, edit in MUTS:
    if os.path.exists(work): shutil.rmtree(work)
    shutil.copytree(os.path.join(REPO, "app"), work, ignore=shutil.ignore_patterns("captures"))
    path = os.path.join(work, rel)
    mutated = edit(open(path, encoding="utf-8").read())
    open(path, "w", encoding="utf-8").write(mutated)
    out = subprocess.run([G, "--headless", "--path", work, "--audio-driver", "Dummy", "--script", "res://tests/test_crash_sections.gd"], capture_output=True, text=True, timeout=300)
    fails = [l for l in out.stdout.splitlines() if l.startswith("FAIL")]
    # app/test.sh fails a test on any engine ERROR line; apply the same rule.
    crashed = not fails and (out.returncode != 0 or any(l.startswith(("ERROR:", "SCRIPT ERROR:")) for l in (out.stdout + out.stderr).splitlines()))
    print(("KILLED  " if fails or crashed else "SURVIVED") + f" {label}: {len(fails)} failing checks" + (f" (e.g. {fails[0][5:]})" if fails else (" (engine error, failed by test.sh)" if crashed else "")))
shutil.rmtree(work)
