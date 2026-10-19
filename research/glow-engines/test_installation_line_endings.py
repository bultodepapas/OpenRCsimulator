"""Verify generated glow installation JSON keeps its exact CRLF representation."""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_installations  # noqa: E402

EXPECTED_GENERATED_PATHS = {
    "app/data/glow/stik_55ax_2t.json",
    "app/data/aircraft/stik_glow_55ax_2t.json",
    "app/data/glow/stik_55ax_2t_apc_13x6.json",
    "app/data/aircraft/stik_glow_55ax_2t_apc_13x6.json",
    "app/data/glow/stik_fs64v_4t.json",
    "app/data/aircraft/stik_glow_fs64v_4t.json",
    "app/data/glow/stik_fs64v_4t_apc_13x6.json",
    "app/data/aircraft/stik_glow_fs64v_4t_apc_13x6.json",
    "app/data/glow/stik_61fx_2t.json",
    "app/data/aircraft/stik_glow_61fx_2t.json",
    "app/data/glow/extra_61fx_2t.json",
}


def expected_crlf(value: dict) -> bytes:
    text = json.dumps(value, indent=2, ensure_ascii=False) + "\n"
    return text.replace("\n", "\r\n").encode("utf-8")


class InstallationLineEndingTests(unittest.TestCase):
    def test_fresh_checkouts_preserve_every_installation_output(self) -> None:
        tools = ROOT / ".tools"
        tools.mkdir(exist_ok=True)
        generated = build_installations.outputs()
        with tempfile.TemporaryDirectory(prefix="fuel-checkout-", dir=tools) as directory:
            work = Path(directory)
            source = work / "source"
            source.mkdir()
            shutil.copy2(ROOT / ".gitattributes", source / ".gitattributes")
            for path in generated:
                destination = source / path.relative_to(ROOT)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination)

            def git(cwd: Path, *args: str) -> None:
                subprocess.run(["git", "-c", "user.name=Fuel checkout fixture", "-c",
                                "user.email=fuel-fixture@localhost", *args], cwd=cwd,
                               check=True, capture_output=True)

            git(source, "init", "--quiet")
            git(source, "add", ".")
            git(source, "commit", "--quiet", "-m", "Disposable fuel byte fixture")
            for autocrlf in ("false", "true"):
                clone = work / ("clone-" + autocrlf)
                git(work, "-c", "core.autocrlf=" + autocrlf, "clone", "--quiet", str(source), str(clone))
                for path in generated:
                    relative = path.relative_to(ROOT)
                    self.assertEqual((clone / relative).read_bytes(), path.read_bytes(),
                                     f"{relative}, autocrlf={autocrlf}")

    def test_balance_accumulation_is_left_to_right(self) -> None:
        # This order deliberately distinguishes sequential += from newer
        # compensated built-in sum implementations.
        self.assertEqual(build_installations.left_to_right_sum([1e16, 1.0, -1e16]), 0.0)
        self.assertEqual(build_installations.left_to_right_sum([1e16, -1e16, 1.0]), 1.0)

    def test_generator_writes_identical_crlf_bytes_on_any_host(self) -> None:
        payload = {"engine": "fixture", "nested": [1, {"enabled": True}]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "generated.json"
            build_installations.write_generated_json(path, payload)
            first = path.read_bytes()
            build_installations.write_generated_json(path, payload)
            second = path.read_bytes()

        self.assertEqual(first, expected_crlf(payload))
        self.assertEqual(second, first)
        self.assertNotIn(b"\n", first.replace(b"\r\n", b""))

    def test_checked_in_installation_and_aircraft_outputs_are_crlf(self) -> None:
        generated = build_installations.outputs()
        paths = {path.relative_to(ROOT).as_posix() for path in generated}
        self.assertEqual(paths, EXPECTED_GENERATED_PATHS)
        # Extra has its own finite-glow aircraft generator, but this shared pipeline
        # owns its installation and must bind the reviewed 61FX candidate by profile ID.
        extra_path = ROOT / "app/data/glow/extra_61fx_2t.json"
        extra_installation = generated[extra_path]
        self.assertEqual(extra_installation["family"], "glow_2t")
        self.assertEqual(extra_installation["profile"], "res://data/glow/os_max_61fx_candidate.json")
        self.assertNotIn("fuel_feed", extra_installation)  # no Extra-specific carburetor location is sourced
        profile = json.loads((ROOT / "app/data/glow/os_max_61fx_candidate.json").read_text(encoding="utf-8"))
        self.assertEqual((profile["id"], profile["family"]), ("os_max_61fx_candidate", "glow_2t"))
        for path, value in generated.items():
            with self.subTest(path=path.relative_to(ROOT)):
                self.assertEqual(path.read_bytes(), expected_crlf(value))


if __name__ == "__main__":
    unittest.main()
