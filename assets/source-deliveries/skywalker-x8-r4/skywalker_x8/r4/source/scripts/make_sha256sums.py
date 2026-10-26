"""SHA256SUMS.txt de todo el paquete excepto el propio manifiesto (r4).

  python make_sha256sums.py <raiz_del_paquete>            escribe SHA256SUMS.txt
  python make_sha256sums.py <raiz_del_paquete> --check    verifica (como sha256sum -c)
"""
import sys, os, hashlib
PKG = os.path.abspath(sys.argv[1])
MAN = os.path.join(PKG, "SHA256SUMS.txt")
SKIP_DIRS = {"__pycache__", "_work", "_tmp"}


def files():
    for root, dirs, fs in os.walk(PKG):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for f in sorted(fs):
            p = os.path.join(root, f)
            if p != MAN and not f.endswith(".blend1"):
                yield os.path.relpath(p, PKG)


def h(p):
    d = hashlib.sha256()
    with open(p, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            d.update(b)
    return d.hexdigest()


if "--check" in sys.argv:
    bad, seen = [], set()
    for line in open(MAN):
        hh, rel = line.rstrip("\n").split("  ", 1)
        seen.add(rel)
        p = os.path.join(PKG, rel)
        if not os.path.exists(p) or h(p) != hh:
            bad.append(rel)
    extra = sorted(set(files()) - seen)
    print("SHA256SUMS", "OK" if not bad and not extra else "FALLA", len(seen), "archivos", bad[:5], extra[:5])
    sys.exit(0 if not bad and not extra else 1)
lines = [f"{h(os.path.join(PKG, r))}  {r}" for r in files()]
open(MAN, "w").write("\n".join(lines) + "\n")
print("SHA256SUMS", len(lines), "archivos")
