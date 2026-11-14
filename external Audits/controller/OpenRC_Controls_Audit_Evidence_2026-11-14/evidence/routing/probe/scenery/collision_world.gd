# Disposable audit stub. Collision queries are outside this isolated resume-gate probe.
extends RefCounted
static func _world_header_is_valid(_world: Dictionary) -> bool: return true
static func _proxy_is_valid(_proxy: Dictionary) -> bool: return true
static func nearby(_world: Dictionary, _n: float, _e: float, _d: float, _reach: float) -> Array[Dictionary]: return []
static func _aabb_sphere_overlap(_proxy: Dictionary, _n: float, _e: float, _d: float, _reach: float) -> bool: return false
