extends RefCounted
## Bounded streaming zlib inflate for untrusted input (AC-03). Pure data; no scene tree.
##
## The stream is pumped through one fixed scratch buffer (`Limits.INFLATE_SCRATCH_BYTES`), so the
## memory in flight never depends on a size the file declares. The caller states the exact output
## size it expects; inflation stops at the first chunk that passes it, so an expansion bomb costs at
## most one scratch buffer of extra output.
##
## The two-byte zlib header is checked here, before the engine sees any byte. Corrupt deflate data
## after a valid header is still refused, but the engine logs its own error for it: a bad block, an
## Adler-32 mismatch, or a stream cut inside its last checksum byte cannot be detected without
## decoding. Every other refusal is silent.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")

const STATUS_OK := "ok"
const MAX_INTEGER := 9223372036854775807
## The input does not start with an admissible zlib header, or `expected_bytes` is negative.
const STATUS_HEADER := "header"
## The stream ended, or the input ran out, before `expected_bytes` were produced.
const STATUS_SHORT := "short"
## The stream produced more than `expected_bytes`. Inflation stopped at that chunk.
const STATUS_EXCESS := "excess"
## Compressed bytes remain after the end of the stream.
const STATUS_TRAILING := "trailing"
## `expected_bytes` were produced but the stream is not terminated (missing end or checksum).
const STATUS_TRUNCATED := "truncated"
## The engine inflater reported an error.
const STATUS_CORRUPT := "corrupt"
## The caller's sink refused a chunk.
const STATUS_SINK := "sink"
## The header declares a window smaller than the data it must produce. The engine's inflater
## ignores the declared window, while PNG decoders enforce it: such a stream could pass here and
## fail later inside the image decoder, so it is refused. Encoders shrink the window only for
## data that fits in it, which this rule still admits.
const STATUS_WINDOW := "window"


## Inflates the concatenation of `parts` and succeeds only when the stream yields exactly
## `expected_bytes` and no compressed byte remains. Returns the `R` envelope with
## `value = {bytes_out, output}`; `output` is present only with `keep_output`, and is then bounded
## by `expected_bytes`, which the caller must have bounded itself.
##
## `sink`, when valid, is called as `sink.call(chunk: PackedByteArray, offset: int) -> bool` for
## each output chunk in order (`offset` is the stream position of its first byte), so a caller can
## check the data without keeping it. Returning false stops the inflation.
static func zlib_exact(parts: Array[PackedByteArray], expected_bytes: int, keep_output := false,
		sink := Callable()) -> Dictionary:
	var report := zlib_scan(parts, expected_bytes, keep_output, sink)
	match str(report.status):
		STATUS_OK:
			var value := {bytes_out = int(report.bytes_out)}
			if keep_output:
				value.output = report.output
			return R.ok(value)
		STATUS_HEADER:
			return R.fail(R.SOURCE_INVALID, "The compressed data does not start with a valid zlib header.")
		STATUS_SHORT:
			return R.fail(R.SOURCE_INVALID, "The compressed data is truncated: it holds less data than declared.")
		STATUS_EXCESS:
			return R.fail(R.SOURCE_INVALID, "The compressed data expands beyond its declared size.")
		STATUS_TRAILING:
			return R.fail(R.SOURCE_INVALID, "Extra bytes follow the end of the compressed data.")
		STATUS_TRUNCATED:
			return R.fail(R.SOURCE_INVALID, "The compressed data is truncated: its end marker or checksum is missing.")
		STATUS_SINK:
			return R.fail(R.SOURCE_INVALID, "The compressed data holds values its reader refuses.")
		STATUS_WINDOW:
			return R.fail(R.SOURCE_UNSUPPORTED, "The compressed data declares a window smaller than its content.")
	return R.fail(R.SOURCE_INVALID, "The compressed data is corrupt.")


## Same work as `zlib_exact`, reported as plain data: `{status, bytes_out, output}`. `bytes_out`
## counts every byte taken from the inflater, including the chunk that crossed the bound.
static func zlib_scan(parts: Array[PackedByteArray], expected_bytes: int, keep_output := false,
		sink := Callable()) -> Dictionary:
	var report := {status = STATUS_HEADER, bytes_out = 0, output = PackedByteArray()}
	if expected_bytes < 0:
		return report
	var head := PackedByteArray()
	for part: PackedByteArray in parts:
		var at := 0
		while head.size() < 2 and at < part.size():
			head.append(part[at])
			at += 1
		if head.size() == 2:
			break
	if head.size() < 2 or not is_zlib_header(head[0], head[1]):
		return report
	if expected_bytes > declared_window(head[0]):
		report.status = STATUS_WINDOW
		return report

	var scratch := Limits.INFLATE_SCRATCH_BYTES
	var peer := StreamPeerGZIP.new()
	if peer.start_decompression(true, scratch) != OK:
		report.status = STATUS_CORRUPT
		return report
	var output := PackedByteArray()
	var bytes_out := 0
	for part: PackedByteArray in parts:
		var offset := 0
		while offset < part.size():
			var step := mini(scratch, part.size() - offset)
			var fed: Array = peer.put_partial_data(part if step == part.size() else part.slice(offset, offset + step))
			if int(fed[0]) != OK:
				report.status = STATUS_CORRUPT
				report.bytes_out = bytes_out
				return report
			var consumed := int(fed[1])
			offset += consumed
			var drained := 0
			while peer.get_available_bytes() > 0:
				var got: Array = peer.get_partial_data(mini(peer.get_available_bytes(), scratch))
				var chunk: PackedByteArray = got[1]
				if int(got[0]) != OK or chunk.is_empty():
					report.status = STATUS_CORRUPT
					report.bytes_out = bytes_out
					return report
				drained += chunk.size()
				if bytes_out + chunk.size() > expected_bytes:
					report.status = STATUS_EXCESS
					report.bytes_out = bytes_out + chunk.size()
					return report
				if sink.is_valid() and not bool(sink.call(chunk, bytes_out)):
					report.status = STATUS_SINK
					report.bytes_out = bytes_out + chunk.size()
					return report
				if keep_output:
					output.append_array(chunk)
				bytes_out += chunk.size()
			# With the ring buffer drained the inflater always makes progress on a live stream,
			# so no progress means the stream has ended and these input bytes are left over.
			if consumed == 0 and drained == 0:
				report.status = STATUS_TRAILING
				report.bytes_out = bytes_out
				return report
	report.bytes_out = bytes_out
	if bytes_out < expected_bytes:
		report.status = STATUS_SHORT
		return report
	# The engine exposes no "stream finished" state. A finished stream takes no further input,
	# so one probe byte tells a complete stream from one cut inside its last block or checksum.
	var probe: Array = peer.put_partial_data(PackedByteArray([0]))
	if int(probe[0]) != OK:
		report.status = STATUS_CORRUPT
		return report
	if int(probe[1]) != 0 or peer.get_available_bytes() > 0:
		report.status = STATUS_TRUNCATED
		return report
	report.status = STATUS_OK
	if keep_output:
		report.output = output
	return report


## Bytes a back-reference may reach according to the zlib header: 2^(CINFO + 8). With the full
## 32 KiB window (CINFO 7) this is the deflate maximum, so every decoder agrees on the stream.
static func declared_window(cmf: int) -> int:
	return MAX_INTEGER if (cmf >> 4) >= 7 else 1 << ((cmf >> 4) + 8)


## RFC 1950: deflate method, window of at most 32 KiB, valid check bits, no preset dictionary.
static func is_zlib_header(cmf: int, flg: int) -> bool:
	return (cmf & 0x0F) == 8 and (cmf >> 4) <= 7 and ((cmf << 8) | flg) % 31 == 0 and (flg & 0x20) == 0
