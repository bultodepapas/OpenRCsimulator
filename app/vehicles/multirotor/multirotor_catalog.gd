## DR-36a: the experimental FPV quad entry and its command-line route. One physical configuration. It is deliberately
## not an entry of the fixed-wing aircraft catalog (that would route it through airplane trim, preview and Workshop
## code); Home lists it in its vehicle catalog (app_state/vehicle_roster.gd, UI-39) and AppRoot starts it in the
## exclusive activity slot.
extends RefCounted

const ID := "openrc-fpv5-x1"
const DATA_PATH := "res://data/multirotors/openrc-fpv5-x1.json"
const DISPLAY_NAME := "FPV quad 5\" (experimental)"
const VEHICLE := "multirotor"
const ARGUMENT := "--multirotor="


static func contains(id: String) -> bool:
	return id == ID


## Reads the direct route from the user arguments. {requested: false} when no argument names the multirotor;
## otherwise {requested, ok, id, error}. The route takes exactly one user argument, `--multirotor=<id>`.
static func route_from_args(args: PackedStringArray) -> Dictionary:
	var requested := false
	for arg: String in args:
		if arg.begins_with("--multirotor"):
			requested = true
	if not requested:
		return {requested = false, ok = false, id = "", error = ""}
	if args.size() != 1 or not args[0].begins_with(ARGUMENT):
		return {requested = true, ok = false, id = "",
			error = "The FPV quad route accepts exactly one %s<id> option (valid id: %s)" % [ARGUMENT, ID]}
	var id := args[0].trim_prefix(ARGUMENT)
	if not contains(id):
		return {requested = true, ok = false, id = id, error = "Unknown multirotor '%s'; the valid id is %s" % [id, ID]}
	return {requested = true, ok = true, id = id, error = ""}
