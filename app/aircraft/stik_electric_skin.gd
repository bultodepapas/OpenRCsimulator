# Electric Stik paint identity is independent of the shared glow Stik family.
extends RefCounted

const Registry := preload("res://aircraft/model_registry.gd")
const SharedPaint := preload("res://aircraft/procedural_skin.gd")
const FAMILY := "stik-electric-6s"
const REVISION := "openrc-stik-electric-paint-v1"
const SCRIPT_PATH := "res://aircraft/stik_electric_skin.gd"


static func identity(family: String) -> String:
	if family != FAMILY: return ""
	var described: Dictionary = Registry.describe(family)
	if not described.get("ok", false): return ""
	var proofs: Dictionary = Registry._read_package_proofs()
	if not proofs.get("ok", false): return ""
	var files: Dictionary = proofs.files
	var electric_hash: String = SharedPaint._source_hash(SCRIPT_PATH, files)
	var shared_hash: String = SharedPaint._source_hash(SharedPaint.SCRIPT_PATH, files)
	if electric_hash.is_empty() or shared_hash.is_empty(): return ""
	return (REVISION + "\n" + family + "\n" + str(described.manifest_sha256) + "\n" + electric_hash + "\n" + shared_hash + "\n").sha256_text()


static func prepare(family: String, root: Node3D) -> Dictionary:
	if family != FAMILY:
		return {ok = false, errors = PackedStringArray(["Unknown electric Stik paint family."])}
	return SharedPaint.prepare(SharedPaint.STIK, root)


static func paint(material: Material, record: Dictionary, texture: Texture2D) -> Material:
	return SharedPaint.paint(material, record, texture)
