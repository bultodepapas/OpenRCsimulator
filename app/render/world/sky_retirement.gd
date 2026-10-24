## GLES3 keeps a dirty Sky queued until rendering updates it. Preserve its resource
## through that draw, or release it when the scene tree shuts down without a draw.
extends RefCounted

class PendingSky extends RefCounted:
	var sky: Sky
	var tree_root: WeakRef

	func release(_keep_alive: RefCounted) -> void:
		# The bound reference keeps this guard alive; each guard has a distinct
		# receiver so several Skies can retire during the same frame.
		var callback := release.bind(self)
		if RenderingServer.frame_post_draw.is_connected(callback):
			RenderingServer.frame_post_draw.disconnect(callback)
		var root: Node = tree_root.get_ref()
		if is_instance_valid(root) and root.tree_exiting.is_connected(callback):
			root.tree_exiting.disconnect(callback)
		sky = null


static func retain_until_draw(sky: Sky) -> void:
	if sky == null or DisplayServer.get_name() == "headless" \
			or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		return
	var tree := Engine.get_main_loop() as SceneTree
	# During final tree destruction there will be no subsequent renderer update.
	if tree == null or tree.root == null or not tree.root.is_inside_tree():
		return
	var pending := PendingSky.new()
	pending.sky = sky
	pending.tree_root = weakref(tree.root)
	var release := pending.release.bind(pending)
	RenderingServer.frame_post_draw.connect(release, CONNECT_ONE_SHOT)
	tree.root.tree_exiting.connect(release, CONNECT_ONE_SHOT)


