#!/usr/bin/env python3
"""Intake the pinned AMD FSR SDK 2.4.0 for a separate Windows/Vulkan trial.

The SDK archive and its complete source tree remain isolated from the existing
engine and runtime. This only downloads, verifies and stages; it does not build,
load or run an AMD binary. Its source archive SHA-256 is a locally measured pin,
not a checksum published by AMD. Run with --offline only after caching the ZIP.

For callers: prepare(cache) returns (source_root, receipt). Preserve the source
tree's relative layout: the upscaler headers include the API headers by path.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import urllib.request
import zipfile


ROOT = Path(__file__).resolve().parents[3]
REPOSITORY = "https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK"
TAG = "v2.4.0"
COMMIT = "7539ae8b6568ad29ed78a753404351daf3b5cca7"
ARCHIVE_NAME = "fidelityfx-sdk-v2.4.0.zip"
ARCHIVE_URL = f"https://codeload.github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/zip/refs/tags/{TAG}"
ARCHIVE_SHA256 = "27120e3bbe0d0b30213825ad40f19077563f04f04572e252109a392d5fb522cb"
ZIP_ROOT = "FidelityFX-SDK-2.4.0/"
STAGE_NAME = "intake-v2.4.0"
# SHA-256 of sorted UTF-8 relative-path + NUL + per-file SHA-256 + newline.
TREE_SHA256 = "3215b1a40247bf042f64c76a846ab495979ba15d26b14e51659f57ac8caf2f9e"
TREE_FILE_COUNT = 943
TREE_SIZE = 337303172

# The SHA-256s are locally measured from the pinned archive. Git blob IDs were
# independently checked against the GitHub tree at COMMIT, not the moving branch.
PINNED_FILES = {
    "3rdpartynotice.md": ("3b69b1a1011622557a81b55a9a211dd797d01b8160924a5ec51b4c3432d33a4f", "1f22c8e3e5900c8dc02fbf6a2567fe1c6343f81a"),
    "docs/license.md": ("410f9c138e766e846acf2dc93db768198def0293a017d7e3296815b451688dbe", "abfeaf46c5aaea767cef4379d2890735dcc66207"),
    "Kits/FidelityFX/docs/license.md": ("32357259b965d6a8001e9e508ba60eda6034027c5923a7d226ffbaff813c2bfb", "aef7adddbcf121c1f7f1248fe97de0f7f7a3d719"),
    "Kits/FidelityFX/api/include/dx12/ffx_api_dx12.h": ("c9afbc3c4c673723e9e5369a666f0ff54560543b5a93537f8ff453bf1c3bf530", "1b711807c597630f4a8d2dfa2572a845c069829a"),
    "Kits/FidelityFX/api/include/dx12/ffx_api_dx12.hpp": ("a4f02dcf86ed5c05f76b3cb83d8b3410f0b8c96f5d6042e48cca30dd25bac7f2", "accebb1943d16c00dcc244fa4044e1d6cfb8d2f4"),
    "Kits/FidelityFX/api/include/ffx_api.h": ("4d9dcf243ef5efbf03340a02f16b51a22053243a22e8a9a0b3ce91c26982b4bf", "d351c168edad86d0f7851bfd8ff5eb77be3667f0"),
    "Kits/FidelityFX/api/include/ffx_api.hpp": ("af441486342abfeb189c5672f3216a28446b582ad314ec4e754b81e20bb8a840", "53879977a9d83853afeda48815d4187fa7ebc9dc"),
    "Kits/FidelityFX/api/include/ffx_api_loader.h": ("18d1901dbbc881e8131b91c65ad44bb3b4a1de6c31435d5b75236f16727ba80e", "ac05ec4bbd5d338643825d81c0ffccd5fbbd1c3e"),
    "Kits/FidelityFX/api/include/ffx_api_matrix_helpers.h": ("f37055b1980562b75295ac0ee3f4b60dd314c8c2f21a41b7d71d9f9070858bd5", "bb8a48231b03571d62c6b4d79381577f1c612cd1"),
    "Kits/FidelityFX/api/include/ffx_api_matrix_helpers.hpp": ("8f671dadf9e1267dd8a51d224e11b27656ddb9da51ef9524a177b89114548737", "901f708e7d32d7b8e08afc3cf4e86fd39922b725"),
    "Kits/FidelityFX/api/include/ffx_api_types.h": ("53f07c113a9ba493f297656e4481b6539aed0afc9f3cc8da682aa477d270c46c", "380c4c0a1bcc7eb9bb4097f1046de886f9f4c587"),
    "Kits/FidelityFX/api/include/vk/ffx_api_vk.h": ("09ac1855bc4c2f711243d6982909385072ca3f8d30db44d1a82ee5bd637832ad", "1bbe1d9e4c6ce1d5253399ced757a9104ea4ac9b"),
    "Kits/FidelityFX/api/include/vk/ffx_api_vk.hpp": ("7757c3ffa6b1e189bca5eec3b8c93aa8f802386642648a0dfeb8c2c52502e5ba", "be91bef567396ae335cfb0961f2fd6ab3bba992c"),
    "Kits/FidelityFX/upscalers/include/ffx_upscale.h": ("13091e7fe5fd9c82b1fb7c044b9f08f664d9653f599d2ea500738709236fca4d", "9d4a3e5f6c60cf601c42bfb9953c6e1a1a481891"),
    "Kits/FidelityFX/upscalers/include/ffx_upscale.hpp": ("52066379fd629080ed5c9a2821627cd7a3b972e6592565c7f3fa54a95404bac0", "602687f7203f04c11083dbe3cf6befe848d7868a"),
    "Kits/FidelityFX/signedbin/amd_fidelityfx_loader_vk.dll": ("38a56a01fb3565c0757d9f5c1e4e69de4b65e5f2e5769b323b200dc1f142bab9", "fb9877780927cd41ee0a25d5cd9314da118ddd27"),
    "Kits/FidelityFX/signedbin/amd_fidelityfx_loader_vk.lib": ("7f0b0186c7c207779bee56f44ee6a7881b9c6ebb32038a95e8b960ccce9b3689", "ea43707b1610af9606bc686f4aaaf7a4db4cf2e2"),
    "Kits/FidelityFX/signedbin/amd_fidelityfx_upscaler_vk.dll": ("4a7e895af6e0b615d40a84d59eb8c2b1054ad91cdd0c739567940270d51bdab7", "9e2fade37c51fc2fd6323218bf3d736969e9dd2a"),
}
SIGNED_DLLS = (
    "Kits/FidelityFX/signedbin/amd_fidelityfx_loader_vk.dll",
    "Kits/FidelityFX/signedbin/amd_fidelityfx_upscaler_vk.dll",
)
SIGNER = "33D35682079E201671B738B7209B4586103BC271"
TIMESTAMP_SIGNER = "51D9ABDA034973D84F4266ACA48248E6B369C439"
SIGNER_SUBJECT = "CN=Advanced Micro Devices, O=Advanced Micro Devices, S=California, C=US"


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_tag() -> None:
    """Check the live lightweight tag, rejecting a moved or unavailable tag."""
    try:
        result = subprocess.run(
            ["git", "ls-remote", "--refs", REPOSITORY, f"refs/tags/{TAG}"],
            check=True, capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise RuntimeError(f"Cannot verify upstream {TAG}: {error}") from error
    if result.stdout.strip() != f"{COMMIT}\trefs/tags/{TAG}":
        raise RuntimeError(f"Upstream {TAG} does not resolve to the pinned commit: {result.stdout.strip()!r}")


def fetch(cache: Path, *, offline: bool = False) -> Path:
    """Fetch into a new cache entry; never replace a mismatched cached archive."""
    archive = cache / ARCHIVE_NAME
    if not archive.exists():
        if offline:
            raise RuntimeError(f"Offline SDK archive is missing: {archive}")
        cache.mkdir(parents=True, exist_ok=True)
        # A unique temporary file avoids consuming or overwriting another run's work.
        handle, name = tempfile.mkstemp(prefix="sdk24-download-", suffix=".tmp", dir=cache)
        temporary = Path(name)
        try:
            print(f"Downloading {ARCHIVE_URL}", flush=True)
            request = urllib.request.Request(ARCHIVE_URL, headers={"User-Agent": "OpenRC-SDK24-intake"})
            with os.fdopen(handle, "wb") as target, urllib.request.urlopen(request, timeout=120) as response:
                shutil.copyfileobj(response, target)
            if sha256(temporary) != ARCHIVE_SHA256:
                raise RuntimeError(f"SDK archive SHA-256 mismatch: {temporary}")
            # link is atomic and fails if another process has already populated it.
            try:
                os.link(temporary, archive)
            except FileExistsError:
                pass
        finally:
            temporary.unlink(missing_ok=True)
    if not archive.is_file() or archive.is_symlink() or sha256(archive) != ARCHIVE_SHA256:
        raise RuntimeError(f"SDK archive SHA-256 mismatch or unsafe cache entry: {archive}")
    return archive


def _archive_files(package: zipfile.ZipFile) -> list[zipfile.ZipInfo]:
    """Reject traversal, aliases and special entries before writing any member."""
    seen: set[str] = set()
    files = []
    for entry in package.infolist():
        name = entry.filename
        parts = name.rstrip("/").split("/")
        if (not name.startswith(ZIP_ROOT) or "\\" in name or ":" in name or
                any(part in ("", ".", "..") or part.endswith((".", " ")) for part in parts)):
            raise RuntimeError(f"Unsafe archive member: {name}")
        folded = name.rstrip("/").casefold()
        if folded in seen:
            raise RuntimeError(f"Duplicate archive member: {name}")
        seen.add(folded)
        mode = entry.external_attr >> 16
        if stat.S_ISLNK(mode) or (stat.S_IFMT(mode) and not (stat.S_ISREG(mode) or stat.S_ISDIR(mode))):
            raise RuntimeError(f"Special archive member: {name}")
        if not entry.is_dir():
            files.append(entry)
    if len(files) != TREE_FILE_COUNT or sum(entry.file_size for entry in files) != TREE_SIZE:
        raise RuntimeError("SDK archive file count or uncompressed size mismatch")
    return files


def _unsafe_link(path: Path) -> bool:
    # Windows junctions and other reparse points must not redirect validation.
    info = path.lstat()
    attributes = getattr(info, "st_file_attributes", 0)
    return stat.S_ISLNK(info.st_mode) or bool(attributes & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))


def verify_tree(source: Path) -> dict[str, dict[str, str]]:
    """Verify every staged file against a pinned canonical tree and key Git blobs."""
    if not source.is_dir() or _unsafe_link(source):
        raise RuntimeError(f"Missing or unsafe SDK source tree: {source}")
    files: list[Path] = []
    for directory, dirs, names in os.walk(source, followlinks=False):
        for name in dirs + names:
            entry = Path(directory) / name
            if _unsafe_link(entry):
                raise RuntimeError(f"Unsafe SDK cache entry: {entry}")
        for name in names:
            entry = Path(directory) / name
            if not entry.is_file():
                raise RuntimeError(f"Non-file SDK cache entry: {entry}")
            files.append(entry)
    files.sort(key=lambda path: path.relative_to(source).as_posix())
    if len(files) != TREE_FILE_COUNT or sum(path.stat().st_size for path in files) != TREE_SIZE:
        raise RuntimeError("SDK staged file count or size mismatch; use a fresh cache")
    tree_hash = hashlib.sha256()
    checked = {}
    for path in files:
        rel = path.relative_to(source).as_posix()
        digest = sha256(path)
        tree_hash.update((rel + "\0" + digest + "\n").encode("utf-8"))
        if rel in PINNED_FILES:
            size = path.stat().st_size
            blob = hashlib.sha1(f"blob {size}\0".encode("ascii"))
            with path.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    blob.update(block)
            expected_digest, expected_blob = PINNED_FILES[rel]
            if digest != expected_digest or blob.hexdigest() != expected_blob:
                raise RuntimeError(f"SDK file pin mismatch: {rel}")
            checked[rel] = {"sha256": digest, "git_blob_sha1": blob.hexdigest()}
    if tree_hash.hexdigest() != TREE_SHA256 or set(checked) != set(PINNED_FILES):
        raise RuntimeError("SDK staged tree hash or required files mismatch; use a fresh cache")
    return checked


def verify_signature(path: Path) -> dict[str, str]:
    """Require Windows trust verification and the observed AMD/timestamp signers."""
    if os.name != "nt":
        raise RuntimeError("Authenticode verification of the SDK requires Windows")
    script = (
        # A PowerShell 7 parent can put its incompatible Security module first
        # in PSModulePath. Import the Windows PowerShell module explicitly.
        'Import-Module "$env:SystemRoot\\System32\\WindowsPowerShell\\v1.0\\Modules\\'
        'Microsoft.PowerShell.Security\\Microsoft.PowerShell.Security.psd1" -ErrorAction Stop; '
        "$s = Get-AuthenticodeSignature -LiteralPath $env:OPENRC_SDK24_SIGNATURE_FILE; "
        "@{status=$s.Status.ToString(); type=$s.SignatureType.ToString(); "
        "subject=$s.SignerCertificate.Subject; signer=$s.SignerCertificate.Thumbprint; "
        "timestamp_signer=$s.TimeStamperCertificate.Thumbprint} | ConvertTo-Json -Compress"
    )
    env = dict(os.environ, OPENRC_SDK24_SIGNATURE_FILE=str(path))
    try:
        result = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script],
                                check=True, capture_output=True, text=True, env=env, timeout=60)
        signature = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        detail = getattr(error, "stderr", "") or str(error)
        raise RuntimeError(f"Cannot verify Authenticode signature: {path}: {detail}") from error
    expected = {"status": "Valid", "type": "Authenticode", "subject": SIGNER_SUBJECT,
                "signer": SIGNER, "timestamp_signer": TIMESTAMP_SIGNER}
    if signature != expected:
        raise RuntimeError(f"Invalid or unexpected Authenticode signature: {path}: {signature}")
    return signature


def _receipt(files: dict, signatures: dict, tag_check: dict) -> dict:
    return {
        "schema": "openrc-fsr-sdk24-intake-v1",
        "sdk_version": "2.4.0", "tag": TAG, "commit": COMMIT,
        "release": f"{REPOSITORY}/releases/tag/{TAG}",
        "archive": {"url": ARCHIVE_URL, "sha256": ARCHIVE_SHA256,
                    "checksum_origin": "locally measured, not published by AMD"},
        "tag_check": tag_check,
        "source_tree": {"directory": "source", "sha256": TREE_SHA256,
                        "file_count": TREE_FILE_COUNT, "size_bytes": TREE_SIZE},
        "pinned_files": files,
        "authenticode": signatures,
        "release_reported_components": {"ml_upscale": "4.1.2", "analytical_upscale": "3.1.6",
                                        "ml_frame_generation": "4.0.2", "analytical_frame_generation": "3.1.6",
                                        "ml_swapchain": "4.0.0", "analytical_swapchain": "3.1.7"},
        "scope": "source and signed Windows/Vulkan binaries only; no build, provider query or GPU test",
    }


def _read_receipt(stage: Path, files: dict, signatures: dict) -> dict:
    try:
        receipt = json.loads((stage / "receipt.json").read_text(encoding="utf-8"))
        tag_check = receipt["tag_check"]
        if (not isinstance(tag_check, dict) or set(tag_check) != {"live", "checked_utc"} or
                type(tag_check["live"]) is not bool or
                (tag_check["live"] and not isinstance(tag_check["checked_utc"], str)) or
                (not tag_check["live"] and tag_check["checked_utc"] is not None) or
                receipt != _receipt(files, signatures, tag_check)):
            raise ValueError("receipt differs from verified inputs")
        if tag_check["live"] and datetime.fromisoformat(tag_check["checked_utc"]).utcoffset() is None:
            raise ValueError("tag check timestamp has no UTC offset")
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise RuntimeError(f"Invalid or missing SDK intake receipt: {stage / 'receipt.json'}") from error
    return receipt


def prepare(cache: Path, *, offline: bool = False) -> tuple[Path, dict]:
    """Return the immutable verified SDK source tree and its intake receipt."""
    cache = Path(cache).resolve()
    cache.mkdir(parents=True, exist_ok=True)
    tag_check = {"live": False, "checked_utc": None}
    if not offline:
        verify_tag()
        tag_check = {"live": True, "checked_utc": datetime.now(timezone.utc).isoformat()}
    archive = fetch(cache, offline=offline)
    stage = cache / STAGE_NAME
    if stage.exists():
        if not stage.is_dir() or _unsafe_link(stage):
            raise RuntimeError(f"Unsafe SDK stage: {stage}")
        source = stage / "source"
        files = verify_tree(source)
        signatures = {name: verify_signature(source / name) for name in SIGNED_DLLS}
        return source, _read_receipt(stage, files, signatures)
    with tempfile.TemporaryDirectory(prefix="sdk24-stage-", dir=cache) as temporary:
        work = Path(temporary)
        source = work / "source"
        source.mkdir()
        with zipfile.ZipFile(archive) as package:
            entries = _archive_files(package)
            for entry in entries:
                target = source / entry.filename[len(ZIP_ROOT):]
                target.parent.mkdir(parents=True, exist_ok=True)
                with package.open(entry) as inp, target.open("xb") as out:
                    shutil.copyfileobj(inp, out)
        files = verify_tree(source)
        signatures = {name: verify_signature(source / name) for name in SIGNED_DLLS}
        receipt = _receipt(files, signatures, tag_check)
        (work / "receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        # This rename fails instead of replacing an existing stage on Windows.
        work.rename(stage)
    return stage / "source", receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / ".tools/advanced-rendering-sdk24-intake")
    parser.add_argument("--offline", action="store_true", help="use an existing pinned ZIP without checking the live tag")
    args = parser.parse_args()
    source, receipt = prepare(args.cache, offline=args.offline)
    print(f"Verified SDK source: {source}")
    print(f"Receipt: {source.parent / 'receipt.json'}")
    print(f"Tag verified online during this run: {not args.offline}; original receipt: {receipt['tag_check']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
