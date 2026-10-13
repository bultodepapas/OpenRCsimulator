## Bounded timing probe for the legacy Stik and paired glow flight adapters.
## Research diagnostic only: host isolation is not guaranteed and no physical claim follows.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const GlowFlight := preload("res://physics/glow/flight.gd")
const Life := preload("res://physics/glow/lifecycle.gd")
const Source := preload("res://physics/glow/source.gd")
const Blade := preload("res://physics/glow/propeller.gd")
const Vibration := preload("res://physics/glow/vibration.gd")
const GlowVoice := preload("res://audio/glow_voice.gd")
const FuelMass := preload("res://physics/glow/fuel_mass.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const M := preload("res://physics/math3d.gd")

const STEP_TARGET_US := 500.0
const EXTENDED_PRECONDITION_TICKS := 120
const EXTENDED_MISFIRE_PRECONDITION_TICKS := 240
const EXTENDED_EVENT_COAST_TICKS := 600
const EXTENDED_PCM_BLOCK_FRAMES := 768
const EXTENDED_SCENARIOS := ["idle", "misfire", "high_load", "advancing_inflow", "fuel_exhaustion", "thermal_shutdown"]
const RELEASE_BINARY_RELATIVE := ".tools/rc7-proof/windows-smoke/OpenRC Simulator.exe"
const RELEASE_PACK_RELATIVE := ".tools/glow-package-20261013/nitro02-candidate.pck"
const CASES := [
	{"label": "legacy_stik", "path": "res://data/aircraft/jensen_ugly_stik_60.json", "input": "app/data/aircraft/jensen_ugly_stik_60.json", "glow": false},
	{"label": "glow_2t", "path": "res://data/aircraft/stik_glow_55ax_2t.json", "input": "app/data/aircraft/stik_glow_55ax_2t.json", "glow": true},
	{"label": "glow_4t", "path": "res://data/aircraft/stik_glow_fs64v_4t.json", "input": "app/data/aircraft/stik_glow_fs64v_4t.json", "glow": true},
]
const SOURCE_PATHS := [
	"research/glow-engines/performance_probe.gd",
	"research/glow-engines/release_probe_wrapper.gd",
	"research/glow-engines/release_probe_wrapper.tscn",
	"research/glow-engines/build_release_probe_project.py",
	"app/sim/flight_session.gd",
	"app/sim/simulation.gd",
	"app/physics/glow/flight.gd",
	"app/physics/glow/lifecycle.gd",
	"app/physics/glow/source.gd",
	"app/physics/glow/two_stroke.gd",
	"app/physics/glow/four_stroke.gd",
	"app/physics/glow/thermal.gd",
	"app/physics/glow/profile.gd",
	"app/physics/glow/propeller.gd",
	"app/physics/glow/vibration.gd",
	"app/audio/glow_voice.gd",
	"app/physics/glow/fuel_mass.gd",
	"app/physics/glow/installation.gd",
	"app/physics/dynamics.gd",
	"app/physics/math3d.gd",
	"app/physics/air_data.gd",
	"app/physics/aero.gd",
	"app/physics/propulsion.gd",
	"app/physics/rotor_coupling.gd",
	"app/physics/electric_battery_step.gd",
	"app/physics/rigid_body.gd",
	"app/physics/ground_contact.gd",
]
const INPUT_PATHS := [
	"app/data/aircraft/jensen_ugly_stik_60.json",
	"app/data/aircraft/stik_glow_55ax_2t.json",
	"app/data/aircraft/stik_glow_fs64v_4t.json",
	"app/data/glow/stik_55ax_2t.json",
	"app/data/glow/stik_fs64v_4t.json",
	"app/data/glow/os_max_55ax_candidate.json",
	"app/data/glow/os_fs_64v_candidate.json",
	"app/data/glow/profile_contract.json",
]

var hz: int = 240
var warmup_ticks: int = 120
var measured_ticks: int = 600
var micro_groups: int = 25
var output_path: String = ""
var runtime_pack_path: String = ""
var repository_root_override: String = ""
var runtime_mode: String = "standalone_script"
var extended_glow: bool = false
var extended_preflight_only: bool = false
var release_manifest: Dictionary = {}
var release_manifest_sha256: String = ""
var _probe_started: bool = false
var report: Dictionary = {}

# Fixed sampled context for microbenchmarks. Reusing this input state isolates each
# pure evaluator; it does not mutate the committed simulation state.
var _owner: Node
var _body: PackedFloat64Array
var _values: PackedFloat64Array
var _time_s: float
var _model: Dictionary
var _install: Dictionary
var _profile: Dictionary
var _state: Dictionary
var _deflections: Dictionary
var _rho: float
var _wind: PackedFloat64Array
var _ground_up: float
var _downwash: float = NAN
var _air: Dictionary
var _source_context: Dictionary
var _axial_speed: float
var _last_result: Variant
var _observer_flight: Node
var _observer_snapshot: Dictionary
var _observer_vibration_prepared: Dictionary
var _observer_voice: RefCounted


func _initialize() -> void:
	if _probe_started:
		return
	_probe_started = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="):
			hz = arg.trim_prefix("--hz=").to_int()
		elif arg.begins_with("--warmup="):
			warmup_ticks = arg.trim_prefix("--warmup=").to_int()
		elif arg.begins_with("--ticks="):
			measured_ticks = arg.trim_prefix("--ticks=").to_int()
		elif arg.begins_with("--micro-groups="):
			micro_groups = arg.trim_prefix("--micro-groups=").to_int()
		elif arg.begins_with("--out="):
			output_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--runtime-pack="):
			runtime_pack_path = arg.trim_prefix("--runtime-pack=")
		elif arg.begins_with("--repo-root="):
			repository_root_override = arg.trim_prefix("--repo-root=")
		elif arg.begins_with("--runtime-mode="):
			runtime_mode = arg.trim_prefix("--runtime-mode=")
		elif arg == "--extended-glow":
			extended_glow = true
		elif arg == "--extended-preflight":
			extended_preflight_only = true
			extended_glow = true
	if hz not in [120, 240, 480] or warmup_ticks < 0 or measured_ticks < 100 or micro_groups < 5:
		printerr("Invalid probe settings; use --hz=240 --warmup=120 --ticks=600 --micro-groups=25")
		quit(2)
		return
	Engine.physics_ticks_per_second = hz
	report = {
		"format": "openrc-glow-performance-probe v1",
		"purpose": "diagnostic interpreter timing; not a release qualification or physical validation",
		"godot": Engine.get_version_info(),
		"host": {
			"os": OS.get_name(),
			"processor": OS.get_processor_name(),
			"logical_processors": OS.get_processor_count(),
			"isolation": "best effort only; two long-lived Godot sessions were observed at preflight (repository climb-trim watch and unrelated Corruption app) and neither was stopped",
		},
		"runtime": {
			"probe_mode": runtime_mode,
			"binary_path": OS.get_executable_path(),
			"binary_sha256": _sha256_file(OS.get_executable_path()),
			"debug_feature": OS.has_feature("debug"),
			"release_feature": OS.has_feature("release"),
			"main_pack_path": "embedded in executable" if runtime_pack_path == "embedded" else runtime_pack_path,
			"main_pack_sha256": "embedded_in_executable; see binary_sha256" if runtime_pack_path == "embedded" else (_sha256_file(runtime_pack_path) if not runtime_pack_path.is_empty() else "not_supplied"),
		},
		"prior_release_override_attempt": {
			"binary_path": RELEASE_BINARY_RELATIVE,
			"binary_sha256": _sha256_file(_repo_path(RELEASE_BINARY_RELATIVE)),
			"pack_path": RELEASE_PACK_RELATIVE,
			"pack_sha256": _sha256_file(_repo_path(RELEASE_PACK_RELATIVE)),
			"feature_flags": "unavailable; external probe could not execute in release runtime",
			"probe_status": "blocked: --main-pack aborts because path overrides were disabled at Godot build time; --script alone did not execute the external probe",
			"observed_release_errors": [
				"--main-pack: Godot binary compiled without support for path overrides",
				"--script alone: release application parsed --warmup as its own option and required --frametimes",
			],
		},
		"started_at_local": Time.get_datetime_string_from_system(true, true),
		"hash_scope": String(release_manifest.get("hash_scope", "working_tree_at_probe_start")),
		"release_manifest_sha256": release_manifest_sha256 if not release_manifest_sha256.is_empty() else "not_embedded",
		"release_manifest_provenance": String(release_manifest.get("provenance", "Hashes read directly from repository files at probe start.")),
		"source_hashes": release_manifest.get("source_hashes", _hash_paths(SOURCE_PATHS)),
		"input_hashes": release_manifest.get("input_hashes", _hash_paths(INPUT_PATHS)),
		"build_configuration_hashes": release_manifest.get("build_configuration_hashes", {}),
		"propeller_inertia_basis": "Candidate propeller polar inertia follows the inventory's uniform-box surrogate geometry; engine crank polar inertia is inferred (2e-5 kg m2 for the 2T, 3e-5 kg m2 for the 4T). These are estimated mass distributions and inferred terms, with no matched propeller/crank inertia measurements.",
		"configuration": {
			"physics_hz": hz,
			"warmup_ticks": warmup_ticks,
			"measured_ticks_per_case": measured_ticks,
			"counterbalanced_rounds": 2,
			"microprofile_groups": micro_groups,
			"full_step_budget_us": STEP_TARGET_US,
			"step_timing": "Time.get_ticks_usec around each manual Simulation.step(); p50/p95/max of individual ticks",
			"micro_timing": "median/p95/max of batch mean per-call times; callable-dispatch no-op measured separately",
			"flight_state": "trimmed airborne steady scenario at each aircraft's default launch state; neutral controls",
		},
		"cases": [],
	}
	report["source_tree_sha256"] = String(release_manifest.get("source_tree_sha256", _combined_hash(report.source_hashes)))
	report["input_tree_sha256"] = String(release_manifest.get("input_tree_sha256", _combined_hash(report.input_hashes)))
	if extended_preflight_only:
		report["probe_mode"] = "extended_glow_non_timed_preflight"
		var preflight: Dictionary = _run_extended_glow(false)
		report["extended_glow_preflight"] = preflight
		if not preflight.get("ok", false):
			printerr("Extended glow preflight failed: ", preflight.get("message", "unknown"))
			_write_report()
			quit(1)
			return
		_write_report()
		print("EXTENDED_GLOW_PREFLIGHT scenarios=", preflight.scenarios.size(), " timing_collected=false")
		quit(0)
		return
	var ordered_cases: Array[Dictionary] = []
	for case: Dictionary in CASES:
		var first: Dictionary = case.duplicate(true)
		first["round"] = 1
		ordered_cases.append(first)
	for index in range(CASES.size() - 1, -1, -1):
		var second: Dictionary = CASES[index].duplicate(true)
		second["round"] = 2
		ordered_cases.append(second)
	for case: Dictionary in ordered_cases:
		var result: Dictionary = _measure_case(case)
		if not result.get("ok", false):
			printerr("Performance probe failed: ", case.label, " ", result.get("message", "unknown"))
			quit(1)
			return
		report.cases.append(result)
	report["summary"] = _aggregate_runs(report.cases)
	if extended_glow:
		var extended: Dictionary = _run_extended_glow(true)
		report["extended_glow"] = extended
		if not extended.get("ok", false):
			printerr("Extended glow diagnostics failed: ", extended.get("message", "unknown"))
			_write_report()
			quit(1)
			return
	if not _write_report():
		quit(3)
		return
	for spec: Dictionary in CASES:
		var result: Dictionary = report.summary[spec.label]
		print("SUMMARY ", spec.label, " rounds=", result.rounds,
			" step_p50_median_us=", result.median_of_round_step_p50_us,
			" step_p95_median_us=", result.median_of_round_step_p95_us,
			" step_p95_worst_us=", result.worst_round_step_p95_us,
			" ratio_to_500us=", result.median_of_round_step_p95_us / STEP_TARGET_US)
	if extended_glow:
		print("EXTENDED_GLOW scenarios=", report.extended_glow.scenarios.size(), " independent_of_500us_gate=true")
	quit(0)


func _write_report() -> bool:
	if output_path.is_empty():
		return true
	var output_file := FileAccess.open(output_path, FileAccess.WRITE)
	if output_file == null:
		printerr("Could not open report output: ", output_path)
		return false
	output_file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	output_file.close()
	print("Wrote performance report: ", output_path)
	return true


func _measure_case(spec: Dictionary) -> Dictionary:
	var flight := Session.new()
	flight.setup(String(spec.path))
	flight.input_enabled = false
	if not flight.is_flyable() or flight.sim == null:
		flight.free()
		return {"ok": false, "message": "aircraft did not reach a flyable setup"}
	for _tick in warmup_ticks:
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			var warm_fault: String = flight.sim.fault_reason
			flight.free()
			return {"ok": false, "message": "fault during warmup: " + warm_fault}
	var costs: Array[float] = []
	for _tick in measured_ticks:
		var started: int = Time.get_ticks_usec()
		flight.sim.step()
		costs.append(float(Time.get_ticks_usec() - started))
		if not flight.sim.fault_reason.is_empty():
			var fault: String = flight.sim.fault_reason
			flight.free()
			return {"ok": false, "message": "fault during measurement: " + fault}
	costs.sort()
	var step_stats := _stats(costs)
	var result: Dictionary = {
		"ok": true,
		"case": String(spec.label),
		"round": int(spec.round),
		"aircraft_id": String(flight.aircraft.model.id),
		"aircraft_input": String(spec.input),
		"aircraft_input_sha256": String(report.input_hashes.get(String(spec.input), "missing")),
		"glow_active": bool(flight.glow_is_active()),
		"shaft_integrator": flight.shaft_integrator(),
		"start_time_s": flight.sim.time() - float(measured_ticks) / float(hz),
		"step_cost_us": step_stats,
		"step_p95_to_500us_budget_ratio": step_stats.p95 / STEP_TARGET_US,
	}
	if bool(spec.glow):
		_context_from_flight(flight)
		result["microprofile"] = _microprofile_glow()
	else:
		_context_from_flight(flight)
		result["microprofile"] = {"dynamics_loads": _measure(Callable(self, "_micro_dynamics_loads"), 24)}
	flight.free()
	return result


func _run_extended_glow(collect_measurements: bool) -> Dictionary:
	var output: Dictionary = {
		"ok": true,
		"format": "openrc-glow-extended-diagnostics v1",
		"purpose": "Optional stateful regime and observer/audio diagnostics; results are excluded from the neutral summary and 500 us gate.",
		"gate_500us_applies": false,
		"mode": "timed_diagnostic" if collect_measurements else "non_timed_preflight",
		"measurements_collected": collect_measurements,
		"event_timing_resolution": "A stop reason is observed at the first accepted simulation tick; this report does not claim sub-tick event timestamps.",
		"configuration": {
			"scenario_ticks": measured_ticks if collect_measurements else 0,
			"event_coast_ticks": EXTENDED_EVENT_COAST_TICKS if collect_measurements else 0,
			"idle_precondition_ticks": EXTENDED_PRECONDITION_TICKS,
			"misfire_precondition_ticks": EXTENDED_MISFIRE_PRECONDITION_TICKS,
			"high_load_precondition_ticks": EXTENDED_PRECONDITION_TICKS,
			"pcm_block_frames": EXTENDED_PCM_BLOCK_FRAMES,
			"pcm_sample_rate_hz": int(GlowVoice.RATE),
			"pcm_block_duration_ms": 1000.0 * float(EXTENDED_PCM_BLOCK_FRAMES) / GlowVoice.RATE,
			"audio_scope": "GlowVoice.render_telemetry PCM synthesis only; excludes Soundscape, AudioStreamGeneratorPlayback, AudioServer, device and callback costs.",
			"preconditioning_costs_reported": false,
		},
		"observer_audio_source_hashes": {
			"app/physics/glow/vibration.gd": String(report.source_hashes.get("app/physics/glow/vibration.gd", "missing")),
			"app/audio/glow_voice.gd": String(report.source_hashes.get("app/audio/glow_voice.gd", "missing")),
		},
		"scenarios": [],
	}
	for family: String in ["glow_2t", "glow_4t"]:
		for scenario_name: String in EXTENDED_SCENARIOS:
			var result: Dictionary = _run_extended_scenario(family, scenario_name, collect_measurements)
			output.scenarios.append(result)
			if not result.get("ok", false):
				output.ok = false
				output.message = "%s.%s: %s" % [family, scenario_name, str(result.get("message", "scenario failed"))]
				return output
	return output


func _run_extended_scenario(family: String, scenario_name: String, collect_measurements: bool) -> Dictionary:
	var case_spec: Dictionary = {}
	for candidate: Dictionary in CASES:
		if bool(candidate.glow) and String(candidate.label) == family:
			case_spec = candidate
			break
	if case_spec.is_empty():
		return {"ok": false, "family": family, "scenario": scenario_name, "message": "No installed aircraft is mapped to this family"}
	var flight := Session.new()
	flight.setup(String(case_spec.path))
	flight.input_enabled = false
	if not flight.is_flyable() or flight.sim == null:
		flight.free()
		return {"ok": false, "family": family, "scenario": scenario_name, "message": "Aircraft did not reach a flyable setup"}
	var install: Dictionary = flight.aircraft.model.propulsion.glow
	var nominal_mixture: float = float(install.profile.operation.nominal_mixture)
	var throttle: float = float(flight.sim.inputs[3])
	var mixture_command: float = nominal_mixture
	var misfire_target_mixture: float = nominal_mixture
	match scenario_name:
		"idle":
			throttle = 0.0
		"misfire":
			throttle = 0.45
			var rich_start: float = float(install.settings.rich_misfire_start_ratio)
			var rich_zero: float = float(install.settings.rich_misfire_zero_ratio)
			misfire_target_mixture = nominal_mixture * 0.5 * (rich_start + rich_zero)
			mixture_command = misfire_target_mixture
		"high_load":
			throttle = 1.0
		"advancing_inflow":
			throttle = 0.55
		"fuel_exhaustion":
			throttle = 1.0
		"thermal_shutdown":
			throttle = 1.0
		_:
			flight.free()
			return {"ok": false, "family": family, "scenario": scenario_name, "message": "Unsupported extended scenario"}
	flight.sim.inputs[3] = throttle
	if not flight.glow_set_mixture(mixture_command):
		flight.free()
		return {"ok": false, "family": family, "scenario": scenario_name, "message": "Could not set the documented mixture command"}
	var synthetic_precondition: Dictionary = {"kind": "none", "state_override": {}}
	if scenario_name in ["fuel_exhaustion", "thermal_shutdown"]:
		var seeded: Dictionary = GlowFlight.unpack(flight.sim.continuous, install)
		if seeded.is_empty():
			flight.free()
			return {"ok": false, "family": family, "scenario": scenario_name, "message": "Could not read initial glow state for event fixture"}
		if scenario_name == "fuel_exhaustion":
			seeded.fuel_kg = 1.0e-9
			synthetic_precondition = {
				"kind": "seed_finite_tank_near_zero",
				"state_override": {"fuel_kg": 1.0e-9},
				"reason": "Exercise the installed finite-tank event boundary from a positive, valid inventory; the event is expected on the first accepted tick.",
			}
		else:
			var hot_zero: float = float(install.settings.temperature_firing_hot_zero_k)
			seeded.temperature_k = hot_zero + 5.0
			synthetic_precondition = {
				"kind": "seed_temperature_above_hot_zero",
				"state_override": {"temperature_k": hot_zero + 5.0},
				"hot_zero_temperature_k": hot_zero,
				"margin_k": 5.0,
				"reason": "Exercise the installed overheat stop with a valid running state above its declared hot-zero threshold; this is a synthetic boundary fixture, not an endurance trajectory.",
			}
		flight.sim.continuous = GlowFlight.put_state(flight.sim.continuous, seeded)
		if not flight.sim.reset(flight.sim.state.duplicate()):
			var reset_reason: String = flight.sim.fault_reason
			flight.free()
			return {"ok": false, "family": family, "scenario": scenario_name, "message": "Synthetic event state failed simulation reset: " + reset_reason}
	var before_preconditioning: Dictionary = flight.glow_state()
	if not before_preconditioning.get("ok", false):
		flight.free()
		return {"ok": false, "family": family, "scenario": scenario_name, "message": "Initial accepted telemetry is unavailable"}
	var initial_state_record: Dictionary = _extended_state_record(flight, before_preconditioning)
	var precondition_ticks: int = _extended_precondition_ticks(scenario_name)
	for _tick: int in range(precondition_ticks):
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			var precondition_fault: String = flight.sim.fault_reason
			flight.free()
			return {"ok": false, "family": family, "scenario": scenario_name, "message": "Fault during unmeasured preconditioning: " + precondition_fault}
	var sample: Dictionary = flight.glow_state()
	if not sample.get("ok", false):
		flight.free()
		return {"ok": false, "family": family, "scenario": scenario_name, "message": "Scenario telemetry is unavailable after preconditioning"}
	var baseline_opportunities: int = int(before_preconditioning.get("opportunity_count", 0))
	var baseline_fires: int = int(before_preconditioning.get("fire_count", 0))
	var verification: Dictionary = _verify_extended_scenario(scenario_name, flight, sample, baseline_opportunities, baseline_fires, synthetic_precondition)
	if not verification.get("ok", false):
		var verify_message: String = str(verification.get("message", "scenario precondition was not met"))
		flight.free()
		return {
			"ok": false,
			"family": family,
			"scenario": scenario_name,
			"message": verify_message,
			"verification": verification,
		}
	var output: Dictionary = {
		"ok": true,
		"family": family,
		"scenario": scenario_name,
		"aircraft_id": String(flight.aircraft.model.id),
		"aircraft_input": String(case_spec.input),
		"aircraft_input_sha256": String(report.input_hashes.get(String(case_spec.input), "missing")),
		"requested_controls": {"throttle": throttle, "mixture_command": mixture_command},
		"scenario_interpretation": "Airborne idle-command transition from the trimmed initial condition." if scenario_name == "idle" else "Synthetic rich-mixture command derived from the installed partial-misfire interval." if scenario_name == "misfire" else "",
		"synthetic_precondition": synthetic_precondition,
		"preconditioning": {
			"steps": precondition_ticks,
			"measured": false,
			"fault_free": true,
			"initial_state": initial_state_record,
		},
		"verification": verification,
		"sampling_state_before_measurement": _extended_state_record(flight, sample),
		"measurements_collected": collect_measurements,
	}
	if collect_measurements:
		var observer_audio: Dictionary = _measure_extended_observer_audio(flight, sample)
		if not observer_audio.get("ok", false):
			var observer_message: String = str(observer_audio.get("message", "observer/audio profile failed"))
			flight.free()
			return {"ok": false, "family": family, "scenario": scenario_name, "message": observer_message}
		output["observer_audio"] = observer_audio
		if scenario_name in ["fuel_exhaustion", "thermal_shutdown"]:
			var event_started: int = Time.get_ticks_usec()
			flight.sim.step()
			var event_cost_us: float = float(Time.get_ticks_usec() - event_started)
			if not flight.sim.fault_reason.is_empty():
				var event_fault: String = flight.sim.fault_reason
				flight.free()
				return {"ok": false, "family": family, "scenario": scenario_name, "message": "Fault on event tick: " + event_fault}
			var event_state: Dictionary = flight.glow_state()
			var expected_reason: String = "fuel_exhausted" if scenario_name == "fuel_exhaustion" else "overheat"
			if not event_state.get("ok", false) or String(event_state.get("stop_reason", "")) != expected_reason:
				var event_reason: String = String(event_state.get("stop_reason", "unavailable")) if event_state.get("ok", false) else "telemetry_failed"
				flight.free()
				return {"ok": false, "family": family, "scenario": scenario_name,
					"message": "Expected %s event on first accepted tick; observed %s" % [expected_reason, event_reason]}
			output["event_tick"] = {
				"cost_us": event_cost_us,
				"tick_before": flight.sim.tick - 1,
				"tick_after": flight.sim.tick,
				"accepted_stop_reason": expected_reason,
				"event_state": _extended_state_record(flight, event_state),
				"detection": "Accepted telemetry stop_reason after the first simulation step.",
			}
			var coast: Dictionary = _measure_extended_step_batch(flight, EXTENDED_EVENT_COAST_TICKS)
			if not coast.get("ok", false):
				var coast_message: String = str(coast.get("message", "post-event coast measurement failed"))
				flight.free()
				return {"ok": false, "family": family, "scenario": scenario_name, "message": coast_message}
			output["post_event_coast"] = coast
			var coast_telemetry: Dictionary = flight.glow_state()
			if not coast_telemetry.get("ok", false):
				flight.free()
				return {"ok": false, "family": family, "scenario": scenario_name, "message": "Post-event coast telemetry is unavailable"}
			output["after_measurement_state"] = _extended_state_record(flight, coast_telemetry)
		else:
			var steps: Dictionary = _measure_extended_step_batch(flight, measured_ticks)
			if not steps.get("ok", false):
				var step_message: String = str(steps.get("message", "scenario measurement failed"))
				flight.free()
				return {"ok": false, "family": family, "scenario": scenario_name, "message": step_message}
			output["step_cost_us"] = steps.step_cost_us
			output["measured_ticks"] = measured_ticks
			var after: Dictionary = flight.glow_state()
			if not after.get("ok", false):
				flight.free()
				return {"ok": false, "family": family, "scenario": scenario_name, "message": "Final telemetry is unavailable"}
			output["after_measurement_state"] = _extended_state_record(flight, after)
	else:
		var observer_validation: Dictionary = _validate_extended_observer_audio(flight, sample)
		if not observer_validation.get("ok", false):
			var observer_validation_message: String = str(observer_validation.get("message", "observer/audio preflight failed"))
			flight.free()
			return {"ok": false, "family": family, "scenario": scenario_name, "message": observer_validation_message}
		output["observer_audio_validation"] = observer_validation
		if scenario_name in ["fuel_exhaustion", "thermal_shutdown"]:
			flight.sim.step()
			if not flight.sim.fault_reason.is_empty():
				var event_fault: String = flight.sim.fault_reason
				flight.free()
				return {"ok": false, "family": family, "scenario": scenario_name, "message": "Fault during untimed event validation: " + event_fault}
			var event_state: Dictionary = flight.glow_state()
			var expected_reason: String = "fuel_exhausted" if scenario_name == "fuel_exhaustion" else "overheat"
			if not event_state.get("ok", false) or String(event_state.get("stop_reason", "")) != expected_reason:
				var event_reason: String = String(event_state.get("stop_reason", "unavailable")) if event_state.get("ok", false) else "telemetry_failed"
				flight.free()
				return {"ok": false, "family": family, "scenario": scenario_name,
					"message": "Untimed preflight expected %s event; observed %s" % [expected_reason, event_reason]}
			output["event_validation"] = {
				"accepted_stop_reason": expected_reason,
				"tick_after": flight.sim.tick,
				"event_state": _extended_state_record(flight, event_state),
				"timing_collected": false,
			}
			var coast_validation: Dictionary = _advance_extended_untimed(flight, EXTENDED_EVENT_COAST_TICKS)
			if not coast_validation.get("ok", false):
				var coast_message: String = str(coast_validation.get("message", "untimed post-event validation failed"))
				flight.free()
				return {"ok": false, "family": family, "scenario": scenario_name, "message": coast_message}
			var coast_state: Dictionary = flight.glow_state()
			if not coast_state.get("ok", false) or String(coast_state.get("stop_reason", "")) != expected_reason:
				flight.free()
				return {"ok": false, "family": family, "scenario": scenario_name,
					"message": "Stop reason did not persist through the untimed coast validation"}
			output["trajectory_validation"] = {
				"post_event_coast_ticks": EXTENDED_EVENT_COAST_TICKS,
				"timing_collected": false,
				"fault_free": true,
				"end_state": _extended_state_record(flight, coast_state),
			}
		else:
			var trajectory_validation: Dictionary = _advance_extended_untimed(flight, measured_ticks)
			if not trajectory_validation.get("ok", false):
				var trajectory_message: String = str(trajectory_validation.get("message", "untimed scenario validation failed"))
				flight.free()
				return {"ok": false, "family": family, "scenario": scenario_name, "message": trajectory_message}
			var trajectory_state: Dictionary = flight.glow_state()
			if not trajectory_state.get("ok", false):
				flight.free()
				return {"ok": false, "family": family, "scenario": scenario_name, "message": "Final untimed trajectory telemetry is unavailable"}
			output["trajectory_validation"] = {
				"ticks": measured_ticks,
				"timing_collected": false,
				"fault_free": true,
				"end_state": _extended_state_record(flight, trajectory_state),
			}
	output["fault_free"] = flight.sim.fault_reason.is_empty()
	if collect_measurements:
		output["sampling_state_before_measurement"]["observer_audio_label"] = "state at the start of the separately measured observer/audio calls"
	flight.free()
	return output


func _extended_precondition_ticks(scenario_name: String) -> int:
	match scenario_name:
		"idle", "high_load":
			return EXTENDED_PRECONDITION_TICKS
		"misfire":
			return EXTENDED_MISFIRE_PRECONDITION_TICKS
		_:
			return 0


func _verify_extended_scenario(scenario_name: String, flight: Node, sample: Dictionary,
		baseline_opportunities: int, baseline_fires: int, synthetic_precondition: Dictionary) -> Dictionary:
	var state_record: Dictionary = _extended_state_record(flight, sample)
	var passed: bool = false
	var predicate: String = ""
	var reason: String = ""
	match scenario_name:
		"idle":
			predicate = "airborne start receives throttle input 0 for the configured preconditioning window; engine remains running or reports modeled idle stall; no simulation fault"
			passed = float(state_record.throttle) == 0.0 and (bool(state_record.running) or String(state_record.stop_reason) == "stall")
		"misfire":
			var scenario_opportunity_delta: int = int(state_record.opportunity_count) - baseline_opportunities
			var scenario_fire_delta: int = int(state_record.fire_count) - baseline_fires
			var scenario_missed_delta: int = scenario_opportunity_delta - scenario_fire_delta
			var install: Dictionary = flight.aircraft.model.propulsion.glow
			var relative_target: float = float(install.profile.operation.nominal_mixture) * 0.5 * (
				float(install.settings.rich_misfire_start_ratio) + float(install.settings.rich_misfire_zero_ratio))
			predicate = "configured rich-mixture command lies between declared misfire thresholds; engine remains running with both successful and missed opportunities during preconditioning"
			passed = bool(state_record.running) \
				and is_equal_approx(float(state_record.mixture_command), relative_target) \
				and float(state_record.firing_fraction) > 0.0 and float(state_record.firing_fraction) < 1.0 \
				and scenario_opportunity_delta > 0 and scenario_fire_delta > 0 and scenario_missed_delta > 0
		"high_load":
			predicate = "wide-open throttle servo reaches at least 0.95, propeller resisting torque is positive, and the engine remains running"
			passed = float(state_record.throttle) == 1.0 and float(state_record.servo_fraction) >= 0.95 \
				and float(state_record.propeller_torque_nm) > 0.0 and bool(state_record.running)
		"advancing_inflow":
			predicate = "trimmed airborne start has positive axial hub-relative inflow above 1 m/s and the engine remains running"
			passed = float(state_record.hub_axial_inflow_m_s) > 1.0 and bool(state_record.running)
		"fuel_exhaustion":
			predicate = "running engine has a positive 1e-9 kg residual tank immediately before the accepted exhaustion event"
			passed = bool(state_record.running) and float(state_record.fuel_kg) == 1.0e-9
		"thermal_shutdown":
			var hot_zero: float = float(synthetic_precondition.get("hot_zero_temperature_k", NAN))
			predicate = "running engine is seeded at declared hot-zero plus 5 K immediately before the accepted overheat event"
			passed = bool(state_record.running) and is_finite(hot_zero) and float(state_record.temperature_k) == hot_zero + 5.0
	if not flight.sim.fault_reason.is_empty():
		passed = false
		reason = "simulation fault: " + flight.sim.fault_reason
	elif not passed:
		reason = "declared scenario verification predicate was not met"
	var opportunity_delta: int = int(state_record.opportunity_count) - baseline_opportunities
	var fire_delta: int = int(state_record.fire_count) - baseline_fires if scenario_name == "misfire" else 0
	return {"ok": passed, "predicate": predicate, "message": reason,
		"observed_state": state_record,
		"opportunity_delta": opportunity_delta,
		"fire_delta": fire_delta,
		"missed_opportunity_delta": opportunity_delta - fire_delta if scenario_name == "misfire" else 0}


func _extended_state_record(flight: Node, telemetry: Dictionary) -> Dictionary:
	var sim_state: PackedFloat64Array = flight.sim.state
	var velocity := [sim_state[3], sim_state[4], sim_state[5]]
	var record: Dictionary = {
		"rpm": float(telemetry.get("rpm", NAN)),
		"fuel_kg": float(telemetry.get("fuel_kg", NAN)),
		"temperature_k": float(telemetry.get("temperature_k", NAN)),
		"servo_fraction": float(telemetry.get("servo_fraction", NAN)),
		"air_fraction": float(telemetry.get("air_fraction", NAN)),
		"fuel_transport_kg_s": float(telemetry.get("fuel_transport_kg_s", NAN)),
		"phase_revolutions": float(telemetry.get("phase_revolutions", NAN)),
		"opportunity_count": int(telemetry.get("opportunity_count", 0)),
		"fire_count": int(telemetry.get("fire_count", 0)),
		"firing_accumulator": float(telemetry.get("firing_accumulator", NAN)),
		"running": bool(telemetry.get("running", false)),
		"stop_reason": String(telemetry.get("stop_reason", "")),
		"firing_fraction": float(telemetry.get("firing_fraction", NAN)),
		"actual_mixture": float(telemetry.get("actual_mixture", NAN)),
		"mixture_command": float(telemetry.get("mixture_command", flight.sim.continuous[12])),
		"throttle": float(flight.sim.inputs[3]),
		"body_velocity_m_s": velocity,
		"tick": int(flight.sim.tick),
	}
	var hub_air_value: Variant = telemetry.get("hub_air_velocity_body_m_s", PackedFloat64Array())
	var propeller_torque_nm: float = NAN
	if hub_air_value is PackedFloat64Array and hub_air_value.size() == 3:
		var axis: PackedFloat64Array = flight.aircraft.model.propulsion.axis
		record["hub_axial_inflow_m_s"] = M.dot(hub_air_value, axis)
		var propeller: Dictionary = flight.aircraft.model.propulsion.glow.propeller
		var load: Dictionary = Blade.evaluate(float(telemetry.get("rpm", 0.0)),
			float(record["hub_axial_inflow_m_s"]), flight.air_density(), propeller)
		if load.get("ok", false):
			propeller_torque_nm = float(load.get("torque_nm", NAN))
	else:
		record["hub_axial_inflow_m_s"] = NAN
	record["propeller_torque_nm"] = propeller_torque_nm
	var vibration_value: Variant = telemetry.get("source_vibration", {})
	if vibration_value is Dictionary:
		record["source_vibration"] = {
			"ok": bool(vibration_value.get("ok", false)),
			"order_1x_force_peak_n": float(vibration_value.get("order_1x_force_peak_n", 0.0)),
			"order_2x_force_peak_n": float(vibration_value.get("order_2x_force_peak_n", 0.0)),
			"constant_speed_assumption": bool(vibration_value.get("constant_speed_assumption", false)),
		}
	return record


func _measure_extended_observer_audio(flight: Node, sample: Dictionary) -> Dictionary:
	if not sample.get("ok", false):
		return {"ok": false, "message": "Observer/audio measurement needs valid accepted telemetry"}
	var install: Dictionary = flight.aircraft.model.propulsion.glow
	var prepared: Dictionary = Vibration.prepare(install.profile)
	if not prepared.get("ok", false):
		return {"ok": false, "message": "Could not prepare the source-vibration observer"}
	_observer_flight = flight
	_observer_snapshot = sample.duplicate(true)
	_observer_snapshot["max_rpm"] = float(install.profile.operation.max_rpm)
	_observer_snapshot["firing_fraction"] = float(sample.get("firing_fraction", 0.0)) if bool(sample.get("running", false)) else 0.0
	_observer_vibration_prepared = prepared
	_observer_voice = GlowVoice.new()
	_observer_voice.reset(float(sample.get("rpm", 0.0)), float(install.profile.operation.max_rpm))
	var observer_timing: Dictionary = _measure(Callable(self, "_micro_session_glow_state"), 4)
	if not _last_result is Dictionary or not _last_result.get("ok", false):
		_clear_extended_observer_context()
		return {"ok": false, "message": "FlightSession glow telemetry failed during observer profiling"}
	var vibration_timing: Dictionary = _measure(Callable(self, "_micro_vibration_observer"), 64)
	if not _last_result is Dictionary or not _last_result.get("ok", false):
		_clear_extended_observer_context()
		return {"ok": false, "message": "Vibration evaluator failed during observer profiling"}
	var audio_timing: Dictionary = _measure(Callable(self, "_micro_glow_voice_pcm"), 1)
	if not _last_result is PackedVector2Array or _last_result.size() != EXTENDED_PCM_BLOCK_FRAMES:
		_clear_extended_observer_context()
		return {"ok": false, "message": "GlowVoice did not produce the declared PCM block"}
	var output: Dictionary = {
		"ok": true,
		"sampling_state": _extended_state_record(flight, sample),
		"source_vibration_evaluate": {"timing_us_per_call": vibration_timing, "method": "prepared Vibration.evaluate at fixed accepted-state phase, RPM, firing fraction and alpha=0"},
		"flight_session_glow_state": {"timing_us_per_call": observer_timing, "method": "FlightSession.glow_state including pure GlowFlight telemetry and source-vibration observer"},
		"glow_voice_pcm_render": {"timing_us_per_block": audio_timing, "frames": EXTENDED_PCM_BLOCK_FRAMES,
			"sample_rate_hz": int(GlowVoice.RATE), "block_duration_ms": 1000.0 * float(EXTENDED_PCM_BLOCK_FRAMES) / GlowVoice.RATE,
			"method": "Stateful GlowVoice.render_telemetry over one reusable voice instance; PCM synthesis only, no AudioStreamGeneratorPlayback or AudioServer callback."},
		"timing_note": "Callable group means include dispatch and output construction; no dispatch subtraction is applied to this supplementary profile.",
	}
	_clear_extended_observer_context()
	return output


func _validate_extended_observer_audio(flight: Node, sample: Dictionary) -> Dictionary:
	if not sample.get("ok", false):
		return {"ok": false, "message": "Untimed observer/audio validation needs accepted telemetry"}
	var install: Dictionary = flight.aircraft.model.propulsion.glow
	var prepared: Dictionary = Vibration.prepare(install.profile)
	if not prepared.get("ok", false):
		return {"ok": false, "message": "Untimed validation could not prepare source vibration"}
	var firing_fraction: float = float(sample.get("firing_fraction", 0.0)) if bool(sample.get("running", false)) else 0.0
	var source_vibration: Dictionary = Vibration.evaluate(prepared,
		float(sample.get("phase_revolutions", 0.0)) * TAU,
		float(sample.get("rpm", 0.0)) * TAU / 60.0,
		0.0, firing_fraction)
	if not source_vibration.get("ok", false):
		return {"ok": false, "message": "Untimed source-vibration observer evaluation failed"}
	if source_vibration != sample.get("source_vibration", {}):
		return {"ok": false, "message": "Untimed source-vibration observer result does not match accepted telemetry"}
	var voice: GlowVoice = GlowVoice.new()
	voice.reset(float(sample.get("rpm", 0.0)), float(install.profile.operation.max_rpm))
	var telemetry: Dictionary = sample.duplicate(true)
	telemetry["max_rpm"] = float(install.profile.operation.max_rpm)
	var pcm: PackedVector2Array = voice.render_telemetry(telemetry, EXTENDED_PCM_BLOCK_FRAMES)
	if pcm.size() != EXTENDED_PCM_BLOCK_FRAMES:
		return {"ok": false, "message": "Untimed GlowVoice validation returned a malformed PCM block"}
	var peak: float = 0.0
	for frame: Vector2 in pcm:
		if not is_finite(frame.x) or not is_finite(frame.y) or absf(frame.x) > 0.98 or absf(frame.y) > 0.98:
			return {"ok": false, "message": "Untimed GlowVoice validation found a nonfinite or out-of-range PCM sample"}
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return {
		"ok": true,
		"timing_collected": false,
		"prepared_source_vibration_ok": true,
		"prepared_source_vibration_matches_telemetry": true,
		"pcm_frame_count": pcm.size(),
		"pcm_all_finite_and_bounded": true,
		"peak_pcm_abs": peak,
		"scope": "Functional call validation only; no wall-clock values collected and no audio device callback exercised.",
	}


func _clear_extended_observer_context() -> void:
	_observer_flight = null
	_observer_snapshot = {}
	_observer_vibration_prepared = {}
	_observer_voice = null


func _micro_session_glow_state() -> Dictionary:
	return _observer_flight.glow_state()


func _micro_vibration_observer() -> Dictionary:
	return Vibration.evaluate(_observer_vibration_prepared,
		float(_observer_snapshot.get("phase_revolutions", 0.0)) * TAU,
		float(_observer_snapshot.get("rpm", 0.0)) * TAU / 60.0,
		0.0, float(_observer_snapshot.get("firing_fraction", 0.0)))


func _micro_glow_voice_pcm() -> PackedVector2Array:
	return _observer_voice.render_telemetry(_observer_snapshot, EXTENDED_PCM_BLOCK_FRAMES)


func _measure_extended_step_batch(flight: Node, tick_count: int) -> Dictionary:
	var costs: Array[float] = []
	for _tick: int in range(tick_count):
		var started: int = Time.get_ticks_usec()
		flight.sim.step()
		costs.append(float(Time.get_ticks_usec() - started))
		if not flight.sim.fault_reason.is_empty():
			return {"ok": false, "message": "Fault during measured scenario ticks: " + flight.sim.fault_reason}
	costs.sort()
	return {"ok": true, "ticks": tick_count, "step_cost_us": _stats(costs),
		"timing_scope": "Supplementary scenario-specific per-tick Simulation.step latency; excluded from the neutral 500 us gate."}


func _advance_extended_untimed(flight: Node, tick_count: int) -> Dictionary:
	for _tick: int in range(tick_count):
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			return {"ok": false, "message": "Fault during untimed scenario validation: " + flight.sim.fault_reason}
	return {"ok": true, "ticks": tick_count, "timing_collected": false}


func _context_from_flight(flight: Node) -> void:
	_owner = flight
	_body = flight.sim.state.duplicate()
	_values = flight.sim.continuous.duplicate()
	_time_s = flight.sim.time()
	_model = flight.aircraft.model
	_rho = flight.air_density()
	_wind = flight.wind_at(_time_s)
	_deflections = flight._deflections(flight.sim.aux)
	_ground_up = flight._ground_up(_body)
	var lag_index: int = flight.downwash_index()
	_downwash = flight.sim.aux[lag_index] if lag_index >= 0 else NAN
	_air = flight.air_data(_body, _time_s)
	_install = _model.propulsion.get("glow", {})
	if _install.is_empty():
		_profile = {}
		_state = {}
		_source_context = {}
		_axial_speed = 0.0
	else:
		_profile = _install.profile
		_state = GlowFlight.unpack(_values, _install)
		_source_context = {
			"rpm": maxf(0.0, _values[0]),
			"admission": float(_values[4]),
			"mixture": float(_values[12]),
			"density": 1.225 * float(flight.engine_charge_ratio()),
			"running": bool(flight.engine_running),
		}
		_axial_speed = M.dot(_air.v_air, _model.propulsion.axis)


func _microprofile_glow() -> Dictionary:
	var tests: Array[Dictionary] = [
		{"name": "flight_evaluate", "method": "_micro_flight_evaluate", "calls_per_group": 4},
		{"name": "flight_point", "method": "_micro_flight_point", "calls_per_group": 12},
		{"name": "lifecycle_evaluate", "method": "_micro_lifecycle_evaluate", "calls_per_group": 24},
		{"name": "source_evaluate", "method": "_micro_source_evaluate", "calls_per_group": 48},
		{"name": "blade_evaluate", "method": "_micro_blade_evaluate", "calls_per_group": 96},
		{"name": "fuel_mass_evaluate", "method": "_micro_fuel_mass_evaluate", "calls_per_group": 48},
		{"name": "dynamics_loads", "method": "_micro_dynamics_loads", "calls_per_group": 24},
	]
	var noop := _measure(Callable(self, "_micro_noop"), 96)
	var output: Dictionary = {"callable_dispatch_noop": noop, "results": {}}
	for test: Dictionary in tests:
		var gross: Dictionary = _measure(Callable(self, String(test.method)), int(test.calls_per_group))
		gross["median_kernel_estimate_us"] = maxf(0.0, gross.p50 - noop.p50)
		gross["dispatch_adjustment_note"] = "gross minus the measured no-op callable median; approximate only"
		output.results[test.name] = gross
	return output


func _measure(callback: Callable, calls_per_group: int) -> Dictionary:
	for _warm in 5:
		callback.call()
	var group_means: Array[float] = []
	for _group in micro_groups:
		var started: int = Time.get_ticks_usec()
		for _call in calls_per_group:
			_last_result = callback.call()
		var elapsed: float = float(Time.get_ticks_usec() - started)
		group_means.append(elapsed / float(calls_per_group))
	group_means.sort()
	var stats := _stats(group_means)
	stats["calls_per_group"] = calls_per_group
	stats["groups"] = micro_groups
	return stats


func _stats(sorted_values: Array[float]) -> Dictionary:
	var n: int = sorted_values.size()
	return {
		"p50": sorted_values[int(floor(float(n - 1) * 0.50))],
		"p95": sorted_values[int(floor(float(n - 1) * 0.95))],
		"maximum": sorted_values[n - 1],
	}


func _aggregate_runs(runs: Array) -> Dictionary:
	var output: Dictionary = {}
	for spec: Dictionary in CASES:
		var matching: Array[Dictionary] = []
		for run: Dictionary in runs:
			if run.case == spec.label:
				matching.append(run)
		var p50s: Array[float] = []
		var p95s: Array[float] = []
		for run: Dictionary in matching:
			p50s.append(float(run.step_cost_us.p50))
			p95s.append(float(run.step_cost_us.p95))
		p50s.sort()
		p95s.sort()
		var summary: Dictionary = {
			"rounds": matching.size(),
			"median_of_round_step_p50_us": _median(p50s),
			"median_of_round_step_p95_us": _median(p95s),
			"worst_round_step_p95_us": p95s[-1],
			"round_step_p95_us": p95s,
		}
		if bool(spec.glow):
			var micro_names: Array[String] = ["flight_evaluate", "flight_point", "lifecycle_evaluate", "source_evaluate", "blade_evaluate", "fuel_mass_evaluate", "dynamics_loads"]
			var micro_summary: Dictionary = {}
			for name: String in micro_names:
				var values: Array[float] = []
				for run: Dictionary in matching:
					values.append(float(run.microprofile.results[name].p50))
				values.sort()
				micro_summary[name] = {"median_of_round_us_per_call": _median(values), "round_p50_us_per_call": values}
			summary["microprofile"] = micro_summary
		else:
			var dynamics: Array[float] = []
			for run: Dictionary in matching:
				dynamics.append(float(run.microprofile.dynamics_loads.p50))
			dynamics.sort()
			summary["microprofile"] = {"dynamics_loads": {"median_of_round_us_per_call": _median(dynamics), "round_p50_us_per_call": dynamics}}
		output[spec.label] = summary
	return output


func _median(sorted_values: Array[float]) -> float:
	var n: int = sorted_values.size()
	if n % 2 == 1:
		return sorted_values[n / 2]
	return 0.5 * (sorted_values[n / 2 - 1] + sorted_values[n / 2])


func _hash_paths(paths: Array) -> Dictionary:
	var output: Dictionary = {}
	for relative_path: String in paths:
		output[relative_path] = _sha256_file(_repo_path(relative_path))
	return output


func _repo_path(relative_path: String) -> String:
	var root: String = repository_root_override
	if root.is_empty():
		root = ProjectSettings.globalize_path("res://..").simplify_path()
	return root.path_join(relative_path)


func _sha256_file(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return "missing_or_empty"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "unreadable"
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while not file.eof_reached():
		var bytes: PackedByteArray = file.get_buffer(1048576)
		if not bytes.is_empty():
			context.update(bytes)
	file.close()
	return context.finish().hex_encode()


func _combined_hash(hashes: Dictionary) -> String:
	var paths: Array = hashes.keys()
	paths.sort()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path: String in paths:
		context.update(path.to_utf8_buffer())
		context.update(PackedByteArray([0]))
		context.update(String(hashes[path]).to_utf8_buffer())
		context.update(PackedByteArray([0]))
	return context.finish().hex_encode()


func _micro_noop() -> bool:
	return true


func _micro_flight_evaluate() -> Dictionary:
	return GlowFlight.evaluate(_body, _values, _time_s, _owner)


func _micro_flight_point() -> Dictionary:
	return GlowFlight.point(_owner, _body, _values, _time_s)


func _micro_lifecycle_evaluate() -> Dictionary:
	return Life.evaluate(_install.profile, _install.settings, _state, _source_context.rpm,
		float(_owner.sim.inputs[3]), _source_context.mixture, _source_context.density,
		float(_owner.atmosphere_configuration().get("temperature_k", 288.15)), M.norm(_air.v_air))


func _micro_source_evaluate() -> Dictionary:
	return Source.evaluate(_profile, _source_context.rpm, _source_context.admission,
		_source_context.mixture, _source_context.density, _source_context.running, 1.0)


func _micro_blade_evaluate() -> Dictionary:
	return Blade.evaluate(_source_context.rpm, _axial_speed, _rho, _install.propeller)


func _micro_fuel_mass_evaluate() -> Dictionary:
	return FuelMass.evaluate(_model.mass_kg, _model.inertia, _install.initial_fuel_kg,
		maxf(0.0, _values[1]), _install.tank_position, _install.tank_size)


func _micro_dynamics_loads() -> PackedFloat64Array:
	return Dynamics.loads(_body, _model, _deflections, maxf(0.0, _values[0]), _rho, _wind,
		_downwash, PackedFloat64Array(), _ground_up)
