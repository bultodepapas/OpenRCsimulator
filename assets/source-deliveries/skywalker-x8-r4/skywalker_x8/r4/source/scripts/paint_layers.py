"""Capas editables de una librea (r4): pintura base, rotulos/marcas e insignias.

  python paint_layers.py split   textures/<skin>/source <skin>   (despues de pintar dos veces)
  python paint_layers.py compose textures/<skin>/source <skin> [--write]

split: el pintor se corre una vez normal (x8_<skin>_base_color.png y las coberturas
masks/marking_alpha.png e insignia_alpha.png de 16 bits) y otra con --no-markings
(layers/x8_<skin>_paint_base.png). Como las capas posteriores del pintor (desgaste, polvo,
luces) son mezclas lineales que no dependen del color de debajo, el color final cumple
    final = base * (1 - a) + marca * a
y de ahi sale el color de cada marca: marca = (final - base * (1 - a)) / a. Se guardan como PNG
RGBA de 8 bits en layers/ (x8_<skin>_markings.png, x8_<skin>_insignia.png).

compose: base + markings + insignia (en ese orden, "over") -> color base. Sin --write solo
compara con x8_<skin>_base_color.png y escribe layers/compose_report.json; con --write
reemplaza x8_<skin>_base_color.png (flujo de retoque a mano: editar las capas, componer,
livery_bake_textures.py, exportar, verificar).
"""
import sys, os, json
import numpy as np
from PIL import Image

mode, SRC, SKIN = sys.argv[1], os.path.abspath(sys.argv[2]), sys.argv[3]
PRE = f"x8_{SKIN}_"
LAY = os.path.join(SRC, "layers")
os.makedirs(LAY, exist_ok=True)


def rgb(p):
    return np.asarray(Image.open(p).convert("RGB"), np.float64) / 255.0


def alpha16(p):
    return np.asarray(Image.open(p), np.float64) / 65535.0 if os.path.exists(p) else None


def save_rgba(path, col, a):
    out = np.zeros(col.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.round(np.clip(col, 0, 1) * 255)
    out[..., 3] = np.round(np.clip(a, 0, 1) * 255)
    Image.fromarray(out, "RGBA").save(path)


def load_rgba(path, shape):
    if not os.path.exists(path):
        return np.zeros(shape), np.zeros(shape[:2])
    x = np.asarray(Image.open(path).convert("RGBA"), np.float64) / 255.0
    return x[..., :3], x[..., 3]


if mode == "split":
    F = rgb(os.path.join(SRC, PRE + "base_color.png"))
    N = rgb(os.path.join(LAY, PRE + "paint_base.png"))
    am = alpha16(os.path.join(SRC, "masks", "marking_alpha.png"))
    ai = alpha16(os.path.join(SRC, "masks", "insignia_alpha.png"))
    am = np.zeros(F.shape[:2]) if am is None else am
    ai = np.zeros(F.shape[:2]) if ai is None else ai
    both = (am > 0) & (ai > 0)                       # solapes: todo a la capa de marcas
    am = np.where(both, 1 - (1 - am) * (1 - ai), am)
    ai = np.where(both, 0.0, ai)
    out = {}
    for name, a in (("markings", am), ("insignia", ai)):
        a8 = np.round(np.clip(a, 0, 1) * 255) / 255.0       # alfa tal como queda en 8 bits
        ok = a8 > 0
        col = np.zeros_like(F)
        col[ok] = np.clip((F[ok] - N[ok] * (1 - a8[ok, None])) / a8[ok, None], 0, 1)
        if ok.any():
            save_rgba(os.path.join(LAY, f"{PRE}{name}.png"), col, a8)
        elif os.path.exists(os.path.join(LAY, f"{PRE}{name}.png")):
            os.remove(os.path.join(LAY, f"{PRE}{name}.png"))
        out[name] = dict(texels=int(ok.sum()), file=f"layers/{PRE}{name}.png" if ok.any() else None)
    print("CAPAS", SKIN, out)
    mode = "compose"

if mode == "compose":
    N = rgb(os.path.join(LAY, PRE + "paint_base.png"))
    C = N.copy()
    used = []
    for name in ("markings", "insignia"):
        col, a = load_rgba(os.path.join(LAY, f"{PRE}{name}.png"), N.shape)
        if a.any():
            used.append(name)
        C = C * (1 - a[..., None]) + col * a[..., None]
    C8 = np.round(np.clip(C, 0, 1) * 255).astype(np.uint8)
    ref_p = os.path.join(SRC, PRE + "base_color.png")
    ref = np.asarray(Image.open(ref_p).convert("RGB"), np.int16)
    d = np.abs(C8.astype(np.int16) - ref)
    rep = dict(skin=SKIN, layers=["paint_base"] + used, compose_rule="base, then markings, then "
               "insignia, 'over' with straight alpha, 8-bit", max_abs_diff_8bit=int(d.max()),
               mean_abs_diff_8bit=round(float(d.mean()), 5),
               fraction_texels_diff_gt_2=round(float((d.max(axis=2) > 2).mean()), 7),
               threshold="max <= 3 levels of 255 (8-bit quantisation of layer colour and alpha)",
               passed=bool(d.max() <= 3))
    if "--write" in sys.argv:
        Image.fromarray(C8, "RGB").save(ref_p)
        rep["written"] = ref_p
    json.dump(rep, open(os.path.join(LAY, "compose_report.json"), "w"), indent=1)
    print("COMPOSE", SKIN, "max", rep["max_abs_diff_8bit"], "media", rep["mean_abs_diff_8bit"],
          "OK" if rep["passed"] else "FALLA")
    sys.exit(0 if rep["passed"] else 1)
