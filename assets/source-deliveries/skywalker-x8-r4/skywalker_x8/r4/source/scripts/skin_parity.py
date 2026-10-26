"""Paridad del fuselaje entre skins (r4): misma geometria, aunque cambien materiales y texturas.

  python skin_parity.py export/aircraft.glb export/bolido.glb [--json salida.json]

Compara en terminos semanticos (no bytes): nombres de nodos, jerarquia, transformaciones de
reposo, extras (openrc_section) y, por cada malla, el conjunto de triangulos con posicion,
normal, UV0 y tangente por esquina, en orden canonico (independiente del orden de los vertices
y de la division en primitivas). Tambien revisa que cada textura del atlas use el canal UV 0.
Sale con 1 si algo difiere mas que la tolerancia.
"""
import sys, os, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import glb_util as G

TOL = dict(POSITION=1e-6, NORMAL=1e-5, TEXCOORD_0=1e-6, TANGENT=1e-5, TRS=1e-7)


def node_table(js):
    parent = {}
    for i, n in enumerate(js["nodes"]):
        for c in n.get("children", []):
            parent[c] = i
    out = {}
    for i, n in enumerate(js["nodes"]):
        out[n["name"]] = dict(parent=js["nodes"][parent[i]]["name"] if i in parent else None,
                              t=n.get("translation", [0, 0, 0]), r=n.get("rotation", [0, 0, 0, 1]),
                              s=n.get("scale", [1, 1, 1]), m=n.get("matrix"),
                              extras=n.get("extras", {}), mesh=n.get("mesh"))
    return out


def texture_bindings(js):
    res = {}
    for m in js.get("materials", []):
        b = {}
        pbr = m.get("pbrMetallicRoughness", {})
        for slot, ti in (("baseColorTexture", pbr.get("baseColorTexture")),
                         ("metallicRoughnessTexture", pbr.get("metallicRoughnessTexture")),
                         ("normalTexture", m.get("normalTexture")),
                         ("occlusionTexture", m.get("occlusionTexture")),
                         ("emissiveTexture", m.get("emissiveTexture"))):
            if ti is not None:
                src = js["textures"][ti["index"]]["source"]
                b[slot] = dict(image=js["images"][src].get("name"), texCoord=ti.get("texCoord", 0),
                               mime=js["images"][src].get("mimeType"))
        res[m["name"]] = b
    return res


def compare(ref_path, path):
    jr, br = G.read_glb(ref_path)
    jo, bo = G.read_glb(path)
    errs, per_node = [], {}
    tr, to = node_table(jr), node_table(jo)
    if set(tr) != set(to):
        errs.append(f"nodos distintos: faltan {sorted(set(tr) - set(to))}, sobran {sorted(set(to) - set(tr))}")
    max_trs = 0.0
    for name in sorted(set(tr) & set(to)):
        a, b = tr[name], to[name]
        if a["parent"] != b["parent"]:
            errs.append(f"{name}: padre {b['parent']} != {a['parent']}")
        if a["extras"] != b["extras"]:
            errs.append(f"{name}: extras {b['extras']} != {a['extras']}")
        if (a["mesh"] is None) != (b["mesh"] is None):
            errs.append(f"{name}: malla presente en uno solo")
        for k in ("t", "r", "s"):
            d = float(np.max(np.abs(np.subtract(a[k], b[k]))))
            max_trs = max(max_trs, d)
        if a["m"] != b["m"]:
            errs.append(f"{name}: matriz distinta")
        if a["mesh"] is None or b["mesh"] is None:
            continue
        ca = G.canonical(G.mesh_corners(jr, br, a["mesh"]))
        cb = G.canonical(G.mesh_corners(jo, bo, b["mesh"]))
        st = dict(triangles_ref=len(ca["POSITION"]), triangles=len(cb["POSITION"]))
        if st["triangles_ref"] != st["triangles"]:
            errs.append(f"{name}: {st['triangles']} triangulos != {st['triangles_ref']}")
            per_node[name] = st
            continue
        for k in ("POSITION", "NORMAL", "TEXCOORD_0", "TANGENT"):
            if (ca[k] is None) != (cb[k] is None):
                errs.append(f"{name}: atributo {k} presente en uno solo")
                continue
            if ca[k] is None:
                st[k] = None
                continue
            d = float(np.max(np.abs(ca[k] - cb[k])))
            st[k + "_max_abs_diff"] = d
            if d > TOL[k]:
                errs.append(f"{name}: {k} difiere hasta {d:.3g}")
        per_node[name] = st
    if max_trs > TOL["TRS"]:
        errs.append(f"transformaciones de reposo difieren hasta {max_trs:.3g}")
    bind = texture_bindings(jo)
    for mat, slots in bind.items():
        for slot, v in slots.items():
            if v["texCoord"] != 0:
                errs.append(f"{mat}.{slot}: texCoord {v['texCoord']} (se espera 0)")
    return dict(reference=os.path.basename(ref_path), compared=os.path.basename(path),
                tolerances=TOL, nodes=len(to), mesh_nodes=len(per_node), max_rest_trs_diff=max_trs,
                per_mesh=per_node, texture_bindings=bind, errors=errs, passed=not errs)


if __name__ == "__main__":
    a = sys.argv[1:]
    out = a[a.index("--json") + 1] if "--json" in a else None
    r = compare(a[0], a[1])
    if out:
        json.dump(r, open(out, "w"), indent=1)
    print("PARIDAD", r["compared"], "vs", r["reference"], "OK" if r["passed"] else "FALLA", r["errors"][:5])
    sys.exit(0 if r["passed"] else 1)
