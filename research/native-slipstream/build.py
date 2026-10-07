#!/usr/bin/env python3
"""Build the Gate-P GDExtension with locked, repository-local dependencies."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform as host_platform
import shutil
import subprocess
import sys
import urllib.request
import venv
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LOCK_PATH = Path(__file__).with_name("toolchain-lock.json")
TOOL_ROOT = ROOT / ".tools" / "native-slipstream"
SOURCES = Path(__file__).resolve().parent / "src"


def run(
    command: list[str],
    *,
    cwd: Path | None = None,
    capture: bool = False,
    env: dict[str, str] | None = None,
) -> str:
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )
    return result.stdout or ""


def host_platform_name() -> str:
    if sys.platform.startswith("linux"):
        return "linux"
    if sys.platform == "win32":
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    raise SystemExit(f"Unsupported host platform: {sys.platform}")


def host_arch_name() -> str:
    machine = host_platform.machine().lower()
    if machine in {"x86_64", "amd64"}:
        return "x86_64"
    if machine in {"arm64", "aarch64"}:
        return "arm64"
    raise SystemExit(f"Unsupported host architecture: {machine}")


def load_lock() -> dict:
    with LOCK_PATH.open(encoding="utf-8") as lock_file:
        return json.load(lock_file)


def venv_python(venv_dir: Path) -> Path:
    if os.name == "nt":
        return venv_dir / "Scripts" / "python.exe"
    return venv_dir / "bin" / "python"


def scons_command(python: Path) -> list[str]:
    return [str(python), "-m", "SCons"]


def ensure_scons(lock: dict) -> Path:
    if sys.version_info < (3, 9):
        raise SystemExit("Python 3.9 or newer is required by the Godot 4.7 build tools.")

    scons = lock["scons"]
    venv_dir = TOOL_ROOT / "venv"
    python = venv_python(venv_dir)
    if not python.is_file():
        # --without-pip keeps this bootstrap usable on Ubuntu installations
        # that omit python3-venv's ensurepip payload.
        venv.EnvBuilder(with_pip=False).create(venv_dir)

    wheel = TOOL_ROOT / "downloads" / scons["wheel_filename"]
    wheel.parent.mkdir(parents=True, exist_ok=True)
    if not wheel.is_file():
        request = urllib.request.Request(scons["wheel_url"], headers={"User-Agent": "OpenRCsimulator-Gate-P/1"})
        with urllib.request.urlopen(request, timeout=60) as response:
            wheel.write_bytes(response.read())

    actual_hash = hashlib.sha256(wheel.read_bytes()).hexdigest()
    if actual_hash != scons["wheel_sha256"]:
        wheel.unlink(missing_ok=True)
        raise SystemExit(
            f"SCons wheel SHA-256 mismatch: expected {scons['wheel_sha256']}, got {actual_hash}."
        )

    if os.name == "nt":
        site_packages = venv_dir / "Lib" / "site-packages"
    else:
        site_packages = venv_dir / "lib" / f"python{sys.version_info.major}.{sys.version_info.minor}" / "site-packages"
    site_packages.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(wheel) as wheel_archive:
        wheel_archive.extractall(site_packages)

    command = scons_command(python)
    version_output = run([*command, "--version"], capture=True)
    expected = f"SCons: v{scons['version']}"
    if expected not in version_output:
        raise SystemExit(f"Expected {expected}; got {version_output.strip()}.")
    return command


def ensure_godot_cpp(lock: dict) -> Path:
    dependency = lock["godot_cpp"]
    checkout = TOOL_ROOT / "godot-cpp"
    if not (checkout / ".git").exists():
        checkout.parent.mkdir(parents=True, exist_ok=True)
        run(
            [
                "git",
                "clone",
                "--depth",
                "1",
                "--branch",
                dependency["tag"],
                "--recurse-submodules",
                dependency["url"],
                str(checkout),
            ]
        )

    actual_commit = run(["git", "rev-parse", "HEAD"], cwd=checkout, capture=True).strip()
    if actual_commit != dependency["commit"]:
        raise SystemExit(
            "The local godot-cpp checkout is not the locked revision. "
            f"Expected {dependency['commit']}, got {actual_commit}; remove {checkout} and retry."
        )
    dirty_tracked = run(
        ["git", "status", "--porcelain", "--untracked-files=no"], cwd=checkout, capture=True
    ).strip()
    if dirty_tracked:
        raise SystemExit(
            "The pinned godot-cpp checkout has tracked local changes; restore or remove "
            f"{checkout} before building."
        )
    if not (checkout / "gdextension" / "extension_api-4-7.json").is_file():
        raise SystemExit("The pinned godot-cpp checkout does not contain the Godot 4.7 API file.")
    return checkout


def sconstruct_text(
    godot_cpp_dir: Path,
    source_dir: Path,
    output_dir: Path,
    profile_path: Path,
    api_version: str,
) -> str:
    return f'''#!/usr/bin/env python
import os

from SCons.Script import Default, Environment, Glob, SConscript

godot_cpp_dir = os.path.abspath({str(godot_cpp_dir)!r})
source_dir = os.path.abspath({str(source_dir)!r})
output_dir = os.path.abspath({str(output_dir)!r})
profile_path = os.path.abspath({str(profile_path)!r})
api_version = {api_version!r}

sources = sorted(Glob(os.path.join(source_dir, "*.cpp")), key=lambda source: str(source))
if not sources:
    raise RuntimeError("No C++ sources found in " + source_dir)

env = Environment(tools=["default"], PLATFORM="")
env["build_profile"] = profile_path
env = SConscript(
    os.path.join(godot_cpp_dir, "SConstruct"),
    exports={{"api_version": api_version, "env": env}},
)

# Keep the numerical kernel on strict IEEE-style floating-point semantics.
# Apply these after importing godot-cpp so the bindings and extension share the policy.
if env["platform"] == "windows" and not env.get("use_mingw", False):
    env.Append(CXXFLAGS=["/fp:strict"])
else:
    env.Append(CXXFLAGS=["-fno-fast-math", "-ffp-contract=off"])
    if env["platform"] == "macos":
        env.Append(CXXFLAGS=["-ffp-model=strict"])

env.Append(CPPPATH=[source_dir])
os.makedirs(output_dir, exist_ok=True)
library_filename = env.subst("$SHLIBPREFIX") + "openrc_slipstream" + env.subst("$SHLIBSUFFIX")
object_dir = os.path.join(output_dir, "obj")
os.makedirs(object_dir, exist_ok=True)
objects = [
    env.SharedObject(
        target=os.path.join(object_dir, os.path.basename(str(source)) + env.subst("$OBJSUFFIX")),
        source=source,
    )
    for source in sources
]
library = env.SharedLibrary(os.path.join(output_dir, library_filename), source=objects)
env.NoCache(library)
Default(library)
'''


def expected_library_name(platform_name: str) -> str:
    if platform_name == "windows":
        return "openrc_slipstream.dll"
    if platform_name == "macos":
        return "libopenrc_slipstream.dylib"
    return "libopenrc_slipstream.so"


def main() -> int:
    lock = load_lock()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        help="destination library path (relative paths are relative to the repository root)",
    )
    parser.add_argument("--platform", choices=("linux", "windows", "macos"), default=host_platform_name())
    parser.add_argument("--arch", choices=("x86_64", "arm64"), default=host_arch_name())
    parser.add_argument("--target", choices=("template_debug", "template_release"), default="template_release")
    parser.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    parser.add_argument("--verbose", action="store_true", help="print full compiler and linker commands")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")
    if args.platform != host_platform_name():
        parser.error("Cross-platform builds are not configured; run this command on the target OS.")

    output = args.output or (ROOT / ".tools" / "native-slipstream" / expected_library_name(args.platform))
    if not output.is_absolute():
        output = ROOT / output
    output = output.resolve()

    if not SOURCES.is_dir() or not list(SOURCES.glob("*.cpp")):
        raise SystemExit(f"Expected native C++ sources under {SOURCES}; none were found.")

    build_env = os.environ.copy()
    if args.platform == "linux":
        linux_lock = lock["linux"]
        compiler_version = run(["g++", "-dumpfullversion", "-dumpversion"], capture=True).strip()
        if compiler_version != linux_lock["compiler_version"]:
            raise SystemExit(
                f"Linux build is pinned to g++ {linux_lock['compiler_version']}; "
                f"found {compiler_version}."
            )
        build_env["CC"] = "gcc"
        build_env["CXX"] = "g++"

    scons = ensure_scons(lock)
    godot_cpp = ensure_godot_cpp(lock)
    api_version = lock["godot"]["extension_api"]
    build_dir = TOOL_ROOT / "build" / f"{args.platform}-{args.arch}-{args.target}"
    build_dir.mkdir(parents=True, exist_ok=True)
    profile = lock["godot_cpp"]["build_profile"]
    profile_path = build_dir / "build_profile.json"
    profile_content = json.dumps(profile["content"], sort_keys=True, separators=(",", ":")) + "\n"
    profile_digest = hashlib.sha256(profile_content.encode("utf-8")).hexdigest()
    if profile_digest != profile["sha256"]:
        raise SystemExit(
            f"Build profile SHA-256 mismatch: expected {profile['sha256']}, got {profile_digest}."
        )
    profile_path.write_text(profile_content, encoding="utf-8")
    output_dir = build_dir / "lib"
    (build_dir / "SConstruct").write_text(
        sconstruct_text(godot_cpp, SOURCES, output_dir, profile_path, api_version), encoding="utf-8"
    )

    run(
        [
            *scons,
            "-C",
            str(build_dir),
            f"-j{args.jobs}",
            f"platform={args.platform}",
            f"arch={args.arch}",
            f"target={args.target}",
            *(["verbose=yes"] if args.verbose else []),
        ],
        env=build_env,
    )

    built_library = build_dir / "lib" / expected_library_name(args.platform)
    if not built_library.is_file():
        raise SystemExit(f"SCons finished without producing {built_library}.")
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(built_library, output)
    print(f"Built {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
