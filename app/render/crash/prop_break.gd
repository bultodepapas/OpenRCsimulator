# US-V11: what a prop strike leaves of the propeller. A propeller that names its breakable blade meshes (meta
# BREAKS_META) and its broken stubs (meta STUBS_META, hidden while intact) keeps its hub and shows the stubs; any other
# propeller disappears whole, as E3d2 did. While broken the propeller node carries BROKEN_META so the blur
# (render/propeller_blur.gd) keeps the blades hidden. Presentation only: never reads or writes simulation state.
extends RefCounted

const BREAKS_META := "prop_strike_breaks"
const STUBS_META := "prop_strike_reveal"
const BROKEN_META := "blades_broken"


## Breaks the blades of `propeller` (the node itself and its subtree) and returns the records restore() undoes.
static func break_blades(propeller: Node3D) -> Array:
	var parts: Array = [propeller]
	parts.append_array(propeller.find_children("*", "Node3D", true, false))
	if not parts.any(func(n: Node) -> bool: return n.has_meta(BREAKS_META)):
		var whole: Array = [{node = propeller, visible = propeller.visible}]
		propeller.visible = false
		return whole
	var records: Array = []
	for node: Node3D in parts:
		if node.has_meta(BREAKS_META) or node.has_meta(STUBS_META):
			records.append({node = node, visible = node.visible})
			node.visible = node.has_meta(STUBS_META)
	propeller.set_meta(BROKEN_META, true)
	records.append({node = propeller, broken = true})
	return records


## Undoes break_blades(): earlier visibilities come back and the broken flag goes.
static func restore(records: Array) -> void:
	for record: Dictionary in records:
		var node: Variant = record.node
		if not is_instance_valid(node):
			continue
		if record.has("broken"):
			(node as Node3D).remove_meta(BROKEN_META)
		else:
			(node as Node3D).visible = bool(record.visible)
