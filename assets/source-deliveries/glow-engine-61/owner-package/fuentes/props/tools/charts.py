"""Verification sheet (PNG): pitch measured on the meshes, chord vs APC's PE0 table, front outline vs the UIUC
photo, weight vs the makers' figures.  python3 charts.py check_props.json out.png"""
import json
import math
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

sys.path.insert(0, "/home/claude/props")
import propgeom as G  # noqa: E402

chk = json.load(open(sys.argv[1]))["props"]
OUT = sys.argv[2]
SURF, INK, INK2, MUTED, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#8a8984", "#e4e3df"
S1, S2, S3 = "#2a78d6", "#eb6834", "#1baf7a"
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10.5, "axes.edgecolor": MUTED,
                     "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2, "axes.facecolor": SURF,
                     "figure.facecolor": SURF, "axes.titlesize": 12, "axes.titleweight": "bold",
                     "axes.titlecolor": INK, "axes.titlelocation": "left"})
fig, ax = plt.subplots(2, 2, figsize=(14, 9.6), dpi=130)
for a in ax.flat:
    a.grid(True, color=GRID, lw=0.8)
    a.set_axisbelow(True)
    for s in ("top", "right"):
        a.spines[s].set_visible(False)


def label_end(a, x, y, text, color):
    a.annotate(text, (x, y), xytext=(6, 0), textcoords="offset points", va="center", color=INK, fontsize=9.5,
               bbox=dict(boxstyle="round,pad=0.15", fc=SURF, ec=color, lw=1.0))


# 1. flat-bottom pitch along the blade
a = ax[0, 0]
for k, col in (("APC_11x8", S3), ("APC_11x7", S1), ("APC_12x6", S2)):
    secs = chk[k]["sections"]
    xs = [float(s) for s in secs]
    ys = [secs[s]["model"]["pitch_flat_in"] for s in secs]
    a.plot(xs, ys, color=col, lw=2, marker="o", ms=6, mec=SURF, mew=1.5)
    nom = chk[k]["label"].split("x")[-1]
    a.axhline(float(nom), color=MUTED, lw=0.8, ls=(0, (4, 3)))
    label_end(a, xs[-1], ys[-1], chk[k]["label"].replace("APC Sport ", "APC "), col)
a.set_xlim(0.2, 1.06)
a.set_ylim(4.5, 8.8)
a.set_xlabel("r/R")
a.set_ylabel("paso de cara plana (in)")
a.set_title("Paso medido en la malla (galga Prather, cara plana)")
a.text(0.21, 4.62, "Líneas a trazos: paso nominal. Cerca del buje el paso baja a propósito (transición APC).",
       color=INK2, fontsize=9)

# 2. chord: mesh vs PE0 (APC 11x7) and vs the UIUC table (MA G/F 11x7)
a = ax[0, 1]
d = G.read_pe0("11x7")
R = d["R"]
a.plot([r["r"] / R for r in d["rows"]], [r["c"] * G.IN for r in d["rows"]], color=S2, lw=2)
secs = chk["APC_11x7"]["sections"]
a.plot([float(s) for s in secs], [secs[s]["model"]["chord"] for s in secs], ls="none", marker="o", ms=8,
       color=S1, mec=SURF, mew=1.5)
label_end(a, 0.62, 25.3, "tabla APC PE0 (11x7)", S2)
label_end(a, 0.76, 19.6, "malla del modelo", S1)
a.set_xlim(0.2, 1.02)
a.set_ylim(0, 28)
a.set_xlabel("r/R")
a.set_ylabel("cuerda (mm)")
a.set_title("Cuerda APC Sport 11x7: malla medida vs tabla del fabricante")

# 3. front-view outline: model (PE0) vs UIUC photo silhouette
a = ax[1, 0]
spec = next(p for p in G.PROPS if p["key"] == "APC_11x7")
loops, rows, _ = G.build_loops(spec)
Rmm = spec["D"] * G.IN / 2
rs = [L[0][0] / Rmm for L in loops if L[0][0] > 12.7]
up = [max(p[1] for p in L) for L in loops if L[0][0] > 12.7]
dn = [min(p[1] for p in L) for L in loops if L[0][0] > 12.7]
a.plot(rs, up, color=S1, lw=2)
a.plot(rs, dn, color=S1, lw=2)
pl = G.PU.PLAN["apcsp_11x7_front"]
a.plot([p[0] for p in pl], [p[1] * Rmm for p in pl], color=S2, lw=2, ls=(0, (5, 3)))
a.plot([p[0] for p in pl], [-p[2] * Rmm for p in pl], color=S2, lw=2, ls=(0, (5, 3)))
label_end(a, 0.42, 15.6, "modelo (geometría PE0)", S1)
label_end(a, 0.6, -10.6, "foto UIUC (silueta medida)", S2)
a.axhline(0, color=MUTED, lw=0.8)
a.text(0.1, -15.6, "Ancho igual (±1 mm); el modelo va ~2 mm hacia el borde de ataque: eje de referencia distinto\n"
       "entre la tabla PE0 y la foto (hélice UIUC de otra serie).", color=INK2, fontsize=8.8, va="bottom")
a.set_xlim(0.08, 1.02)
a.set_ylim(-16, 19)
a.set_xlabel("r/R")
a.set_ylabel("borde de ataque (+) / de salida (-), mm")
a.set_title("Vista frontal APC 11x7: modelo vs foto independiente")

# 4. weight
a = ax[1, 1]
ks = [k for k in chk if chk[k]["mass_spec_g"]]
labs = [chk[k]["label"].replace("Master Airscrew", "MA").replace("APC Sport", "APC").replace("3-Blade", "3P")
        for k in ks]
xs = range(len(ks))
w = 0.38
a.bar([x - w / 2 - 0.01 for x in xs], [chk[k]["mass_g"] for k in ks], w, color=S1, label="modelo",
      edgecolor=SURF, lw=1)
a.bar([x + w / 2 + 0.01 for x in xs], [chk[k]["mass_spec_g"] for k in ks], w, color=S2, label="fabricante",
      edgecolor=SURF, lw=1)
for x, k in zip(xs, ks):
    e = chk[k]["mass_err_pct"]
    a.text(x, max(chk[k]["mass_g"], chk[k]["mass_spec_g"]) + 1.2, f"{e:+.0f}%", ha="center", color=INK2,
           fontsize=9)
a.set_xticks(list(xs))
a.set_xticklabels(labs, rotation=28, ha="right", fontsize=9)
a.set_ylabel("masa (g)")
a.set_ylim(0, 70)
a.legend(frameon=False, loc="upper right", labelcolor=INK, ncol=2)
pe0 = {k: chk[k].get("pe0_weight_g") for k in ks if chk[k].get("pe0_weight_g")}
a.text(-0.4, 59.0, "Simulación PE0 de APC (SG 1.7): " + ", ".join(f"{chk[k]['label'].split()[-1]} {v} g"
       for k, v in pe0.items()) + "\nMA: el espesor de pala se ajustó a su masa publicada (no es una comprobación independiente).",
       color=INK2, fontsize=8.8, va="center")
a.set_title("Masa: modelo (volumen x densidad) vs ficha del fabricante")
fig.suptitle("O.S. 61SF - hélices: verificación contra datos publicados", x=0.012, ha="left", fontsize=15,
             fontweight="bold", color=INK)
fig.text(0.012, 0.935, "APC: tablas PE0 de APC (paso, cuerda, espesor, centroides); MA: tablas y fotos UIUC vol. 1; "
         "masas: APC (Brodak/AMain), masterairscrew.com", color=INK2, fontsize=9.5)
fig.tight_layout(rect=(0, 0, 1, 0.925))
fig.savefig(OUT, facecolor=SURF)
print("saved", OUT)
