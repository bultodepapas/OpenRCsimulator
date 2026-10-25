#!/usr/bin/env python3
"""Prepare the pinned disposable app copy for the Godot 4.8 native-upscaler trial."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import PurePosixPath
from pathlib import Path
from typing import Callable


ROOT = Path(__file__).resolve().parents[3]
CANDIDATE = ROOT / "tmp" / "native-reconstruction-candidate"
BASE_COMMIT = "343be4b0bba007ec4295e7da408220a0577d97e1"
INTEGRATION_COMMIT = "7bfbe2ec071bd142c5b1acf7350fff634ec31f16"
FEATURE_INTEGRATION_COMMIT = "91b67d620c1adf3f470dddba33ace63f3fb6851c"
ENGINE_VERSION = "4.8.0"
GENERATOR_RELATIVE = Path("research/aircraft-standardization/build_customization.py")
GENERATOR_SHA256 = "a78b580aa320dfd4d34e27ef2e017cb395e19f71a5e35b25132a7228482e7ac6"
RECEIPT_RELATIVE = Path("presentation-engine-receipt.json")
RECEIPT_FORMAT = "openrc-native-reconstruction-candidate-receipt v1"
INTEGRATION_OVERLAYS = (
    "app/render/reconstruction.gd",
    "app/app_state/display_preferences.gd",
    "app/ui/settings_screen.gd",
    "app/i18n/es.po",
    "app/app_root.gd",
    "app/main.gd",
    "app/tests/test_reconstruction.gd",
    "app/tests/test_advanced_graphics_settings.gd",
)
INTEGRATION_SOURCE_COMMITS = {
    path: INTEGRATION_COMMIT for path in INTEGRATION_OVERLAYS
}
for _path in (
    "app/render/reconstruction.gd",
    "app/ui/settings_screen.gd",
    "app/i18n/es.po",
    "app/tests/test_reconstruction.gd",
    "app/tests/test_advanced_graphics_settings.gd",
):
    INTEGRATION_SOURCE_COMMITS[_path] = FEATURE_INTEGRATION_COMMIT
INTEGRATION_SOURCE_COMMITS["app/tests/test_advanced_graphics_settings.gd"] = "ba42e49b7b814a86f0c29f5d7d29f2239a002e03"
for _path in ("app/render/reconstruction.gd", "app/tests/test_reconstruction.gd"):
    INTEGRATION_SOURCE_COMMITS[_path] = "7af9257dbb6251f1ab3e2f4c4113eec3038b61d4"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def normalized_text(data: bytes) -> bytes:
    try:
        return data.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
    except UnicodeDecodeError as exc:
        raise RuntimeError("candidate inputs must be UTF-8 text") from exc


def pinned_blob(path: str, commit: str = BASE_COMMIT) -> bytes:
    result = subprocess.run(
        ["git", "show", f"{commit}:{path}"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout


def integration_source_commit(path: str) -> str:
    try:
        return INTEGRATION_SOURCE_COMMITS[path]
    except KeyError as exc:
        raise RuntimeError(f"no integration source pin is defined for {path}") from exc


def pinned_integration_blob(path: str) -> bytes:
    return pinned_blob(path, integration_source_commit(path))


def integration_content(path: str) -> bytes:
    """Apply narrow DLSS fixes without importing unrelated newer UI dependencies."""
    content = pinned_integration_blob(path).decode("utf-8")
    if path == "app/ui/settings_screen.gd":
        anchor = '\t\t"dlss_unavailable": return tr("The current graphics session does not report DLSS support.")'
        content = replace_once(content, anchor, anchor + '\n\t\t"dlss_runtime_failure": return tr("DLSS could not continue in this graphics session.")', path)
    elif path == "app/i18n/es.po":
        content += '\nmsgid "DLSS could not continue in this graphics session."\nmsgstr "DLSS no pudo continuar en esta sesión gráfica."\n'
    elif path == "app/render/reconstruction.gd":
        anchor = '\t\t\treturn "" if bool(status.get("available", false)) else "dlss_unavailable"'
        content = replace_once(content, anchor, anchor + '\n\t\treturn "dlss_unavailable"', path)
    return content.encode("utf-8")


def expected_integration_overlays() -> dict[str, dict[str, str]]:
    records: dict[str, dict[str, str]] = {}
    for path in INTEGRATION_OVERLAYS:
        source_commit = integration_source_commit(path)
        source_hash = sha256(pinned_integration_blob(path))
        records[path] = {
            "source_commit": source_commit,
            "source_sha256": source_hash,
            "expected_final_sha256": sha256(integration_content(path)),
        }
    return records


def create_candidate_from_archive() -> None:
    """Stream the pinned app/assets archive into a staging tree, then atomically publish it."""
    if CANDIDATE.exists():
        return
    staging_root = ROOT / "tmp"
    staging_root.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix="native-reconstruction-candidate-", dir=staging_root))
    process: subprocess.Popen[bytes] | None = None
    try:
        process = subprocess.Popen(
            ["git", "archive", "--format=tar", BASE_COMMIT, "app", "assets"],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert process.stdout is not None
        with tarfile.open(fileobj=process.stdout, mode="r|") as archive:
            for member in archive:
                relative = PurePosixPath(member.name)
                if relative.is_absolute() or ".." in relative.parts or not relative.parts or relative.parts[0] not in {"app", "assets"}:
                    raise RuntimeError(f"unsafe path in pinned git archive: {member.name}")
                target = staging.joinpath(*relative.parts)
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                if not member.isfile():
                    raise RuntimeError(f"unsupported entry in pinned git archive: {member.name}")
                source = archive.extractfile(member)
                if source is None:
                    raise RuntimeError(f"cannot read pinned archive member: {member.name}")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.read())
                os.chmod(target, member.mode & 0o777)
        archive_stderr = process.stderr.read().decode("utf-8", errors="replace") if process.stderr else ""
        status = process.wait()
        process = None
        if status:
            raise RuntimeError(f"git archive failed with {status}: {archive_stderr.strip()}")
        (staging / "base-commit.txt").write_text(BASE_COMMIT + "\n", encoding="utf-8")
        if not staging.resolve().is_relative_to(staging_root.resolve()) or CANDIDATE.parent.resolve() != staging_root.resolve():
            raise RuntimeError("candidate staging paths escaped the intended temporary root")
        staging.rename(CANDIDATE)
        print(f"created candidate tree from pinned app/assets archive {BASE_COMMIT}")
    except Exception:
        if process is not None:
            process.kill()
            process.wait()
        if staging.exists():
            if not staging.resolve().is_relative_to(staging_root.resolve()) or staging.resolve() == staging_root.resolve():
                raise RuntimeError("refusing to remove an unexpected staging path")
            shutil.rmtree(staging)
        raise


def replace_once(text: str, old: str, new: str, path: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"expected one pinned edit in {path}: {old!r}")
    return text.replace(old, new, 1)


def prepare_text(path: str, transform: Callable[[str], str], changes: list[dict[str, str]]) -> bytes:
    baseline = pinned_blob(path)
    try:
        baseline_text = baseline.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise RuntimeError(f"pinned source is not UTF-8: {path}") from exc
    expected = transform(baseline_text).encode("utf-8")
    target = CANDIDATE / path
    current = target.read_bytes() if target.is_file() else b""
    normalized_current = normalized_text(current) if current else b""
    if normalized_current not in (normalized_text(baseline), normalized_text(expected)):
        raise RuntimeError(f"candidate has an unexpected edit; refusing to replace: {path}")
    if b"\r\n" in current and current.count(b"\r\n") == current.count(b"\n"):
        expected = expected.replace(b"\n", b"\r\n")
    if current != expected:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(expected)
    changes.append({
        "path": path,
        "base_sha256": sha256(baseline),
        "prepared_sha256": sha256(expected),
    })
    return expected


def pin_line(old: str, new: str, path: str) -> Callable[[str], str]:
    return lambda text: replace_once(text, old, new, path)


def verify_pinned_input(path: str, expected: bytes | None = None) -> bytes:
    baseline = pinned_blob(path)
    candidate = CANDIDATE / path
    current = candidate.read_bytes() if candidate.is_file() else b""
    allowed = (normalized_text(baseline),) if expected is None else (
        normalized_text(baseline), normalized_text(expected)
    )
    if normalized_text(current) not in allowed:
        raise RuntimeError(f"candidate generator input differs from pinned source: {path}")
    return current


def apply_integration_overlay(path: str, previous: dict, changes: list[dict[str, str]]) -> str:
    source_commit = integration_source_commit(path)
    content = integration_content(path)
    content_hash = sha256(content)
    target = CANDIDATE / path
    current = target.read_bytes() if target.is_file() else b""
    try:
        baseline = pinned_blob(path)
    except subprocess.CalledProcessError:
        baseline = b""
    previous_hash = previous.get("integration_overlays", {}).get(path, {}).get("prepared_sha256")
    allowed = {sha256(content), sha256(normalized_text(content))}
    if baseline:
        allowed.update({sha256(baseline), sha256(normalized_text(baseline))})
    if previous_hash:
        allowed.add(str(previous_hash))
    if current and sha256(current) not in allowed and sha256(normalized_text(current)) not in allowed:
        raise RuntimeError(f"candidate integration file has an unexpected edit: {path}")
    if current != content:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    changes.append({
        "path": path,
        "base_sha256": sha256(baseline) if baseline else "not-present-at-source-base",
        "integration_source_commit": source_commit,
        "integration_source_sha256": sha256(pinned_integration_blob(path)),
        "expected_final_sha256": content_hash,
        "prepared_sha256": content_hash,
    })
    return content_hash


def prepare_forward_plus_project(previous: dict, changes: list[dict[str, str]]) -> str:
    path = "app/project.godot"
    baseline = pinned_blob(path)
    text = baseline.decode("utf-8")
    expected = replace_once(
        text,
        'renderer/rendering_method="gl_compatibility"',
        'renderer/rendering_method="forward_plus"',
        path,
    )
    expected = replace_once(expected, "[rendering]\n", '[rendering]\n\nstreamline/dlss_preset="K"\n', path)
    # MovieWriter fixes its output size at startup; a 1080p window alone still
    # records the historical 720p viewport. Keep diagnostic movies at the primary target.
    expected = replace_once(expected, "[display]\n", "[display]\n\nwindow/size/viewport_width.movie=1920\nwindow/size/viewport_height.movie=1080\n", path).encode("utf-8")
    target = CANDIDATE / path
    current = target.read_bytes() if target.is_file() else b""
    previous_hash = previous.get("candidate_project_sha256")
    allowed = {sha256(normalized_text(baseline)), sha256(normalized_text(expected))}
    if previous_hash:
        allowed.add(str(previous_hash))
    if current and sha256(current) not in allowed and sha256(normalized_text(current)) not in allowed:
        raise RuntimeError("candidate project.godot has an unexpected edit")
    if b"\r\n" in current and current.count(b"\r\n") == current.count(b"\n"):
        expected = expected.replace(b"\n", b"\r\n")
    if current != expected:
        target.write_bytes(expected)
    changes.append({
        "path": path,
        "base_sha256": sha256(baseline),
        "prepared_sha256": sha256(expected),
        "renderer": "forward_plus",
    })
    return sha256(expected)


def read_receipt() -> dict:
    path = CANDIDATE / RECEIPT_RELATIVE
    if not path.is_file():
        return {}
    try:
        receipt = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("candidate receipt exists but is invalid") from exc
    if receipt.get("format") != RECEIPT_FORMAT or receipt.get("source_base_commit") != BASE_COMMIT:
        raise RuntimeError("candidate receipt does not match the pinned source base")
    return receipt


def main() -> int:
    create_candidate_from_archive()
    base_marker = CANDIDATE / "base-commit.txt"
    if not base_marker.is_file() or base_marker.read_text(encoding="utf-8").strip() != BASE_COMMIT:
        raise RuntimeError(f"candidate must be extracted from exactly {BASE_COMMIT}")

    pinned_generator = pinned_blob(GENERATOR_RELATIVE.as_posix())
    if sha256(pinned_generator) != GENERATOR_SHA256:
        raise RuntimeError("pinned customization generator source hash changed")
    generator_text = pinned_generator.decode("utf-8")
    prepared_generator = replace_once(
        generator_text,
        'PRESENTATION_ENGINE_VERSION = "4.7.2"',
        f'PRESENTATION_ENGINE_VERSION = "{ENGINE_VERSION}"',
        GENERATOR_RELATIVE.as_posix(),
    ).encode("utf-8")

    old_receipt = read_receipt()
    generator_target = CANDIDATE / GENERATOR_RELATIVE
    generator_current = generator_target.read_bytes() if generator_target.is_file() else b""
    if generator_current not in (b"", pinned_generator, prepared_generator):
        raise RuntimeError("candidate generator copy has an unexpected edit")
    generator_target.parent.mkdir(parents=True, exist_ok=True)
    if generator_current != prepared_generator:
        generator_target.write_bytes(prepared_generator)

    changes: list[dict[str, str]] = []
    integration_overlay_hashes: dict[str, str] = {}
    for path in INTEGRATION_OVERLAYS:
        integration_overlay_hashes[path] = apply_integration_overlay(path, old_receipt, changes)
    integration_overlay_records = expected_integration_overlays()
    for path, digest in integration_overlay_hashes.items():
        if integration_overlay_records[path]["expected_final_sha256"] != digest:
            raise RuntimeError(f"prepared integration overlay differs from its pinned hash: {path}")
    candidate_project_sha256 = prepare_forward_plus_project(old_receipt, changes)

    source_changes = {
        "app/render/presentation_sources.gd": pin_line(
            'const ENGINE_VERSION_PIN := "4.7.2"',
            f'const ENGINE_VERSION_PIN := "{ENGINE_VERSION}"',
            "app/render/presentation_sources.gd",
        ),
        "app/workshop/presentation.gd": pin_line(
            'const PRESENTATION_ENGINE_VERSION: String = "4.7.2"',
            f'const PRESENTATION_ENGINE_VERSION: String = "{ENGINE_VERSION}"',
            "app/workshop/presentation.gd",
        ),
        "app/tests/test_aircraft_customization.gd": pin_line(
            'str(bindings.get("presentation_engine_version", "")) == "4.7.2"',
            'str(bindings.get("presentation_engine_version", "")) == PresentationSources.ENGINE_VERSION_PIN',
            "app/tests/test_aircraft_customization.gd",
        ),
        "app/tests/test_smoke_bindings.gd": pin_line(
            '"smoke_slots": slots, "presentation_engine_version": "4.7.2", "presentation_sources": Sources.current_records(2), "slots_sha256": ""',
            '"smoke_slots": slots, "presentation_engine_version": Sources.ENGINE_VERSION_PIN, "presentation_sources": Sources.current_records(2), "slots_sha256": ""',
            "app/tests/test_smoke_bindings.gd",
        ),
        "app/tests/test_workshop_presentation.gd": pin_line(
            '"presentation_engine_version": "4.7.2",',
            '"presentation_engine_version": Profile.PRESENTATION_ENGINE_VERSION,',
            "app/tests/test_workshop_presentation.gd",
        ),
    }
    prepared_sources: dict[str, bytes] = {}
    for path, transform in source_changes.items():
        prepared_sources[path] = prepare_text(path, transform, changes)

    # The only generator inputs allowed to differ from the pinned commit are the
    # two source files whose presentation engine identity was intentionally changed.
    for source_path in (
        "assets/aircraft/customization-bindings.json",
        "assets/aircraft/model-bindings.json",
    ):
        verify_pinned_input(source_path)

    model_source = json.loads((CANDIDATE / "assets/aircraft/model-bindings.json").read_text(encoding="utf-8"))
    families = model_source.get("families", [])
    if not isinstance(families, list) or not families:
        raise RuntimeError("pinned model source registry has no families")
    for family in families:
        family_id = str(family.get("family_id", ""))
        verify_pinned_input(f"app/data/aircraft_models/{family_id}.json")

    generator_source_module = importlib.util.spec_from_file_location("candidate_customization_generator", generator_target)
    if generator_source_module is None or generator_source_module.loader is None:
        raise RuntimeError("cannot load the pinned candidate customization generator")
    generator_module = importlib.util.module_from_spec(generator_source_module)
    generator_source_module.loader.exec_module(generator_module)
    for resource_path in generator_module.PRESENTATION_SOURCE_PATHS:
        relative = "app/" + resource_path.removeprefix("res://")
        verify_pinned_input(relative, prepared_sources.get(relative))

    registry_relative = "app/data/aircraft_customization.json"
    registry_base = pinned_blob(registry_relative)
    registry_target = CANDIDATE / registry_relative
    registry_current = registry_target.read_bytes() if registry_target.is_file() else b""
    expected_previous = old_receipt.get("generated_registry_sha256")
    if normalized_text(registry_current) != normalized_text(registry_base) and sha256(registry_current) != expected_previous:
        raise RuntimeError("candidate generated registry has an unexpected edit")

    subprocess.run(
        [sys.executable, str(generator_target), "--root", str(CANDIDATE)],
        cwd=ROOT,
        check=True,
    )

    registry = json.loads(registry_target.read_text(encoding="utf-8"))
    companions = registry.get("families")
    if not isinstance(companions, list) or not companions:
        raise RuntimeError("candidate generator emitted an empty family registry")
    source_records = None
    for companion in companions:
        if companion.get("presentation_engine_version") != ENGINE_VERSION:
            raise RuntimeError("generated presentation version does not match the candidate engine")
        records = companion.get("presentation_sources")
        if not isinstance(records, list) or not records:
            raise RuntimeError("generated presentation source closure is missing")
        if source_records is None:
            source_records = records
        elif records != source_records:
            raise RuntimeError("family companions have inconsistent presentation source closures")

    generator_target_sha = sha256(prepared_generator)
    changes.insert(0, {
        "path": GENERATOR_RELATIVE.as_posix(),
        "base_sha256": sha256(pinned_generator),
        "prepared_sha256": generator_target_sha,
    })
    changes.append({
        "path": registry_relative,
        "base_sha256": sha256(registry_base),
        "prepared_sha256": sha256(registry_target.read_bytes()),
    })
    receipt = {
        "format": RECEIPT_FORMAT,
        "source_base_commit": BASE_COMMIT,
        "integration_source_commit": INTEGRATION_COMMIT,
        "engine_identity": ENGINE_VERSION,
        "candidate_renderer": "forward_plus",
        "candidate_project_sha256": candidate_project_sha256,
        "integration_overlays": {
            path: {
                **integration_overlay_records[path],
                "prepared_sha256": digest,
            }
            for path, digest in integration_overlay_hashes.items()
        },
        "generator_source_sha256": sha256(pinned_generator),
        "candidate_generator_sha256": generator_target_sha,
        "generated_registry_sha256": sha256(registry_target.read_bytes()),
        "visual_families": [str(item.get("visual_family", "")) for item in companions],
        "presentation_sources": source_records,
        "changes": changes,
    }
    (CANDIDATE / RECEIPT_RELATIVE).write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"prepared candidate from {BASE_COMMIT}: Godot {ENGINE_VERSION}, "
        f"{len(companions)} visual families, registry sha256 {receipt['generated_registry_sha256']}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"candidate preparation failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
