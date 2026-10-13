# O5 Telemetry (HUD-10): attitude, flow angles, load factor and engine speed for curious pilots.
extends "res://render/overlays/overlay_frame.gd"

const Units := preload("res://render/overlays/units.gd")

var values: Dictionary


func _init() -> void:
	super("telemetry", tr("Telemetry"))
	values = add_rows([
		["alpha", tr("Angle of attack")],
		["beta", tr("Sideslip")],
		["pitch", tr("Pitch angle")],
		["bank", tr("Bank angle")],
		["heading", tr("Heading")],
		["load", tr("Load factor")],
		["rpm", tr("Engine")],
	])


## t: Telemetry.compute() output or {}; rpm: engine or rotor speed (aux 0).
func refresh(t: Dictionary, rpm: float) -> void:
	if t.is_empty():
		for key in values:
			values[key].text = "–"
		return
	values.alpha.text = Units.angle(t.alpha_deg, 1)
	values.beta.text = Units.angle(t.beta_deg, 1)
	values.pitch.text = Units.angle(t.pitch_deg, 0)
	values.bank.text = Units.angle(t.bank_deg, 0)
	values.heading.text = "%03d°" % (roundi(t.heading_deg) % 360)
	values.load.text = "%.1f g" % t.load_factor
	values.rpm.text = tr("%d rpm") % roundi(rpm)
