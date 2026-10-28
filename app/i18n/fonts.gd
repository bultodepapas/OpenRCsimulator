## UI-01e/k: preserve Latin metrics and use the matching regional CJK glyph forms.
extends Node

static var _chinese: Font
static var _japanese: Font
static var _language_names: FontVariation


static func chinese_font() -> Font:
	if _chinese == null:
		_chinese = load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	return _chinese


static func japanese_font() -> Font:
	if _japanese == null:
		_japanese = load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	return _japanese


static func language_names_font() -> Font:
	if _language_names == null:
		_language_names = FontVariation.new()
		# Shallow copies share atlas images, so later glyph insertions can corrupt the UI font.
		_language_names.base_font = ThemeDB.fallback_font.duplicate(true)
		_language_names.base_font.fallbacks = []
		_language_names.fallbacks = [japanese_font(), chinese_font()]
	return _language_names


func _enter_tree() -> void:
	_update_fallback()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_update_fallback()


func _update_fallback() -> void:
	var chinese: Font = chinese_font()
	var japanese: Font = japanese_font()
	var fallbacks: Array[Font] = ThemeDB.fallback_font.fallbacks
	# These two fallbacks are mutually exclusive: shared kanji need locale-specific forms.
	fallbacks.erase(chinese)
	fallbacks.erase(japanese)
	var locale: String = TranslationServer.get_locale()
	if locale.begins_with("zh"):
		fallbacks.append(chinese)
	elif locale.begins_with("ja"):
		fallbacks.append(japanese)
	ThemeDB.fallback_font.fallbacks = fallbacks
