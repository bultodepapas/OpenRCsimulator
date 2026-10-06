# Editor side of the build identity (MENU-PLAN UI-04a): registers the export plugin. Only the editor runs it (the
# exporter is the editor); the scripts never ship (export presets exclude addons/*).
@tool
extends EditorPlugin

var _export := preload("res://addons/build_info/export_plugin.gd").new()


func _enter_tree() -> void:
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
