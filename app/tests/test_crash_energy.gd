## CR-22b: fire, fuel stains and LiPo smoke follow the tagged energy source (docs/research/crash-damage-investigations/
## CR-22b/research.md). Pure outcome matrix, one real Effects instance, and the fleet's data tags.
extends SceneTree

const Effects = preload("res://render/crash/effects.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_matrix()
	await _instance()
	_fleet_tags()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))


func _report(level: int, severity: float, group: String, ruptured: bool) -> Dictionary:
	return {"class": level, "severity": severity, "component_group": group, "tank_ruptured": ruptured}


func _matrix() -> void:
	var jet := Effects.energy_outcome({kerosene = 1.28}, _report(3, 0.6, "fuselage", true), true, true)
	_check("a hot turbine with a ruptured kerosene tank burns", jet.fire_kind == "kerosene" and is_equal_approx(jet.fire_s, 1.28 / Effects.KEROSENE_BURN_KG_S))
	var cold := Effects.energy_outcome({kerosene = 1.28}, _report(4, 1.0, "fuselage", true), false, false)
	_check("cold kerosene only stains", cold.fire_kind.is_empty() and cold.stain)
	var glow := Effects.energy_outcome({glow_fuel = 0.12}, _report(4, 1.0, "fuselage", true), true, false)
	_check("glow fuel never shows a fire, only a wet stain", glow.fire_kind.is_empty() and glow.stain)
	_check("an intact glow tank leaves nothing", not Effects.energy_outcome({glow_fuel = 0.12}, _report(2, 0.1, "wingtip", false), true, false).stain)
	var gas := Effects.energy_outcome({gasoline = 0.37}, _report(4, 0.9, "engine", true), true, false)
	_check("a destroyed gasoline airplane with the engine running burns briefly", gas.fire_kind == "gasoline" and is_equal_approx(gas.fire_s, 0.37 / Effects.GASOLINE_BURN_KG_S), str(gas.fire_s))
	var gas_c3 := Effects.energy_outcome({gasoline = 0.37}, _report(3, 0.6, "engine", true), true, false)
	_check("a structural (not destroyed) gasoline crash only stains", gas_c3.fire_kind.is_empty() and gas_c3.stain)
	_check("a stopped gasoline engine does not ignite", Effects.energy_outcome({gasoline = 0.37}, _report(4, 1.0, "engine", true), false, false).fire_kind.is_empty())
	_check("a wing-tip gasoline crash does not ignite", Effects.energy_outcome({gasoline = 0.37}, _report(4, 1.0, "wingtip", true), true, false).fire_kind.is_empty())
	var light := Effects.energy_outcome({lipo = 0.33}, _report(3, 0.3, "fuselage", false), true, false)
	var hard := Effects.energy_outcome({lipo = 0.33}, _report(3, 0.9, "fuselage", false), true, false)
	_check("a central C3 hit makes a damaged pack vent later", light.vent_delay_s > 0.0 and light.vent_s > 0.0 and not light.flare)
	_check("a harder hit vents sooner", hard.vent_delay_s < light.vent_delay_s, "%.1f < %.1f s" % [hard.vent_delay_s, light.vent_delay_s])
	_check("venting delay stays inside its bounds", hard.vent_delay_s >= Effects.VENT_DELAY_MIN_S and light.vent_delay_s <= Effects.VENT_DELAY_MAX_S)
	_check("only the worst destroyed band flares", Effects.energy_outcome({lipo = 0.33}, _report(4, 0.9, "engine", false), true, false).flare
		and not Effects.energy_outcome({lipo = 0.33}, _report(4, 0.5, "engine", false), true, false).flare)
	_check("a wing-tip hit leaves the pack alone", Effects.energy_outcome({lipo = 0.33}, _report(4, 1.0, "wingtip", false), true, false).vent_delay_s < 0.0)
	_check("a damage-class hit leaves the pack alone", Effects.energy_outcome({lipo = 0.33}, _report(2, 0.2, "fuselage", false), true, false).vent_delay_s < 0.0)
	# CR-22d: a fuel fire starts with a flash sized by Roberts (1981) on the atomised share; glow and LiPo never flash.
	var roberts := func(kg: float) -> float: return minf(0.5 * 5.8 * pow(Effects.FLASH_ATOMISED_FRACTION * kg, 1.0 / 3.0), Effects.FLASH_MAX_RADIUS_M)
	_check("a kerosene fire starts with a flash of the Roberts size", jet.flash and is_equal_approx(jet.flash_radius_m, roberts.call(1.28)), "%.2f m" % jet.flash_radius_m)
	_check("a gasoline fire flashes smaller than the jet's", gas.flash and gas.flash_radius_m < jet.flash_radius_m)
	_check("a flash lasts at least the perceptible minimum", jet.flash_s >= Effects.FLASH_MIN_S)
	_check("glow fuel never flashes", not glow.flash)
	_check("a LiPo flare is not a fuel flash", not Effects.energy_outcome({lipo = 0.33}, _report(4, 0.9, "engine", false), true, false).flash)
	_check("cold kerosene never flashes", not cold.flash)
	var none := Effects.energy_outcome({}, _report(4, 1.0, "fuselage", true), true, true)
	_check("no tagged energy, no fire, stain or smoke", none.fire_kind.is_empty() and not none.stain and none.vent_delay_s < 0.0)


func _instance() -> void:
	var fx := Effects.new()
	root.add_child(fx)
	fx.prepare()
	await process_frame
	_check("particle budget holds with the venting emitter", int(fx.stats().particles) <= 700, str(fx.stats().particles))
	var report := _report(4, 0.9, "fuselage", false)
	fx.start(Vector3.ZERO, Vector3(10, -5, 0), report, 0.0, false, Vector3.ZERO)
	var outcome := Effects.energy_outcome({lipo = 0.33}, report, true, false)
	fx.apply_energy(outcome)
	var delay: float = outcome.vent_delay_s
	_check("no smoke and no flame right after the impact", not fx.vent.emitting and fx.fire_strength() == 0.0)
	_step(fx, delay - 0.5)
	_check("still quiet just before the venting delay", not fx.vent.emitting)
	_step(fx, 1.0)
	_check("the pack vents after the delay", fx.vent.emitting)
	_check("the worst band flares as venting starts", fx.fire_strength() > 0.0 and fx.flame.emitting)
	_step(fx, Effects.FLARE_S + 0.5)
	_check("the flare is short", fx.fire_strength() == 0.0)
	_step(fx, Effects.VENT_DURATION_S)
	_check("venting ends", not fx.vent.emitting)
	fx.start(Vector3.ZERO, Vector3(10, -5, 0), _report(4, 1.0, "fuselage", true), 0.0, false, Vector3.ZERO)
	var marks_before := int(fx.stats().marks)
	fx.apply_energy(Effects.energy_outcome({glow_fuel = 0.12}, _report(4, 1.0, "fuselage", true), true, false))
	var stain: MeshInstance3D = fx.marks[(int(fx.stats().marks) - 1)] if int(fx.stats().marks) > 0 else null
	_check("a glow spill leaves one dark wet stain", int(fx.stats().marks) == marks_before + 1 and stain != null
		and (stain.material_override as StandardMaterial3D).albedo_color.a < 0.6)
	fx.reset()
	var jet_report := _report(4, 1.0, "fuselage", true)
	fx.start(Vector3.ZERO, Vector3(20, -10, 0), jet_report, 1.28, true, Vector3.ZERO)
	var jet_outcome := Effects.energy_outcome({kerosene = 1.28}, jet_report, true, true)
	fx.apply_energy(jet_outcome)
	_check("ignition throws a fireball", fx.fireball.emitting)
	_step(fx, 0.05)
	_check("the flash lights the scene far brighter than the fire", fx.light.visible and fx.light.light_energy >= 6.0, "%.1f" % fx.light.light_energy)
	_step(fx, float(jet_outcome.flash_s) + 0.1)
	_check("the flash is over, the fire burns on", fx.flash_strength() == 0.0 and fx.fire_strength() > 0.0 and fx.light.light_energy < 3.0, "%.2f" % fx.light.light_energy)
	fx.reset()
	_check("reset clears pending venting", not fx.vent.emitting and fx._vent_start_s == INF and fx.flash_strength() == 0.0)
	fx.free()


func _step(fx: Variant, seconds: float) -> void:
	var steps := int(ceil(seconds / 0.05))
	for i in steps:
		fx.update(0.05, false)


func _fleet_tags() -> void:
	var expected := {
		"jensen_ugly_stik_60": "glow_fuel", "gp_extra_300s_60": "glow_fuel", "p51d_mustang_120": "gasoline",
		"sebart_avanti_s_a200": "kerosene", "turbo_lumber_evolution": "lipo",
		"stik_glow_55ax_2t": "glow_fuel", "stik_glow_55ax_2t_apc_13x6": "glow_fuel",
		"stik_glow_fs64v_4t": "glow_fuel", "stik_glow_fs64v_4t_apc_13x6": "glow_fuel",
	}
	for file: String in DirAccess.get_files_at("res://data/aircraft/"):
		if not file.ends_with(".json"):
			continue
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/" + file))
		var kinds: Array = []
		for item: Dictionary in raw.inventory:
			if item.has("energy_source"):
				kinds.append(item.energy_source)
		var id := file.get_basename()
		if expected.has(id):
			_check("%s carries %s" % [id, expected[id]], kinds == [expected[id]], str(kinds))
		else:
			_check("%s (synthetic electric donor) tags no energy" % id, kinds.is_empty(), str(kinds))
