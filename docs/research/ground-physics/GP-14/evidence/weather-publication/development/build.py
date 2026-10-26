from pathlib import Path
import hashlib, json
root = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent
source = root / 'app/sim/flight_session.gd'
original = source.read_bytes()
(out / 'flight_session.before.gd').write_bytes(original)
text = original.decode('utf-8').replace('\r\n','\n')
old = '''	resetting.emit() # a recording cannot span an environment-identity change
	_weather = built.field
	_weather_pending_reset = sim != null
	if sim != null:
		sim.set_paused(true)
	weather_error = ""
	return true
'''
new = '''	# Before setup there is no installed flight or recorder to close.
	if sim == null:
		_weather = built.field
		_weather_pending_reset = false
		weather_error = ""
		return true
	var transaction := _begin_start_transaction()
	# Even obtaining the old closing checkpoint can invoke the model validator.
	# Refuse before notification if that read attempted to change the owner.
	var intact: bool = sim._endpoint_guard_matches(transaction.kernel)
	for field: String in _START_OWNER_FIELDS:
		intact = intact and Sim._guard_values_equal(get(field), transaction.owner[field])
	if _reset_transaction_reentry or not intact:
		_refuse_start_transaction(transaction, "weather preparation changed the installed owner")
		weather_error = "weather preparation changed the installed owner"
		return false
	_weather = built.field
	_weather_pending_reset = true
	weather_error = ""
	# This accepts a pending configuration, not a new physical start. Keep the
	# historical setup_weather(); reset() contract, with no tick or credit here.
	transaction.committed = true
	_reset_physical_committed = true # Post-acceptance presentation holds are legal.
	sim.reset_observer_fault = ""
	sim._publish_committed_boundary(func() -> void:
		_reset_publication_active = true
		_reset_closing_context = transaction.closing
		resetting.emit()
		_reset_closing_context = {}
		_reset_publication_active = false, false, "weather configuration", true)
	_end_start_transaction(transaction)
	if not sim.reset_observer_fault.is_empty():
		weather_error = sim.reset_observer_fault
		pause_reason = "simulation fault: " + weather_error
	return true
'''
assert text.count(old)==1
draft = text.replace(old,new).encode()
(out / 'flight_session.gd').write_bytes(draft)
(out / 'source-hashes.json').write_text(json.dumps({'before':hashlib.sha256(original).hexdigest(),'draft':hashlib.sha256(draft).hexdigest()},indent=2)+'\n')
