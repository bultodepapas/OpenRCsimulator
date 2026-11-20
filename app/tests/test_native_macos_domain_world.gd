## Portable early warning for the macOS native physics default (DT-MAC-04n-R1).
## `sim/native_macos_domain.gd` pins the macOS ARM64 SHA-256 identity of the stock
## collision world. That identity hashes trigonometric results, so each platform
## computes a different value. This test pins what every platform reproduces: the
## proxy count and a millimetre-quantized geometry fingerprint. A collision-world
## change therefore fails here on Linux and Windows, instead of silently moving
## Mac flights to the reference evaluator.
extends SceneTree

const Domain := preload("res://sim/native_macos_domain.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")

## Renew together with Domain.STOCK_WORLD and Domain.STOCK_WORLD_PROXIES; see RENEWAL.
const STOCK_WORLD_PORTABLE_FINGERPRINT := "2cfce9a5108d593befbfb58f4b57cbf97a48859458989a576468e72dad741ad2"
const RENEWAL := "the stock collision world changed. Renew Domain.STOCK_WORLD from the macOS CI line " \
	+ "MACOS_DOMAIN_STOCK_GUARD_DIAGNOSTIC (world_identity), Domain.STOCK_WORLD_PROXIES and this test's " \
	+ "fingerprint, following docs/plans/apple-silicon-performance.md (DT-MAC-04n-R1)"
const TEXT_FIELDS := ["id", "kind", "part", "shape", "response_class", "damage_id", "damage_profile"]
const LENGTH_FIELDS := ["north", "east", "down", "radius", "half_length", "half_x", "half_down", "half_z",
	"bounds_north_min", "bounds_north_max", "bounds_east_min", "bounds_east_max", "bounds_down_min", "bounds_down_max"]
const UNIT_FIELDS := ["sin_heading", "cos_heading"]
## Authored inputs include many exact decimal and float32 binary fractions. A decimal or
## power-of-two step puts some of them exactly on a rounding edge, so the steps are
## deliberately irrational: about 0.95 mm and 0.95e-6.
const LENGTH_QUANTUM := 1000.0 * PI / 3.0
const UNIT_QUANTUM := 1000000.0 * PI / 3.0
## Platform math differs by a few ulps. A value within about 450 ulps of a rounding edge
## could round differently elsewhere, so it fails as not portable: change both steps
## slightly and renew the fingerprint.
const EDGE_MARGIN := 1.0e-13

var checks := 0
var failures := 0


func _initialize() -> void:
	_run()
	print("native macOS domain world: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, (": " + detail) if not detail.is_empty() else "")


## Null when a value is malformed or too close to a rounding edge to be portable.
static func _quantized(value: Variant, quantum: float) -> Variant:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT]:
		return null
	var scaled := float(value) * quantum
	if not is_finite(scaled) or absf(scaled) > 1.0e15:
		return null
	if absf(absf(scaled - floorf(scaled)) - 0.5) < EDGE_MARGIN * maxf(1.0, absf(scaled)):
		return null
	return roundi(scaled)


## {ok, fingerprint, proxies, reason}. Proxy order is part of the screened world.
static func fingerprint(world: Dictionary) -> Dictionary:
	var proxies: Variant = world.get("proxies")
	if not proxies is Array:
		return {ok = false, reason = "world has no proxy array"}
	var rows: Array = []
	for proxy: Variant in proxies:
		if not proxy is Dictionary:
			return {ok = false, reason = "proxy is not a dictionary"}
		var row: Array = []
		for key: String in TEXT_FIELDS:
			var text: Variant = proxy.get(key)
			if typeof(text) not in [TYPE_STRING, TYPE_STRING_NAME]:
				return {ok = false, reason = "proxy %s field %s is not text" % [str(proxy.get("id")), key]}
			row.append(str(text))
		for key: String in LENGTH_FIELDS + UNIT_FIELDS:
			var quantum := UNIT_QUANTUM if key in UNIT_FIELDS else LENGTH_QUANTUM
			var quantized: Variant = _quantized(proxy.get(key), quantum)
			if quantized == null:
				return {ok = false, reason = "proxy %s field %s is malformed or not portable" % [str(proxy.get("id")), key]}
			row.append(quantized)
		rows.append(row)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(rows))
	return {ok = true, fingerprint = digest.finish().hex_encode(), proxies = rows.size(), reason = ""}


func _run() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	_check("stock field loads", loaded.get("ok", false))
	if not loaded.get("ok", false): return
	var built: Dictionary = CollisionSetup.build(loaded.field)
	_check("stock collision world builds", built.get("ok", false), str(built.get("errors", "")))
	if not built.get("ok", false): return
	var world: Dictionary = built.world
	var current := fingerprint(world)
	_check("stock world has a portable fingerprint", current.ok, str(current.reason))
	if not current.ok: return
	print("STOCK_WORLD_PORTABLE ", JSON.stringify({proxies = current.proxies, fingerprint = current.fingerprint,
		platform_identity = world.get("identity"), os = OS.get_name(), architecture = Engine.get_architecture_name()}))
	_check("proxy count matches the screened Mac domain", current.proxies == Domain.STOCK_WORLD_PROXIES,
		"%d != %d; %s" % [current.proxies, Domain.STOCK_WORLD_PROXIES, RENEWAL])
	_check("portable geometry fingerprint matches the screened Mac domain",
		current.fingerprint == STOCK_WORLD_PORTABLE_FINGERPRINT, RENEWAL)
	if OS.get_name() == "macOS" and Engine.get_architecture_name() == "arm64":
		_check("macOS ARM64 identity matches the screened domain", world.get("identity") == Domain.STOCK_WORLD, RENEWAL)
	_mutation_controls(world, current.fingerprint)


## The gate must reject the failure class it exists for: changed geometry with old pins.
func _mutation_controls(world: Dictionary, baseline: String) -> void:
	var moved: Dictionary = {proxies = world.proxies.duplicate(true)}
	moved.proxies[0]["north"] = float(moved.proxies[0].get("north")) + 0.002
	var moved_print := fingerprint(moved)
	_check("a 2 mm proxy move changes the fingerprint", moved_print.ok and moved_print.fingerprint != baseline)
	var removed: Dictionary = {proxies = world.proxies.slice(1)}
	var removed_print := fingerprint(removed)
	_check("a removed proxy changes count and fingerprint", removed_print.ok
		and removed_print.proxies == world.proxies.size() - 1 and removed_print.fingerprint != baseline)
	var renamed: Dictionary = {proxies = world.proxies.duplicate(true)}
	renamed.proxies[0]["part"] = str(renamed.proxies[0].get("part")) + "-changed"
	var renamed_print := fingerprint(renamed)
	_check("a changed proxy part changes the fingerprint", renamed_print.ok and renamed_print.fingerprint != baseline)
	var malformed: Dictionary = {proxies = world.proxies.duplicate(true)}
	malformed.proxies[0]["east"] = NAN
	_check("a non-finite proxy value fails closed", not fingerprint(malformed).ok)
