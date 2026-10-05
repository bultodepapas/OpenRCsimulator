# Sonda de investigación 16: cobertura de glifos, cifras tabulares (tnum), ejes y SHA-256 de fuentes candidatas.
# Uso: PYTHONPATH=<dir con fonttools 4.60.1> python3 check_fonts.py <carpeta con .ttf/.woff2>  (descargas fuera del repo)
import sys, glob, hashlib, os, json
from fontTools.ttLib import TTFont
CHARS = "áéíóúüñÁÉÍÓÚÜÑ¿¡°±·×"
EXTRA = "−–—…€‰²³µ←→↑↓"  # minus, dashes, ellipsis, euro, permil, sup, micro, arrows
out = []
for p in sorted(glob.glob(sys.argv[1] + "/*")):
    if not p.endswith((".ttf", ".woff2", ".otf")): continue
    f = TTFont(p)
    cmap = f.getBestCmap()
    miss = [c for c in CHARS if ord(c) not in cmap]
    miss_x = [c for c in EXTRA if ord(c) not in cmap]
    feats = set()
    for t in ("GSUB", "GPOS"):
        if t in f and f[t].table.FeatureList:
            feats |= {r.FeatureTag for r in f[t].table.FeatureList.FeatureRecord}
    axes = [a.axisTag + f"{a.minValue:g}-{a.maxValue:g}" for a in f["fvar"].axes] if "fvar" in f else []
    hmtx = f["hmtx"]; gs = f.getGlyphSet()
    digit_w = sorted({hmtx[cmap[ord(d)]][0] for d in "0123456789"})
    # glyph shapes distinct?  compare outline bounds of I l 1 and O 0
    name = f["name"].getDebugName(4); ver = f["name"].getDebugName(5)
    rfn = []
    for rec in f["name"].names:
        if rec.nameID == 0:
            s = rec.toUnicode()
            if "Reserved Font Name" in s: rfn.append(s[s.find("Reserved")-60:])
    out.append(dict(file=os.path.basename(p), name=name, version=ver, bytes=os.path.getsize(p),
        sha256=hashlib.sha256(open(p,"rb").read()).hexdigest(), glyphs=len(f.getGlyphOrder()),
        missing_es=miss, missing_extra=miss_x, tnum="tnum" in feats, pnum="pnum" in feats,
        default_digit_widths=digit_w, zero="zero" in feats, ss=sorted(x for x in feats if x.startswith(("ss","cv"))),
        axes=axes, rfn=bool(rfn), copyright=f["name"].getDebugName(0)))
print(json.dumps(out, ensure_ascii=False, indent=1))
