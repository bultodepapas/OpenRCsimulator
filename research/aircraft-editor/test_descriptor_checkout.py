"""AE-01: exact-byte descriptor bindings survive fresh LF/CRLF Git checkouts."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CheckoutBindings(unittest.TestCase):
    def test_fresh_checkouts_keep_exact_bindings(self):
        tools = (ROOT / ".tools").resolve()
        tools.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="workshop-checkout-", dir=tools) as directory:
            work = Path(directory).resolve()
            self.assertTrue(work.is_relative_to(tools))
            source = work / "source"
            source.mkdir()
            paths = [Path(".gitattributes"), Path("app/app_state/aircraft_catalog.gd"),
                     Path("app/data/ground/wheel_profiles.json"),
                     Path("app/data/schema/aircraft-modules-v1.json"),
                     Path("research/aircraft-standardization/modules.py"),
                     Path("research/aircraft-editor/build_descriptors.py")]
            paths.extend(path.relative_to(ROOT) for path in (ROOT / "app/data/aircraft").glob("*.json"))
            paths.extend(path.relative_to(ROOT) for path in (ROOT / "app/data/workshop").glob("*.json"))
            paths.extend(path.relative_to(ROOT) for path in (ROOT / "app/data/aircraft_models").glob("*.json"))
            for relative in paths:
                target = source / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)

            def git(cwd, *args):
                return subprocess.run(["git", "-c", "user.name=Workshop checkout test", "-c",
                                       "user.email=workshop-test@localhost", *args], cwd=cwd,
                                      check=True, capture_output=True, text=True)

            git(source, "init", "--quiet")
            git(source, "add", ".")
            git(source, "commit", "--quiet", "-m", "Disposable byte-binding fixture")
            for mode in ("false", "true"):
                clone = work / ("clone-" + mode)
                git(work, "-c", "core.autocrlf=" + mode, "clone", "--quiet", str(source), str(clone))
                result = subprocess.run(["python", "research/aircraft-editor/build_descriptors.py", "--check"],
                                        cwd=clone, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                # This companion is part of every variant's dependency manifest.
                wheel = Path("app/data/ground/wheel_profiles.json")
                self.assertEqual((clone / wheel).read_bytes(), (ROOT / wheel).read_bytes())


if __name__ == "__main__":
    unittest.main()
