# Candidate regression probe, not run by the researcher.
# Compare a running glow source, a genuinely cut/coasting glow source and a
# stopped rotor, all through the same production session guard. The source-off
# rotating case asserts the documented E3d2 turning-disc behavior and is expected
# to fail on baseline a7de9b35676d891bc2034cc344b910d9e1ef9c61.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Hull := preload("res://physics/hull_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const AIRCRAFT := "res://data/aircraft/stik_glow_55ax_2t.json"

var checks := 0
var failures := 0

func check(label: String, ok: bool, detail := "") -> bool:
	checks += 1
	print(("ok   " if ok else "FAIL ") + label + " " + detail)
	if not ok:
		failures += 1
	return ok

func _initialize() -> void:
	_case("source on, spinning", true, false, true)
	_case("source cut, spinning", false, false, true)
	_case("source cut, stopped", false, true, false)
	print("PROBE spinning source-off ground strike: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _case(label: String, source_on: bool, stopped: bool, expect_strike: bool) -> void:
	var s := Flight.new()
	s.input_enabled = false
	s.soft_hull_contacts = true
	s.crash_auto_restart = false
	s.setup(AIRCRAFT)
	root.add_child(s)
	if not check(label + ": loaded glow flight", s.is_flyable() and s.glow_is_active() and s.engine_running):
		s.free()
		return
	s.sim.set_paused(false)
	if not source_on and not check(label + ": actual glow cut accepted", s.glow_cut() and not s.engine_running):
		s.free()
		return
	# Establish an accepted source-on or source-off spinning state in flight; a
	# disabled engine's positive RPM must be actual coupled-shaft state, not only
	# an inconsistent auxiliary mirror.
	var clear_depth: Dictionary = Hull.prop_disc_depth(s.sim.state, s._prop_disc)
	if not check(label + ": airborne disc before coast", float(clear_depth.depth) < 0.0):
		s.free()
		return
	var before_tick: int = s.sim.tick
	s.sim.step()
	if not check(label + ": airborne tick accepted while spinning", s.sim.tick == before_tick + 1 \
			and s.sim.fault_reason.is_empty() and s.sim.continuous[0] >= Hull.STRIKE_MIN_RPM \
			and s.sim.aux[Flight.AUX_RPM] == s.sim.continuous[0], s.sim.fault_reason):
		s.free()
		return
	if stopped:
		# A controlled stopped-rotor boundary; do not conflate this with the
		# independently established, genuinely spinning source-off case.
		s.sim.continuous[0] = 0.0
		s.sim.aux[Flight.AUX_RPM] = 0.0
	var body := RB.make_state(PackedFloat64Array([0.0, 0.0, -10.0]), \
		PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), \
		PackedFloat64Array([0.0, 0.0, 0.0]))
	var depth: Dictionary = Hull.prop_disc_depth(body, s._prop_disc)
	body[RB.POS + 2] += -float(depth.depth) + 0.001
	var placed: Dictionary = Hull.prop_disc_depth(body, s._prop_disc)
	if not check(label + ": disc-only intersection fixture", float(placed.depth) > 0.0 \
			and not s.gear_collapsed(body) and Hull.contacts(body, body, s._hull_contact).is_empty()):
		s.free()
		return
	if not check(label + ": intersection body accepted", s.sim.reset(body)):
		s.free()
		return
	s.sim.set_paused(false)
	var rpm: float = s.sim.aux[Flight.AUX_RPM]
	if not check(label + ": RPM and source mode preserved at guard", s.engine_running == source_on \
			and s.sim.continuous[0] == rpm \
			and (rpm == 0.0 if stopped else rpm >= Hull.STRIKE_MIN_RPM)):
		s.free()
		return
	s._physics_process(s.sim.dt())
	var struck: bool = not s.prop_strike.is_empty()
	print("OBSERVED ", label, " source_on=", source_on, " rpm=", rpm, \
		" depth=", placed.depth, " struck=", struck, " crash=", not s.crash.is_empty())
	check(label + ": documented strike result", struck == expect_strike \
		and s.crash.is_empty() and (not struck or not s.engine_running))
	s.free()
