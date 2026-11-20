extends RefCounted
## Single owner of the engine's per-viewport render-time measurement flag (VQ-01c; graphics audit F02).
##
## `RenderingServer.viewport_set_measure_render_time` is one boolean per viewport RID. Several diagnostic consumers
## can observe the same viewport at once: Main's `--frame-diagnostics`, the GOD TEST driver, the debug bridge's
## RenderProbe and its ablations. Before this owner each wrote the flag directly, so the first consumer to stop
## switched GPU timing off under the others. Consumers now hold opaque leases: the flag turns on with the first
## live lease on a viewport and off only when the last one is released.
##
## A viewport freed while leased is retired without writing to its stale RID, and its tokens die. If the engine later
## reuses that RID for a new viewport, the new viewport starts a fresh entry that old tokens cannot release.
## Releasing is idempotent. Main thread only, like the RenderingServer viewport calls it wraps. The owner cannot see direct
## writes by standalone capture tools that bypass it; those tools own their whole process.

## Viewport RID -> {ref: WeakRef, tokens: {token: owner label}}.
static var _viewports: Dictionary = {}
## Live token -> viewport RID. Retiring a viewport erases its tokens here.
static var _leases: Dictionary = {}
static var _next_token: int = 1
## Test seam: replaces the RenderingServer write when valid; receives (rid: RID, enabled: bool).
static var _setter: Callable = Callable()


## Takes a lease on the viewport's render-time measurement. Returns a positive token, or 0 when the viewport is not
## valid or has no render RID. The flag is written only when this is the viewport's first live lease.
static func acquire(viewport: Viewport, owner: String = "") -> int:
	if viewport == null or not is_instance_valid(viewport):
		return 0
	var rid: RID = viewport.get_viewport_rid()
	if not rid.is_valid():
		return 0
	_prune_freed()
	var entry: Dictionary = _viewports.get(rid, {})
	if not entry.is_empty() and entry.ref.get_ref() != viewport:
		_retire(rid)
		entry = {}
	if entry.is_empty():
		entry = {ref = weakref(viewport), tokens = {}}
		_viewports[rid] = entry
	var token: int = _next_token
	_next_token += 1
	var first: bool = entry.tokens.is_empty()
	entry.tokens[token] = owner
	_leases[token] = rid
	if first:
		_write(rid, true)
	return token


## Releases one lease. Returns true when the token was live. The last live lease on a still-valid viewport turns its
## measurement off; a freed viewport is forgotten without touching its RID.
static func release(token: int) -> bool:
	if not _leases.has(token):
		return false
	var rid: RID = _leases[token]
	_leases.erase(token)
	var entry: Dictionary = _viewports.get(rid, {})
	if entry.is_empty():
		return true
	entry.tokens.erase(token)
	if not entry.tokens.is_empty():
		return true
	_viewports.erase(rid)
	var viewport: Object = entry.ref.get_ref()
	if viewport != null and is_instance_valid(viewport) and (viewport as Viewport).get_viewport_rid() == rid:
		_write(rid, false)
	return true


## True while the token is a live lease on a viewport that has not been freed.
static func is_held(token: int) -> bool:
	if not _leases.has(token):
		return false
	var entry: Dictionary = _viewports.get(_leases[token], {})
	if entry.is_empty():
		return false
	var viewport: Object = entry.ref.get_ref()
	return viewport != null and is_instance_valid(viewport)


## Number of live leases on the viewport (0 when it is not measured through this owner).
static func holders(viewport: Viewport) -> int:
	if viewport == null or not is_instance_valid(viewport):
		return 0
	var entry: Dictionary = _viewports.get(viewport.get_viewport_rid(), {})
	if entry.is_empty() or entry.ref.get_ref() != viewport:
		return 0
	return entry.tokens.size()


## Owner labels of the live leases on the viewport, sorted, for diagnostics metadata.
static func owners(viewport: Viewport) -> Array[String]:
	var result: Array[String] = []
	if holders(viewport) == 0:
		return result
	for label: Variant in _viewports[viewport.get_viewport_rid()].tokens.values():
		result.append(str(label))
	result.sort()
	return result


## Test seam. Pass an invalid Callable to restore the RenderingServer write.
static func set_setter_for_tests(setter: Callable) -> void:
	_setter = setter


## Test seam: forgets every lease without writing to any viewport.
static func reset_for_tests() -> void:
	_viewports.clear()
	_leases.clear()
	_setter = Callable()


static func _retire(rid: RID) -> void:
	var entry: Dictionary = _viewports.get(rid, {})
	for token: Variant in entry.get("tokens", {}).keys():
		_leases.erase(token)
	_viewports.erase(rid)


static func _prune_freed() -> void:
	var stale: Array[RID] = []
	for rid: RID in _viewports.keys():
		var viewport: Object = _viewports[rid].ref.get_ref()
		if viewport == null or not is_instance_valid(viewport):
			stale.append(rid)
	for rid: RID in stale:
		_retire(rid)


static func _write(rid: RID, enabled: bool) -> void:
	if _setter.is_valid():
		_setter.call(rid, enabled)
	else:
		RenderingServer.viewport_set_measure_render_time(rid, enabled)
