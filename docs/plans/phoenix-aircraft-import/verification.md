# Phoenix importer verification and delivery guide

Status: proposed runtime acceptance, 2026-11-18. The [implementation guide](implementation.md) defines the contracts; the [parent plan](../phoenix-aircraft-import.md) owns AC-PX-00…09 status. Case IDs here are acceptance specifications, **not implemented or passed application tests**. The [audit receipt](../../research/aircraft-creator/phoenix-plan-audit-verification-2026-11-18.json) records the narrower checks actually run.

## 1. Evidence levels and test discipline

Keep four distinct evidence classes:

| Class | What it establishes | What it does not establish |
| --- | --- | --- |
| Source inspection | A particular implementation or plan contains a stated seam/condition | An executed exploit, engine behavior or release compatibility |
| Synthetic research execution | The pinned Python research tools exhibit the recorded behavior on original small fixtures | Production admission, real GEO conversion or platform safety |
| Application fixture campaign | The exact engine/application implementation passes its named positive/negative oracles | Compatibility with every Phoenix package or measured physical fidelity |
| Real source/export and platform campaign | The listed specimens/workflows/platforms pass the advertised stages | General support beyond that evidence |

This audit ran the existing 31 container, 26 capture/receipt and 61 definition checks: **118 existing synthetic checks, zero real samples in this run**. It separately reproduced **five additional owned boundary fixtures**: one MOD report-limit case and four PKG cases. Passing the research suite does not invalidate these findings; accepting path strings as inert JSON is intentional in that probe.

Use original/expressly licensed public fixtures. Do not commit downloaded third-party aircraft binaries to make a regression suite convenient. Keep lawful local sample manifests and rights evidence separate from test results. Public availability is not a redistribution grant.

### 1.1 Required receipt for a future campaign

Record exact application/research commit, dirty-state status, parser/converter/fixture hashes, profile and policy versions, engine/build/OS/architecture, Python/zlib or validator versions when used, command and exit status, expected/actual outcome, checked stages, untested stages and resource observations. Never replace “not run” with “passed” because a prerequisite passed.

For a real sample include source URL/author/revision, captured bytes hash/size, outer/member occurrence identities, selected root/scheme, complete required closure, rights basis and stage-by-stage support. Filename, model label, image equality and a catalog row are not unique aircraft identities.

Keep input and observed output fixed before inspecting the implementation's answer. Do not generate an expected result with the same converter and call its round trip independent validation. Store before/after hashes for files that must remain untouched.

## 2. Running the existing research checks

From a checkout containing the pinned research tools, choose new receipt filenames because the checkers create output exclusively:

```sh
python3 research/aircraft-creator/phoenix/check_probe.py \
  --report /absolute/private/output/phoenix-probe-new-run.json

python3 research/aircraft-creator/phoenix/check_definitions.py \
  --report /absolute/private/output/phoenix-definition-new-run.json
```

Create the private output directory first. Do not overwrite sources, existing receipts or aliases. These commands run synthetic cases by default; adding real-input flags requires the separately documented captured inventory and must not change the meaning of the synthetic result. See the [research README](../../../research/aircraft-creator/phoenix/README.md).

Pinned source SHA-256 for the 2026-11-18 reproduction:

| Tool | SHA-256 |
| --- | --- |
| `inspect_pkg.py` | `4f89ac322421842a9812e9c577c2b26f7e8436738ebd07104fb263f94c8cfdf9` |
| `inspect_definition.py` | `678268321579b34ef75662102fba1b734deb9421b59d39f3f314c24057402550` |

The [dated audit's reproduction appendix](../../research/aircraft-creator/phoenix-plan-audit-2026-11-18.md#6-reproduce-the-five-new-boundary-cases) contains the exact isolated script. It rejects optimized Python, verifies source hashes and records the default refusal separately from a temporary in-memory limit increase used only to measure output size. It does not modify repository parsers.

### 2.1 Original PKG fixture construction

For the observed profile, independently assemble little-endian fields rather than calling a production exporter. A minimal test package contains marker `00`, length-prefixed ASCII `1.000000`, one framed zlib chunk, and a body beginning `01 00 01 00` followed by a u16 child count. One file record is kind `00`, length-prefixed name and author-source strings, u32 payload length, payload and zero u16 children.

Record expected byte offsets manually for a tiny example. Mutate one field/region at a time for refusal tests. Include a separate independently generated compressor/reference for the engine differential campaign. This checks a proposed observed framing profile; it cannot prove that all Phoenix packages use it.

## 3. Capture, dispatch, containers and namespace acceptance

Proposed home: `test_creator_phoenix_capture.gd` / `test_creator_phoenix_package.gd`, with shared archive tests owned jointly with ClearView. Those filenames are proposals. Reuse existing `test_creator_clearview_readers.gd` fixtures only where the generic contract is actually identical.

| ID | Setup and action | Decisive oracle |
| --- | --- | --- |
| PX-C01 | Valid small standalone PKG, PKG inside ZIP, installed model folder, existing GLB/STL; misleading suffixes | Content dispatch chooses the supported reader; each exact captured input is hashed once per owned read. No ZIP is automatically assigned to ClearView. Unsupported/ambiguous data produces a typed discovery result. |
| PX-C02 | Mixed-provider ZIP, paint-only package, VAR without base, preview/site-only input | Distinct complete candidates are explicit; no thumbnail/site/variant is promoted to an aircraft. Shared outer metadata/namespace is checked before provider selection. |
| PX-C03 | With a scaled test capture limit, many individually sub-limit directory files cross the aggregate total | Refusal before accepting the over-budget write; total original capture and private disk counters remain bounded; no accepted Store state changes. Test a single member crossing its own bound separately. |
| PX-C04 | FIFO, socket/device, symlink/junction and substituted intermediate directory on each supported OS | Unsafe kinds are refused without a blocking read; prohibited links are not followed. Unsupported platform guarantees produce `UNSUPPORTED_CAPTURE`. Use controlled processes/timeouts, not a test that can hang CI indefinitely. |
| PX-C05 | Controlled replacement/growth/truncation while capturing; same-size byte mutation | The resulting guarantee is truthful: either capture refuses, or receipt/hash/parser refer to precisely the captured bytes. No claim of an atomic directory instant based only on unchanged stats. Subsequent original-path mutation has no effect. |
| PX-C06 | Report target equals source, hardlink/symlink alias or pre-existing receipt | Exclusive output creation refuses; all before/after input hashes match. No partially written success report. |
| PX-C07 | ZIP local/central disagreements, invalid CRC, overlapping ranges, unsupported method/flags/encryption/ZIP64/multidisk | Layer-specific refusal before verified-member promotion. For lazy payloads, untouched members remain payload-unchecked; selecting a bad-CRC member refuses even if the index passed. |
| PX-C08 | PKG wrong marker/header/body prefix/kind, truncated field, arithmetic overflow or file with children | Stable profile/format refusal and real span where attributable. Header `1.0` is unsupported by this profile; no unsupported claim of corruption or simulator version. |
| PX-C09 | Truncated zlib, checksum error, output shorter/longer than declared, second stream or unused compressed bytes | Exact-size/EOF/consumption checks refuse; no partial member. Run against Python reference and the pinned Godot adapter; do not assume identical APIs. |
| PX-C10 | Two nested decode edges each produce 8 MiB under a scaled 12 MiB work limit | Both individually fit but the job refuses at aggregate output greater than 12 MiB. No reset at ZIP→PKG or re-read. Logical reuse without decoding does not spuriously double-charge. |
| PX-C11 | Each count/depth/name/member/chunk bound at limit−1, limit and limit+1; long zero-output progress | Accept only profile-permitted boundary cases; reject before allocation beyond bounds; cancellation/work checks still run without output. Use scaled limits for unit tests and measured real ceilings in platform tests. |
| PX-C12 | `foo` file + `foo/` directory; `foo` file + `foo/bar`; duplicate file; duplicate explicit directory; empty name | Full-tree refusal includes unselected and empty-directory occurrences. One implicit directory confirmed by one explicit directory is accepted. Research report acceptance is not reused as a runtime pass. |
| PX-C13 | `../x`, absolute/drive/UNC forms, embedded separator/NUL, case alias, unsupported encoding and normalization alias | Admission refuses under the selected path profile without extraction or normalization collisions. Raw bytes remain distinct from display; no first-match lookup. |
| PX-C14 | Body trailer: none, allowed zeros, within-bound nonzero, 513 nonzero bytes | Valid zero trailer accepted only within the observed bound; specific nonzero span when inspected; over-limit trailer reports neutral `TRAILING_DATA_LIMIT`. No inference that unexamined bytes are zero. |
| PX-C15 | Whole Jets/AllPublic archives and separately prepared small selections with lineage; bounded concurrent/replaced jobs | Whole inputs exceed the 64 MiB profile and refuse. Derived fixture has its own capture identity and documented parent/member evidence. Active/unreaped jobs cannot exceed process-wide staging reservations; cleanup touches only private unaccepted data. |

## 4. Definition and dependency acceptance

Proposed home: `test_creator_phoenix_definition.gd` / `test_creator_phoenix_observations.gd`. Preserve the Python observed-profile suite as a cross-language reference, not a substitute for runtime admission.

| ID | Setup and action | Decisive oracle |
| --- | --- | --- |
| PX-D01 | Equivalent admitted LF/CRLF definitions, absent final newline, comment markers inside strings and at line ends | Exact source bytes, numeric lexemes and spans retained; expected syntax tree/observations agree without executing Lua. Line/byte-column diagnostics agree with hand-counted offsets. |
| PX-D02 | Calls, expressions, unexpected assignment root, unobserved escapes/exponents, mixed table forms, bare CR, NUL/binary bytes | Profile-specific refusal at the actual token/span. Unsupported text is never skipped as a comment or partially adopted. |
| PX-D03 | Exact duplicate keys and separate case variants; repeated surface names in separate contexts; empty geometry list | Exact duplicates refuse; case variants survive syntax and get explicit mapping ambiguity; structural occurrence identities remain distinct. Empty does not invent geometry or topology. |
| PX-D04 | `Engine` as string, number and table; source sound/airfoil references; misleading familiar field names | Type/context registry controls interpretation. No engine-sound label becomes propulsion data, NACA label becomes a polar or `nodeCount` becomes verified GEO nodes. |
| PX-D05 | Token/string/numeric/depth/object/diagnostic limits; finite lexeme overflow and exact distinct hinge decimals collapsing in float64 | Typed bounded refusal/observation with correct phase; no nonfinite adopted value, silent precision-collapse binding or unbounded retained path strings. |
| PX-D06 | The 8,421-byte long-path MOD plus variants just below/at/above report budget | New runtime contract produces bounded `REPORT_LIMIT` before retaining/serializing an oversized report. Fixed failure envelope, no partial success, real triggering span or explicit phase-unavailable location. Record peak memory separately from output length. |
| PX-D07 | Required geometry missing but same basename exists in another root; optional sound absent; optional sound resolves twice | Missing mandatory dependency stops visual stage; absent optional sound permits only the stated omission. **Two optional matches refuse ambiguity**; no arbitrary first match or false omission. |
| PX-D08 | Two distinct candidates with identical texture/GEO bytes and repeated internal node occurrences | Byte storage can deduplicate, but candidate/member/object identities include entry occurrence and selection; neither aircraft is merged into the other. |
| PX-D09 | Container A paired with B's valid MOD, report or GLB; recompute all advertised hashes | Re-establish actual membership from A and conversion from its selected closure; refuse the forged join. A matching supplied inventory row is insufficient. |
| PX-D10 | Change source unit/frame/mapping profile, selected scheme, root, parser policy or one required dependency behind the same name | Exact relevant fingerprint changes; affected observations/conversion cache miss or refuse; no silent reuse, source rebinding, ambient fallback or network dependency fetch. |

## 5. Geometry, appearance and motion acceptance

Proposed homes: `test_creator_phoenix_geometry.gd` / `test_creator_phoenix_motion.gd`. Existing anchors: `test_creator_glb.gd`, `test_creator_import.gd`, `test_creator_visual.gd` and `test_creator_clearview_motion.gd`. All geometric constants below are original test data, **not Phoenix axis/scale facts**.

### 5.1 Independent numeric fixtures

**Reflection triangle, decoder only.** Vertices A=(0,0,0), B=(1,0,0), C=(0,1,0), CCW indices [0,1,2], normal +z, distinct UVs. Under reflection x, output positions are (0,0,0), (−1,0,0), (0,1,0); indices [0,2,1] keep normal +z. Preserve each corner's UV association. This XY fixture has zero z extent and should fail complete current Creator admission. Include a separate known clockwise source-convention fixture before determinant reversal.

**Asymmetric 3D tetrahedron, complete visual route.** Positions p0=(0,0,0), p1=(2,0,0), p2=(0,1,0), p3=(0,0,3). Outward faces [0,2,1], [0,1,3], [0,3,2], [1,2,3]. Reflect x and reverse each face once after canonical winding: bounds become (−2,0,0)…(0,1,3). Compare ordered corners, normals, UVs and material slots, not only bounds.

For a fully specified attribute fixture, assign every corner of those four faces its face normal, respectively (0,0,−1), (0,−1,0), (−1,0,0), (3/7,6/7,2/7). In each listed source face order, assign UVs (0,0), (1,0), (0,1); assign face materials M0, M1, M0, M1. M0 has base-color factor (1,1,1,1), M1 (1,0.5,0.25,1); both use the same test PNG, metallic 0, roughness 1 and OPAQUE mode. After reflection the normals are (0,0,−1), (0,−1,0), (1,0,0), (−3/7,6/7,2/7). Reversing each output face gives indices [0,1,2], [0,3,1], [0,2,3], [1,3,2] before corner splitting; UVs follow their source corners, not their new ordinal. Face material IDs remain M0/M1/M0/M1. This intentionally requires per-face normal/UV seam splits.

**Nested transform.** Child-local point (2,0,0); rotate +90 degrees about z, then translate (0,2,0); parent translates (4,0,0). Source world is (4,4,0). Test map `0.5 * diag(−1,1,1)` gives (−2,2,0). This detects multiplication-order and double-transform errors.

**Reflected hinge.** h0=(0,0,0), h1=(1,0,0), moving point (0,1,0), source +90 degrees around +x → (0,0,1). After reflecting x, directed axis is −x; the matching mapped angle is −90 degrees, still yielding (0,0,1). Test intermediate angles with independently calculated sine/cosine answers.

**Pivot wrapper.** Parent P=T(10,0,0), old child G=T(12,0,0), pivot H=T(11,0,0), axis +z. Wrapper W=T(1,0,0), child local L=T(1,0,0). Child-local (0,1,0) moves from (12,1,0) to (10,1,0) at +90 degrees. Verify sibling poses and actual admitted Creator binding behavior.

**Texture/alpha.** Original 2×2 RGBA8 image: upper row red (255,0,0,0) / green (0,255,0,128), lower row blue (0,0,255,255) / white (255,255,255,255). Nearest-sampled UV centers (0.25,0.25), (0.75,0.25), (0.25,0.75), (0.75,0.75) address those texels in that order. For the separate alpha test use unit base-color factor, opaque black background, MASK cutoff 0.5 and straight-alpha source-over composition. The independent oracle below is linear RGB before display encoding, lighting or tone mapping; a renderer test must pin/verify those settings rather than compare unspecified screen pixels.

| Material mode | Red texel result | Green texel result | Blue / white result |
| --- | --- | --- | --- |
| OPAQUE | (1,0,0) | (0,1,0) | (0,0,1) / (1,1,1) |
| MASK, cutoff 0.5 | Discard → black | Retain → (0,1,0), because 128/255 exceeds 0.5 | Retain original blue / white |
| BLEND over opaque black | (0,0,0) | (0,128/255,0) | (0,0,1) / (1,1,1) |

All composed output alpha values are 1 over this opaque background. Sample/compose this oracle independently from the converter and then check the configured renderer; record any color-encoding conversion explicitly.

Predeclare numerical tolerances from source/export representation and float32 storage. Record maximum/RMS errors for numeric comparisons, and exact mismatches for topology/identity/material association. Never select tolerance after seeing the result. A known reference rendering supplements these measurements; it does not replace them.

### 5.2 Acceptance matrix

| ID | Setup and action | Decisive oracle |
| --- | --- | --- |
| PX-G01 | Owned editable source/export pair, exact Builder version/settings, independent held-out workflow | A documented GEO profile decodes the independently known data; report exact scope. Until available, `UNSUPPORTED_GEO_PROFILE` is the correct outcome, not a guessed mesh. |
| PX-G02 | Unknown record, truncated record, overlap, invalid index/reference, nonfinite scalar, graph cycle | Refuse affected capability. Skip only a record class explicitly proven skippable by that exact profile; “unknown” never implies optional. |
| PX-G03 | Reflection triangle with independently known CCW and clockwise source winding | Canonical source normalization plus determinant parity produces correct oriented triangles/UVs/normals; unknown winding blocks correspondence. XY case remains decoder-only. |
| PX-G04 | Asymmetric tetrahedron through conversion, independent validator and Creator admission | Exact expected bounds/corner associations; both format and project admission pass for the valid fixture; wrong-but-valid geometry fails independent source equivalence. |
| PX-G05 | Nested transform, differently transformed instances of one source mesh and duplicate-byte members | Expected world points match without double application; duplicate instances rebase/duplicate where needed; logical object IDs remain separate from content deduplication. |
| PX-G06 | Missing normals, nonuniform/reflected transform, normal map and a UV flip | Either qualified normal/tangent-frame conversion with correct handedness/lighting, or explicit unresolved mapping. No blind reuse of source tangents or false smoothing-preservation claim. |
| PX-G07 | UV and hard-normal seams, multiple materials, 2×2 image and OPAQUE/MASK/BLEND cases | Corner tuple splitting and material slots remain correct; expected sampled colors/alpha outcomes; no thumbnail selected as diffuse map or double UV/image flip. |
| PX-G08 | Oversized/deceptive source image, opaque BMP-named data, unsupported TGA/DDS, aggregate pixel overflow | Content/profile refusal with bounded native workspace and decoded pixels; a suffix never authorizes a decoder. Each output PNG also passes existing admission. |
| PX-G09 | Highest valid index and one-past-last; u8 index 255 with 256 vertices; u16 index 65535 | Converter chooses legal component width, promotes reserved maxima, and rejects true range errors. Independent validator and Creator results recorded separately; investigate the current preflight gap without claiming it reproduced here. |
| PX-G10 | Misaligned/truncated accessors, attribute count mismatch, forbidden transform, skins/morph/animation/sparse data, nonempty `extensionsRequired` | Current Creator subset enforced in addition to generic format validity. Test limits−1/at/+1 and zero-axis bounds without overallocating. |
| PX-G11 | Zero hinge, exact distinct decimals collapsing after conversion, `1e−250` separation, unrepresentable subtraction, oblique axis | No naive squared-norm underflow/overflow; small representable axes normalized with scale-safe arithmetic. Unknown units do not justify arbitrary epsilon rejection. Unrepresentable motion remains unavailable. |
| PX-G12 | Reflected hinge and pivot-wrapper numeric fixtures at neutral, intermediate values and both ends | Actual Creator pose matches independently mapped rigid motion, correct sign and unchanged siblings. Axis alignment alone is insufficient. |
| PX-G13 | Nonuniform/sheared parent, overlapping subtree bindings, too many parts, source gain/offset/mix beyond `sign * role_angle` | Verified rebasing/approved extension or explicit static-only result; no unsupported transfer function or conflicting geometry is silently flattened. Distinguish 25-degree preview from physical surface angles. |
| PX-G14 | OBJ recovery with separate/negative corner indices, missing MTL/image, concave polygon and escaping reference | Exact supported directive profile only; tuple splitting and closure enforced; triangle-only policy refuses unsupported polygons. No claim of original GEO/rig/physics recovery. |
| PX-G15 | Admitted visual GLB B associated with source A; scheme change with valid cached geometry | Source-equivalence/selection association catches the mismatch even if both GLBs validate. Geometry, appearance and motion evidence are versioned separately. |

## 6. Creator, provenance, derivation and persistence acceptance

Proposed homes: `test_creator_phoenix_integration.gd` and extensions to existing shared-owner suites. The new provider must not bypass a shared contract merely to avoid modifying a shared test.

| ID | Setup and action | Decisive oracle |
| --- | --- | --- |
| PX-R01 | Inspect caller-owned byte buffer, then mutate the original argument before adoption/trial; mutate nested report dictionaries; delay inspection at a controlled barrier | Consumer uses defensively owned bytes or detects the changed identity before acting. Digest, parsed data, source bytes and visual cannot disagree. Existing returned-copy tests alone do not cover caller-buffer aliasing. |
| PX-R02 | Known provider in source metadata only, retained record only, both matching, both conflicting, one removed, and unknown schema/provider | Apply closed provider rules consistently at every relevant route. Removing one recognized context does not remove its restriction. Fully stripped independently supplied GLB has no false origin-authentication guarantee. |
| PX-R03 | Valid same-UUID definition A with physically different valid raw B; recompute binding, blobs, record/index/pointer hashes | Trusted recompile rejects A/B even when structure and all hashes agree. Unmodified A/A and B/B pass the new supported proof path. Run legacy/new publication and reopen/resolver variants. |
| PX-R04 | Warm package/thrust/document caches; replace package bytes or compiler implementation behind unchanged display IDs/profile labels | Verified content/context changes miss or refuse caches. Proof uses exact package bytes and implementation; no ID/SOC/revision-only cache result counts as recompilation. |
| PX-R05 | Identical numeric adopted value with source A vs source B; identical numbers with differing evidence kind; then a truly read-only report edit | Compile cache includes consumed provenance. If emitted quantity kind/source differs, canonical raw bytes may differ even when physics numbers match. Report-only changes with identical complete compile projection keep raw bytes identical. |
| PX-R06 | Observe → explicitly adopt → manual override → save/recovery → reopen → compile/publish/resolve where admitted | Value, units, raw source span, observation identity, mapping version, original ancestry and override disposition survive each step. Source-authored values are not silently relabeled measured or player-entered. |
| PX-R07 | Borrowed inventory mass, manual position component, estimated size and mixed-origin vector; edit via item setter | New per-property/component schema preserves differences or rejects unsupported adoption. Emitted quantities and vector aggregate evidence remain honest after save/reopen/compile. No single item-wide measured/borrowed label covers unrelated edits. |
| PX-R08 | Change only paint, scheme or review annotation; separately adopt a physical change | First branch changes review/visual identity only if the entire compile projection is unchanged. Second branch recompiles affected physical bytes and invalidates dependent qualification. |
| PX-R09 | Replace source bytes/root with same filename while keeping unrelated edits; old observation adoption request races replacement | Old source association is cleared or requires explicit review; stale request refuses by source/report/revision identity. Unrelated authored values remain; old spans never silently bind to new bytes. |
| PX-R10 | Worker A paused; choose B or change scheme/revision, finish B, release A | B/current accepted document remains; A cannot adopt, publish, cache a success or seed a trial. Verify cache contents and Store pointer, not merely visible UI. |
| PX-R11 | Cancel/close during capture, inflate, image work, conversion and a bounded non-cooperative call; repeat imports | Cancellation outcome and latency match measured policy; old workers are reaped; worker/buffer/private-disk reservations remain bounded. Closing cannot call the same Store instance concurrently with worker operations. |
| PX-R12 | Store pointer/index externally altered with same generation; stale expected draft record SHA or aircraft revision; two writers | Existing exact-pointer/index and operation-specific CAS checks refuse, even when generation matches. Quota/dedup/index are calculated under valid exclusive ownership, not stale pre-lock state. |
| PX-R13 | Controlled barrier immediately before cancel/commit arbitration and immediately after COMMITTING wins | Cancel-first preserves old accepted pointer; commit-first reports pending then actual result. Never return “canceled” after successful pointer publication or “committed” before verified readback. No double commit. |
| PX-R14 | Fault at staged object/index, pointer transition and current `FAULT_READBACK_LOST` stage | Failure before transition preserves prior accepted state; unproven readback produces UNCERTAIN and requires reopen. No deletion of accepted/shared history. Record filesystem durability scope separately. |
| PX-R15 | Two drafts/revisions share a closure; archive one; exact quota boundary; original archive+derived GLB+manifest/history costs | Logical associations remain distinct, bytes may deduplicate, quota covers accepted retained data, archival frees nothing under current append-only policy. Cancellation removes only private unaccepted staging. |
| PX-R16 | Reopen exact older source ref after later publication; missing original enclosure but present members/GLB; changed external download | Resolve exact revision or give explicit unavailable result. Without original bytes/approved membership proof, container membership cannot be reconstructed from member hashes; no “original backup” claim or substitution with latest. |
| PX-R17 | Warm Store object verification/dedup cache; replace stored object with different same-size bytes; publish a new closure referencing it | New association/retention guarantee freshly rechecks reused bytes or relies on a separately qualified immutability mechanism. Cached hash/size alone is insufficient. Mark this as a new targeted case, not an executed current-Store exploit. |
| PX-R18 | Exercise draft save/recovery/load, legacy and compiled publication, aircraft load, resolver, direct trial freeze/verify and actual UI route | Same provider/association/domain restriction holds at every acting boundary. No bypass through a helper/API that the guarded UI does not use. |
| PX-R19 | Concurrent load/save/recovery/close requests against one Store instance; cancel while writer owns transition | One serialized owner handles all instance operations; no thread-unsafe cross-calls, teardown races or blocking UI. Process lock alone does not establish instance thread safety. |
| PX-R20 | Unknown historical compiler profile, changed package profile, unqualified cross-platform byte result; old revision admitted under policy A but refused by tightened policy B | Derivation/current use unavailable without rewriting historical bytes. No old cache hit, replay or launch bypasses current policy. An explicitly approved migration creates a new revision with new evidence. No post-hoc tolerance or relabeling accepts a mismatched pair. |

### 6.1 Construct the recomputed-hash counterexample explicitly

```text
create owned valid definition A and B in the admitted compiler domain
use the SAME aircraft UUID, but different effective physical input
compile A and B independently using the pinned context
require raw_A != raw_B
build a proposed saved record using definition_A and raw_B
recompute every association/blob/record/index hash and valid pointer encoding
do not retain A's old compile-binding hash by accident

exercise publication/reopen/resolver through the relevant owner fixture
expect DERIVATION_MISMATCH at the trusted recompile boundary
confirm A/A and B/B positive controls pass
confirm a failed candidate cannot replace the prior accepted Store pointer
```

Current `test_creator_source_ref.gd` has a mixed-pair test whose binding remains from A. It tests an important hash mismatch, but not this stronger recomputed-binding counterexample. Extend it rather than counting it as existing coverage. Runtime execution of the new case remains pending.

### 6.2 Existing suite anchors

| Concern | Existing suite(s) at the audited main |
| --- | --- |
| Compile receipt, semantic pair, exact source ref | `test_creator_compile_binding.gd`, `test_creator_source_ref.gd` |
| Compiler domain/provenance/cache projection | `test_creator_compiler.gd`, `test_creator_clearview_observations.gd` |
| Provider markers and source associations | `test_creator_source_installation.gd` |
| Frozen trial ownership and mutation | `test_creator_trial.gd`, `test_creator_import.gd` |
| Stale jobs, saved selection and UI adoption | `test_creator_clearview_ui.gd`, `test_creator_selection_state.gd`, `test_creator_persistence_ui.gd` |
| Persistence faults/CAS/quota/recovery | `test_creator_store.gd` |
| Saved trial still unavailable | `test_creator_published_trial.gd` |

Paths are under `app/tests/`. They are implementation starting points, not permission to relax prior ClearView/Creator assertions.

## 7. Application and exported-runtime gates

| ID | Setup and action | Decisive oracle |
| --- | --- | --- |
| PX-F01 | Valid conventional aft-tail single-tractor electric candidate; twin EDF, biplane, pusher, retract/flap/vectoring and helicopter counterexamples | Only the exact owner-supported compiler domain may proceed. Others remain accurately report/visual-only until their physical capabilities and gates exist; no default trainer substitution. |
| PX-F02 | Draft launch through Creator UI → app root freeze/check → Main verify/build, including forged/edited requests | Every real acting route checks exact frozen identities and supported backend/start/environment/numerical gates. Successful schema loading or trim alone does not complete the applicable campaign. |
| PX-F03 | Attempt saved-aircraft start through current PublishedTrial helper and any future connected route | Current helper remains unavailable. Enabling it requires its owners' separate live-route evidence; helper-only passing tests cannot imply the application is wired. |
| PX-F04 | Clean exported Windows/Linux/macOS builds, initially supported profiles and limit/adversarial cases | Record actual CPU/RSS/VRAM, staging disk, import/cancel latency, UI responsiveness, close/reopen and exact outcomes. Pinned-engine headless tests and proposed caps do not establish exported performance. |
| PX-F05 | Existing ClearView/GLB/STL imports, draft edit/save/recovery and trial flows after shared changes | Existing admitted profiles retain behavior and restrictions. New provider dispatch/schema code does not broaden old validators or change unrelated canonical physical output. Run only the owner-required shared regression scope for changed interfaces. |

### 7.1 Commands for application implementation work

The audited application pins `4.8.beta2.official.cafc17a19` through `app/get-godot.sh`. Follow current `AGENTS.md` and the [shared-host test admission guide](../../../tools/testqueue/README.md): on enrolled hosts, route compatible independent checks through `sim_test_launch`, then `sim_test_status` and same-request `sim_test_recover` as needed, or the documented pool CLI. Retain the frozen source/request identity; a bridge port is not session ownership.

The standalone example below is for an **unenrolled/private runner**, a complete application checkout, and the pinned-engine resources already imported as required by [the engine workflow](../../tools/shared.md#engine). It runs an existing focused suite, not the new proposed cases:

```sh
godot_path="$(app/get-godot.sh)"
python3 tools/godot/run_checked.py --label creator-compile-binding --timeout 240 -- \
  "$godot_path" --headless --path app --audio-driver Dummy \
  --script res://tests/test_creator_compile_binding.gd
```

After implementing a proposed test file, replace the script/label with that actual test. Do not run a nonexistent proposed filename and call it coverage. Read `CONTRIBUTING.md` and current owner/test routing for the touched application files; required repository gates remain applicable.

For geometry campaigns, pin the independent Khronos validator release/artifact hash and record its JSON report alongside Creator admission and numeric-oracle results. Use its documented interface for that pinned version. No validator execution, Godot runtime suite, exported build, physical flight campaign or real GEO conversion was performed by this documentation audit.

For this documentation-only change, validate JSON receipts, added/affected local links, code-path references, exact fixture/source hashes, table/case consistency and `git diff --check`. Do not run a sparse checkout as though it were a complete game installation.

## 8. Delivery sequence

These are proposed review slices within existing AC-PX ownership, not new milestones or completed work. Each slice updates the parent plan only after its evidence exists.

| Slice | Concrete output | Required evidence before advancing |
| --- | --- | --- |
| PX-I1 — Capture and inspection | Qualified capture backend, shared content dispatch, complete PKG tree and virtual namespace, bounded budgets/reports | PX-C01…15; output remains inspection-only; generic ZIP changes reviewed with ClearView owner |
| PX-I2 — Definition observations | Restricted runtime MOD parser, typed schema/reference pass, readonly checked report and candidate closure | PX-D01…10; source hashes/locations preserved; no physical adoption or general Lua |
| PX-I3 — GEO feasibility | Owned independently known export corpus, documented narrow grammar and bounded source representation | PX-G01…05 plus malformed cases; hold-out workflow; stop if no independent correspondence |
| PX-I4 — One visual route | One narrow selected aircraft/scheme → admitted GLB; images and supported rigid articulation | PX-G06…15, independent validator+Creator+oracle, explicit static-only omissions; no flight claim |
| PX-I5 — Authoring/provider integration | Closed next definition/snapshot version, typed provider registry, explicit in-memory adoption/overrides and real entry-point guards | PX-R01/02 and in-memory/schema portions of PX-R06…10; new-provider publish/reopen/flight proof routes stay unavailable pending I6. PX-R18 refusal guards must hold; existing unrelated ClearView/legacy behavior remains unchanged. |
| PX-I6 — Retention and derivation | Versioned closure storage, trusted exact recompile context, complete cache keys, serialized cancellation/CAS commit behavior | PX-R03…07 persisted round trips and PX-R11…20, including positive supported routes after the earlier refusal guards, fault injection and reopen; no false saved-original claim |
| PX-I7 — Exact flight candidate | Actual supported physical authoring/configuration and current trial route | PX-F01…03 and applicable owner numerical/capability campaigns; additional mechanisms enter their owning plans |
| PX-I8 — Release profile | Clean exported builds, measured limits and cancellation, documented compatible specimens/stages | PX-F04…05; current support matrix and unresolved cases; no claim based on catalog totals |

Inspection work can proceed while source-geometry research is blocked. General UI, flight and large-pack support must not be scheduled as though GEO, physical domain or platform capture were already qualified.

### 8.1 Review exit checklist

A slice is reviewable when its public contract, implementation scope, positive and negative oracles, exact commands/results and remaining unsupported cases agree. All “passed” claims have receipts; all source-derived hypotheses remain labeled until reproduced.

Stop the affected stage when source encoding, unit/frame semantics, namespace identity, mandatory closure, GEO record meaning, source/output association, physical derivation or applicable numerical admission is unresolved. Preserve the user's original input and prior accepted state. Useful earlier-stage evidence can still be delivered without promoting later capabilities.
