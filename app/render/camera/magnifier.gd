# CAM-18: magnifier inset (docs/plans/camera-views.md §5.7). A small window at the top of the screen shows the aircraft
# from the pilot's eye, framed large, while the main pilot view keeps its real distance cues: attitude reads in the
# inset, approach and retreat in the main view (CRRCSim's auto model view, PicaSim's zoom inset, RealFlight's
# binoculars). Following PicaSim's "only plane in zoom view", the inset draws only the aircraft's own render layer over
# the sky, so it costs a few draw calls instead of a second scene render in the Compatibility renderer. A tight depth
# range around the aircraft gives it full depth precision. Presentation only; it renders nothing while hidden.
extends CanvasLayer

const PilotCamera := preload("res://render/pilot_camera.gd")
const CameraMath := preload("res://render/camera/camera_math.gd")
const ViewportColor := preload("res://render/viewport_color.gd")

## Render layer the aircraft's meshes join; other code uses 1 << 19 for crash debris (render/crash/wreck.gd).
const LAYER := 1 << 18
const MODES: Array[String] = ["off", "auto", "on"]
## Inset side as a share of the viewport height, and the aircraft span as a share of the inset.
const SIZE_SHARE := 0.22
const FILL := 0.6
## Auto: appears when the aircraft spans less than SHOW_BELOW of the main view's height, leaves above HIDE_ABOVE.
const SHOW_BELOW := 0.04
const HIDE_ABOVE := 0.05
const MARGIN_PX := 12.0
## Godot refuses a Camera3D FOV below 1°, too wide for a distant aircraft. The inset camera therefore stands on the
## pilot's line of sight, at the distance where INSET_FOV_DEG frames the span: the same viewing direction, so the
## same attitude the pilot sees. A closer aircraft is framed from the pilot's eye with a wider FOV.
const INSET_FOV_DEG := 10.0
const MAX_FOV_DEG := 60.0

var mode := "off"
var shown := false # the inset is on screen this frame
var camera: Camera3D
var _viewport: SubViewport
var _container: SubViewportContainer
var _frame: Panel
var _auto_shown := false
var _tagged: Node = null


func _ready() -> void:
	layer = 4
	_frame = Panel.new()
	_frame.name = "MagnifierFrame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(1, 1, 1, 0.55)
	style.set_border_width_all(2)
	_frame.add_theme_stylebox_override("panel", style)
	add_child(_frame)
	_container = SubViewportContainer.new()
	_container.name = "Magnifier"
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	ViewportColor.configure(_viewport)
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.audio_listener_enable_3d = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_container.add_child(_viewport)
	camera = Camera3D.new()
	camera.cull_mask = LAYER
	_viewport.add_child(camera)
	camera.current = true
	_set_visible(false)


## Puts every mesh under `root` on the magnifier's layer too; the main camera still sees all layers.
static func tag(root: Node) -> void:
	if root == null:
		return
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers |= LAYER
	for child in root.get_children():
		tag(child)


## Whether the inset shows for an aircraft spanning `share` of the main view's height (auto keeps its last answer
## between SHOW_BELOW and HIDE_ABOVE, so it never flickers at the threshold).
func wants(share: float, active: bool) -> bool:
	if share < SHOW_BELOW:
		_auto_shown = true
	elif share > HIDE_ABOVE:
		_auto_shown = false
	return active and (mode == "on" or (mode == "auto" and _auto_shown))


## main_camera: the pilot view this frame; target: the aircraft's CG; span: its span (m); root: its model root (tagged
## once per model); active: the pilot view is flying an intact aircraft. Call after the rig placed the main camera.
## The inset camera stands on the pilot's line of sight, framing the span at FILL of the inset height.
func update(main_camera: Camera3D, target: Vector3, span: float, root: Node, active: bool) -> void:
	if root != _tagged:
		tag(root)
		_tagged = root
	var eye := main_camera.global_position
	var distance := maxf(eye.distance_to(target), 0.1)
	var share := PilotCamera.projected_px(span, distance, main_camera.fov, 1.0)
	_set_visible(wants(share, active))
	if not shown:
		return
	var height := float(main_camera.get_viewport().get_visible_rect().size.y) if main_camera.is_inside_tree() else 1080.0
	var side := roundf(height * SIZE_SHARE)
	var width := float(main_camera.get_viewport().get_visible_rect().size.x) if main_camera.is_inside_tree() else 1920.0
	_container.position = Vector2(roundf((width - side) * 0.5), MARGIN_PX)
	_container.size = Vector2(side, side)
	_frame.position = _container.position - Vector2(2, 2)
	_frame.size = _container.size + Vector2(4, 4)
	var frame := minf(distance, span / (2.0 * FILL * tan(deg_to_rad(INSET_FOV_DEG) * 0.5)))
	var at := target - (target - eye) / distance * frame
	camera.global_transform = Transform3D(CameraMath.look_basis(at, target), at)
	camera.fov = minf(rad_to_deg(2.0 * atan(span / (2.0 * frame * FILL))), MAX_FOV_DEG)
	# Only the aircraft is drawn: a depth range of a few spans around it.
	camera.near = maxf(0.05, frame - 2.0 * span)
	camera.far = frame + 2.0 * span


func _set_visible(on: bool) -> void:
	shown = on
	visible = on
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
