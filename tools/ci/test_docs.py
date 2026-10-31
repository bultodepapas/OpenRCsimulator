"""Document-link checks against disposable Git objects and event receipts."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import check_docs
import policy


class DocumentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-ci-docs-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "user.name", "Fixture")
        self.git("config", "core.autocrlf", "false")
        self.base = self.commit({
            "AGENTS.md": "# Start\n[old debt](missing-inherited.md)\n",
            "docs/README.md": "# Hello, World!\n# Hello, World!\n## Café & `flight`\n<a id=\"custom\"></a>\n",
        })

    def git(self, *args):
        return policy.git(self.root, *args).strip()

    def commit(self, files):
        for name, contents in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents, encoding="utf-8")
        self.git("add", "-A")
        self.git("commit", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def event(self, sha):
        return {"before": self.base, "after": sha, "ref": "refs/heads/main", "deleted": False}

    def receipt(self, sha):
        return policy.selection(self.root, "push", "refs/heads/main", sha, self.event(sha))

    def check(self, sha, receipt=None, payload=None):
        return check_docs.check(self.root, receipt or self.receipt(sha), sha, "push", "refs/heads/main",
                                payload if payload is not None else self.event(sha))

    def test_inherited_broken_link_is_excluded_but_new_link_is_checked(self):
        sha = self.commit({"AGENTS.md": "# Start\n[old debt](missing-inherited.md)\nSome editing.\n"})
        self.assertEqual(self.check(sha), 0)
        sha = self.commit({"AGENTS.md": "# Start\n[old debt](missing-inherited.md)\n[bad](missing-new.md)\n"})
        with self.assertRaisesRegex(ValueError, "missing target missing-new.md"):
            self.check(sha)

    def test_added_duplicate_of_inherited_broken_link_is_checked(self):
        sha = self.commit({"AGENTS.md": "[old](missing-inherited.md)\n[another](missing-inherited.md)\n"})
        with self.assertRaisesRegex(ValueError, "missing target missing-inherited.md"):
            self.check(sha)

    def test_links_targets_and_anchors_with_multiple_markdown_forms(self):
        sha = self.commit({"AGENTS.md": """# Start
[old debt](missing-inherited.md)
[heading](docs/README.md#hello-world)
[duplicate](<docs/README.md#hello-world-1> "title")
[unicode][manual]
[same](#start)
[custom](docs/README.md#custom)
[space](docs/space%20%28test%29.md#find-it)
![image](docs/picture.png)
<a href="docs/README.md#hello-world">HTML</a>
[remote](https://example.invalid/elsewhere)

[manual]: docs/README.md#caf%C3%A9--flight
""", "docs/space (test).md": "# Find it\n", "docs/picture.png": "fixture"})
        self.assertEqual(self.check(sha), 8)

    def test_broken_anchor_and_missing_target_fail(self):
        for destination in ("docs/README.md#absent", "docs/absent.md", "docs/README.md#hello-world-2"):
            with self.subTest(destination=destination):
                sha = self.commit({"AGENTS.md": f"[new]({destination})\n"})
                with self.assertRaisesRegex(ValueError, "missing (anchor|target)"):
                    self.check(sha)

    def test_reference_definition_change_is_a_changed_link(self):
        self.base = self.commit({"AGENTS.md": "[Guide][help]\n\n[help]: docs/README.md#hello-world\n"})
        sha = self.commit({"AGENTS.md": "[Guide][help]\n\n[help]: docs/README.md#broken\n"})
        with self.assertRaisesRegex(ValueError, "missing anchor #broken"):
            self.check(sha)

    def test_reference_shortcut_and_collapsed_links(self):
        sha = self.commit({"AGENTS.md": "[Guide]\n[Guide][]\n\n[guide]: docs/README.md#hello-world\n"})
        self.assertEqual(self.check(sha), 2)

    def test_example_links_in_comments_and_code_are_ignored(self):
        sha = self.commit({"AGENTS.md": """# Start
<!-- [comment](missing.md) -->
`[inline](missing.md)`
````markdown
[fenced](missing.md)
```
[still-fenced](missing.md)
````
~~~
<a href="missing.md">code</a>
~~~
<pre>[html-code](missing.md)</pre>

    [indented-code](missing.md)

> ```
> [quoted-code](missing.md)
> ```

[good](docs/README.md#hello-world)
"""})
        self.assertEqual(self.check(sha), 1)

    def test_links_in_indented_list_continuations_are_checked(self):
        sha = self.commit({"AGENTS.md": "- List item\n    [bad](missing.md)\n"})
        with self.assertRaisesRegex(ValueError, "missing target missing.md"):
            self.check(sha)

    def test_removing_linked_heading_in_same_document_fails(self):
        self.base = self.commit({"AGENTS.md": "# Start\n[go](#old-heading)\n\n## Old heading\n"})
        sha = self.commit({"AGENTS.md": "# Start\n[go](#old-heading)\n\n## New heading\n"})
        with self.assertRaisesRegex(ValueError, "missing anchor #old-heading in AGENTS.md"):
            self.check(sha)

    def test_inbound_link_from_an_unchanged_audited_guide_is_checked(self):
        self.base = self.commit({"AGENTS.md": "[go](docs/README.md#hello-world)\n"})
        sha = self.commit({"docs/README.md": "# Renamed\n"})
        with self.assertRaisesRegex(ValueError, "missing anchor #hello-world in docs/README.md"):
            self.check(sha)

    def test_preexisting_broken_inbound_anchor_remains_excluded(self):
        self.base = self.commit({"AGENTS.md": "[old debt](docs/README.md#never-existed)\n"})
        sha = self.commit({"docs/README.md": "# Renamed\n"})
        self.assertEqual(self.check(sha), 0)

    def test_anchors_ignore_code_examples_and_allow_inline_heading_code(self):
        self.base = self.commit({"docs/README.md": "# `Flight` controls\n\n`<a id=\"fake\">`\n"})
        sha = self.commit({"AGENTS.md": "[ok](docs/README.md#flight-controls)\n"})
        self.assertEqual(self.check(sha), 1)
        sha = self.commit({"AGENTS.md": "[fake](docs/README.md#fake)\n"})
        with self.assertRaisesRegex(ValueError, "missing anchor #fake"):
            self.check(sha)

    def test_path_traversal_invalid_encoding_and_absolute_path_fail(self):
        for destination in ("../outside.md", "%2e%2e/outside.md", "/absolute.md", "docs/%ZZ.md"):
            with self.subTest(destination=destination):
                sha = self.commit({"AGENTS.md": f"[bad]({destination})\n"})
                with self.assertRaises(ValueError):
                    self.check(sha)

    def test_directory_readme_and_line_anchors(self):
        sha = self.commit({"AGENTS.md": "[dir](docs/#hello-world)\n[line](docs/README.md#L2-L3)\n"})
        self.assertEqual(self.check(sha), 2)
        sha = self.commit({"AGENTS.md": "[line](docs/README.md#L2-L999)\n"})
        with self.assertRaisesRegex(ValueError, "missing line anchor"):
            self.check(sha)

    def test_committed_objects_not_untracked_or_dirty_files_are_checked(self):
        sha = self.commit({"AGENTS.md": "[bad](untracked.md)\n"})
        (self.root / "untracked.md").write_text("untracked", encoding="utf-8")
        (self.root / "AGENTS.md").write_text("dirty edit hides link", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "missing target untracked.md"):
            self.check(sha)

        sha = self.commit({"AGENTS.md": "[good](docs/README.md#hello-world)\n"})
        (self.root / "docs/README.md").unlink()
        self.assertEqual(self.check(sha), 1)

    def test_forged_receipt_and_mismatched_event_fail_before_check(self):
        sha = self.commit({"AGENTS.md": "[bad](missing.md)\n"})
        receipt = self.receipt(sha)
        forged = copy.deepcopy(receipt)
        forged["paths"] = []
        with self.assertRaises(ValueError):
            self.check(sha, forged)
        with self.assertRaises(ValueError):
            self.check(sha, receipt, {**self.event(sha), "after": "f" * 40})

    def test_non_comparable_event_retains_full_scope(self):
        sha = self.commit({"AGENTS.md": "[bad](missing.md)\n"})
        receipt = policy.selection(self.root, "workflow_dispatch", "refs/heads/main", sha, {})
        self.assertTrue(all(receipt["recommended"].values()))
        self.assertEqual(check_docs.check(self.root, receipt, sha, "workflow_dispatch", "refs/heads/main", {}), 0)

    def test_unallowlisted_documents_do_not_imply_a_safe_scope(self):
        sha = self.commit({"docs/plans/other.md": "[bad](missing.md)\n"})
        self.assertTrue(all(self.receipt(sha)["recommended"].values()))
        self.assertEqual(self.check(sha), 0)

    def test_deleted_safe_document_forces_full_scope(self):
        self.git("rm", "AGENTS.md")
        self.git("commit", "-qm", "delete")
        sha = self.git("rev-parse", "HEAD")
        self.assertTrue(all(self.receipt(sha)["recommended"].values()))
        self.assertEqual(self.check(sha), 0)

    def test_cli_revalidates_receipt_event_and_git(self):
        sha = self.commit({"AGENTS.md": "[good](docs/README.md#hello-world)\n"})
        receipt_path = self.root / "selection.json"
        event_path = self.root / "event.json"
        receipt = self.receipt(sha)
        receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
        event_path.write_text(json.dumps(self.event(sha)), encoding="utf-8")
        env = {**os.environ, "GITHUB_SHA": sha, "GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/heads/main",
               "GITHUB_EVENT_PATH": str(event_path)}
        cmd = [sys.executable, str(Path(check_docs.__file__).resolve()), "--root", str(self.root),
               "--receipt", str(receipt_path)]
        valid = subprocess.run(cmd, env=env, text=True, capture_output=True)
        self.assertEqual(valid.returncode, 0, valid.stderr)
        self.assertIn("Checked 1", valid.stdout)
        receipt["paths"] = []
        receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
        invalid = subprocess.run(cmd, env=env, text=True, capture_output=True)
        self.assertNotEqual(invalid.returncode, 0)
        self.assertIn("refused", invalid.stderr)


if __name__ == "__main__":
    unittest.main()
