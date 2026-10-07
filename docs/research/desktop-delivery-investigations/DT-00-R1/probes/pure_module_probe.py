#!/usr/bin/env python3
"""Probe copied production modules in a disposable project; never write app/user data."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


GDSCRIPT = r'''extends SceneTree

const Prefs = preload("res://app_state/preferences.gd")
const Radio = preload("res://input/rc_input.gd")

func _initialize() -> void:
	var path: String = "user://probe-settings.cfg"
	var initial: Dictionary = Prefs.load_from(path)
	assert(Prefs.save_to(path, initial) == OK)
	var first: Dictionary = Prefs.load_from(path)
	var second: Dictionary = Prefs.load_from(path)
	first.language = "es"
	assert(Prefs.save_to(path, first) == OK)
	second.aircraft = "gp-extra-300s-60"
	assert(Prefs.save_to(path, second) == OK)
	var after: Dictionary = Prefs.load_from(path)
	var result: Dictionary = {
		stale_writer = {first_language = first.language, final_language = after.language,
			final_aircraft = after.aircraft, earlier_language_lost = after.language != first.language}
	}
	var cfg: ConfigFile = ConfigFile.new()
	assert(cfg.load(path) == OK)
	cfg.set_value("future", "same_schema_extra", "preserve-me")
	assert(cfg.save(path) == OK)
	var known: Dictionary = Prefs.load_from(path)
	assert(Prefs.save_to(path, known) == OK)
	var reread: ConfigFile = ConfigFile.new()
	assert(reread.load(path) == OK)
	result.same_schema_unknown_key_removed = not reread.has_section_key("future", "same_schema_extra")
	reread.set_value("meta", "schema", 999)
	assert(reread.save(path) == OK)
	var original: String = FileAccess.get_file_as_string(path)
	var future: Dictionary = Prefs.load_from(path)
	var save_error: Error = Prefs.save_to(path, future)
	result.future_schema = {writable = future.writable, save_error = save_error,
		bytes_unchanged = original == FileAccess.get_file_as_string(path)}
	var info: Dictionary = {guid = "fixture-firmware-1", vendor_id = "4617",
		product_id = "20308", name = "Fixture Joystick", known = true}
	var updated: Dictionary = info.duplicate()
	updated.guid = "fixture-firmware-2"
	result.radio_identity = {same_key_for_two_runtime_ids = Radio.key_for(0, info) == Radio.key_for(1, info),
		changed_guid_changes_key = Radio.key_for(0, info) != Radio.key_for(0, updated)}
	var radio: RefCounted = Radio.new()
	radio.connect_device(0, info)
	result.synthetic_unrecognized_radio = {profile_source = radio.profile_source,
		vendor_id = int(info.vendor_id), product_id = int(info.product_id),
		kind = radio.profile.kind, caveat = "Synthetic info only; no device or SDL event was exercised."}
	result.godot = Engine.get_version_info().string
	result.user_dir_is_probe = OS.get_user_data_dir().contains("openrc-dt-probe")
	print("DT_PROBE_JSON=" + JSON.stringify(result))
	quit(0)
'''


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, timeout=45, **kwargs)
    if result.returncode:
        raise RuntimeError(f"Command failed: {command}\n{result.stdout}\n{result.stderr}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--linter', type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    paths = ['app/app_state/preferences.gd', 'app/app_state/aircraft_catalog.gd', 'app/input/rc_input.gd']
    contents = {name: (repo / name).read_bytes() for name in paths}
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in contents.items()}
    lint_results = {}
    with tempfile.TemporaryDirectory(prefix='openrc-dt-probe-') as temporary:
        temp = Path(temporary)
        project = temp / 'project'
        project.mkdir()
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="openrc-dt-probe"\n')
        if args.linter:
            lint_results['before'] = json.loads(run(['python3', str(args.linter), str(project)]).stdout)
        for name, data in contents.items():
            dest = project / name.removeprefix('app/')
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
        # Catalog paths remain valid for the static linter; the probe does not load aircraft data.
        for source in (repo / 'app/data/aircraft').glob('*.json'):
            dest = project / 'data/aircraft' / source.name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(source.read_bytes())
        (project / 'probe.gd').write_text(GDSCRIPT)
        if args.linter:
            lint_results['after'] = json.loads(run(['python3', str(args.linter), str(project)]).stdout)
        env = os.environ.copy()
        env['XDG_DATA_HOME'] = str(temp / 'data')
        env['XDG_CONFIG_HOME'] = str(temp / 'config')
        env['XDG_CACHE_HOME'] = str(temp / 'cache')
        result = run([str(args.godot.resolve()), '--headless', '--path', str(project),
                      '--script', 'res://probe.gd'], env=env)
        if 'SCRIPT ERROR:' in result.stderr or 'ERROR:' in result.stderr:
            raise RuntimeError(result.stderr)
        payloads = [line.removeprefix('DT_PROBE_JSON=') for line in result.stdout.splitlines()
                    if line.startswith('DT_PROBE_JSON=')]
        assert len(payloads) == 1, result.stdout
        observed = json.loads(payloads[0])
        assert observed['user_dir_is_probe']
    assert all((repo / p).read_bytes() == content for p, content in contents.items()), 'Source changed during probe; rerun.'
    output = {'format': 'openrc-desktop-pure-probe v1', 'step': 'DT-00-R1',
              'source_sha256': hashes, 'results': observed, 'lint': lint_results,
              'scope': 'Copied production pure modules, headless Linux; no app, real preferences, USB device or native GUI exercised.'}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps(observed, indent=2))


if __name__ == '__main__':
    main()
