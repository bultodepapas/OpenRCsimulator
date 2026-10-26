from pathlib import Path
import hashlib
folder=Path(__file__).resolve().parent
source=(folder/'test_normal_compliance_interval.gd').read_text()
start=source.index('# Complete original API Variant-byte/hex SHA256 captures')
end=source.index('var largest_secant_ratio := 0.0',start)
source=source[:start]+source[end:]
source=source.replace('_parity(law)','_parity(raw, law)')
start=source.index('func _parity(')
end=source.index('## Independent scalar polynomial',start)
source=source[:start]+'''func _parity(raw: Dictionary, law: Dictionary) -> void:
	var old := C.prepare(raw)
	_check("original prepare remains byte identical", var_to_bytes(old) == var_to_bytes(law))
	var same := true
	for x: float in [-.01, 0.0, 1e-12, .001, .002, .019, .02, .021, .03, .04]:
		for v: float in [-3.0, -.1, 0.0, .1, 3.0]:
			if var_to_bytes(C.evaluate(old, x, v)) != var_to_bytes(Candidate.evaluate(law, x, v)): same = false
	_check("all original evaluate fields/default arithmetic remain byte identical", same)
	same = true
	for xmax: float in [0.0, .001, .02, .025, .04]:
		var previous := C.bounds(old, xmax, 3.0)
		if var_to_bytes(previous) != var_to_bytes(Candidate.bounds(law, xmax, 3.0)): same = false
		if var_to_bytes(previous) != var_to_bytes(Candidate.bounds_interval(law, 0.0, xmax, 3.0)): same = false
	_check("old bounds and interval starting at zero are byte identical", same)
	_check("original scalar selector remains byte identical", var_to_bytes(C.scalar_substeps(old, .04, 3.0, 2.0, 1.0/240.0))
		== var_to_bytes(Candidate.scalar_substeps(law, .04, 3.0, 2.0, 1.0/240.0)))


'''+source[end:]
source=source.replace('missing prepared success/law selector refuses cleanly','malformed prepared result refuses cleanly')
target=folder/'original-465-test.gd'
target.write_text(source,encoding='utf-8',newline='\n')
actual=hashlib.sha256(target.read_bytes()).hexdigest()
expected='b6913c3facd816ea2a26f6ab7ec13f4845fc25f74add6e0c68c8ff3b0cbf1748'
assert actual==expected,(actual,expected)
print('Recovered exact original465 test bytes from sealed hash:',actual)
