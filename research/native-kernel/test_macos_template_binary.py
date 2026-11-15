"""Portable controls for executable binding; system codesign is simulated."""
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("template_binding", HERE / "macos_engine_pair.py")
pair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pair)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class TemplateExecutableBinding(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="template-binding-test-", dir=HERE.parents[1])
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.template = self.root / "template-original"
        self.executable = self.root / "export-original"
        self.template.write_bytes(b"original macho payload\nTEMPLATE_SIG")
        self.executable.write_bytes(b"original macho payload\nEXPORT_SIG")
        self.original = {path: path.read_bytes() for path in (self.template, self.executable)}
        self.expected = digest(self.template)
        self.calls = []
        original_temp = tempfile.TemporaryDirectory
        def owned_temp(*args, **kwargs):
            kwargs["dir"] = self.root
            return original_temp(*args, **kwargs)
        self.temp_patch = mock.patch.object(pair.tempfile, "TemporaryDirectory", side_effect=owned_temp)
        self.temp_patch.start()
        self.addCleanup(self.temp_patch.stop)

    def fake_codesign(self, arguments):
        self.calls.append(list(arguments))
        path = Path(arguments[-1])
        self.assertNotIn(path, self.original)
        data = path.read_bytes()
        if arguments[0] == "--remove-signature":
            if data.endswith(b"\nTEMPLATE_SIG"):
                path.write_bytes(data.removesuffix(b"\nTEMPLATE_SIG"))
            elif data.endswith(b"\nEXPORT_SIG"):
                path.write_bytes(data.removesuffix(b"\nEXPORT_SIG"))
            else:
                raise ValueError("unsigned synthetic input")
        elif arguments[0] == "--force":
            self.assertEqual(arguments[1:-1], ["--sign", "-", "--timestamp=none", "--identifier", pair.NORMALIZATION_IDENTIFIER])
            path.write_bytes(data + b"\nFIXED_ADHOC_SIGNATURE")
        elif arguments[0] == "--verify":
            self.assertEqual(arguments[1:-1], ["--strict"])
            if not data.endswith(b"\nFIXED_ADHOC_SIGNATURE"):
                raise ValueError("signature missing")
        else:
            raise AssertionError(arguments)

    def verify(self):
        return pair.verify_export_executable(self.template, self.executable, self.expected)

    def assert_clean_and_originals(self):
        self.assertEqual(set(self.root.iterdir()), set(self.original))
        for path, content in self.original.items():
            self.assertEqual(path.read_bytes(), content)

    def test_signature_variants_normalize_and_repeated_proof_is_stable(self):
        with mock.patch.object(pair, "_codesign", side_effect=self.fake_codesign):
            first = self.verify()
            second = self.verify()
        self.assertEqual(first, second)
        self.assertNotEqual(first["template_sha256"], first["executable_sha256"])
        self.assertEqual(first["normalized_sha256"], hashlib.sha256(b"original macho payload\nFIXED_ADHOC_SIGNATURE").hexdigest())
        self.assertEqual([call[0] for call in self.calls], ["--remove-signature", "--force", "--verify"] * 4)
        self.assert_clean_and_originals()

    def test_changed_executable_code_is_rejected_and_copies_cleaned(self):
        # Preserve size: rejection must depend on content, not just length.
        self.executable.write_bytes(b"Original macho payload\nEXPORT_SIG")
        self.original[self.executable] = self.executable.read_bytes()
        with mock.patch.object(pair, "_codesign", side_effect=self.fake_codesign):
            with self.assertRaisesRegex(ValueError, "differs from the selected release template"):
                self.verify()
        self.assert_clean_and_originals()

    def test_wrong_template_pin_refuses_before_any_tool_call(self):
        self.expected = "0" * 64
        with mock.patch.object(pair, "_codesign") as codesign:
            with self.assertRaisesRegex(ValueError, "independently verified pair"):
                self.verify()
            codesign.assert_not_called()
        self.assert_clean_and_originals()

    def test_original_change_during_normalization_is_refused(self):
        def change_once(arguments):
            self.fake_codesign(arguments)
            if len(self.calls) == 1:
                self.executable.write_bytes(b"mutated during verification")
        with mock.patch.object(pair, "_codesign", side_effect=change_once):
            with self.assertRaisesRegex(ValueError, "Original executable changed"):
                self.verify()
        self.assertEqual(set(self.root.iterdir()), set(self.original))
        self.assertEqual(self.template.read_bytes(), self.original[self.template])

    def test_signing_failure_cleans_copies_and_preserves_originals(self):
        with mock.patch.object(pair, "_codesign", side_effect=ValueError("refused")):
            with self.assertRaisesRegex(ValueError, "refused"):
                self.verify()
        self.assert_clean_and_originals()

    def test_missing_signature_is_not_treated_as_success(self):
        self.executable.write_bytes(b"original macho payload")
        self.original[self.executable] = self.executable.read_bytes()
        with mock.patch.object(pair, "_codesign", side_effect=self.fake_codesign):
            with self.assertRaisesRegex(ValueError, "unsigned synthetic input"):
                self.verify()
        self.assert_clean_and_originals()

    def test_snapshot_rejects_oversized_input_before_copy(self):
        with mock.patch.object(pair, "MAX_BINARY", 4), mock.patch.object(pair, "_codesign") as codesign:
            with self.assertRaisesRegex(ValueError, "size bound"):
                self.verify()
            codesign.assert_not_called()
        self.assert_clean_and_originals()

    def test_system_tool_call_is_explicit_and_rejects_failure(self):
        with mock.patch.dict(os.environ, {"DYLD_LIBRARY_PATH": "unsafe", "CODESIGN_ALLOCATE": "unsafe"}):
            with mock.patch.object(pair.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout=b"")) as run:
                pair._codesign(["--verify", "--strict", "fixture"])
                self.assertEqual(run.call_args.args[0], ["/usr/bin/codesign", "--verify", "--strict", "fixture"])
                self.assertNotIn("DYLD_LIBRARY_PATH", run.call_args.kwargs["env"])
                self.assertNotIn("CODESIGN_ALLOCATE", run.call_args.kwargs["env"])
            with mock.patch.object(pair.subprocess, "run", return_value=SimpleNamespace(returncode=1, stdout=b"no signature")):
                with self.assertRaisesRegex(ValueError, "no signature"):
                    pair._codesign(["--remove-signature", "fixture"])


if __name__ == "__main__":
    unittest.main()
