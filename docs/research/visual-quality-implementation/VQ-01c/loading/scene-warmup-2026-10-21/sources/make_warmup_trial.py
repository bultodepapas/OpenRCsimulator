"""Disk-bounded isolated one-shot scene warmup experiment, never a production patch."""
from pathlib import Path
import os, shutil, difflib, hashlib, json
root = Path(__file__).resolve().parent
repo = root.parents[1]
for variant in ('load-control', 'load-warmup'):
    out = root / variant
    assert not out.exists(), out
    shutil.copytree(root / 'control', out, copy_function=os.link)
    project = out / 'app/project.godot'
    project.unlink()
    project.write_bytes((repo / 'app/project.godot').read_bytes())
    if variant == 'load-control':
        continue
    path = out / 'app/app_root.gd'
    original_bytes = path.read_bytes()
    before = path.read_text(encoding='utf-8')
    after = before.replace('var _workshop_home_detached := false', 'var _workshop_home_detached := false\nvar _trial_pending_scene := ""')
    old = '\tshow_home()\n\t_start_update_check()'
    new = '''	# Scratch experiment: one resource request, no early flight instance.
	if Catalog.can_fly(preferences.aircraft) and not Catalog.is_rotorcraft(preferences.aircraft):
		if ResourceLoader.load_threaded_request(FLIGHT_SCENE, "PackedScene", false) == OK:
			_trial_pending_scene = FLIGHT_SCENE
	show_home()
	_start_update_check()'''
    assert after.count(old) == 1
    after = after.replace(old, new)
    old = '\treturn load(route_path).instantiate()'
    new = '''	if route_path == _trial_pending_scene:
		var status := ResourceLoader.load_threaded_get_status(_trial_pending_scene)
		print("warmup trial status at Fly: ", status)
		var scene: PackedScene = ResourceLoader.load_threaded_get(_trial_pending_scene) as PackedScene
		_trial_pending_scene = ""
		if scene != null:
			return scene.instantiate()
	return load(route_path).instantiate()'''
    assert after.count(old) == 1
    after = after.replace(old, new)
    old = 'func _exit_tree() -> void:\n'
    new = '''func _exit_tree() -> void:
	if not _trial_pending_scene.is_empty():
		var begin := Time.get_ticks_usec()
		ResourceLoader.load_threaded_get(_trial_pending_scene)
		_trial_pending_scene = ""
		print("warmup trial exit drain usec: ", Time.get_ticks_usec() - begin)
'''
    assert after.count(old) == 1
    after = after.replace(old, new)
    path.unlink()
    path.write_text(after, encoding='utf-8')
    (root / 'warmup-trial.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile='control/app/app_root.gd', tofile='warmup/app/app_root.gd')), encoding='utf-8')
    (root / 'warmup-trial-identity.json').write_text(json.dumps({'control_sha256':hashlib.sha256(original_bytes).hexdigest(), 'patch_control_lf_sha256':hashlib.sha256(before.encode()).hexdigest(), 'candidate_sha256':hashlib.sha256(path.read_bytes()).hexdigest()}, indent=2), encoding='utf-8')
print('Created linked control and scratch warmup snapshots')
