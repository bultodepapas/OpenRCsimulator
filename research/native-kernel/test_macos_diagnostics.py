"""Portable policy tests for the disposable Apple sanitizer diagnostics."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("openrc_macos_diagnostic_tests", HERE / "macos_diagnostics.py")
diag = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(diag)


def thin_arm64(text=b"test executable code", identity=b"a" * 16):
    offset = 256
    size = offset + len(text)
    header = struct.pack("<IiiIIIII", 0xFEEDFACF, 0x0100000C, 0, 2, 2, 176, 0, 0)
    uuid_command = struct.pack("<II16s", 0x1B, 24, identity)
    segment = struct.pack("<II16sQQQQIIII", 0x19, 152, b"__TEXT", 0x100000000, size,
                          0, size, 7, 5, 1, 0)
    section = struct.pack("<16s16sQQIIIIIIII", b"__text", b"__TEXT", 0x100000000 + offset,
                          len(text), offset, 0, 0, 0, 0, 0, 0, 0)
    return (header + uuid_command + segment + section).ljust(offset, b"\0") + text


class DiagnosticPolicyTests(unittest.TestCase):
    def test_macho_text_identity_and_invalid_layouts(self):
        with tempfile.TemporaryDirectory() as temporary:
            host = Path(temporary) / "Godot"
            original = thin_arm64()
            host.write_bytes(original)
            identity = diag._arm64_text_identity(host)
            self.assertEqual(identity["architecture"], "arm64")
            self.assertEqual(identity["text_sha256"], hashlib.sha256(b"test executable code").hexdigest())
            host.write_bytes(original + b"different signature material")
            self.assertEqual(diag._arm64_text_identity(host), identity)
            host.write_bytes(thin_arm64(b"changed code"))
            self.assertNotEqual(diag._arm64_text_identity(host), identity)
            host.write_bytes(thin_arm64(identity=b"b" * 16))
            self.assertNotEqual(diag._arm64_text_identity(host), identity)
            for bad in (original[:31], original[:-1], b"bad!" + original[4:],
                        original[:4] + struct.pack("<I", 0x01000007) + original[8:]):
                host.write_bytes(bad)
                with self.subTest(size=len(bad)), self.assertRaises(ValueError):
                    diag._arm64_text_identity(host)

    def test_diagnostic_signature_requires_adhoc_without_hardened_runtime_and_records_entitlements(self):
        path = Path("/tmp/diagnostic-godot")
        xml = plistlib.dumps({"com.example.diagnostic": True})
        detail = "CodeDirectory v=20400 size=99 flags=0x2(adhoc) hashes=1+1\nSignature=adhoc\nTeamIdentifier=not set\n"

        def check(text, payload=xml):
            def run(command, **_kwargs):
                if "--entitlements" in command:
                    return SimpleNamespace(stdout=payload, stderr=b"Executable=/tmp/diagnostic-godot\n")
                return SimpleNamespace(stdout="", stderr=text)
            with patch.object(diag.subprocess, "run", side_effect=run):
                return diag._diagnostic_signature(path, {})

        result = check(detail)
        self.assertEqual(result["flags"], "0x2")
        self.assertEqual(result["entitlements_xml"], xml.decode())
        self.assertEqual(result["entitlements_sha256"], hashlib.sha256(xml).hexdigest())
        self.assertIn("--verify", result["verify_command"])
        self.assertEqual(check(detail, b"")["entitlements_xml"], "")
        for bad in (detail.replace("0x2(adhoc)", "0x10002(adhoc,runtime)"),
                    detail.replace("Signature=adhoc", "Signature size=123"),
                    detail.replace("TeamIdentifier=not set", "TeamIdentifier=ABCDEFGHIJ"),
                    detail + "Authority=Some Team\n"):
            with self.subTest(detail=bad), self.assertRaises(ValueError):
                check(bad)
        with self.assertRaises(ValueError):
            check(detail, b"not a plist")

    def test_clone_must_be_distinct_task_owned_same_arm64_code_and_uuid(self):
        with tempfile.TemporaryDirectory() as temporary:
            tmp = Path(temporary).resolve()
            original = tmp / "official"
            host = tmp / "clone"
            original.write_bytes(thin_arm64())
            host.write_bytes(thin_arm64() + b"replacement signature")

            def identity(path, _lock):
                return {"path": str(path), "version": "pinned", "architectures": ["arm64"],
                        "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

            mac = SimpleNamespace(godot_identity=identity)
            with patch.object(diag, "_diagnostic_signature", return_value={"flags": "0x2"}):
                result = diag._diagnostic_host(original, host, mac, {}, {}, tmp, ())
                self.assertEqual(result["engine"]["path"], str(host))
                self.assertEqual(result["official_code"], result["diagnostic_code"])
                with self.assertRaises(ValueError):
                    diag._diagnostic_host(original, original, mac, {}, {}, tmp, ())
                with self.assertRaises(ValueError):
                    diag._diagnostic_host(original, host, mac, {}, {}, tmp, (tmp,))
                host.write_bytes(thin_arm64(b"wrong code"))
                with self.assertRaisesRegex(ValueError, "UUID or text"):
                    diag._diagnostic_host(original, host, mac, {}, {}, tmp, ())
                host.write_bytes(thin_arm64(identity=b"b" * 16))
                with self.assertRaisesRegex(ValueError, "UUID or text"):
                    diag._diagnostic_host(original, host, mac, {}, {}, tmp, ())
                host.unlink()
                try:
                    os.link(original, host)
                except OSError:
                    pass
                else:
                    with self.assertRaises(ValueError):
                        diag._diagnostic_host(original, host, mac, {}, {}, tmp, ())

    def test_clone_controls_and_oracles_run_on_clone_but_build_stays_bound_to_official(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            here = root / "research/native-kernel"
            source = here / "src/nk_kernel.cpp"
            source.parent.mkdir(parents=True)
            source.write_text('#include <cstdint>\n\t\t__asm__ __volatile__("mrs %0, fpcr" : "=r"(fpcr) : : "memory");\n')
            for path in (here / "run.py", here / "build_macos.py", here / "fpcr_control_probe.py",
                         here / "macos_diagnostics.py", here / "stage_oracle.gd", root / "tools/godot/run_checked.py"):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("fixture")
            tmp = root / "tmp"
            work = tmp / "build/work/candidate"
            work.mkdir(parents=True)
            (work / "compile_commands.json").write_text(json.dumps([{"directory": str(work), "file": str(source)}]))
            old_obj = work / "old.o"
            old_obj.write_bytes(b"object")
            (tmp / "build/build-receipt.json").write_text("{}")
            project = tmp / "research/app"
            project.mkdir(parents=True)
            official = root / "official-godot"
            clone = tmp / "clone-godot"
            official.write_bytes(thin_arm64())
            clone.write_bytes(thin_arm64() + b"adhoc signature")

            def sha(path):
                return hashlib.sha256(Path(path).read_bytes()).hexdigest()

            def engine_identity(path, _lock):
                path = Path(path).resolve()
                return {"path": str(path), "version": "pinned", "sha256": sha(path), "architectures": ["arm64"]}

            engine = engine_identity(official, {})
            validate = Mock(return_value={"binary_sha256": "b" * 64, "link_command": ["link"]})
            mac = SimpleNamespace(locked=SimpleNamespace(load_lock=lambda: {}),
                host_toolchain=lambda: {"compiler": "cc", "c_compiler": "cc", "sdk_path": "sdk"},
                godot_identity=engine_identity, _identity=lambda: {"source": "identity"}, validate_build=validate,
                clean_build_environment=lambda *_: {}, architectures=lambda _: ["arm64"])
            runner = SimpleNamespace(validate_project=lambda _: {"prepared": True})

            def log_command(command, _cwd, _env, log, _timeout):
                Path(log).write_text("ubsan" if "nm" in command else "")
                if command[0] in ("compile", "link"):
                    Path(command[1]).write_bytes(command[0].encode())

            helper = SimpleNamespace(_sha=sha,
                _module=lambda name, _path: mac if name.endswith("builder") else runner if name.endswith("oracle") else object(),
                compile_command=lambda _row, _cc, _work, _source, _copy, obj, *_args: (["compile", str(obj)], old_obj),
                link_command=lambda _command, _cc, _work, _old, _obj, lib: (["link", str(lib)], []),
                _run_to_log=log_command)
            spec = SimpleNamespace(loader=SimpleNamespace(exec_module=lambda _: None))
            commands = []

            def checked(_runner, command, _out, label, _timeout, _required, _mode, _runtime):
                commands.append(command)
                if label == "sanitizer-control":
                    log = "OPENRC_MAC_SANITIZER_CONTROL mode=ubsan\nnk_kernel.cpp: runtime error: signed integer overflow"
                    return {"complete": True, "reason": "process_exit", "process_exit": 1}, log
                output = next(value.split("=", 1)[1] for value in command if value.startswith("--output="))
                Path(output).write_text("{}")
                return {}, ""

            args = SimpleNamespace(timeout=60, states=1, variant_states=1, script=["stage_oracle.gd"],
                tool_root=tmp / "build", project=project, out=tmp / "result", godot=official,
                diagnostic_godot=clone, mode="ubsan", seed=1)
            with patch.object(diag, "ROOT", root), patch.object(diag, "HERE", here), \
                    patch.object(diag.importlib.util, "spec_from_file_location", return_value=spec), \
                    patch.object(diag.importlib.util, "module_from_spec", return_value=helper), \
                    patch.object(diag, "_official_engine", return_value="official signature"), \
                    patch.object(diag, "_diagnostic_signature", return_value={"flags": "0x2"}), \
                    patch.object(diag, "_sign", return_value="adhoc"), patch.object(diag, "_checked", side_effect=checked), \
                    patch.object(diag, "oracle_error", return_value=""):
                summary = diag.run(args)
            self.assertEqual(summary["status"], "passed")
            self.assertFalse(summary["official_engine_parity"] or summary["installable"])
            self.assertTrue(summary["official_host_unchanged"] and summary["diagnostic_host_unchanged"])
            self.assertEqual([command[0] for command in commands], [str(clone), str(clone)])
            self.assertEqual(validate.call_args.args[4], engine)

    def test_compile_defines_match_instrumentation_for_candidate_and_control(self):
        for mode, expected, excluded in (
            ("ubsan", "-DUBSAN_ENABLED", "-DASAN_ENABLED"),
            ("asan", "-DASAN_ENABLED", "-DUBSAN_ENABLED"),
        ):
            with self.subTest(mode=mode):
                link = diag.sanitizer_flags(mode)
                candidate = diag.sanitizer_compile_flags(mode)
                control = diag.sanitizer_compile_flags(mode, control=True)
                self.assertTrue(set(link).issubset(candidate))
                self.assertTrue(set(candidate).issubset(control))
                self.assertEqual(candidate.count(expected), 1)
                self.assertEqual(control.count(expected), 1)
                self.assertNotIn(excluded, candidate)
                self.assertNotIn(excluded, control)
                self.assertNotIn("-DLSAN_ENABLED", candidate)
                self.assertNotIn("-DLSAN_ENABLED", control)
                self.assertFalse(any(flag.startswith("-D") for flag in link))
                self.assertNotIn("-DOPENRC_MAC_SANITIZER_CONTROL=1", candidate)
                self.assertIn("-DOPENRC_MAC_SANITIZER_CONTROL=1", control)
                self.assertEqual("-DOPENRC_MAC_SANITIZER_ASAN=1" in control, mode == "asan")
        with self.assertRaises(ValueError):
            diag.sanitizer_compile_flags("profile")

    def test_modes_and_controls_are_separate_from_candidate_source(self):
        original = (HERE / "src/nk_kernel.cpp").read_text(encoding="utf-8")
        for mode, flag, fault in (("ubsan", "-fsanitize=undefined", "INT_MAX"),
                                  ("asan", "-fsanitize=address", "values[index] = 42")):
            with self.subTest(mode=mode):
                self.assertIn(flag, diag.sanitizer_flags(mode))
                self.assertIn("-fno-sanitize-recover=all", diag.sanitizer_flags(mode))
                changed = diag.control_source(original, mode)
                self.assertIn("#if defined(OPENRC_MAC_SANITIZER_CONTROL)", changed)
                self.assertIn(f"{diag.CONTROL_MARKER} mode={mode}", changed)
                self.assertIn(fault, changed)
                self.assertNotIn(diag.CONTROL_MARKER, original)
        with self.assertRaises(ValueError):
            diag.control_source(original.replace("#include <cstdint>\n", ""), "ubsan")
        with self.assertRaises(ValueError):
            diag.sanitizer_flags("profile")

    def test_positive_control_needs_matching_origin_marker_diagnostic_and_exit(self):
        report = {"complete": True, "reason": "process_exit", "process_exit": 1}
        source, library = Path("/tmp/control/nk_kernel.cpp"), Path("/tmp/control/libopenrc_native_kernel.dylib")
        for mode, diagnostic in (("ubsan", f"{source}:27: runtime error: signed integer overflow"),
                                 ("asan", f"ERROR: AddressSanitizer: heap-buffer-overflow in {library}")):
            marker = f"{diag.CONTROL_MARKER} mode={mode}\n"
            log = marker + diagnostic
            self.assertTrue(diag.detected_control(mode, report, log, source, library))
            for bad in (diagnostic, marker + "unrelated error", diagnostic + "\n" + marker):
                self.assertFalse(diag.detected_control(mode, report, bad, source, library))
            for altered in (dict(report, complete=False), dict(report, process_exit=0), dict(report, reason="timeout")):
                self.assertFalse(diag.detected_control(mode, altered, log, source, library))

    def test_sanitizer_environment_is_local_and_restored(self):
        initial = {"DYLD_INSERT_LIBRARIES": "previous", "ASAN_OPTIONS": "old", "PATH": "safe"}
        with patch.dict(os.environ, initial, clear=True):
            with diag.sanitizer_environment("ubsan", None):
                self.assertNotIn("DYLD_INSERT_LIBRARIES", os.environ)
                self.assertIn("halt_on_error=1", os.environ["UBSAN_OPTIONS"])
            self.assertEqual(dict(os.environ), initial)
            with self.assertRaisesRegex(ValueError, "runtime"):
                with diag.sanitizer_environment("asan", None):
                    pass
            self.assertEqual(dict(os.environ), initial)
            with self.assertRaisesRegex(RuntimeError, "stop"):
                with diag.sanitizer_environment("asan", Path("/runtime.dylib")):
                    self.assertEqual(os.environ["DYLD_INSERT_LIBRARIES"], str(Path("/runtime.dylib")))
                    raise RuntimeError("stop")
            self.assertEqual(dict(os.environ), initial)

    def test_clean_oracle_needs_real_component_and_rejects_sanitizer_stderr(self):
        report = {"ok": True, "complete": True, "reason": "passed", "process_exit": 0,
                  "counts": {"error": 0}, "missing_required_text": []}
        result = {"format": "openrc-nk3-stage-oracle v1", "verdict": "pass", "failures": [],
                  "seed": 7, "states": 64, "self_test": {"passed": True}, "identity": {"backend": "native"},
                  "components": {"stage_bytes": {"count": 64, "identical": 64}},
                  "total": {"compared": 64, "identical": 64, "mismatched": 0},
                  "coverage": {"stage_air": {"states": 20}, "stage_ground": {"states": 25},
                               "stage_hull": {"states": 19}}}
        self.assertEqual(diag.oracle_error("stage_oracle.gd", result, report, "", 7, 64), "")
        self.assertTrue(diag.oracle_error("stage_oracle.gd", result, report, "runtime error: overflow", 7, 64))
        for changes in ({"components": {}}, {"identity": {"backend": "reference"}}, {"states": 1}):
            bad = copy.deepcopy(result)
            bad.update(changes)
            self.assertTrue(diag.oracle_error("stage_oracle.gd", bad, report, "", 7, 64))
        bad_report = dict(report, complete=False)
        self.assertTrue(diag.oracle_error("stage_oracle.gd", result, bad_report, "", 7, 64))


if __name__ == "__main__":
    unittest.main()
