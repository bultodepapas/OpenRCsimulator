extends SceneTree

const FlightScene = preload("res://main.gd")
const LakeData = preload("res://data/lake_loader.gd")
const ImpactData = preload("res://physics/impact_snapshot.gd")

class CountedSplash extends "res://render/lake/water_effects.gd":
	var resyncs := 0
	var hides := 0
	var material_clocks := 0
	var sink_syncs := 0

	func _sync_visuals() -> void:
		resyncs += 1
		super()

	func _hide_droplet(index: int) -> void:
		hides += 1
		super(index)

	func _set_material_clock(material: ShaderMaterial, clock_s: float) -> void:
		material_clocks += 1
		super(material, clock_s)

	func _sync_aircraft_sink() -> void:
		sink_syncs += 1
		super()

	func reset_counts() -> void:
		resyncs = 0
		hides = 0
		material_clocks = 0
		sink_syncs = 0

	func sample() -> Dictionary:
		return {"visual_syncs": resyncs, "hide_droplet_calls": hides, "material_clock_calls": material_clocks,
			"sink_syncs": sink_syncs, "plume_visible": _plume.visible, "droplets_visible": _droplets.visible,
			"rings_visible": _rings.filter(func(n: MeshInstance3D) -> bool: return n.visible).size(),
			"elapsed_s": _elapsed_s}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var flight := FlightScene.new()
	flight.interactive_start = true
	root.add_child(flight)
	flight.set_process(false)
	await process_frame
	if flight.session == null or flight._crash_director == null:
		printerr("Main did not finish setup")
		quit(2)
		return
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	flight.session.input_enabled = false
	var data: Dictionary = LakeData.load_from()
	if not data.ok or not flight.session.set_lake_context(data.lake):
		printerr("could not install the stock lake")
		quit(2)
		return
	var director := flight._crash_director
	var old := director.water_effects
	var fx := CountedSplash.new()
	director.add_child(fx)
	director.water_effects = fx
	old.free()
	if not fx.configure(data.lake, false):
		quit(2)
		return
	fx.reset_counts()
	for i: int in 60:
		fx.update(1.0 / 60.0)
	var empty := fx.sample()
	var hit := ImpactData.Snapshot.new()
	hit.trigger = "water"
	hit.tick = flight.session.sim.tick + 1
	hit.detected_state = flight.session.sim.state.duplicate()
	hit.has_kinematics = true
	hit.point_ned = PackedFloat64Array([110.0, 125.0, 0.8])
	hit.velocity_ned = PackedFloat64Array([0.0, 0.0, 18.0])
	hit.speed_mps = 18.0
	hit.down_speed_mps = 18.0
	flight.session.crash = {"impact": hit, "why": "water aftermath audit", "ticks_left": 20}
	director.update(0.12)
	var advancing := fx.sample()
	for i: int in 24:
		director.update(0.25)
	var before := fx.checkpoint()
	fx.reset_counts()
	for i: int in 60:
		flight._process(1.0 / 60.0)
	var live := fx.sample()
	flight.session.hold("audit_water_pause")
	fx.reset_counts()
	for i: int in 60:
		flight._process(1.0 / 60.0)
	var held := fx.sample()
	var same := fx.checkpoint() == before
	var active := director.active and director._water_active and not director._water_checkpoint_latched
	print("AUDIT_WATER_TAIL ", JSON.stringify({"empty_direct_updates_60": empty, "started": advancing,
		"ordinary_main_frames_60": live, "held_main_frames_60": held, "ordinary_water_crash": active,
		"same_effect_checkpoint": same, "auto_restart": flight.session.crash_auto_restart}))
	var ok: bool = active and same and empty.visual_syncs == 0 and advancing.plume_visible \
		and live.visual_syncs == 60 and live.hide_droplet_calls == 960 and live.material_clock_calls == 180 \
		and held == live and not live.droplets_visible and not live.plume_visible and live.rings_visible == 0
	flight.session.release("audit_water_pause")
	flight.free()
	await process_frame
	await process_frame
	quit(0 if ok else 1)
