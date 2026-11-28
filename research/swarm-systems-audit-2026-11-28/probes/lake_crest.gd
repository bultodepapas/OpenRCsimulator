## Stock wave components. Prescribed rigid endpoint states; no running aircraft integrator.
extends SceneTree

const Lake := preload("res://physics/lake_surface.gd")
const Loader := preload("res://data/lake_loader.gd")
const Collision := preload("res://sim/lake_collision.gd")
const Aircraft := preload("res://physics/aircraft_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const DT := 1.0 / 240.0
const CREST_N := 106.64877984412676
const CREST_E := 128.02108157112164
const SPEED_N := -28.8
const SPEED_E := -49.883063257983665
const DOWN := 0.3951
var failures := 0
var checks := 0


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % [label, ok])


func _point(fraction: float, down: float) -> PackedFloat64Array:
	var elapsed := (fraction - 0.5) * DT
	return PackedFloat64Array([CREST_N + SPEED_N * elapsed, CREST_E + SPEED_E * elapsed, down])


func _initialize() -> void:
	var read: Dictionary = Loader.load_from()
	_check("stock lake admitted", read.ok)
	if not read.ok:
		quit(1)
		return
	var lake: Dictionary = read.lake
	var a := _point(0.0, DOWN)
	var m := _point(0.5, DOWN)
	var b := _point(1.0, DOWN)
	var clear0 := Lake.water_height_down(lake, a[0], a[1], 0.0) - DOWN
	var immersion := DOWN - Lake.water_height_down(lake, m[0], m[1], DT * 0.5)
	var clear1 := Lake.water_height_down(lake, b[0], b[1], DT) - DOWN
	print("endpoint_clearance_m=[%.12f,%.12f] midpoint_immersion_m=%.12f" % [clear0, clear1, immersion])
	_check("analytic signs, with margins well above tolerance", clear0 > 9.4e-5 and clear1 > 9.4e-5 and immersion > 9.99e-5)
	var steps := Lake._subdivision_count(lake, lake.waves, a, b, 0.0, DT, 0.0, 1.0, "water")
	_check("one interval", steps == 1)
	var full := Lake.sweep_probe(lake, a, b, 0.0, DT)
	var half := Lake.sweep_probe(lake, a, m, 0.0, DT * 0.5)
	print("full_hit=%s half_hit=%s first_entry_full_tick_fraction=%.12f" % [full.hit, half.hit, half.fraction * 0.5])
	_check("whole point sweep misses", full.ok and not full.hit)
	_check("first half detects real entry", half.ok and half.hit and half.material == "water" and half.fraction > 0.0 and half.fraction < 1.0)
	var clear := Lake.sweep_probe(lake, _point(0, 0.3949), _point(1, 0.3949), 0.0, DT)
	var wet := Lake.sweep_probe(lake, _point(0, 0.3953), _point(1, 0.3953), 0.0, DT)
	_check("clear throughout", clear.ok and not clear.hit)
	_check("wet at start", wet.ok and wet.hit and wet.fraction == 0.0)
	var yaw := atan2(SPEED_E, SPEED_N)
	var q := M.q_from_euler(yaw, 0.0, deg_to_rad(3.0))
	var vel := M.q_rotate(M.q_conj(q), M.v3(SPEED_N, SPEED_E, 0.0))
	var zero := M.v3(0, 0, 0)
	var inertia := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
	_check_collision(lake, M.v3(0, 0, 0), {}, 1.0, inertia, zero, q, vel, "point hull")
	var stock := Aircraft.load_file("res://data/aircraft/sebart_avanti_s_a200.json")
	_check("stock Avanti admitted", stock.ok)
	if stock.ok:
		var model: Dictionary = stock.model
		var lowest := M.v3(0, 0, -INF)
		var name := ""
		for i in range(0, model.crash_hull.size(), 3):
			var off := M.q_rotate(q, model.crash_hull.slice(i, i + 3))
			if off[2] > lowest[2]:
				lowest = off
				name = "hull %d" % (i / 3)
		for contact: Dictionary in model.landing_gear.contacts:
			var off := M.q_rotate(q, contact.position)
			if off[2] > lowest[2]:
				lowest = off
				name = str(contact.name)
		print("lowest Avanti point=%s offset_down_m=%.9f" % [name, lowest[2]])
		_check_collision(lake, model.crash_hull, model.landing_gear, model.mass_kg, model.inertia, lowest, q, vel, "Avanti hull and gear")
	print("R2_LAKE_CREST checks=%d failed=%d" % [checks, failures])
	quit(1 if failures else 0)


func _check_collision(lake: Dictionary, hull: PackedFloat64Array, gear: Dictionary, mass: float,
		inertia: PackedFloat64Array, offset: PackedFloat64Array, q: PackedFloat64Array, vel: PackedFloat64Array, label: String) -> void:
	var z := M.v3(0.0, 0.0, 0.0)
	var a := RB.make_state(M.sub(_point(0.0, DOWN), offset), vel, q, z)
	var m := RB.make_state(M.sub(_point(0.5, DOWN), offset), vel, q, z)
	var b := RB.make_state(M.sub(_point(1.0, DOWN), offset), vel, q, z)
	var full := Collision.first_hit(lake, a, b, hull, gear, 1, DT, mass, inertia)
	var half := Collision.first_hit(lake, a, m, hull, gear, 1, DT * 0.5, mass, inertia)
	_check(label + " whole collision query misses", full == null)
	_check(label + " half collision query selects terminal water", half != null and half.terminal and half.material == "water")
	if half != null:
		print("%s half selected=%s/%s first_entry_full_tick_fraction=%.12f" % [label, half.probe_kind, half.component_name, half.time_fraction * 0.5])
