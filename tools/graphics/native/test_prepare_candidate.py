"""Trial adapter updates must preserve unknown user edits before writing any files."""
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tools.graphics.native import prepare_candidate as candidate


class TrialSourceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-trial-source-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.target = self.root / "candidate"
        self.sources = {"app/native_trial/a.gd": self.root / "a.gd",
                        "app/native_trial/z.gd": self.root / "z.gd"}
        for path in self.sources.values():
            path.write_bytes(b"extends Node\n# new\n")
        patch = mock.patch.multiple(candidate, CANDIDATE=self.target, TRIAL_SOURCES=self.sources)
        patch.start()
        self.addCleanup(patch.stop)

    def test_recorded_version_upgrades_and_repeated_preparation_is_identical(self):
        old = b"extends Node\n# previous\n"
        previous = {"trial_sources": {}}
        for name in self.sources:
            path = self.target / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(old)
            previous["trial_sources"][name] = candidate.sha256(old)
        hashes = candidate.prepare_trial_sources(previous)
        self.assertEqual(hashes, candidate.prepare_trial_sources({"trial_sources": hashes}))
        for name, source in self.sources.items():
            self.assertEqual((self.target / name).read_bytes(), source.read_bytes())

    def test_unknown_later_edit_preserves_every_existing_source(self):
        previous = {"trial_sources": {}}
        before = {}
        for name in self.sources:
            path = self.target / name
            path.parent.mkdir(parents=True, exist_ok=True)
            before[name] = b"recorded" if name.endswith("a.gd") else b"user edit"
            path.write_bytes(before[name])
            previous["trial_sources"][name] = candidate.sha256(b"recorded")
        with self.assertRaisesRegex(RuntimeError, "unexpected edit"):
            candidate.prepare_trial_sources(previous)
        self.assertEqual(before, {name: (self.target / name).read_bytes() for name in self.sources})


if __name__ == "__main__":
    unittest.main()
