"""GDU-00: list app code exposed to known Godot 4.8 changes. Read-only; stdlib only.

Usage: python -I research/engine-upgrade/gdu00_exposure.py [--json]
Re-run at each 4.8 candidate (beta/RC/stable) and compare with the GDU-00 record.
"""
import json
import pathlib
import re
import subprocess
import sys

APP = pathlib.Path(__file__).resolve().parents[2] / "app"


def tracked(*patterns):
    out = subprocess.run(["git", "-C", str(APP), "ls-files", *patterns], capture_output=True, text=True, check=True)
    return [APP / p for p in out.stdout.split()]


def expand(path, seen):
    """Shader source with `#include "res://..."` inlined (each include once)."""
    if path in seen or not path.exists():
        return ""
    seen.add(path)
    text = path.read_text(encoding="utf-8", errors="ignore")
    return re.sub(r'#include\s+"res://([^"]+)"', lambda m: expand(APP / m.group(1), seen), text)


def shader_globals():
    """godot#124742: Compatibility reads non-sampler globals wrongly with >= 4 sampler2D uniforms."""
    rows = []
    for path in tracked("*.gdshader"):
        text = expand(path, set())
        globals_ = [t for t in re.findall(r"global uniform\s+(\w+)", text) if not t.startswith("sampler")]
        samplers = len(re.findall(r"uniform\s+sampler2D\w*", text))
        if globals_:
            rows.append({"shader": path.relative_to(APP).as_posix(), "globals": len(globals_),
                         "sampler2D": samplers, "exposed_124742": samplers >= 4})
    return rows


def version_pins():
    """Literal engine-version identities that an upgrade must bump deliberately."""
    pattern = re.compile(r'"4\.7(\.2)?(\.stable|-stable)?"|4\.7\.2-stable|VERSION=4\.7')
    rows = []
    for path in tracked("*.gd", "*.sh", "*.py", "*.cfg", "*.godot", "*.gdextension"):
        for number, line in enumerate(path.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
            if pattern.search(line):
                rows.append({"file": path.relative_to(APP).as_posix(), "line": number, "text": line.strip()[:140]})
    return rows


def main():
    report = {"shader_globals": shader_globals(), "version_pins": version_pins()}
    if "--json" in sys.argv:
        print(json.dumps(report, indent=1))
        return
    exposed = [r for r in report["shader_globals"] if r["exposed_124742"]]
    print(f"shaders with non-sampler globals: {len(report['shader_globals'])}; exposed to #124742: {len(exposed)}")
    for r in exposed:
        print(f"  {r['shader']}  globals={r['globals']} sampler2D={r['sampler2D']}")
    print(f"engine version pins: {len(report['version_pins'])}")
    for r in report["version_pins"]:
        print(f"  {r['file']}:{r['line']}  {r['text']}")


if __name__ == "__main__":
    main()
