# mt8_rig.gd - rig visual del Bisonte MT8 (generado por gen_rig_gd.py; no editar a mano)
# Coloca este script en un Node3D que sea padre (o abuelo) del nodo MT8_Root importado del .glb.
# El simulador decide recorrido, direccion y giro; este script solo coloca las piezas.
#   set_travel(corner, t)  t en metros, + = compresion (rueda sube respecto al chasis)
#   set_steer(delta)       radianes, + = gira a la izquierda (solo FL/FR)
#   set_spin(corner, a)    radianes alrededor de +X local; avanzar (-Z) = angulo decreciente
@tool
extends Node3D

const ARM_X_IN := 0.06
const ARM_L := 0.155
const Y_ARM_LO := -0.047
const Y_ARM_UP := -0.0030000000000000027
const X_WHEEL := 0.215
const RIDE_Y_WHEEL := -0.025
const Z_FRONT := -0.21
const Z_REAR := 0.21
const TRAVEL_BUMP := 0.05
const TRAVEL_DROOP := 0.07
const STEER_MAX := deg_to_rad(30.0)
const SHOCK_DZ := 0.03
const SHOCK_LO_ARM := Vector2(0.05, 0.012)
const SHOCK_UP := Vector2(0.07, 0.125)
const SHOCK_CAP_UP := 0.012
const SHOCK_CAP_LO := 0.018
const SPRING_REST := 0.13492422502470644
const DIFF_OUT_X := 0.065
const CV_OFF := 0.022
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
