#!/usr/bin/env python3
"""Check release source identity and pinned inputs before native/export jobs."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess

TAG = re.compile(r"v([0-9]+\.[0-9]+\.[0-9]+)(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?\Z")
COMMIT = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
REQUIRED_FILES = (
    "app/project.godot", "app/export.sh", "app/export_presets.cfg", "app/get-godot.sh",
    "app/get-templates.sh", "tools/godot/macos_universal_template.py",
    "tools/release/manifest.py", "tools/release/elf_audit.py",
    "research/native-kernel/toolchain-lock.json", "research/native-kernel/package.py",
    "research/rc-monster-truck/native/toolchain-lock.json",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def git(root, *args, check=True):
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, check=False)
    if check and result.returncode:
        raise ValueError(f"git {' '.join(args)} failed")
    return result


def single(pattern, text, label):
    matches = re.findall(pattern, text, re.MULTILINE)
    require(len(matches) == 1, f"expected one {label}")
    return matches[0]


def godot_uid_sidecars(root):
    # Import generates missing sidecars and would invalidate the selected clean
    # export identity. Catch that source omission before native builds or import.
    tracked = {name.decode("utf-8") for name in
               git(root, "ls-files", "-z", "--", "app/").stdout.split(b"\0") if name}
    invalid = []
    for name in sorted(tracked):
        if not name.endswith((".gd", ".gdshader")):
            continue
        sidecar = name + ".uid"
        path = root / sidecar
        if (sidecar not in tracked or not path.is_file() or path.is_symlink()
                or path.stat().st_size == 0):
            invalid.append(sidecar)
    require(not invalid,
            f"missing or invalid tracked Godot UID sidecars ({len(invalid)}): "
            + json.dumps(invalid[:20]) + (" ..." if len(invalid) > 20 else "")
            + "; generate with the pinned editor and commit them with their scripts/shaders")


def pinned_prerequisites(root):
    for name in REQUIRED_FILES:
        path = root / name
        require(path.is_file() and not path.is_symlink() and path.stat().st_size > 0,
                f"missing or invalid prerequisite: {name}")
        require(git(root, "ls-files", "--error-unmatch", "--", name, check=False).returncode == 0,
                f"untracked prerequisite: {name}")
    editor = (root / "app/get-godot.sh").read_text(encoding="utf-8")
    templates = (root / "app/get-templates.sh").read_text(encoding="utf-8")
    version = single(r"^VERSION=([0-9A-Za-z][0-9A-Za-z.+-]*)$", editor, "editor version")
    engine = single(r"^ENGINE_VERSION=([0-9A-Za-z][0-9A-Za-z.+-]*)$", editor, "engine identity")
    require(single(r"^VERSION=([0-9A-Za-z][0-9A-Za-z.+-]*)$", templates,
                   "template version") == version, "editor and template versions differ")
    for script, count, label in ((editor, 3, "editor"), (templates, 1, "template")):
        hashes = re.findall(r"^\s*SHA512=([^\s]+)$", script, re.MULTILINE)
        require(len(hashes) == count and all(re.fullmatch(r"[0-9a-f]{128}", h) for h in hashes),
                f"invalid pinned {label} archive hashes")
    block = single(r"^MEMBER_SHA512=\(\s*([\s\S]*?)^\)", templates, "template member hashes")
    members = block.split()
    require(len(members) == 4 and all(re.fullmatch(r"[0-9a-f]{128}", h) for h in members),
            "invalid pinned template member hashes")
    locks = []
    for name in ("research/native-kernel/toolchain-lock.json",
                 "research/rc-monster-truck/native/toolchain-lock.json"):
        lock = json.loads((root / name).read_text(encoding="utf-8"))
        require(lock["schema_version"] == 1 and lock["godot"]["version"] == engine,
                f"invalid engine lock: {name}")
        require(re.fullmatch(r"[0-9a-f]{40}", lock["godot_cpp"]["commit"]) is not None,
                f"invalid godot-cpp commit pin: {name}")
        require(re.fullmatch(r"[0-9a-f]{64}", lock["scons"]["wheel_sha256"]) is not None,
                f"invalid SCons hash pin: {name}")
        require(re.fullmatch(r"[0-9]+(?:\.[0-9]+)+", lock["scons"]["version"]) is not None,
                f"invalid SCons version pin: {name}")
        locks.append(lock)
    require(locks[0]["godot_cpp"]["commit"] == locks[1]["godot_cpp"]["commit"]
            and locks[0]["scons"] == locks[1]["scons"], "native toolchain pins differ")


def preflight(root, event, ref, sha):
    root = Path(root).resolve()
    require(COMMIT.fullmatch(sha) is not None, "expected a full lowercase source SHA")
    require(event in ("push", "pull_request", "workflow_dispatch"), "unsupported event")
    require(git(root, "check-ref-format", ref, check=False).returncode == 0, "invalid event ref")
    if event == "pull_request":
        require(re.fullmatch(r"refs/pull/[1-9][0-9]*/merge", ref) is not None, "invalid PR merge ref")
    else:
        require(ref.startswith(("refs/heads/", "refs/tags/")), "invalid push/dispatch ref")
    head = git(root, "rev-parse", "HEAD^{commit}").stdout.decode("ascii").strip()
    require(head == sha, "checked source does not match event SHA")
    require(git(root, "diff", "--quiet", "HEAD", "--", check=False).returncode == 0,
            "tracked source changed after checkout")
    require(not git(root, "ls-files", "--others", "--exclude-standard", "-z", "--", "app/").stdout,
            "untracked application source")
    pinned_prerequisites(root)
    godot_uid_sidecars(root)
    project = (root / "app/project.godot").read_text(encoding="utf-8")
    numeric = single(r'^config/version="([0-9]+\.[0-9]+\.[0-9]+)"$', project, "project version")
    tag = None
    if ref.startswith("refs/tags/"):
        tag = ref.removeprefix("refs/tags/")
        match = TAG.fullmatch(tag)
        require(match is not None and len(tag) <= 160, "invalid release tag")
        require(match.group(1) == numeric, "release tag/project version mismatch")
        tagged = git(root, "rev-parse", f"{ref}^{{commit}}").stdout.decode("ascii").strip()
        require(tagged == sha, "release tag does not identify checked source")
        notes = root / "docs/releases" / f"{tag}.md"
        require(notes.is_file() and not notes.is_symlink() and notes.stat().st_size > 0,
                "missing or empty release notes")
        require(git(root, "ls-files", "--error-unmatch", "--", str(notes.relative_to(root)),
                    check=False).returncode == 0, "release notes are not tracked")
    else:
        # app/export.sh enforces this when git describe selects an exact version tag.
        exact = git(root, "describe", "--exact-match", "--tags", "HEAD", check=False)
        if exact.returncode == 0:
            version = re.match(r"^v([0-9]+\.[0-9]+\.[0-9]+)", exact.stdout.decode("utf-8").strip())
            require(version is None or version.group(1) == numeric, "exact tag/project version mismatch")
    return {"source": sha, "ref": ref, "event": event, "tag": tag, "project_version": numeric}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--event", required=True)
    parser.add_argument("--ref", required=True)
    parser.add_argument("--sha", required=True)
    args = parser.parse_args()
    try:
        result = preflight(args.root, args.event, args.ref, args.sha)
        print("Release preflight passed: " + json.dumps(result, sort_keys=True))
    except (OSError, ValueError, KeyError, TypeError, UnicodeError) as error:
        parser.exit(1, f"Release preflight failed: {error}\n")


if __name__ == "__main__":
    main()
