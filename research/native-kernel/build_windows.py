#!/usr/bin/env python3
"""NK-4 spike: build the NK-3 native kernel for Windows x86_64 with MinGW-w64 GCC (research only).

The Windows design note in README.md prefers MinGW-w64 GCC, like the official Godot Windows binaries:
the extension then links the same msvcrt/libmingwex math as the engine. This builder reuses the
Linux builder's pinned godot-cpp, SCons wheel, build profile, sources, floating-point and exception
flags, mutant switch and receipt fields; only the platform, compiler and import inspection differ.
It never installs anything into app/. Oracles run through run.py with OPENRC_NK_TOOL_ROOT set to the
same --tool-root.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPEC = importlib.util.spec_from_file_location("openrc_native_kernel_build", HERE / "build.py")
nk = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(nk)
locked = nk.locked

# Math the engine resolves from msvcrt.dll (objdump -p of the pinned Godot 4.8-beta2 Windows binaries);
# sin/cos/pow/exp/log/atan2/fmod are statically linked libmingwex code in both the engine and this DLL.
ENGINE_MSVCRT_MATH = {"_nextafter", "acos", "asin", "atan", "ceil", "cosh", "log10", "sinh", "tan", "tanh"}
# - sin and cos stay separate calls: GCC otherwise fuses sin(x)/cos(x) into libmingwex sincos(), which returns
#   the hardware default -NaN for an infinite argument where the engine's separate sin/cos return +NaN. It also
#   stops compile-time (MPFR) folding of a transcendental of a literal, which the engine evaluates at run time.
# - The Windows engine binary's lerp keeps Godot's source operand order (two-NaN priority; see nk_math.hpp).
# - sqrt_ uses SSE2 sqrtsd: libmingwex sqrt (called out of line) uses x87 fsqrt and double-rounds (see nk_math.hpp).
WINDOWS_FLAGS = ["-fno-builtin-sin", "-fno-builtin-cos", "-DNK_ENGINE_LERP_SOURCE_ORDER=1", "-DNK_ENGINE_SQRT_SSE2=1"]
MATH_NAMES = ENGINE_MSVCRT_MATH | {"sin", "cos", "pow", "exp", "log", "atan2", "fmod", "floor", "sqrt",
                                   "nextafter", "sincos", "exp2", "log2", "hypot", "round", "trunc"}


def dll_imports(binary: Path) -> dict[str, list[str]]:
    """Imported symbols per DLL (objdump -p import table)."""
    output = subprocess.run(["objdump", "-p", str(binary)], check=True, text=True, capture_output=True).stdout
    imports: dict[str, list[str]] = {}
    current = ""
    for line in output.splitlines():
        stripped = line.strip()
        if stripped.startswith("DLL Name:"):
            current = stripped.split(":", 1)[1].strip()
            imports.setdefault(current, [])
        elif current and stripped and stripped.split()[-1].isidentifier() and len(stripped.split()) >= 2 \
                and stripped.split()[0].isalnum():
            imports[current].append(stripped.split()[-1])
        elif not stripped:
            current = current if current else ""
    return {dll: sorted(set(names)) for dll, names in imports.items()}


ENGINE_LABEL = "4.8-beta2 (official)"
# run.py launches oracles through the console wrapper; the app process is the GUI executable it starts.
ENGINE_WRAPPER = ROOT / ".tools/Godot_v4.8-beta2_win64_console.exe"
ENGINE_EXECUTABLE = ROOT / ".tools/Godot_v4.8-beta2_win64.exe"
WINDOWS_DESCRIPTOR = (
    "; NK-4 native stage, installed by research/native-kernel/build_windows.py --install-app.\n"
    "; .gdignore prevents discovery; app/sim/native_stage.gd loads it after receipt checks.\n"
    "[configuration]\n"
    f'entry_symbol = "{nk.NAME}_library_init"\n'
    'compatibility_minimum = "4.7"\n'
    "reloadable = false\n\n"
    "[libraries]\n"
    f'windows.x86_64 = "res://native/kernel/{nk.NAME}.dll"\n'
)


def find_verification(tool_root: Path, key: str, pattern: str, binary_sha256: str, sources: dict[str, str]) -> dict:
    """build.py's find_verification for the Windows build: same evidence rules, Windows identities."""
    wrapper_sha256 = nk.sha256_file(ENGINE_WRAPPER)
    mutant = key == "negative_control"
    candidate_binary = tool_root / f"lib/{nk.NAME}_mutant.dll"
    builder = nk.sha256_file(Path(__file__))
    for path in sorted(tool_root.glob(pattern), reverse=True):
        if ("_mutant" in path.name) != mutant:
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if (data["engine_sha256_before"] != wrapper_sha256 or data["engine_sha256_after"] != wrapper_sha256):
                continue
            receipt = data["build_receipt"]
            expected_binary = nk.sha256_file(candidate_binary) if mutant else binary_sha256
            if (receipt["mutant"] is not mutant or receipt["binary_sha256"] != expected_binary
                    or data["binary_sha256_before"] != expected_binary or data["binary_sha256_after"] != expected_binary
                    or (mutant and (expected_binary == binary_sha256 or "-DNK_MUTATION=1" not in receipt["cxxflags_appended"]))
                    or (not mutant and "-DNK_MUTATION=1" in receipt["cxxflags_appended"])):
                continue
            if (receipt["source_sha256"] != nk.source_digest() or receipt["lock_sha256"] != nk.sha256_file(locked.LOCK_PATH)
                    or receipt["builder_sha256"] != builder or receipt["platform"] != "windows"
                    or receipt["backend_version"] != nk.BACKEND_VERSION or receipt["abi_version"] != nk.ABI_VERSION
                    or receipt["reference_sources_sha256"] != sources
                    or data["reference_sources_before"] != sources or data["reference_sources_after"] != sources):
                continue
            observed = data["sources"]
            if not isinstance(observed, dict) or not observed or data["sources_after"] != observed:
                continue
            for name, value in observed.items():
                file = (ROOT / "app" / name.removeprefix("res://")).resolve()
                if not name.startswith("res://") or not file.is_relative_to((ROOT / "app").resolve()):
                    raise ValueError("unexpected oracle source path")
                relative = str(file.relative_to(ROOT)).replace("\\", "/")
                current = sources.get(relative) if relative in sources else nk.sha256_file(file)
                if value != current:
                    raise ValueError("oracle source changed")
            for name, digest in data["harness_sources"].items():
                file = (ROOT / name).resolve()
                if not file.is_relative_to(ROOT.resolve()) or nk.sha256_file(file) != digest:
                    raise ValueError("oracle harness changed")
            if nk.verification_error(key, data):
                continue
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            continue
        return {"results": path.name, "results_sha256": nk.sha256_file(path), "verdict": "fail" if mutant else "pass",
                "compared": data.get("total", {}).get("compared", 0)}
    raise SystemExit(
        f"--install-app needs complete {'negative-control' if mutant else 'passing'} {key} evidence ({pattern} in "
        f"{tool_root}) for the current binary, source, harness and engine; run: OPENRC_NK_TOOL_ROOT={tool_root} "
        f"python research/native-kernel/run.py --script {nk.ORACLE_SCRIPTS[key]} {nk.ORACLE_ARGUMENTS[key]}")


def install_app(tool_root: Path) -> int:
    """Stage the verified Windows build under the ignored app/native/kernel/, beside (never over) Linux."""
    lock = locked.load_lock()
    built_path = tool_root / "build-receipt.json"
    library = tool_root / f"lib/{nk.NAME}.dll"
    if not built_path.is_file() or not library.is_file():
        raise SystemExit(f"No Windows build in {tool_root}; run build_windows.py first.")
    built = json.loads(built_path.read_text(encoding="utf-8"))
    expected_flags = [*lock["linux"]["floating_point_flags"], *lock["linux"]["exception_flags"], *nk.EXTRA_FLAGS, *WINDOWS_FLAGS]
    if built.get("cxxflags_appended") != expected_flags:
        raise SystemExit("The staged build used diagnostic or unexpected compiler flags; rebuild without --define.")
    if built.get("mutant") or built.get("platform") != "windows" or built.get("binary_sha256") != nk.sha256_file(library):
        raise SystemExit("The staged library does not match its Windows build receipt (or is the mutant).")
    sources = nk.mirrored_sources()
    if (built.get("source_sha256") != nk.source_digest() or built.get("reference_sources_sha256") != sources
            or built.get("builder_sha256") != nk.sha256_file(Path(__file__))
            or built.get("lock_sha256") != nk.sha256_file(locked.LOCK_PATH)
            or built.get("backend_version") != nk.BACKEND_VERSION or built.get("abi_version") != nk.ABI_VERSION):
        raise SystemExit("Native sources, mirrored sources, build policy or toolchain changed since the build; rebuild first.")
    verification = {key: find_verification(tool_root, key, pattern, built["binary_sha256"], sources)
                    for key, pattern in nk.VERIFICATIONS.items()}
    record = {
        "platform": "windows", "architecture": "x86_64", "backend": "native", "backend_version": nk.BACKEND_VERSION,
        "abi_version": nk.ABI_VERSION, "binary_sha256": built["binary_sha256"], "source_sha256": built["source_sha256"],
        "lock_sha256": built["lock_sha256"], "builder_sha256": built["builder_sha256"],
        "godot_cpp_commit": built["godot_cpp_commit"], "compiler": built["compiler"],
        "compiler_version": built["compiler_version"], "cxxflags_appended": built["cxxflags_appended"],
        "dll_math_imports": built["dll_math_imports"], "dll_imports": built["dll_imports"],
        "repository_head": built["repository_head"], "mirrored_sources": sources, "verification": verification,
        "engine_version": ENGINE_LABEL, "engine_sha256": nk.sha256_file(ENGINE_EXECUTABLE),
        "engine_wrapper_sha256": nk.sha256_file(ENGINE_WRAPPER),
    }
    receipt = {"format": nk.RECEIPT_FORMAT, "backend": "native", "backend_version": nk.BACKEND_VERSION,
               "abi_version": nk.ABI_VERSION, "platforms": {"windows": record}}
    destination = nk.APP_DESTINATION
    nk.prepare_manual_loading(ROOT / "app", destination)
    installed = destination / library.name
    if not installed.is_file() or nk.sha256_file(installed) != built["binary_sha256"]:
        staged = destination / (library.name + ".tmp")
        shutil.copy2(library, staged)
        staged.replace(installed)
    (destination / f"{nk.NAME}_windows.gdextension").write_text(WINDOWS_DESCRIPTOR, encoding="utf-8", newline="\n")
    (destination / "build-receipt-windows.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                                            encoding="utf-8", newline="\n")
    licence = locked.ensure_godot_cpp(lock) / "LICENSE.md"
    if not licence.is_file():
        raise SystemExit(f"Pinned godot-cpp licence not found at {licence}")
    shutil.copy2(licence, destination / "LICENSE.godot-cpp.md")
    print(json.dumps({k: record[k] for k in ("binary_sha256", "engine_sha256", "verification")}, indent=2))
    print(f"Installed the verified Windows native stage under {destination}.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--mutant", action="store_true", help="negative control: -DNK_MUTATION=1")
    parser.add_argument("--define", action="append", default=[],
                        help="diagnostic-only preprocessor define (e.g. NK_DEBUG_ECM); such builds are never installable")
    parser.add_argument("--install-app", action="store_true",
                        help="install the existing verified Windows build into the ignored app/native/kernel/ "
                             "(no rebuild); requires complete matching evidence for every installer gate")
    parser.add_argument("--tool-root", type=Path, default=Path(os.environ.get("OPENRC_NK_TOOL_ROOT", ROOT / "tmp/native-kernel")),
                        help="toolchain/build root (keep it off a nearly full system drive)")
    args = parser.parse_args()
    if locked.host_platform_name() != "windows" or locked.host_arch_name() != "x86_64":
        raise SystemExit("build_windows.py builds on a Windows x86_64 host.")
    tool_root = args.tool_root.resolve()
    locked.TOOL_ROOT = tool_root
    nk.TOOL_ROOT = tool_root
    if args.install_app:
        if args.mutant:
            parser.error("--install-app never installs the mutant")
        return install_app(tool_root)
    if shutil.disk_usage(tool_root.anchor).free < 4 * 1024**3:
        raise SystemExit(f"Less than 4 GB free on {tool_root.anchor}; refusing to build.")
    target = subprocess.run(["g++", "-dumpmachine"], check=True, text=True, capture_output=True).stdout.strip()
    if target != "x86_64-w64-mingw32":
        raise SystemExit(f"Expected a MinGW-w64 x86_64 g++, got target {target!r}.")
    compiler_version = subprocess.run(["g++", "-dumpfullversion", "-dumpversion"], check=True, text=True,
                                      capture_output=True).stdout.strip()
    lock = locked.load_lock()
    linux = lock["linux"]
    variant = "_mutant" if args.mutant else ""
    library_name = nk.NAME + variant
    scons = locked.ensure_scons(lock)
    godot_cpp = locked.ensure_godot_cpp(lock)
    build_dir = tool_root / f"build/windows-x86_64-template_release{variant}"
    build_dir.mkdir(parents=True, exist_ok=True)
    profile = lock["godot_cpp"]["build_profile"]
    profile_content = json.dumps(profile["content"], sort_keys=True, separators=(",", ":")) + "\n"
    if hashlib.sha256(profile_content.encode("utf-8")).hexdigest() != profile["sha256"]:
        raise SystemExit("Build profile SHA-256 mismatch.")
    profile_path = build_dir / "build_profile.json"
    profile_path.write_text(profile_content, encoding="utf-8")
    sconstruct = locked.sconstruct_text(godot_cpp, locked.SOURCES, build_dir / "lib", profile_path,
                                        lock["godot"]["extension_api"])
    default_fp = 'env.Append(CXXFLAGS=["-fno-fast-math", "-ffp-contract=off"])'
    # Same numerical policy as Linux; static libgcc/libstdc++ so the DLL needs only system DLLs.
    flags = [*linux["floating_point_flags"], *linux["exception_flags"], *nk.EXTRA_FLAGS, *WINDOWS_FLAGS,
             *(["-DNK_MUTATION=1"] if args.mutant else []), *[f"-D{name}" for name in args.define]]
    if sconstruct.count(default_fp) != 1 or sconstruct.count("openrc_slipstream") != 1:
        raise SystemExit("Shared SConstruct template changed; update this adapter.")
    sconstruct = sconstruct.replace(default_fp, f"env.Append(CXXFLAGS={json.dumps(flags)})\n"
                                    '    env.Append(LINKFLAGS=["-static-libgcc", "-static-libstdc++"])')
    (build_dir / "SConstruct").write_text(sconstruct.replace("openrc_slipstream", library_name), encoding="utf-8")
    log_path = tool_root / f"build-windows{variant}.log"
    with log_path.open("w", encoding="utf-8") as log:
        result = subprocess.run([*scons, "-C", str(build_dir), f"-j{args.jobs}", "platform=windows", "use_mingw=yes",
                                 "arch=x86_64", "target=template_release", "verbose=yes"],
                                stdout=log, stderr=subprocess.STDOUT, text=True)
    if result.returncode != 0:
        print("\n".join(log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-40:]))
        raise SystemExit(f"SCons failed ({result.returncode}); full log: {log_path}")
    candidates = sorted((build_dir / "lib").glob(f"*{library_name}*.dll"))
    if len(candidates) != 1:
        raise SystemExit(f"Expected one {library_name} DLL in {build_dir / 'lib'}, found {candidates}.")
    library = tool_root / f"lib/{library_name}.dll"
    library.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(candidates[0], library)
    imports = dll_imports(library)
    math_imports = {dll: [n for n in names if n in MATH_NAMES] for dll, names in imports.items()}
    math_imports = {dll: names for dll, names in math_imports.items() if names}
    unexpected = [f"{dll}:{n}" for dll, names in math_imports.items() for n in names
                  if dll.lower() != "msvcrt.dll" or n not in ENGINE_MSVCRT_MATH]
    if unexpected:
        raise SystemExit(f"Math imported differently from the engine: {unexpected}")
    allowed_dlls = {"kernel32.dll", "msvcrt.dll", "user32.dll"}
    foreign = [dll for dll in imports if dll.lower() not in allowed_dlls and not dll.lower().startswith("api-ms-win")]
    if foreign:
        raise SystemExit(f"DLL depends on non-system libraries: {foreign}")
    descriptor = tool_root / f"{library_name}.gdextension"
    descriptor.write_text(
        "; NK-4 Windows research descriptor, generated by research/native-kernel/build_windows.py; run time only.\n"
        "[configuration]\n"
        f'entry_symbol = "{nk.NAME}_library_init"\n'
        'compatibility_minimum = "4.7"\n'
        "reloadable = false\n\n"
        "[libraries]\n"
        f'windows.x86_64 = "lib/{library_name}.dll"\n', encoding="utf-8")
    receipt = {
        "library": str(library), "descriptor": str(descriptor), "mutant": args.mutant,
        "binary_sha256": nk.sha256_file(library), "source_sha256": nk.source_digest(),
        "backend_version": nk.BACKEND_VERSION, "abi_version": nk.ABI_VERSION,
        "lock_sha256": nk.sha256_file(locked.LOCK_PATH), "builder_sha256": nk.sha256_file(Path(__file__)),
        "linux_builder_sha256": nk.sha256_file(HERE / "build.py"),
        "godot_cpp_commit": locked.run(["git", "rev-parse", "HEAD"], cwd=godot_cpp, capture=True).strip(),
        "scons_wheel_sha256": lock["scons"]["wheel_sha256"], "compiler": f"g++ {compiler_version} {target}",
        "compiler_version": compiler_version, "cxxflags_appended": flags, "target": "template_release",
        "platform": "windows", "architecture": "x86_64", "dll_math_imports": math_imports,
        "dll_imports": sorted(imports), "repository_head": locked.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture=True).strip(),
        "reference_sources_sha256": nk.mirrored_sources(),
    }
    (tool_root / f"build-receipt{variant}.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                                          encoding="utf-8")
    print(json.dumps({k: receipt[k] for k in ["library", "binary_sha256", "compiler", "dll_math_imports", "dll_imports"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
