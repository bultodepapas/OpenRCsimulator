"""Acabado por skin y por pieza a partir de las texturas de juego (r4).

  python check_finish.py source/aircraft_game.blend textures --json checks/finish.json

Para cada skin y cada malla pintada muestrea, en el centro UV de cada cara del atlas, el color
base (luminancia), la rugosidad y el metal (ORM G, B), la oclusion (ORM R) y la inclinacion del
mapa de normales respecto a la normal de la superficie. Sirve para declarar las diferencias de
acabado intencionales entre skins y para detectar un mapa de normales perdido (inclinacion ~0)
o un cambio accidental de rugosidad. Falla si una skin tiene el mapa de normales plano, el
canal de oclusion distinto del compartido o texturas con tamano distinto de 2048.
"""
import sys, os, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
from PIL import Image
import bpy
import x8_game_spec as S

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
BLEND, TEXROOT = os.path.abspath(argv[0]), os.path.abspath(argv[1])
OUT = argv[argv.index("--json") + 1] if "--json" in argv else None
bpy.ops.wm.open_mainfile(filepath=BLEND)
ob = bpy.data.objects
UV = {}
for name in S.LIVERY_PARTS:
    me = ob[name].data
    names = [m.name for m in me.materials]
    uvd = me.uv_layers["UVMap"].data
    pts = []
    for p in me.polygons:
        if names[p.material_index] == S.LIVERY_MATERIAL:
            u = np.mean([uvd[li].uv[:] for li in p.loop_indices], axis=0)
            pts.append(u)
    UV[name] = np.array(pts)
occ_shared = np.asarray(Image.open(os.path.join(TEXROOT, "shared", "x8_airframe_occlusion.png")).convert("L"))


def sample(img, uv):
    h, w = img.shape[:2]
    x = np.clip((uv[:, 0] * w).astype(int), 0, w - 1)
    y = np.clip(((1 - uv[:, 1]) * h).astype(int), 0, h - 1)
    return img[y, x]


R, errs = {}, []
for skin in S.SKIN_ORDER:
    d = os.path.join(TEXROOT, skin)
    f = {k: os.path.join(d, n) for k, n in zip(("base", "orm", "normal", "emission"), S.livery_images(skin))}
    ims = {k: np.asarray(Image.open(p).convert("RGB"), np.float32) / 255.0 for k, p in f.items()}
    sizes = {k: Image.open(p).size for k, p in f.items()}
    if any(sz != (S.LIVERY_RES_RUNTIME, S.LIVERY_RES_RUNTIME) for sz in sizes.values()):
        errs.append(f"{skin}: tamanos {sizes}")
    orm_r = (ims["orm"][..., 0] * 255 + 0.5).astype(np.uint8)
    if not np.array_equal(orm_r, occ_shared):
        errs.append(f"{skin}: canal R del ORM distinto de la oclusion compartida")
    parts = {}
    for name, uv in UV.items():
        b = sample(ims["base"], uv)
        o = sample(ims["orm"], uv)
        nrm = sample(ims["normal"], uv) * 2 - 1
        e = sample(ims["emission"], uv)
        tilt = np.degrees(np.arccos(np.clip(nrm[:, 2] / np.maximum(np.linalg.norm(nrm, axis=1), 1e-6), -1, 1)))
        lum = b @ np.array([0.2126, 0.7152, 0.0722])
        parts[name] = dict(faces=int(len(uv)), base_luminance_mean=round(float(lum.mean()), 3),
                           roughness_mean=round(float(o[:, 1].mean()), 3),
                           roughness_std=round(float(o[:, 1].std()), 3),
                           metallic_mean=round(float(o[:, 2].mean()), 3),
                           occlusion_mean=round(float(o[:, 0].mean()), 3),
                           normal_tilt_mean_deg=round(float(tilt.mean()), 2),
                           normal_tilt_p95_deg=round(float(np.percentile(tilt, 95)), 2),
                           emissive_faces=int((e.max(axis=1) > 0.02).sum()))
    full_tilt = np.degrees(np.arccos(np.clip(ims["normal"][..., 2] * 2 - 1, -1, 1)))
    rep = dict(textures={k: os.path.relpath(p, os.path.dirname(TEXROOT)) for k, p in f.items()},
               sizes=sizes, normal_tilt_mean_deg_atlas=round(float(full_tilt.mean()), 2),
               occlusion_channel="identical to textures/shared/x8_airframe_occlusion.png"
               if np.array_equal(orm_r, occ_shared) else "DIFFERENT", per_part=parts)
    w_ = np.array([v["faces"] for v in parts.values()], float)
    t_ = np.array([v["normal_tilt_mean_deg"] for v in parts.values()])
    rep["normal_tilt_mean_deg_painted"] = round(float((w_ * t_).sum() / w_.sum()), 2)
    if rep["normal_tilt_mean_deg_painted"] < 0.3:                # mapa de normales perdido o plano
        errs.append(f"{skin}: mapa de normales casi plano en las caras pintadas")
    R[skin] = rep
out = dict(method="face-centre UV samples of the runtime (2048) textures, per painted mesh",
           skins=R, errors=errs, passed=not errs)
if OUT:
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    json.dump(out, open(OUT, "w"), indent=1)
for skin, r in R.items():
    print("ACABADO", skin, {k: (v["roughness_mean"], v["metallic_mean"], v["normal_tilt_mean_deg"]) for k, v in list(r["per_part"].items())[:4]})
print("FINISH", "OK" if out["passed"] else "FALLA", errs)
sys.exit(0 if out["passed"] else 1)
