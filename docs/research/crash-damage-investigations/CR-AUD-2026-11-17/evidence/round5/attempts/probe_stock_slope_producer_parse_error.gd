## Scratch diagnostic: stock RC-track producer -> actual fixed-wing crash director.
##
## This does NOT step the simulation. Previous/candidate poses are prescribed,
## with a 6 m/s vertical translation consistent with one 1/240 s tick. The
## circuit, field and complete 26-point electric Stik hull are stock data. The
## script calls FlightSession._rc_track_hit() and forwards the returned snapshot
## unchanged to Director._start(). Its oracle computes slope-normal kinematics
## and effective mass from the witness and the constant live mass/inertia.
##
## A bounded search reports unresolved/missed candidates; it never fabricates an
## event. The desired slope-normal assertions are expected to fail on current
## main. Passing or failing this diagnostic does NOT establish an accepted flight
## tick, a physically validated structural failure, or lake-bank behavior.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const Director := preload("res://render/crash/director.gd")
const PresentationContext := preload("res://render/crash/presentation_context.gd")


class QuietWreck extends "res://render/crash/wreck.gd":
	var starts := 0
	func start(_pose: Transform3D, _velocity: Vector3, _angular_velocity: Vector3, _severity: Dictionary) -> void:
		starts += 1


class QuietEffects extends "res://render/crash/effects.gd":
	var starts := 0
	func start(_point: Vector3, _velocity: Vector3, _severity: Dictionary, _kerosene: float, _hot: bool, _wind: Vector3) -> void:
		starts += 1
	func apply_energy(_outcome: Dictionary) -> void:
		pass


var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, passed: bool, detail: String = "") -> void:
	checks += 1
	if not passed:
		failures += 1
	print("PROBE ", label, " ", "PASS" if passed else "FAIL", " ", detail)


func _body_state(north: float, east: float, up: float, speed_down: float) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([north, east, -up]), PackedFloat64Array([0.0, 0.0, speed_down]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))


## For identity attitude and vertical motion, find the highest CG altitude at
## which any actual stock hull point reaches composed ground. This only chooses
## input poses; the production query independently chooses the real crossing.
func _site_geometry(north: float, east: float, hull: PackedFloat64Array,
		track: Dictionary, surfaces: PackedFloat64Array) -> Dictionary:
	var raised_peak := -INF
	var all_peak := -INF
	var chosen := {}
	for i: int in hull.size() / 3:
		var arm := hull.slice(i * 3, i * 3 + 3)
		var point_n := north + arm[0]
		var point_e := east + arm[1]
		var base := GroundTerrain.sample_validated(point_n, point_e, surfaces)
		var overlay: Dictionary = Track.sample(track, point_n, point_e)
		var height := base[0] + float(overlay.height_m)
		var threshold := height + arm[2]
		all_peak = maxf(all_peak, threshold)
		if float(overlay.height_m) < Session.RC_RELIEF_MIN_M or height <= 0.0:
			continue
		if threshold > raised_peak:
			raised_peak = threshold
			chosen = {"index": i, "peak_up": threshold, "height": height,
				"relief": float(overlay.height_m), "dn": base[1] + float(overlay.dn),
				"de": base[2] + float(overlay.de), "point_north": point_n, "point_east": point_e}
	if not chosen.is_empty():
		chosen["all_peak"] = all_peak
	return chosen


func _dot3(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


## Independent LDL^T solve for w^T I^-1 w, avoiding the production
## EffectiveMass implementation and its explicit inverse. Inertia layout is
## [Ixx, Iyy, Izz, Ixy, Ixz, Iyz]. Positive pivots are required.
func _inverse_quadratic(inertia: PackedFloat64Array, w: PackedFloat64Array) -> float:
	if inertia.size() != 6 or w.size() != 3:
		return NAN
	var d0 := inertia[0]
	if not is_finite(d0) or d0 <= 0.0:
		return NAN
	var l10 := inertia[3] / d0
	var l20 := inertia[4] / d0
	var d1 := inertia[1] - l10 * l10 * d0
	if not is_finite(d1) or d1 <= 0.0:
		return NAN
	var l21 := (inertia[5] - l20 * l10 * d0) / d1
	var d2 := inertia[2] - l20 * l20 * d0 - l21 * l21 * d1
	if not is_finite(d2) or d2 <= 0.0:
		return NAN
	var y0 := w[0]
	var y1 := w[1] - l10 * y0
	var y2 := w[2] - l20 * y0 - l21 * y1
	return y0 * y0 / d0 + y1 * y1 / d1 + y2 * y2 / d2


func _run() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	var track_result: Dictionary = Track.load_default()
	_check("stock field and circuit load", field_result.get("ok", false) and track_result.get("ok", false))
	if not field_result.get("ok", false) or not track_result.get("ok", false):
		_finish(null, null, null, null, null)
		return
	var field: Dictionary = field_result.field
	var track: Dictionary = track_result.track
	var session := Session.new()
	session.input_enabled = false
	session.physics_enabled = false
	session.crash_auto_restart = false
	root.add_child(session)
	session.setup("res://data/aircraft/stik_electric_6s.json")
	var ready: bool = session.aircraft.get("ok", false) and session.sim != null
	_check("stock electric Stik model loads", ready)
	if not ready:
		_finish(session, null, null, null, null)
		return
	var installed: bool = session.set_field(field) and session.set_rc_track(track)
	_check("stock field and circuit are installed before the query", installed and not session.rc_track_context().is_empty())
	if not installed:
		_finish(session, null, null, null, null)
		return
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var properties: Dictionary = session.mass_properties()
	var constant_cg: PackedFloat64Array = properties.get("cg_body_m", PackedFloat64Array())
	var constant_model: bool = properties.get("ok", false) and not bool(properties.get("finite_fuel", true)) \
		and constant_cg.size() == 3 and _dot3(constant_cg, constant_cg) < 1.0e-20
	_check("complete stock hull and constant-mass CG are available", hull.size() == 78 and constant_model,
		"hull_points=%d finite_fuel=%s" % [hull.size() / 3, str(properties.get("finite_fuel"))])
	if hull.size() != 78 or not constant_model:
		_finish(session, null, null, null, null)
		return

	# These are near the authored outer bank. Scan a small fixed set so selection
	# follows the loaded, actual hull and field microrelief. Every query outcome is
	# counted. Discard a site if the independently selected witness is not clear at
	# the start or the returned production normal does not establish a real slope.
	var sites := [[45.0, 20.0], [44.5, 20.0], [45.5, 20.0], [46.0, 20.0], [46.5, 20.0]]
	var speed := 6.0
	var half_drop := speed * session.sim.dt() * 0.5
	var selected := {}
	var attempted := 0
	var refused := 0
	var missed := 0
	for site: Array in sites:
		var north: float = site[0]
		var east: float = site[1]
		var geometry := _site_geometry(north, east, hull, track, session.ground_surfaces)
		if geometry.is_empty() or float(geometry.all_peak) > float(geometry.peak_up) + half_drop \
				or sqrt(float(geometry.dn) ** 2 + float(geometry.de) ** 2) < 0.3:
			continue
		var before := _body_state(north, east, float(geometry.peak_up) + half_drop, speed)
		var candidate := _body_state(north, east, float(geometry.peak_up) - half_drop, speed)
		attempted += 1
		var found: Dictionary = session._rc_track_hit(before, candidate, 1)
		if not found.get("ok", false):
			refused += 1
			continue
		var event: Variant = found.get("impact")
		if event == null:
			missed += 1
			continue
		if not event.has_kinematics or event.normal_ned.size() != 3:
			continue
		if sqrt(event.normal_ned[0] ** 2 + event.normal_ned[1] ** 2) < 0.2:
			continue
		selected = {"site": site, "geometry": geometry, "before": before, "candidate": candidate,
			"hit": found, "impact": event}
		break
	print("SEARCH attempted=", attempted, " refused=", refused, " missed=", missed, " selected=", not selected.is_empty())
	_check("stock hull query produces a sloped RC-track witness", not selected.is_empty())
	if selected.is_empty():
		_finish(session, null, null, null, null)
		return

	var impact: Variant = selected.impact
	var norm: PackedFloat64Array = impact.normal_ned.duplicate()
	var point: PackedFloat64Array = impact.point_ned.duplicate()
	var velocity: PackedFloat64Array = impact.velocity_ned.duplicate()
	var arm: PackedFloat64Array = impact.body_point.duplicate()
	var index := int(impact.point_index)
	var overlay: Dictionary = Track.sample(track, point[0], point[1])
	var base := GroundTerrain.sample_validated(point[0], point[1], session.ground_surfaces)
	var normal_length := sqrt(_dot3(norm, norm))
	var terrain_gap := point[2] + base[0] + float(overlay.height_m)
	_check("witness carries producer contact, actual relief and non-flat unit normal", impact.trigger == "hull_contact"
		and impact.soft_rule.is_empty() and impact.crossing != null and impact.crossing.available
		and index >= 0 and index < hull.size() / 3 and arm == hull.slice(index * 3, index * 3 + 3)
		and float(overlay.height_m) >= Session.RC_RELIEF_MIN_M and absf(normal_length - 1.0) < 1.0e-9
		and absf(norm[2]) < 0.99 and terrain_gap >= -1.0e-8 and terrain_gap < 1.0e-5,
		"site=%s index=%d point=%s normal=%s relief=%.8f penetration=%.12f" % [str(selected.site), index,
		str(point), str(norm), float(overlay.height_m), terrain_gap])
	_check("prescribed endpoints are one tick apart at 6 m/s", absf(float(selected.candidate[RB.POS + 2])
		- float(selected.before[RB.POS + 2]) - speed * session.sim.dt()) < 1.0e-12
		and absf(float(velocity[2]) - speed) < 1.0e-12 and velocity[0] == 0.0 and velocity[1] == 0.0)
	var clear_before := _body_state(float(selected.site[0]), float(selected.site[1]), float(selected.geometry.peak_up) + 3.0, speed)
	var clear_after := _body_state(float(selected.site[0]), float(selected.site[1]), float(selected.geometry.peak_up) + 3.0 - speed * session.sim.dt(), speed)
	var clear: Dictionary = session._rc_track_hit(clear_before, clear_after, 1)
	_check("higher trajectory has no circuit contact", clear.get("ok", false) and clear.get("impact") == null)

	# The event was returned by the real _rc_track_hit and is passed through unchanged.
	var source := Node3D.new()
	var bindings := PresentationContext.ModelBindings.new()
	bindings.root = source
	bindings.empty = false
	var context := PresentationContext.new()
	context.session = session
	context.model_bindings = bindings
	context.field = field
	context.cg_model = Vector3.ZERO
	context.pose_provider = func() -> Dictionary:
		return {basis = Basis.IDENTITY, pos = Vector3(0.0, 2.0, 0.0)}
	context.wind_provider = func(_t: float) -> Vector3: return Vector3.ZERO
	var director := Director.new()
	director.context = context
	director._audio_enabled = false
	var wreck := QuietWreck.new()
	var effects := QuietEffects.new()
	director.wreck = wreck
	director.effects = effects
	session.crash = {impact = impact}
	director._start()
	var report: Dictionary = director.report.duplicate(true)
	_check("director consumes the returned snapshot without mutation", bool(report.get("valid", false))
		and wreck.starts == 1 and effects.starts == 1 and impact.normal_ned == norm
		and impact.point_ned == point and impact.velocity_ned == velocity)

	var closing := maxf(0.0, -_dot3(velocity, norm) / normal_length)
	var speed_sq := _dot3(velocity, velocity)
	var tangent := sqrt(maxf(0.0, speed_sq - closing * closing))
	var unit_n := PackedFloat64Array([norm[0] / normal_length, norm[1] / normal_length, norm[2] / normal_length])
	# Identity attitude and zero CG offset are enforced above.
	var w := PackedFloat64Array([arm[1] * unit_n[2] - arm[2] * unit_n[1],
		arm[2] * unit_n[0] - arm[0] * unit_n[2], arm[0] * unit_n[1] - arm[1] * unit_n[0]])
	var rotational := _inverse_quadratic(properties.inertia, w)
	var mass: float = float(properties.mass_kg)
	var normal_mass := 1.0 / (1.0 / mass + rotational) if is_finite(rotational) and rotational >= 0.0 else NAN
	var normal_energy := 0.5 * normal_mass * closing * closing
	var reported_closing := float(report.get("speed_mps", -1.0)) * sin(deg_to_rad(float(report.get("impact_angle_deg", -1.0))))
	var detail := "closing actual=%.9f expected=%.9f; tangent actual=%.9f expected=%.9f; m_eff actual=%.9f expected=%.9f; normal_j actual=%.9f expected=%.9f; class=%d" % [
		reported_closing, closing, float(report.get("tangential_speed_mps", -1.0)), tangent,
		float(report.get("effective_mass_kg", -1.0)), normal_mass,
		float(report.get("normal_energy_j", -1.0)), normal_energy, int(report.get("class", -1))]
	_check("oracle inertia factor and closing speed are finite", is_finite(normal_mass) and normal_mass > 0.0
		and normal_mass <= mass * (1.0 + 1.0e-10) and closing > 0.0, detail)
	# Desired behavior, not evidence for measured breakage or an accepted tick.
	_check("desired: report uses the actual sloped normal speed", absf(reported_closing - closing) < 1.0e-7, detail)
	_check("desired: report uses the actual sloped tangent speed", absf(float(report.get("tangential_speed_mps", -1.0)) - tangent) < 1.0e-7, detail)
	_check("desired: report uses effective mass along the actual normal", absf(float(report.get("effective_mass_kg", -1.0)) - normal_mass) < 1.0e-7, detail)
	_check("desired: report uses actual normal kinetic energy", absf(float(report.get("normal_energy_j", -1.0)) - normal_energy) < 1.0e-7, detail)
	_finish(session, director, wreck, effects, source)


func _finish(session: Node, director: Node, wreck: Node, effects: Node, source: Node) -> void:
	print("STOCK_SLOPE_PRODUCER_PROBE: %d checks, %d failed; direct producer and prescribed poses only" % [checks, failures])
	if director != null:
		director.set("wreck", null)
		director.set("effects", null)
	if wreck != null: wreck.free()
	if effects != null: effects.free()
	if director != null: director.free()
	if source != null: source.free()
	if session != null: session.free()
	quit(1 if failures > 0 else 0)
