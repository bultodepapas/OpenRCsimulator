"""Copy the current source tree to a NEW directory, normalizing text files only there.

Windows checkouts can carry CRLF in Bash files. This preserves concurrent live edits
and provides a source hash manifest for an isolated Linux app/test.sh run.
Generated text fixtures also require LF for their byte-for-byte generator checks.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

TEXT_SUFFIXES = {".sh", ".gd", ".gdshader", ".gdshaderinc", ".json", ".py", ".md",
                 ".godot", ".tscn", ".tres", ".csv", ".txt", ".po", ".yml", ".yaml",
                 ".toml", ".cfg", ".ini", ".svg", ".html", ".js", ".ts", ".css", ".mjs"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[2]
    target = args.destination.resolve()
    target.mkdir(parents=True, exist_ok=False)
    # Preserve the real HEAD for replay/build stamps without checking out over the
    # working source copied below. A fresh `git init` has no commit and falsely
    # fails the replay provenance check. The shallow clone stays self-contained.
    subprocess.run(["git", "clone", "--quiet", "--no-checkout", "--depth", "1",
                    "--no-local", str(source), str(target)], check=True)
    subprocess.run(["git", "-C", str(target), "read-tree", "HEAD"], check=True)
    names = subprocess.check_output(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=source
    ).decode().split("\0")
    manifest = {}
    for name in sorted(set(names) - {""}):
        origin = source / name
        if not origin.is_file():
            continue
        data = origin.read_bytes()
        manifest[name] = hashlib.sha256(data).hexdigest()
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data.replace(b"\r\n", b"\n") if origin.suffix in TEXT_SUFFIXES else data)
        if name.endswith(".sh"):
            destination.chmod(0o755)
    (target / "source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    binary = source / ".tools/Godot_v4.8-beta1_linux.x86_64"
    if binary.exists():
        (target / ".tools").mkdir()
        copied = target / ".tools" / binary.name
        shutil.copy2(binary, copied)
        copied.chmod(0o755)
    print(f"Snapshot: {target}; {len(manifest)} files; live source unchanged")


if __name__ == "__main__":
    main()
