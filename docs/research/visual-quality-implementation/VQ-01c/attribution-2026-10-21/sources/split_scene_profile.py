from pathlib import Path
import difflib
root = Path(__file__).resolve().parent
path = root / 'profile-deep/app/app_root.gd'
before = path.read_text(encoding='utf-8')
old = '\treturn load(route_path).instantiate()'
new = '''	var load_begin: int = Time.get_ticks_usec()
	var scene: PackedScene = load(route_path)
	Phase2LoadingProfile.record("flight_scene.load", load_begin, Time.get_ticks_usec())
	var instantiate_begin: int = Time.get_ticks_usec()
	var instance: Node = scene.instantiate()
	Phase2LoadingProfile.record("flight_scene.instantiate", instantiate_begin, Time.get_ticks_usec())
	return instance'''
assert before.count(old) == 1
after = before.replace(old, new)
(root / 'profile-deep/provenance/app_root-before-split.gd').write_text(before, encoding='utf-8')
path.unlink()
path.write_text(after, encoding='utf-8')
(root / 'profile-deep/provenance/split-scene.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile='profile04/app/app_root.gd', tofile='profile05/app/app_root.gd')), encoding='utf-8')
