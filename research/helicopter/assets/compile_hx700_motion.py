"""Compile a reviewed, mechanical-only subset of Blender scalar expressions to GDScript.

No eval, Blender driver interpreter, aerodynamic telemetry or frame clock in runtime.
Generated transforms are an inspection oracle, not achieved flight servo dynamics.
"""
import argparse
import ast
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "assets/aircraft/hx-700/articulated/motion-source.json"
OUTPUT = ROOT / "app/render/rotor/hx700_motion_equations.gd"
SOURCE_SHA256 = "1919de349b74286bc36770ab2d7d08f743fd8a4062608d488c7e4e276103725f"
MOTION_SOURCE_SHA256 = "24f99dd8c7c1c9a79e4421198c27c837e44b3aa8eed9c4dfd0b4ee0293f13db3"
INPUTS = {"paso_colectivo": "collective_deg", "ciclico_alabeo": "roll_deg",
          "ciclico_cabeceo": "pitch_deg", "paso_cola": "tail_deg", "giro_rotor": "phase_rad"}
FUNCS = {"sin": "sin", "cos": "cos", "tan": "tan", "asin": "asin", "acos": "acos",
         "atan": "atan", "atan2": "atan2", "sqrt": "sqrt", "radians": "deg_to_rad",
         "degrees": "rad_to_deg", "abs": "absf", "min": "minf", "max": "maxf", "floor": "floorf"}


def number(value):
    return repr(float(value))


def vector(values):
    return "Vector3(" + ", ".join(map(str, values)) + ")"


def transform(values):
    v = list(map(number, values))
    return "Transform3D(Basis(%s, %s, %s), %s)" % tuple(vector(v[i:i+3]) for i in (0, 3, 6, 9))


class Compiler:
    def __init__(self, data):
        self.objects = data["objects"]
        self.resolved = {}
        self.pending = set()
        self.lines = []

    def prop(self, name, path):
        key = name, path
        if key in self.resolved:
            return self.resolved[key]
        if key in self.pending:
            raise ValueError("cyclic source dependency: " + str(key))
        property_name = json.loads(path[1:-1])
        if name == "HX-700" and property_name in INPUTS:
            return INPUTS[property_name]
        # Precompensation is authored off in this inspection configuration.
        # Cut this exact boundary instead of evaluating source aero/engine laws.
        if key == ("Mezclador_01e_Precomp_Paso", '["PC"]'):
            return "-deg_to_rad(tail_deg)"
        if "Aero" in name or "Precomp" in name or "Telemetria" in name:
            raise ValueError("non-mechanical source dependency: " + str(key))
        self.pending.add(key)
        obj = self.objects[name]
        driver = next((d for d in obj["drivers"] if d["path"] == path), None)
        if driver:
            expression = self.expression(driver)
            symbol = "v%d" % len(self.lines)
            self.lines.append("\tvar %s: float = %s # %s.%s" % (symbol, expression, name, property_name))
        else:
            symbol = number(obj["properties"][property_name])
        self.pending.remove(key)
        self.resolved[key] = symbol
        return symbol

    def expression(self, driver):
        variables = driver["variables"]
        def emit(node):
            if isinstance(node, ast.Constant) and type(node.value) in (int, float):
                return number(node.value)
            if isinstance(node, ast.Name):
                return "1.0" if node.id == "frame" else self.prop(*variables[node.id])
            if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
                return ("-" if isinstance(node.op, ast.USub) else "+") + "(" + emit(node.operand) + ")"
            if isinstance(node, ast.BinOp) and type(node.op) in (ast.Add, ast.Sub, ast.Mult, ast.Div):
                op = {ast.Add: "+", ast.Sub: "-", ast.Mult: "*", ast.Div: "/"}[type(node.op)]
                return "(" + emit(node.left) + " " + op + " " + emit(node.right) + ")"
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in FUNCS and not node.keywords:
                args = [emit(x) for x in node.args]
                if node.func.id in ("min", "max"):
                    while len(args) > 2:
                        args[:2] = [FUNCS[node.func.id] + "(" + ", ".join(args[:2]) + ")"]
                return FUNCS[node.func.id] + "(" + ", ".join(args) + ")"
            raise ValueError("unsupported expression: " + ast.dump(node))
        return emit(ast.parse(driver["expression"], mode="eval").body)


def compile_source(source_bytes):
    if hashlib.sha256(source_bytes).hexdigest() != MOTION_SOURCE_SHA256:
        raise ValueError("Motion source snapshot differs from the reviewed mechanical expressions")
    data = json.loads(source_bytes.decode("utf-8"))
    if data.get("source_sha256") != SOURCE_SHA256:
        raise ValueError("Motion source is not the reviewed HX-700 revision")
    adjustments = data["objects"]["Ajustes_Mecanicos"]["properties"]
    for name, value in adjustments.items():
        expected = 40.0 if name in ("limite_servos_ciclicos", "limite_servo_cola") else 0.0
        if value != expected:
            raise ValueError("Inspection requires neutral authored adjustment: " + name)
    profile_bytes = (ROOT / "assets/aircraft/hx-700/articulated/construction.json").read_bytes()
    bindings = {b["id"]: b for b in json.loads(profile_bytes)["bindings"]}
    pose_ids = [r["id"] for r in data["recipes"]]
    if len(set(pose_ids)) != len(pose_ids) or any(r["id"] not in bindings or bindings[r["id"]]["node"] != r["node"] for r in data["recipes"]):
        raise ValueError("Motion recipes must uniquely bind the reviewed construction profile")
    c = Compiler(data)
    poses = []
    for recipe in data["recipes"]:
        components = {key: list(map(number, recipe[key])) for key in ("location", "rotation_euler", "scale")}
        for driver in data["objects"][recipe["node"]]["drivers"]:
            if driver["path"] in components:
                components[driver["path"]][driver["index"]] = c.expression(driver)
        loc, rot, scale = (components[k] for k in ("location", "rotation_euler", "scale"))
        basis = "Basis(Vector3.UP, %s) * Basis(Vector3.FORWARD, %s) * Basis(Vector3.RIGHT, %s) * Basis.from_scale(%s)" % (*rot[::-1], vector([scale[0], scale[2], scale[1]]))
        expr = transform(recipe["parent_inverse"]) + " * Transform3D(" + basis + ", " + vector([loc[0], loc[2], "-(" + loc[1] + ")"]) + ")"
        poses.append('\t\t"%s": %s,' % (recipe["id"], expr))
    servos = [c.prop("Mezclador_08_Servos", '["%s"]' % k) for k in ("SV_FL", "SV_FR", "SV_R", "GAM")]
    pitches = ["-(" + c.prop("Mezclador_20_Palas", '["RA"]') + ")", c.prop("Mezclador_20_Palas", '["RB"]'), "-(" + c.prop("Mezclador_15_Plato_Real", '["PCR"]') + ")"]
    return '\n'.join([
        '# Generated by research/helicopter/assets/compile_hx700_motion.py. Do not edit.',
        '# HELI-26a: bounded mechanical inspection only; no flight/actuator dynamics.',
        'extends RefCounted', '', 'const SOURCE_SHA256 := "%s"' % data["source_sha256"],
        'const MOTION_SOURCE_SHA256 := "%s"' % MOTION_SOURCE_SHA256,
        'const PROFILE_SHA256 := "%s"' % hashlib.sha256(profile_bytes).hexdigest(),
        'const POSE_IDS := ' + json.dumps(pose_ids), '',
        'static func evaluate(collective_deg: float, roll_deg: float, pitch_deg: float, tail_deg: float, phase_rad: float) -> Dictionary:',
        *c.lines, '\tvar poses: Dictionary = {', *poses, '\t}',
        '\treturn {"poses": poses, "servos": PackedFloat64Array([' + ', '.join(servos) + ']),',
        '\t\t"blade_pitch": PackedFloat64Array([' + ', '.join(pitches) + '])}', ''])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--out", type=Path, default=OUTPUT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = compile_source(args.source.read_bytes())
    if args.check:
        if args.out.read_text(encoding="utf-8") != text:
            raise SystemExit("Generated HX-700 motion equations are stale")
    else:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8", newline="\n")
    print("HX-700 mechanical equations match source" if args.check else str(args.out))


if __name__ == "__main__":
    main()
