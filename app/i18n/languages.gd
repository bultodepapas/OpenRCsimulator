## UI-01e: small shared locale registry; safe to preload before the application shell.
extends RefCounted

const NAMES := {
	"en": "English",
	"es": "Español",
	"zh_Hans": "简体中文",
	"pt_BR": "Português (Brasil)",
	"de": "Deutsch",
	"fr": "Français",
	"it": "Italiano",
	"ru": "Русский",
	"ja": "日本語",
}


static func supported_locale(locale: String) -> String:
	var normalized: String = TranslationServer.standardize_locale(locale)
	for code: String in NAMES:
		if normalized == code or normalized.begins_with(code + "_"):
			return code
	return "en"
