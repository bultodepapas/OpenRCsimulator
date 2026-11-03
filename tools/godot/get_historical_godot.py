"""Obtain the pinned beta1 editor needed by the GP-12 historical gate.

This is separate from the current-engine getter. Existing files are verified,
never replaced, and an incomplete cache must be inspected before retrying.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile

HISTORICAL_VERSION = "4.8.beta1.official.4d10419ca"
ENGINE_LINUX_SHA512 = "e5a41b16a00a5f73c533135544754f175897b14feb77ef03d7d2bc6fd59163bb78444752d06641a24fb790fbdf0412e7a02dd14bf4406b641a312a903856a814"
ENGINE_WINDOWS_CONSOLE_SHA512 = "c01f16cada68a8180f5c002e90b727015e136cf36342ac6a2ce222d26aba617b011545b73ff6ce9b9420ed1e29d62a43edb2c8b64e9805dc242506e0cd49b5dd"
ENGINE_WINDOWS_SHA512 = "7b8c3a09e1beabe120789b7a325d017eb2103b69bb6f8e9b4678e51a1521bfe4071a12841c1784d289147fb7ae60e73895fadd1f67633788367eec208bc7fabe"
MAX_ARCHIVE_BYTES = 256 * 1024 * 1024
MAX_MEMBER_BYTES = 512 * 1024 * 1024


@dataclass(frozen=True)
class Editor:
    archive: str
    archive_sha512: str
    executable: str
    binaries: dict[str, str]


EDITORS = {
    "Linux": Editor(
        "Godot_v4.8-beta1_linux.x86_64.zip",
        "aee4cbf3c5f86eee875c0f2f77cc9d816a3fbb220774e6ffc95fd5a557a6c5ec917f2b6118c0aa2008bd10f4b2a021225dc78ba7b7c54745411e0f2721f70a67",
        "Godot_v4.8-beta1_linux.x86_64",
        {"Godot_v4.8-beta1_linux.x86_64": ENGINE_LINUX_SHA512},
    ),
    "Windows": Editor(
        "Godot_v4.8-beta1_win64.exe.zip",
        "bdc79f8ef47c3794c6984751bbac2c1934cf1c7c9ceebc2d0e87db0846766411b7bbbb6fecf90f3485f951a1289c3171b1c7bebca18dcdd8e08bd81de95b6cc0",
        "Godot_v4.8-beta1_win64_console.exe",
        {"Godot_v4.8-beta1_win64.exe": ENGINE_WINDOWS_SHA512,
         "Godot_v4.8-beta1_win64_console.exe": ENGINE_WINDOWS_CONSOLE_SHA512},
    ),
}


def sha512(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha512").hexdigest()


def verify_editor(directory: Path, editor: Editor) -> Path:
    for name, expected in editor.binaries.items():
        path = directory / name
        if path.is_symlink() or not path.is_file() or sha512(path) != expected:
            raise ValueError("historical editor cache is incomplete or changed; retained for inspection: " + str(path))
    executable = directory / editor.executable
    if subprocess.check_output([str(executable), "--version"], text=True).strip() != HISTORICAL_VERSION:
        raise ValueError("historical editor version differs: " + str(executable))
    return executable


def download(url: str, path: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "OpenRC-fixed-brake-gate"})
    count = 0
    with urllib.request.urlopen(request, timeout=120) as response, path.open("xb") as output:
        while chunk := response.read(1024 * 1024):
            count += len(chunk)
            if count > MAX_ARCHIVE_BYTES:
                raise ValueError("historical editor archive exceeds the size limit")
            output.write(chunk)


def ensure_editor(tools_dir: Path, editor: Editor) -> Path:
    tools_dir.mkdir(parents=True, exist_ok=True)
    paths = [tools_dir / name for name in editor.binaries]
    if all(path.is_file() and not path.is_symlink() for path in paths):
        try:
            return verify_editor(tools_dir, editor)
        except (OSError, ValueError, subprocess.CalledProcessError):
            # A publisher may still be writing; diagnose again under the lock.
            pass
    lock = tools_dir / ".fixed-brake-beta1.lock"
    try:
        lock.mkdir()
    except FileExistsError as error:
        raise ValueError("historical editor cache is locked; inspect a stale lock: " + str(lock)) from error
    try:
        if any(path.exists() or path.is_symlink() for path in paths):
            return verify_editor(tools_dir, editor)
        with tempfile.TemporaryDirectory(prefix=".fixed-brake-beta1-", dir=tools_dir) as tmp:
            staging = Path(tmp)
            archive = staging / editor.archive
            url = "https://github.com/godotengine/godot-builds/releases/download/4.8-beta1/" + editor.archive
            download(url, archive)
            if sha512(archive) != editor.archive_sha512:
                raise ValueError("historical editor archive failed the official SHA-512 check")
            try:
                with zipfile.ZipFile(archive) as source:
                    members = source.infolist()
                    if len(members) != len(editor.binaries) or {m.filename for m in members} != set(editor.binaries):
                        raise ValueError("historical editor archive contents differ")
                    for member in members:
                        if member.is_dir() or member.file_size > MAX_MEMBER_BYTES:
                            raise ValueError("invalid historical editor archive member: " + member.filename)
                        with source.open(member) as src, (staging / member.filename).open("xb") as dst:
                            shutil.copyfileobj(src, dst, length=1024 * 1024)
            except zipfile.BadZipFile as error:
                raise ValueError("historical editor archive is invalid") from error
            if os.name != "nt":
                (staging / editor.executable).chmod(0o755)
            verify_editor(staging, editor)
            for name in editor.binaries:
                with (staging / name).open("rb") as src, (tools_dir / name).open("xb") as dst:
                    shutil.copyfileobj(src, dst, length=1024 * 1024)
                if os.name != "nt":
                    (tools_dir / name).chmod(0o755)
        return verify_editor(tools_dir, editor)
    finally:
        lock.rmdir()


def ensure_historical_godot(repo: Path) -> Path:
    system = platform.system()
    if system not in EDITORS or platform.machine().lower() not in {"x86_64", "amd64"}:
        raise ValueError("no pinned historical fixed-brake engine for this host")
    return ensure_editor(repo / ".tools", EDITORS[system])
