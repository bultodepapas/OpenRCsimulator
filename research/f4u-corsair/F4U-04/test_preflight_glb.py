#!/usr/bin/env python3
"""F4U-04: deliberate mutations of an accepted GLB must make preflight_glb.py exit nonzero.

Uses the shipped Timber r2 GLB as a known-good sectioned asset and the Avanti GLB (exported with its retractable
gear stowed) for the stowed-gear rule. For the skin-orientation rule (F4U-18) it uses the frozen g1.13 Corsair, whose
fuselage is inside out, and a copy with that mesh's triangle winding reversed; the shipped g2.1 Corsair must pass the
g2 profile (F4U-19). Writes each mutation to a disposable temporary copy and never touches the originals.

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
STOWED = ROOT / "app/assets/aircraft/avanti-s-a200/avanti_s.glb"
CORSAIR = ROOT / "assets/source-deliveries/f4u-corsair-g1-13/f4u_corsair/g1_13/export/aircraft.glb"
SHIPPED = ROOT / "app/assets/aircraft/f4u-corsair-250/f4u_corsair.glb"
TOOL = HERE / "preflight_glb.py"
INDEX_FORMATS = {5121: "B", 5123: "H", 5125: "I"}
sys.path.insert(0, str(HERE))
import preflight_glb  # noqa: E402


def write_glb(path, gltf, binary):
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    length = 12 + 8 + len(text) + 8 + len(binary)
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, length) + struct.pack("<II", len(text), 0x4E4F534A) + text
                     + struct.pack("<II", len(binary), 0x004E4942) + binary)


def run(path, profile="generic", *extra):
    return subprocess.run([sys.executable, "-I", str(TOOL), str(path), "--profile", profile, *extra],
                          capture_output=True, text=True).returncode


def first(gltf, predicate):
    return next(index for index, node in enumerate(gltf["nodes"]) if predicate(node))


def section(node):
    return (node.get("extras") or {}).get("openrc_section")


def reverse_winding(gltf, binary, name):
    """Return a copy of the binary chunk with every triangle of mesh node `name` wound the other way."""
    out = bytearray(binary)
    node = gltf["nodes"][first(gltf, lambda n: n.get("name") == name)]
    for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
        accessor = gltf["accessors"][primitive["indices"]]
        fmt = INDEX_FORMATS[accessor["componentType"]]
        size = struct.calcsize(fmt)
        start = gltf["bufferViews"][accessor["bufferView"]].get("byteOffset", 0) + accessor.get("byteOffset", 0)
        for t in range(accessor["count"] // 3):
            at = start + 3 * t * size
            a, b, c = struct.unpack_from("<" + fmt * 3, out, at)
            struct.pack_into("<" + fmt * 3, out, at, a, c, b)
    return bytes(out)


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
        expect("fixed-gear Timber fails the stowed-gear rule", run(BASE, "generic", "--gear-stowed") == 1)
        expect("stowed Avanti passes the stowed-gear rule", run(STOWED, "generic", "--gear-stowed") == 0)
        stowed, stowed_binary = preflight_glb.read_glb(STOWED)
        pivot = stowed["nodes"][first(stowed, lambda n: n.get("name") == "MainGear_L_Pivot")]
        pivot["translation"][1] -= 0.1  # child of the identity root: 0.1 m straight down
        write_glb(Path(directory) / "gear_down.glb", stowed, stowed_binary)
        expect("preflight rejects: a main gear 0.1 m below its stowed pose", run(Path(directory) / "gear_down.glb", "generic", "--gear-stowed") == 1)
        frozen = preflight_glb.inspect(CORSAIR, "f4u-g1")
        expect("frozen g1.13 Corsair fails only the inside-out fuselage",
               len(frozen["failures"]) == 1 and frozen["failures"][0].startswith("fuselage_core is inside out"))
        expect("shipped g2.1 Corsair passes the f4u-g2 profile", run(SHIPPED, "f4u-g2") == 0)
        corsair, corsair_binary = preflight_glb.read_glb(CORSAIR)
        fixed_binary = reverse_winding(corsair, corsair_binary, "fuselage_core")
        fixed = Path(directory) / "fuselage_reversed.glb"
        write_glb(fixed, corsair, fixed_binary)
        expect("the same Corsair with the fuselage reversed passes f4u-g1", run(fixed, "f4u-g1") == 0)
        expect("and passes the f4u-g2 budgets", run(fixed, "f4u-g2") == 0)
        write_glb(fixed, corsair, reverse_winding(corsair, fixed_binary, "wing_left_fixed"))
        expect("preflight rejects: an inside-out outer wing panel", run(fixed, "f4u-g1") == 1)
        bad = Path(directory) / "broken.glb"
        bad.write_bytes(b"not a glb")
        expect("unreadable input exits 2", run(bad) == 2)
    print(f"F4U-04 preflight mutations: {checks} checks, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
