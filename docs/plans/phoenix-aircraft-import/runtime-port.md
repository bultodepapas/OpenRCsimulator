# Phoenix PKG and MOD runtime port contract

Status: proposed, audited on 2026-11-18. This guide makes the Python-to-Godot port reviewable; it does not deliver a runtime reader. The [parent plan](../phoenix-aircraft-import.md) owns AC-PX status, the [implementation guide](implementation.md) owns the overall pipeline and closure, and the [verification guide](verification.md#9-runtime-port-and-discovery-regressions) owns acceptance IDs. The [second audit](../../research/aircraft-creator/phoenix-port-audit-2026-11-18.md) records actual evidence and an executable reproduction appendix.

## 1. Compatibility means a defined intersection

Research source is pinned at `818581323f437f0c3ee1a5eac55cfcf2079d1ac8`; current application source at `39fa2746ae4f4ba8698b87db279adcfe84ef5d17`. The latter identifies Godot `4.8.beta2.official.cafc17a19`; this audit did not execute that engine. Recheck interfaces at the implementation revision.

A faithful port preserves ordered structure, raw bytes, decimal lexemes, structural occurrences and source-relative locations on the intersection of the observed Python grammar and the approved runtime policy. A research parse is not runtime namespace, complete-aircraft, visual or flight admission. Deliberate narrower limits/encoding rules must produce an explicit policy result, not a claim that all other Phoenix files are corrupt.

The starting point is [inspect_pkg.py](https://github.com/bultodepapas/OpenRCsimulator/blob/818581323f437f0c3ee1a5eac55cfcf2079d1ac8/research/aircraft-creator/phoenix/inspect_pkg.py) and [inspect_definition.py](https://github.com/bultodepapas/OpenRCsimulator/blob/818581323f437f0c3ee1a5eac55cfcf2079d1ac8/research/aircraft-creator/phoenix/inspect_definition.py). Their report representation, memory behavior and diagnostics are not a production API. Every uppercase helper and record below is a proposed contract, not an existing Godot method.

## 2. Owned bytes, checked arithmetic and honest locations

Reserve capture/copy memory and staged disk before taking a private copy or bounded spool. Hash, index, decode and publish the **same privately owned bytes**. Do not index a duplicate and then hash the original caller argument: current [ClearView Archive.inspect](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/clearview/archive.gd) has precisely that source-level split. Controlled original-buffer mutation is a new qualification target, not a reproduced engine failure. The existing `SourceImporter.inspect_bytes` ownership question remains separately tracked.

Godot's [PackedByteArray documentation](https://docs.godotengine.org/en/stable/classes/class_packedbytearray.html) describes reference passing, clamped slices and zero returns from short integer decodes. Those conveniences cannot establish a required field's presence. Check the complete range before decoding, slicing or allocating. Stable documentation is background; the pinned beta still needs execution.

```text
take(cursor, n):
    require n is a nonnegative integer and 0 <= cursor.pos <= cursor.length
    if n > cursor.length - cursor.pos:
        fail TRUNCATED at cursor's space and remaining half-open range
        # Failure leaves cursor.pos unchanged. Record wanted=n separately.
    start = cursor.pos
    cursor.pos += n
    return immutable_view(start, cursor.pos)  # a copy needs a separate reservation

u32le(cursor):
    s = require_ok(take(cursor, 4))
    return byte(s,0) | byte(s,1)<<8 | byte(s,2)<<16 | byte(s,3)<<24

charge(counter, amount, limit):
    require 0 <= counter <= limit and amount >= 0
    if amount > limit - counter: fail LIMIT
    return counter + amount

reserve_array(count, item_bytes, remaining):
    require count >= 0 and item_bytes > 0 and remaining >= 0
    if count > floor(remaining / item_bytes): fail LIMIT
    return checked_allocation(count * item_bytes)
```

Use equivalent checked u8/u16 operations. GDScript's signed integer arithmetic is not an overflow detector. In particular, a truncated zero `u16` after a file payload must not be mistaken for a valid zero child count. All resource counters use subtraction/division checks before addition/multiplication.

Locations have a closed tagged representation:

| Space | Identity and range |
| --- | --- |
| `CAPTURE_INPUT` | Exact outer file digest and half-open byte interval |
| `PKG_INPUT` | Exact captured PKG occurrence/digest and interval; if nested, retain its outer membership proof |
| `PKG_BODY` | Concatenated inflated-body digest, interval and package occurrence |
| `MEMBER_BYTES` | Member occurrence/digest and member-relative interval |
| `PHASE_UNAVAILABLE` | Bounded phase and containing occurrence/extent when a precise byte is unavailable |

Record each chunk's compressed PKG interval and its inflated-body interval. A member or tree field can cross chunks. A MOD span translates into a body interval through its member payload start, but **cannot be added to a compressed offset**. Report intersecting chunk extents when useful; do not fabricate a one-to-one compressed-byte map. Derive line and byte-column values from the original MOD bytes, never display-decoded characters.

## 3. PKG framing and the zlib adapter decision

Follow the exact observed framing in [implementation section 4](implementation.md#42-observed-pkg-profile), with these checked steps:

```text
read_pkg(capture, ctx):
    p = checked_cursor(capture, PKG_INPUT)
    require u8(p) == 0
    label = sized_u16_bytes(p, maximum=4096)
    require ASCII label matches digits + '.' + exactly six digits
    count = u16le(p); require 1 <= count <= 2048
    body = reserved_private_spool()
    for chunk_ordinal in range(count):
        compressed = u32le(p); plain = u32le(p)
        require 0 < compressed <= 64 MiB and 0 < plain <= 1_024_000
        charge declared_body_total by plain against 128 MiB
        block = take(p, compressed)
        body_start = body.length
        result = QUALIFIED_ZLIB_EXACT(block, plain, ctx, body_sink)
        require result.end_reached and result.checksum_ok
        require result.input_consumed == compressed and result.output_produced == plain
        record compressed span and [body_start, body.length) in their own spaces
    require p.pos == p.length
    parse body using a checked cursor and prefix 01 00 01 00
    retain every file/directory occurrence, including empty directories
    require every file's child-count field is present and zero
    require remaining body length <= 512; then require every remaining byte is zero
    return raw tree for separate full namespace admission
```

The existing research limits also include 2,048 file/directory occurrences, depth 32, 4,096 bytes per string, 32 MiB per member and 128 MiB per body. The shared job and narrower runtime namespace limits remain additional gates. Charge every actual decompression, copy, retained chunk map, hash pass and report against the appropriate counter; buffer release does not refund spent work. Avoid retaining all inflated parts and then making a second joined body without reserving both live representations.

### 3.1 Window size is not total output size

[RFC 1950](https://www.rfc-editor.org/rfc/rfc1950.html) defines CINFO as the LZ77 history-window size. A valid 512-byte-window stream may produce more than 512 output bytes. The new original vector `small-window-long-output` does exactly that and passes the pinned Python reader. Current [inflate.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/inflate.gd) rejects expected output above its declared-window policy when CINFO is below 7. That is a conservative existing image-path restriction, not a universal zlib rule. The predicted `STATUS_WINDOW` result is source inspection, not an executed Godot result.

Choose a separately qualified PKG zlib profile/adapter, or explicitly advertise/refuse the narrower initial subset. Do not remove the existing image restriction globally to make this fixture pass. Preserve its owner-reviewed PNG tests and its independent image-decoder admission.

### 3.2 Required decoder facts

An adapter must establish header/check bits, supported compression method, supported window, explicit preset-dictionary policy, valid backreference distances, checksum, real stream end, exact input consumption and exact output count. FDICT is unsupported in the initial profile; it does not authorize loading a dictionary from disk/network. Truncated checksum/end markers, an appended byte or a second zlib stream refuse even when the expected output was already produced.

[clearview/deflate.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/clearview/deflate.gd) is raw DEFLATE. Removing two header bytes and four trailer bytes is insufficient: a new wrapper must independently enforce the zlib header window on each backreference, validate Adler-32 and qualify final bit/byte consumption. Its current distance check against bytes already written is not that window check. Its per-call work ceiling must also borrow the job-wide budget.

The [Python 3.12 zlib API](https://docs.python.org/3.12/library/zlib.html) supplies explicit `eof`, `unused_data` and `unconsumed_tail`; Godot's stream interface is not assumed equivalent. If the chosen engine adapter cannot expose or independently establish all required facts, refuse that profile until another reviewed implementation exists. Do not invent an EOF property or call decompression `finish()` as an unproven substitute. Pin decoder implementation and engine artifacts, not only API names.

## 4. Cancellation and output accounting are part of parsing

Current `zlib_scan` has no cancellation argument and calls its sink only after output. Raw DEFLATE cancellation can become generic `SOURCE_INVALID`; its stored-block copy loop lacks per-copy work/cancel polling. These are concrete reuse limits, not evidence of an executed application hang.

The proposed adapter checks a shared ticket and work/deadline budget at bounded input feeds, output drains, symbol batches, stored-byte copies, checksum/hash batches and report writes. Zero output does not mean zero work. Never reset these counters at ZIP→PKG→MOD, on a cache miss, or after retrying another discriminator. Reserve decoder scratch and any temporary overrun buffer before native calls. Measure the maximum uninterruptible call on the pinned engine; if it is unsuitable, use a qualified isolated worker/lifetime policy rather than promising that a Boolean flag interrupts native code.

Keep `CANCELLED`, `LIMIT`, `UNSUPPORTED_PROFILE` and malformed-input failures distinct internally. A cancellation invalidates that job's pending success/adoption; cleanup only removes private incomplete state. The single Store actor and final commit arbiter remain as specified by the overall implementation guide.

## 5. MOD is an explicit byte grammar

Port the actual observed grammar, including its positive edge cases. Do not replace it with a Lua runtime, JSON parser or permissive `String.to_float()` call. The [Godot String reference](https://docs.godotengine.org/en/stable/classes/class_string.html) documents parsing behavior broader than this grammar; grammar validation must happen first.

```text
lex_mod(member, ctx):
    require source length <= 512 KiB
    reject each CR not followed by LF; retain original byte line starts
    while input remains:
        charge/poll even while skipping comments or scanning a long string
        admit defined ASCII whitespace and '--' line comments; reject '--[' form
        match ASCII identifiers, exact fixed decimals, quotes or allowed punctuation
        reject backslash, control bytes and DEL inside strings; retain high bytes
        preserve raw token content and full source spans
        charge before each source token; maximum 60,000
    append one EOF sentinel outside that source-token count

parse_value(depth):
    require available token; enforce node budget <= 25,000
    table: require depth <= 32; preserve ordered entries
           reject mixed keyed/positional mode and duplicate keys
           allow empty table and trailing comma; retain key/child occurrence spans
    scalar: retain exact string/decimal, or only physics.airplane / physics.helicopter
    # Whitespace/comments between dotted symbol tokens are grammar-permitted.

finish:
    require modelTypes.identifier = table and exact EOF after permitted trivia
    require named root entries when the root contains entries
    return syntax evidence; required aircraft fields belong to the next schema stage
```

Identifiers are bounded at 128 bytes, quoted content at 4,096, numbers at 64. The depth check applies when opening a table; a scalar leaf at depth 33 inside a table opened at depth 32 is accepted by the research grammar. Test that boundary explicitly. Preserve refusal of `+1`, `.5`, `1.`, exponents, unobserved escapes, bare `true` and arbitrary symbols. An empty `modelTypes.X={}` parses but is not a complete aircraft. Strings retain raw bytes; UTF-8 for the whole valid string or whole-string Latin-1 fallback is a tagged **display strategy**, not evidence of Phoenix's encoding. The byte strings `c3 a9` and `e9` can display alike while remaining distinct.

The output encoder must explicitly represent bytes as bounded hex/base64 or immutable blob references. Existing [CreatorBytes](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/bytes.gd) does not accept arbitrary packed arrays as ordinary JSON values and limits exact integers. Account for encoding expansion before allocating diagnostic strings; source-local author paths remain redacted in public reports.

## 6. Exact decimal identity and binary64 projection

The current grammar is `-?[0-9]+(?:\.[0-9]+)?` with at most 64 raw bytes. Every nonzero accepted magnitude is at least `1e-62` and below `1e64`, so all are inside normal binary64 range. A binary64 overflow/underflow token is impossible in this profile. Test token length, precision and later float32 projection instead; a wider future grammar needs its own range tests.

Preserve a bounded exact decimal record alongside any numerical projection:

```text
normalize_decimal(raw):
    validate full grammar and raw byte length first
    retain raw spelling and negative-zero spelling separately
    digits = concatenate integer/fraction digits; scale = fraction digit count
    remove leading zero digits
    if no nonzero digits: return exact_zero plus raw spelling
    while digits ends with '0': remove last digit; scale -= 1
    return sign, coefficient_digits, signed_scale   # value = sign * coefficient * 10^-scale

equal_exact(a, b):
    zeros compare equal; otherwise compare normalized sign, digits and scale

project_binary64(a):
    if exact_zero: return the separately specified signed-zero projection
    build positive N/D exactly from coefficient and signed scale
    e = unique integer with 2^e <= N/D < 2^(e+1), using integer comparisons
    shift = 52 - e
    A,B = (N << shift, D) if shift >= 0 else (N, D << -shift)
    q,r = exact_divmod(A,B)
    if 2*r > B or (2*r == B and q is odd): q += 1
    if q == 2^53: q >>= 1; e += 1
    encode sign, exponent e+1023, fraction q-2^52 with checked field ranges
```

This is proposed round-to-nearest, ties-to-even logic, not a claim that GDScript has arbitrary-precision integers. Use a reviewed bounded integer implementation/native conversion dependency, or keep these values observation-only until conversion is qualified. Bound digits, shifts, intermediate integers, arithmetic work and cancellation before adopting an implementation. Negative normalized scale multiplies the numerator; it is not a negative decimal denominator exponent silently dropped. Never parse a 64-digit coefficient into a signed 64-bit integer.

A conservative 512-bit cap covers the **mathematical intermediates** for this grammar: `N < 2^213`, `D < 2^206`, exponent `e` lies in `[-206,212]`, and shift lies in `[-160,258]`. The independently loose bounds for the shifted numerator/divisor are 471/366 bits; twice the remainder fits within 367 bits. The implementation must enforce that cap on every operation and prove its limb/carry arithmetic cannot overflow native integers. To find `e`, let `k=bit_length(N)-bit_length(D)`; compare `N` with `D<<k` for nonnegative k, or `N<<(-k)` with `D` otherwise. Set `e=k-1` if the left side is smaller, else `e=k`. This avoids floating logarithms. Extend the boundary suite with the exact carry midpoint `2-2^-53` and both signs; those extra cases are proposed, not included in the nineteen executed vectors.

Current `CreatorBytes.exact_float` recovers the number represented by its own canonical writer spelling; its fallback selects the first writer spelling at or above a noncanonical token. It is not a general nearest-even parser for arbitrary MOD decimals. Do not substitute it without proving the required contract.

The original vector receipt fixes two exact midpoint oracles: `1 + 2^-53` rounds to 1, while `1 + 3*2^-53` rounds to `1 + 2^-51`. It also includes `10000000000000000` versus `10000000000000001`: distinct exact values with the same nearest-even binary64 projection. Compare pivots exactly first (`COINCIDENT_PIVOTS`); only then compare projected coordinates (`PIVOT_PRECISION_LOSS`). Signed zeros are numerically equal for that test; original spelling/identity survives any canonical output normalization. No guessed epsilon resolves an undefined hinge.

## 7. Failure records and Creator integration

Existing [Creator result envelopes](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/result.gd) use `{ok, value, diagnostics}` on success and omit `value` on failure. They have `SOURCE_INVALID`, `SOURCE_UNSUPPORTED` and `SOURCE_LIMIT`, but no shared `CANCELLED` constant. Introduce a checked, versioned provider report/internal outcome and an explicit UI adapter; coordinate any shared schema change with its owner. Do not append unknown fields to closed records or turn a successful dictionary into an accepted owner.

| Internal reason | Proposed boundary treatment |
| --- | --- |
| Malformed framing/checksum/syntax | Existing invalid-source presentation plus separately validated detailed reason/location |
| Outside observed profile or required decoder capability absent | Unsupported-source/capability presentation; no corruption claim |
| Byte/work/node/report budget | Source-limit presentation with bounded counter/phase metadata |
| Missing/ambiguous required reference | Checked dependency result; preserve earlier syntax observations without admitting closure |
| Cancellation/stale job | Distinct internal job outcome; suppress adoption and use coordinated UI semantics, not an invalid-file accusation |

Use fixed message templates, bounded arguments and a separately bounded failure envelope. A sink refusal must retain whether its cause was limit, cancellation or I/O. Partial observations may be shown as an explicit incomplete report; they cannot occupy the accepted `value`/handle of a failed stage.

## 8. Differential qualification and implementation order

The [19 original reference vectors](../../research/aircraft-creator/phoenix-port-reference-vectors-2026-11-18.json) retain complete tiny input hex, hashes, accepted/refused outcomes and scoped reference data. They execute captured trusted Python source bytes only. Source-derived STL/zlib predictions are separately labeled; no Godot or Builder pass is implied.

First implement owned capture, cursor and tagged locations; then the independently qualified exact zlib adapter; then complete raw tree and namespace; then MOD syntax, exact decimal observations and bounded reports. Candidate discovery/closure follows the [overall algorithms](implementation.md#5-candidate-closure-and-association-proofs). None requires GEO guesses or changes to physical simulation.

For a runtime campaign, freeze the exact engine/application build and fixture bytes. Compare raw payload hashes, ordered occurrences, field kinds, lexemes, location spaces, exact decimals and projected bits on the common profile. Hand-count tiny spans and use independently generated framing/compression; Python's report is a reference observation, not the only oracle. Compare semantic records rather than demanding identical Python pretty JSON and Creator canonical JSON. Add zero-output/cancel, header/window/Adler/EOF, every truncation boundary, nested aggregate work and actual caller-mutation tests. Run only the focused owner-required suites through the repository's test admission workflow.

Advancement requires honest outcomes for every unsupported case, bounded failure behavior and exact provenance through Creator/Store. Passing these port tests still leaves GEO correspondence, exported-platform performance and flight qualification open.
