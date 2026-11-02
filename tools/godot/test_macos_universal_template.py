"""Template unit checks and opt-in beta1/beta2 cross-export controls (no macOS execution)."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("macos_universal_template", HERE / "macos_universal_template.py")
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)


def preset(template: str | None, architecture: str = "universal") -> str:
    custom_templates = (f'custom_template/release={json.dumps(template)}\n'
                        f'custom_template/debug={json.dumps(template)}\n') if template else ""
    return ('[preset.0]\nname="macOS"\nplatform="macOS"\nrunnable=false\n'
            'export_filter="all_resources"\ninclude_filter=""\nexclude_filter=""\nscript_export_mode=2\n[preset.0.options]\n'
            f'binary_format/architecture="{architecture}"\n'
            f'{custom_templates}'
            'application/bundle_identifier="io.openrc.gdu08fixture"\ncodesign/codesign=1\nnotarization/notarization=0\n')


def macho_uuids(data: bytes) -> dict[str, str]:
    """Read LC_UUID identities, excluding export-time changes to code signatures."""
    architectures = {0x01000007: "x86_64", 0x0100000C: "arm64"}
    if struct.unpack_from(">I", data)[0] == 0xCAFEBABE:
        count = struct.unpack_from(">I", data, 4)[0]
        result = {}
        for index in range(count):
            _, _, offset, size, _ = struct.unpack_from(">IIIII", data, 8 + index * 20)
            result.update(macho_uuids(data[offset:offset + size]))
        return result
    magic, cpu = struct.unpack_from("<II", data)
    if magic != 0xFEEDFACF or cpu not in architectures:
        raise ValueError("unknown Mach-O architecture")
    offset = 32
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("malformed Mach-O command")
        if command == 0x1B:
            return {architectures[cpu]: data[offset + 8:offset + 24].hex()}
        offset += size
    raise ValueError("Mach-O has no LC_UUID")


class TemplateUnitTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="macos-template-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "official.zip"
        self.output = self.root / "project/.godot/template.zip"
        with zipfile.ZipFile(self.source, "w") as package:
            package.comment = b"preserve archive comment"
            for name in (*HELPER.SWAPS, "macos_template.app/Contents/Info.plist"):
                entry = zipfile.ZipInfo(name, (2026, 10, 15, 1, 2, 4))
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = (0o100755 if name in HELPER.SWAPS else 0o100644) << 16
                entry.comment = b"entry comment"
                entry.create_system = 3
                package.writestr(entry, name.encode())
        self.pin = mock.patch.object(HELPER, "MACOS_ZIP_SHA512", HELPER.digest(self.source, "sha512"))
        self.pin.start()
        self.addCleanup(self.pin.stop)

    def test_only_binary_payloads_swap_and_entry_metadata_stays(self):
        before = self.source.read_bytes()
        receipt = HELPER.prepare_template(self.source, self.output)
        self.assertEqual(self.source.read_bytes(), before)
        self.assertEqual(receipt["output_sha256"], HELPER.digest(self.output))
        with zipfile.ZipFile(self.source) as original, zipfile.ZipFile(self.output) as result:
            self.assertEqual(result.namelist(), original.namelist())
            self.assertEqual(result.comment, original.comment)
            for left, right in zip(original.infolist(), result.infolist()):
                for key in ("filename", "date_time", "compress_type", "external_attr", "internal_attr", "create_system", "comment", "extra"):
                    self.assertEqual(getattr(left, key), getattr(right, key), key)
                expected = HELPER.SWAPS.get(left.filename, left.filename)
                self.assertEqual(result.read(right), original.read(expected))

    def test_cached_repeat_does_not_rewrite_files(self):
        receipt = HELPER.prepare_template(self.source, self.output)
        with mock.patch.object(Path, "write_text", side_effect=AssertionError("cache receipt rewritten")), \
                mock.patch.object(zipfile, "ZipFile", side_effect=AssertionError("cache archive rebuilt")):
            self.assertEqual(HELPER.prepare_template(self.source, self.output), receipt)

    def test_unknown_official_source_is_rejected_without_output(self):
        self.source.write_bytes(b"unknown source")
        with self.assertRaisesRegex(RuntimeError, "does not match the pinned"):
            HELPER.prepare_template(self.source, self.output)
        self.assertFalse(self.output.parent.exists())

    def test_corrupt_cached_template_is_preserved_and_rejected(self):
        HELPER.prepare_template(self.source, self.output)
        self.output.write_bytes(b"unexpected local work")
        with self.assertRaisesRegex(RuntimeError, "differs from its receipt"):
            HELPER.prepare_template(self.source, self.output)
        self.assertEqual(self.output.read_bytes(), b"unexpected local work")

    def test_unreceipted_output_is_preserved_and_rejected(self):
        self.output.parent.mkdir(parents=True)
        self.output.write_bytes(b"unexpected local work")
        with self.assertRaisesRegex(RuntimeError, "unreceipted"):
            HELPER.prepare_template(self.source, self.output)
        self.assertEqual(self.output.read_bytes(), b"unexpected local work")

    def test_official_source_cannot_be_output(self):
        with self.assertRaisesRegex(RuntimeError, "never be overwritten"):
            HELPER.prepare_template(self.source, self.source)

    def test_project_preset_rejects_single_architecture(self):
        (self.root / "export_presets.cfg").write_text(preset(HELPER.RESOURCE_OUTPUT, "arm64"))
        with self.assertRaisesRegex(RuntimeError, "only valid for universal"):
            HELPER.validate_project(self.root)

    def test_project_preset_requires_local_template_for_both_modes(self):
        (self.root / "export_presets.cfg").write_text(preset(HELPER.RESOURCE_OUTPUT))
        HELPER.validate_project(self.root)
        (self.root / "export_presets.cfg").write_text(preset("res://some-other-template.zip"))
        with self.assertRaisesRegex(RuntimeError, "does not select the project-local"):
            HELPER.validate_project(self.root)


@unittest.skipUnless(os.environ.get("OPENRC_MACOS_EXPORT_GODOT"), "set OPENRC_MACOS_EXPORT_GODOT for real beta1 exports")
class NativeMacOSExportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = Path(os.environ["OPENRC_MACOS_EXPORT_GODOT"]).resolve()
        version = subprocess.check_output([str(cls.engine), "--version"], text=True).strip()
        if version != "4.8.beta1.official.4d10419ca":
            raise RuntimeError("these before/after controls require the exact official beta1 editor")
        cls.source = Path(os.environ["OPENRC_MACOS_TEMPLATE_SOURCE"]).resolve()
        cls.root = Path(os.environ["OPENRC_MACOS_TEST_OUT"]).resolve()
        if cls.root.exists():
            raise RuntimeError("real-export evidence output must be new")
        cls.root.mkdir(parents=True)
        cls.original_hash = HELPER.digest(cls.source, "sha512")
        cls.expected = {}
        with zipfile.ZipFile(cls.source) as original:
            for mode in ("release", "debug"):
                cls.expected[mode] = {}
                for arch in ("arm64", "x86_64"):
                    cls.expected[mode].update(macho_uuids(original.read(HELPER.PREFIX + mode + "." + arch)))
        cls.results = {"engine": version, "engine_sha256": HELPER.digest(cls.engine),
                       "source_zip_sha512": cls.original_hash, "expected_uuids": cls.expected, "exports": {}}
        cls.saved_environment = {key: os.environ.get(key) for key in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP")}
        for key, directory in (("APPDATA", "profile"), ("LOCALAPPDATA", "local-profile"), ("TEMP", "temp"), ("TMP", "temp")):
            path = cls.root / directory
            path.mkdir(exist_ok=True)
            os.environ[key] = str(path)
        sys.path.insert(0, str(HERE))
        from run_checked import run_checked
        cls.run_checked = staticmethod(run_checked)
        for variant, template in (("official", cls.source.as_posix()), ("fixed", HELPER.RESOURCE_OUTPUT)):
            project = cls.root / variant
            project.mkdir()
            (project / "project.godot").write_text(
                'config_version=5\n[application]\nconfig/name="GDU08 macOS Fixture"\nrun/main_scene="res://main.tscn"\n'
                '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
            (project / "main.tscn").write_text('[gd_scene format=3]\n[node name="Main" type="Node"]\n')
            (project / "export_presets.cfg").write_text(preset(template))
            if variant == "fixed":
                HELPER.validate_project(project)
                receipt = HELPER.prepare_template(cls.source, project / HELPER.RELATIVE_OUTPUT)
                cls.results["corrected_template"] = receipt
            checked = cls.run_checked([str(cls.engine), "--headless", "--path", str(project), "--import"],
                                      cls.root / "checks", timeout=180, label=variant + "-import")
            if not checked["ok"]:
                raise RuntimeError(str(checked["report"]))

    @classmethod
    def tearDownClass(cls):
        cls.results["official_source_unchanged"] = HELPER.digest(cls.source, "sha512") == cls.original_hash
        (cls.root / "verification.json").write_text(json.dumps(cls.results, indent=2) + "\n")
        for key, value in cls.saved_environment.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def export(self, variant: str, mode: str):
        target = self.root / (variant + "-" + mode + ".zip")
        checked = self.run_checked([str(self.engine), "--headless", "--path", str(self.root / variant),
                                   "--export-" + mode, "macOS", str(target)],
                                  self.root / "checks", timeout=180, label=variant + "-" + mode)
        self.assertTrue(checked["ok"], checked["report"])
        with zipfile.ZipFile(target) as package:
            executable = [name for name in package.namelist() if "/Contents/MacOS/" in name and not name.endswith("/")]
            self.assertEqual(len(executable), 1)
            actual = macho_uuids(package.read(executable[0]))
        signature = subprocess.run([sys.executable, str(HERE.parents[1] / "app/tests/check_macos_export.py"), str(target)],
                                   text=True, capture_output=True)
        self.assertEqual(signature.returncode, 0, signature.stdout + signature.stderr)
        self.results["exports"][variant + "-" + mode] = {"uuids": actual, "sha256": HELPER.digest(target),
            "signature_check": signature.stdout.strip(), "checked_report": str(checked["report"])}
        return actual

    def test_official_release_reproduces_inverted_payload(self):
        self.assertEqual(self.export("official", "release"), self.expected["debug"])

    def test_official_debug_reproduces_inverted_payload(self):
        self.assertEqual(self.export("official", "debug"), self.expected["release"])

    def test_fixed_release_uses_official_release_payloads(self):
        self.assertEqual(self.export("fixed", "release"), self.expected["release"])

    def test_fixed_debug_uses_official_debug_payloads(self):
        self.assertEqual(self.export("fixed", "debug"), self.expected["debug"])


@unittest.skipUnless(os.environ.get("OPENRC_MACOS_BETA2_EXPORT_GODOT"), "set OPENRC_MACOS_BETA2_EXPORT_GODOT for real beta2 exports")
class Beta2MacOSExportTests(unittest.TestCase):
    """Verify beta2's unmodified default templates; no macOS execution is claimed."""

    @classmethod
    def setUpClass(cls):
        cls.engine = Path(os.environ["OPENRC_MACOS_BETA2_EXPORT_GODOT"]).resolve()
        version = subprocess.check_output([str(cls.engine), "--version"], text=True).strip()
        if version != "4.8.beta2.official.cafc17a19":
            raise RuntimeError("these controls require the exact official beta2 editor")
        cls.source = Path(os.environ["OPENRC_MACOS_BETA2_TEMPLATE_SOURCE"]).resolve()
        cls.source_hash = HELPER.digest(cls.source, "sha512")
        if cls.source_hash != "a307324eec2db7db8eef26be10c7c4b91c923c8f91fe9144aee4c5812cd17f4e65e7b03e33021d29f8ff9384fc51a8a9b2d3ea81c461b966dc795edad42a09c7":
            raise RuntimeError("beta2 macOS template does not match the official archive member")
        cls.root = Path(os.environ["OPENRC_MACOS_BETA2_TEST_OUT"]).resolve()
        if cls.root.exists():
            raise RuntimeError("real-export evidence output must be new")
        cls.root.mkdir(parents=True)
        cls.expected = {}
        with zipfile.ZipFile(cls.source) as original:
            for mode in ("release", "debug"):
                cls.expected[mode] = {}
                for arch in ("arm64", "x86_64"):
                    cls.expected[mode].update(macho_uuids(original.read(HELPER.PREFIX + mode + "." + arch)))
        cls.results = {"engine": version, "engine_sha256": HELPER.digest(cls.engine),
                       "source_zip_sha512": cls.source_hash, "expected_uuids": cls.expected, "exports": {}}
        cls.saved_environment = {key: os.environ.get(key) for key in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "XDG_DATA_HOME")}
        def restore_environment():
            for key, value in cls.saved_environment.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        cls.addClassCleanup(restore_environment)
        for key, directory in (("APPDATA", "profile"), ("LOCALAPPDATA", "local-profile"),
                               ("TEMP", "temp"), ("TMP", "temp"), ("XDG_DATA_HOME", "profile")):
            path = cls.root / directory
            path.mkdir(exist_ok=True)
            os.environ[key] = str(path)
        if sys.platform == "win32":
            data_root = cls.root / "profile/Godot"
        elif sys.platform == "darwin":
            raise RuntimeError("run this cross-export control on Windows or Linux")
        else:
            data_root = cls.root / "profile/godot"
        template_dir = data_root / "export_templates/4.8.beta2"
        template_dir.mkdir(parents=True)
        shutil.copyfile(cls.source, template_dir / "macos.zip")
        cls.project = cls.root / "project"
        cls.project.mkdir()
        (cls.project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="GDU beta2 macOS Fixture"\nrun/main_scene="res://main.tscn"\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        (cls.project / "main.tscn").write_text('[gd_scene format=3]\n[node name="Main" type="Node"]\n')
        (cls.project / "export_presets.cfg").write_text(preset(None))
        sys.path.insert(0, str(HERE))
        from run_checked import run_checked
        cls.run_checked = staticmethod(run_checked)
        checked = cls.run_checked([str(cls.engine), "--headless", "--audio-driver", "Dummy",
                                   "--path", str(cls.project), "--import"],
                                  cls.root / "checks", timeout=180, label="beta2-import")
        if not checked["ok"]:
            raise RuntimeError(str(checked["report"]))

    @classmethod
    def tearDownClass(cls):
        cls.results["official_source_unchanged"] = HELPER.digest(cls.source, "sha512") == cls.source_hash
        (cls.root / "verification.json").write_text(json.dumps(cls.results, indent=2) + "\n")

    def export(self, mode: str):
        target = self.root / (mode + ".zip")
        checked = self.run_checked([str(self.engine), "--headless", "--audio-driver", "Dummy", "--path", str(self.project),
                                   "--export-" + mode, "macOS", str(target)],
                                  self.root / "checks", timeout=180, label="beta2-" + mode)
        self.assertTrue(checked["ok"], checked["report"])
        with zipfile.ZipFile(target) as package:
            executable = [name for name in package.namelist() if "/Contents/MacOS/" in name and not name.endswith("/")]
            self.assertEqual(len(executable), 1)
            actual = macho_uuids(package.read(executable[0]))
        signature = subprocess.run([sys.executable, str(HERE.parents[1] / "app/tests/check_macos_export.py"), str(target)],
                                   text=True, capture_output=True)
        self.assertEqual(signature.returncode, 0, signature.stdout + signature.stderr)
        self.results["exports"][mode] = {"uuids": actual, "sha256": HELPER.digest(target),
            "signature_check": signature.stdout.strip(), "checked_report": str(checked["report"])}
        return actual

    def test_official_release_uses_release_payloads(self):
        self.assertEqual(self.export("release"), self.expected["release"])

    def test_official_debug_uses_debug_payloads(self):
        self.assertEqual(self.export("debug"), self.expected["debug"])


if __name__ == "__main__":
    unittest.main()
