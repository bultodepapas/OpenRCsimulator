#!/usr/bin/env python3
"""Bind a retained MetalFX editor/template pair to one custom macOS export ZIP.

This producer is deliberately separate from package admission and promotion.  A
binding establishes checked artifact consistency, not build authorship, native
backend correctness, hardware qualification, or permission to distribute.
"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import struct
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FORMAT = "openrc-macos-engine-pair-binding v1"
RELEASE_MEMBER = "macos_template.app/Contents/MacOS/godot_macos_release.arm64"
SKELETON = frozenset({
    "macos_template.app/Contents/Info.plist",
    "macos_template.app/Contents/PkgInfo",
    "macos_template.app/Contents/Resources/PrivacyInfo.xcprivacy",
    "macos_template.app/Contents/Resources/icon.icns",
})
SHA_FIELDS = frozenset({"editor_sha256", "template_sha256", "editor_receipt_sha256",
                        "template_receipt_sha256", "pair_receipt_sha256", "export_template_sha256",
                        "source_archive_sha256", "source_catalog_sha256"})
MAX_JSON = 2 * 1024 * 1024
MAX_PATCH = 8 * 1024 * 1024
MAX_SKELETON = 2 * 1024 * 1024
MAX_BINARY = 512 * 1024 * 1024
MAX_ZIP = 512 * 1024 * 1024
MAX_SOURCE = 2 * 1024 * 1024 * 1024
MAX_LOG = 256 * 1024 * 1024
CHUNK = 1024 * 1024


def _module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValueError(f"Cannot load required verifier: {path}")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def _engine():
    return _module("openrc_pair_intake", ROOT / "tools/graphics/metalfx/engine.py")


def _mac_builder():
    return _module("openrc_pair_macos_builder", HERE / "build_macos.py")


def _digest(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def _pins(value: object) -> dict:
    if not isinstance(value, dict) or set(value) != SHA_FIELDS | {"format", "patch_sha256"} \
            or value.get("format") != FORMAT or any(not _digest(value[k]) for k in SHA_FIELDS):
        raise ValueError("Expected binding must contain every independently selected identity")
    patches = value.get("patch_sha256")
    if not isinstance(patches, list) or not 1 <= len(patches) <= 64 \
            or any(not _digest(item) for item in patches):
        raise ValueError("Expected ordered patch identities must contain 1 to 64 SHA-256 values")
    return copy.deepcopy(value)


def _path(value: object, *, directory: bool = False) -> Path:
    if not isinstance(value, (str, Path)) or not str(value):
        raise ValueError("Input path must be explicit")
    path = Path(value).absolute()
    try:
        resolved = path.resolve(strict=True)
        if os.path.normcase(os.path.abspath(path)) != os.path.normcase(str(resolved)):
            raise ValueError(f"Redirected input path: {path}")
        if any(part.is_symlink() for part in (path, *path.parents)):
            raise ValueError(f"Symbolic-link input path: {path}")
        mode = path.stat().st_mode
        if not (stat.S_ISDIR(mode) if directory else stat.S_ISREG(mode)):
            raise ValueError(f"Input is not an ordinary {'directory' if directory else 'file'}: {path}")
    except OSError as error:
        raise ValueError(f"Missing or inaccessible input: {path}") from error
    return path


def _same_path(left: object, right: object) -> bool:
    return os.path.normcase(str(_path(left))) == os.path.normcase(str(_path(right)))


def _stamp(info: os.stat_result) -> tuple:
    # On Windows Python's handle and pathname ctime can temporarily differ
    # after a close; inode, size and mtime plus the digest remain comparable.
    common = (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns)
    return common if os.name == "nt" else common + (info.st_ctime_ns,)


def _open(path: Path):
    path = _path(path)
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    stream = os.fdopen(fd, "rb")
    opened, named = _stamp(os.fstat(stream.fileno())), _stamp(path.stat())
    if opened != named:
        stream.close()
        raise ValueError(f"Input changed while opening: {path}")
    return stream


def _snapshot(path: Path, limit: int) -> tuple:
    path = _path(path)
    with _open(path) as stream:
        before = _stamp(os.fstat(stream.fileno()))
        if not 0 < before[3] <= limit:
            raise ValueError(f"Input is empty or exceeds its size bound: {path}")
        digest = hashlib.sha256()
        count = 0
        for chunk in iter(lambda: stream.read(CHUNK), b""):
            count += len(chunk)
            if count > limit:
                raise ValueError(f"Input exceeds its size bound: {path}")
            digest.update(chunk)
        if count != before[3] or _stamp(os.fstat(stream.fileno())) != before \
                or _stamp(_path(path).stat()) != before:
            raise ValueError(f"Input changed while reading: {path}")
        return before, digest.hexdigest()


def _json(path: Path) -> dict:
    before = _snapshot(path, MAX_JSON)
    with _open(path) as stream:
        raw = stream.read(MAX_JSON + 1)
    if len(raw) > MAX_JSON or hashlib.sha256(raw).hexdigest() != before[1] \
            or _snapshot(path, MAX_JSON) != before:
        raise ValueError(f"Receipt changed while reading: {path}")
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate receipt key: {key}")
            result[key] = value
        return result
    def invalid(value):
        raise ValueError(f"Non-finite receipt value: {value}")
    try:
        value = json.loads(raw, object_pairs_hook=unique, parse_constant=invalid)
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as error:
        raise ValueError(f"Invalid receipt: {path}") from error
    if not isinstance(value, dict):
        raise ValueError("Receipt must be an object")
    return value


def _pair_shape(pair: object, helper) -> None:
    if not isinstance(pair, dict) or set(pair) != {"schema", "status", "source_commit", "build_receipts",
                                              "artifacts", "hardware_qualification", "public_distribution"} \
            or pair.get("schema") != helper.SCHEMA or pair.get("status") != "pair_verified" \
            or pair.get("source_commit") != helper.COMMIT or pair.get("hardware_qualification") != "not_run" \
            or pair.get("public_distribution") != "deferred":
        raise ValueError("Saved or freshly verified pair has an invalid envelope")
    receipts, artifacts = pair.get("build_receipts"), pair.get("artifacts")
    if not isinstance(receipts, list) or len(receipts) != 2 or any(not _digest(x) for x in receipts) \
            or not isinstance(artifacts, list) or len(artifacts) != 2:
        raise ValueError("Pair must contain the ordered editor and release template")
    for item, name in zip(artifacts, ("godot.macos.editor.arm64", "godot.macos.template_release.arm64")):
        if not isinstance(item, dict) or set(item) != {"name", "sha256", "bytes", "architectures"} \
                or item.get("name") != name or not _digest(item.get("sha256")) \
                or type(item.get("bytes")) is not int or not 0 < item["bytes"] <= MAX_BINARY \
                or item.get("architectures") != ["arm64"]:
            raise ValueError("Pair artifact identity, order, size, or architecture differs")


def _regular_member(info: zipfile.ZipInfo, maximum: int) -> None:
    mode = info.external_attr >> 16
    if (info.orig_filename != info.filename or info.is_dir() or info.create_system != 3
            or stat.S_IFMT(mode) != stat.S_IFREG or info.flag_bits & 1
            or info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
            or not 0 < info.file_size <= maximum or not 0 < info.compress_size <= MAX_ZIP):
        raise ValueError(f"Unsafe or oversized ZIP member: {info.filename!r}")


def _compare_streams(left, right, size: int, *, executable: bool = False) -> str:
    digest = hashlib.sha256()
    count = 0
    header = b""
    while True:
        a, b = left.read(CHUNK), right.read(CHUNK)
        if a != b:
            raise ValueError("Export ZIP member differs from its independently verified input")
        if not a:
            break
        if not header:
            header = a[:32]
        count += len(a)
        if count > size:
            raise ValueError("Export ZIP member exceeds its declared size")
        digest.update(a)
    if count != size:
        raise ValueError("Export ZIP member size differs from its verified input")
    if executable:
        if len(header) != 32:
            raise ValueError("Release template has no complete Mach-O header")
        magic, cpu, _subtype, filetype, _ncmds, _cmdbytes, _flags, _reserved = struct.unpack("<8I", header)
        if (magic, cpu, filetype) != (0xFEEDFACF, 0x0100000C, 2):
            raise ValueError("Release template is not a thin ARM64 Mach-O executable")
    return digest.hexdigest()


def _bounded_export_directory(stream) -> None:
    """Reject huge/ambiguous directories before ZipFile allocates its member list."""
    stream.seek(0, os.SEEK_END)
    length = stream.tell()
    if not 22 <= length <= MAX_ZIP:
        raise ValueError("Export ZIP is outside its size bound")
    stream.seek(-22, os.SEEK_END)
    end = stream.read(22)
    signature, disk, directory_disk, disk_count, total_count, directory_size, directory_offset, comment = \
        struct.unpack("<4s4H2IH", end)
    if (signature != b"PK\x05\x06" or disk != 0 or directory_disk != 0 or disk_count != 5
            or total_count != 5 or comment != 0 or directory_size > 64 * 1024
            or directory_offset + directory_size != length - 22):
        raise ValueError("Export ZIP lacks a bounded five-entry central directory")
    stream.seek(0)


def _check_export_zip(export: Path, source: Path, release: Path, artifact: dict, helper) -> None:
    """Compare the five archive members without extracting any filesystem path."""
    try:
        with _open(export) as export_stream, _open(source) as source_stream, _open(release) as executable:
            _bounded_export_directory(export_stream)
            with zipfile.ZipFile(export_stream) as package, zipfile.ZipFile(source_stream) as original:
                items = package.infolist()
                names = [item.filename for item in items]
                if len(names) != 5 or len({name.casefold() for name in names}) != 5 \
                        or set(names) != SKELETON | {RELEASE_MEMBER}:
                    raise ValueError("Export ZIP has a missing, duplicate, unsafe, or unexpected member")
                source_names = {name: f"{helper.SOURCE_PREFIX}/misc/dist/{name}" for name in SKELETON}
                source_infos = original.infolist()
                for item in items:
                    _regular_member(item, MAX_BINARY if item.filename == RELEASE_MEMBER else MAX_SKELETON)
                    if item.filename == RELEASE_MEMBER:
                        if item.file_size != artifact["bytes"] or not (item.external_attr >> 16) & stat.S_IXUSR:
                            raise ValueError("Release member size or executable mode differs")
                        with package.open(item) as payload:
                            digest = _compare_streams(payload, executable, artifact["bytes"], executable=True)
                        if digest != artifact["sha256"]:
                            raise ValueError("Release member digest differs from the verified template")
                    else:
                        matches = [info for info in source_infos if info.filename == source_names[item.filename]]
                        if len(matches) != 1 or matches[0].is_dir() or matches[0].file_size != item.file_size \
                                or matches[0].file_size > MAX_SKELETON \
                                or stat.S_IFMT(matches[0].external_attr >> 16) == stat.S_IFLNK:
                            raise ValueError("Pinned source archive lacks an unambiguous skeleton member")
                        with package.open(item) as payload, original.open(matches[0]) as expected:
                            _compare_streams(payload, expected, item.file_size)
    except (zipfile.BadZipFile, NotImplementedError, EOFError) as error:
        raise ValueError("Invalid or unsupported export/source ZIP") from error


def bind(*, archive: Path, editor_intake: Path, template_intake: Path, patches: list[Path],
         pair_receipt: Path, export_template: Path, godot: Path, selection: dict, expected: dict) -> dict:
    """Verify live inputs and return the ten-field binding, only if every external pin matches.

    ``selection`` is the explicit research-engine selection accepted by
    macos_engine_identity, including its *engine* toolchain profile. ``expected``
    contains all independently selected binding digests; it is never inferred
    from the saved receipt. The native-kernel compiler profile is not an input.
    """
    expected = _pins(expected)
    if not isinstance(selection, dict) or not isinstance(patches, list) or not 1 <= len(patches) <= 64:
        raise ValueError("Explicit research selection and ordered patches are required")
    selected = copy.deepcopy(selection)
    helper, mac = _engine(), _mac_builder()
    engine_path, policy_path = _path(helper.__file__), _path(mac.engine_policy.__file__)
    archive, pair_receipt, export_template, godot = map(_path, (archive, pair_receipt, export_template, godot))
    editor_intake, template_intake = (_path(path, directory=True) for path in (editor_intake, template_intake))
    patches = [_path(path) for path in patches]
    if len(set(map(lambda p: os.path.normcase(str(p)), patches))) != len(patches) or editor_intake == template_intake:
        raise ValueError("Intakes and ordered patch files must be distinct")
    editor_receipt = _path(editor_intake / "build-editor.json")
    template_receipt = _path(template_intake / "build-template_release.json")
    template_binary = _path(template_intake / "build-source-template_release/bin/godot.macos.template_release.arm64")
    editor_binary = _path(editor_intake / "build-source-editor/bin/godot.macos.editor.arm64")
    api = _path(selected.get("extension_api"))
    reference = _path(selected.get("reference_godot"))
    if not _same_path(godot, editor_binary) or not _same_path(selected.get("receipt"), editor_receipt) \
            or not _same_path(selected.get("archive"), archive) or not isinstance(selected.get("patches"), list) \
            or len(selected["patches"]) != len(patches) \
            or any(not _same_path(a, b) for a, b in zip(selected["patches"], patches)):
        raise ValueError("Research selection does not name these original ordered pair inputs")
    profile_name = selected.get("toolchain_profile")
    profiles = mac.engine_policy.TOOLCHAIN_PROFILES
    if not isinstance(profile_name, str) or profile_name not in profiles:
        raise ValueError("An explicit, supported research-engine toolchain profile is required")
    files = [(archive, MAX_SOURCE), (pair_receipt, MAX_JSON), (export_template, MAX_ZIP),
             (editor_receipt, MAX_JSON), (template_receipt, MAX_JSON), (editor_binary, MAX_BINARY),
             (template_binary, MAX_BINARY), (engine_path, MAX_PATCH), (policy_path, MAX_PATCH),
             (api, 64 * 1024 * 1024), (reference, MAX_BINARY),
             *[(patch, MAX_PATCH) for patch in patches]]
    for directory, target in ((editor_intake, "editor"), (template_intake, "template_release")):
        files.extend([(_path(directory / "intake.json"), MAX_JSON),
                      (_path(directory / f"build-{target}.log"), MAX_LOG)])
        _path(directory / "source", directory=True)
        _path(directory / f"build-source-{target}", directory=True)
    before = {str(path): _snapshot(path, maximum) for path, maximum in files}
    saved = _json(pair_receipt)
    _pair_shape(saved, helper)
    records = [_json(editor_receipt), _json(template_receipt)]
    intakes = [_json(editor_intake / "intake.json"), _json(template_intake / "intake.json")]
    patch_hashes = [before[str(path)][1] for path in patches]
    # Reject a wrong independent pin early; acceptance still requires every
    # verifier below and a second comparison with the derived binding.
    observed = {"format": FORMAT, "editor_sha256": before[str(editor_binary)][1],
                "template_sha256": before[str(template_binary)][1],
                "editor_receipt_sha256": before[str(editor_receipt)][1],
                "template_receipt_sha256": before[str(template_receipt)][1],
                "pair_receipt_sha256": before[str(pair_receipt)][1],
                "export_template_sha256": before[str(export_template)][1],
                "source_archive_sha256": before[str(archive)][1],
                "source_catalog_sha256": intakes[0].get("source_catalog_sha256"), "patch_sha256": patch_hashes}
    if observed != expected:
        raise ValueError("Inputs differ from independently selected identities")
    for record, intake, target in zip(records, intakes, ("editor", "template_release")):
        if type(record.get("returncode")) is not int or record["returncode"] != 0 \
                or record.get("hardware_qualification") != "not_run" or record.get("target") != target \
                or record.get("intake") != intake \
                or record.get("sdk_version") != profiles[profile_name]["sdk_version"] \
                or not isinstance(record.get("clang"), str) \
                or record["clang"].splitlines()[:1] != [profiles[profile_name]["compiler_version"]]:
            raise ValueError("Engine build receipt or explicit compiler/SDK profile differs")
    editor_command, template_command = (record.get("command") for record in records)
    if not isinstance(editor_command, list) or not isinstance(template_command, list) \
            or len(editor_command) != 18 or len(template_command) != 18 \
            or not isinstance(template_command[3], str) \
            or re.fullmatch(r"-j(?:[1-9]|[12][0-9]|3[0-2])", template_command[3]) is None \
            or editor_command[:3] != template_command[:3] \
            or editor_command[4:6] != template_command[4:6] \
            or editor_command[6] != "target=editor" or template_command[6] != "target=template_release" \
            or editor_command[7:] != template_command[7:]:
        raise ValueError("Template command differs from the independently checked editor build")
    fresh = helper.verify_pair(archive, editor_intake, template_intake, patches)
    _pair_shape(fresh, helper)
    if saved != fresh:
        raise ValueError("Saved pair differs from fresh verification of the original intakes and builds")
    lock = copy.deepcopy(mac.locked.load_lock())
    identity = mac.godot_identity(godot, lock, selected)
    if not isinstance(identity, dict) or not isinstance(identity.get("research_engine"), dict):
        raise ValueError("Selected editor has no checked research provenance")
    provenance = identity["research_engine"]
    expected_toolchain = {"profile": profile_name, **profiles[profile_name]}
    if (identity.get("sha256") != fresh["artifacts"][0]["sha256"]
            or identity.get("architectures") != ["arm64"] or not _same_path(identity.get("path"), godot)
            or provenance.get("scope") != mac.engine_policy.SCOPE or provenance.get("selection") != selected
            or provenance.get("runtime_version") != selected.get("runtime_version")
            or provenance.get("source_commit") != helper.COMMIT
            or provenance.get("build_toolchain") != expected_toolchain
            or provenance.get("build_receipt_sha256") != fresh["build_receipts"][0]
            or provenance.get("source_archive_sha256") != before[str(archive)][1]
            or provenance.get("intake_helper_sha256") != before[str(engine_path)][1]
            or provenance.get("identity_helper_sha256") != before[str(policy_path)][1]
            or provenance.get("ordered_patches") != [{"path": str(path), "sha256": sha}
                                                       for path, sha in zip(patches, patch_hashes)]):
        raise ValueError("Independently checked editor provenance differs from the verified pair")
    catalog = helper.expected_catalog(archive, patches, template_intake.parent)
    for directory, target in ((editor_intake, "editor"), (template_intake, "template_release")):
        helper.verify_source(directory / f"build-source-{target}", catalog, strict=False)
    if helper.digest_catalog(catalog) != provenance.get("source_catalog_sha256"):
        raise ValueError("Pair source catalog differs from editor provenance")
    _check_export_zip(export_template, archive, template_binary, fresh["artifacts"][1], helper)
    result = {"format": FORMAT, "editor_sha256": fresh["artifacts"][0]["sha256"],
              "template_sha256": fresh["artifacts"][1]["sha256"],
              "editor_receipt_sha256": fresh["build_receipts"][0],
              "template_receipt_sha256": fresh["build_receipts"][1],
              "pair_receipt_sha256": before[str(pair_receipt)][1],
              "export_template_sha256": before[str(export_template)][1],
              "source_archive_sha256": before[str(archive)][1],
              "source_catalog_sha256": provenance["source_catalog_sha256"], "patch_sha256": patch_hashes}
    if result != expected:
        raise ValueError("Verified binding differs from independently selected identities")
    if helper.verify_pair(archive, editor_intake, template_intake, patches) != fresh \
            or mac.godot_identity(godot, lock, selected) != identity or mac.locked.load_lock() != lock:
        raise ValueError("Pair or selected editor changed during verification")
    for directory, target in ((editor_intake, "editor"), (template_intake, "template_release")):
        helper.verify_source(directory / f"build-source-{target}", catalog, strict=False)
    after = {str(path): _snapshot(path, maximum) for path, maximum in files}
    if before != after or selected != selection:
        raise ValueError("Pair binding inputs changed during verification")
    return result
