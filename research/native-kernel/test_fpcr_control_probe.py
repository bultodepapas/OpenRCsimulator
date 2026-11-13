"""Offline checks for the disposable macOS FPCR detector control."""
from __future__ import annotations

import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPEC = importlib.util.spec_from_file_location("openrc_fpcr_control_test", HERE / "fpcr_control_probe.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class ControlProbeTests(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / "tmp/fpcr-control-tests"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.work = self.root / "candidate"
        self.source = self.root / "src/nk_kernel.cpp"
        self.compiler = self.root / "bin/clang++"
        self.old_obj = self.work / "lib/obj/nk_kernel.o"
        self.archive = self.work / "dependencies/godot-cpp/bin/libgodot-cpp.a"
        for path in (self.source, self.compiler, self.old_obj, self.archive):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture", encoding="utf-8")
        self.out = self.root / "out"
        self.out.mkdir()

    def row(self):
        return {"directory": str(self.work), "file": str(self.source), "output": "lib/obj/nk_kernel.o",
                "arguments": [str(self.compiler), "-o", "lib/obj/nk_kernel.o", "-c", "-std=c++17",
                              "-Idependencies/godot-cpp/include", str(self.source)]}

    def command(self, row):
        return probe.compile_command(row, self.compiler, self.work, self.source, self.out / "copy.cpp",
                                     self.out / "control.o", self.source.parent)

    def test_mutation_is_guarded_and_restores_the_saved_register(self):
        source = (HERE / "src/nk_kernel.cpp").read_text(encoding="utf-8")
        changed = probe.mutated_source(source)
        self.assertEqual(source.count('"mrs %0, fpcr" : "=r"(fpcr)'), 1)
        self.assertEqual(changed.count("#if defined(OPENRC_FPCR_CONTROL_MUTANT)"), 1)
        self.assertIn("std::uint64_t(1) << 24", changed)
        self.assertIn('"msr fpcr, %0\\n\\tisb"', changed)
        self.assertIn('"r"(saved_fpcr)', changed)
        self.assertIn(probe.MARKER, changed)
        with self.assertRaises(ValueError):
            probe.mutated_source(source.replace("#include <cstdint>\n", ""))

    def test_only_copy_and_output_are_substituted(self):
        command, old = self.command(self.row())
        self.assertEqual(old, self.old_obj)
        self.assertIn(str(self.out / "copy.cpp"), command)
        self.assertIn(str(self.out / "control.o"), command)
        self.assertIn("-I" + str(self.source.parent), command)
        self.assertIn("-DOPENRC_FPCR_CONTROL_MUTANT=1", command)
        self.assertNotIn(str(self.source), command)
        for extra in (["-save-temps"], ["-o", "danger.o"], [str(self.source)]):
            row = self.row()
            row["arguments"].extend(extra)
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.command(row)

    def test_shared_compiler_helper_can_build_without_the_fpcr_mutant(self):
        command, _ = probe.compile_command(self.row(), self.compiler, self.work, self.source,
                                           self.out / "copy.cpp", self.out / "sanitized.o", self.source.parent,
                                           ("-fsanitize=undefined",))
        self.assertIn("-fsanitize=undefined", command)
        self.assertNotIn("-DOPENRC_FPCR_CONTROL_MUTANT=1", command)

    def test_link_replaces_object_and_output_and_rejects_extra_options(self):
        original = [str(self.compiler), "-o", "lib/libopenrc_native_kernel.dylib", "-arch", "arm64",
                    "-fvisibility=hidden", "-fno-lto", "-isysroot", "/sdk", "-mmacosx-version-min=11.0",
                    "-Wl,-install_name,@rpath/libopenrc_native_kernel.dylib", "-shared", "lib/obj/nk_kernel.o",
                    "dependencies/godot-cpp/bin/libgodot-cpp.a"]
        library = self.out / "libopenrc_native_kernel.dylib"
        command, archives = probe.link_command(original, self.compiler, self.work, self.old_obj,
                                               self.out / "control.o", library)
        self.assertEqual(archives, [self.archive])
        self.assertIn(str(library), command)
        self.assertIn(str(self.out / "control.o"), command)
        for bad in (original + ["-Wl,-map,/tmp/map"], original + ["@response"], original + ["-o", "/tmp/x"]):
            with self.subTest(bad=bad[-1]), self.assertRaises(ValueError):
                probe.link_command(bad, self.compiler, self.work, self.old_obj, self.out / "control.o", library)

    def test_requires_observed_fz_mutation_and_restoration(self):
        initial, changed = 0, probe.FZ
        row = lambda value: {"raw": f"0x{value:016x}", "control": f"0x{value & probe.MASK:08x}"}
        result = {"format": "openrc-nk3-oracle v1", "verdict": "fail", "failures": [probe.ERROR],
                  "macos_boundary": {"control_unchanged": False, "fpcr":
                                     {"before_transport": row(initial), "after_transport": row(changed)}},
                  "coverage": {"macos_fpcr": {"observations": 2, "changed": 1}}}
        checked = {"complete": True, "reason": "process_exit", "process_exit": 1,
                   "counts": {"error": 0}, "missing_required_text": []}
        log = (f"{probe.MARKER} initial={initial:016x} observed={changed:016x} restored={initial:016x}\n")
        self.assertEqual(probe.control_result(result, checked, log)["flipped_bit"], 24)
        changes = [
            (dict(result, verdict="pass"), checked, log),
            (dict(result, failures=[]), checked, log),
            (result, dict(checked, complete=False), log),
            (result, dict(checked, counts={"error": 1}), log),
            (result, checked, log.replace(f"restored={initial:016x}", f"restored={changed:016x}")),
            (result, checked, log.replace(f"observed={changed:016x}", f"observed={0:016x}")),
            (result, checked, ""),
        ]
        bad_snapshot = copy.deepcopy(result)
        bad_snapshot["macos_boundary"]["fpcr"]["after_transport"]["raw"] = "0x0000000000000000"
        changes.append((bad_snapshot, checked, log))
        for bad_result, bad_checked, bad_log in changes:
            with self.subTest(result=bad_result, checked=bad_checked, log=bad_log), self.assertRaises(ValueError):
                probe.control_result(bad_result, bad_checked, bad_log)


if __name__ == "__main__":
    unittest.main()
