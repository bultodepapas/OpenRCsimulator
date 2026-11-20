#!/usr/bin/env python3
"""Read-only research decoder for Phoenix RC stock `.geo` geometry and `.bmp` textures.

Profile ``openrc-phoenix-geo-observed-v1`` was derived on 2026-11-20 from the stock
PhoenixRC 5.5.k installation (220 of 221 aircraft GEO files consume exactly). It is a
research probe, not the runtime importer: see docs/research/aircraft-creator/phoenix-stock-format-2026-11-20.md.

Usage:
  inspect_geo.py MODEL.geo [--texture MODEL.bmp] [--glb OUT.glb] [--scale S] [--flip-v]
  inspect_geo.py --corpus ROOT [--report OUT.json]

The tool never executes model content, never follows stored paths and never writes
into the source tree. A GLB is written only to an explicitly named new file.
"""
import argparse, json, math, os, struct, sys, zlib

PROFILE = "openrc-phoenix-geo-observed-v1"
MAX_INPUT = 64 << 20
MAX_MATERIALS = 64
MAX_NODES = 512
MAX_SUBS = 256
MAX_TRIANGLES = 200_000
MATERIAL_BYTES = 716
VERTEX_BYTES = 52
SUB_BYTES = 74
NAME_FIELD = 28
NO_MATERIAL = 0xFFFFFFFF


class GeoError(ValueError):
    pass


class Cursor:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def take(self, n):
        if n < 0 or self.pos + n > len(self.data):
            raise GeoError("truncated at %d (need %d)" % (self.pos, n))
        v = self.data[self.pos:self.pos + n]
        self.pos += n
        return v

    def u8(self):
        return self.take(1)[0]

    def u16(self):
        return struct.unpack("<H", self.take(2))[0]

    def u32(self):
        return struct.unpack("<I", self.take(4))[0]

    def floats(self, n, check=True):
        v = struct.unpack("<%df" % n, self.take(4 * n))
        if check and not all(math.isfinite(x) for x in v):
            raise GeoError("non-finite float before %d" % self.pos)
        return list(v)


def c_name(field, limit):
    """Phoenix writes 28-byte c_str() fields; names >= 28 chars overflow into the next field."""
    z = field.find(0, 0, limit)
    if z < 0:
        raise GeoError("unterminated name")
    raw = field[:z]
    return raw.decode("latin-1"), raw.hex(), z >= NAME_FIELD


def role_of(name):
    low = name.lower()
    if low.startswith("__col"):
        return "collision"
    if low.startswith("__"):
        return "helper"
    return "visual"


def parse(data):
    if len(data) > MAX_INPUT:
        raise GeoError("input limit")
    c = Cursor(data)
    version, node_count, h2, triangles, flag = c.u32(), c.u32(), c.u32(), c.u32(), c.u8()
    if version != 1:
        raise GeoError("unsupported version %d" % version)
    if not 0 < node_count <= MAX_NODES or not 0 < triangles <= MAX_TRIANGLES:
        raise GeoError("header counts out of profile")
    bbox = c.floats(6)
    mcount = c.u32()
    if mcount > MAX_MATERIALS:
        raise GeoError("material count")
    materials = []
    for i in range(mcount):
        rec = c.take(MATERIAL_BYTES)
        name, name_hex, overflow = c_name(rec, 56)
        has_tex, = struct.unpack_from("<I", rec, 128)
        if has_tex not in (0, 1):
            raise GeoError("material %d texture flag %d" % (i, has_tex))
        tex = c_name(rec[132:], 56)[0] if has_tex else None
        diffuse = list(struct.unpack_from("<3f", rec, 680))
        specular = list(struct.unpack_from("<3f", rec, 692))
        extra = list(struct.unpack_from("<3f", rec, 704))
        materials.append({"name": name, "name_hex": name_hex, "name_overflow": overflow, "texture": tex,
                          "diffuse": diffuse, "specular": specular, "unresolved_704": extra})
    vcount = c.u32()
    if vcount != triangles * 3:
        raise GeoError("vertex count %d != 3 * triangles %d" % (vcount, triangles))
    vstart = c.pos
    vbytes = c.take(vcount * VERTEX_BYTES)
    for i in range(0, vcount):
        o = i * VERTEX_BYTES
        if not all(math.isfinite(x) for x in struct.unpack_from("<8f", vbytes, o)):
            raise GeoError("non-finite vertex %d" % i)
    ncount = c.u32()
    if ncount != node_count:
        raise GeoError("node count %d != header %d" % (ncount, node_count))
    nodes, cursor_end = [], 0
    for i in range(ncount):
        start = c.pos
        head = c.take(124)
        name, name_hex, overflow = c_name(head, 56)
        unresolved = c.floats(2, check=False)  # writer garbage observed here
        nbbox = c.floats(6)
        matrix = c.floats(16)
        sub_count = c.u32()
        if sub_count > MAX_SUBS:
            raise GeoError("node %d sub count" % i)
        subs = []
        for j in range(sub_count):
            sb = c.floats(6, check=False)
            mat = c.u32()
            u1, u2, u3 = c.u32(), c.u32(), c.u16()
            c.u32()  # writer heap pointer: never interpreted
            sb2 = c.floats(6, check=False)
            first, end = c.u32(), c.u32()
            if first != cursor_end or end < first or end > vcount or (end - first) % 3:
                raise GeoError("node %d sub %d range %d..%d" % (i, j, first, end))
            if mat != NO_MATERIAL and mat >= mcount:
                raise GeoError("node %d sub %d material %d" % (i, j, mat))
            cursor_end = end
            subs.append({"material": None if mat == NO_MATERIAL else mat, "first": first, "end": end,
                         "bbox": sb, "unresolved": [u1, u2, u3]})
        tail = c.u32()
        nodes.append({"index": i, "name": name, "name_hex": name_hex, "name_overflow": overflow,
                      "role": role_of(name), "bbox": nbbox, "matrix": matrix, "subs": subs,
                      "unresolved_124": unresolved, "unresolved_tail": tail, "offset": start})
    if cursor_end != vcount:
        raise GeoError("ranges end at %d of %d vertices" % (cursor_end, vcount))
    if c.pos != len(data):
        raise GeoError("%d unconsumed bytes" % (len(data) - c.pos))
    return {"profile": PROFILE, "header": {"version": version, "nodes": node_count, "unresolved_h2": h2,
            "triangles": triangles, "flag": flag, "bbox": bbox}, "materials": materials,
            "vertex_count": vcount, "vertex_offset": vstart, "nodes": nodes}


def vertex(data, off, i):
    return struct.unpack_from("<8f", data, off + i * VERTEX_BYTES)


def winding_agreement(data, geo):
    agree = total = 0
    off = geo["vertex_offset"]
    for t in range(geo["vertex_count"] // 3):
        a, b, c = (vertex(data, off, 3 * t + k) for k in range(3))
        e1 = [b[k] - a[k] for k in range(3)]
        e2 = [c[k] - a[k] for k in range(3)]
        cr = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]]
        n = [a[3 + k] + b[3 + k] + c[3 + k] for k in range(3)]
        dot = sum(cr[k] * n[k] for k in range(3))
        if dot != 0:
            total += 1
            agree += dot > 0
    return agree, total


# ---------------------------------------------------------------- textures

TEXTURE_MAGIC = bytes([0xFF, 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02])
# Bytes the pixel data starts before (size - width*height*channels): BGR 1, BGRA 2.
TEXTURE_LEAD = {3: 1, 4: 2}


def texture_profile(data):
    """Stock `.bmp`: 8-byte magic, an overwritten BMP header, then BGR(A) rows bottom-up.

    The colour phase was fixed on known liveries (red Fokker DR-1, yellow J-3 Cub): 3-channel pixel
    data begins one byte before (size - width*height*channels); 4-channel (BGRA) data begins two bytes
    before (glass, rotor disc and thumbnails). `app/workshop/creator/phoenix/texture.gd` ports this rule.

    Dimensions are not recoverable from the overwritten header; they are inferred from the size
    (power-of-two sides) and, for non-square candidates, by adjacent-row similarity.
    """
    if data[:2] == b"BM":
        return {"kind": "standard BMP"}
    if data[:8] != TEXTURE_MAGIC:
        raise GeoError("unrecognized texture magic")
    cands = []
    for ch in (3, 4):
        for hdr in (54, 56):
            n = len(data) - 8 - hdr
            if n <= 0 or n % ch:
                continue
            px = n // ch
            w = 4
            while w <= 4096:
                if px % w == 0:
                    h = px // w
                    if 4 <= h <= 4096 and h & (h - 1) == 0:
                        cands.append((w, h, ch, len(data) - n - TEXTURE_LEAD[ch]))
                w *= 2
    if not cands:
        raise GeoError("unrecognized texture layout (%d bytes)" % len(data))

    def roughness(c):
        w, h, ch, off = c
        stride = w * ch
        rows = min(h - 1, 64)
        step = max(1, (h - 1) // rows)
        tot = 0
        for y in range(0, h - 1, step):
            a = data[off + y * stride: off + y * stride + stride: 7]
            b = data[off + (y + 1) * stride: off + (y + 1) * stride + stride: 7]
            tot += sum(abs(x - z) for x, z in zip(a, b))
        return tot
    square = [c for c in cands if c[0] == c[1]]
    near = [c for c in cands if max(c[0], c[1]) <= 2 * min(c[0], c[1])]
    pool = square or near or cands
    best = min(pool, key=roughness) if len(pool) > 1 else pool[0]
    w, h, ch, off = best
    return {"kind": "phoenix raw", "width": w, "height": h, "channels": ch, "pixel_offset": off,
            "candidates": len(cands)}


def png_from_texture(data):
    p = texture_profile(data)
    if p["kind"] != "phoenix raw":
        raise GeoError("only the observed raw profile is converted")
    w, h, ch, off = p["width"], p["height"], p["channels"], p["pixel_offset"]
    stride = w * ch
    rows = []
    for y in range(h):  # stored bottom-up, BGR(A)
        r = bytearray(data[off + (h - 1 - y) * stride: off + (h - y) * stride])
        r[0::ch], r[2::ch] = r[2::ch], r[0::ch]
        rows.append(bytes(r))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + r for r in rows)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6 if ch == 4 else 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""), p


# ---------------------------------------------------------------- GLB export

def export_glb(data, geo, png=None, scale=1.0, flip_v=False, include=("visual",)):
    """Phoenix GEO space already matches glTF (+X left, +Y up, +Z forward, CCW)."""
    off = geo["vertex_offset"]
    bin_ = bytearray()
    gltf = {"asset": {"version": "2.0", "generator": PROFILE,
                      "extras": {"openrc_phoenix_research": {"profile": PROFILE, "scale": scale,
                                                             "physics_imported": False}}},
            "scene": 0, "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "accessors": [],
            "bufferViews": [], "materials": [], "buffers": []}

    def view(blob, target):
        while len(bin_) % 4:
            bin_.append(0)
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(bin_), "byteLength": len(blob), "target": target})
        bin_.extend(blob)
        return len(gltf["bufferViews"]) - 1

    def accessor(blob, ctype, count, typ, target, lo=None, hi=None):
        a = {"bufferView": view(blob, target), "componentType": ctype, "count": count, "type": typ}
        if lo is not None:
            a["min"], a["max"] = lo, hi
        gltf["accessors"].append(a)
        return len(gltf["accessors"]) - 1

    tex_index = None
    if png is not None:
        while len(bin_) % 4:
            bin_.append(0)
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(bin_), "byteLength": len(png)})
        bin_.extend(png)
        gltf["images"] = [{"bufferView": len(gltf["bufferViews"]) - 1, "mimeType": "image/png"}]
        gltf["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
        gltf["textures"] = [{"sampler": 0, "source": 0}]
        tex_index = 0
    for m in geo["materials"]:
        pbr = {"baseColorFactor": [1, 1, 1, 1] if m["texture"] and tex_index is not None else m["diffuse"] + [1],
               "metallicFactor": 0.0, "roughnessFactor": 0.6}
        if m["texture"] and tex_index is not None:
            pbr["baseColorTexture"] = {"index": tex_index}
        gltf["materials"].append({"name": m["name"], "pbrMetallicRoughness": pbr, "doubleSided": False})
    for n in geo["nodes"]:
        if n["role"] not in include or not n["subs"]:
            continue
        prims = []
        for s in n["subs"]:
            cnt = s["end"] - s["first"]
            if cnt == 0:
                continue
            pos, nor, uv = bytearray(), bytearray(), bytearray()
            lo, hi = [math.inf] * 3, [-math.inf] * 3
            for i in range(s["first"], s["end"]):
                v = vertex(data, off, i)
                p = [v[0] * scale, v[1] * scale, v[2] * scale]
                lo = [min(lo[k], p[k]) for k in range(3)]
                hi = [max(hi[k], p[k]) for k in range(3)]
                ln = math.sqrt(v[3] ** 2 + v[4] ** 2 + v[5] ** 2) or 1.0
                pos += struct.pack("<3f", *p)
                nor += struct.pack("<3f", v[3] / ln, v[4] / ln, v[5] / ln)
                uv += struct.pack("<2f", v[6], (1.0 - v[7]) if flip_v else v[7])
            attrs = {"POSITION": accessor(bytes(pos), 5126, cnt, "VEC3", 34962, lo, hi),
                     "NORMAL": accessor(bytes(nor), 5126, cnt, "VEC3", 34962),
                     "TEXCOORD_0": accessor(bytes(uv), 5126, cnt, "VEC2", 34962)}
            idx = struct.pack("<%dI" % cnt, *range(cnt))
            prim = {"attributes": attrs, "indices": accessor(idx, 5125, cnt, "SCALAR", 34963), "mode": 4}
            if s["material"] is not None:
                prim["material"] = s["material"]
            prims.append(prim)
        if not prims:
            continue
        gltf["meshes"].append({"name": n["name"], "primitives": prims})
        gltf["nodes"].append({"name": n["name"], "mesh": len(gltf["meshes"]) - 1,
                              "extras": {"openrc_phoenix_node": {"index": n["index"], "role": n["role"]}}})
        gltf["scenes"][0]["nodes"].append(len(gltf["nodes"]) - 1)
    while len(bin_) % 4:
        bin_.append(0)
    gltf["buffers"] = [{"byteLength": len(bin_)}]
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(bin_)
    return (struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js
            + struct.pack("<II", len(bin_), 0x004E4942) + bytes(bin_))


# ---------------------------------------------------------------- reports

def summary(data, geo):
    roles = {}
    for n in geo["nodes"]:
        roles[n["role"]] = roles.get(n["role"], 0) + 1
    agree, total = winding_agreement(data, geo)
    return {"profile": PROFILE, "triangles": geo["header"]["triangles"], "nodes": len(geo["nodes"]),
            "roles": roles, "materials": [(m["name"], m["texture"]) for m in geo["materials"]],
            "bbox": geo["header"]["bbox"], "winding_normal_agreement": [agree, total],
            "name_overflows": sum(n["name_overflow"] for n in geo["nodes"]),
            "visual_nodes": [n["name"] for n in geo["nodes"] if n["role"] == "visual"]}


def corpus(root):
    results = {"profile": PROFILE, "accepted": [], "rejected": []}
    for dp, dn, fn in sorted(os.walk(root)):
        dn.sort()
        for f in sorted(fn):
            if not f.lower().endswith(".geo"):
                continue
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, root).replace(os.sep, "/")
            data = open(p, "rb").read()
            try:
                geo = parse(data)
                agree, total = winding_agreement(data, geo)
                results["accepted"].append({"path": rel, "bytes": len(data), "triangles": geo["header"]["triangles"],
                                            "nodes": len(geo["nodes"]), "materials": len(geo["materials"]),
                                            "winding_agree": agree, "winding_total": total})
            except GeoError as e:
                results["rejected"].append({"path": rel, "bytes": len(data), "reason": str(e)})
    return results


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("geo", nargs="?")
    ap.add_argument("--texture")
    ap.add_argument("--glb")
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--flip-v", action="store_true")
    ap.add_argument("--corpus")
    ap.add_argument("--report")
    a = ap.parse_args(argv)
    if a.corpus:
        out = corpus(a.corpus)
        text = json.dumps(out, indent=1)
        if a.report:
            with open(a.report, "x", encoding="utf-8") as fh:
                fh.write(text + "\n")
        print("accepted %d rejected %d" % (len(out["accepted"]), len(out["rejected"])))
        for r in out["rejected"]:
            print("  rejected", r["path"], r["reason"])
        return 0
    data = open(a.geo, "rb").read()
    try:
        geo = parse(data)
    except GeoError as e:
        print("rejected:", e, file=sys.stderr)
        return 1
    print(json.dumps(summary(data, geo), indent=1))
    if a.glb:
        png = None
        if a.texture:
            png, prof = png_from_texture(open(a.texture, "rb").read())
            print("texture", prof)
        with open(a.glb, "xb") as fh:
            fh.write(export_glb(data, geo, png, a.scale, a.flip_v))
    return 0


if __name__ == "__main__":
    sys.exit(main())
