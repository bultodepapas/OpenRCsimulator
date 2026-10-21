## LU-34 source-geometry allowances per scenery subsystem, shared by test_scenery_build.gd and
## test_landscape_vegetation.gd. Source triangles bound vertex memory and first-load work; they do not
## predict per-frame cost, which tools/scenery/scene_budget.json budgets per view in drawn primitives,
## draw calls and shadow casters. The former single 725,000 non-fleet pool let one subsystem's growth
## (people/cars use 371,573) block unrelated work. Counts follow the scenery tests' existing rule:
## mesh triangles, MultiMesh instances x mesh triangles, full detail before LOD.
extends RefCounted

const Population := preload("res://scenery/population.gd")

## Measured 2026-10-21 (field build) in parentheses; imported subsystems carry generated LODs.
const ALLOWANCES := {
	"population": 380000, # imported people/cars/furniture, generated LODs (371,573)
	"parked_aircraft": 350000, # SC-09-R1 full-detail fleet allowance (273,421)
	"cells": 175000, # merged procedural props, no LODs (168,031)
	"vegetation": 150000, # imported close trees/shrubs, generated LODs (101,167); room for species variety
	"botanical": 90000, # downloaded habitats, generated LODs (63,315 field, 89,655 with lake context)
	"pit_shelters": 13000, # procedural, no LODs (12,096)
	"airfield_detail": 5000, # imported, generated LODs (4,482)
	"other": 8000, # contacts, decals, hedges, woodland edges, motion, roofs (4,220)
}


static func subsystem(node_name: String) -> String:
	match node_name:
		"Population":
			return "population"
		"ParkedAircraft":
			return "parked_aircraft"
		"ImportedVegetationBatches":
			return "vegetation"
		"BotanicalHabitats":
			return "botanical"
		"AirfieldDetail":
			return "airfield_detail"
	if node_name.begins_with("cell_"):
		return "cells"
	if node_name.begins_with("PitShelter_"):
		return "pit_shelters"
	return "other"


static func counts(scenery_root: Node) -> Dictionary:
	var result := {}
	for key: String in ALLOWANCES:
		result[key] = 0
	for child: Node in scenery_root.get_children():
		var key := subsystem(str(child.name))
		result[key] = int(result[key]) + _triangles(child)
	return result


## Empty when every subsystem fits its allowance.
static func failures(scenery_root: Node) -> PackedStringArray:
	var result := PackedStringArray()
	var measured := counts(scenery_root)
	for key: String in ALLOWANCES:
		if int(measured[key]) > int(ALLOWANCES[key]):
			result.append("%s %d > %d" % [key, measured[key], ALLOWANCES[key]])
	return result


static func _triangles(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		count += Population.triangles((node as MeshInstance3D).mesh)
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		var multimesh := (node as MultiMeshInstance3D).multimesh
		count += multimesh.instance_count * Population.triangles(multimesh.mesh)
	for child: Node in node.get_children():
		count += _triangles(child)
	return count
