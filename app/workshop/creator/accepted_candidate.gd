extends RefCounted
## Trusted owner of one compiled Aircraft Creator candidate (AC-06).
##
## compiler.gd creates a sealed instance after the exact emitted bytes passed the flight loader and the
## package domain. A dictionary with `ok = true` is never a candidate: consumers call is_accepted().
## This is an ownership convention, not a security boundary: GDScript cannot hide a constructor or a
## member, so in-process code could seal an instance with a model that does not come from its bytes.
## The seal only checks that bytes, hash and identity agree. What makes a flight trustworthy is that
## `trial.gd` never flies this object's model: it reloads the aircraft from `raw_bytes()` and verifies
## that again before every use. Accessors return copies.

const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")

const QUALIFICATION := "experimental"

var _sealed := false
var _aircraft_id := ""
var _raw_bytes := PackedByteArray()
var _raw_sha256 := ""
var _definition_sha256 := ""
var _flight_data: Dictionary = {}
var _summary: Dictionary = {}


## True only for a sealed instance of this class.
static func is_accepted(value: Variant) -> bool:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return false
	var script: Script = load("res://workshop/creator/accepted_candidate.gd")
	return is_instance_of(value, script) and bool(value.get("_sealed"))


## Compiler-only. Returns false and leaves the instance empty unless the parts agree with each other.
func _seal(aircraft: String, raw: PackedByteArray, definition_hash: String, loaded: Dictionary, read_out: Dictionary) -> bool:
	if _sealed or raw.is_empty() or not CreatorBytes.is_sha256(definition_hash) or not loaded.get("ok", false):
		return false
	var identity: Variant = loaded.get("input_identity")
	var model: Variant = loaded.get("model")
	var digest := CreatorBytes.sha256(raw)
	if typeof(identity) != TYPE_DICTIONARY or typeof(model) != TYPE_DICTIONARY \
			or identity.get("format") != AircraftData.FORMAT or identity.get("sha256") != digest \
			or aircraft.is_empty() or model.get("id") != aircraft:
		return false
	_aircraft_id = aircraft
	_raw_bytes = raw.duplicate()
	_raw_sha256 = digest
	_definition_sha256 = definition_hash
	_flight_data = loaded.duplicate(true)
	_summary = read_out.duplicate(true)
	_sealed = true
	return true


## "user-aircraft-<uuid>".
func aircraft_id() -> String:
	return _aircraft_id


## The exact emitted openrc-aircraft v2 bytes.
func raw_bytes() -> PackedByteArray:
	return _raw_bytes.duplicate()


func raw_sha256() -> String:
	return _raw_sha256


func definition_sha256() -> String:
	return _definition_sha256


## Deep copy of the loader result for these bytes: FlightSession.setup("", aircraft_id(), flight_data()).
func flight_data() -> Dictionary:
	return _flight_data.duplicate(true)


## The compiler's read-out (as Compiler.summarize) plus derived inertia and identities.
func summary() -> Dictionary:
	return _summary.duplicate(true)


## Estimated package; its numerical domain is not qualified yet.
func qualification() -> String:
	return QUALIFICATION if _sealed else ""
