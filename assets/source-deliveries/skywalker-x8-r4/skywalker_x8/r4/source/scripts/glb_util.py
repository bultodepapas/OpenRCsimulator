"""Lectura y escritura minima de GLB (glTF 2.0 binario) sin dependencias, para las comprobaciones
de paridad entre skins y las pruebas de rechazo (r4).

  read_glb(path) -> (gltf_json, bin_bytes)
  write_glb(path, gltf_json, bin_bytes)
  accessor(gltf, bin, index) -> numpy array (count, n) en float64 (o enteros para indices)
  mesh_corners(gltf, bin, mesh_index) -> dict con posiciones, normales, uv0 y tangentes por esquina
  canonical(corners) -> arrays ordenados por triangulo (independiente del orden y de la division en
                        primitivas; conserva el sentido de giro de cada triangulo)
"""
import json, struct
import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32,
      5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    raw = open(path, "rb").read()
    magic, ver, length = struct.unpack("<III", raw[:12])
    if magic != 0x46546C67 or ver != 2:
        raise ValueError("no es GLB 2.0")
    off, js, binb = 12, None, b""
    while off < length:
        clen, ctype = struct.unpack("<II", raw[off:off + 8])
        data = raw[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(data)
        elif ctype == 0x004E4942:
            binb = data
        off += 8 + clen
    return js, binb


def write_glb(path, js, binb):
    jb = json.dumps(js, separators=(",", ":")).encode()
    jb += b" " * ((4 - len(jb) % 4) % 4)
    bb = bytes(binb) + b"\0" * ((4 - len(binb) % 4) % 4)
    total = 12 + 8 + len(jb) + (8 + len(bb) if bb else 0)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        if bb:
            f.write(struct.pack("<II", len(bb), 0x004E4942) + bb)


def accessor(js, binb, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    dt = np.dtype(CT[a["componentType"]])
    nc = NC[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0) or dt.itemsize * nc
    cnt = a["count"]
    buf = np.frombuffer(binb, np.uint8, count=stride * (cnt - 1) + dt.itemsize * nc, offset=start)
    rows = np.lib.stride_tricks.as_strided(buf, shape=(cnt, dt.itemsize * nc), strides=(stride, 1))
    out = np.ascontiguousarray(rows).view(dt).reshape(cnt, nc)
    if a.get("normalized") and dt != np.float32:
        out = out.astype(np.float64) / np.iinfo(dt).max
    return out


def accessor_location(js, i):
    """(desplazamiento en el BIN, paso, componente) del primer valor de un accesor."""
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    dt = np.dtype(CT[a["componentType"]])
    nc = NC[a["type"]]
    return bv.get("byteOffset", 0) + a.get("byteOffset", 0), (bv.get("byteStride", 0) or dt.itemsize * nc), dt


def mesh_corners(js, binb, mi):
    """Atributos por esquina de triangulo de todas las primitivas de la malla mi."""
    out = {"POSITION": [], "NORMAL": [], "TEXCOORD_0": [], "TANGENT": []}
    for p in js["meshes"][mi]["primitives"]:
        if p.get("mode", 4) != 4:
            raise ValueError("solo triangulos")
        idx = accessor(js, binb, p["indices"])[:, 0].astype(np.int64)
        for k in out:
            if k in p["attributes"]:
                out[k].append(accessor(js, binb, p["attributes"][k])[idx].astype(np.float64))
    return {k: (np.concatenate(v) if v else None) for k, v in out.items()}


def canonical(c):
    """Ordena triangulos de forma canonica: cada triangulo empieza por su esquina menor (rotacion,
    sin cambiar el giro) y la lista de triangulos se ordena lexicograficamente por posiciones."""
    P = c["POSITION"].reshape(-1, 3, 3)
    key = np.round(P, 7)
    first = np.empty(len(P), np.int64)
    for t_ in range(len(P)):                                            # ntri es pequeno (40 k)
        k = key[t_]
        first[t_] = min(range(3), key=lambda j: (k[j, 0], k[j, 1], k[j, 2]))
    rot = (first[:, None] + np.arange(3)[None, :]) % 3
    res = {}
    for name, v in c.items():
        if v is None:
            res[name] = None
            continue
        w = v.reshape(len(P), 3, -1)
        res[name] = np.take_along_axis(w, rot[:, :, None], axis=1)
    kp = np.round(res["POSITION"].reshape(len(P), 9), 7)
    tri_order = np.lexsort(kp.T[::-1])
    return {k: (v[tri_order] if v is not None else None) for k, v in res.items()}
