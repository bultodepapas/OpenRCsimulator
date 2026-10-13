## CR-03b / CR-02b: crash dust, sparks, chips and sound follow the surface, the struck part and the outcome class
## (docs/plans/crash-realism.md §3.3). Pure helpers plus one real Effects instance; no audio device needed.
extends SceneTree

const Effects = preload("res://render/crash/effects.gd")
const CrashAudio = preload("res://render/crash/crash_audio.gd")
const Director = preload("res://render/crash/director.gd")
const AirplaneBuilder = preload("res://render/airplane.gd")
const AircraftCatalog = preload("res://app_state/aircraft_catalog.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_dust_and_sparks()
	_chips()
	await _effects_instance()
	_audio_ladder()
	await _airframe_colors()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))


func _dust_and_sparks() -> void:
	for hard in ["runway", "asphalt", "concrete", "building"]:
		_check("%s throws no dust" % hard, Effects.dust_profile(hard).is_empty())
	_check("grass throws turf, not soil", Effects.dust_profile("grass") == Effects.DUST_COLORS.grass and Effects.dust_profile("mown") == Effects.DUST_COLORS.grass)
	_check("rough ground throws soil", Effects.dust_profile("rough") == Effects.DUST_COLORS.soil)
	_check("a tree trunk throws bark, foliage throws leaves", Effects.dust_profile("tree_trunk") == Effects.DUST_COLORS.bark and Effects.dust_profile("tree_foliage") == Effects.DUST_COLORS.leaves)
	_check("no sparks on grass, even for a hot turbine", not Effects.sparks_for(4, "grass", "engine", 30.0, true))
	_check("a wood wing sliding on asphalt does not spark", not Effects.sparks_for(3, "runway", "wingtip", 25.0, false))
	_check("an engine sliding fast on asphalt sparks", Effects.sparks_for(2, "runway", "engine", 12.0, false))
	_check("a slow engine scrape does not spark", not Effects.sparks_for(3, "runway", "engine", 5.0, false))
	_check("a hot turbine casing sparks in a structural crash on paving", Effects.sparks_for(3, "asphalt", "fuselage", 0.0, true))
	_check("a touch or scrape never sparks", not Effects.sparks_for(1, "runway", "propeller", 30.0, true))


func _chips() -> void:
	_check("no chips below C2", Effects.splinter_count(0, 1.0) == 0 and Effects.splinter_count(1, 1.0) == 0)
	_check("C2 sheds a few chips from the struck part", Effects.splinter_count(2, 0.0) == 8 and Effects.splinter_count(2, 1.0) == 16)
	_check("chips grow with class and severity", Effects.splinter_count(3, 0.5) < Effects.splinter_count(4, 0.5) and Effects.splinter_count(3, 0.2) < Effects.splinter_count(3, 0.9))
	_check("chips stay inside the pool", Effects.splinter_count(4, 1.0) <= Effects.MAX_SPLINTERS)


func _effects_instance() -> void:
	var fx := Effects.new()
	root.add_child(fx)
	fx.prepare()
	await process_frame
	var slide := Vector3(20.0, -6.0, 0.0)
	fx.set_debris_colors([Color(0.9, 0.1, 0.1), Color(0.95, 0.95, 0.95)])
	fx.start(Vector3.ZERO, slide, {"class": 3, "severity": 0.6, "surface": "grass", "component_group": "wing"}, 0.0, false, Vector3.ZERO)
	_check("grass C3 throws dust", fx.dust.emitting)
	_check("dust leans along the slide instead of bursting", fx.dust.direction.x > 0.4 and fx.dust.spread <= 30.0, str(fx.dust.direction))
	var along := 0.0
	var across := 0.0
	var colors_ok := true
	for i in fx.stats().splinters:
		along += fx._velocities[i].x
		across += absf(fx._velocities[i].z)
		# Headless rendering does not store MultiMesh colours; check the colour start() assigns.
		var c: Color = fx.chip_color(i, false)
		colors_ok = colors_ok and (_near(c, Color(0.9, 0.1, 0.1)) or _near(c, Color(0.95, 0.95, 0.95)))
	var n := maxi(fx.stats().splinters, 1)
	var lift := 0.0
	for i in fx.stats().splinters:
		lift += fx._velocities[i].y
	# Per-chip means: carried forward with a quarter of the slide, a narrow sideways spread and a low lift.
	# The CR-03a fountain (random ±4 m/s sideways, 2–8 m/s up) fails the spread and lift bounds.
	_check("chips trail along the slide", along / n >= 4.5 and across / n < 1.0 and lift / n < 2.5,
		"per chip: along %.2f, across %.2f, lift %.2f m/s" % [along / n, across / n, lift / n])
	_check("chips take the airframe's colours", colors_ok and fx.stats().splinters > 0)
	_check("a hot turbine adds dark casing chips", fx.chip_color(0, true).get_luminance() < 0.2 and _near(fx.chip_color(1, true), Color(0.95, 0.95, 0.95)))
	fx.start(Vector3.ZERO, slide, {"class": 3, "severity": 0.6, "surface": "runway", "component_group": "wingtip", "tangential_speed_mps": 20.0}, 0.0, false, Vector3.ZERO)
	_check("runway C3 wing hit: no dust, no sparks", not fx.dust.emitting and not fx.sparks.emitting)
	fx.start(Vector3.ZERO, slide, {"class": 0, "severity": 0.0, "surface": "grass"}, 0.0, false, Vector3.ZERO)
	_check("a C0 touch throws no crash dust and no chips", not fx.dust.emitting and fx.stats().splinters == 0)
	fx.set_debris_colors([])
	_check("empty colours restore the default chip colour", fx.debris_colors == Effects.DEFAULT_DEBRIS)
	fx.free()


## MultiMesh stores instance colours at reduced precision.
func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _samples(severity: Dictionary, turbine := false) -> Array:
	return CrashAudio.layers_for(severity, turbine).map(func(layer: Dictionary) -> String: return String(layer.sample))


func _audio_ladder() -> void:
	_check("C0 is a body thud only", _samples({"class": 0, "severity": 0.0, "surface": "grass"}) == ["impact_grass"])
	_check("C1 adds a scrape tail, no crack", _samples({"class": 1, "severity": 0.01, "surface": "grass"}) == ["impact_grass", "scrape"])
	var c2_wing := _samples({"class": 2, "severity": 0.1, "surface": "runway", "component_group": "wingtip"})
	_check("C2 wing hit cracks lightly and rattles, engine keeps running", c2_wing == ["crack_light", "impact_hard", "debris", "scrape"], str(c2_wing))
	var c2_prop := _samples({"class": 2, "severity": 0.1, "surface": "grass", "component_group": "propeller"})
	_check("C2 propeller strike cuts the engine", c2_prop.has("engine_cut") and not c2_prop.has("tear"), str(c2_prop))
	var c3 := _samples({"class": 3, "severity": 0.5, "surface": "rough"})
	_check("C3 cracks heavily, tears and runs the engine down", c3 == ["crack_heavy", "impact_dirt", "tear", "debris", "scrape", "engine_cut"], str(c3))
	_check("a turbine runs down instead of cutting", _samples({"class": 4, "severity": 1.0}, true).has("turbine_spool"))
	var quiet: float = CrashAudio.layers_for({"class": 0, "severity": 0.0}, false)[0].gain
	var loud: float = 0.0
	for layer: Dictionary in CrashAudio.layers_for({"class": 4, "severity": 1.0}, false):
		if String(layer.sample).begins_with("impact_"):
			loud = layer.gain
	_check("the body thud grows with the outcome", quiet < loud, "%.3f < %.3f" % [quiet, loud])
	var bounded := true
	for level in 5:
		for layer: Dictionary in CrashAudio.layers_for({"class": level, "severity": 1.0}, level % 2 == 0):
			bounded = bounded and float(layer.gain) > 0.0 and float(layer.gain) <= 0.95
	_check("every layer gain stays inside the mix bound", bounded)


func _airframe_colors() -> void:
	for entry: Dictionary in AircraftCatalog.ENTRIES:
		var airplane: Node3D = AirplaneBuilder.build(String(entry.id)).root
		root.add_child(airplane)
		await process_frame
		var colors := Director.airframe_colors(airplane)
		var dark := colors.any(func(c: Color) -> bool: return c.get_luminance() < Director.CHIP_MIN_LUMINANCE)
		print("     %s: %d chip colours %s" % [entry.id, colors.size(), str(colors.map(func(c: Color) -> String: return c.to_html(false)))])
		_check("%s chip colours are bounded, non-empty and not dark" % entry.id, not colors.is_empty() and colors.size() <= 6 and not dark)
		airplane.free()
	var stik: Node3D = AirplaneBuilder.build("jensen-das-ugly-stik-60").root
	root.add_child(stik)
	await process_frame
	_check("the Stik yields its own covering colours", not Director.airframe_colors(stik).is_empty())
	stik.free()
