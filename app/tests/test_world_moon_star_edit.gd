extends SceneTree
## A24 §6: a frozen Moon phase edit rotates retained star geometry from its fixed build basis.
const World := preload("res://render/world/world.gd")
const Conditions := preload("res://render/world/conditions.gd")
const MoonConfig := preload("res://environment/moon_config.gd")
const Stars := preload("res://render/world/stars.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, accepted: bool) -> void:
	checks += 1
	if not accepted:
		failures += 1
		printerr("FAIL ", label)

func _empty_field() -> void:
	pass

func _run() -> void:
	MoonConfig.session_config = MoonConfig.defaults()
	var conditions := Conditions.resolve(PackedStringArray(["--date=2026-06-21", "--time=22:30", "--utc_offset=2"]))
	var field := {id = "moon-star-edit", runway = "", surfaces = []}
	var owner := Node3D.new()
	root.add_child(owner)
	var built := World.build(owner, field, Callable(self, "_empty_field"), conditions)
	var stars: Node3D = built.environment.get_meta("fw_star_field").get_ref()
	var reference: Basis = stars.get_meta("fw_equatorial_basis")
	var full := MoonConfig.defaults()
	full.moon = "phase"
	full.phase = "full"
	_check("frozen fixture has no running sky clock", World._flow.is_empty())
	World.set_moon_config(full)
	var expected := Stars.equatorial_basis(float(Atmosphere.state.lst_deg), float(World.shown_when().latitude_deg))
	_check("phase edit rotates the frozen stars", not stars.basis.is_equal_approx(Basis.IDENTITY))
	_check("edited star directions use the accepted equatorial basis", (stars.basis * reference).is_equal_approx(expected))
	var first: Basis = stars.basis
	for repeat: int in 20:
		World.set_moon_config(MoonConfig.defaults())
		World.set_moon_config(full)
	_check("repeated phase edits do not accumulate rotation", stars.basis == first)
	MoonConfig.session_config = full.duplicate(true)
	var fresh := Node3D.new()
	root.add_child(fresh)
	var rebuilt := World.build(fresh, field, Callable(self, "_empty_field"), conditions)
	var fresh_stars: Node3D = rebuilt.environment.get_meta("fw_star_field").get_ref()
	_check("edited directions match a freshly built world", (first * reference).is_equal_approx(
		fresh_stars.basis * (fresh_stars.get_meta("fw_equatorial_basis") as Basis)))
	owner.free()
	fresh.free()
	MoonConfig.session_config = {}
	print("Moon star edit: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
