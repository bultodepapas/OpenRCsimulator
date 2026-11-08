extends SceneTree
## Preserve the donor profile/save identity while explicitly sharing its unchanged wheels.
const Data := preload("res://physics/aircraft_data.gd")
const Wheels := preload("res://physics/wheel_profiles.gd")
const Dependencies := preload("res://workshop/dependencies.gd")
const BASIC := "res://data/aircraft/jensen_ugly_stik_60.json"
const ELECTRIC := "stik-electric-6s"
const ORIGINAL_REGISTRY_SHA := "58a2526829a3e9e529ac16f79a7d135614618c3d70350c2187d804a476e40665"
var checks := 0
var failures := 0

func check(label: String, accepted: bool) -> void:
	checks += 1
	if not accepted:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	var donor := Data.load_file(BASIC)
	check("donor loads with an applied wheel profile", donor.ok and donor.model.wheel_profile.status == "applied")
	if not donor.ok:
		quit(1)
		return
	check("original global registry bytes are preserved", FileAccess.get_sha256(Wheels.DEFAULT_PATH) == ORIGINAL_REGISTRY_SHA)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASIC))
	var old_manifest := {format = Dependencies.FORMAT, files = {Wheels.DEFAULT_PATH: ORIGINAL_REGISTRY_SHA}}
	check("existing basic Workshop wheel dependency still verifies unchanged", Dependencies.verify(raw, old_manifest).ok)
	var model: Dictionary = donor.model.duplicate(true)
	model.id = ELECTRIC
	var shared := Wheels.apply_to_model(model)
	check("electric resolves the strict donor profile", shared.ok and shared.identity.status == "applied")
	if shared.ok:
		check("electric keeps its own aircraft identity", shared.model.id == ELECTRIC and shared.identity.aircraft_id == ELECTRIC)
		check("shared quantities and gear remain exact", shared.model.landing_gear == donor.model.landing_gear)
		check("selected and file identities stay the donor identities", shared.identity.profile_sha256 == donor.model.wheel_profile.profile_sha256 and shared.identity.input_sha256 == ORIGINAL_REGISTRY_SHA)
	var renamed := model.duplicate(true)
	renamed.id = "workshop-renamed-wheel-fixture"
	var selected := Wheels.apply_selected_profile(renamed, ELECTRIC, donor.model.wheel_profile.profile_sha256)
	check("explicit electric source survives a Workshop rename", selected.ok and selected.identity.aircraft_id == renamed.id and selected.identity.profile_id == ELECTRIC)
	check("explicit alias still refuses a wrong pin", not Wheels.apply_selected_profile(renamed, ELECTRIC, "0".repeat(64)).ok)
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Wheels.DEFAULT_PATH))
	var other_id := "synthetic_stik_electric_4s"
	var other_sha := JSON.stringify(registry.profiles[other_id], "", true, true).sha256_text()
	var other := Wheels.apply_selected_profile(model, other_id, other_sha)
	check("explicit profile selection takes precedence over model ID", other.ok and other.identity.profile_id == other_id and other.identity.profile_sha256 == other_sha)
	var fixture := "user://test_stik_wheel_alias_%d.json" % Time.get_ticks_usec()
	var fixture_profile: Dictionary = registry.profiles["jensen-das-ugly-stik-60"].duplicate(true)
	fixture_profile.description = "Explicit fixture source, independent of the bundled alias"
	var document := {format = Wheels.FORMAT, profiles = {ELECTRIC: fixture_profile}}
	var file := FileAccess.open(fixture, FileAccess.WRITE)
	check("isolated fixture opens", file != null)
	if file != null:
		file.store_string(JSON.stringify(document))
		file.close()
		var fixture_sha := JSON.stringify(fixture_profile, "", true, true).sha256_text()
		var explicit := Wheels.apply_selected_profile(model, ELECTRIC, fixture_sha, fixture)
		check("caller-supplied registry keeps its independent lookup", explicit.ok and explicit.identity.profile_sha256 == fixture_sha)
		document.profiles = {}
		file = FileAccess.open(fixture, FileAccess.WRITE)
		file.store_string(JSON.stringify(document))
		file.close()
		check("missing explicit profile cannot downgrade to legacy", not Wheels.apply_selected_profile(model, ELECTRIC, fixture_sha, fixture).ok)
		document.profiles = {ELECTRIC: fixture_profile}
		fixture_profile.contacts.nose.wheel_radius.value = -1.0
		file = FileAccess.open(fixture, FileAccess.WRITE)
		file.store_string(JSON.stringify(document))
		file.close()
		check("invalid wheel source is refused", not Wheels.apply_to_model(model, fixture).ok)
		check("isolated fixture cleans up", DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture)) == OK)
	print("Stik wheel profile alias: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
