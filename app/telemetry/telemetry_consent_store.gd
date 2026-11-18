## TELEM-02: the player's telemetry choice, in its own small file (never in settings.cfg: an older settings
## backup must not restore a grant). It holds the choice and the notice it answered, nothing that identifies the
## player. Loading fails closed: a missing file means "not asked yet"; anything unreadable, foreign or newer
## means "unreadable" (off, not asked again automatically). Saving writes a temporary file, reads it back, then
## replaces the old one; there is no restorable backup, so an interrupted save can only lose the file (the next
## launch asks again) and never bring back an earlier "enabled".
extends RefCounted

const DEFAULT_PATH := "user://telemetry_consent.cfg"
const FORMAT := "openrc-telemetry-consent v1"
const SECTION := "telemetry"
const CHOICES: Array[String] = ["enabled", "disabled"]


## {choice: "unset"|"enabled"|"disabled"|"unreadable", notice: String}
static func load_choice(path := DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"choice": "unset", "notice": ""}
	var text := FileAccess.get_file_as_string(path)
	if text.length() > 4096:
		return {"choice": "unreadable", "notice": ""}
	var file := ConfigFile.new()
	if file.parse(text) != OK or file.get_sections() != PackedStringArray([SECTION]):
		return {"choice": "unreadable", "notice": ""}
	if file.get_section_keys(SECTION) != PackedStringArray(["format", "choice", "notice"]):
		return {"choice": "unreadable", "notice": ""}
	var format: Variant = file.get_value(SECTION, "format")
	var choice: Variant = file.get_value(SECTION, "choice")
	var notice: Variant = file.get_value(SECTION, "notice")
	if format != FORMAT or typeof(choice) != TYPE_STRING or not choice in CHOICES or typeof(notice) != TYPE_STRING \
			or notice.length() > 32:
		return {"choice": "unreadable", "notice": ""}
	return {"choice": choice, "notice": notice}


## OK only when the new choice is durably readable at `path`.
static func save_choice(choice: String, notice: String, path := DEFAULT_PATH) -> Error:
	if not choice in CHOICES or notice.length() > 32:
		return ERR_INVALID_PARAMETER
	# A decline first removes any earlier grant (removal needs only directory rights): if the new file then cannot
	# be written, the next launch finds no choice and asks again instead of loading the old "enabled".
	if choice == "disabled" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var file := ConfigFile.new()
	file.set_value(SECTION, "format", FORMAT)
	file.set_value(SECTION, "choice", choice)
	file.set_value(SECTION, "notice", notice)
	var text := file.encode_to_text()
	var temporary := path + ".tmp"
	var out := FileAccess.open(temporary, FileAccess.WRITE)
	if out == null:
		return FileAccess.get_open_error()
	out.store_string(text)
	out.flush()
	var write_error := out.get_error()
	out.close()
	if write_error != OK or FileAccess.get_file_as_string(temporary) != text:
		DirAccess.remove_absolute(temporary)
		return ERR_FILE_CANT_WRITE if write_error == OK else write_error
	# Godot's Windows rename does not replace an existing file: remove first. A crash between the two steps leaves
	# no choice (asked again), never an older one.
	if FileAccess.file_exists(path):
		var removed := DirAccess.remove_absolute(path)
		if removed != OK:
			DirAccess.remove_absolute(temporary)
			return removed
	var renamed := DirAccess.rename_absolute(temporary, path)
	if renamed != OK:
		DirAccess.remove_absolute(temporary)
		return renamed
	var check := load_choice(path)
	return OK if check.choice == choice and check.notice == notice else ERR_FILE_CORRUPT
