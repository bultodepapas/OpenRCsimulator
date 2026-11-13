#!/usr/bin/env python3
"""Build the experimental NK-3 evaluator on native Apple Silicon.

Every candidate uses a fresh variant workspace beneath --tool-root, with its own
godot-cpp checkout.  The signed dylib and its evidence are research outputs;
building them does not qualify or install the native backend.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPEC = importlib.util.spec_from_file_location("openrc_native_kernel_build", HERE / "build.py")
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Cannot load the native kernel builder")
nk = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(nk)
locked = nk.locked

# The observed M1 toolchain; changing any member requires new qualification.
APPLE_CLANG = "Apple clang version 21.0.0 (clang-2100.3.34.2)"
SDK_VERSION = "27.0"
# 11.0 is the first macOS release supporting Apple Silicon. This is a build
# floor, not a claim that the resulting evaluator is qualified on macOS 11.
DEPLOYMENT_TARGET = "11.0"
FORMAT = "openrc-native-kernel-macos-research-build v1"
SOURCE_SCOPE = "macos-arm64-fixed-wing-experimental-v1"
SOURCE_DESCRIPTOR = (
    "; DT-MAC native stage, installed by research/native-kernel/build_macos.py --install-app.\n"
    "; .gdignore prevents discovery; app/sim/native_stage.gd loads it after receipt checks.\n"
    "[configuration]\n"
    f'entry_symbol = "{nk.NAME}_library_init"\n'
    'compatibility_minimum = "4.7"\n'
    "reloadable = false\n\n"
    "[libraries]\n"
    f'macos.arm64 = "res://native/kernel/lib{nk.NAME}.dylib"\n'
)
MATH_NAMES = nk.LIBM_SYMBOLS | {"ceil", "exp2", "hypot", "log10", "log2", "round", "trunc"}
STRICT_FLAGS = ["-fno-fast-math", "-ffp-contract=off", "-fno-builtin", "-fno-builtin-sin",
                "-fno-builtin-cos", "-fexceptions", "-fno-lto", "-std=c++17"]
UNSAFE_FLAGS = {"-ffast-math", "-Ofast", "-funsafe-math-optimizations", "-fassociative-math",
                "-freciprocal-math", "-ffinite-math-only", "-fno-signed-zeros", "-fno-trapping-math",
                "-fbuiltin", "-fbuiltin-sin", "-fbuiltin-cos"}


def signing_selection(identity: str | None, team_id: str | None) -> dict:
    """Never resolve certificate names or accept an incomplete Developer ID selection."""
    if identity is None and team_id is None:
        return {"kind": "ad-hoc"}
    if not isinstance(identity, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", identity):
        raise ValueError("--signing-identity must be an exact 40-hex certificate SHA-1 fingerprint")
    if not isinstance(team_id, str) or not re.fullmatch(r"[A-Z0-9]{10}", team_id):
        raise ValueError("--team-id is required and must be 10 uppercase letters or digits")
    return {"kind": "developer-id-application", "identity_sha1": identity.upper(), "team_id": team_id}


def _developer_authority(authority: object, team_id: str) -> bool:
    prefix, suffix = "Developer ID Application: ", f" ({team_id})"
    return (isinstance(authority, str) and authority.startswith(prefix) and authority.endswith(suffix)
            and len(authority) > len(prefix) + len(suffix)
            and not any(char in authority for char in '\r\n"'))


def resolve_signing_identity(selection: dict) -> dict:
    """Confirm one usable local Developer ID Application identity without changing the keychain."""
    if selection == {"kind": "ad-hoc"}:
        return selection
    selected = signing_selection(selection.get("identity_sha1"), selection.get("team_id"))
    if selected != selection:
        raise ValueError("Unexpected signing selection")
    output = subprocess.run(["security", "find-identity", "-p", "codesigning", "-v"], check=True,
                            text=True, capture_output=True).stdout
    rows = re.findall(r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"([^"\r\n]+)"\s*$', output, flags=re.MULTILINE)
    matches = [name for digest, name in rows if digest.upper() == selected["identity_sha1"]]
    if len(matches) != 1 or not _developer_authority(matches[0], selected["team_id"]):
        raise ValueError("Selected signing identity is absent, ambiguous, wrong-team or not Developer ID Application")
    return {**selected, "authority": matches[0]}


def _developer_requirement(selection: dict) -> str:
    """Require Apple's Developer ID Application chain, Team ID and exact signing certificate."""
    checked = signing_selection(selection.get("identity_sha1"), selection.get("team_id"))
    if selection.get("kind") != checked["kind"]:
        raise ValueError("Unexpected Developer ID signing kind")
    return ('=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists '
            'and certificate leaf[field.1.2.840.113635.100.6.1.13] exists '
            f'and certificate leaf[subject.OU] = "{checked["team_id"]}" '
            f'and certificate leaf = H"{checked["identity_sha1"]}"')


def _developer_signature_metadata(details: str, selection: dict) -> dict:
    if not isinstance(details, str) or not _developer_authority(selection.get("authority"), selection["team_id"]):
        raise ValueError("Missing Developer ID signature metadata")
    lines = [line.strip() for line in details.splitlines()]
    authorities = [line.removeprefix("Authority=") for line in lines if line.startswith("Authority=")]
    teams = [line.removeprefix("TeamIdentifier=") for line in lines if line.startswith("TeamIdentifier=")]
    timestamps = [line.removeprefix("Timestamp=") for line in lines if line.startswith("Timestamp=")]
    if (len(authorities) < 2 or authorities[0] != selection["authority"] or teams != [selection["team_id"]]
            or len(timestamps) != 1 or not timestamps[0].strip() or timestamps[0].strip().lower() == "none"
            or any(re.fullmatch(r"Signature\s*=\s*adhoc", line, flags=re.IGNORECASE) for line in lines)):
        raise ValueError("Dylib signature metadata has the wrong authority, team or secure timestamp")
    return {"authorities": authorities, "timestamp": timestamps[0]}


def _signing_record_selection(signing: object) -> dict:
    if not isinstance(signing, dict) or signing.get("verified") is not True or signing.get("notarized") is not False:
        raise ValueError("Missing or invalid dylib signing receipt")
    if signing.get("kind") == "ad-hoc":
        if set(signing) != {"kind", "verified", "details", "notarized"} or not isinstance(signing.get("details"), str) \
                or "adhoc" not in signing["details"].lower():
            raise ValueError("Invalid ad-hoc signing receipt")
        return {"kind": "ad-hoc"}
    if signing.get("kind") != "developer-id-application":
        raise ValueError("Unsupported dylib signing kind")
    selection = signing_selection(signing.get("identity_sha1"), signing.get("team_id"))
    if signing.get("identity_sha1") != selection["identity_sha1"]:
        raise ValueError("Developer ID fingerprint is not in canonical form")
    selection["authority"] = signing.get("authority")
    if set(signing) != {"kind", "identity_sha1", "team_id", "authority", "authorities", "timestamp",
                        "requirement", "verified", "details", "notarized"}:
        raise ValueError("Invalid Developer ID signing receipt fields")
    observed = _developer_signature_metadata(signing.get("details"), selection)
    if (signing.get("authorities") != observed["authorities"] or signing.get("timestamp") != observed["timestamp"]
            or signing.get("requirement") != _developer_requirement(selection)):
        raise ValueError("Developer ID signing receipt metadata differs")
    return selection


def validate_signing_pair(candidate: dict, mutant: dict) -> None:
    """Require one immutable signing selection for candidate and negative control."""
    if not isinstance(candidate, dict) or not isinstance(mutant, dict):
        raise ValueError("Missing candidate or mutant signing receipt")
    if _signing_record_selection(candidate.get("signing")) != _signing_record_selection(mutant.get("signing")):
        raise ValueError("Candidate and mutant must use the same signing selection")


def inspect_signing(library: Path, selection: dict, *, env: dict[str, str] | None = None) -> dict:
    """Verify actual signed bytes and retain the selected signing identity and metadata."""
    if selection.get("kind") == "developer-id-application" and env is None:
        env = dict(os.environ, LC_ALL="C")
    subprocess.run(["codesign", "--verify", "--strict", str(library)], check=True, env=env)
    if selection.get("kind") == "developer-id-application":
        requirement = _developer_requirement(selection)
        subprocess.run(["codesign", "--verify", "--strict", "-R", requirement, str(library)], check=True, env=env)
    elif selection != {"kind": "ad-hoc"}:
        raise ValueError("Unexpected signing selection")
    signature = subprocess.run(["codesign", "-dv", "--verbose=4", str(library)], check=True, text=True,
                               capture_output=True, env=env).stderr.strip()
    if selection == {"kind": "ad-hoc"}:
        if "adhoc" not in signature.lower():
            raise ValueError("The dylib does not report an ad-hoc signature")
        return {"kind": "ad-hoc", "verified": True, "details": signature, "notarized": False}
    metadata = _developer_signature_metadata(signature, selection)
    return {**selection, **metadata, "requirement": requirement, "verified": True,
            "details": signature, "notarized": False}


def _output(command: list[str], *, env: dict[str, str] | None = None) -> str:
    return subprocess.run(command, check=True, text=True, capture_output=True, env=env).stdout.strip()


def _version(value: str) -> tuple[int, ...]:
    if not re.fullmatch(r"\d+(?:\.\d+)*", value):
        raise ValueError(f"Malformed version: {value!r}")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * max(0, 3 - len(parts))


def _write_json(path: Path, value: object) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as output:
        json.dump(value, output, indent=2, sort_keys=True, allow_nan=False)
        output.write("\n")


def clean_build_environment(compiler: Path, sdk: Path) -> dict[str, str]:
    """Remove ambient flags and loader injection; retain the selected developer directory."""
    env = os.environ.copy()
    for name in list(env):
        if name in {"CC", "CXX", "CFLAGS", "CXXFLAGS", "CPPFLAGS", "LDFLAGS", "CPATH",
                    "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "LIBRARY_PATH", "SDKROOT",
                    "MACOSX_DEPLOYMENT_TARGET", "PKG_CONFIG_PATH"} or name.startswith("DYLD_"):
            env.pop(name, None)
    env.update(CC=str(compiler.with_name("clang")), CXX=str(compiler), SDKROOT=str(sdk),
               MACOSX_DEPLOYMENT_TARGET=DEPLOYMENT_TARGET, LC_ALL="C")
    env["PATH"] = str(compiler.parent) + os.pathsep + env.get("PATH", "")
    return env


def host_toolchain() -> dict:
    """Fail before building on Rosetta, a different compiler, SDK, or missing libc++ headers."""
    if locked.host_platform_name() != "macos" or locked.host_arch_name() != "arm64":
        raise ValueError("build_macos.py requires a native macOS ARM64 host")
    translated = _output(["sysctl", "-in", "sysctl.proc_translated"])
    if translated != "0":
        raise ValueError(f"Rosetta state must be explicitly native (0), got {translated!r}")
    sdk = Path(_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"])).resolve()
    sdk_version = _output(["xcrun", "--sdk", "macosx", "--show-sdk-version"])
    # Do not resolve the driver symlink: clang and clang++ may be the same
    # binary, but argv[0] selects different driver and C++ linkage behavior.
    compiler = Path(os.path.abspath(_output(["xcrun", "--sdk", "macosx", "--find", "clang++"])))
    c_compiler = Path(os.path.abspath(_output(["xcrun", "--sdk", "macosx", "--find", "clang"])))
    version = _output([str(compiler), "--version"]).splitlines()[0]
    target = _output([str(compiler), "-dumpmachine"])
    headers = sdk / "usr/include/c++/v1"
    if version != APPLE_CLANG or sdk_version != SDK_VERSION or not target.startswith("arm64-apple-darwin"):
        raise ValueError(f"Unpinned Apple toolchain: {version}, SDK {sdk_version}, target {target}")
    if not compiler.is_file() or not c_compiler.is_file() or not (headers / "vector").is_file():
        raise ValueError(f"Compiler or SDK libc++ headers are missing (expected {headers})")
    # The C and C++ drivers must come from the same selected toolchain.
    if c_compiler.parent != compiler.parent:
        raise ValueError("clang and clang++ resolve to different toolchains")
    settings = sdk / "SDKSettings.json"
    return {"compiler": str(compiler), "compiler_sha256": nk.sha256_file(compiler),
            "c_compiler": str(c_compiler), "c_compiler_sha256": nk.sha256_file(c_compiler),
            "compiler_version": version, "target": target, "sdk_path": str(sdk),
            "sdk_version": sdk_version, "sdk_settings_sha256": nk.sha256_file(settings) if settings.is_file() else None,
            "libcxx_headers": str(headers), "deployment_target": DEPLOYMENT_TARGET,
            "developer_directory": os.environ.get("DEVELOPER_DIR"),
            "xcode_select": _output(["xcode-select", "-p"]),
            "os_version": _output(["sw_vers", "-productVersion"]),
            "os_build": _output(["sw_vers", "-buildVersion"]), "translated": False}


def architectures(binary: Path) -> list[str]:
    result = _output(["xcrun", "lipo", "-archs", str(binary)]).split()
    if not result or len(result) != len(set(result)):
        raise ValueError(f"Could not identify distinct Mach-O slices: {binary}")
    return sorted(result)


def godot_identity(godot: Path, lock: dict) -> dict:
    """Identify the exact executable; a matching version alone is not release provenance."""
    godot = godot.resolve()
    if not godot.is_file() or not os.access(godot, os.X_OK):
        raise ValueError(f"--godot must name an executable file: {godot}")
    slices = architectures(godot)
    if "arm64" not in slices:
        raise ValueError(f"Godot lacks an ARM64 slice: {slices}")
    digest = nk.sha256_file(godot)
    version = _output([str(godot), "--version"])
    if version != lock["godot"]["version"] or nk.sha256_file(godot) != digest:
        raise ValueError(f"Godot version/identity changed or is not pinned: {version}")
    return {"path": str(godot), "version": version, "sha256": digest, "architectures": slices}


def _common_flags(sdk: Path) -> list[str]:
    return [*STRICT_FLAGS, "-arch", "arm64", "-isysroot", str(sdk), "-isystem",
            str(sdk / "usr/include/c++/v1"), f"-mmacosx-version-min={DEPLOYMENT_TARGET}"]


def preflight(toolchain: dict, work: Path, env: dict[str, str]) -> dict:
    """Compile, link and execute a C++/libc++ witness before the expensive build."""
    source = work / "compiler-preflight.cpp"
    source.write_text("#include <cmath>\n#include <vector>\n"
                      "int main() { std::vector<double> x{0.25}; return std::sin(x[0]) == 0.0; }\n",
                      encoding="utf-8")
    binary = work / "compiler-preflight"
    command = [toolchain["compiler"], *_common_flags(Path(toolchain["sdk_path"])), str(source), "-o", str(binary)]
    with (work / "compiler-preflight.log").open("x", encoding="utf-8") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, text=True, env=env)
    if result.returncode:
        raise ValueError(f"Compiler/libc++ preflight failed: {work / 'compiler-preflight.log'}")
    if architectures(binary) != ["arm64"]:
        raise ValueError("Compiler preflight did not produce a single ARM64 slice")
    subprocess.run([str(binary)], check=True, env=env)
    return {"command": command, "source_sha256": nk.sha256_file(source), "binary_sha256": nk.sha256_file(binary)}


def make_sconstruct(godot_cpp: Path, work: Path, profile: Path, lock: dict, flags: list[str],
                    compiler: Path, library_name: str) -> str:
    script = locked.sconstruct_text(godot_cpp, locked.SOURCES, work / "lib", profile,
                                    lock["godot"]["extension_api"])
    before = 'env["build_profile"] = profile_path'
    after = 'env.Append(CPPPATH=[source_dir])'
    if any(script.count(anchor) != 1 for anchor in (before, after, "openrc_slipstream")):
        raise ValueError("Shared SConstruct template changed; update the macOS adapter")
    # Add flags before SConscript for bindings, then after it for the extension,
    # so the template's own -ffp-model setting cannot override -ffp-contract=off.
    settings = (f'\nenv["CC"] = {str(compiler.with_name("clang"))!r}'
                f'\nenv["CXX"] = {str(compiler)!r}\nenv.Append(CCFLAGS={flags!r})')
    link_flags = ["-fno-lto", "-arch", "arm64", "-isysroot", str(Path(lock["_sdk_path"])),
                  f"-mmacosx-version-min={DEPLOYMENT_TARGET}",
                  f"-Wl,-install_name,@rpath/lib{library_name}.dylib"]
    script = script.replace(before, before + settings)
    script = script.replace(after, settings.lstrip("\n") + f"\nenv.Append(LINKFLAGS={link_flags!r})\n" + after)
    return script.replace("openrc_slipstream", library_name)


def _args(entry: dict) -> list[str]:
    args = entry.get("arguments")
    if args is None and isinstance(entry.get("command"), str):
        args = shlex.split(entry["command"])
    if not isinstance(args, list) or not args or any(not isinstance(arg, str) for arg in args):
        raise ValueError("Malformed compilation command")
    return args


def _last_option(args: list[str], option: str) -> str | None:
    values = [args[i + 1] for i, value in enumerate(args[:-1]) if value == option]
    return values[-1] if values else None


def _check_target_flags(args: list[str], sdk: Path) -> None:
    arches = [args[i + 1] for i, value in enumerate(args[:-1]) if value == "-arch"]
    roots = [args[i + 1] for i, value in enumerate(args[:-1]) if value == "-isysroot"]
    floors = [arg.split("=", 1)[1] for arg in args if arg.startswith("-mmacosx-version-min=")]
    if not arches or set(arches) != {"arm64"} or not roots or Path(roots[-1]).resolve() != sdk.resolve():
        raise ValueError("Compilation/link command has an unexpected architecture or SDK")
    if not floors or _version(floors[-1]) != _version(DEPLOYMENT_TARGET):
        raise ValueError("Compilation/link command has an unexpected deployment target")
    if "-fno-lto" not in args or any(arg == "-flto" or arg.startswith("-flto=") for arg in args):
        raise ValueError("Compilation/link command enables or does not explicitly disable LTO")


def validate_compdb(path: Path, compiler: Path, sdk: Path, env: dict[str, str]) -> dict:
    entries = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(entries, list) or not entries:
        raise ValueError("Compilation database is empty or malformed")
    expected = {path.resolve() for path in locked.SOURCES.glob("*.cpp")}
    seen: set[Path] = set()
    for row in entries:
        if not isinstance(row, dict) or not isinstance(row.get("directory"), str) or not isinstance(row.get("file"), str):
            raise ValueError("Malformed compilation database entry")
        args = _args(row)
        command = Path(args[0]) if os.path.isabs(args[0]) else Path(shutil.which(args[0], path=env["PATH"]) or "")
        if command.absolute() != compiler.absolute():
            raise ValueError(f"Compilation used a different C++ compiler: {args[0]}")
        if any(flag not in args for flag in STRICT_FLAGS) or any(arg in UNSAFE_FLAGS for arg in args):
            raise ValueError("Compilation is missing strict flags or contains unsafe flags")
        # godot-cpp can emit its default -fno-exceptions before our policy.
        # Clang applies the last exception option; reject an effective disable,
        # rather than rejecting an earlier option which is explicitly overridden.
        exceptions = [arg for arg in args if arg in {"-fexceptions", "-fno-exceptions"}]
        if not exceptions or exceptions[-1] != "-fexceptions":
            raise ValueError("Compilation disables the required exception support")
        for prefix, expected_flag in (("-std=", "-std=c++17"), ("-ffp-contract=", "-ffp-contract=off")):
            matching = [arg for arg in args if arg.startswith(prefix)]
            if not matching or matching[-1] != expected_flag:
                raise ValueError(f"Compilation overrides {expected_flag}")
        if any(arg.startswith("-ffp-model=") and arg != "-ffp-model=strict" for arg in args):
            raise ValueError("Compilation uses an unqualified floating-point model")
        if any("REAL_T_IS_DOUBLE" in arg for arg in args):
            raise ValueError("Bindings must use the single-precision Godot real_t ABI")
        headers = str(sdk / "usr/include/c++/v1")
        if not any(arg == "-isystem" and i + 1 < len(args) and args[i + 1] == headers
                   for i, arg in enumerate(args)):
            raise ValueError("Compilation omits the selected SDK libc++ header path")
        _check_target_flags(args, sdk)
        source = (Path(row["directory"]) / row["file"]).resolve()
        if source in seen:
            raise ValueError(f"Repeated compilation database entry: {source}")
        seen.add(source)
    if not expected or not expected.issubset(seen):
        raise ValueError(f"Compilation database misses native translation units: {sorted(expected - seen)}")
    return {"entries": len(entries), "native_translation_units": len(expected), "sha256": nk.sha256_file(path)}


def validate_link_command(log: Path, library: Path, sdk: Path, compiler: Path, env: dict[str, str]) -> list[str]:
    matches = []
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            args = shlex.split(line)
        except ValueError:
            continue
        if not args or "-o" not in args:
            continue
        output = _last_option(args, "-o")
        if output and Path(output).name == library.name:
            matches.append(args)
    if len(matches) != 1:
        raise ValueError("Build log does not contain exactly one final dylib link command")
    args = matches[0]
    driver = Path(args[0]) if os.path.isabs(args[0]) else Path(shutil.which(args[0], path=env["PATH"]) or "")
    if driver.absolute() != compiler.absolute():
        raise ValueError("Dylib was linked with an unexpected compiler")
    _check_target_flags(args, sdk)
    if f"-Wl,-install_name,@rpath/{library.name}" not in args:
        raise ValueError("Dylib link command has an unexpected install name")
    return args


def undefined_symbols(binary: Path) -> list[str]:
    output = _output(["xcrun", "nm", "-u", str(binary)])
    symbols = []
    for line in output.splitlines():
        line = line.strip()
        if not line:
            continue
        # Apple nm -u emits names only; LLVM/BSD variants can retain the U
        # column. The library is a single inspected slice, so headers or other
        # unrecognized records are failures rather than silently skipped data.
        match = re.fullmatch(r"(?:U\s+)?([A-Za-z_.$][A-Za-z0-9_.$]*)", line)
        if not match:
            raise ValueError(f"Malformed undefined-symbol record: {line!r}")
        symbols.append(match[1])
    if not symbols:
        raise ValueError(f"No undefined symbols found in {binary}")
    return sorted(set(symbols))


def math_imports(symbols: list[str]) -> list[str]:
    return sorted(symbol for symbol in symbols if symbol.removeprefix("_") in MATH_NAMES
                  or "sincos" in symbol.lower())


def dependencies(binary: Path) -> list[str]:
    lines = _output(["xcrun", "otool", "-L", str(binary)]).splitlines()
    if len(lines) < 2 or not lines[0].endswith(":"):
        raise ValueError(f"Malformed Mach-O dependencies for {binary}")
    return [line.strip().split(" (", 1)[0] for line in lines[1:]]


def uuid_map(binary: Path) -> dict[str, str]:
    result = {}
    for line in _output(["xcrun", "dwarfdump", "--uuid", str(binary)]).splitlines():
        match = re.match(r"UUID: ([0-9A-Fa-f-]+) \(([^)]+)\)", line)
        if not match or match[2] in result:
            raise ValueError(f"Malformed or duplicate Mach-O UUID: {line}")
        result[match[2]] = match[1].upper()
    if not result:
        raise ValueError(f"Missing Mach-O UUID: {binary}")
    return result


def build_version(load_commands: str) -> dict:
    blocks = re.split(r"(?=\s*Load command \d+\n)", load_commands)
    found = []
    for block in blocks:
        if re.search(r"\bcmd LC_BUILD_VERSION\b", block):
            platform = re.search(r"\bplatform\s+(\S+)", block)
            minimum = re.search(r"\bminos\s+(\S+)", block)
            sdk = re.search(r"\bsdk\s+(\S+)", block)
            if not platform or not minimum or not sdk:
                raise ValueError("Malformed LC_BUILD_VERSION")
            found.append({"platform": platform[1], "minimum_os": minimum[1], "sdk": sdk[1]})
    if len(found) != 1 or found[0]["platform"] not in {"MACOS", "1"}:
        raise ValueError("Missing or ambiguous macOS LC_BUILD_VERSION")
    result = found[0]
    if _version(result["minimum_os"]) != _version(DEPLOYMENT_TARGET) or _version(result["sdk"]) != _version(SDK_VERSION):
        raise ValueError(f"Mach-O SDK/deployment differs from the selected toolchain: {result}")
    return result


def inspect_library(library: Path, dsym: Path, work: Path) -> dict:
    if architectures(library) != ["arm64"]:
        raise ValueError("The dylib must contain exactly one ARM64 slice")
    commands = _output(["xcrun", "otool", "-l", str(library)])
    (work / "macho-load-commands.txt").write_text(commands + "\n", encoding="utf-8")
    version = build_version(commands)
    install = _output(["xcrun", "otool", "-D", str(library)]).splitlines()
    if len(install) != 2 or install[1].strip() != f"@rpath/{library.name}":
        raise ValueError(f"Unexpected dylib install name: {install}")
    deps = dependencies(library)
    # otool -L includes the install name itself as its first item.
    if not deps or deps[0] != f"@rpath/{library.name}":
        raise ValueError("Dylib dependency table has an unexpected install name")
    foreign = [item for item in deps[1:] if not item.startswith(("/usr/lib/", "/System/Library/Frameworks/"))]
    if foreign:
        raise ValueError(f"Dylib depends on non-system libraries: {foreign}")
    symbols = undefined_symbols(library)
    imports = math_imports(symbols)
    if not {"_sin", "_cos", "_pow"}.issubset(imports) or any("sincos" in symbol.lower() for symbol in imports):
        raise ValueError(f"Missing separate sin/cos/pow or unexpected sincos import: {imports}")
    lib_uuid, dsym_uuid = uuid_map(library), uuid_map(dsym)
    if set(lib_uuid) != {"arm64"} or lib_uuid != dsym_uuid:
        raise ValueError("dSYM UUID does not match the final ARM64 dylib")
    return {"architectures": ["arm64"], "install_name": install[1].strip(), "dependencies": deps[1:],
            "math_imports": imports, "undefined_symbols": symbols, "build_version": version,
            "load_commands_sha256": nk.sha256_file(work / "macho-load-commands.txt"),
            "uuid": lib_uuid, "dsym": str(dsym), "dsym_sha256": nk.sha256_file(dsym)}


def verification_roster() -> dict[str, str]:
    """The experimental fixed-wing scope excludes helicopter admission and adds the base oracle."""
    return {"base_oracle": "results-[0-9]*.json", **{key: pattern for key, pattern in nk.VERIFICATIONS.items()
                                                      if key not in {"helicopter", "helicopter_stage"}}}


def _base_oracle_error(data: dict) -> str:
    """The full base oracle includes the special-value math grid and literal table."""
    if data.get("format") != "openrc-nk3-oracle v1" or data.get("verdict") != "pass" or data.get("failures") != []:
        return "base oracle did not pass"
    self_test = data.get("self_test")
    if not isinstance(self_test, dict) or self_test.get("passed") is not True or self_test.get("detected") != [True] * 4:
        return "base oracle comparator self-test is incomplete"
    if type(data.get("states")) is not int or data["states"] < 12000 \
            or type(data.get("variant_states")) is not int or data["variant_states"] < 1500:
        return "base oracle did not execute the full state and variant counts"
    law = data.get("law_identity")
    if not isinstance(law, dict) or any(not isinstance(law.get(field), str) or not law[field]
                                       for field in ("aero_reference", "aero_native", "rolling_reference", "rolling_native")) \
            or law["aero_reference"] != law["aero_native"] or law["rolling_reference"] != law["rolling_native"]:
        return "base oracle law identity differs"
    components = data.get("components")
    if not isinstance(components, dict) or not components:
        return "base oracle has no components"
    total = 0
    for row in components.values():
        if (not isinstance(row, dict) or type(row.get("count")) is not int or row["count"] <= 0
                or type(row.get("identical")) is not int or row["identical"] != row["count"]):
            return "base oracle has missing or unequal comparisons"
        total += row["count"]
    # _check_math_shim currently covers 14 functions over the 27x27 special
    # grid and 20,000 random arguments. The literal table has over 100 keys.
    if components.get("math_shim", {}).get("count", 0) < 14 * (27 * 27 + 20000) \
            or components.get("literals", {}).get("count", 0) < 100:
        return "base oracle math or literal coverage is incomplete"
    if data.get("total") != {"compared": total, "identical": total, "mismatched": 0}:
        return "base oracle comparison totals differ"
    error = _macos_boundary_error(data)
    if error:
        return error
    return ""


def _macos_boundary_error(data: dict) -> str:
    """Require the actual engine boundary and control observations, not standalone C++ proof."""
    boundary = data.get("macos_boundary", {})
    if (boundary.get("format") != "openrc-nk3-macos-boundary-probe v1"
            or boundary.get("control_mask") != "0x07c8bf07"
            or boundary.get("fpsr") != "not_observed" or boundary.get("signaling_nan") != "not_tested"):
        return "Mac float64/FPCR boundary evidence is missing or incompatible"
    required = ("control_unchanged", "control_detector", "float32_narrowing_detected",
                "retained_after_input_change", "independent_results", "caller_unchanged_by_result",
                "repeated_call", "retained_after_repeat", "stage_prepared", "tick_context_accepted",
                "stage_shaped", "refusal_observed")
    if any(boundary.get(field) is not True for field in required):
        return "Mac boundary observation or negative detector did not pass"
    if (boundary.get("float32_detector_input") != "3ff0000000000001"
            or boundary.get("float32_detector_result") != "3ff0000000000000"):
        return "Mac float32 narrowing detector did not exercise its exact witness"
    coverage = data.get("coverage", {})
    expected = {
        "macos_float64_transport": {"scalar_cases": 13, "packed_cases": 13, "retention_checks": 5,
                                    "quiet_nan_encodings": 3, "signaling_nan_tested": False,
                                    "beyond_float32_cases": 2},
        "macos_fpcr": {"observations": 14, "changed": 0, "fpsr_tested": False},
    }
    for name, fields in expected.items():
        row = coverage.get(name, {})
        if any(type(row.get(key)) is not type(value) or row[key] != value for key, value in fields.items()):
            return "Mac boundary coverage is incomplete"
    components = data.get("components", {})
    counts = {"macos_float64_scalar_transport": 13, "macos_float64_packed_transport": 13,
              **{name: 1 for name in ("macos_float64_input_isolation", "macos_float64_result_isolation",
                                     "macos_float64_caller_isolation", "macos_float64_repeated_transport",
                                     "macos_float64_retained_transport", "macos_fpcr_math_witness")}}
    for name, count in counts.items():
        row = components.get(name, {})
        if any(type(row.get(key)) is not int or row[key] != count for key in ("count", "identical")):
            return "Mac boundary comparisons are incomplete"
    observations = boundary.get("fpcr", {})
    labels = {f"{edge}_{operation}" for edge in ("before", "after")
              for operation in ("transport", "math", "prepare", "context", "stage", "refusal", "checks")}
    if not isinstance(observations, dict) or set(observations) != labels:
        return "Mac FPCR observations are incomplete"
    controls = set()
    for row in observations.values():
        if (not isinstance(row, dict) or not isinstance(row.get("raw"), str)
                or not re.fullmatch(r"0x[0-9a-f]{16}", row["raw"])
                or not isinstance(row.get("control"), str) or not re.fullmatch(r"0x[0-9a-f]{8}", row["control"])):
            return "Mac FPCR observation is malformed"
        control = int(row["control"], 16)
        if int(row["raw"], 16) & 0x07c8bf07 != control:
            return "Mac FPCR raw and control bits differ"
        controls.add(control)
    return "Mac FPCR controls changed" if len(controls) != 1 else ""


def verification_error(key: str, data: dict) -> str:
    """Reuse the shared verdict policy; binary, engine and Mac identity checks are separate."""
    if key == "base_oracle":
        try:
            return _base_oracle_error(data)
        except (KeyError, TypeError, ValueError, AttributeError):
            return "malformed base oracle evidence"
    if key not in verification_roster():
        return "unknown verification kind"
    try:
        return nk.verification_error(key, data)
    except (KeyError, TypeError, ValueError, AttributeError):
        return "malformed verification evidence"


def _verified_path(path: Path, expected: Path, digest: str) -> None:
    if path.is_symlink() or path.resolve() != expected.resolve() or not path.is_file() or nk.sha256_file(path) != digest:
        raise ValueError(f"Missing, moved, symlinked or changed build input: {path}")


def _verified_macho(library: Path, work: Path, built: dict) -> None:
    """Reinspect the signed bytes without changing the original build evidence."""
    macho = built["mach_o"]
    if architectures(library) != ["arm64"] or macho["architectures"] != ["arm64"]:
        raise ValueError("Unexpected dylib slice")
    signing = built.get("signing")
    selection = _signing_record_selection(signing)
    current_signing = inspect_signing(library, selection)
    if selection["kind"] == "developer-id-application" and current_signing != signing:
        raise ValueError("The signed dylib no longer has the recorded Developer ID signature metadata")
    commands = _output(["xcrun", "otool", "-l", str(library)])
    if (hashlib.sha256((commands + "\n").encode()).hexdigest() != macho["load_commands_sha256"]
            or build_version(commands) != macho["build_version"]):
        raise ValueError("Dylib load commands changed")
    install = _output(["xcrun", "otool", "-D", str(library)]).splitlines()
    if len(install) != 2 or install[1].strip() != f"@rpath/{library.name}" or macho["install_name"] != install[1].strip():
        raise ValueError("Dylib install name changed")
    deps = dependencies(library)
    if (not deps or deps[0] != macho["install_name"] or deps[1:] != macho["dependencies"]
            or any(not item.startswith(("/usr/lib/", "/System/Library/Frameworks/")) for item in deps[1:])):
        raise ValueError("Dylib dependencies changed or are not system libraries")
    symbols = undefined_symbols(library)
    imports = math_imports(symbols)
    if (symbols != macho["undefined_symbols"] or imports != macho["math_imports"]
            or not {"_sin", "_cos", "_pow"}.issubset(imports)
            or any("sincos" in symbol.lower() for symbol in imports)):
        raise ValueError("Dylib math or undefined symbols changed")
    dwarf = work / (library.name + ".dSYM") / "Contents/Resources/DWARF" / library.name
    _verified_path(Path(macho["dsym"]), dwarf, macho["dsym_sha256"])
    if uuid_map(library) != macho["uuid"] or uuid_map(dwarf) != macho["uuid"] or set(macho["uuid"]) != {"arm64"}:
        raise ValueError("Dylib and dSYM UUIDs differ")


def validate_variant_compdb(path: Path, mutant: bool) -> None:
    """Every translation unit must have the intended mutation and no diagnostic NK defines."""
    rows = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(rows, list) or not rows:
        raise ValueError("Missing variant compilation commands")
    expected = {"NK_MUTATION=1"} if mutant else set()
    for row in rows:
        args = _args(row)
        defines = set()
        for index, arg in enumerate(args):
            if arg == "-D" and index + 1 < len(args):
                name = args[index + 1]
            elif arg.startswith("-D"):
                name = arg[2:]
            else:
                continue
            if name.startswith("NK_"):
                defines.add(name)
        if defines != expected:
            raise ValueError(f"Unexpected diagnostic or mutation defines in compilation: {sorted(defines)}")


def validate_build(root: Path, mutant: bool, identity: dict, toolchain: dict, engine: dict, lock: dict) -> dict:
    """Revalidate the exact research build, including all retained effective commands."""
    variant = "_mutant" if mutant else ""
    work = root / "work" / ("mutant" if mutant else "candidate")
    library = root / "lib" / f"lib{nk.NAME}{variant}.dylib"
    receipt_path = root / f"build-receipt{variant}.json"
    if receipt_path.is_symlink() or not receipt_path.is_file():
        raise ValueError(f"Missing regular build receipt: {receipt_path}")
    built = json.loads(receipt_path.read_text(encoding="utf-8"))
    if not isinstance(built, dict) or any(built.get(key) != value for key, value in identity.items()):
        raise ValueError("Native source, mirrored source, builder or lock changed since the build")
    flags = [*_common_flags(Path(toolchain["sdk_path"])), *(["-DNK_MUTATION=1"] if mutant else [])]
    required = {"format": FORMAT, "installable": False, "mutant": mutant, "platform": "macos",
                "architecture": "arm64", "target": "template_release", "backend_version": nk.BACKEND_VERSION,
                "abi_version": nk.ABI_VERSION, "toolchain": toolchain, "engine": engine,
                "engine_version": engine["version"], "engine_sha256": engine["sha256"],
                "godot_cpp_commit": lock["godot_cpp"]["commit"], "scons_version": lock["scons"]["version"],
                "scons_wheel_sha256": lock["scons"]["wheel_sha256"], "extension_api": lock["godot"]["extension_api"],
                "binding_precision": "single", "build_profile_sha256": lock["godot_cpp"]["build_profile"]["sha256"],
                "cxxflags_appended": flags}
    if any(built.get(key) != value for key, value in required.items()):
        raise ValueError(f"Stale, diagnostic or unpinned {'mutant' if mutant else 'candidate'} build receipt")
    _verified_path(Path(built["library"]), library, built["binary_sha256"])
    descriptor = root / f"{nk.NAME}{variant}.gdextension"
    _verified_path(Path(built["descriptor"]), descriptor, built["descriptor_sha256"])
    dependencies_root = work / "dependencies"
    cpp = dependencies_root / "godot-cpp"
    if (not cpp.is_dir() or locked.run(["git", "rev-parse", "HEAD"], cwd=cpp, capture=True).strip()
            != lock["godot_cpp"]["commit"]
            or locked.run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=cpp, capture=True).strip()):
        raise ValueError("godot-cpp checkout differs from the pinned clean revision")
    api = cpp / "gdextension/extension_api-4-7.json"
    _verified_path(Path(built["extension_api_path"]), api, built["extension_api_sha256"])
    _verified_path(work / "build_profile.json", work / "build_profile.json", built["build_profile_sha256"])
    wheel = dependencies_root / "downloads" / lock["scons"]["wheel_filename"]
    _verified_path(wheel, wheel, lock["scons"]["wheel_sha256"])
    env = clean_build_environment(Path(toolchain["compiler"]), Path(toolchain["sdk_path"]))
    database = validate_compdb(work / "compile_commands.json", Path(toolchain["compiler"]), Path(toolchain["sdk_path"]), env)
    if database != built["compile_database"]:
        raise ValueError("Compilation database changed after the build")
    validate_variant_compdb(work / "compile_commands.json", mutant)
    log = work / "build.log"
    if nk.sha256_file(log) != built["build_log_sha256"]:
        raise ValueError("Build log changed after the build")
    built_library = work / "lib" / library.name
    if validate_link_command(log, built_library, Path(toolchain["sdk_path"]), Path(toolchain["compiler"]), env) != built["link_command"]:
        raise ValueError("Effective dylib link command differs")
    _verified_macho(library, work, built)
    return built


def _runner():
    spec = importlib.util.spec_from_file_location("openrc_macos_evidence_runner", HERE / "run.py")
    if spec is None or spec.loader is None:
        raise ValueError("Cannot load the oracle evidence runner")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _relative_digest(name: str, root: Path, digest: str) -> None:
    if not isinstance(name, str) or not isinstance(digest, str) or "\\" in name:
        raise ValueError("Malformed evidence source path")
    relative = Path(name)
    if relative.is_absolute() or any(part in {".", "..", ""} for part in name.split("/")):
        raise ValueError("Unexpected evidence source path")
    source = (root / relative).resolve()
    if not source.is_relative_to(root.resolve()) or not source.is_file() or nk.sha256_file(source) != digest:
        raise ValueError(f"Evidence source changed: {name}")


def _one_argument(command: list[str], option: str) -> str:
    values = [command[index + 1] for index, value in enumerate(command[:-1]) if value == option]
    if len(values) != 1:
        raise ValueError(f"Checked command needs exactly one {option}")
    return values[0]


def _one_prefixed(command: list[str], option: str) -> str:
    values = [arg[len(option):] for arg in command if arg.startswith(option)]
    if len(values) != 1 or not values[0]:
        raise ValueError(f"Checked command needs exactly one {option}")
    return values[0]


def _engine_display(version: str) -> str:
    release = version.split(".official.")[0].replace(".beta", "-beta").replace(".rc", "-rc")
    return f"{release} (official)"


def _check_oracle_identity(data: dict, result_path: Path, key: str, built: dict,
                           project_cache: dict[str, dict], runner) -> None:
    mutant = key == "negative_control"
    expected_engine = built["engine"]
    if (data.get("run_valid") is not True or data.get("engine") != _engine_display(expected_engine["version"])
            or data.get("build_receipt") != built
            or any(data.get(field) != expected_engine["sha256"] for field in
                   ("engine_sha256_before", "engine_sha256_after", "engine_executable_sha256_before", "engine_executable_sha256_after"))
            or any(data.get(field) != built["binary_sha256"] for field in ("binary_sha256_before", "binary_sha256_after"))):
        raise ValueError("Evidence does not bind the current engine and exact signed build")
    native = data.get("identity")
    if (not isinstance(native, dict) or native.get("backend") != "native"
            or native.get("backend_version") != nk.BACKEND_VERSION or native.get("abi_version") != nk.ABI_VERSION):
        raise ValueError("Oracle did not identify the expected native backend")
    sources = built["reference_sources_sha256"]
    if data.get("reference_sources_before") != sources or data.get("reference_sources_after") != sources:
        raise ValueError("Evidence mirrored-source identity differs")
    observed = data.get("sources")
    if not isinstance(observed, dict) or not observed or data.get("sources_after") != observed:
        raise ValueError("Oracle source inventory is missing or changed")
    for name, digest in observed.items():
        if not isinstance(name, str) or not name.startswith("res://"):
            raise ValueError("Unexpected oracle source path")
        _relative_digest(name.removeprefix("res://"), ROOT / "app", digest)
    script = "oracle.gd" if key == "base_oracle" else nk.ORACLE_SCRIPTS[key]
    harness = {"research/native-kernel/" + name for name in
               ("oracle.gd", "stage_oracle.gd", "stage_adapter.gd", "run.py", "build.py", "build_macos.py", script)}
    harness.update({"app/sim/native_stage.gd", "tools/godot/run_checked.py"})
    if key == "electric_stage": harness.add("research/native-kernel/electric_oracle.gd")
    if key == "wake_spatial": harness.update({"research/native-kernel/weather_oracle.gd", "research/native-kernel/wake_oracle.gd"})
    observed_harness = data.get("harness_sources")
    if not isinstance(observed_harness, dict) or not harness.issubset(observed_harness):
        raise ValueError("Oracle harness identity is incomplete")
    for name, digest in observed_harness.items():
        _relative_digest(name, ROOT, digest)
    project_value = data.get("project")
    if not isinstance(project_value, str) or not Path(project_value).is_absolute():
        raise ValueError("Oracle project identity is missing")
    project = Path(project_value).resolve()
    if str(project) not in project_cache:
        project_cache[str(project)] = runner.validate_project(project)
    proof = project_cache[str(project)]
    if data.get("project_inventory_before") != proof or data.get("project_inventory_after") != proof:
        raise ValueError("Oracle project inventory proof is missing, stale or incomplete")
    if project != (ROOT / "app").resolve() and (not isinstance(proof, dict) or not proof):
        raise ValueError("Copied project lacks verified inventory proof")
    checked = data.get("checked_run")
    marker = "NK3_ORACLE verdict=fail" if mutant else "NK3_ORACLE verdict=pass"
    if (not isinstance(checked, dict) or checked.get("complete") is not True
            or checked.get("ok") is not (not mutant) or checked.get("required_text") != [marker]
            or checked.get("missing_required_text") != [] or checked.get("counts", {}).get("error") != 0
            or checked.get("process_exit") != (1 if mutant else 0)
            or checked.get("reason") != ("process_exit" if mutant else "passed")):
        raise ValueError("Checked process did not establish its required oracle marker")
    checks = Path(built["library"]).resolve().parent.parent / "checks"
    report_file = Path(checked.get("report", ""))
    log_file = Path(checked.get("log", ""))
    if (report_file.is_symlink() or log_file.is_symlink() or not report_file.is_file() or not log_file.is_file()
            or not report_file.resolve().is_relative_to(checks.resolve())
            or log_file.resolve().parent != report_file.resolve().parent
            or json.loads(report_file.read_text(encoding="utf-8")) != checked
            or nk.sha256_file(log_file) != checked.get("log_sha256")
            or marker.encode("utf-8") not in log_file.read_bytes()):
        raise ValueError("Checked process report or oracle-marker log is missing or changed")
    command = checked.get("command")
    if not isinstance(command, list) or any(not isinstance(arg, str) for arg in command) or not command:
        raise ValueError("Checked oracle command is missing")
    if (Path(checked.get("cwd", "")).resolve() != ROOT.resolve()
            or Path(command[0]).resolve() != Path(expected_engine["path"]).resolve()
            or "--headless" not in command or _one_argument(command, "--audio-driver") != "Dummy"
            or Path(_one_argument(command, "--path")).resolve() != project
            or Path(_one_argument(command, "--script")).resolve() != (HERE / script).resolve()
            or Path(_one_prefixed(command, "--extension=")).resolve() != Path(built["descriptor"]).resolve()
            or Path(_one_prefixed(command, "--output=")).resolve() != result_path.resolve()
            or int(_one_prefixed(command, "--states=")) != data.get("states")
            or int(_one_prefixed(command, "--variant-states=")) != data.get("variant_states")):
        raise ValueError("Checked command did not execute the selected engine, project, script and research descriptor")
    error = verification_error(key, data)
    if error:
        raise ValueError(error)


def find_verification(root: Path, key: str, pattern: str, built: dict, project_cache: dict[str, dict], runner) -> dict:
    mutant = key == "negative_control"
    last_error = "no matching report"
    for path in sorted(root.glob(pattern), reverse=True):
        if ("_mutant" in path.name) != mutant or path.is_symlink():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                raise ValueError("report must be an object")
            _check_oracle_identity(data, path, key, built, project_cache, runner)
            return {"results": path.name, "results_sha256": nk.sha256_file(path),
                    "verdict": "fail" if mutant else "pass", "compared": data["total"]["compared"]}
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
            last_error = str(error)
    script = "oracle.gd" if key == "base_oracle" else nk.ORACLE_SCRIPTS[key]
    raise ValueError(f"Missing complete current {key} evidence ({pattern}); last rejection: {last_error}; "
                     f"run research/native-kernel/run.py --script {script}")


def prepare_macos_manual_loading(app: Path, destination: Path) -> None:
    """Exclude imports and remove only the Mac descriptor from an old extension cache."""
    app = app.resolve()
    expected = app / "native/kernel"
    registry = app / ".godot/extension_list.cfg"
    if (destination.absolute() != expected or (app / "native").is_symlink() or destination.is_symlink()
            or destination.resolve() != expected or registry.parent.is_symlink() or registry.is_symlink()
            or not registry.resolve().is_relative_to(app)):
        raise ValueError("Refusing symlinked or unexpected native destination or extension registry")
    if registry.exists() and not registry.is_file():
        raise ValueError("Extension registry is not a regular file")
    ignore = destination / ".gdignore"
    if ignore.is_symlink() or (ignore.exists() and not ignore.is_file()):
        raise ValueError("Cannot create a safe native import exclusion")
    destination.mkdir(parents=True, exist_ok=True)
    if not ignore.exists():
        ignore.touch(exist_ok=False)
    if not registry.exists():
        return
    original = registry.read_bytes()
    entry = f"res://native/kernel/{nk.NAME}_macos.gdextension".encode()
    retained = b"".join(line for line in original.splitlines(keepends=True) if line.rstrip(b"\r\n") != entry)
    if retained == original:
        return
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=registry.parent, prefix=".nk3-mac-extension-list-", delete=False) as output:
            temporary = Path(output.name)
            output.write(retained)
        os.chmod(temporary, stat.S_IMODE(registry.stat().st_mode))
        os.replace(temporary, registry)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _atomic_install(path: Path, data: bytes) -> None:
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError(f"Refusing symlinked or non-file install target: {path}")
    if path.is_file() and path.read_bytes() == data:
        return
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".nk3-mac-install-", delete=False) as output:
            temporary = Path(output.name)
            output.write(data)
        if temporary.read_bytes() != data:
            raise ValueError(f"Could not verify staged install: {path}")
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def install_app(tool_root: Path, godot: Path, expected_signing: dict | None = None) -> int:
    """Install only an evidence-bound, experimental source-tree fixed-wing candidate."""
    root = tool_root.resolve()
    tmp = (ROOT / "tmp").resolve()
    if root == tmp or not root.is_relative_to(tmp):
        raise ValueError("--tool-root must be a directory inside this checkout's tmp/")
    lock = locked.load_lock()
    toolchain = host_toolchain()
    engine = godot_identity(godot, lock)
    identity = _identity()
    candidate = validate_build(root, False, identity, toolchain, engine, lock)
    mutant = validate_build(root, True, identity, toolchain, engine, lock)
    validate_signing_pair(candidate, mutant)
    if expected_signing is not None:
        actual = _signing_record_selection(candidate["signing"])
        if any(actual.get(key) != value for key, value in expected_signing.items()):
            raise ValueError("Installed build does not match the requested signing identity and team")
    if candidate["extension_api_sha256"] != mutant["extension_api_sha256"]:
        raise ValueError("Candidate and negative-control extension APIs differ")
    if candidate["binary_sha256"] == mutant["binary_sha256"]:
        raise ValueError("Negative-control dylib must differ from the candidate")
    runner = _runner()
    cache: dict[str, dict] = {}
    verifications = {key: find_verification(root, key, pattern, mutant if key == "negative_control" else candidate,
                                            cache, runner) for key, pattern in verification_roster().items()}
    license_path = root / "work/candidate/dependencies/godot-cpp/LICENSE.md"
    if license_path.is_symlink() or not license_path.is_file():
        raise ValueError("Pinned godot-cpp licence is missing")
    license_bytes = license_path.read_bytes()
    app = (ROOT / "app").resolve()
    destination = app / "native/kernel"
    shared_license = destination / "LICENSE.godot-cpp.md"
    if shared_license.is_symlink() or (shared_license.exists() and
                                      (not shared_license.is_file() or shared_license.read_bytes() != license_bytes)):
        raise ValueError("Existing shared godot-cpp licence differs; refusing to replace it")
    for name in (f"lib{nk.NAME}.dylib", f"{nk.NAME}_macos.gdextension", "build-receipt-macos.json"):
        target = destination / name
        if target.is_symlink() or (target.exists() and not target.is_file()):
            raise ValueError(f"Refusing symlinked or non-file install target: {target}")
    row = {"platform": "macos", "architecture": "arm64", "backend": "native",
           "backend_version": nk.BACKEND_VERSION, "abi_version": nk.ABI_VERSION,
           "qualification_scope": SOURCE_SCOPE, "binary_sha256": candidate["binary_sha256"],
           "source_sha256": identity["source_sha256"], "lock_sha256": identity["lock_sha256"],
           "builder_sha256": identity["builder_sha256"], "linux_builder_sha256": identity["linux_builder_sha256"],
           "shared_builder_sha256": identity["shared_builder_sha256"], "mirrored_sources": identity["reference_sources_sha256"],
           "runtime_os_version": toolchain["os_version"], "runtime_os_build": toolchain["os_build"],
           "toolchain": toolchain, "engine": engine, "engine_version": _engine_display(engine["version"]),
           "engine_cli_version": engine["version"], "engine_sha256": engine["sha256"],
           "godot_cpp_commit": candidate["godot_cpp_commit"], "extension_api_sha256": candidate["extension_api_sha256"],
           "binding_precision": candidate["binding_precision"], "cxxflags_appended": candidate["cxxflags_appended"],
           "repository_head": candidate["repository_head"], "verification": verifications}
    receipt = {"format": nk.RECEIPT_FORMAT, "backend": "native", "backend_version": nk.BACKEND_VERSION,
               "abi_version": nk.ABI_VERSION, "platforms": {"macos": row}}
    # Recheck all mutable identity inputs immediately before any app writes.
    final_cache: dict[str, dict] = {}
    final_verifications = {key: find_verification(root, key, pattern, mutant if key == "negative_control" else candidate,
                                                  final_cache, runner) for key, pattern in verification_roster().items()}
    library_bytes = Path(candidate["library"]).read_bytes()
    if (_identity() != identity or godot_identity(godot, lock) != engine or host_toolchain() != toolchain
            or hashlib.sha256(library_bytes).hexdigest() != candidate["binary_sha256"]
            or nk.sha256_file(Path(mutant["library"])) != mutant["binary_sha256"]
            or final_verifications != verifications):
        raise ValueError("Build, engine, host or evidence changed during verification")
    prepare_macos_manual_loading(app, destination)
    _atomic_install(destination / f"lib{nk.NAME}.dylib", library_bytes)
    _atomic_install(destination / f"{nk.NAME}_macos.gdextension", SOURCE_DESCRIPTOR.encode("utf-8"))
    _atomic_install(shared_license, license_bytes)
    _atomic_install(destination / "build-receipt-macos.json",
                    (json.dumps(receipt, indent=2, sort_keys=True, allow_nan=False) + "\n").encode("utf-8"))
    print(f"Installed experimental source-only Mac native stage at {destination}; fleet and package qualification are pending.")
    return 0


def check_free_space(root: Path, minimum_gib: float) -> int:
    if not math.isfinite(minimum_gib) or minimum_gib < 0.5:
        raise ValueError("--min-free-gib must be finite and at least 0.5 GiB")
    free = shutil.disk_usage(root).free
    if free < minimum_gib * 1024**3:
        raise ValueError(f"At least {minimum_gib:g} GiB free is required at {root}; found {free} bytes")
    return free


def _identity() -> dict:
    return {"source_sha256": nk.source_digest(), "reference_sources_sha256": nk.mirrored_sources(),
            "lock_sha256": nk.sha256_file(locked.LOCK_PATH), "builder_sha256": nk.sha256_file(Path(__file__)),
            "linux_builder_sha256": nk.sha256_file(HERE / "build.py"),
            "shared_builder_sha256": nk.sha256_file(nk.SHARED_BUILDER)}


def build(args: argparse.Namespace) -> int:
    if args.jobs < 1:
        raise ValueError("--jobs must be at least 1")
    requested_signing = signing_selection(getattr(args, "signing_identity", None), getattr(args, "team_id", None))
    toolchain = host_toolchain()
    lock = locked.load_lock()
    engine = godot_identity(args.godot, lock)
    root = args.tool_root.resolve()
    tmp = (ROOT / "tmp").resolve()
    if root == tmp or not root.is_relative_to(tmp):
        raise ValueError("--tool-root must be a directory inside this checkout's tmp/")
    root.mkdir(parents=True, exist_ok=True)
    free_before = check_free_space(root, args.min_free_gib)
    selected_signing = resolve_signing_identity(requested_signing)
    other_receipt = root / ("build-receipt.json" if args.mutant else "build-receipt_mutant.json")
    if other_receipt.exists() or other_receipt.is_symlink():
        if other_receipt.is_symlink() or not other_receipt.is_file():
            raise ValueError("The existing paired build receipt is not a regular file")
        other = json.loads(other_receipt.read_text(encoding="utf-8"))
        if not isinstance(other, dict) or _signing_record_selection(other.get("signing")) != selected_signing:
            raise ValueError("Candidate and mutant must use the same signing selection")
    variant = "_mutant" if args.mutant else ""
    name = nk.NAME + variant
    library = root / "lib" / f"lib{name}.dylib"
    descriptor = root / f"{name}.gdextension"
    receipt_path = root / f"build-receipt{variant}.json"
    for output in (library, descriptor, receipt_path):
        if output.exists() or output.is_symlink():
            raise ValueError(f"Refusing to overwrite an existing output: {output}")
    work = root / "work" / ("mutant" if args.mutant else "candidate")
    work.mkdir(parents=True, exist_ok=False)
    before = _identity()
    env = clean_build_environment(Path(toolchain["compiler"]), Path(toolchain["sdk_path"]))
    env["CC"] = toolchain["c_compiler"]
    preflight_result = preflight(toolchain, work, env)
    # godot-cpp builds into its checkout: never share it with another candidate.
    locked.TOOL_ROOT = work / "dependencies"
    scons = locked.ensure_scons(lock)
    godot_cpp = locked.ensure_godot_cpp(lock)
    free_before_build = check_free_space(root, args.min_free_gib)
    api = godot_cpp / "gdextension" / "extension_api-4-7.json"
    api_sha256 = nk.sha256_file(api)
    profile = lock["godot_cpp"]["build_profile"]
    profile_content = json.dumps(profile["content"], sort_keys=True, separators=(",", ":")) + "\n"
    if hashlib.sha256(profile_content.encode()).hexdigest() != profile["sha256"]:
        raise ValueError("Build profile SHA-256 mismatch")
    profile_path = work / "build_profile.json"
    profile_path.write_text(profile_content, encoding="utf-8")
    flags = [*_common_flags(Path(toolchain["sdk_path"])), *(["-DNK_MUTATION=1"] if args.mutant else [])]
    local_lock = dict(lock, _sdk_path=toolchain["sdk_path"])
    script = make_sconstruct(godot_cpp, work, profile_path, local_lock, flags, Path(toolchain["compiler"]), name)
    (work / "SConstruct").write_text(script, encoding="utf-8")
    compdb = work / "compile_commands.json"
    command = [*scons, "-C", str(work), f"-j{args.jobs}", "platform=macos", "arch=arm64",
               "target=template_release", "precision=single", "debug_symbols=yes", "lto=none", "verbose=yes",
               "compiledb=yes", f"compiledb_file={compdb}"]
    log_path = work / "build.log"
    with log_path.open("x", encoding="utf-8") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, text=True, env=env)
    if result.returncode:
        raise ValueError(f"SCons failed ({result.returncode}); inspect {log_path}")
    built = work / "lib" / f"lib{name}.dylib"
    if not built.is_file():
        raise ValueError(f"SCons did not produce the expected dylib: {built}")
    database = validate_compdb(compdb, Path(toolchain["compiler"]), Path(toolchain["sdk_path"]), env)
    validate_variant_compdb(compdb, args.mutant)
    link = validate_link_command(log_path, built, Path(toolchain["sdk_path"]), Path(toolchain["compiler"]), env)
    library.parent.mkdir(parents=True, exist_ok=True)
    with built.open("rb") as source, library.open("xb") as target:
        shutil.copyfileobj(source, target)
    dsym_bundle = work / (library.name + ".dSYM")
    subprocess.run(["xcrun", "dsymutil", str(library), "-o", str(dsym_bundle)], check=True, env=env)
    dwarf = dsym_bundle / "Contents/Resources/DWARF" / library.name
    if selected_signing["kind"] == "ad-hoc":
        sign_command = ["codesign", "--force", "--sign", "-", "--timestamp=none", str(library)]
    else:
        sign_command = ["codesign", "--force", "--sign", selected_signing["identity_sha1"], "--timestamp", str(library)]
    subprocess.run(sign_command, check=True, env=env)
    signature = inspect_signing(library, selected_signing, env=env)
    inspection = inspect_library(library, dwarf, work)
    if before != _identity() or nk.sha256_file(api) != api_sha256 or nk.sha256_file(args.godot.resolve()) != engine["sha256"]:
        raise ValueError("Sources, API or engine changed during the build; use a fresh tool root")
    with descriptor.open("x", encoding="utf-8", newline="\n") as output:
        output.write("; Experimental signed Mac ARM64 research library; manual loading only.\n"
                     "[configuration]\n"
                     f'entry_symbol = "{nk.NAME}_library_init"\n'
                     'compatibility_minimum = "4.7"\nreloadable = false\n\n[libraries]\n'
                     f'macos.arm64 = "lib/{library.name}"\n')
    receipt = {"format": FORMAT, "installable": False, "library": str(library), "descriptor": str(descriptor),
               "descriptor_sha256": nk.sha256_file(descriptor), "mutant": args.mutant,
               "binary_sha256": nk.sha256_file(library), **before, "backend_version": nk.BACKEND_VERSION,
               "abi_version": nk.ABI_VERSION, "platform": "macos", "architecture": "arm64",
               "target": "template_release", "compiler": toolchain["compiler_version"],
               "compiler_version": toolchain["compiler_version"], "toolchain": toolchain, "engine": engine,
               "engine_version": engine["version"], "engine_sha256": engine["sha256"],
               "godot_cpp_commit": lock["godot_cpp"]["commit"], "scons_version": lock["scons"]["version"],
               "scons_wheel_sha256": lock["scons"]["wheel_sha256"], "extension_api": lock["godot"]["extension_api"],
               "extension_api_path": str(api), "extension_api_sha256": api_sha256, "binding_precision": "single",
               "build_profile_sha256": profile["sha256"], "cxxflags_appended": flags, "build_command": command,
               "preflight": preflight_result, "compile_database": database, "link_command": link,
               "build_log_sha256": nk.sha256_file(log_path), "mach_o": inspection,
               "disk_headroom": {"minimum_gib": args.min_free_gib, "before_bytes": free_before,
                                 "before_build_bytes": free_before_build,
                                 "after_bytes": shutil.disk_usage(root).free},
               "signing": signature,
               "repository_head": locked.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture=True).strip()}
    _write_json(receipt_path, receipt)
    print(json.dumps({key: receipt[key] for key in ("library", "binary_sha256", "engine", "mach_o")}, indent=2))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True, help="exact pinned native ARM64 Godot executable")
    parser.add_argument("--tool-root", type=Path, default=Path(os.environ.get("OPENRC_NK_TOOL_ROOT", ROOT / "tmp/native-kernel-macos")))
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--min-free-gib", type=float, default=2.0,
                        help="required free space before bootstrap and SCons (default 2 GiB; minimum 0.5)")
    parser.add_argument("--mutant", action="store_true", help="build the independent negative-control candidate")
    parser.add_argument("--signing-identity", help="exact SHA-1 fingerprint of a Developer ID Application certificate")
    parser.add_argument("--team-id", help="10-character Developer ID team; required with --signing-identity")
    parser.add_argument("--install-app", action="store_true",
                        help="install the evidence-bound experimental source candidate; does not qualify fleet or packages")
    args = parser.parse_args()
    try:
        if args.install_app and args.mutant:
            parser.error("--install-app never installs a mutant")
        requested = signing_selection(args.signing_identity, args.team_id)
        return install_app(args.tool_root, args.godot,
                           expected_signing=requested if args.signing_identity is not None else None) if args.install_app else build(args)
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"Mac native build refused: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
