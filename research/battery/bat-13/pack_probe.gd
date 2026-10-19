# BAT-13 software probe: Timber pack_ecm numbers for the evidence record (not physical validation).
# Airborne trimmed start, ISA, no pilot: full throttle for 2 s, idle 4 s, then a low pack at full throttle until the
# soft cut. Run from the repository root:
#   "$(app/get-godot.sh)" --headless --path app --script "$PWD/research/battery/bat-13/pack_probe.gd"
extends SceneTree

const Flight: Script = preload("res://sim/flight_session.gd")
const Catalog: Script = preload("res://app_state/aircraft_catalog.gd")
const AircraftData: Script = preload("res://physics/aircraft_data.gd")


func _row(label: String, p: Dictionary) -> void:
	print("%s t=%.2f s | V=%.3f V (OCV %.3f, polarization %.3f) | I=%.2f A | cell avg %.3f min %.3f V | T=%.2f K | used %.1f mAh | ESC %s limit %.3f | rpm %.0f" % [
		label, p.time_s, p.bus_voltage_v, p.ocv_v, p.polarization_v, p.pack_current_a, p.cell_voltage_avg_v,
		p.cell_voltage_min_v, p.temperature_k, p.consumed_charge_c / 3.6, p.esc_state, p.esc_limit, p.rpm])


func _initialize() -> void:
	var a: Node = Flight.new()
	a.setup(Catalog.data_for("turbo-lumber-evolution", "pack"), "turbo-lumber-evolution")
	a.input_enabled = false
	a.engine_running = true
	_row("start", a.electrical_state())
	a.sim.inputs[3] = 1.0
	for _i: int in 480:
		a.sim.step()
	_row("full 2 s", a.electrical_state())
	a.sim.inputs[3] = 0.0
	for _i: int in 960:
		a.sim.step()
	_row("idle 4 s", a.electrical_state())
	a.free()
	var data: Dictionary = AircraftData.load_file(Catalog.data_for("turbo-lumber-evolution", "pack")).duplicate(true)
	data.model.propulsion.battery.initial_soc = 0.15
	var low: Node = Flight.new()
	low.setup(Catalog.data_for("turbo-lumber-evolution", "pack"), "turbo-lumber-evolution", data)
	low.input_enabled = false
	low.engine_running = true
	low.sim.inputs[3] = 1.0
	_row("low start", low.electrical_state())
	var trip: float = -1.0
	for tick: int in 240 * 120:
		low.sim.step()
		var p: Dictionary = low.electrical_state()
		if trip < 0.0 and p.esc_state != "normal":
			trip = p.time_s
			_row("LVC sensed", p)
		if p.esc_state == "soft_cut" and p.esc_limit <= 0.5:
			_row("soft cut 50%", p)
			break
	low.free()
	quit(0)
