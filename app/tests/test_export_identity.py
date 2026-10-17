"""Exercise release identity and import failure gates using a disposable exporter."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class ExportIdentity(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-export-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "app"
        self.app.mkdir()
        source = Path(__file__).parents[1] / "export.sh"
        (self.app / "export.sh").write_text(source.read_text(encoding="utf-8"),
                                             encoding="utf-8", newline="\n")
        (self.app / "project.godot").write_text('config/version="1.2.3"\n', encoding="utf-8")
        scripts = {
            "get-godot.sh": '#!/usr/bin/env bash\nprintf "%s/fake-engine.sh\\n" "$(cd "$(dirname "$0")" && pwd)"\n',
            "get-templates.sh": "#!/usr/bin/env bash\nexit 0\n",
            "fake-engine.sh": '''#!/usr/bin/env bash
python3 - <<'PY'
import json, os
from pathlib import Path
keys = ("DESCRIBE", "COMMIT", "DIRTY", "DATE")
Path(os.environ["PROBE_IDENTITY"]).write_text(json.dumps({key: os.environ["OPENRC_BUILD_" + key] for key in keys}))
PY
if [[ "${PROBE_IMPORT_ERROR:-}" == 1 ]]; then
  echo 'SCRIPT ERROR: simulated import failure'
  exit 0
fi
exit 23
''',
        }
        for name, content in scripts.items():
            path = self.app / name
            path.write_text(content, encoding="utf-8", newline="\n")
            path.chmod(0o755)
        self.git("init", "--quiet")
        self.git("config", "user.email", "export-test@example.invalid")
        self.git("config", "user.name", "Export test")
        self.git("config", "core.autocrlf", "false")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "fixture")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def export(self, *args, **overrides):
        env = os.environ.copy()
        env.pop("GITHUB_REF", None)
        env.update(PROBE_IDENTITY=str(self.root / "identity.json"))
        env.update(overrides)
        return subprocess.run([os.environ.get("OPENRC_TEST_BASH", "bash"), "app/export.sh", *args],
                              cwd=self.root, env=env, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=30)

    def test_triggering_tag_wins_over_another_annotated_tag(self):
        self.git("tag", "-a", "v1.2.3-rc1", "-m", "annotated candidate")
        self.git("tag", "v1.2.3")
        self.assertEqual(self.git("describe", "--tags", "--always"), "v1.2.3-rc1")
        result = self.export(GITHUB_REF="refs/tags/v1.2.3")
        self.assertEqual(result.returncode, 1, result.stdout)  # fake import exits 23
        identity = json.loads((self.root / "identity.json").read_text())
        self.assertEqual(identity["DESCRIBE"], "v1.2.3")
        self.assertEqual(identity["COMMIT"], self.git("rev-parse", "HEAD"))
        self.assertEqual(identity["DIRTY"], "0")

    def test_prerelease_trigger_is_preserved(self):
        self.git("tag", "v1.2.3-rc.2")
        result = self.export(GITHUB_REF="refs/tags/v1.2.3-rc.2")
        self.assertEqual(result.returncode, 1, result.stdout)
        identity = json.loads((self.root / "identity.json").read_text())
        self.assertEqual(identity["DESCRIBE"], "v1.2.3-rc.2")

    def test_branch_exports_retain_git_describe_identity(self):
        self.git("tag", "v1.2.3-rc1")
        (self.app / "project.godot").write_text('config/version="1.2.3"\n# development\n', encoding="utf-8")
        result = self.export(GITHUB_REF="refs/heads/main")
        self.assertEqual(result.returncode, 1, result.stdout)
        identity = json.loads((self.root / "identity.json").read_text())
        self.assertEqual(identity["DESCRIBE"], self.git("describe", "--tags", "--always", "--dirty"))
        self.assertEqual(identity["DIRTY"], "1")

    def test_release_rejects_wrong_commit_dirty_tree_and_numeric_mismatch(self):
        self.git("tag", "v1.2.3")
        self.git("tag", "v9.8.7")
        result = self.export(GITHUB_REF="refs/tags/v9.8.7")
        self.assertIn("does not match project.godot", result.stdout)
        (self.app / "project.godot").write_text('config/version="1.2.3"\n# dirty\n', encoding="utf-8")
        result = self.export(GITHUB_REF="refs/tags/v1.2.3")
        self.assertIn("requires a clean working tree", result.stdout)
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "advance HEAD")
        result = self.export(GITHUB_REF="refs/tags/v1.2.3")
        self.assertIn("does not identify HEAD", result.stdout)
        self.assertFalse((self.root / "identity.json").exists())

    def test_malformed_release_tags_and_arguments_fail_before_engine_setup(self):
        for tag in ("vlatest", "v1.2.3garbage", "v1.2.3-", "v1.2.3-rc_2"):
            with self.subTest(tag=tag):
                self.git("tag", tag)
                result = self.export(GITHUB_REF="refs/tags/" + tag)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn("release tag must be", result.stdout)
        result = self.export("1.2.3")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("takes no version argument", result.stdout)
        self.assertFalse((self.root / "identity.json").exists())

    def test_zero_exit_import_error_stops_before_export(self):
        self.git("tag", "v1.2.3")
        result = self.export(PROBE_IMPORT_ERROR="1")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("engine error while importing", result.stdout)
        self.assertNotIn("== export Linux", result.stdout)


if __name__ == "__main__":
    unittest.main()
