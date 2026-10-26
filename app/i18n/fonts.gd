## UI-01e: add bundled CJK glyphs to the engine font before startup or any screen is built.
## Loading at runtime lets a clean editor import finish before imported font data is needed.
extends Node


func _enter_tree() -> void:
	var chinese: Font = load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	var fallbacks: Array[Font] = ThemeDB.fallback_font.fallbacks
	if chinese not in fallbacks:
		fallbacks.append(chinese)
		ThemeDB.fallback_font.fallbacks = fallbacks
