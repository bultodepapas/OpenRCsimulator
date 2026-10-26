extends RefCounted
## AUD-16: presentation-only equipment sound choices. Never changes actuator physics.

const SERVO_TYPES: Array[String] = ["standard", "high_torque"]
const RETRACT_TYPES: Array[String] = ["electric", "pneumatic"]

static func defaults() -> Dictionary:
	return {"servo_type": "standard", "servo_level": 1.0, "retract_type": "electric"}

static func validate(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if not raw is Dictionary or raw.size() != 3:
		return {"ok": false, "errors": PackedStringArray(["Mechanical audio requires servo_type, servo_level and retract_type."]), "profile": {}}
	if not raw.get("servo_type") is String or not SERVO_TYPES.has(str(raw.get("servo_type", ""))):
		errors.append("Choose Standard Servo or High-Torque Servo.")
	if not raw.get("retract_type") is String or not RETRACT_TYPES.has(str(raw.get("retract_type", ""))):
		errors.append("Choose electric or pneumatic retract audio.")
	var level: Variant = raw.get("servo_level")
	if typeof(level) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(level)) or float(level) < 0.0 or float(level) > 1.0:
		errors.append("Servo sound level must be a finite number from 0 to 1.")
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "profile": {}}
	return {"ok": true, "errors": errors, "profile": {
		"servo_type": str(raw.servo_type), "servo_level": float(raw.servo_level), "retract_type": str(raw.retract_type)}}

static func resolve(presentation: Dictionary) -> Dictionary:
	var checked := validate(presentation.get("mechanical_audio", defaults()))
	return checked.profile if checked.ok else defaults()
