# FIELD-WORLD-PLAN FW-35: a night-flying kit for any catalog aircraft, placed from the model's own bounds, so no
# model team file, node name or hinge changes. Model frame: +x right wing, +y up, −z nose (render/frames.gd).
# - navigation lights: red left tip, green right tip, white tail (the full-size convention RC night kits copy);
#   seeing red on the right means the airplane is coming toward you or inverted, as for full-size traffic;
# - white anti-collision strobes on both tips, double flash every second (on sim_clock);
# - a forward landing light (one SpotLight3D, no shadows) that lights the runway on approach.
# Belly LED strips (upright vs inverted at a glance) need per-model anchors: requested from the model teams, because
# the bounds include wheels and propeller and would float a strip below the gear.
# Brightness is physical in scene units (sun irradiance = 1), so the time-of-day exposure decides what shows.
extends RefCounted

const SPRITE_SHADER := preload("res://render/world/light_sprite.gdshader")
const Spec := preload("res://spec.gd")
const Exposure := preload("res://render/world/exposure.gd")

## LED luminance as scene-linear radiance (estimate: ~3× a sunlit white surface, ~10⁴–10⁵ cd/m²).
const LED_RADIANCE := 2.5
const NAV_SIZE_M := 0.025
## Smallest on-screen size and brightest on-screen value of a kit light (estimates, from night captures): 4 px and
## 2.5 keep red and green readable as colours at 100–200 m instead of white specks.
const NAV_MIN_PX := 4.0
const NAV_DISPLAY_CAP := 2.5
const STROBE := Vector4(1.0, 0.06, 0.16, 1.0) # 1 s period, 60 ms pulses, second pulse at 160 ms
## Landing light: SpotLight3D energy ≈ irradiance × d² in scene units. ~2,000 cd (a bright LED landing light,
## estimate) gives ~5 lux at 20 m, i.e. 5·10⁻⁵ of a ~10⁵ lux sun.
const LANDING_ENERGY := 0.02
const LANDING_RANGE_M := 80.0
const LANDING_ANGLE_DEG := 16.0


## The model's bounds in its root frame, and the widest mesh's (the wing's) bounds.
static func bounds(root: Node3D) -> Dictionary:
	var all := AABB()
	var wing := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		var b := t * mi.get_aabb()
		all = b if first else all.merge(b)
		if first or b.size.x > wing.size.x:
			wing = b
		first = false
	return {all = all, wing = wing}


## A self-luminous point (render/world/light_sprite.gdshader) with the current exposure.
static func sprite(name: String, color: Color, position: Vector3, size_m: float, radiance := LED_RADIANCE,
		flash := Vector4(1.0, 0.0, 0.0, 0.0), min_px := NAV_MIN_PX, display_cap := NAV_DISPLAY_CAP) -> MeshInstance3D:
	Exposure.register() # before the shader compiles
	var material := ShaderMaterial.new()
	material.shader = SPRITE_SHADER
	material.set_shader_parameter("light_color", color)
	material.set_shader_parameter("radiance", radiance)
	material.set_shader_parameter("size_m", size_m)
	material.set_shader_parameter("rad_per_px", deg_to_rad(Spec.CAMERA.fov_deg) / 720.0)
	material.set_shader_parameter("flash", flash)
	material.set_shader_parameter("min_px", min_px)
	material.set_shader_parameter("display_cap", display_cap)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = quad
	mi.position = position
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16.0 # the billboard grows with distance
	return mi


## Adds the kit under the airplane's root (a child named "NightKit") and returns it.
static func attach(root: Node3D) -> Node3D:
	var kit := Node3D.new()
	kit.name = "NightKit"
	var b := bounds(root)
	var all: AABB = b.all
	var wing: AABB = b.wing
	var tip_y := wing.position.y + wing.size.y * 0.5
	var tip_z := wing.position.z + wing.size.z * 0.5
	kit.add_child(sprite("nav_left", Color(1.0, 0.06, 0.04), Vector3(wing.position.x - 0.01, tip_y, tip_z), NAV_SIZE_M))
	kit.add_child(sprite("nav_right", Color(0.08, 1.0, 0.25), Vector3(wing.end.x + 0.01, tip_y, tip_z), NAV_SIZE_M))
	kit.add_child(sprite("nav_tail", Color(1.0, 1.0, 1.0), Vector3(0.0, all.position.y + all.size.y * 0.6, all.end.z + 0.01), NAV_SIZE_M))
	var strobe_z := wing.position.z + wing.size.z * 0.75
	kit.add_child(sprite("strobe_left", Color(1.0, 1.0, 1.0), Vector3(wing.position.x - 0.01, tip_y, strobe_z), NAV_SIZE_M * 1.4, LED_RADIANCE, STROBE))
	kit.add_child(sprite("strobe_right", Color(1.0, 1.0, 1.0), Vector3(wing.end.x + 0.01, tip_y, strobe_z), NAV_SIZE_M * 1.4, LED_RADIANCE, STROBE))
	var landing := SpotLight3D.new()
	landing.name = "landing_light"
	landing.position = Vector3(0.0, wing.position.y, wing.position.z)
	landing.rotation = Vector3(deg_to_rad(-6.0), 0.0, 0.0) # aimed a little down from the nose (−z)
	landing.light_energy = LANDING_ENERGY
	landing.spot_range = LANDING_RANGE_M
	landing.spot_angle = LANDING_ANGLE_DEG
	landing.light_color = Color("#fff4e0")
	landing.shadow_enabled = false
	kit.add_child(landing)
	root.add_child(kit)
	return kit
