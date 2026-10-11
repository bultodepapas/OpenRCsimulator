# G3b: pure per-voice oscillator. Audio state never feeds the flight solver.
extends RefCounted

const RATE := 22050.0
const TABLE_SIZE := 4096
const HARMONICS := [1.0, 0.6, 0.45, 0.3, 0.2, 0.12]
# Estimated presentation smoothing, not an engine/servo time constant.
const SMOOTH_SECONDS := 0.003
static var _tables: Array[PackedFloat32Array] = []

var phase := 0.0
var frequency := 0.0
var amplitude := 0.0


static func prepare() -> void:
	if not _tables.is_empty():
		return
	var total := 0.0
	for h in HARMONICS:
		total += h
	for count in HARMONICS.size() + 1:
		var table := PackedFloat32Array()
		table.resize(TABLE_SIZE + 1)
		for i in TABLE_SIZE:
			var value := 0.0
			for k in count:
				value += HARMONICS[k] * sin(TAU * (k + 1) * float(i) / TABLE_SIZE)
			table[i] = value / total
		table[TABLE_SIZE] = table[0]
		_tables.append(table)


static func band(freq: float, rate: float) -> int:
	var count := 0
	while count < HARMONICS.size() and (count + 1) * freq < rate * 0.5:
		count += 1
	return count


static func sample(table: PackedFloat32Array, cycles: float) -> float:
	var index := cycles * TABLE_SIZE
	var lo := int(index)
	return table[lo] + (table[lo + 1] - table[lo]) * (index - lo)


func reset(rpm := 0.0, max_rpm := 1.0) -> void:
	phase = 0.0
	frequency = maxf(rpm, 0.0) / 60.0 if is_finite(rpm) else 0.0
	amplitude = level(rpm, max_rpm)


static func level(rpm: float, max_rpm: float) -> float:
	if not is_finite(rpm) or not is_finite(max_rpm) or rpm <= 0.0 or max_rpm <= 0.0:
		return 0.0
	return 0.15 + 0.45 * clampf(rpm / max_rpm, 0.0, 1.0)


## Render a smoothed RPM target directly into the stereo generator buffer.
func render(rpm: float, max_rpm: float, frames: int) -> PackedVector2Array:
	prepare()
	var target := maxf(rpm, 0.0) / 60.0 if is_finite(rpm) else 0.0
	var gain := level(rpm, max_rpm)
	var table := _tables[band(maxf(frequency, target), RATE)]
	var alpha := 1.0 - exp(-1.0 / (SMOOTH_SECONDS * RATE))
	var out := PackedVector2Array()
	out.resize(maxi(frames, 0))
	for i in out.size():
		frequency += alpha * (target - frequency)
		amplitude += alpha * (gain - amplitude)
		var value := amplitude * sample(table, phase)
		out[i] = Vector2(value, value)
		phase = fposmod(phase + frequency / RATE, 1.0)
	return out


## D5-compatible fixed-frequency pure renderer, used by offline spectral checks.
static func synthesize(cycles: float, freq: float, amp: float, frames: int, rate := RATE) -> Array:
	prepare()
	var out := PackedFloat32Array()
	out.resize(maxi(frames, 0))
	if not is_finite(cycles) or not is_finite(freq) or not is_finite(amp) or not is_finite(rate) or rate <= 0.0:
		return [out, 0.0]
	cycles = fposmod(cycles, 1.0)
	if freq <= 0.0:
		return [out, cycles]
	var table := _tables[band(freq, rate)]
	var step := fposmod(freq / rate, 1.0)
	for i in out.size():
		out[i] = amp * sample(table, cycles)
		cycles = fposmod(cycles + step, 1.0)
	return [out, cycles]
