"""Offline regression checks for the native engine's overlapping patch stack."""
from __future__ import annotations

import difflib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock
import zipfile


SPEC = importlib.util.spec_from_file_location("native_build_under_test", Path(__file__).with_name("build.py"))
assert SPEC is not None and SPEC.loader is not None
native_build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(native_build)


@unittest.skipUnless(shutil.which("git"), "Git is required for the native patch helper")
class EnginePatchTests(unittest.TestCase):
    COMMIT = "fixture-commit"
    BASE = {"src/a.txt": b"before\noriginal\nafter\n", "src/z.txt": b"before\noriginal-z\nafter\n"}
    PREFIX = {"src/a.txt": b"before\nfirst\nafter\n", "src/z.txt": b"before\nfirst-z\nafter\n"}
    FINAL = {"src/a.txt": b"before\nsecond\nafter\n", "src/z.txt": PREFIX["src/z.txt"]}

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="native-patch-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        # A containing repository must not make git apply target its worktree root.
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True, capture_output=True)
        self.patches = self.root / "patches"
        self.patches.mkdir()
        self.engine = self.root / "cache" / "engine"
        self.engine.mkdir(parents=True)
        self.archive = self.root / "source.zip"
        self.write_archive(self.BASE)
        self.write_engine(self.BASE)
        (self.engine / "unrelated.bin").write_bytes(b"\x00\xffpreserve\r\n")
        self.write_patch("first.patch", self.BASE, self.PREFIX)
        self.write_patch("second.patch", self.PREFIX, self.FINAL)
        self.globals = mock.patch.multiple(
            native_build, HERE=self.patches, ENGINE_PATCHES=("first.patch", "second.patch"), COMMIT=self.COMMIT
        )
        self.globals.start()
        self.addCleanup(self.globals.stop)

    def write_archive(self, files: dict[str, bytes]) -> None:
        with zipfile.ZipFile(self.archive, "w") as package:
            for name, content in files.items():
                package.writestr(f"godot-{self.COMMIT}/{name}", content)

    def write_engine(self, files: dict[str, bytes]) -> None:
        for name, content in files.items():
            target = self.engine / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)

    def write_patch(self, name: str, before: dict[str, bytes], after: dict[str, bytes]) -> None:
        patch = "".join(
            "".join(difflib.unified_diff(before[path].decode().splitlines(keepends=True),
                                        after[path].decode().splitlines(keepends=True),
                                        fromfile=f"a/{path}", tofile=f"b/{path}"))
            for path in sorted(before) if before[path] != after[path]
        )
        (self.patches / name).write_bytes(patch.encode())

    def snapshot(self) -> dict[str, bytes]:
        return {path.relative_to(self.engine).as_posix(): path.read_bytes()
                for path in self.engine.rglob("*") if path.is_file()}

    def assert_final(self) -> None:
        for name, content in self.FINAL.items():
            self.assertEqual((self.engine / name).read_bytes(), content, name)
        self.assertEqual((self.engine / "unrelated.bin").read_bytes(), b"\x00\xffpreserve\r\n")

    def test_pristine_applies_sequential_overlapping_patches(self) -> None:
        native_build.apply_engine_patches(self.engine, self.archive)
        self.assert_final()

    def test_complete_stack_can_be_repeated_without_rewriting(self) -> None:
        self.write_engine(self.FINAL)
        before = self.snapshot()
        original_write = Path.write_bytes

        def write_staged(path: Path, content: bytes) -> int:
            self.assertFalse(path.is_relative_to(self.engine), f"unexpected live rewrite: {path}")
            return original_write(path, content)

        with mock.patch.object(Path, "write_bytes", write_staged):
            native_build.apply_engine_patches(self.engine, self.archive)
        self.assertEqual(self.snapshot(), before)

    def test_previous_stack_is_upgraded(self) -> None:
        self.write_engine(self.PREFIX)
        native_build.apply_engine_patches(self.engine, self.archive)
        self.assert_final()

    def test_unknown_edit_rejects_before_any_live_file_is_overwritten(self) -> None:
        # a.txt sorts first and needs an upgrade; z.txt must be checked before that write.
        (self.engine / "src/z.txt").write_bytes(b"unknown local work\r\n")
        before = self.snapshot()
        with self.assertRaisesRegex(RuntimeError, "unknown edits: src/z.txt"):
            native_build.apply_engine_patches(self.engine, self.archive)
        self.assertEqual(self.snapshot(), before)

    def test_windows_crlf_archive_patches_and_live_sources_are_normalized(self) -> None:
        crlf = {name: content.replace(b"\n", b"\r\n") for name, content in self.BASE.items()}
        self.write_archive(crlf)
        self.write_engine(crlf)
        for patch in self.patches.iterdir():
            patch.write_bytes(patch.read_bytes().replace(b"\n", b"\r\n"))
        native_build.apply_engine_patches(self.engine, self.archive)
        self.assert_final()

    def test_later_patch_failure_leaves_live_engine_untouched(self) -> None:
        (self.patches / "second.patch").write_bytes(
            b"--- a/src/a.txt\n+++ b/src/a.txt\n@@ -1,3 +1,3 @@\n before\n-does-not-exist\n+second\n after\n"
        )
        before = self.snapshot()
        with self.assertRaisesRegex(RuntimeError, "Cannot apply second.patch"):
            native_build.apply_engine_patches(self.engine, self.archive)
        self.assertEqual(self.snapshot(), before)

    def test_git_apply_does_not_use_containing_repository(self) -> None:
        outer_file = self.root / "src/a.txt"
        outer_file.parent.mkdir()
        outer_file.write_bytes(b"outer repository work\n")
        native_build.apply_engine_patches(self.engine, self.archive)
        self.assert_final()
        self.assertEqual(outer_file.read_bytes(), b"outer repository work\n")


class DLSSHistoryResetTests(unittest.TestCase):
    def test_per_context_success_acknowledges_captured_generation(self) -> None:
        compiler = shutil.which("g++") or shutil.which("clang++")
        if not compiler:
            self.skipTest("A C++ compiler is required for the DLSS history state test")

        # Compile the actual state helper added by the engine patch. The surrounding
        # integration is exercised separately by the rendered repro fixture.
        patch = Path(__file__).with_name("dlss_history_reset.patch").read_text(encoding="utf-8")
        added = "\n".join(line[1:] for line in patch.splitlines() if line.startswith("+") and not line.startswith("+++"))
        begin, end = "// BEGIN DLSS HISTORY RESET STATE", "// END DLSS HISTORY RESET STATE"
        self.assertEqual(added.count(begin), 1)
        self.assertEqual(added.count(end), 1)
        state = added[added.index(begin):added.index(end) + len(end)]
        program = """#include <cassert>
#include <cstdint>
""" + state + """
int main() {
    DLSSHistoryResetState a, b;
    // No evaluation occurs during warmup or a rejected/failed callback.
    assert(a.should_reset(2));
    assert(a.should_reset(2));
    assert(b.should_reset(1));
    // The first successful callback coalesces requests for A only.
    a.evaluated(2);
    assert(!a.should_reset(2));
    assert(b.should_reset(1));
    b.evaluated(1);
    assert(!b.should_reset(1));
    // A queued frame carries generation 2; a newer request is generation 3.
    assert(!a.should_reset(2));
    assert(a.should_reset(3));
    a.evaluated(2);
    assert(a.should_reset(3));
    assert(!b.should_reset(1));
    a.evaluated(3);
    assert(!a.should_reset(3));
    // A stale completion cannot roll back a newer success.
    a.evaluated(2);
    assert(!a.should_reset(3));
    // A replacement context must reset on its own first evaluation.
    DLSSHistoryResetState recreated;
    assert(recreated.should_reset(3));
    recreated.evaluated(3);
    assert(!recreated.should_reset(3));
}
"""
        with tempfile.TemporaryDirectory(prefix="dlss-history-state-test-") as temporary:
            source = Path(temporary) / "state.cpp"
            binary = Path(temporary) / ("state.exe" if os.name == "nt" else "state")
            source.write_text(program, encoding="utf-8")
            subprocess.run([compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", str(source), "-o", str(binary)],
                           check=True, capture_output=True)
            subprocess.run([str(binary)], check=True, capture_output=True)


if __name__ == "__main__":
    unittest.main()
