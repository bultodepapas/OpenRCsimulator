"""Build an isolated copy of app/ with a probe wrapper as its main scene."""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
PROBE = ROOT / "research" / "glow-engines" / "performance_probe.gd"
WRAPPER = ROOT / "research" / "glow-engines" / "release_probe_wrapper.gd"
SCENE = ROOT / "research" / "glow-engines" / "release_probe_wrapper.tscn"


def _ignore(directory: str, names: list[str]) -> set[str]:
	return {name for name in names if name in {".tools", "tests", "docs"}}


def _replace_one(text: str, pattern: str, replacement: str, label: str) -> str:
	updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
	if count != 1:
		raise RuntimeError(f"Expected exactly one {label} setting; found {count}")
	return updated


def build(target_root: Path) -> dict[str, str]:
	target_root = target_root.resolve()
	tools_root = (ROOT / ".tools").resolve()
	if tools_root not in target_root.parents:
		raise ValueError(f"Build target must be below {tools_root}")
	if target_root.exists():
		raise FileExistsError(f"Refusing to replace existing build target: {target_root}")
	project = target_root / "project"
	target_root.mkdir(parents=True)
	shutil.copytree(APP, project, ignore=_ignore)

	research = project / "research" / "glow-engines"
	research.mkdir(parents=True)
	shutil.copy2(PROBE, research / PROBE.name)
	shutil.copy2(WRAPPER, research / WRAPPER.name)
	shutil.copy2(SCENE, research / SCENE.name)

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
		extras = "data/**/*.json,research/glow-engines/*.gd,research/glow-engines/*.tscn"
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

	manifest = {
		"source_project": str(APP),
		"isolated_project": str(project),
		"main_scene": "res://research/glow-engines/release_probe_wrapper.tscn",
		"production_project_mutated": False,
		"excluded_from_copy": [".tools", "tests", "docs"],
	}
	(target_root / "build_manifest.json").write_text(
		json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
	)
	return {"project": str(project), "target_root": str(target_root)}


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument(
		"--target",
		type=Path,
		default=ROOT / ".tools" / "glow-release-probe-20261013",
	)
	args = parser.parse_args()
	result = build(args.target)
	print(json.dumps(result, indent=2))


if __name__ == "__main__":
	main()
