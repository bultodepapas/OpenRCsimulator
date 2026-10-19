## SUN-02/03/04 (docs/plans/sun.md; was LU-04): the optics of looking toward the sun.
## The pilot view is an eye: the CIE disability-glare veil over the sky and aureole behind the model, with the ciliary
## corona (pass 0, sun_glare.gdshader), and the patches the sun's image bleaches on the retina, which lose all detail
## while the model crosses the sun and for seconds after (a canvas overlay under the interface, sun_afterimage.gdshader).
## Chase, orbit and close-up cameras are lenses: a smaller veil and a starburst (pass 0), ghosts (pass 1), no bleaching.
## Reads the actual sky material and exposure each frame, so FW flow, TOD edits and weather cannot leave stale solar
## inputs; never writes the sky except LU-04's one-time disc cloud occlusion. Math and constants:
## render/sun/sun_optics.gd. The glare source is generic: see source() for adding another one (FW-MOON-08 moon glare).
extends MeshInstance3D

const Options := preload("res://render/landscape_upgrade/options.gd")
const GLARE_SHADER := preload("res://render/landscape_upgrade/sun_glare.gdshader")
const AFTERIMAGE_SHADER := preload("res://render/sun/sun_afterimage.gdshader")
const SunOptics := preload("res://render/sun/sun_optics.gd")
const SkyMirror := preload("res://render/sun/sky_mirror.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Atmosphere := preload("res://render/atmosphere.gd")

## The sky uniforms SkyMirror.transmission reads.
const CLOUD_UNIFORMS: Array[StringName] = [&"layered_appearance", &"cloud_coverage", &"cloud_offset", &"cloud_scale",
	&"cloud_seed", &"cluster_strength", &"cirrus_strength", &"cirrus_coverage", &"appearance_layer_count",
	&"appearance_layer_parameters", &"appearance_layer_motion", &"appearance_layer_seeds", &"appearance_cloud_density"]
## Camera metadata naming its optics: "eye" (the pilot; the default) or "lens" (camera_rig.gd sets it per view).
const OPTICS_META := &"openrc_optics"
## The afterimage overlay's canvas layer: above the 3D image, below every interface layer (HUD 1, notices 20+).
const AFTERIMAGE_LAYER := -10

var environment: Environment
var intensity := 1.0
var _material: ShaderMaterial
## Pass 1, drawn over the veil: the lens's ghosts (sun_glare.gdshader pass_kind 1).
var _secondary: MeshInstance3D
var _secondary_material: ShaderMaterial
var _veil_mesh: QuadMesh
## The eye's bleached patches: their canvas overlay, the state (SunOptics.afterimage_step) and the shader clock it last
## advanced at (−1 = rested).
var _after_layer: CanvasLayer
var _after_material: ShaderMaterial
var _afterimage: Dictionary = SunOptics.afterimage_rest()
var _after_clock := -1.0
## SkyMirror.transmission is recomputed only when its inputs change (cloud offsets move at Spec cloud_update_s).
var _cloud_key: Array = []
var _cloud_transmission := 1.0

static func attach(parent: Node, env: Environment) -> MeshInstance3D:
	var script: GDScript = load("res://render/landscape_upgrade/sun_glare.gd")
	var node: MeshInstance3D = script.new()
	node.name = "SunGlare"
	node.environment = env
	node.intensity = Options.glare_strength()
	parent.add_child(node)
	return node

func _ready() -> void:
	_material = _pass_material(0)
	_veil_mesh = _quad()
	mesh = _veil_mesh
	material_override = _material
	_configure_overlay(self)
	_secondary = MeshInstance3D.new()
	_secondary.name = "Secondary"
	_secondary_material = _pass_material(1)
	_secondary.mesh = _veil_mesh
	_secondary.material_override = _secondary_material
	_configure_overlay(_secondary)
	add_child(_secondary)
	_after_layer = CanvasLayer.new()
	_after_layer.name = "Afterimage"
	_after_layer.layer = AFTERIMAGE_LAYER
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_after_material = ShaderMaterial.new()
	_after_material.shader = AFTERIMAGE_SHADER
	_after_material.set_shader_parameter("tint", SunOptics.AFTER_TINT)
	rect.material = _after_material
	_after_layer.add_child(rect)
	_after_layer.visible = false
	add_child(_after_layer)
	_process(0.0)


static func _quad() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	return quad


static func _pass_material(kind: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLARE_SHADER
	material.render_priority = 110 + kind
	material.set_shader_parameter("pass_kind", kind)
	material.set_shader_parameter("kappa", SunOptics.KAPPA)
	material.set_shader_parameter("age_factor", SunOptics.age_factor(SunOptics.OBSERVER_AGE))
	material.set_shader_parameter("pigment", SunOptics.OBSERVER_PIGMENT)
	material.set_shader_parameter("veil_cut", SunOptics.glare_spread(SunOptics.VEIL_CUT_DEG))
	material.set_shader_parameter("veil_cut_deg", SunOptics.VEIL_CUT_DEG)
	material.set_shader_parameter("lens_veil", SunOptics.LENS_VEIL)
	material.set_shader_parameter("aureole_core", SunOptics.AUREOLE_BACKGROUND_CORE_DEG)
	return material


static func _configure_overlay(node: MeshInstance3D) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.ignore_occlusion_culling = true
	node.custom_aabb = AABB(Vector3(-100000, -100000, -100000), Vector3(200000, 200000, 200000))


## The glare source the sky shows now: {dir (render, toward the apparent disc), radius (rad), disc_lin (the disc's mean
## radiance, pre-exposure), illuminance (relative to the calibrated day sun: drives bleaching), e_over_b (its
## illuminance over the sky's luminance around it, sr: drives the veil)}; zeros when the disc is off. The sky's
## sun_lin carries Atmosphere.shadow_compensation (Compatibility's shadowed-light correction), divided out here. Another
## source (the moon, FW-MOON-08) returns the same keys: its absolute illuminance is ~10⁻⁶ of the sun's, so it veils
## a dark-adapted view but never bleaches.
static func source(sky: ShaderMaterial, shadow_compensation := 1.0) -> Dictionary:
	var occluded: bool = sky.get_shader_parameter("disc_cloud_occlusion") == true
	var dir: Variant = sky.get_shader_parameter("disc_dir") if occluded else sky.get_shader_parameter("sun_dir")
	var sun_lin: Variant = sky.get_shader_parameter("sun_lin")
	var disc: Variant = sky.get_shader_parameter("sun_disc")
	var radius: Variant = sky.get_shader_parameter("sun_radius")
	if not dir is Vector3 or not sun_lin is Vector3 or (dir as Vector3).length_squared() < 1e-12:
		return {dir = Vector3.UP, radius = 0.0, disc_lin = Vector3.ZERO, illuminance = 0.0, e_over_b = 0.0}
	var d: float = clampf(float(disc) if disc != null else 1.0, 0.0, 1.0)
	var toward := (dir as Vector3).normalized()
	var light := (sun_lin as Vector3) / maxf(shadow_compensation, 1e-6)
	return {dir = toward, radius = float(radius) if radius != null else 0.0046251,
		disc_lin = (sun_lin as Vector3) * SunOptics.DISC_RADIANCE_FACTOR,
		illuminance = SunOptics.illuminance_scale(light) * d,
		e_over_b = SunOptics.illuminance_over_background(light, SkyMirror.background_luminance(sky, toward)) * d}


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or environment == null or environment.sky == null:
		_hide()
		return
	var sky := environment.sky.sky_material as ShaderMaterial
	if sky == null:
		_hide()
		return
	# LU-04: the visible solar disc and the glare share cloud attenuation and apparent position.
	if not sky.get_shader_parameter("disc_cloud_occlusion"):
		sky.set_shader_parameter("disc_cloud_occlusion", true)
	var src := source(sky, Atmosphere.shadow_compensation())
	var dir: Vector3 = src.dir
	var clouds := _clouds(sky, dir)
	var prior := SunOptics.horizon_prior(asin(clampf(dir.y, -1.0, 1.0)))
	var strength := intensity * float(src.e_over_b) * clouds
	var dose := intensity * float(src.illuminance) * clouds * prior
	var optics := str(camera.get_meta(OPTICS_META, "eye"))
	var lens := optics == "lens"
	var perspective := camera.projection == Camera3D.PROJECTION_PERSPECTIVE
	var eye := perspective and not lens
	var sun_view := camera.global_transform.basis.orthonormalized().inverse() * dir
	_advance_afterimage(sun_view, dose if eye else 0.0)
	var veil := perspective and strength > 0.0 and dir.y > -0.02 and veil_reaches_view(camera, dir)
	visible = veil
	_secondary.visible = veil and lens
	_after_layer.visible = eye and _show_afterimage(camera, sun_view, dose)
	set_meta("strength", strength * prior)
	set_meta("illuminance", dose)
	set_meta("afterimage", SunOptics.afterimage_dose(_afterimage))
	set_meta("optics", optics)
	if not veil:
		return
	var values := {source_dir = dir, source_radius = float(src.radius), source_lin = src.disc_lin,
		source_scale = strength, horizon_prior = prior, far_distance = camera.far,
		aureole_coeff = SunOptics.aureole_background_coeff(rad_to_deg(asin(clampf(dir.y, -1.0, 1.0))), Atmosphere.aureole_aerosol_factor()),
		exposure = maxf(environment.tonemap_exposure, 1e-6), optics = 1 if lens else 0}
	set_meta("aureole_coeff", values.aureole_coeff)
	for key: String in values:
		_material.set_shader_parameter(key, values[key])
		if lens:
			_secondary_material.set_shader_parameter(key, values[key])
	var size := get_viewport().get_visible_rect().size
	if size.x > 0.0 and size.y > 0.0 and not camera.is_position_behind(camera.global_position + dir * 1000.0):
		set_meta("solar_uv", camera.unproject_position(camera.global_position + dir * 1000.0) / size)


func _hide() -> void:
	visible = false
	if _after_layer != null:
		_after_layer.visible = false


func _clouds(sky: ShaderMaterial, dir: Vector3) -> float:
	var key := [dir.snapped(Vector3.ONE * 1e-5)]
	for uniform_name: StringName in CLOUD_UNIFORMS:
		key.append(sky.get_shader_parameter(uniform_name))
	if key != _cloud_key:
		_cloud_key = key
		_cloud_transmission = SkyMirror.transmission(sky, dir)
	return _cloud_transmission


## Whether any pixel can lie within SunOptics.VEIL_CUT_DEG of `dir` (else the pass would draw nothing).
static func veil_reaches_view(camera: Camera3D, dir: Vector3) -> bool:
	var size := camera.get_viewport().get_visible_rect().size if camera.is_inside_tree() else Vector2(16.0, 9.0)
	var aspect := size.x / size.y if size.y > 0.0 else 1.0
	var long_side := maxf(aspect, 1.0 / aspect)
	var half_diagonal := atan(tan(deg_to_rad(camera.fov) * 0.5) * sqrt(1.0 + long_side * long_side))
	var basis := camera.global_transform.basis if camera.is_inside_tree() else camera.transform.basis
	var forward := -basis.z.normalized()
	return forward.angle_to(dir) < half_diagonal + deg_to_rad(SunOptics.VEIL_CUT_DEG)


## Places the bleached patches on screen (fixed to the view: the camera is the pilot's gaze). Returns whether any shows.
func _show_afterimage(camera: Camera3D, sun_view: Vector3, dose: float) -> bool:
	var size := get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	var alphas := SunOptics.afterimage_alphas(_afterimage)
	var patches: Array = _afterimage.patches
	var tan_half_height := SunOptics.view_tan_half_height(camera.fov, camera.keep_aspect == Camera3D.KEEP_WIDTH, size.x / size.y)
	var packed := PackedVector4Array()
	var lit := PackedFloat32Array()
	var any := false
	for i in SunOptics.AFTER_PATCHES:
		var patch: Dictionary = patches[i] if i < patches.size() else {}
		var d: Vector3 = patch.get("dir", Vector3(0.0, 0.0, -1.0))
		var radius := float(patch.get("radius", SunOptics.AFTER_BASE_RADIUS))
		var alpha := alphas[i] if d.z < -0.05 else 0.0
		# View space to screen uv (top-left origin, as SCREEN_UV): x right, y up in view space.
		var uv := Vector2(0.5 + d.x / -d.z / tan_half_height * 0.5 * size.y / size.x, 0.5 - d.y / -d.z / tan_half_height * 0.5) \
			if d.z < -0.05 else Vector2(-10.0, -10.0)
		packed.append(Vector4(uv.x, uv.y, tan(radius) / tan_half_height * 0.5, alpha))
		lit.append(SunOptics.afterimage_lit(d, radius, sun_view, dose))
		any = any or alpha > 0.002
	_after_material.set_shader_parameter("patches", packed)
	_after_material.set_shader_parameter("lit", lit)
	return any


## The bleached patches follow simulation time (ShaderClock: pauses and replays hold them); a jump starts the eye
## rested. `e`: the sun's illuminance reaching the eye relative to the day sun (× clouds, skyline prior and strength),
## weighted by the eye's field.
func _advance_afterimage(sun_view: Vector3, e: float) -> void:
	var now := ShaderClock.last_clock
	if _after_clock < 0.0:
		_after_clock = now
		return
	var dt := fposmod(now - _after_clock, ShaderClock.WRAP_S)
	_after_clock = now
	if dt <= 0.0:
		return
	if dt > SunOptics.AFTER_MAX_STEP_S:
		_afterimage = SunOptics.afterimage_rest()
		return
	var gaze := acos(clampf(-sun_view.z, -1.0, 1.0))
	_afterimage = SunOptics.afterimage_step(_afterimage, dt, e * SunOptics.field_weight(gaze), sun_view)


## Starts the eye rested (a restarted flight, a camera cut that should not carry the patch).
func rest() -> void:
	_afterimage = SunOptics.afterimage_rest()
	_after_clock = -1.0
