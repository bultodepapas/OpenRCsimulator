#!/usr/bin/env python3
"""Read-only research reader for Phoenix RC stock `.mod` / `.sim` script containers.

Observed container (2026-11-20, PhoenixRC 5.5.k stock install and 6.0.i update):
  bytes 0..7  magic 00 01 02 04 08 10 20 40
  then pairs  each logical byte = (p[2i] + p[2i+1]) mod 256
The logical stream is a standard Lua 5.0 binary chunk ("\\x1bLua" 0x50).

This tool never runs Lua. It parses the chunk and abstractly evaluates only the
straight-line data-construction subset (constants, tables, globals as symbols).
Any other opcode stops evaluation of that function with a diagnostic. Functions
are reported as opaque closures. See docs/research/aircraft-creator/phoenix-stock-format-2026-11-20.md.

Usage: inspect_luac.py FILE.mod [--json OUT.json] [--listing]
       inspect_luac.py --corpus ROOT
"""
import argparse, json, math, os, struct, sys

MAGIC = bytes([0, 1, 2, 4, 8, 16, 32, 64])
PROFILE = "openrc-phoenix-luac50-observed-v1"
MAX_INPUT = 8 << 20
MAX_CONSTANTS = 1 << 16
MAX_CODE = 1 << 18
MAX_DEPTH = 16
OPNAMES = ["MOVE", "LOADK", "LOADBOOL", "LOADNIL", "GETUPVAL", "GETGLOBAL", "GETTABLE", "SETGLOBAL",
           "SETUPVAL", "SETTABLE", "NEWTABLE", "SELF", "ADD", "SUB", "MUL", "DIV", "POW", "UNM", "NOT",
           "CONCAT", "JMP", "EQ", "LT", "LE", "TEST", "CALL", "TAILCALL", "RETURN", "FORLOOP",
           "TFORLOOP", "TFORPREP", "SETLIST", "SETLISTO", "CLOSE", "CLOSURE"]
MAXSTACK = 250
FIELDS_PER_FLUSH = 32


class ChunkError(ValueError):
    pass


def unsplit(data):
    if data[:8] != MAGIC:
        raise ChunkError("not the observed Phoenix script container")
    if (len(data) - 8) % 2:
        raise ChunkError("odd payload length")
    p = memoryview(data)[8:]
    return bytes((p[i] + p[i + 1]) & 0xFF for i in range(0, len(p), 2))


class Reader:
    def __init__(self, b):
        self.b, self.o = b, 0

    def take(self, n):
        if n < 0 or self.o + n > len(self.b):
            raise ChunkError("truncated at %d" % self.o)
        v = self.b[self.o:self.o + n]
        self.o += n
        return v

    def byte(self):
        return self.take(1)[0]

    def int(self):
        return struct.unpack("<i", self.take(4))[0]

    def count(self, limit):
        n = self.int()
        if not 0 <= n <= limit:
            raise ChunkError("count %d out of range at %d" % (n, self.o))
        return n

    def string(self):
        n = struct.unpack("<I", self.take(4))[0]
        if n == 0:
            return None
        if n > len(self.b):
            raise ChunkError("string length")
        s = self.take(n)
        if s[-1] != 0:
            raise ChunkError("string not NUL terminated")
        return s[:-1]

    def number(self):
        return struct.unpack("<d", self.take(8))[0]


def parse_function(r, depth=0):
    if depth > MAX_DEPTH:
        raise ChunkError("function nesting")
    f = {"source": r.string(), "line": r.int(), "nups": r.byte(), "params": r.byte(),
         "vararg": r.byte(), "maxstack": r.byte()}
    f["lines"] = [r.int() for _ in range(r.count(MAX_CODE))]
    f["locals"] = [(r.string(), r.int(), r.int()) for _ in range(r.count(MAX_CONSTANTS))]
    f["upvalues"] = [r.string() for _ in range(r.count(255))]
    consts = []
    for _ in range(r.count(MAX_CONSTANTS)):
        t = r.byte()
        if t == 3:
            consts.append(r.number())
        elif t == 4:
            consts.append(r.string())
        elif t == 0:
            consts.append(None)
        else:
            raise ChunkError("constant type %d" % t)
    f["constants"] = consts
    f["protos"] = [parse_function(r, depth + 1) for _ in range(r.count(4096))]
    f["code"] = [struct.unpack("<I", r.take(4))[0] for _ in range(r.count(MAX_CODE))]
    return f


def parse(data):
    if len(data) > MAX_INPUT:
        raise ChunkError("input limit")
    b = unsplit(data)
    r = Reader(b)
    hdr = r.take(12)
    if hdr != b"\x1bLua\x50\x01\x04\x04\x04\x06\x08\x09" or r.byte() != 9 or r.byte() != 8:
        raise ChunkError("unexpected Lua header %s" % hdr.hex())
    if r.number() != 3.14159265358979323846E7:
        raise ChunkError("test number mismatch")
    main = parse_function(r)
    if r.o != len(b):
        raise ChunkError("%d trailing bytes" % (len(b) - r.o))
    return main


def decode(i):
    op = i & 0x3F
    c = (i >> 6) & 0x1FF
    b = (i >> 15) & 0x1FF
    a = (i >> 24) & 0xFF
    bx = (i >> 6) & 0x3FFFF
    return op, a, b, c, bx, bx - 131071


# ------------------------------------------------------------------ evaluation

class Sym:
    """A value read from an unknown global, e.g. physics.airplane."""
    def __init__(self, path):
        self.path = path

    def __repr__(self):
        return self.path


class LTable:
    def __init__(self):
        self.items = []  # ordered (key, value); later assignment replaces

    def set(self, k, v):
        for i, (kk, _) in enumerate(self.items):
            if type(kk) is type(k) and kk == k:
                self.items[i] = (k, v)
                return
        self.items.append((k, v))

    def get(self, k):
        for kk, v in self.items:
            if type(kk) is type(k) and kk == k:
                return v
        return None


def to_text(v):
    return v.decode("latin-1") if isinstance(v, bytes) else v


def plain(v, depth=0):
    if depth > 64:
        return "<depth>"
    if isinstance(v, LTable):
        keys = [k for k, _ in v.items]
        if keys and all(isinstance(k, float) and k == i + 1 for i, k in enumerate(keys)):
            return [plain(x, depth + 1) for _, x in v.items]
        out = {}
        for k, x in v.items:
            ks = to_text(k)
            if isinstance(ks, float):
                ks = ("%d" % ks) if ks.is_integer() else repr(ks)
            out[str(ks)] = plain(x, depth + 1)
        return out
    if isinstance(v, bytes):
        return to_text(v)
    if isinstance(v, Sym):
        return {"$symbol": v.path}
    if isinstance(v, dict):
        return v
    if isinstance(v, float) and v.is_integer() and abs(v) < 2 ** 53:
        return int(v)
    return v


def evaluate(fn, max_steps=2_000_000):
    """Straight-line abstract evaluation of a data chunk. Returns (globals, diagnostics)."""
    regs = [None] * 256
    globals_ = LTable()
    assigned = LTable()  # assignments into unknown globals, e.g. modelTypes.easystar
    diags = []
    k = fn["constants"]

    def rk(x):
        return k[x - MAXSTACK] if x >= MAXSTACK else regs[x]

    def gget(name):
        v = globals_.get(name)
        return v if v is not None else Sym(to_text(name))

    pc, steps = 0, 0
    code = fn["code"]
    while pc < len(code):
        steps += 1
        if steps > max_steps:
            diags.append("step limit")
            break
        op, a, b, c, bx, sbx = decode(code[pc])
        name = OPNAMES[op] if op < len(OPNAMES) else "OP%d" % op
        pc += 1
        if name == "MOVE":
            regs[a] = regs[b]
        elif name == "LOADK":
            regs[a] = k[bx]
        elif name == "LOADBOOL":
            regs[a] = bool(b)
            if c:
                pc += 1
        elif name == "LOADNIL":
            for i in range(a, b + 1):
                regs[i] = None
        elif name == "GETGLOBAL":
            regs[a] = gget(k[bx])
        elif name == "SETGLOBAL":
            globals_.set(k[bx], regs[a])
        elif name == "NEWTABLE":
            regs[a] = LTable()
        elif name == "SETTABLE":
            t = regs[a]
            if isinstance(t, LTable):
                t.set(rk(b), rk(c))
            elif isinstance(t, Sym):
                assigned.set("%s.%s" % (t.path, to_text(rk(b))), rk(c))
            else:
                diags.append("SETTABLE on non-table at pc %d" % (pc - 1))
        elif name == "GETTABLE":
            t, key = regs[b], rk(c)
            if isinstance(t, LTable):
                regs[a] = t.get(key)
            elif isinstance(t, Sym):
                regs[a] = Sym("%s.%s" % (t.path, to_text(key)))
            else:
                regs[a] = None
                diags.append("GETTABLE on non-table at pc %d" % (pc - 1))
        elif name in ("SETLIST", "SETLISTO"):
            t = regs[a]
            n = bx % FIELDS_PER_FLUSH + 1
            base = bx - bx % FIELDS_PER_FLUSH
            for i in range(1, n + 1):
                t.set(float(base + i), regs[a + i])
        elif name == "UNM":
            v = regs[b]
            regs[a] = -v if isinstance(v, float) else {"$expr": "-", "of": plain(v)}
        elif name in ("ADD", "SUB", "MUL", "DIV"):
            x, y = rk(b), rk(c)
            if isinstance(x, float) and isinstance(y, float):
                regs[a] = {"ADD": x + y, "SUB": x - y, "MUL": x * y, "DIV": x / y if y else math.nan}[name]
            else:
                regs[a] = {"$expr": name, "args": [plain(x), plain(y)]}
        elif name == "CLOSURE":
            regs[a] = {"$closure": pc - 1}
            pc += fn["protos"][bx]["nups"]
        elif name == "RETURN":
            break
        else:
            diags.append("stopped at unsupported %s (pc %d)" % (name, pc - 1))
            break
    return globals_, assigned, diags


def summarize(path):
    data = open(path, "rb").read()
    fn = parse(data)
    g, assigned, diags = evaluate(fn)
    return {"profile": PROFILE, "source": to_text(fn["source"]), "globals": plain(g),
            "assigned": plain(assigned), "diagnostics": diags,
            "instructions": len(fn["code"]), "constants": len(fn["constants"]), "functions": len(fn["protos"])}


def listing(fn, indent=""):
    for pc, ins in enumerate(fn["code"]):
        op, a, b, c, bx, sbx = decode(ins)
        print("%s%4d %-9s A=%d B=%d C=%d Bx=%d" % (indent, pc, OPNAMES[op] if op < len(OPNAMES) else op, a, b, c, bx))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("file", nargs="?")
    ap.add_argument("--json")
    ap.add_argument("--listing", action="store_true")
    ap.add_argument("--corpus")
    a = ap.parse_args(argv)
    if a.corpus:
        ok = bad = clean = 0
        for dp, dn, fn in sorted(os.walk(a.corpus)):
            for f in sorted(fn):
                if not f.lower().endswith((".mod", ".sim", ".var")):
                    continue
                p = os.path.join(dp, f)
                try:
                    s = summarize(p)
                    ok += 1
                    clean += not s["diagnostics"]
                except (ChunkError, struct.error, IndexError) as e:
                    bad += 1
                    print("rejected", os.path.relpath(p, a.corpus), e)
        print("parsed %d (straight-line clean %d) rejected %d" % (ok, clean, bad))
        return 0
    if a.listing:
        listing(parse(open(a.file, "rb").read()))
        return 0
    s = summarize(a.file)
    text = json.dumps(s, indent=1, ensure_ascii=False)
    if a.json:
        with open(a.json, "x", encoding="utf-8") as fh:
            fh.write(text + "\n")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
