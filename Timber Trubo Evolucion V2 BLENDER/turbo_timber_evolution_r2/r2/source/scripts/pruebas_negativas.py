"""
Negative tests for the r2 verifier: deliberately broken disposable copies of export/aircraft.glb must be rejected.

  python3 pruebas_negativas.py <aircraft.glb> <work dir> [--r1 <r1 aircraft.glb>] [--blender-verifier <cmd prefix>]

Each case writes a modified copy into <work dir> (never touching the original), runs valida_glb.py on it as a
separate process and requires exit code 1 with the expected check failing. With --blender-verifier the full
Blender verifier (verifica_r2.py --glb <copy> --structure-only) is also run on every copy and must exit nonzero.
Exit 0 only if every broken copy is rejected AND the unmodified file still passes.
"""
import json, os, struct, subprocess, sys, shutil, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))


def leer(ruta):
    raw = open(ruta, "rb").read(); jl = struct.unpack_from("<I", raw, 12)[0]
    return json.loads(raw[20:20 + jl]), raw[20 + jl:]


def escribir(ruta, gl, resto):
    js = json.dumps(gl, separators=(",", ":")).encode(); js += b" " * ((4 - len(js) % 4) % 4)
    cuerpo = struct.pack("<II", len(js), 0x4E4F534A) + js + resto
    open(ruta, "wb").write(struct.pack("<III", 0x46546C67, 2, 12 + len(cuerpo)) + cuerpo)


def idx(gl, nombre): return next(i for i, n in enumerate(gl["nodes"]) if n.get("name") == nombre)


def quitar_nodo(gl, nombre):
    """delete a pivot node; its children are re-attached to the scene root node (as if the hinge was forgotten)"""
    i = idx(gl, nombre); hijos = gl["nodes"][i].get("children", [])
    for n in gl["nodes"]:
        if i in n.get("children", []): n["children"] = [c for c in n["children"] if c != i] + hijos
    del gl["nodes"][i]
    remap = lambda j: j - 1 if j > i else j
    for n in gl["nodes"]:
        if "children" in n: n["children"] = [remap(c) for c in n["children"]]
    for s in gl["scenes"]: s["nodes"] = [remap(c) for c in s["nodes"]]
    for a in gl.get("animations", []):
        for c in a["channels"]: c["target"]["node"] = remap(c["target"]["node"])


def caso_sin_bisagra(gl): quitar_nodo(gl, "elevator_hinge")
def caso_sin_seccion(gl): gl["nodes"][idx(gl, "wing_left_fixed")].setdefault("extras", {}).pop("openrc_section", None)
def caso_seccion_invalida(gl): gl["nodes"][idx(gl, "rudder_hinge")]["extras"]["openrc_section"] = "wingleft"
def caso_seccion_no_texto(gl): gl["nodes"][idx(gl, "cowl")]["extras"]["openrc_section"] = 7
def caso_rotor_bajo_motor(gl): gl["nodes"][idx(gl, "thrust_frame")].setdefault("extras", {})["openrc_section"] = "engine"
def caso_escala(gl): gl["nodes"][idx(gl, "aileron_left_hinge")]["scale"] = [1.0, 1.0, -1.0]
def caso_sufijo(gl): gl["nodes"][idx(gl, "flap_right")]["name"] = "flap_right.001"

CASOS = [("missing_hinge_elevator", caso_sin_bisagra, "hierarchy_matches_spec_tree"),
         ("missing_section_wing_left_fixed", caso_sin_seccion, "openrc_section_present"),
         ("invalid_section_rudder_hinge", caso_seccion_invalida, "openrc_section_valid"),
         ("non_string_section_cowl", caso_seccion_no_texto, "openrc_section_valid"),
         ("rotor_under_engine_tag", caso_rotor_bajo_motor, "rotor_not_under_engine_tag"),
         ("mirrored_scale_aileron_left_hinge", caso_escala, "node_scales_unit"),
         ("blender_suffix_flap_right", caso_sufijo, "names_unique_ascii_no_suffix")]


def correr(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True); return p.returncode, p.stdout[-3000:] + p.stderr[-2000:]


if __name__ == "__main__":
    a = sys.argv[1:]; glb, work = a[0], a[1]
    r1 = ["--r1", a[a.index("--r1") + 1]] if "--r1" in a else []
    bv = a[a.index("--blender-verifier") + 1].split() if "--blender-verifier" in a else None
    os.makedirs(work, exist_ok=True)
    h0 = hashlib.sha256(open(glb, "rb").read()).hexdigest()
    out = {"original": glb, "original_sha256": h0, "cases": []}
    rc, txt = correr([sys.executable, os.path.join(HERE, "valida_glb.py"), glb, *r1])
    out["original_passes"] = rc == 0
    for nombre, f, check in CASOS:
        gl, resto = leer(glb); f(gl)
        ruta = os.path.join(work, f"broken_{nombre}.glb"); escribir(ruta, gl, resto)
        rep = os.path.join(work, f"broken_{nombre}.json")
        rc, txt = correr([sys.executable, os.path.join(HERE, "valida_glb.py"), ruta, *r1, "--json", rep])
        fallos = json.load(open(rep))["failed"] if os.path.exists(rep) else []
        c = {"case": nombre, "validator_exit": rc, "expected_check": check, "failed_checks": fallos,
             "rejected": rc == 1 and check in fallos}
        if bv:
            rc2, txt2 = correr(bv + ["--", "--glb", ruta, "--structure-only", "--out", os.path.join(work, f"broken_{nombre}_blender.json")])
            c["blender_verifier_exit"] = rc2; c["rejected"] = c["rejected"] and rc2 != 0
        out["cases"].append(c)
        print(("REJECTED " if c["rejected"] else "NOT REJECTED ") + nombre, rc, fallos)
    out["original_untouched"] = hashlib.sha256(open(glb, "rb").read()).hexdigest() == h0
    out["pass"] = out["original_passes"] and out["original_untouched"] and all(c["rejected"] for c in out["cases"])
    json.dump(out, open(os.path.join(work, "negative_tests.json"), "w"), indent=1)
    print("NEGATIVE TESTS", "PASS" if out["pass"] else "FAIL")
    sys.exit(0 if out["pass"] else 1)
