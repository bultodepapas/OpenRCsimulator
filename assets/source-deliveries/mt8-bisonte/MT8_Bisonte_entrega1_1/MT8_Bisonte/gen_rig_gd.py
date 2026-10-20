"""Genera godot/mt8_rig.gd con las constantes de mt8_spec.py (una sola fuente de verdad)."""
import os
import mt8_spec as S

HERE = os.path.dirname(os.path.abspath(__file__))

TEMPLATE = r'''# mt8_rig.gd - rig visual del Bisonte MT8 (generado por gen_rig_gd.py; no editar a mano)
# Coloca este script en un Node3D que sea padre (o abuelo) del nodo MT8_Root importado del .glb.
# El simulador decide recorrido, direccion y giro; este script solo coloca las piezas.
#   set_travel(corner, t)  t en metros, + = compresion (rueda sube respecto al chasis)
#   set_steer(delta)       radianes, + = gira a la izquierda (solo FL/FR)
#   set_spin(corner, a)    radianes alrededor de +X local; avanzar (-Z) = angulo decreciente
@tool
extends Node3D

const ARM_X_IN := {ARM_X_IN}
const ARM_L := {ARM_L}
const Y_ARM_LO := {Y_ARM_LO}
const Y_ARM_UP := {Y_ARM_UP}
const X_WHEEL := {X_WHEEL}
const RIDE_Y_WHEEL := {RIDE_Y_WHEEL}
const Z_FRONT := {Z_FRONT}
const Z_REAR := {Z_REAR}
const TRAVEL_BUMP := {TRAVEL_BUMP}
const TRAVEL_DROOP := {TRAVEL_DROOP}
const STEER_MAX := {STEER_MAX}
const SHOCK_DZ := {SHOCK_DZ}
const SHOCK_LO_ARM := Vector2({SHOCK_LO_X}, {SHOCK_LO_Y})
const SHOCK_UP := Vector2({SHOCK_UP_X}, {SHOCK_UP_Y})
const SHOCK_CAP_UP := {SHOCK_CAP_UP}
const SHOCK_CAP_LO := {SHOCK_CAP_LO}
const SPRING_REST := {SPRING_REST}
const DIFF_OUT_X := {DIFF_OUT_X}
const CV_OFF := {CV_OFF}
const CORNERS := ["FL", "FR", "RL", "RR"]

@export var root_path: NodePath = ^"MT8_Root"
@export_range(-0.07, 0.05, 0.001) var preview_travel := 0.0:
	set(v):
		preview_travel = v
		for c in CORNERS:
			travel[c] = v
		_apply()
@export_range(-30.0, 30.0, 0.5) var preview_steer_deg := 0.0:
	set(v):
		preview_steer_deg = v
		steer = deg_to_rad(v)
		_apply()

var travel := {"FL": 0.0, "FR": 0.0, "RL": 0.0, "RR": 0.0}
var spin := {"FL": 0.0, "FR": 0.0, "RL": 0.0, "RR": 0.0}
var steer := 0.0
var _n := {}


func _ready() -> void:
	_cache()
	_apply()


func _cache() -> void:
	_n.clear()
	var r := get_node_or_null(root_path)
	if r == null:
		return
	for c in CORNERS:
		for part in ["ArmLower", "ArmUpper", "Suspension", "Steer", "Spin", "DriveshaftIn", "DriveshaftOut",
				"ShockA_Body", "ShockA_Spring", "ShockA_Shaft", "ShockB_Body", "ShockB_Spring", "ShockB_Shaft"]:
			var nd := r.find_child(c + "_" + part, true, false)
			if nd:
				_n[c + "_" + part] = nd


func set_travel(corner: String, t: float) -> void:
	travel[corner] = clampf(t, -TRAVEL_DROOP, TRAVEL_BUMP)
	_apply_corner(corner)


func set_steer(delta: float) -> void:
	steer = clampf(delta, -STEER_MAX, STEER_MAX)
	_apply_corner("FL")
	_apply_corner("FR")


func set_spin(corner: String, a: float) -> void:
	spin[corner] = a
	if _n.has(corner + "_Spin"):
		_n[corner + "_Spin"].transform.basis = Basis(Vector3.RIGHT, a)


func _apply() -> void:
	if _n.is_empty():
		_cache()
	for c in CORNERS:
		_apply_corner(c)


static func side_of(c: String) -> float:
	return -1.0 if c[1] == "L" else 1.0


static func axle_z(c: String) -> float:
	return Z_FRONT if c[0] == "F" else Z_REAR


static func arm_angle(t: float) -> float:
	return asin(clampf(t, -TRAVEL_DROOP, TRAVEL_BUMP) / ARM_L)


func _apply_corner(c: String) -> void:
	if _n.is_empty():
		return
	var s := side_of(c)
	var za := axle_z(c)
	var th := arm_angle(travel[c])
	var rot_arm := Basis(Vector3.BACK, s * th)  # giro alrededor de +Z
	_n[c + "_ArmLower"].transform = Transform3D(rot_arm, Vector3(s * ARM_X_IN, Y_ARM_LO, za))
	_n[c + "_ArmUpper"].transform = Transform3D(rot_arm, Vector3(s * ARM_X_IN, Y_ARM_UP, za))
	var off := Vector3(s * ARM_L * (cos(th) - 1.0), ARM_L * sin(th), 0.0)
	_n[c + "_Suspension"].transform = Transform3D(Basis(), Vector3(s * X_WHEEL, RIDE_Y_WHEEL, za) + off)
	var d := 0.0
	if c[0] == "F":
		d = clampf(steer, -STEER_MAX, STEER_MAX)
		_n[c + "_Steer"].transform = Transform3D(Basis(Vector3.UP, d), Vector3.ZERO)
	_n[c + "_Spin"].transform = Transform3D(Basis(Vector3.RIGHT, spin[c]), Vector3.ZERO)
	for w in ["A", "B"]:
		var dz := -SHOCK_DZ if w == "A" else SHOCK_DZ
		var up := Vector3(s * SHOCK_UP.x, SHOCK_UP.y, za + dz)
		var lo_arm := Vector3(s * SHOCK_LO_ARM.x, SHOCK_LO_ARM.y, dz)
		var lo := Vector3(s * ARM_X_IN, Y_ARM_LO, za) + rot_arm * lo_arm
		var D := lo - up
		var beta := atan2(D.x, -D.y)
		_n[c + "_Shock" + w + "_Body"].transform = Transform3D(Basis(Vector3.BACK, beta), up)
		var k := (D.length() - SHOCK_CAP_UP - SHOCK_CAP_LO) / SPRING_REST
		_n[c + "_Shock" + w + "_Spring"].transform = Transform3D(Basis().scaled(Vector3(1.0, k, 1.0)), Vector3(0, -SHOCK_CAP_UP, 0))
		_n[c + "_Shock" + w + "_Shaft"].transform = Transform3D(Basis(Vector3.BACK, beta - s * th), lo_arm)
	var pin := Vector3(s * DIFF_OUT_X, RIDE_Y_WHEEL, za)
	var wc := Vector3(s * X_WHEEL, RIDE_Y_WHEEL, za) + off
	var pout := wc + Basis(Vector3.UP, d) * Vector3(-s * CV_OFF, 0, 0)
	var dir := (pout - pin).normalized()
	_n[c + "_DriveshaftIn"].transform = Transform3D(Basis(Quaternion(Vector3(s, 0, 0), dir)), pin)
	# la pieza exterior cuelga de la mangueta: su giro local descuenta la direccion
	var q_out := Quaternion(Vector3(-s, 0, 0), -dir)
	_n[c + "_DriveshaftOut"].transform = Transform3D(Basis(Vector3.UP, -d) * Basis(q_out), Vector3(-s * CV_OFF, 0, 0))
'''


def main():
    vals = dict(
        ARM_X_IN=S.ARM_X_IN, ARM_L=S.ARM_L, Y_ARM_LO=S.Y_ARM_LO, Y_ARM_UP=S.Y_ARM_UP, X_WHEEL=S.X_WHEEL,
        RIDE_Y_WHEEL=S.RIDE_Y_WHEEL, Z_FRONT=S.Z_FRONT, Z_REAR=S.Z_REAR, TRAVEL_BUMP=S.TRAVEL_BUMP,
        TRAVEL_DROOP=S.TRAVEL_DROOP, STEER_MAX=f"deg_to_rad({S.STEER_MAX_DEG})", SHOCK_DZ=S.SHOCK_DZ,
        SHOCK_LO_X=S.SHOCK_LO_ARM[0], SHOCK_LO_Y=S.SHOCK_LO_ARM[1], SHOCK_UP_X=S.SHOCK_UP[0], SHOCK_UP_Y=S.SHOCK_UP[1],
        SHOCK_CAP_UP=S.SHOCK_CAP_UP, SHOCK_CAP_LO=S.SHOCK_CAP_LO, SPRING_REST=repr(S.SPRING_REST),
        DIFF_OUT_X=S.DIFF_OUT_X, CV_OFF=S.CV_OFF,
    )
    out = TEMPLATE
    for k, v in vals.items():
        out = out.replace("{" + k + "}", str(v))
    os.makedirs(os.path.join(HERE, "godot"), exist_ok=True)
    with open(os.path.join(HERE, "godot", "mt8_rig.gd"), "w") as f:
        f.write(out)
    print("ok")


if __name__ == "__main__":
    main()
