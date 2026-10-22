#!/usr/bin/env python3
"""F4U-04: deliberate mutations of an accepted GLB must make preflight_glb.py exit nonzero.

Uses the shipped Timber r2 GLB as a known-good sectioned asset, writes each mutation to a disposable temporary
copy and never touches the original.

    python research/f4u-corsair/F4U-04/test_preflight_glb.py
"""
import json
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASE = ROOT / "app/assets/aircraft/turbo-lumber-evolution/timber.glb"
TOOL = HERE / "preflight_glb.py"
sys.path.insert(0, str(HERE))
import preflight_glb  # noqa: E402


def write_glb(path, gltf, binary):
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    length = 12 + 8 + len(text) + 8 + len(binary)
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, length) + struct.pack("<II", len(text), 0x4E4F534A) + text
                     + struct.pack("<II", len(binary), 0x004E4942) + binary)


def run(path, profile="generic"):
    return subprocess.run([sys.executable, "-I", str(TOOL), str(path), "--profile", profile],
                          capture_output=True, text=True).returncode


def first(gltf, predicate):
    return next(index for index, node in enumerate(gltf["nodes"]) if predicate(node))


def section(node):
    return (node.get("extras") or {}).get("openrc_section")


def main():
    gltf, binary = preflight_glb.read_glb(BASE)
    checks, failures = 0, 0

    def expect(label, passed):
        nonlocal checks, failures
        checks += 1
        if not passed:
            failures += 1
            print("FAIL", label)

    mutations = {}

    def mutation(name):
        def register(function):
            mutations[name] = function
            return function
        return register

    @mutation("missing section on a mesh")
    def _(g):
        del g["nodes"][first(g, lambda n: "mesh" in n and section(n))]["extras"]["openrc_section"]

    @mutation("invalid section value")
    def _(g):
        g["nodes"][first(g, lambda n: "mesh" in n and section(n))]["extras"]["openrc_section"] = "left_wing"

    @mutation("non-unit node scale")
    def _(g):
        g["nodes"][first(g, lambda n: "mesh" in n)]["scale"] = [2.0, 2.0, 2.0]

    @mutation("duplicate node name")
    def _(g):
        meshes = [i for i, n in enumerate(g["nodes"]) if "mesh" in n]
        g["nodes"][meshes[1]]["name"] = g["nodes"][meshes[0]]["name"]

    @mutation("engine captures propeller")
    def _(g):
        engine = first(g, lambda n: section(n) == "engine")
        rotor = first(g, lambda n: section(n) == "propeller")
        for node in g["nodes"]:
            if rotor in node.get("children", []):
                node["children"].remove(rotor)
        g["nodes"][engine].setdefault("children", []).append(rotor)

    @mutation("animation present")
    def _(g):
        g["animations"] = [{"channels": [], "samplers": []}]

    with tempfile.TemporaryDirectory() as directory:
        expect("unmodified copy passes the generic profile", run(BASE) == 0)
        for name, function in mutations.items():
            copy = json.loads(json.dumps(gltf))
            function(copy)
            path = Path(directory) / "mutated.glb"
            write_glb(path, copy, binary)
            expect(f"preflight rejects: {name}", run(path) == 1)
        expect("strict profile rejects a non-F4U asset", run(BASE, "f4u-g1") == 1)
        bad = Path(directory) / "broken.glb"
        bad.write_bytes(b"not a glb")
        expect("unreadable input exits 2", run(bad) == 2)
    print(f"F4U-04 preflight mutations: {checks} checks, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
