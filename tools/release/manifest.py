#!/usr/bin/env python3
"""Capture export inputs, finalize release metadata and verify transferred artifacts."""
from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import threading
import zipfile

if __package__:
    from . import elf_audit, macos_reference_receipt
else:
    import elf_audit
    import macos_reference_receipt

FORMAT = "openrc-release-manifest-v2"
LEGACY_FORMAT = "openrc-release-manifest-v1"
MANIFEST = "release-manifest.json"
ABI_REPORT = "linux-abi.json"
CHECKSUMS = "SHA256SUMS"
SNAPSHOT = ".release-inputs.json"
TARGETS = (("linux", "x86_64"), ("windows", "x86_64"), ("macos", "universal"))
SOURCE_INPUTS = (
    "app/export.sh", "app/get-godot.sh", "app/get-templates.sh", "app/export_presets.cfg",
    "tools/release/manifest.py", "tools/release/elf_audit.py",
    "tools/godot/macos_universal_template.py", ".github/workflows/ci.yml",
    "research/native-kernel/toolchain-lock.json", "research/native-kernel/package.py",
    "research/rc-monster-truck/native/toolchain-lock.json",
    "app/native/kernel/build-receipt.json", "app/native/ground_vehicle/build-receipt.json",
)
TEMPLATES = ("linux_release.x86_64", "windows_release_x86_64.exe", "macos.zip", "version.txt")
MACOS_OFFICIAL = "template/macos-selected.zip"
MACOS_CUSTOM = {"template/macos-derived.zip", "template/macos-derived.receipt.json"}
CI_KEYS = ("GITHUB_REPOSITORY", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_WORKFLOW_REF",
           "GITHUB_WORKFLOW_SHA", "GITHUB_REF", "GITHUB_SHA", "RUNNER_OS", "RUNNER_ARCH")
PENDING = ["native_desktop_gpu_controller_acceptance", "distro_and_isa_qualification",
           "dlopen_and_driver_dependency_closure", "downloaded_package_rehearsal",
           "sbom_and_license_closure", "publisher_attestation", "reproducible_builds"]
HEX = re.compile(r"[0-9a-f]{64}\Z")
VERSION = re.compile(r"[0-9A-Za-z][0-9A-Za-z._+-]{0,159}\Z")
TAG = re.compile(r"v([0-9]+\.[0-9]+\.[0-9]+)(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?\Z")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(path):
    require(path.is_file() and not path.is_symlink(), f"not a regular metadata file: {path}")
    require(path.stat().st_size <= 16 * 1024 * 1024, f"metadata is too large: {path}")
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)


def write_new(path, value):
    # Exclusive creation also refuses dangling symlinks. Partial files remain on I/O failure.
    with path.open("x", encoding="utf-8", newline="\n") as target:
        target.write(value)


def json_text(value):
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=True) + "\n"


def file_info(path, *, allow_empty=False):
    require(path.is_file() and not path.is_symlink(), f"not a regular input/artifact: {path}")
    before = path.stat()
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    after = path.stat()
    require((before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns),
            f"file changed while hashing: {path}")
    require(allow_empty or before.st_size > 0, f"empty input/artifact: {path}")
    return {"sha256": digest.hexdigest(), "bytes": before.st_size}


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.PIPE)


def git_diff_identity(root):
    command = ["git", "-C", str(root), "diff", "HEAD", "--binary", "--no-ext-diff", "--no-textconv"]
    digest = hashlib.sha256()
    changed = False
    stderr = bytearray()
    stderr_errors = []
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
        def drain_stderr():
            try:
                for chunk in iter(lambda: process.stderr.read(65536), b""):
                    stderr.extend(chunk[:max(0, 65536 - len(stderr))])
            except OSError as error:
                stderr_errors.append(error)
                process.kill()

        reader = threading.Thread(target=drain_stderr, daemon=True)
        reader.start()
        try:
            for chunk in iter(lambda: process.stdout.read(1024 * 1024), b""):
                changed = True
                digest.update(chunk)
            code = process.wait()
        except BaseException:
            process.kill()
            raise
        finally:
            reader.join()
        if stderr_errors:
            raise stderr_errors[0]
        if code:
            raise subprocess.CalledProcessError(code, command, stderr=bytes(stderr))
    return changed, digest


def worktree_identity(root):
    changed, digest = git_diff_identity(root)
    untracked = git(root, "ls-files", "--others", "--exclude-standard", "-z", "--", "app/")
    for raw in sorted(filter(None, untracked.split(b"\0"))):
        path = root / os.fsdecode(raw)
        digest.update(b"\0" + raw + b"\0" + file_info(path, allow_empty=True)["sha256"].encode("ascii"))
    return bool(changed or untracked), digest.hexdigest()


def source_identity(root, env):
    version = env["OPENRC_BUILD_DESCRIBE"]
    commit = git(root, "rev-parse", "HEAD").decode().strip()
    commit_date = git(root, "show", "-s", "--format=%cI", "HEAD").decode().strip()
    dirty, worktree_sha = worktree_identity(root)
    require(env["OPENRC_BUILD_COMMIT"] == commit and env["OPENRC_BUILD_DATE"] == commit_date,
            "source commit changed since export identity was selected")
    require(env["OPENRC_BUILD_DIRTY"] == ("1" if dirty else "0"),
            "source cleanliness changed since export identity was selected")
    numeric = re.search(r'^config/version="([0-9]+\.[0-9]+\.[0-9]+)"$',
                        (root / "app/project.godot").read_text(encoding="utf-8"), re.MULTILINE)
    require(numeric is not None, "invalid project application version")
    ref = env.get("GITHUB_REF", "")
    tag = ref.removeprefix("refs/tags/") if ref.startswith("refs/tags/") else None
    if tag is not None:
        require(TAG.fullmatch(tag) is not None and version == tag and not dirty, "invalid tagged build identity")
        require(git(root, "rev-parse", f"refs/tags/{tag}^{{commit}}").decode().strip() == commit,
                "release tag does not identify the source commit")
    return {"version": version, "commit": commit, "commit_date": commit_date,
            "tree": git(root, "rev-parse", "HEAD^{tree}").decode().strip(),
            "application_version": numeric.group(1), "dirty": dirty, "tag": tag,
            "channel": ("preview" if "-" in tag else "stable") if tag else "development",
            "worktree_sha256": worktree_sha}


def desktop_template_inputs(root, templates):
    """Validate all selected desktop templates and identify the macOS input."""
    config = configparser.ConfigParser(interpolation=None, delimiters=("=",), strict=True)
    config.optionxform = str
    try:
        config.read_string((root / "app/export_presets.cfg").read_text(encoding="utf-8"))
        require(not config.defaults(), "export preset defaults are unsupported")
        expected = {"Linux": "Linux", "Windows": "Windows Desktop", "macOS": "macOS"}
        presets = {name: [] for name in expected}
        for section in config.sections():
            if not re.fullmatch(r"preset\.\d+", section):
                continue
            number = section.removeprefix("preset.")
            require(number == str(int(number)), "noncanonical export preset index")
            name = json.loads(config.get(section, "name", fallback='""'))
            require(isinstance(name, str), "export preset name must be a string")
            if name in presets:
                presets[name].append(section)
        custom_templates = {}
        for name, platform_name in expected.items():
            require(len(presets[name]) == 1, f"expected exactly one {name} export preset")
            preset = presets[name][0]
            platform_value = json.loads(config.get(preset, "platform", fallback='""'))
            require(isinstance(platform_value, str) and platform_value == platform_name,
                    f"{name} export preset has the wrong platform")
            setting = config.get(preset + ".options", "custom_template/release", fallback='""')
            custom_templates[name] = json.loads(setting)
            require(isinstance(custom_templates[name], str), f"{name} release template must be a string")
        for name in ("Linux", "Windows"):
            require(not custom_templates[name], f"custom {name} release templates are not supported")
        custom = custom_templates["macOS"]
    except (configparser.Error, json.JSONDecodeError) as error:
        raise ValueError(f"invalid export preset configuration: {error}") from error
    if not custom:
        return {MACOS_OFFICIAL: templates / "macos.zip"}
    require(custom.startswith("res://") and len(custom) > len("res://"),
            "custom macOS release template must be a project resource")
    derived = root / "app" / custom.removeprefix("res://")
    require(derived.resolve().is_relative_to((root / "app/.godot/export_templates").resolve()),
            "derived template must stay in the project template cache")
    return {"template/macos-derived.zip": derived,
            "template/macos-derived.receipt.json": derived.with_suffix(".zip.receipt.json")}


def capture(root, editor, templates, env=None):
    env = os.environ if env is None else env
    source = source_identity(root, env)
    paths = {name: root / name for name in SOURCE_INPUTS}
    paths.update({"template/" + name: templates / name for name in TEMPLATES})
    paths.update(desktop_template_inputs(root, templates))
    paths["editor"] = editor
    for tool in ("zip", "readelf"):
        executable = shutil.which(tool)
        require(executable is not None, f"required export tool is unavailable: {tool}")
        paths["tool/" + tool] = Path(executable).resolve()
    inputs = {name: file_info(path) for name, path in paths.items()}
    engine = subprocess.check_output([str(editor), "--version"], text=True, timeout=30).strip()
    expected = re.search(r'^ENGINE_VERSION=(\S+)$', (root / "app/get-godot.sh").read_text(), re.MULTILINE)
    require(expected is not None and engine == expected.group(1), "editor differs from pinned engine version")
    return {"format": "openrc-release-inputs-v1", "source": source, "engine_version": engine,
            "inputs": inputs, "paths": {name: str(path.resolve()) for name, path in paths.items()},
            "build": {"host": platform.platform(), "python": platform.python_version(),
                      "ci": {key: env.get(key) for key in CI_KEYS}}}


def artifact_names(version):
    require(isinstance(version, str) and VERSION.fullmatch(version) is not None, "unsafe build version")
    return [f"openrc-simulator-{version}-{system}-{architecture}.zip" for system, architecture in TARGETS]


def keys(value, expected, label):
    require(isinstance(value, dict) and set(value) == set(expected), f"invalid {label} fields")


def validate_digest(value):
    require(isinstance(value.get("sha256"), str) and HEX.fullmatch(value["sha256"]) is not None,
            "invalid artifact/input SHA-256")
    require(type(value.get("bytes")) is int and value["bytes"] > 0, "invalid artifact/input byte size")


def validate_metadata(data):
    require(isinstance(data, dict) and data.get("format") in (FORMAT, LEGACY_FORMAT),
            "unsupported release manifest format")
    fields = ("format", "source", "build", "engine_version", "inputs", "artifacts", "reports", "qualification")
    keys(data, fields + (("macos_reference",) if data["format"] == FORMAT else ()), "manifest")
    source = data["source"]
    keys(source, ("version", "commit", "commit_date", "tree", "application_version", "dirty", "tag", "channel", "worktree_sha256"), "source")
    names = artifact_names(source["version"])
    for field in ("commit", "tree"):
        require(isinstance(source[field], str) and re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", source[field]), "invalid Git identity")
    require(isinstance(source["worktree_sha256"], str) and HEX.fullmatch(source["worktree_sha256"]), "invalid worktree digest")
    require(type(source["dirty"]) is bool, "source dirty must be a boolean")
    require(isinstance(source["commit_date"], str) and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:Z|[+-]\d\d:\d\d)", source["commit_date"]), "invalid source timestamp")
    require(isinstance(source["application_version"], str) and re.fullmatch(r"\d+\.\d+\.\d+", source["application_version"]), "invalid application version")
    if source["tag"] is None:
        require(source["channel"] == "development", "untagged artifacts must use development channel")
    else:
        tag = source["tag"]
        match = TAG.fullmatch(tag) if isinstance(tag, str) else None
        require(match is not None and source["version"] == tag and not source["dirty"], "invalid release tag")
        require(match.group(1) == source["application_version"], "release tag/application version mismatch")
        require(source["channel"] == ("preview" if "-" in tag else "stable"), "incorrect release channel")
    keys(data["build"], ("host", "python", "ci"), "build")
    keys(data["build"]["ci"], CI_KEYS, "CI identity")
    require(all(value is None or isinstance(value, str) for value in data["build"]["ci"].values()), "invalid CI identity")
    require(all(isinstance(data["build"][key], str) and data["build"][key] for key in ("host", "python")), "invalid build host")
    require(isinstance(data["engine_version"], str) and bool(data["engine_version"]), "missing engine version")
    input_names = set(SOURCE_INPUTS) | {"template/" + name for name in TEMPLATES} | {
        "editor", "tool/zip", "tool/readelf"}
    require(isinstance(data["inputs"], dict) and set(data["inputs"]) in
            (input_names | {MACOS_OFFICIAL}, input_names | MACOS_CUSTOM), "incorrect export inputs")
    for row in data["inputs"].values():
        keys(row, ("sha256", "bytes"), "input")
        validate_digest(row)
    if MACOS_OFFICIAL in data["inputs"]:
        require(data["inputs"][MACOS_OFFICIAL] == data["inputs"]["template/macos.zip"],
                "selected official macOS template differs from the installed template")
    require(isinstance(data["artifacts"], list) and len(data["artifacts"]) == len(TARGETS), "incorrect package inventory")
    for row, name, (system, architecture) in zip(data["artifacts"], names, TARGETS):
        keys(row, ("filename", "platform", "architecture", "format", "sha256", "bytes"), "artifact")
        require((row["filename"], row["platform"], row["architecture"], row["format"]) ==
                (name, system, architecture, "zip"), "incorrect package identity")
        validate_digest(row)
    require(isinstance(data["reports"], list) and len(data["reports"]) == 1, "incorrect report inventory")
    row = data["reports"][0]
    keys(row, ("filename", "sha256", "bytes"), "report")
    require(row["filename"] == ABI_REPORT, "unexpected report filename")
    validate_digest(row)
    require(data["qualification"] == {"status": "not_platform_qualified", "pending": PENDING},
            "this schema does not certify platform qualification")
    if data["format"] == FORMAT:
        reference = data["macos_reference"]
        keys(reference, ("receipt_sha256", "source_receipt_sha256", "probe_sha256"), "Mac reference")
        require(all(isinstance(value, str) and HEX.fullmatch(value) for value in reference.values()),
                "invalid Mac reference digest")


def validate_abi(report, linux):
    elf_audit.validate_report(report)
    require(report.get("expected_architecture") == "x86_64", "incorrect Linux ABI architecture")
    archive = report.get("archive", {})
    require(archive == {"path": linux["filename"], "sha256": linux["sha256"], "bytes": linux["bytes"]},
            "ABI report does not identify the final Linux archive")


def validate_linux_payload(directory, root, captured, report):
    """Bind inventoried final native bytes to the receipts checked before packaging."""
    rows = {row["path"]: row for row in report["elfs"]}
    main = "openrc-simulator.x86_64"
    kernel = "native/kernel/libopenrc_native_kernel.so"
    ground = "libopenrc_ground_vehicle.so"
    require({main, kernel, ground} <= set(rows), "final Linux ZIP omitted a required executable/native library")
    with zipfile.ZipFile(directory / report["archive"]["path"]) as archive:
        info = archive.getinfo("native/kernel/package-receipt.json")
        require(info.file_size <= 1024 * 1024, "oversized native package receipt")
        receipt = json.loads(archive.read(info), object_pairs_hook=unique_object)
    require(isinstance(receipt, dict) and receipt.get("format") == "openrc-native-kernel-package-artifact v1",
            "invalid packaged native receipt")
    expected = {"executable_sha256": rows[main]["sha256"], "native_binary_sha256": rows[kernel]["sha256"],
                "editor_sha256": captured["inputs"]["editor"]["sha256"],
                "template_sha256": captured["inputs"]["template/linux_release.x86_64"]["sha256"],
                "manifest_sha256": file_info(root / "app/native/kernel/package.json")["sha256"]}
    require(all(receipt.get(key) == value for key, value in expected.items()),
            "final Linux ZIP differs from the qualified native package receipt")
    for path, member in (("app/native/kernel/build-receipt.json", kernel),
                         ("app/native/ground_vehicle/build-receipt.json", ground)):
        native = read_json(Path(captured["paths"][path]))
        require(native["platforms"]["linux"]["binary_sha256"] == rows[member]["sha256"],
                f"final Linux native library differs from captured build receipt: {member}")


def validate_macos_payload(directory, artifact, source, *, snapshot_hash=None, probe_hash=None, staged_zip=None):
    path = directory / artifact["filename"]
    identity = macos_reference_receipt.verify_zip(path, source=source, snapshot_hash=snapshot_hash,
                                                   probe_hash=probe_hash, staged_zip=staged_zip)
    require(identity["architectures"] == ["arm64", "x86_64"], "final Mac ZIP is not universal")
    require(file_info(path) == {key: artifact[key] for key in ("sha256", "bytes")},
            "final Mac ZIP changed while validating its receipt")
    return identity


def finalize(directory, root, snapshot):
    captured = read_json(snapshot)
    require(captured.get("format") == "openrc-release-inputs-v1", "invalid input snapshot")
    source = captured["source"]
    env = {"OPENRC_BUILD_DESCRIBE": source["version"], "OPENRC_BUILD_COMMIT": source["commit"],
           "OPENRC_BUILD_DATE": source["commit_date"], "OPENRC_BUILD_DIRTY": "1" if source["dirty"] else "0",
           "GITHUB_REF": "refs/tags/" + source["tag"] if source["tag"] else ""}
    require(source_identity(root, env) == source, "source changed during export")
    require(set(captured["paths"]) == set(captured["inputs"]), "incomplete captured paths")
    for name, path in captured["paths"].items():
        require(file_info(Path(path)) == captured["inputs"][name], f"export input changed: {name}")
    artifacts = []
    for name, (system, architecture) in zip(artifact_names(source["version"]), TARGETS):
        artifacts.append({"filename": name, "platform": system, "architecture": architecture,
                          "format": "zip", **file_info(directory / name)})
    report = read_json(directory / ABI_REPORT)
    validate_abi(report, artifacts[0])
    validate_linux_payload(directory, root, captured, report)
    mac_identity = validate_macos_payload(directory, artifacts[2], source, snapshot_hash=file_info(snapshot)["sha256"],
                                          probe_hash=file_info(root / "research/performance/session_probe.gd")["sha256"],
                                          staged_zip=directory / "macos/OpenRC Simulator.zip")
    data = {key: captured[key] for key in ("source", "build", "engine_version", "inputs")}
    data.update(format=FORMAT, artifacts=artifacts,
                reports=[{"filename": ABI_REPORT, **file_info(directory / ABI_REPORT)}],
                qualification={"status": "not_platform_qualified", "pending": PENDING},
                macos_reference={key: mac_identity[key] for key in
                                 ("receipt_sha256", "source_receipt_sha256", "probe_sha256")})
    validate_metadata(data)
    write_new(directory / MANIFEST, json_text(data))
    records = artifacts + data["reports"] + [{"filename": MANIFEST, **file_info(directory / MANIFEST)}]
    write_new(directory / CHECKSUMS, "".join(f'{row["sha256"]}  {row["filename"]}\n' for row in records))
    verify(directory, allow_staging=True)
    return data


def verify(directory, *, expected_commit=None, expected_tag=None, expected_run_id=None,
           expected_repository=None, allow_staging=False):
    data = read_json(directory / MANIFEST)
    validate_metadata(data)
    source = data["source"]
    for expected, actual, label in ((expected_commit, source["commit"], "commit"),
                                    (expected_tag, source["tag"], "tag"),
                                    (expected_run_id, data["build"]["ci"]["GITHUB_RUN_ID"], "Actions run"),
                                    (expected_repository, data["build"]["ci"]["GITHUB_REPOSITORY"], "repository")):
        require(expected is None or expected == actual, f"unexpected release {label}")
    rows = data["artifacts"] + data["reports"]
    for row in rows:
        require(file_info(directory / row["filename"]) == {key: row[key] for key in ("sha256", "bytes")},
                f"artifact digest/size mismatch: {row['filename']}")
    validate_abi(read_json(directory / ABI_REPORT), data["artifacts"][0])
    # v1 predates the Mac receipt; retain its original integrity-only policy.
    if data["format"] == FORMAT:
        mac_identity = validate_macos_payload(directory, data["artifacts"][2], source)
        require(all(mac_identity[key] == expected for key, expected in data["macos_reference"].items()),
                "Mac receipt differs from the manifest reference digests")
    records = rows + [{"filename": MANIFEST, **file_info(directory / MANIFEST)}]
    expected_sums = "".join(f'{row["sha256"]}  {row["filename"]}\n' for row in records)
    checksum_path = directory / CHECKSUMS
    require(checksum_path.is_file() and not checksum_path.is_symlink(), "missing regular SHA256SUMS")
    require(checksum_path.read_bytes() == expected_sums.encode("ascii"), "checksum inventory/content mismatch")
    expected_names = {row["filename"] for row in records} | {CHECKSUMS}
    staging_names = {"linux", "windows", "macos", SNAPSHOT} if allow_staging else set()
    actual_names = {path.name for path in directory.iterdir()}
    require(expected_names <= actual_names and actual_names <= expected_names | staging_names,
            "unexpected files/directories in release inventory")
    for name in actual_names & staging_names:
        path = directory / name
        require(not path.is_symlink() and (path.is_file() if name == SNAPSHOT else path.is_dir()), "invalid export staging path")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    start = commands.add_parser("capture", help="freeze actual inputs before exporting")
    start.add_argument("--root", type=Path, required=True)
    start.add_argument("--editor", type=Path, required=True)
    start.add_argument("--templates", type=Path, required=True)
    start.add_argument("--output", type=Path, required=True)
    finish = commands.add_parser("finalize", help="bind final archives and ABI report after existing export checks")
    finish.add_argument("--root", type=Path, required=True)
    finish.add_argument("--directory", type=Path, required=True)
    finish.add_argument("--inputs", type=Path, required=True)
    check = commands.add_parser("verify", help="verify the complete transferred six-file release set")
    check.add_argument("--directory", type=Path, required=True)
    check.add_argument("--expected-commit")
    check.add_argument("--expected-tag")
    check.add_argument("--expected-run-id")
    check.add_argument("--expected-repository")
    check.add_argument("--allow-staging", action="store_true", help="allow only known exporter working paths")
    args = parser.parse_args()
    try:
        if args.command == "capture":
            write_new(args.output, json_text(capture(args.root.resolve(), args.editor.resolve(), args.templates.resolve())))
        elif args.command == "finalize":
            finalize(args.directory, args.root, args.inputs)
        else:
            verify(args.directory, expected_commit=args.expected_commit, expected_tag=args.expected_tag,
                   expected_run_id=args.expected_run_id, expected_repository=args.expected_repository,
                   allow_staging=args.allow_staging)
        print(f"Release metadata {args.command}: passed")
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        parser.exit(1, f"Release metadata {args.command}: {error}\n")


if __name__ == "__main__":
    main()
