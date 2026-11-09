extends SceneTree
const Data := preload("res://physics/aircraft_data.gd")
const Flight := preload("res://sim/flight_session.gd")
const PATH := "res://data/aircraft/battery/stik_electric_6s_pack.json"
func _initialize() -> void:
	var frozen: Dictionary = Data.load_file(PATH)
	frozen.model.propulsion.battery.initial_soc = 0.08
	var s := Flight.new()
	s.input_enabled = false
	s.setup(PATH, "stik-electric-6s", frozen)
	var failures := 0
	if not s.is_flyable():
		printerr("FAIL low-SOC session start ", s.start_error)
		failures += 1
	if s.is_flyable():
		s.engine_running = true
		var seen := false
		var cut_point := {}
		for i: int in 4800:
			s.sim.inputs[3] = 1.0
			s.sim.step()
			if not s.sim.fault_reason.is_empty(): break
			if i % 24 == 0:
				var p: Dictionary = s.electrical_state()
				if p.esc_state == "soft_cut":
					print("LOW_CUT tick=", i + 1, " soc=", p.soc, " bus_v=", p.bus_voltage_v, " limit=", p.esc_limit)
					cut_point = p
					seen = true
					break
		if not seen or not s.sim.fault_reason.is_empty() or cut_point.soc >= 0.08 or cut_point.effective_duty > cut_point.esc_limit:
			printerr("FAIL actual low-SOC cutoff: ", s.sim.fault_reason)
			failures += 1
		else:
			var recovered := false
			for i: int in 720:
				s.sim.inputs[3] = 0.0
				s.sim.step()
				if not s.sim.fault_reason.is_empty(): break
				if i % 24 == 0:
					var p: Dictionary = s.electrical_state()
					if p.esc_state == "normal" and p.esc_limit == 1.0:
						recovered = true
						print("LOW_RECOVERY ticks_after_cut=", i + 1, " sensed_v=", p.esc_sensed_voltage_v)
						break
			if not recovered or not s.sim.fault_reason.is_empty():
				printerr("FAIL actual low-SOC recovery: ", s.sim.fault_reason)
				failures += 1
	s.free()
	print("STIK_LOW_SOC_TEST failures=", failures)
	quit(1 if failures else 0)
