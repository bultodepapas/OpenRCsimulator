# HUD-14: a compact, optional view of the statistics service. It only queries displayed counts;
# the service owns collection and storage even while this instrument is hidden.
extends "res://render/overlays/player_instrument.gd"

var _detail_label: Label


func _init(instrument_id: String = "session_stats") -> void:
	super(instrument_id, "Session statistics", "speed")
	graphic.custom_minimum_size = Vector2(240, 34)
	_detail_label = text_label("", 12, MUTED)
	_detail_label.name = "StatisticsDetail"
	_detail_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	graphic.add_child(_detail_label)
	_apply_density()


func refresh_statistics(sample: Dictionary, scope_label: String) -> void:
	var landings := _count(sample.get("landings", 0))
	var crashes := _count(sample.get("crashes", 0))
	var restarts := _count(sample.get("restarts", 0))
	var started := _count(sample.get("started", 0))
	var completed := _count(sample.get("completed", 0))
	var subtitle_text := "%s · %s" % [tr("This session"), scope_label]
	var details_text := "%s %d · %s %d" % [tr("Started"), started, tr("Completed"), completed]
	var key: Array = [landings, crashes, restarts, subtitle_text, details_text, TranslationServer.get_locale()]
	if key == _view_key:
		return
	_view_key = key
	value_label.text = str(landings)
	unit_label.text = tr("Landings")
	subtitle.text = subtitle_text
	left_caption.text = tr("Crashes").to_upper()
	left_value.text = str(crashes)
	right_caption.text = tr("Restarts").to_upper()
	right_value.text = str(restarts)
	_detail_label.text = details_text
	queue_redraw()


static func _count(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return maxi(0, value)
	if typeof(value) == TYPE_FLOAT and is_finite(value):
		return maxi(0, roundi(value))
	return 0
