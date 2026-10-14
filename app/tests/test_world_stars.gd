# FW-24: the star field stands where the ephemeris says: Sirius at its computed azimuth and elevation, Polaris at the
# latitude's height; colours follow B−V; the build is complete and deterministic.
# Run: godot --headless --path . --script res://tests/test_world_stars.gd
extends SceneTree

const Ephemeris := preload("res://render/world/ephemeris.gd")
const Conditions := preload("res://render/world/conditions.gd")
const SkyState := preload("res://render/world/sky_state.gd")
const Stars := preload("res://render/world/stars.gd")
const World := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## Azimuth (from north, clockwise) and elevation in degrees of a render-axes direction.
func _az_el(d: Vector3) -> Vector2:
	var north := -d.z
	var east := d.x
	return Vector2(fposmod(rad_to_deg(atan2(east, north)), 360.0), rad_to_deg(asin(clampf(d.y, -1.0, 1.0))))


func _initialize() -> void:
	var c := Conditions.resolve(PackedStringArray(["--time_of_day=night_dark"]))
	var sky := Ephemeris.sky(c.when)
	var basis := Stars.equatorial_basis(sky.lst_deg, c.when.latitude_deg)
	_check("basis orthonormal", basis.is_equal_approx(basis.orthonormalized()) and absf(basis.determinant() - 1.0) < 1e-5, str(basis))

	# Sirius (RA 101.287°, Dec −16.716°) and Vega (279.234°, +38.784°) against Ephemeris.horizontal at the same instant.
	for star: Array in [["Sirius", 101.287, -16.716], ["Vega", 279.234, 38.784], ["Altair", 297.696, 8.868]]:
		var want := Ephemeris.horizontal(star[1], star[2], c.when.latitude_deg, c.when.longitude_deg, sky.jd)
		var got := _az_el(basis * Stars.equatorial(star[1], star[2]))
		var daz := absf(fposmod(got.x - want.azimuth_deg + 180.0, 360.0) - 180.0) * cos(deg_to_rad(want.elevation_deg))
		_check("%s placed by the ephemeris" % star[0], daz < 0.01 and absf(got.y - want.elevation_deg) < 0.01,
			"got %s want az %.3f el %.3f" % [got, want.azimuth_deg, want.elevation_deg])
	var polaris := _az_el(basis * Stars.equatorial(37.95, 89.264))
	_check("Polaris north at the latitude's height", absf(polaris.y - c.when.latitude_deg) < 1.0 and (polaris.x < 2.0 or polaris.x > 358.0), str(polaris))
	var vega := _az_el(basis * Stars.equatorial(279.234, 38.784))
	_check("Vega high on a June midnight at 40° N", vega.y > 60.0, str(vega))

	var blue := Stars.colour(-0.3)
	var red := Stars.colour(1.6)
	_check("hot star bluish, cool star reddish", blue.b > blue.r and red.r > red.b, "%s %s" % [blue, red])
	_check("colours normalised to a white peak", is_equal_approx(maxf(maxf(red.r, red.g), red.b), 1.0))

	var stars := Stars.placements(SkyState.state(sky), c.when.latitude_deg)
	_check("brightest star is Sirius", (stars[0].dir as Vector3).is_equal_approx(basis * Stars.equatorial(101.287, -16.716)), str(stars[0].dir))
	_check("Sirius flux 10^(0.4·1.46)", absf(stars[0].flux - pow(10.0, 0.584)) < 1e-6)
	_check("faintest kept star is V ≤ 6.0", stars[-1].flux >= pow(10.0, -2.4) - 1e-9)
	var field := Stars.build(SkyState.state(sky), c.when.latitude_deg)
	var mmi: MultiMeshInstance3D = field.get_node("StarField")
	_check("all 5,080 stars built in one MultiMesh", stars.size() == 5080 and mmi.multimesh.instance_count == 5080 and field.get_meta("stars") == 5080)
	_check("deterministic", str(Stars.placements(SkyState.state(sky), c.when.latitude_deg)[4000]) == str(stars[4000]))
	field.free()
	var seeded_classic := SkyConfig.defaults()
	seeded_classic.seed = 99
	_check("classic star mask accepts selected seed", Atmosphere.configure_appearance(seeded_classic))
	var seeded_stars := Stars.build(SkyState.state(sky), c.when.latitude_deg, Atmosphere.cloud_state_snapshot())
	var seeded_field := seeded_stars.get_node("StarField") as MultiMeshInstance3D
	var seeded_quad := seeded_field.multimesh.mesh as QuadMesh
	var seeded_material := seeded_quad.material as ShaderMaterial
	_check("classic star mask uses non-default seed", int(seeded_material.get_shader_parameter("cloud_seed")) == 99)
	seeded_stars.free()
	_check("classic default seed restores star mask", Atmosphere.configure_appearance(SkyConfig.defaults()))
	var default_stars := Stars.build(SkyState.state(sky), c.when.latitude_deg, Atmosphere.cloud_state_snapshot())
	var default_field := default_stars.get_node("StarField") as MultiMeshInstance3D
	var default_quad := default_field.multimesh.mesh as QuadMesh
	var default_material := default_quad.material as ShaderMaterial
	_check("classic star mask keeps calibrated seed 1253", int(default_material.get_shader_parameter("cloud_seed")) == 1253)
	default_stars.free()
	var electrical := SkyConfig.for_preset("electrical_storm")
	_check("electrical cloud appearance configures for star occlusion", Atmosphere.configure_appearance(electrical))
	var storm_stars := Stars.build(SkyState.state(sky), c.when.latitude_deg, Atmosphere.cloud_state_snapshot())
	var storm_field := storm_stars.get_node("StarField") as MultiMeshInstance3D
	var storm_quad := storm_field.multimesh.mesh as QuadMesh
	var storm_material := storm_quad.material as ShaderMaterial
	_check("electrical stars sample the layered cloud mask",
		bool(storm_material.get_shader_parameter("layered_appearance"))
		and int(storm_material.get_shader_parameter("appearance_layer_count")) == 3)
	var storm_parameters: PackedVector4Array = storm_material.get_shader_parameter("appearance_layer_parameters")
	_check("star cloud decks sort by physical altitude",
		storm_parameters[0].x < storm_parameters[1].x and storm_parameters[1].x < storm_parameters[2].x)
	var retained_environment := Environment.new()
	retained_environment.set_meta("fw_star_field", weakref(storm_stars))
	_check("clear appearance configures before refreshing retained stars", Atmosphere.configure_appearance(SkyConfig.for_preset("clear")))
	World.refresh_star_cloud_appearance(retained_environment)
	_check("paused preset refresh updates the retained star material",
		int(storm_material.get_shader_parameter("appearance_layer_count")) == 0
		and float(storm_material.get_shader_parameter("appearance_cloud_density")) == 0.0)
	storm_stars.free()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
