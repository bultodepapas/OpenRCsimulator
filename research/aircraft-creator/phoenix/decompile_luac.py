"""Readable pseudo-Lua from a Phoenix RC Lua 5.0 chunk (research only; nothing is executed).

The stock `.sim` / `.mod` scripts keep their debug information (local names and live ranges), so registers
map to named locals and temporaries fold back into expressions. Control flow stays as labelled gotos; the
output is for reading the flight model, not for recompiling. Uses `inspect_luac.py` for the container and
chunk parsing.

    python3 research/aircraft-creator/phoenix/decompile_luac.py <file.sim> > out.lua

Point it only at a local installation; never commit stock scripts or their decompiled text.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inspect_luac as L  # noqa: E402

FIELDS_PER_FLUSH = 32  # Lua 5.0 LFIELDS_PER_FLUSH
MAXSTACK = 250  # Lua 5.0 RK split: index >= MAXSTACK is a constant
BINARY = {"ADD": "+", "SUB": "-", "MUL": "*", "DIV": "/", "POW": "^"}
COMPARE = {"EQ": ("==", "~="), "LT": ("<", ">="), "LE": ("<=", ">")}


def constant(value):
    if isinstance(value, bytes):
        text = value.decode("latin-1")
        return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if value is None:
        return "nil"
    if isinstance(value, float) and value == int(value) and abs(value) < 1e15:
        return str(int(value))
    return repr(value)


def identifier(value):
    if isinstance(value, bytes):
        text = value.decode("latin-1")
        if text.isidentifier():
            return text
    return None


class Function:
    def __init__(self, f, name, depth):
        self.f = f
        self.name = name
        self.depth = depth
        self.code = f["code"]
        self.k = f["constants"]
        self.locals = [(n.decode("latin-1") if isinstance(n, bytes) else str(n), s, e) for n, s, e in f["locals"]]
        self.upvalues = [u.decode("latin-1") if isinstance(u, bytes) else str(u) for u in f["upvalues"]]
        self.out = []
        self.regs = {}
        self.targets = set()
        self.closures = {}

    # -- register naming ---------------------------------------------------------------------------
    def local_name(self, reg, pc):
        active = [name for name, start, end in self.locals if start <= pc < end]
        return active[reg] if reg < len(active) else None

    def rk(self, x, pc):
        if x >= MAXSTACK:
            return constant(self.k[x - MAXSTACK])
        return self.read(x, pc)

    def read(self, reg, pc):
        name = self.local_name(reg, pc)
        if name is not None and not name.startswith("("):
            return name
        expr = self.regs.pop(reg, None)
        return expr if expr is not None else "r%d" % reg

    def write(self, reg, expr, pc, side_effect=False):
        name = self.local_name(reg, pc + 1)
        if name is not None and not name.startswith("("):
            self.emit("%s = %s" % (name, expr))
            return
        if reg in self.regs:
            self.emit("r%d = %s" % (reg, self.regs.pop(reg)))
        if side_effect:
            self.emit("r%d = %s" % (reg, expr))
        else:
            self.regs[reg] = expr

    def flush(self):
        for reg in sorted(self.regs):
            self.emit("r%d = %s" % (reg, self.regs[reg]))
        self.regs = {}

    def emit(self, line):
        self.out.append("  " * (self.depth + 1) + line)

    def index(self, base, key_expr, key_value=None):
        name = identifier(key_value) if key_value is not None else None
        return "%s.%s" % (base, name) if name else "%s[%s]" % (base, key_expr)

    def key(self, x, pc):
        if x >= MAXSTACK:
            return self.rk(x, pc), self.k[x - MAXSTACK]
        return self.read(x, pc), None

    # -- decoding ----------------------------------------------------------------------------------
    def scan_targets(self):
        for pc, ins in enumerate(self.code):
            op, a, b, c, bx, sbx = L.decode(ins)
            name = L.OPNAMES[op]
            if name in ("JMP", "FORLOOP", "TFORPREP"):
                self.targets.add(pc + 1 + sbx)

    def run(self):
        params = [self.local_name(i, 0) or "p%d" % i for i in range(self.f["params"])]
        self.out.append("  " * self.depth + "function %s(%s)  -- line %s" % (self.name, ", ".join(params), self.f.get("line")))
        self.scan_targets()
        pc = 0
        while pc < len(self.code):
            if pc in self.targets:
                self.flush()
                self.out.append("  " * self.depth + " ::L%d::" % pc)
            pc = self.step(pc)
        self.flush()
        self.out.append("  " * self.depth + "end")
        for index, proto in enumerate(self.f["protos"]):
            child = Function(proto, self.closures.get(index, "%s.proto%d" % (self.name, index)), self.depth)
            child.run()
            self.out.append("")
            self.out.extend(child.out)
        return self.out

    def step(self, pc):
        op, a, b, c, bx, sbx = L.decode(self.code[pc])
        name = L.OPNAMES[op] if op < len(L.OPNAMES) else "OP%d" % op
        if name == "MOVE":
            self.write(a, self.read(b, pc), pc)
        elif name == "LOADK":
            self.write(a, constant(self.k[bx]), pc)
        elif name == "LOADBOOL":
            self.write(a, "true" if b else "false", pc)
            if c:
                self.flush()
                self.emit("goto L%d" % (pc + 2))
                self.targets.add(pc + 2)
        elif name == "LOADNIL":
            for reg in range(a, b + 1):
                self.write(reg, "nil", pc)
        elif name == "GETUPVAL":
            self.write(a, self.upvalues[b] if b < len(self.upvalues) else "upvalue%d" % b, pc)
        elif name == "GETGLOBAL":
            self.write(a, identifier(self.k[bx]) or "_G[%s]" % constant(self.k[bx]), pc)
        elif name == "GETTABLE":
            key_expr, key_value = self.key(c, pc)
            self.write(a, self.index(self.read(b, pc), key_expr, key_value), pc)
        elif name == "SETGLOBAL":
            value = self.read(a, pc)
            self.flush()
            self.emit("%s = %s" % (identifier(self.k[bx]) or "_G[%s]" % constant(self.k[bx]), value))
        elif name == "SETUPVAL":
            value = self.read(a, pc)
            self.flush()
            self.emit("%s = %s" % (self.upvalues[b] if b < len(self.upvalues) else "upvalue%d" % b, value))
        elif name == "SETTABLE":
            key_expr, key_value = self.key(b, pc)
            value = self.rk(c, pc)
            target = self.read(a, pc)
            self.flush()
            self.emit("%s = %s" % (self.index(target, key_expr, key_value), value))
            if value.startswith("function") or value.startswith("<closure"):
                pass
        elif name == "NEWTABLE":
            self.write(a, "{}", pc)
        elif name == "SELF":
            obj = self.read(b, pc)
            key_expr, key_value = self.key(c, pc)
            self.write(a + 1, obj, pc)
            self.write(a, "%s:%s" % (obj, identifier(key_value) or key_expr), pc)
        elif name in BINARY:
            self.write(a, "(%s %s %s)" % (self.rk(b, pc), BINARY[name], self.rk(c, pc)), pc)
        elif name == "UNM":
            self.write(a, "-%s" % self.read(b, pc), pc)
        elif name == "NOT":
            self.write(a, "not %s" % self.read(b, pc), pc)
        elif name == "CONCAT":
            self.write(a, "(" + " .. ".join(self.read(r, pc) for r in range(b, c + 1)) + ")", pc)
        elif name == "JMP":
            self.flush()
            self.emit("goto L%d" % (pc + 1 + sbx))
        elif name in COMPARE:
            left, right = self.rk(b, pc), self.rk(c, pc)
            jump = L.decode(self.code[pc + 1])
            target = pc + 2 + jump[5]
            self.targets.add(target)
            self.flush()
            operator = COMPARE[name][0] if a else COMPARE[name][1]
            self.emit("if %s %s %s then goto L%d end" % (left, operator, right, target))
            return pc + 2
        elif name == "TEST":
            value = self.read(b, pc)
            jump = L.decode(self.code[pc + 1])
            target = pc + 2 + jump[5]
            self.targets.add(target)
            self.flush()
            if a != b:
                self.emit("r%d = %s  -- when the test jumps" % (a, value))
            self.emit("if %s%s then goto L%d end" % ("" if c else "not ", value, target))
            return pc + 2
        elif name in ("CALL", "TAILCALL"):
            func = self.read(a, pc)
            if b == 0:
                args = [self.read(r, pc) for r in range(a + 1, a + 1 + 8) if r in self.regs or self.local_name(r, pc)]
                args.append("...")
            else:
                args = [self.read(r, pc) for r in range(a + 1, a + b)]
            if func.endswith(":" + func.split(":")[-1]) and ":" in func and args:
                args = args[1:]
            call = "%s(%s)" % (func, ", ".join(args))
            if name == "TAILCALL":
                self.flush()
                self.emit("return " + call)
            elif c == 1:
                self.flush()
                self.emit(call)
            elif c == 2:
                self.write(a, call, pc, side_effect=True)
            else:
                self.flush()
                results = ["r%d" % r for r in range(a, a + c - 1)] if c else ["r%d..." % a]
                self.emit("%s = %s" % (", ".join(results), call))
        elif name == "RETURN":
            values = [self.read(r, pc) for r in range(a, a + b - 1)] if b else ["r%d..." % a]
            self.flush()
            self.emit("return " + ", ".join(values))
        elif name == "FORLOOP":
            self.flush()
            counter = self.local_name(a, pc) or "r%d" % a
            self.emit("%s = %s + step; if %s <= limit then goto L%d end  -- for" % (counter, counter, counter, pc + 1 + sbx))
        elif name == "TFORPREP":
            self.flush()
            self.emit("goto L%d  -- generic for" % (pc + 1 + sbx))
        elif name == "TFORLOOP":
            self.flush()
            names = [self.local_name(r, pc + 1) or "r%d" % r for r in range(a + 2, a + 3 + c)]
            self.emit("%s = iterate(r%d)  -- generic for; leaves the loop when nil" % (", ".join(names), a))
        elif name in ("SETLIST", "SETLISTO"):
            first = bx - bx % FIELDS_PER_FLUSH
            count = bx % FIELDS_PER_FLUSH + 1
            target = self.read(a, pc)
            items = [self.read(r, pc) for r in range(a + 1, a + 1 + count)]
            self.flush()
            self.emit("%s[%d..] = {%s}" % (target, first + 1, ", ".join(items)))
        elif name == "CLOSE":
            pass
        elif name == "CLOSURE":
            proto = self.f["protos"][bx]
            self.write(a, "<closure %d>" % bx, pc)
            # Name the closure from the next store, when it is a plain field or global.
            nxt = L.decode(self.code[pc + 1]) if pc + 1 < len(self.code) else None
            if nxt and L.OPNAMES[nxt[0]] == "SETTABLE" and nxt[3] == a and nxt[2] >= MAXSTACK:
                self.closures[bx] = identifier(self.k[nxt[2] - MAXSTACK]) or "proto%d" % bx
            elif nxt and L.OPNAMES[nxt[0]] == "SETGLOBAL" and nxt[1] == a:
                self.closures[bx] = identifier(self.k[nxt[4]]) or "proto%d" % bx
            skip = proto["nups"]
            return pc + 1 + skip
        else:
            self.flush()
            self.emit("-- %s %d %d %d" % (name, a, b, c))
        return pc + 1


def main(path):
    chunk = L.parse(open(path, "rb").read())
    for line in Function(chunk, "main", 0).run():
        print(line)


if __name__ == "__main__":
    main(sys.argv[1])
