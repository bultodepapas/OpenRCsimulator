"""Build an isolated copy of app/ with a probe wrapper as its main scene."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
PROBE = ROOT / "research" / "glow-engines" / "performance_probe.gd"
WRAPPER = ROOT / "research" / "glow-engines" / "release_probe_wrapper.gd"
SCENE = ROOT / "research" / "glow-engines" / "release_probe_wrapper.tscn"
BUILDER = ROOT / "research" / "glow-engines" / "build_release_probe_project.py"
EMBEDDED_MANIFEST_NAME = "release_probe_build_manifest.json"


def _ignore(directory: str, names: list[str]) -> set[str]:
	return {name for name in names if name in {".tools", "tests", "docs"}}


def _replace_one(text: str, pattern: str, replacement: str, label: str) -> str:
	updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
	if count != 1:
		raise RuntimeError(f"Expected exactly one {label} setting; found {count}")
	return updated


def _declared_paths(probe_source: str, constant_name: str) -> list[str]:
	match = re.search(
		rf"const {re.escape(constant_name)} := \[(.*?)\n\]",
		probe_source,
		re.DOTALL,
	)
	if match is None:
		raise RuntimeError(f"Could not read {constant_name} from the probe")
	return re.findall(r'"([^\"]+)"', match.group(1))


def _copied_path(project: Path, relative_path: str) -> Path:
	if relative_path.startswith("app/"):
		return project / relative_path[len("app/"):]
	return project / relative_path


def _hash_paths(project: Path, paths: list[str]) -> dict[str, str]:
	output: dict[str, str] = {}
	for relative_path in paths:
		copied_file = _copied_path(project, relative_path)
		if not copied_file.is_file():
			raise FileNotFoundError(f"Copied build input is missing: {relative_path}")
		output[relative_path] = hashlib.sha256(copied_file.read_bytes()).hexdigest()
	return output


def _combined_hash(hashes: dict[str, str]) -> str:
	context = hashlib.sha256()
	for relative_path in sorted(hashes):
		context.update(relative_path.encode("utf-8"))
		context.update(b"\0")
		context.update(hashes[relative_path].encode("utf-8"))
		context.update(b"\0")
	return context.hexdigest()


def build(target_root: Path, app_source: Path = APP) -> dict[str, str]:
	target_root = target_root.resolve()
	app_source = app_source.resolve()
	tools_root = (ROOT / ".tools").resolve()
	if tools_root not in target_root.parents:
		raise ValueError(f"Build target must be below {tools_root}")
	if not app_source.is_dir():
		raise FileNotFoundError(f"Probe app source is not a directory: {app_source}")
	if target_root.exists():
		raise FileExistsError(f"Refusing to replace existing build target: {target_root}")
	project = target_root / "project"
	target_root.mkdir(parents=True)
	shutil.copytree(app_source, project, ignore=_ignore)

	research = project / "research" / "glow-engines"
	research.mkdir(parents=True)
	shutil.copy2(PROBE, research / PROBE.name)
	shutil.copy2(WRAPPER, research / WRAPPER.name)
	shutil.copy2(SCENE, research / SCENE.name)
	shutil.copy2(BUILDER, research / BUILDER.name)

	project_file = project / "project.godot"
	project_text = project_file.read_text(encoding="utf-8")
	project_text = _replace_one(
		project_text,
		r'^run/main_scene="[^"]+"$',
		'run/main_scene="res://research/glow-engines/release_probe_wrapper.tscn"',
		"main scene",
	)
	project_file.write_text(project_text, encoding="utf-8")

	presets_file = project / "export_presets.cfg"
	presets_text = presets_file.read_text(encoding="utf-8")
	def add_probe_resources(match: re.Match[str]) -> str:
		value = match.group(1)
		extras = "data/**/*.json,research/glow-engines/*.gd,research/glow-engines/*.tscn,research/glow-engines/*.json,research/glow-engines/*.py"
		return f'include_filter="{value},{extras}"'

	presets_text, count = re.subn(
		r'^include_filter="([^"]*)"$',
		add_probe_resources,
		presets_text,
		flags=re.MULTILINE,
	)
	if count < 1:
		raise RuntimeError("Could not add probe resources to export presets")
	presets_file.write_text(presets_text, encoding="utf-8")

	probe_source = (research / PROBE.name).read_text(encoding="utf-8")
	source_paths = _declared_paths(probe_source, "SOURCE_PATHS")
	input_paths = _declared_paths(probe_source, "INPUT_PATHS")
	source_hashes = _hash_paths(project, source_paths)
	input_hashes = _hash_paths(project, input_paths)
	configuration_paths = ["project.godot", "export_presets.cfg"]
	build_configuration_hashes = _hash_paths(project, configuration_paths)
	embedded_manifest = {
		"format": "openrc-glow-release-probe-build-manifest v1",
		"hash_scope": "copied_project_files_after_overlay_before_export",
		"source_hashes": source_hashes,
		"input_hashes": input_hashes,
		"build_configuration_hashes": build_configuration_hashes,
		"source_tree_sha256": _combined_hash(source_hashes),
		"input_tree_sha256": _combined_hash(input_hashes),
		"provenance": "SHA-256 values computed from the isolated copied project after probe overlay and export configuration edits, immediately before export; these files are bundled in the exported main pack.",
	}
	embedded_manifest_path = research / EMBEDDED_MANIFEST_NAME
	embedded_manifest_bytes = (json.dumps(embedded_manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")
	embedded_manifest_path.write_bytes(embedded_manifest_bytes)

	manifest = {
		"format": "openrc-glow-release-probe-build v1",
		"source_project": str(app_source),
		"isolated_project": str(project),
		"main_scene": "res://research/glow-engines/release_probe_wrapper.tscn",
		"embedded_manifest": str(embedded_manifest_path),
		"embedded_manifest_sha256": hashlib.sha256(embedded_manifest_bytes).hexdigest(),
		"source_tree_sha256": embedded_manifest["source_tree_sha256"],
		"input_tree_sha256": embedded_manifest["input_tree_sha256"],
		"source_hashes": source_hashes,
		"input_hashes": input_hashes,
		"build_configuration_hashes": build_configuration_hashes,
		"production_project_mutated": False,
		"excluded_from_copy": [".tools", "tests", "docs"],
	}
	(target_root / "build_manifest.json").write_text(
		json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
	)
	return {"project": str(project), "target_root": str(target_root), "embedded_manifest_sha256": hashlib.sha256(embedded_manifest_bytes).hexdigest()}


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument(
		"--target",
		type=Path,
		default=ROOT / ".tools" / "glow-release-probe-20261013",
	)
	parser.add_argument(
		"--app-source",
		type=Path,
		default=APP,
		help="App tree to copy into the isolated probe project (defaults to the working app).",
	)
	args = parser.parse_args()
	result = build(args.target, args.app_source)
	print(json.dumps(result, indent=2))


if __name__ == "__main__":
	main()
