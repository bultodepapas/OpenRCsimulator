extends SceneTree

const Settings := preload("res://render/shadow_settings.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const High := preload("res://render/high_graphics_profile.gd")
const Spec := preload("res://spec.gd")
const Ground := preload("res://render/ground.gd")
const Water := preload("res://render/lake/water_material.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func run() -> void:
	var previous: Dictionary = Settings.describe().requested
	var original_engine := Atmosphere.engine_shadows
	var original_state := Atmosphere.state.duplicate(true)
	var original_spec := Spec.ATMOSPHERE.duplicate(true)
	var standard := Settings.resolve({}, "gl_compatibility", false)
	check("current preserves combined coverage", standard.effective.native and standard.effective.projected and standard.effective.technique == "auto")
	check("current standard preserves allocation", standard.effective.atlas_size == 4096 and standard.effective.cascades == 2 and standard.effective.use_16_bits)
	var high := Settings.resolve({}, "forward_plus", true)
	check("current High preserves allocation and PCSS", high.effective.atlas_size == 8192 and high.effective.cascades == 4 and not high.effective.use_16_bits and high.effective.angular_distance == 0.53)
	check("malformed selections independently fall back", Settings.normalize({shadow_technique = "native", shadow_quality = 99, shadow_distance = "distant", shadow_softness = null}) == {
		shadow_technique = "native", shadow_quality = "current", shadow_distance = "auto", shadow_softness = "auto", shadow_aircraft_cue = "auto", shadow_cloud = "on"})
	for technique: String in Settings.TECHNIQUES:
		var result: Dictionary = Settings.resolve({shadow_technique = technique}, "forward_plus", true).effective
		check(technique + " native ownership", result.native == (technique in ["auto", "native"]))
		check(technique + " projected ownership", result.projected == (technique in ["auto", "projected"]))
		if not result.projected:
			check(technique + " disables aircraft cue", result.aircraft_cue == "off")
	var unsupported := Settings.resolve({shadow_technique = "native"}, "unknown", false)
	check("unknown renderer refuses native and reports fallback", not unsupported.effective.native and unsupported.effective.technique == "projected" and not unsupported.reasons.is_empty())
	var hard: Dictionary = Settings.resolve({shadow_softness = "hard"}, "forward_plus", true).effective
	check("hard disables PCSS and filtering together", hard.angular_distance == 0.0 and hard.filter_quality == 0)
	for quality: String in Settings.QUALITY:
		var result: Dictionary = Settings.resolve({shadow_quality = quality}, "gl_compatibility", false).effective
		check(quality + " bounds atlas", result.atlas_size in [2048, 4096, 8192])
		check(quality + " never invents Compatibility PCSS", result.angular_distance == 0.0 and result.filter_technique != "pcss")
	Settings.apply({})
	var first_revision := Settings.revision
	Settings.apply({})
	High.configure()
	check("same settings/world initialization is idempotent", Settings.revision == first_revision)
	var receipt := Settings.describe()
	receipt.requested.shadow_quality = "ultra"
	receipt.effective.native = false
	check("diagnostic snapshots cannot mutate live state", Settings.describe().requested.shadow_quality == "current" and Settings.effective().native)
	Atmosphere.state = {}
	Atmosphere.engine_shadows = true
	var holder := Node3D.new()
	root.add_child(holder)
	var sun := Atmosphere.create_sun(holder)
	var base_mode := sun.directional_shadow_mode
	var base_blend := sun.directional_shadow_blend_splits
	var base_distance := sun.directional_shadow_max_distance
	var base_angle := sun.light_angular_distance
	var base_energy := sun.light_energy
	var base_color := sun.light_color
	var base_bias := sun.shadow_bias
	var base_normal_bias := sun.shadow_normal_bias
	Settings.apply({shadow_technique = "native", shadow_quality = "high", shadow_distance = "near", shadow_softness = "hard"})
	check("live existing sun takes near range and four cascades", sun.shadow_enabled and sun.directional_shadow_max_distance == 100.0 and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	check("hard solar shadow has no angular blur", sun.light_angular_distance == 0.0)
	Atmosphere.update_sun(sun)
	check("time-of-day reapply cannot overwrite preferences", sun.directional_shadow_max_distance == 100.0 and sun.light_angular_distance == 0.0)
	check("policy preserves direct light/color/bias", sun.light_energy == base_energy and sun.light_color == base_color and sun.shadow_bias == base_bias and sun.shadow_normal_bias == base_normal_bias)
	Settings.apply({shadow_technique = "projected"})
	check("projected disables existing native sun", not sun.shadow_enabled and Settings.projected_enabled())
	var projected_energy := sun.light_energy
	Atmosphere.update_sun(sun)
	check("lighting update does not reactivate native sun", not sun.shadow_enabled and sun.light_energy == projected_energy)
	Settings.apply({shadow_technique = "off"})
	check("off disables both direct routes", not sun.shadow_enabled and not Settings.projected_enabled())
	Settings.apply({})
	check("revert restores original local settings", sun.shadow_enabled and sun.directional_shadow_mode == base_mode and sun.directional_shadow_blend_splits == base_blend and sun.directional_shadow_max_distance == base_distance and sun.light_angular_distance == base_angle)
	Settings.set_distance_cap(sun, 35.0)
	Settings.apply({shadow_distance = "far"})
	Atmosphere.update_sun(sun)
	check("close activity range cap survives live changes and flow", sun.directional_shadow_max_distance == 35.0)
	Atmosphere.engine_shadows = false
	Atmosphere.update_sun(sun)
	Settings.apply({shadow_technique = "native"})
	check("explicit engine-off owner remains authoritative", not sun.shadow_enabled)
	Settings.apply({shadow_quality = "low"})
	var another := Atmosphere.create_sun(holder)
	check("new worlds use selected tier without resetting allocation", another.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS and Settings.effective().atlas_size == 2048)
	holder.free()
	for cycle in 30:
		var temporary := Node3D.new()
		root.add_child(temporary)
		Atmosphere.create_sun(temporary)
		temporary.free()
	check("unchanged-preference world churn keeps weak registry bounded", Settings._lights.size() <= 1)
	Settings.apply({})
	check("destroyed lights are not retained", Settings._lights.is_empty())
	_test_lighting_compensation()
	_test_receipts()
	_test_cloud_shadow_choice()
	check("atmosphere spec remains byte-identical", Spec.ATMOSPHERE == original_spec)
	Atmosphere.state = original_state
	Atmosphere.engine_shadows = original_engine
	Settings.apply(previous)
	print("Shadow settings: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


## SA-15: the saved Cloud shadows choice removes and restores the spatial cloud shade on live ground materials,
## without touching the weather/sky strength it was built with.
func _test_cloud_shadow_choice() -> void:
	Settings.apply({})
	check("SA-15: cloud shadows default on", Settings.cloud_shadows_enabled() and Settings.describe().effective.cloud_shadows)
	var grass := ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGB8))
	var ground: ShaderMaterial = Atmosphere.ground_material(grass)
	var weather := float(ground.get_shader_parameter("cloud_shadow_strength"))
	var unrelated := ShaderMaterial.new()
	unrelated.shader = Atmosphere.SKY_SHADER
	Atmosphere.update_ground_material(unrelated)
	var sky_before: Variant = unrelated.get_shader_parameter("cloud_shadow_strength")
	var revision := Settings.revision
	Settings.apply({shadow_cloud = "off"})
	check("SA-15: Off applies at once to a live ground material", Settings.revision > revision
		and float(ground.get_shader_parameter("cloud_shadow_strength")) == 0.0
		and ground.get_shader_parameter("cloud_shadow_map_enabled") != true)
	check("SA-15: Off leaves other shader kinds and the direct-shadow technique alone",
		unrelated.get_shader_parameter("cloud_shadow_strength") == sky_before and Settings.effective().technique == "auto")
	var built_off: ShaderMaterial = Atmosphere.ground_material(grass)
	check("SA-15: ground built while Off starts without the cloud shade",
		float(built_off.get_shader_parameter("cloud_shadow_strength")) == 0.0)
	var copy := ground.duplicate() as ShaderMaterial
	Atmosphere.track_shadow_material_copy(copy, ground)
	Settings.apply({})
	check("SA-15: On restores the weather strength on every live material, including copies",
		is_equal_approx(float(ground.get_shader_parameter("cloud_shadow_strength")), weather)
		and is_equal_approx(float(built_off.get_shader_parameter("cloud_shadow_strength")), weather)
		and is_equal_approx(float(copy.get_shader_parameter("cloud_shadow_strength")), weather) and weather > 0.0)


## SA-13/14: report what the owner submitted and what each light does, not the project default or global policy.
func _test_receipts() -> void:
	Settings.apply({shadow_quality = "ultra", shadow_technique = "native"})
	var applied := Settings.applied_global()
	check("SA-13: the applied atlas is the selected one, not the project default",
		applied.atlas_size == 8192 and applied.atlas_size != int(ProjectSettings.get_setting(Settings.ATLAS_SETTING, 0))
		and applied.revision == Settings.revision)
	check("SA-13: headless reports that nothing reached a renderer", not applied.submitted)
	Settings.apply({shadow_quality = "ultra", shadow_technique = "projected"})
	var parked := Settings.applied_global()
	check("SA-22: a disabled native route parks the atlas, keeping the saved quality and filter",
		parked.parked and parked.atlas_size == Settings.PARKED_ATLAS_SIZE and parked.use_16_bits
		and parked.filter_quality == applied.filter_quality and Settings.effective().atlas_size == 8192)
	Settings.apply({shadow_quality = "ultra", shadow_technique = "off"})
	check("SA-22: Off parks the atlas too", Settings.applied_global().atlas_size == Settings.PARKED_ATLAS_SIZE)
	Settings.apply({shadow_quality = "ultra", shadow_technique = "native"})
	var restored := Settings.applied_global()
	check("SA-22: re-enabling Native restores the selected atlas", not restored.parked
		and restored.atlas_size == 8192 and not restored.use_16_bits)
	var holder := Node3D.new()
	root.add_child(holder)
	var vetoed := DirectionalLight3D.new()
	holder.add_child(vetoed)
	Settings.apply_sun(vetoed, false)
	var capped := DirectionalLight3D.new()
	holder.add_child(capped)
	Settings.apply_sun(capped, true)
	Settings.set_distance_cap(capped, 35.0)
	var rows := {}
	for row: Dictionary in Settings.light_receipts():
		rows[row.path] = row
	var vetoed_row: Dictionary = rows.get(str(vetoed.get_path()), {})
	var capped_row: Dictionary = rows.get(str(capped.get_path()), {})
	check("SA-14: an explicit source veto is not reported as casting despite effective.native",
		Settings.effective().native and not vetoed_row.is_empty() and not vetoed_row.casting
		and vetoed_row.inactive_reason == "source_disabled")
	check("SA-14: an activity cap is visible beside the configured range", not capped_row.is_empty()
		and capped_row.casting and capped_row.distance_cap_m == 35.0 and capped_row.max_distance_m <= 35.0)
	Settings.apply({shadow_technique = "projected"})
	var off_row: Dictionary = {}
	for row: Dictionary in Settings.light_receipts():
		if row.path == str(capped.get_path()):
			off_row = row
	check("SA-14: a technique without native maps names its reason", not off_row.is_empty() and not off_row.casting
		and off_row.inactive_reason == "technique")
	holder.free()
	Settings.apply({})


func _test_lighting_compensation() -> void:
	Settings.apply({})
	Atmosphere.state = {}
	Atmosphere.engine_shadows = true
	var holder := Node3D.new()
	root.add_child(holder)
	var first: Dictionary = Spec.ATMOSPHERE.duplicate(true)
	first.sun_energy = 0.67
	first.sun_color = Color(0.8, 0.7, 0.6)
	first.sun_scatter = 0.44
	var second: Dictionary = Spec.ATMOSPHERE.duplicate(true)
	second.sun_energy = 1.23
	second.sun_color = Color(0.6, 0.8, 0.9)
	second.sun_scatter = 0.31
	var a := _lighting_fixture(holder, first)
	var b := _lighting_fixture(holder, second)
	a.environment.tonemap_exposure = 0.43
	b.environment.tonemap_exposure = 0.91
	var baseline_a := _lighting_bytes(a)
	var baseline_b := _lighting_bytes(b)
	Atmosphere.engine_shadows = false
	var source_disabled := Atmosphere.create_sun(holder, second)
	var source_disabled_energy := source_disabled.light_energy
	Atmosphere.engine_shadows = true
	# These lights retain their own flow snapshot even if another world becomes active.
	Atmosphere.state = {"light_energy": 0.37, "light_color": Color(0.7, 0.6, 0.5),
		"light_dir": Vector3.UP, "shadow_strength": 1.0}
	var retained := DirectionalLight3D.new()
	holder.add_child(retained)
	Atmosphere.update_sun(retained)
	var retained_baseline := retained.light_energy
	Atmosphere.state = {"light_energy": 1.7, "light_color": Color.WHITE,
		"light_dir": Vector3.UP, "shadow_strength": 1.0}
	Settings.apply({"shadow_technique": "projected"})
	Atmosphere.state = {}
	var fresh_a := _lighting_fixture(holder, first)
	var fresh_b := _lighting_fixture(holder, second)
	var projected_a := _lighting_bytes(fresh_a)
	check("live first snapshot matches fresh projected lighting", _lighting_bytes(a) == _lighting_bytes(fresh_a))
	check("live second snapshot matches fresh projected lighting", _lighting_bytes(b) == _lighting_bytes(fresh_b))
	check("route changes preserve both adapted exposures", is_equal_approx(a.environment.tonemap_exposure, 0.43)
		and is_equal_approx(b.environment.tonemap_exposure, 0.91))
	check("retained flow light uses its own source state", is_equal_approx(retained.light_energy, 0.37))
	check("an explicit source-off light keeps its own uncompensated energy",
		not source_disabled.shadow_enabled and source_disabled.light_energy == source_disabled_energy)
	# An ordinary lighting update while projected is selected must replace the
	# inputs used by the next change, without mutating the other world.
	var updated: Dictionary = first.duplicate(true)
	updated.sun_energy = 0.81
	updated.sun_color = Color(0.5, 0.7, 0.8)
	var compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var tracked_resources: Array = [a.sun, a.environment, a.environment.sky.sky_material, a.ground, a.surface, a.water]
	var references: Array[WeakRef] = []
	var surface_source: Dictionary = {}
	if compatibility:
		for resource: Object in tracked_resources:
			references.append(Atmosphere._shadow_lighting_resources[resource.get_instance_id()].reference)
		surface_source = Atmosphere._shadow_lighting_resources[a.surface.get_instance_id()].source.duplicate(true)
		check("copied surface has its own weak reference", not is_same(references[3], references[4])
			and references[3].get_ref() == a.ground and references[4].get_ref() == a.surface)
	Atmosphere.update_sun(a.sun, updated)
	Atmosphere.update_environment(a.environment, updated)
	Atmosphere.update_ground_material(a.ground, updated)
	if compatibility:
		check("updating the source preserves the copied surface snapshot",
			Atmosphere._shadow_lighting_resources[a.surface.get_instance_id()].source == surface_source
			and is_equal_approx(Atmosphere._shadow_lighting_resources[a.ground.get_instance_id()].source.energy, 0.81))
	Atmosphere.update_ground_material(a.surface, updated)
	Water.update_lighting(a.water, updated)
	if compatibility:
		var reused := true
		for index in tracked_resources.size():
			var resource: Object = tracked_resources[index]
			reused = reused and is_same(references[index],
				Atmosphere._shadow_lighting_resources[resource.get_instance_id()].reference)
		check("lighting updates reuse each live resource's weak reference", reused)
	# Keep this fixture's exposure as an independent owner would after an update.
	a.environment.tonemap_exposure = 0.43
	Settings.apply({})
	var fresh_updated := _lighting_fixture(holder, updated)
	check("updates rebase live inputs before returning to native", _lighting_bytes(a) == _lighting_bytes(fresh_updated))
	check("other snapshot returns to its exact native bytes", _lighting_bytes(b) == baseline_b)
	check("retained flow light restores exact native energy", retained.light_energy == retained_baseline)
	check("source-off energy remains unchanged after returning to native",
		not source_disabled.shadow_enabled and source_disabled.light_energy == source_disabled_energy)
	for cycle in 10:
		Settings.apply({"shadow_technique": "projected"})
		Settings.apply({})
	check("repeated route changes do not accumulate rounding", _lighting_bytes(b) == baseline_b)
	check("native baseline differs only when Compatibility compensation applies",
		RenderingServer.get_current_rendering_method() != "gl_compatibility"
		or baseline_a != projected_a)
	if compatibility:
		var temporary := Node3D.new()
		root.add_child(temporary)
		var temporary_sun := Atmosphere.create_sun(temporary)
		var stale_entry: Dictionary = Atmosphere._shadow_lighting_resources[temporary_sun.get_instance_id()].duplicate(true)
		var reference: WeakRef = stale_entry.reference
		temporary.free()
		check("tracked references do not retain a destroyed light", reference.get_ref() == null)
		# Simulate a stale ID slot without relying on the engine to recycle IDs.
		Atmosphere._prune_shadow_lighting()
		var replacement := DirectionalLight3D.new()
		holder.add_child(replacement)
		var replacement_id := replacement.get_instance_id()
		Atmosphere._shadow_lighting_resources[replacement_id] = stale_entry
		var registrations_before := Atmosphere._shadow_lighting_registrations
		Atmosphere.update_sun(replacement, updated)
		var replacement_entry: Dictionary = Atmosphere._shadow_lighting_resources[replacement_id]
		check("a dead reference is replaced with the new light and snapshot",
			not is_same(reference, replacement_entry.reference) and replacement_entry.reference.get_ref() == replacement
			and is_equal_approx(replacement_entry.source.energy, 0.81)
			and Atmosphere._shadow_lighting_registrations == registrations_before + 1)
		# Also reject a live reference to a different object occupying the slot.
		var foreign_entry: Dictionary = Atmosphere._shadow_lighting_resources[a.ground.get_instance_id()].duplicate(true)
		var foreign_reference: WeakRef = foreign_entry.reference
		var other := DirectionalLight3D.new()
		holder.add_child(other)
		var other_id := other.get_instance_id()
		Atmosphere._shadow_lighting_resources[other_id] = foreign_entry
		registrations_before = Atmosphere._shadow_lighting_registrations
		Atmosphere.update_sun(other, updated)
		var other_entry: Dictionary = Atmosphere._shadow_lighting_resources[other_id]
		check("a different live resource is replaced with the new light and snapshot",
			not is_same(foreign_reference, other_entry.reference) and other_entry.reference.get_ref() == other
			and other_entry.kind == "light" and is_equal_approx(other_entry.source.energy, 0.81)
			and Atmosphere._shadow_lighting_registrations == registrations_before + 1)
	var tracked_before := Atmosphere._shadow_lighting_resources.size()
	for cycle in 130:
		var temporary := Node3D.new()
		root.add_child(temporary)
		Atmosphere.create_sun(temporary)
		temporary.free()
	check("resource registry prunes unchanged-preference churn",
		Atmosphere._shadow_lighting_resources.size() <= tracked_before + Atmosphere.SHADOW_LIGHTING_SWEEP_INTERVAL)
	holder.free()
	Atmosphere.state = {}


func _lighting_fixture(holder: Node, lighting: Dictionary) -> Dictionary:
	var environment := Atmosphere.environment(lighting)
	var sun := Atmosphere.create_sun(holder, lighting)
	var ground := Atmosphere.ground_material(null, lighting)
	var surface := Ground.surface_material(ground, "runway", Vector2.ZERO, Vector2.ONE)
	var water := Water.create({}, lighting)
	return {"environment": environment, "sun": sun, "ground": ground, "surface": surface, "water": water}


func _lighting_bytes(fixture: Dictionary) -> PackedByteArray:
	var sky: ShaderMaterial = fixture.environment.sky.sky_material
	var values: Array = [fixture.sun.light_energy, fixture.environment.fog_sun_scatter,
		sky.get_shader_parameter("sun_lin"), sky.get_shader_parameter("sun_scatter"),
		sky.get_shader_parameter("sun_aureole_lin")]
	for material: ShaderMaterial in [fixture.ground, fixture.surface, fixture.water]:
		values.append(material.get_shader_parameter("sun_lin"))
		values.append(material.get_shader_parameter("sun_scatter"))
	return var_to_bytes(values)
