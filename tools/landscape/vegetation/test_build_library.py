#!/usr/bin/env python3
"""CPU-only contract tests for retained vegetation source intake."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tempfile
import unittest
from zipfile import ZipFile


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_library as library  # noqa: E402


RETAINED_TREE_FACTS = {
    "common_tree_2": {
        "sha256": "67160975f0ac991b4a2ffb2add4ab4037b5e9c1bef9f66dac5235fcf0ba9bd52",
        "triangles": 5648,
        "surfaces": 2,
        "size": [4.464302, 7.642996, 4.275852],
    },
    "common_tree_4": {
        "sha256": "ddf0e8837705702871d3f03de8cf7aeed61ad4bf8ee92052b6f95bdd771297b6",
        "triangles": 4066,
        "surfaces": 2,
        "size": [3.825526, 9.438381, 3.755373],
    },
    "pine_2": {
        "sha256": "57bd4732170b6c7e51bcf78fe5adaabf142f95a50378d8d3051d1f20a04d3c2f",
        "triangles": 3648,
        "surfaces": 2,
        "size": [5.728085, 7.376238, 5.221207],
    },
    "pine_3": {
        "sha256": "54c72a4d614f053dd4b3d4404076a361de6085ec6a34560e42a76d7e79d89830",
        "triangles": 4964,
        "surfaces": 2,
        "size": [3.611395, 7.392199, 3.995804],
    },
}


def file_snapshot(root: Path) -> dict[str, str]:
    if not root.exists():
        return {}
    return {
        path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


class BuildLibraryTests(unittest.TestCase):
    def test_archive_and_output_paths_reject_traversal(self) -> None:
        for unsafe in ("../outside", "/absolute/file", "folder\\file", "nul\x00byte"):
            with self.subTest(path=unsafe), self.assertRaises(library.BuildError):
                library.archive_path(unsafe)

        root = ROOT / "tmp/tree-retained-intake/path-check"
        for unsafe in ("../outside", "models/../../outside", "C:/outside"):
            with self.subTest(path=unsafe), self.assertRaises(library.BuildError):
                library.output_path(root, unsafe)

    def test_default_selection_and_retained_variant_metadata_are_source_exact(self) -> None:
        with (
            ZipFile(library.ARCHIVE) as standard,
            ZipFile(library.CROPS_ARCHIVE) as crops,
            ZipFile(library.REED_ARCHIVE) as reeds,
        ):
            default_catalog, _ = library.catalog_for(standard, crops, reeds)
            candidate_catalog, candidate_files = library.catalog_for(
                standard,
                crops,
                reeds,
                include_reviewed_tree_variants=True,
            )

            installed_catalog = json.loads(library.RUNTIME_CATALOG.read_text(encoding="utf-8"))
            self.assertEqual(
                [asset["id"] for asset in default_catalog["assets"]],
                [asset["id"] for asset in installed_catalog["assets"]],
            )
            self.assertEqual(default_catalog["counts"]["total_assets"], 15)
            self.assertEqual(default_catalog["counts"]["trees"], 3)
            self.assertEqual(candidate_catalog["counts"]["total_assets"], 19)
            self.assertEqual(candidate_catalog["counts"]["trees"], 7)

            candidates = {
                asset["id"]: asset
                for asset in candidate_catalog["assets"]
                if asset["id"] in RETAINED_TREE_FACTS
            }
            self.assertEqual(set(candidates), set(RETAINED_TREE_FACTS))
            for asset_id, facts in RETAINED_TREE_FACTS.items():
                with self.subTest(asset=asset_id):
                    asset = candidates[asset_id]
                    self.assertEqual(asset["source_sha256"], facts["sha256"])
                    self.assertEqual(asset["source_triangles"], facts["triangles"])
                    self.assertEqual(asset["source_surfaces"], facts["surfaces"])
                    self.assertEqual(asset["source_bounds_m"]["size"], facts["size"])

                    for dependency in asset["dependencies"]:
                        output_name = (
                            "models/"
                            + PurePosixPath(dependency).relative_to("glTF").as_posix()
                        )
                        source_bytes = standard.read(dependency)
                        self.assertEqual(candidate_files[output_name], source_bytes)

    def test_candidate_generation_check_and_repeat_are_deterministic(self) -> None:
        trial_root = ROOT / "tmp/tree-retained-intake"
        trial_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="build-library-test-", dir=trial_root) as temp:
            work_root = Path(temp)
            candidate_root = work_root / "candidate-library"
            relative_output = candidate_root.relative_to(ROOT).as_posix()
            script = ROOT / "tools/landscape/vegetation/build_library.py"
            command = [
                sys.executable,
                str(script),
                "--output-root",
                relative_output,
                "--include-reviewed-tree-variants",
            ]

            production_before = file_snapshot(library.RUNTIME)
            source_evidence_before = {
                path: path.read_bytes()
                for path in (library.SOURCE_LICENSE, *library.SOURCE_NOTICES.keys())
            }

            generated = subprocess.run(
                command,
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(generated.returncode, 0, generated.stderr)
            catalog = json.loads((candidate_root / "catalog.json").read_text(encoding="utf-8"))
            self.assertEqual(catalog["counts"]["total_assets"], 19)
            first_snapshot = file_snapshot(candidate_root)

            checked = subprocess.run(
                [*command[:2], "--check", *command[2:]],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(checked.returncode, 0, checked.stderr)
            self.assertEqual(file_snapshot(candidate_root), first_snapshot)

            repeated = subprocess.run(
                command,
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(repeated.returncode, 0, repeated.stderr)
            self.assertEqual(file_snapshot(candidate_root), first_snapshot)

            self.assertEqual(file_snapshot(library.RUNTIME), production_before)
            self.assertEqual(
                {path: path.read_bytes() for path in source_evidence_before},
                source_evidence_before,
            )


if __name__ == "__main__":
    unittest.main()
