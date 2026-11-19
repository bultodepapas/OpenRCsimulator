# HUD-RADIO-02a: read-only presentation of accepted telemetry and sampled flight-pack readings.
# This is OpenRC data, not a running transmitter firmware or a physical RF telemetry link.
extends RefCounted

const Units := preload("res://render/overlays/units.gd")
const FlightData := preload("res://render/overlays/flight_data.gd")


## Stable strings make missing/NaN values compare equal, so a held stick need not trigger LCD redraws.
## system is already resolved by the overlay manager. No source dictionary is retained or changed.
static func readings(telemetry: Dictionary, battery: Dictionary, system: String) -> Dictionary:
	var time_s := number(telemetry, "time_s")
	var pack := battery if not telemetry.is_empty() and battery.get("valid", false) == true else {}
	var voltage := number(pack, "pack_voltage_v")
	var used := number(pack, "used_mah")
	return {
		airspeed = Units.format(Units.speed(number(telemetry, "airspeed"), system)),
		height_agl = Units.format(Units.length(number(telemetry, "height_agl"), system)),
		pack_voltage = ("%.2f V" % voltage) if is_finite(voltage) and voltage >= 0.0 else "– V",
		used_mah = ("%d mAh" % roundi(used)) if is_finite(used) else "– mAh",
		elapsed = FlightData.clock(time_s) if is_finite(time_s) and time_s >= 0.0 else "–",
	}


static func number(source: Dictionary, key: String) -> float:
	var value: Variant = source.get(key)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return NAN
	return float(value) if is_finite(float(value)) else NAN
