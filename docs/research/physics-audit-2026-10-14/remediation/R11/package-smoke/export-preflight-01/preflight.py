import hashlib
import json
import pathlib
import re
import sys

receipt_path, linux_path, windows_path = map(pathlib.Path, sys.argv[1:])
receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
if not isinstance(receipt, dict) or receipt.get("format") != "openrc-ground-vehicle-native-receipt":
    raise SystemExit("native build receipt is missing or has the wrong format")
if receipt.get("backend") != "native" or type(receipt.get("abi_version")) is not int or receipt["abi_version"] != 1:
    raise SystemExit("native receipt does not identify the supported native ABI")
backend_version = receipt.get("backend_version")
solver_version = receipt.get("solver_version")
if not isinstance(backend_version, str) or not backend_version or not isinstance(solver_version, str) or not solver_version:
    raise SystemExit("native receipt has no backend/solver identity")
platforms = receipt.get("platforms")
if not isinstance(platforms, dict):
    raise SystemExit("native receipt has no platform map")
common = ("backend", "backend_version", "abi_version", "solver_version")
hex64 = re.compile(r"[0-9a-f]{64}\Z")
expected_paths = {"linux": linux_path, "windows": windows_path}
declared_source = receipt.get("source_sha256")
if "source_sha256" in receipt and (not isinstance(declared_source, str) or not hex64.fullmatch(declared_source)):
    raise SystemExit("native receipt has an invalid envelope source_sha256")
source_hash = declared_source if "source_sha256" in receipt else None
verified = {}
for platform, binary_path in expected_paths.items():
    row = platforms.get(platform)
    if not isinstance(row, dict):
        raise SystemExit(f"native receipt lacks the {platform} platform row")
    if row.get("platform") != platform or row.get("architecture") != "x86_64":
        raise SystemExit(f"native {platform} receipt row has the wrong platform/architecture")
    if type(row.get("abi_version")) is not int or row["abi_version"] != 1:
        raise SystemExit(f"native {platform} receipt row has a non-integer or unsupported ABI version")
    for key in common:
        if row.get(key) != receipt.get(key):
            raise SystemExit(f"native {platform} receipt row disagrees with envelope field {key}")
    for key in ("source_sha256", "toolchain_sha256", "binary_sha256"):
        value = row.get(key)
        if not isinstance(value, str) or not hex64.fullmatch(value):
            raise SystemExit(f"native {platform} receipt has an invalid {key}")
    if source_hash is None:
        source_hash = row["source_sha256"]
    elif row["source_sha256"] != source_hash:
        raise SystemExit(f"native {platform} receipt row disagrees with the shared source identity")
    if not isinstance(row.get("toolchain"), dict):
        raise SystemExit(f"native {platform} receipt has no toolchain details")
    if not binary_path.is_file():
        raise SystemExit(f"export omitted required native artifact: {binary_path}")
    actual_hash = hashlib.sha256(binary_path.read_bytes()).hexdigest()
    if actual_hash != row["binary_sha256"]:
        raise SystemExit(f"exported {platform} native artifact differs from its receipt: {binary_path}")
    verified[platform] = {
        "binary": str(binary_path),
        "binary_sha256": actual_hash,
        "toolchain_sha256": row["toolchain_sha256"],
    }
print(json.dumps({
    "format": "openrc-native-export-artifacts-v1",
    "backend": receipt["backend"],
    "backend_version": backend_version,
    "abi_version": receipt["abi_version"],
    "solver_version": solver_version,
    "source_sha256": source_hash,
    "platforms": verified,
}, sort_keys=True))
