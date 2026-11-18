# Phoenix importer implementation guide

Status: proposed implementation contract, audited on 2026-11-18. No production Phoenix reader, GEO decoder, schema migration or flight support is delivered by this document. The [parent plan](../phoenix-aircraft-import.md) alone owns AC-PX status. The [verification guide](verification.md) defines fixtures and acceptance; the [dated audit](../../research/aircraft-creator/phoenix-plan-audit-2026-11-18.md) separates reproduced findings from source inspection and proposals.

## 1. Baselines and how to use this guide

Application baseline: [main `39fa2746ae4f4ba8698b87db279adcfe84ef5d17`](https://github.com/bultodepapas/OpenRCsimulator/tree/39fa2746ae4f4ba8698b87db279adcfe84ef5d17). Research baseline: [`3619c19362064a0a51b6fda360adce0bfeb38b3d`](https://github.com/bultodepapas/OpenRCsimulator/tree/3619c19362064a0a51b6fda360adce0bfeb38b3d). These are different code lines. Rebase and check interfaces before implementation; do not copy runtime assumptions from the research branch into current main.

Names in pseudocode, proposed records and module tables below are design contracts, not callable APIs. Existing identifiers are identified explicitly. Pin the reviewed limits, parser/converter implementation, package contents and engine for each qualification. A profile label identifies a contract; it does not authenticate executable code.

Deliver the work in bounded changes: capture/container inspection, definition observations, independently proven geometry, then Creator/Store integration and the applicable flight gates. Inspection can be useful while GEO remains unresolved. Do not make schema or UI work depend on imaginary GEO record offsets.

### 1.1 Actual seams that implementation must change

All paths in this table refer to the application baseline unless marked research.

| Existing seam | Observed behavior | Required coordinated change |
| --- | --- | --- |
| `app/ui/aircraft_creator.gd` import routing | ZIP selections enter the ClearView route; picker text is ClearView-specific | Shared bounded capture and content discovery; explicit provider/candidate selection; retain the existing ClearView route and tests |
| `app/workshop/creator/source_importer.gd` | GLB/STL inspection, 32 MiB source ceiling; no Phoenix package reader | Feed only the exact converted GLB bytes through existing admission; qualify capture and cancellation separately |
| `clearview/archive.gd`, `clearview/deflate.gd` and `inflate.gd` under Creator | Reviewed but format-specific ZIP, raw DEFLATE and zlib ingredients | Owner-reviewed generic archive profile and shared job budget; do not confuse raw DEFLATE with a zlib stream |
| `authoring.gd` / `definition.gd` | Source observations and restoration are statically ClearView-specific; Definition formats v1–v4 are closed | A new closed provider-aware definition/snapshot version, typed adoption and explicit migration |
| `source_installation.gd` | Recognizes `openrc_clearview` only | Closed provider dispatch and provider-specific association checks |
| `compiled_publication.gd` / `compile_binding.gd` | Current source restrictions and a v1 receipt for definition/raw hashes | Apply every provider restriction; independently establish definition-to-physical derivation |
| `packages.gd` / `authoring.gd` | Package lookup caches by ID; thrust cache by ID/SOC; compilation caches by document revision | Content-keyed verified package context, or an uncached proof path |
| `store.gd` / `source_resolver.gd` | One source blob, append-only history, source-ref resolution and structural pairing | Versioned retained closure, exact saved revision, trusted recompile/association verification |
| `trial.gd` → `app/app_root.gd` → `app/main.gd` | Existing draft freeze/check/verify launch chain | Add Phoenix admission to the real entry points, preserving independent numerical/environment gates |
| `published_trial.gd` | `check_start` always reports unavailable; helper is not a live application launch hook | Keep unavailable until its separate owners qualify and connect the saved-aircraft route |
| `research/aircraft-creator/phoenix/inspect_pkg.py` | Bounded research framing/tree probe; directory identities omitted from JSON | Port reviewed framing, not the report as an admission tree |
| `research/aircraft-creator/phoenix/inspect_definition.py` | Restricted byte parser and preflight, late report-size check | Typed bounded diagnostics and incremental output accounting before runtime reuse |

### 1.2 Proposed modules and ownership

| Proposed module or responsibility | Inputs → outputs | Ownership boundary |
| --- | --- | --- |
| Shared `capture` and `archive_dispatch` | User selection → immutable captured bytes and discovery | AC/AE/platform and ClearView owners |
| `phoenix/pkg_reader.gd` | Frozen bytes + budget → complete raw entry tree | Phoenix AC-PX-01; no path writes |
| `phoenix/namespace.gd` and `candidates.gd` | Raw tree → admitted identities, candidates and dependency closure | AC-PX-01 |
| `phoenix/mod_reader.gd` and `observations.gd` | MOD bytes → ordered syntax tree → versioned observations | AC-PX-02; no execution or value adoption |
| `phoenix/geo_reader.gd` | Qualified GEO profile + bytes → source geometry representation | AC-PX-03; blocked pending independent evidence |
| `phoenix/visual_converter.gd` | Geometry, selected scheme and proven transforms → GLB + association receipt | AC-PX-03/04/05; reuse Creator admission |
| Shared provider/adoption interfaces | Checked observations + explicit review → authoring transaction | AC/AE and ClearView/Flight Simulator owners |
| Shared retained closure and verification | Immutable source/definition/visual/physical data → saved revision | Store/resolver/compiler owners |

Do not introduce a Phoenix-specific force evaluator, arbitrary package plugins or a second authoring system. Register readers in trusted application code. Untrusted files select among allowed formats; they cannot name an executable, script, decoder DLL or network service to load.

## 2. Data contracts and honest support states

Proposed records must behave as immutable once admitted. This is an enforced contract, not a property of an ordinary GDScript dictionary: current `trial.gd` explicitly rechecks frozen trials because dictionaries remain mutable. Use private captured storage, defensive byte copies or an equivalent reviewed capability, and verify actual bytes/identity at every acting boundary: result adoption, conversion, trial use, publication and reopen. Hash and parse the same owned buffer/read; do not trust a `sealed=true` flag or a stale receipt after returning a mutable array. Each schema is closed and versioned; unexpected keys or unknown versions fail that record's admission. Bounds apply to identifiers, arrays and error text as well as payloads.

```text
CapturedInput {
  capture_id, kind, byte_count, sha256,
  immutable_handle,
  capture_profile, guarantee, member_capture_receipts[]
}
RawEntry {
  occurrence_id, parent_occurrence_id, kind: FILE | DIRECTORY,
  raw_name_bytes, source_span, raw_component_chain,
  payload_span_or_handle?, declared_size?, actual_size?, sha256?
}
Candidate {
  id, provider, container_profile,
  root_occurrence_id, definition_occurrence_id,
  geometry_occurrence_ids[], scheme_id, dependency_manifest,
  source_fingerprint, discovery_diagnostics[]
}
Observation {
  id, source_fingerprint, definition_member_sha256,
  occurrence_id, key_bytes, span, raw_lexeme_or_value,
  interpretation_profile?, value?, unit?, evidence_class,
  unresolved_reasons[], adopted_field_id?
}
ConversionReceipt {
  schema, source_fingerprint, selection_fingerprint,
  parser_and_converter_fingerprints, policy_fingerprint,
  input_member_identities[], source_to_output_node_map[],
  frame_and_material_profiles, omissions[],
  output_glb_sha256, independent_oracle_receipt?
}
Failure {
  code, stage, safe_detail,
  location: BYTE_SPAN | ENTRY_OCCURRENCE | PHASE_UNAVAILABLE,
  location_value, bounded_limit_context?, source_id?
}
```

These records bind claims; they do not sign/authenticate authors, licenses, tools or physical accuracy. Receipts supplied by an archive are assertions until the trusted reader recomputes the relevant relation.

Maintain separate capabilities, not one `supported=true` flag:

| Capability | Evidence required | Failure preserves |
| --- | --- | --- |
| Captured | Exact immutable selected bytes under a qualified capture profile | Input unchanged; capture diagnostic |
| Container indexed | Accepted structure and full namespace; payload claims distinguish unchecked members | Captured bytes and bounded report |
| Definition parsed | Exact observed grammar consumed | Container evidence |
| Dependencies resolved | Unique selected closure with checked bytes and required references | Parsed observations with missing/conflicting references |
| Visual admitted | Qualified conversion, supported GLB admission and source correspondence | Definition/package report |
| Motion admitted | Supported role, neutral/sign/end-pose correspondence | Admitted static preview |
| Physical authoring accepted | Explicit values/provenance within the current compiler domain | Visual/observations |
| Trial eligible | Exact frozen candidate and applicable numerical/start/backend checks | Editable draft |
| Saved revision verified | Retained objects, exact source ref, source and compile associations rechecked | Previous accepted revision or a precise unavailable result |

Visual-only success must not create a default trainer with an implied Phoenix flight model. A biplane, twin EDF, pusher, helicopter or retracting aircraft does not enter a conventional trainer compiler because its MOD parsed.

## 3. Capture, dispatch and job budgets

### 3.1 Capture contract

The current `FileAccess` bounded read is not evidence of nonblocking special-file handling, no-follow path traversal or an atomic directory snapshot. Select a platform implementation before shipping directory import. A reviewed native helper/GDExtension or broker is a possible implementation; none is implied to exist today.

```text
capture(selection, profile, ticket):
    ticket.check_active()
    handle = platform.open_selected_object(
        no_follow_at_each_component = true,
        refuse_special_without_blocking = true,
        ownership = current_user_selection)
    if these guarantees are unavailable:
        fail UNSUPPORTED_CAPTURE at phase "open"
    if handle.kind is not a permitted regular file or directory:
        fail UNSUPPORTED_FILE_KIND
    if file:
        precheck size when reliable; stream under absolute actual-byte bound
        hash the same chunks written to private immutable capture storage
        check cancellation/work budget between bounded chunks
        seal capture; parse only sealed bytes
    if directory:
        enumerate under owned directory handles, with entry/depth/name limits
        capture each allowed regular member with the same rules
        charge actual member bytes to the shared aggregate original-capture limit
        record exact observed membership and change/missing/refusal results
        seal the manifest and each member
    return exact captured bytes + declared capture guarantee
```

Before/after size or timestamps do not prove a coherent multi-file instant; same-size mutation is a counterexample. Without a real qualified snapshot facility, state “exact bytes captured during this operation,” not “atomic source snapshot.” Parsing must never reopen the original path, follow an author-local path, or fetch a package-provided URL. Reporting uses exclusive creation in owned output storage and cannot overwrite input bytes or aliases.

Privately own/copy the caller's byte buffer before hashing and parsing. Source inspection shows current `inspect_bytes` passes caller bytes onward without an explicit initial duplicate; this audit did not execute a pinned-engine aliasing test. Add mutation of the original argument, not merely of a returned accessor copy, to the boundary tests before relying on its ownership semantics.

### 3.2 Content discovery

Capture once; apply a bounded discriminator without speculative decompression of every possible format. A filename is a user hint. Discovery must distinguish ZIP, the admitted PKG profile, supported installed directory, existing GLB/STL, and unsupported/ambiguous data. A reader receives only its frozen slice/handle and shared budget.

For ZIP, validate the outer index before provider discovery. A mixed ClearView/Phoenix ZIP can expose separate explicit candidates after its shared namespace passes; neither provider may claim the whole archive simply because the suffix is `.zip`. An ambiguous complete candidate is a review/refusal state. A standalone VAR, PHX, thumbnail, scenery or paint-only package does not become a complete aircraft.

### 3.3 Initial limits and what they measure

Numbers below are **proposed first-profile ceilings**, not measured product performance. Pin them in one reviewed policy object. Existing Creator limits in section 7 remain additional gates.

| Counter | Proposed profile | Meaning |
| --- | --- | --- |
| Aggregate original capture | 64 MiB per job | Whole selected ZIP/PKG, or the sum of captured directory member bytes; reject before exceeding actual bytes |
| Private staged disk | 512 MiB process-wide initial proposal | Reserve across active and abandoned jobs before writes; release only after private cleanup or transfer into separately charged accepted Store objects |
| Aggregate produced/copy work | 256 MiB per job | Output produced at every entered wrapper/decoding edge, including repeated decoding |
| One member | 32 MiB | Checked declared and actual payload; a model can have multiple bounded members |
| PKG body | 128 MiB | Additional bound for one decompressed observed PKG body |
| Archive/tree occurrences | 4,096 shared; observed PKG has its narrower 2,048 bound | Charge directories and unselected entries too |
| Virtual path | 512 raw bytes per complete path; maximum depth 16 for first runtime namespace | Explicit runtime policy, narrower than some research limits; never silently truncate |
| MOD/report/string/depth limits | See pinned parser profile and separate output budget | Must be reviewed for port, not inherited from the archive byte ceiling |

MiB means 1,048,576 bytes. Every nested parser borrows the same job accounting. Keep declared sizes, actual output work, persistent captured bytes, live buffers, decoder workspace, object counts and deadlines separate. One 256 MiB output budget is not a 256 MiB process-memory guarantee. Reserve/release live buffers; account for copies, dictionaries, strings, GPU upload and native image work. Measure exported-runtime peak RSS/VRAM separately.

The directory total is mandatory: thousands of individually legal 32 MiB files must not bypass the original-capture ceiling. Private disk reservations include original captures, decoded spools, converted outputs and uncommitted copies. Initially serialize admitted import workers through a process-wide coordinator; do not launch replacements while unreaped work consumes its reservations. Cancel/limit failure cleans only private incomplete staging and preserves accepted Store state. These are proposed resource policies requiring platform measurement, not existing runtime guarantees.

```text
accept_output(chunk, member, budget, ticket):
    ticket.check_active()
    check_deadline_and_work_quantum()
    checked_add(member.actual_bytes, chunk.size) <= member.limit
    checked_add(budget.produced_bytes, chunk.size) <= budget.produced_limit
    reserve_live_memory_if_this_chunk_will_be_retained(chunk.size)
    charge counters BEFORE append/copy/allocation
    append_to_private_bounded_destination(chunk)
```

Logical reuse of already captured immutable bytes does not require a second expansion charge. Actually decoding or copying them again does. Reserve against declared sizes before allocation but charge actual work separately; malicious declarations must not excuse excess output. Any compression-ratio rule needs an explicit zero-size denominator policy and cannot replace absolute caps. Cancellation checks must also occur in zero-output decoder progress loops. A deadline outside an unbounded native call does not bound that call.

**Bulk corpus bridge:** the [catalog's measured directory metadata](../../research/aircraft-creator/phoenix-corpus-archive-index-2026-11-17.json) reports Jets.zip at 141,530,350 bytes and AllPublic.zip at 1,260,906,736 bytes. They are oversized whole-input negative tests for this profile; those observations did not verify all payloads. Planes.zip (63,166,915 bytes) fits only the captured-input ceiling; its expansion and contents remain subject to every other gate. A lawfully prepared bounded member/folder fixture is a different input: retain parent archive identity, selected entry occurrence/hash, preparation method and resulting capture hashes. A future large-pack profile requires measured resource/cancellation evidence and owner review. Do not increase production limits merely to make a corpus pass.

## 4. Container structure and complete namespace

### 4.1 ZIP adapter

Coordinate extraction/versioning of existing ClearView archive primitives. Specify ZIP32 single-disk support, methods 0/8, allowed flags, data-descriptor forms, local/central agreement, nonoverlapping ranges and CRC behavior. Refuse unsupported ZIP64, encryption, multidisk, methods, links or special-entry types with a typed result. “PK” at offset zero is only a discriminator. The primary reference is [PKWARE APPNOTE 6.3.9](https://pkwaredownloads.blob.core.windows.net/pkware-general/Documentation/APPNOTE-6.3.9.TXT); the existing adapter defines the narrower application profile.

Validate metadata/ranges/names for all entries before selection. If payload decompression is lazy, report `INDEXED_PAYLOAD_UNCHECKED` for untouched files. Only bytes actually read, bounded and checksum-checked get a verified-member claim. Never claim every payload in a large indexed ZIP has been verified.

### 4.2 Observed PKG profile

This is the grammar implemented by the pinned research probe, **not a universal Phoenix specification**. All integer fields are little-endian and all arithmetic is checked. The header number remains an opaque numeric label.

```text
package:
    u8 marker == 0
    u16 header_byte_length; exact header bytes
        ASCII digits + "." + exactly six decimal digits in this profile
    u16 chunk_count in 1..2048
    repeat chunk_count:
        u32 compressed_size; u32 plain_size
        plain_size in 1..1_024_000
        exact compressed_size bytes, one bounded zlib stream
        output exactly plain_size bytes
    require outer input fully consumed

concatenated body:
    bytes 01 00 01 00
    directory_children()
    at most 512 trailing bytes, all zero

directory_children():
    u16 child_count
    repeat child_count under shared entry/depth budgets:
        u8 kind; u16 name_length; exact raw name bytes
        if kind == 1: directory_children()
        elif kind == 0:
            u16 author_source_length; exact author-source bytes
            u32 payload_size; exact payload bytes
            u16 child_count_after_file == 0
        else: refuse UNKNOWN_RECORD_KIND
```

The research profile additionally caps its own tree at depth 32, 2,048 entries, strings at 4,096 bytes, body at 128 MiB and members at 32 MiB. A runtime namespace may be stricter; report which gate refused the input. A short header `1.0` is outside this profile, not proven corrupt. A header label matching MOD revision does not identify simulator generation.

Each chunk requires a valid stream checksum, complete stream end, exact output length, no unconsumed/unused input and no concatenated second stream. Python reference checks use `decompressobj` with output bounds and explicit `eof`/`unused_data`/`unconsumed_tail`; consult the [versioned Python 3.12 API](https://docs.python.org/3.12/library/zlib.html) and [zlib manual](https://zlib.net/manual.html). Do not equate this API with Godot's stream behavior. Port tests must exercise the pinned engine's zlib wrapper, small-window behavior, empty progress and truncation. The application pin at this audit is `4.8.beta2.official.cafc17a19`.

The current research implementation retains chunks and then joins a body: its byte limits do not establish peak memory. For runtime, select a bounded spool or a genuinely bounded retained representation, record every copy, and do not join unbounded output in memory.

For a remaining trailer longer than 512 bytes, use `TRAILING_DATA_LIMIT` before assigning a zero-padding interpretation. For a within-bound nonzero byte, use `NONZERO_TRAILING_DATA` with its real span. Do not call unexamined bytes zero, infer a new version or silently discard them.

### 4.3 Full virtual tree before dependency lookup

The research JSON counts directories but omits their identities. It accepts path-like strings as inert evidence. Neither behavior qualifies a filesystem namespace. Build the complete raw tree directly from validated captured bytes, including empty directories and every occurrence.

```text
admit_namespace(raw_entries, path_policy):
    trie = empty virtual root
    for entry in source occurrence order:
        retain raw components, kind, occurrence_id and source span
        reject empty/dot/dot-dot components, NUL, separators inside a component,
               rooted/drive/UNC forms and unsupported encodings
        canonical = path_policy.decode_and_key(raw_components)
        # First profile can be strict ASCII. Any broader policy is separately versioned.
        reject case/normalization aliases that identify distinct source entries
        for ancestor in canonical.parents:
            require ancestor is DIRECTORY, or create an implicit directory
        node = lookup canonical
        reject a second FILE, FILE/DIRECTORY type conflict, or FILE used as ancestor
        allow an implicit directory to be confirmed by its one explicit directory record
        reject duplicate explicit directory records under this initial profile
        insert occurrence with its exact source identity
    return immutable trie + raw occurrence table
```

Check unselected entries too. `foo` as a file with `foo/bar`, or `foo` as a file with an empty `foo/` directory, must fail before a candidate is resolved. A lowercase full-path map alone does not express those type/ancestor rules.

Display decoding is separate from identity. The probe's UTF-8/Latin-1 fallback is not a source encoding standard. Do not strip directories, replace characters, normalize until two entries merge, or pick the first same-name reference. If a broader policy is needed, pin encoding, normalization/case-fold rules and version, byte and character ceilings, and platform aliases explicitly.

Keep source bytes as virtual data. Store outputs under generated content-addressed/owned names, never member path strings. If a later export recreates source paths, it needs a separate platform-specific path/link/reserved-name admission; virtual admission does not authorize arbitrary filesystem extraction.

## 5. Candidate closure and association proofs

Determine model roots using the admitted definition/root profile and observed dependency structure, not a basename-only search. Discovery classifies complete aircraft, definition-only variants, schemes, previews, sounds and sites separately. A variant missing its base cannot inherit an unrelated model from ambient files.

```text
resolve_candidate(index, selection, profiles):
    definition = exact selected occurrence, with checked captured bytes
    parsed = parse_definition(definition.bytes, profiles.mod)
    root = the evidenced owning root of that occurrence
    for reference in schema_pass(parsed).references:
        identity = interpret reference only using its established field/path semantics
        matches = lookup within the allowed captured root/dependency scope
        if matches.count > 1: fail AMBIGUOUS_DEPENDENCY
        if matches.count == 0:
            if required: fail MISSING_DEPENDENCY
            retain a typed optional omission
        else: read/check the unique member, recording raw occurrence and hash
    manifest = ordered exact closure, including selected scheme and base dependencies
    return candidate bound to manifest and policy/profile fingerprints
```

Do not infer a diffuse image from a nearby thumbnail or an alternate aircraft from identical PNG hashes. Byte deduplication preserves distinct logical candidates, source roots, schemes and configurations. Optional sound may be absent for static visual preview only if that stage's policy explicitly allows it. Missing geometry blocks visual conversion.

Use three independent joins:

1. **Container → member:** reparse/index the captured enclosing bytes, select the exact raw occurrence, decode/check its actual bytes and compare its digest. A standalone MOD hash plus an inventory assertion is insufficient.
2. **Selected closure → visual:** trusted conversion over the frozen closure, exact scheme/settings and verified converter implementation must reproduce the admitted output, or an independently reviewed equivalent proof must establish that relation. Two independent hashes do not establish derivation.
3. **Definition → physical output:** trusted compilation must reproduce the saved physical bytes using the verified package context; see section 10.

If an association cannot be re-established, withhold its dependent claims. A complete source container may be retained without validating every unused member payload; its receipt must say which members were checked. Reopening must use the selected saved closure, never silently substitute a newer local model with the same name.

## 6. MOD parsing, semantic observations and bounded diagnostics

### 6.1 Data grammar only

Use `openrc-phoenix-mod-observed-v1` as the starting research profile. Its parser consumes captured bytes and recognizes only observed assignments/tables/literals/comments and allowed symbols. It does not run Lua. Keep decimal lexemes, raw string bytes, ordering, exact spans and line boundaries. No `eval`, arbitrary expressions, includes, function calls, script engines or package-specified library loads.

Define the runtime grammar and all limits explicitly before porting. Preserve the narrow profile's refusal of unobserved escapes/exponents, mixed keyed/positional tables and bare-CR line endings; accept evidenced LF/CRLF and absent final newline. Exact duplicate keys fail. Case-distinct keys survive the syntax tree and require an ambiguity decision before mapping. Comments must not hide unsupported syntax. Use half-open byte spans; line and byte-column display must be derived consistently from the captured bytes, not Unicode character counts.

```text
parse_mod(bytes, policy, ticket):
    require byte bound
    lexer = bounded byte lexer with explicit token/depth/string/numeric limits
    root = parse only the admitted assignment root
    while parsing:
        retain ordered entries and raw lexemes/spans
        use structural occurrence identity, never display-name uniqueness
        check progress, cancellation and aggregate allocation budget
    require exact consumption except grammar-permitted whitespace/comments
    return immutable syntax tree

observe(tree, schema_profile):
    for occurrence in tree:
        classify by full owning structural context and value kind
        retain unknown fields and unresolved units as observations
        derive references only for evidenced field semantics
        diagnose unresolved/ambiguous mappings without overwriting source data
    return closed checked observation report
```

An ordered structural occurrence can be encoded by parent occurrence + child ordinal, bound to the exact MOD digest. Editing/replacing the MOD yields new identities. Repeated `AILERONS`/`FLAPS`/`RUDDER` names, empty visual lists and shared visual/collision names are not automatic duplicates. `Engine` has different kinds/meanings in different contexts; an engine-sound selector is not an engine performance map. `nodeCount` does not prove GEO topology.

### 6.2 Typed field interpretation

Maintain a reviewed registry keyed by schema context and source field, with: allowed value kind, source unit evidence, target unit, conversion formula, domain, evidence class, dependency requirements and unsupported reason. Separate visual coordinates, aerodynamic dimensions, collision geometry, angles, ratios, tuning factors and external-library names.

The possible `Size / 100` relation is a hypothesis requiring same-aircraft bounds/pivot/diameter/CG measurements. Never scale every numeric field together. Source inertia knobs, stall percentages, airfoil labels or mixing parameters do not become an OpenRC inertia tensor, polar or control law by name.

Retain unresolved information for review with bounded diagnostics. The affected mapping remains unavailable. Keep author-local source paths private/redacted in public reports; they never authorize dependency reads.

### 6.3 Report amplification fix required before a runtime port

A reproduced 8,421-byte MOD can cause the research inspector to build a 2,278,748-byte JSON representation before its default 1 MiB limit rejects it. The larger size was measured only after raising the limit in memory in an isolated probe. The default failure is a plain `ValueError` without a stable code or source offset. This is a research-tool finding, not a demonstrated product exploit.

Avoid multiplying a long full structural path into every diagnostic. Store bounded occurrence IDs and a shared path table. Charge syntax nodes, diagnostic objects, string bytes and serialized bytes before retention. Serialize incrementally into a bounded sink; charging after `JSON.stringify`/`json.dumps` has allocated the complete output is too late.

```text
append_diagnostic(code, occurrence, detail):
    bounded_detail = encode_with_fixed_field_limits(detail)
    required = checked_encoded_size(code, occurrence.id, bounded_detail)
    if diagnostics_count + 1 > limit or report_bytes + required > limit:
        stop stage with REPORT_LIMIT
            location = occurrence.span if meaningful else PHASE_UNAVAILABLE("report")
    reserve required; append diagnostic using occurrence ID

finish_report(report):
    emit through a byte-counted bounded serializer
    on any output limit:
        discard private partial success output
        return a small fixed-shape REPORT_LIMIT failure envelope
```

The failure envelope has its own small fixed ceiling and cannot recursively include the rejected report. Lexical/syntax errors require real byte locations. Whole-report, cancellation, storage or platform errors may use an explicit phase-level unavailable location; never invent offset zero to satisfy a test.

## 7. Geometry conversion and the unresolved GEO gate

### 7.1 Establish the source representation before implementing offsets

No full GEO grammar or independently proven decoder was established by this audit. Do not treat an unrelated project called “Phoenix Builder” as simulator documentation. Recognizable object names or plausible float sequences are investigation leads, not a record layout.

AC-PX-03 needs owned source/export pairs from a documented legitimate Builder workflow. Record exact Builder generation, export settings, editable source, expected vertices/corners/UVs/materials/hierarchy, hinge endpoints, raw exported bytes and hashes. Hold out an independent fixture; require a second author/workflow before generalizing. A screenshot can corroborate appearance, but cannot establish exact topology or source physics.

For each proposed GEO profile, document discriminants and every record's type, length, byte order, scalar encoding, index/reference scope, permitted optional data and exact end condition. Every unrecognized record stops the affected capability unless the qualified profile explicitly establishes that exact record as safely skippable; unknown cannot be assumed optional. Review the grammar against independently encoded malformed cases before using external assets.

```text
read_geo(captured_member, admitted_profile, budget, ticket):
    require profile has independently checked source/export fixtures
    require discriminator matches the exact tested profile
    cursor = bounded reader over immutable bytes
    for each record defined by that profile:
        validate type/length/count and checked ranges before allocation
        charge record/node/vertex/index/image/reference budgets
        decode only the profile's scalar representation
        retain raw reference bytes and structural occurrence identity
        reject nonfinite values, invalid indices, overlap, cycles and ambiguity
        ticket.check_active()
    require the profile's exact end condition
    return SourceGeometryIR(
        nodes, instances, meshes, per_corner_attributes,
        material_slots, image_references, transforms, source_occurrences)
```

The converter must have a single documented convention for matrices, vector orientation, parent/child multiplication and units. Source object identity binds the captured package/selection, member entry occurrence and hash, then the internal GEO structural occurrence. Identical bytes in two entries remain separate objects; deduplication is not identity. MOD-to-GEO matching needs proven source reference semantics. An ambiguous repeated name stops its binding; it does not authorize a guessed merge.

### 7.2 Normalization with explicit coordinate math

Let `B` be the established affine map from one source mesh instance's local coordinates to its emitted destination-local coordinates. This can differ per instance after hierarchy rebasing.

```text
for each mesh instance:
    require finite, invertible B and a proven unit/frame interpretation
    require independently proven source front-face winding convention
    normalize source winding to canonical CCW before the reflection step
    p_out = B * p_source
    n_out = normalize(transpose(inverse(B.linear)) * n_source)
    if determinant(B.linear) < 0:
        reverse each triangle's winding exactly once
    preserve per-corner material/UV/normal associations
    split output vertices at UV, normal or other admitted attribute seams
    duplicate a shared mesh when instances require different baked B transforms
    recompute a tested tangent frame from final geometry/UV/seam data,
        or apply a verified transform including handedness w changes
    reject nonfinite float32 output and invalid post-conversion bounds
```

This is mathematical conversion logic, not a claim about Phoenix handedness or front-face convention. The source-convention reversal and determinant reversal combine by exclusive-or; “reverse once” refers to the reflection step after source winding is established. Unknown winding blocks correspondence. If normals are absent, use only an explicitly qualified generation/smoothing policy and report its loss, or refuse that claim. Compare explicit source world poses to emitted world poses. A single global winding toggle cannot fix a hierarchy containing differently mirrored instances. A reflected or sheared transform cannot simply be emitted as an unsupported node; bake/rebase with verified identities and poses, or refuse the relevant stage.

Unchanged source tangents are not a default after a reflection, nonuniform transform or UV orientation change. Verify the whole tangent frame, including `w`, against final normals and UVs. If source normal-map conventions or the conversion are unknown, mark that material mapping unresolved rather than keeping visually plausible but unverified lighting.

Record three frames independently: evidenced Phoenix visual frame, emitted GLB frame and Creator aircraft placement frame. Existing `placement.gd` uses `p_structural = scale * rows * (p_source - datum)` in metres, with structural axes aft/right/up. Physics forward/right/down coordinates are a separate contract. Do not apply an exporter transform twice.

### 7.3 Emit the actual Creator subset

The relevant authority is the pinned application’s `glb_preflight.gd`, `source_importer.gd`, `png_check.gd` and `limits.gd`, not everything Godot can display. At this audit the supported route is rigid triangle geometry, a self-contained GLB buffer, embedded admitted PNGs and a supported scene graph. Skins, morph targets, animations, sparse accessors, negative node scales and mirrored/sheared node matrices are outside this route. Any nonempty `extensionsRequired` is refused, even for the two narrow material exceptions allowed through `extensionsUsed`.

Additional current limits include:

| Resource | Current Creator ceiling |
| --- | --- |
| GLB source / JSON | 32 MiB / 2 MiB |
| Triangles / expanded vertices | 200,000 / 600,000 |
| Nodes / hierarchy depth | 512 / 32 |
| Meshes / primitives | 128 / 256 |
| Materials / images | 32 / 16 |
| Accessors / buffer views | 2,048 / 2,048 |
| One PNG / largest side | 16 MiB / 4,096 pixels |
| Aggregate admitted image pixels | 16,777,216 |

These engineering ceilings do not establish target-device performance. The source importer also rejects a zero bounding-box extent on **any coordinate axis**. An XY triangle is a decoder fixture and should fail complete Creator admission; this is not a statement that all planar or oblique triangles fail.

Write buffers with checked offsets/lengths, required alignment, explicit scene choice and bounds recomputed from emitted finite float32 values. Select an index component width whose reserved maximum is never used: e.g. an actual index 255 needs at least unsigned-short rather than unsigned-byte. Preserve all corner associations when promoting/repacking.

Use the primary [glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html) and a pinned [Khronos glTF-Validator](https://github.com/KhronosGroup/glTF-Validator). Source inspection suggests the current Creator index check may only compare highest index with vertex count; the reserved-maximum case needs a targeted reproduction before labeling it a runtime bug. Do not make a new converter depend on that potential permissiveness.

Three proofs are required and cannot replace each other:

1. Independent GLB format validation on the exact emitted bytes.
2. Creator admission of those same bytes using the pinned application.
3. Source-to-output equivalence against known geometry/material/motion answers.

A valid GLB can contain the wrong aircraft; a visually similar rendering can contain invalid or incorrectly associated data.

### 7.4 Images, schemes and materials

Resolve definition/scheme → material → image references through the selected closure. A `#` image and its thumbnail have different roles. Inspect content signatures and bounded decoder output; a `.bmp` suffix does not prove standard BMP content.

PNG is the first output profile. Source BMP/JPEG/TGA needs a separately qualified bounded decoder/transcoder with dimensions, decoded bytes, aggregate pixels and native workspace limited before expensive allocation. Unknown image encodings remain unsupported members, not guessed payloads. DDS is not automatically supplied by the Creator path.

Establish UV/image orientation once; flipping both image rows and UV coordinates can cancel an intended correction. For glTF, the original 2×2 fixture in the verification guide uses upper-left UV origin. Test color-space interpretation, alpha modes, cutoff, filtering/wrapping and material slots independently. Phoenix specular/glow/tuning values do not automatically mean glTF metallic/roughness values. Record any evidenced approximation and its visual-only scope.

### 7.5 Separate OBJ recovery route

An author-provided OBJ is useful only after verifying the selected source/revision and its complete lawful OBJ/MTL/image closure. It does not reveal GEO framing, original hinges or the Phoenix flight model. A source link alone is not evidence of byte correspondence.

Use a bounded, explicitly supported directive profile; preserve object/group/material occurrence context. Handle position/UV/normal indices as complete corner tuples, including a documented negative-index rule if supported. A triangle-only first profile is safer to specify than untested fan triangulation of concave or nonplanar polygons. Missing material/UV/texture data has an explicit outcome. Resolve MTL/image paths only inside captured scope; never follow author-local absolute paths.

## 8. Hinge conversion and existing bindings

Existing Creator visual bindings select node indices, cardinal local axes and a limited set/count of conventional roles. An arbitrary source hinge therefore needs a verified wrapper frame or a separately approved binding-schema extension. Names such as `ELEVATOR` are not geometric evidence.

First establish that both endpoints share a known frame and unit. Preserve exact source decimals so different endpoints that collapse in float64 can be diagnosed. Reject exact zero or nonfinite separation; do not reject small nonzero hinges with an arbitrary epsilon in unknown units. Source endpoint order, travel sign and min/max meaning require independent observations.

For an orthogonal frame conversion `C`, compute the transformed rotation as `C R C^-1`. Under a reflection, merely transforming a directed axis while leaving the angle unchanged can reverse the motion. With an orthogonal determinant ±1, the equivalent directed-axis identity is `R(C a, det(C) * theta) = C R(a, theta) C^-1`. This does not establish source sign conventions or validate nonuniformly scaled motion.

### 8.1 Proposed rigid wrapper algorithm

All following transforms are in the same destination neutral scene frame.

```text
P = original parent global transform
G = moving subtree's original global transform
h0, h1 = proven converted hinge endpoints
d = h1 - h0
require finite representable d, with nonzero source separation
m = max(abs(d.x), abs(d.y), abs(d.z))
if m == 0: fail ZERO_OR_PRECISION_COLLAPSED_HINGE
a = (d / m) / length(d / m)  # avoid squared-norm underflow/overflow
R = proper orthonormal basis with selected cardinal column k equal to a
    # Choose the reference direction least parallel to a; verify conditioning.
H = affine(R, h0)
W = inverse(P) * H          # new wrapper local transform under old parent
L = inverse(H) * G          # old subtree local transform under wrapper

require W, L and resulting graph pass current GLB transform/graph rules
require selected wrapper is an admissible proper-subset part group
require no conflicting/overlapping part bindings
require mapped motion remains the same rigid source motion
assert neutral P * W * L equals G under declared storage tolerance
bind wrapper node index to cardinal k with independently verified sign
expected_world(theta) = H * R_k(mapped_theta) * inverse(H) * G
compare actual Creator vertices at neutral and BOTH travel limits
```

Nonuniform parent scale/shear can change rotation into a different world motion; rebase with proof or keep that role unsupported. Do not flatten the hierarchy and claim preserved articulation. Reuse and test the current `visual_builder.gd` node-map path; its code warns against relying on `GLTFState.get_scene_node` pointers in this pinned engine workflow.

The existing binding applies `sign * degrees[role]`, with no per-binding gain, offset, independent input or arbitrary transfer function. The preview uses a fixed 25-degree full throw; flight uses simulated surface angles. The wrapper aligns an axis only. Require the source motion to agree with that available role-angle mapping at representative intermediate inputs as well as neutral/endpoints; otherwise leave the role unsupported or obtain a separately owned binding/control extension. A matching fixed preview pose is not proof of source travel.

Known answer: `P=T(10,0,0)`, `G=T(12,0,0)`, `H=T(11,0,0)`, hinge +z. Then `W=L=T(1,0,0)`. A child-local point `(0,1,0)` is initially `(12,1,0)` and becomes `(10,1,0)` after +90 degrees. Unbound siblings retain their transforms.

Verify rendering and physical roles separately. Two meshes animated by one elevator do not establish two independent servo laws. A moving nozzle does not establish thrust-vector forces; a wheel or gear-door animation does not establish contact mechanics or retracting gear. Unsupported motion can preserve an explicitly static preview.

## 9. Provider schemas, field adoption and provenance

### 9.1 Versioned integration, not a string replacement

Current Definition v1–v4, typed ClearView observation arguments and source-installation validators cannot accept a Phoenix record just by changing its provider string. Specify a new definition/snapshot/provider-union version jointly with existing owners; leave previous schemas closed. `openrc_phoenix` is a proposed provider tag, not an existing accepted schema.

At each entry point, dispatch through a trusted closed registry:

```text
validate_source_context(definition, source_record, admitted_visual):
    parse each exact supported schema version
    require provider/selection/source identity agree across retained contexts
    if any known source context is missing, changed or incompatible:
        refuse dependent admission
    checked = registry[provider].validate_frozen_context(...)
    require checked associations and stage capability
    return a typed provider context, never raw untrusted dictionaries
```

Check both source metadata and retained definition/source records; deleting one marker must not remove an already known restriction. Also test conflicting provider markers. Conversely, a fully stripped independently supplied generic GLB cannot have its historical origin authenticated from geometry; do not claim impossible detection.

### 9.2 Explicit adoption transaction

Ordinary `set_raw`, `set_value` and `apply_values` currently reset origin information or retain only an estimated flag. Using them alone would silently relabel Phoenix source values as player-entered data. Add a versioned adoption/override transaction with one atomic value-and-lineage mutation.

```text
adopt_observation(document, request):
    require request.expected_revision == document.revision
    require request.source_fingerprint and report_id match current checked context
    observation = exact immutable observation occurrence
    mapping = trusted typed mapping for this context, field and profile
    require established source unit, finite conversion and target domain
    require explicit user choice for conflicts and material differences
    transaction:
        set target value and target unit
        record source observation ID, original value/unit/span and mapping profile
        record evidence class and user adoption event
        increment revision; invalidate relevant compilation/qualification
    return new revision

override_adopted_value(document, field, player_value):
    validate as normal editable input
    keep original source observation as ancestry
    append explicit override with new value/evidence
    do not overwrite the original captured observation
```

Existing aircraft quantities remain exactly `{value, unit, kind, source}`. The aircraft contract already admits `manual`, `measured`, `borrowed`, `estimated` and `derived`; current Creator definition evidence is narrower. Extend the **definition-side** schema intentionally and map to existing aircraft kinds:

| Evidence event | Proposed resulting aircraft evidence | Qualification |
| --- | --- | --- |
| Established source-authored value adopted with trace | `borrowed` with precise source | Source claim, not a physical measurement by OpenRC |
| Inferred conversion/default or uncertain dimensional estimate | `estimated` | Explicit assumptions and applicable domain |
| Player changes a value | `manual` with retained source ancestry in definition context | Does not become measured because it replaced a source value |
| Independently supplied measurement | `measured` with measurement evidence | Separate from parsing/adoption |
| Trusted compiler computation from inputs | `derived` with named dependencies/method | Must preserve input provenance |

Round-trip this lineage through edit, undo/redo where supported, draft, recovery, publication, reopen and resolver verification. Replacing the source clears or re-reviews associations; it must not silently rebind old spans to new bytes or discard unrelated user edits.

Inventory and vector adoption require particular care. Current inventory records have one evidence kind for an entire item's mass, size and position; `set_item_raw` can change a component without changing that kind. Current vector compilation also aggregates component origins. A borrowed mass plus manually placed position and estimated size cannot share one truthful item-wide source label. The new definition version must store property/component evidence, or defer adoption of those fields. Emit each scalar with its own evidence. For a vector, define a deterministic reviewed aggregate policy: a uniformly evidenced vector can retain that kind; a mixed vector can be `derived` by explicit component assembly with a source summary and references to its retained component lineage. This must not imply all components were measured or erase an estimated component. Test the resulting UI, definition and aircraft quantity together.

Read-only source observations, paint/scheme choice and report annotations must not change canonical physical output when the complete compiler-consumed input projection is identical. That projection includes the evidence kind/source the compiler emits into quantities: the same number adopted from source A versus B may legitimately produce different canonical bytes. Explicit physical adoption changes the relevant projection and invalidates its old qualification.

## 10. Definition-to-physical derivation and caches

The current `CompileBinding` v1 records definition/raw SHA-256 and a compiler-contract label. `CompiledPublication.valid_pair` deliberately validates structure, scope, UUID and law, **not derivation**. Reopen checks must not be described as a trusted recompile. This is an evidence gap for the proposed Phoenix guarantee, not a claim that the existing API promised a stronger guarantee.

### 10.1 Decisive counterexample

Create valid definition A and a physically different valid output B for the same UUID and compiler domain. Pair A with B, recalculate every blob/record/pointer checksum and the compile-binding fields. Structure and hash consistency may hold. The required new oracle is refusal because compiling A under the verified context does not produce B.

### 10.2 Proposed trusted recompile verifier

```text
verify_saved_derivation(record, retained_context, trusted_registry):
    admit closed schemas and exact saved source ref
    require current safety/admission policy permits the requested processing/use
        # Historical acceptance cannot bypass tightened limits or a disabled reader.
    hash actual immutable definition/raw/package bytes; verify record integrity
    verify provider context and selected source/visual associations
    profile = trusted_registry.lookup_exact(record.compiler_profile)
    if absent or execution environment unqualified:
        return DERIVATION_UNAVAILABLE, preserving historical bytes
    packages = load exact immutable package contents specified by this profile/record
    verify package hashes, package schema and applicable domain
    environment = verified implementation + engine/backend + serialization context
    if its expected fingerprint does not match:
        return DERIVATION_UNAVAILABLE
    compiled = profile.compile(
        admitted_definition, fixed_aircraft_uuid, verified_packages,
        disable_or_content_key_all_caches = true)
    require compiled passes existing schema/domain/law checks
    raw_again = compiled.exact_raw_bytes
        # Contract choice: the compiler serializes its physical Dictionary once
        # with the existing canonical writer, then returns those exact bytes.
    require raw_again == exact stored_raw_bytes
    return verified association for this process, record and environment
```

The trusted registry contains installed application implementations only. Never execute a compiler/script/library from the source package to reproduce its output. A serialized fingerprint is not proof until checked against the implementation actually used.

The current `Compiler.compile_candidate` returns an accepted-candidate owner inside a result envelope after encoding the physical dictionary. `CreatorBytes.encode` accepts a dictionary, not that owner. A historical compiler adapter must expose exact accepted raw bytes or an explicitly typed physical dictionary to encode once; never stringify/re-encode an owner object and call it recompilation.

Pin all inputs capable of changing physical output: exact package contents, compiler semantics/code, serialization rules, deterministic ordering, engine/backend context where relevant and fixed aircraft identity. Package IDs alone are insufficient: `packages.gd` caches package lookup by ID and static thrust by `id|initial_soc`; authoring compilation uses document revision. A package can change without its name or the document revision changing.

For the proof path, either bypass these caches or use verified immutable-content keys. Prevent an ID-only cache hit before verification. If byte-identical cross-platform recomputation is not qualified, report derivation unavailable on that platform/profile. Do not choose a new tolerance or round mismatches after the fact to accept B. Historical raw bytes remain immutable; explicit migration creates a new revision with new evidence.

Historical exact derivation and current admissibility are separate gates. Reapply current safety/admission policy before processing, reconversion, replay or use; a formerly accepted reader/profile/cache cannot bypass a tightened resource cap or disabled unsafe path. Preserve the old record and report unavailable when policy now refuses it. Migration must be explicit and produce a new revision, not silently reinterpret or delete history.

### 10.3 Stage-specific cache keys

Use the complete relevant context for each stage, not one oversized or incomplete “file name” cache key:

| Cache | Required identity components |
| --- | --- |
| Container index | Captured bytes, reader implementation/profile, namespace policy and budgets |
| Observations | Exact MOD/member/source context, parser/schema implementation and policy |
| Visual | Ordered selected closure, scheme, GEO/frame/material/converter implementation, target GLB policy |
| Physical | Complete canonical compiler-consumed definition projection, including emitted evidence kind/source and consumed lineage; UUID, verified package contents, compiler/serialization environment |
| Eligibility | Exact frozen physical/visual/source identity and all gate/backend/start/environment inputs relevant to that gate |

Use canonical framed encoding for key construction, not ambiguous string concatenation. A closed receipt or SHA alone does not certify success. Only complete admitted results can enter success caches; canceled, partial, stale and failed work cannot. Visual/report-only changes can alter review identity without altering physical bytes.

## 11. Retained sources, Store and transaction outcomes

### 11.1 Source retention is a schema project

The current Store source blob is normally an admitted GLB, at most 32 MiB. It is not a Phoenix PKG/ZIP/member closure. The Store quota is 4 GiB and append-only; archiving does not free accepted history. Calling a saved preview a “backup of the original Phoenix model” would be false under the current schema.

Propose a versioned closure manifest referencing immutable original container/member captures and derived GLB, with exact selection, checked-member claims and conversion receipts. Define whether a route retains the entire original archive or only a selected captured closure; name that guarantee explicitly. A selected closure cannot be presented as the original complete download.

If original enclosing ZIP/PKG bytes are absent, individual retained members and a declared archive hash do not re-establish container membership. Without a separately reviewed verifiable membership proof, that join becomes unavailable on reopen even when all member hashes match. Preserve provider restrictions and label the remaining captured-member/visual claims accurately.

Deduplicate immutable byte objects while retaining each logical source occurrence and selection. Charge all newly stored originals, derivatives, manifests and retained history to quota before publication. Define a closure-level ceiling distinct from the current one-blob limit. Preserve all objects reachable from accepted draft/recovery/revision indexes; current archival is not garbage collection.

The current Store caches previously verified object hash/size for deduplication; normal loads rehash bytes. That warm cache is not fresh proof if external mutation occurs while the Store is open. For a new closure association, recheck actual reused bytes at the join or qualify a stronger enforced immutability mechanism. The same-size replacement case is an inspection-derived test target, not an executed corruption/commit result in this audit.

Until the new schema and restore path exist, keep original source retention explicitly external/unavailable. A derivation check depending on absent original bytes must report unavailable; do not recreate an invented original from the converted GLB.

### 11.2 Exact saved revision and immutable history

Retain the current closed source-ref concept: `{format, aircraft_uuid, revision, record_sha256}`, with positive revision and verified exact record. “Latest” is not a substitute for a saved source ref. Reopening old revisions must not replace their compiler profile, source closure or package versions automatically.

Apply provider and derivation checks to `save_draft`, `save_recovery`, `load_draft`, legacy `publish_aircraft`, `publish_compiled_aircraft`, `load_aircraft` and source resolution as appropriate. A guarded UI button is not a complete guard if another Store entry point can accept the same forbidden association.

### 11.3 Cancellation and the actual commit point

The current Store stages immutable objects/index data and changes the accepted pointer by rename. A lost readback enters uncertain state and requires reopen. Preserve this distinction; “worker finished” and “commit requested” are not successful persistence.

```text
publish_async(captured_candidate, expected_store_generation, job_ticket):
    build and verify private candidate byte objects, not a final Store index
    check source/definition/visual/physical associations and captured context
    enter the single Store instance owner/actor for all reads, writes and teardown
    obtain/retain existing Store exclusive ownership and serialized writer access
    run _begin-equivalent verification of exact current pointer bytes and its index
    check operation CAS: expected revision for publication,
                         expected record SHA for draft/recovery, as applicable
    compute deduplication, quota, predecessor and next index from writer-owned state
    stage the immutable objects and next index using existing transaction rules
    within the shared cancellation/commit arbiter:
        if ticket canceled or source/document/UI generation stale:
            finish CANCELLED_OR_STALE without pointer transition
        require exact accepted pointer/index and operation CAS still valid
        require expected Store generation still current as an additional check
        claim COMMITTING for this operation  # not COMMITTED
        perform the existing accepted-pointer transition under writer ownership
    read back accepted state using existing Store verification
    if verified new pointer: finish COMMITTED with exact new source ref
    elif confirmed no transition: finish FAILED with previous accepted state
    else: finish UNCERTAIN; require reopen before further writes
    release writer ownership according to existing Store lifecycle
```

Current `Store.open` acquires the writable instance's process lock; `_begin` checks its held ownership, non-halted state, exact accepted `current.json` bytes and index. Reuse those rules: generation alone is not the existing CAS contract. Cancellation before the arbiter decision wins and keeps the prior pointer. After the commit decision wins, a cancel request receives “commit in progress” and eventually the actual committed/failed/uncertain outcome; it cannot promise cancellation. The UI must remain asynchronous; a shared synchronization rule is not permission to block the UI thread through I/O. Generation/CAS checks and pointer publication must not have an unprotected gap that allows stale A to publish after B.

The existing Store explicitly is not thread-safe. An asynchronous integration needs one serialized instance owner/actor covering reads, writes, recovery and close/teardown as well as the process lock; the UI cannot concurrently call methods on that same instance.

Unreferenced temporary objects may be cleaned under existing rules. Never delete accepted history or a shared object because one job was canceled. A verified application commit is not a new claim about sudden-power-loss durability; qualify filesystem durability separately if the product promises it.

## 12. Worker lifecycle, UI and flight gates

Use existing Creator generation/cancellation/abandoned-worker patterns. Capture selected source, candidate, scheme, document revision and relevant policy versions in a job ticket. Any change invalidates dependent work. Check the ticket before adoption, success-cache insertion, Store publication and trial construction, not only when displaying a preview.

```text
on_worker_result(ticket, result):
    if ticket does not match current owner/generation/selection/revision:
        discard result and its private resources; do not cache it as success
        return
    if result failed:
        show bounded stage diagnostic; preserve previous accepted document
        return
    adopt only the stage-specific immutable result under matching ticket
```

Native/engine calls that cannot cooperate with cancellation need measured worst-case bounds or an isolated process with controlled resource/lifetime policy. A timeout flag does not interrupt a blocking decoder. Reap abandoned work; do not allow a new import to accumulate unlimited workers, captures or image buffers.

Expose concrete outcomes: package inspected, missing geometry, unsupported GEO profile, static preview ready, motion unavailable, source value awaiting review, physical domain unsupported, trial gate failed, source missing on reopen, or commit uncertain. These are user decisions/states, not internal implementation details in the primary flow.

### 12.1 Real launch paths to audit

At the pinned main, draft launch goes from `aircraft_creator.gd` to `app_root.gd` freeze/start checking and then `main.gd` verification/build. The reference GDScript backend and visual attachment are separately selected there. Add Phoenix context checks to those real paths and the called authoring/trial APIs. `PublishedTrial.check_start` remains an unavailable helper; adding tests to that helper alone does not wire a saved-aircraft launch.

The current Creator compiler's supported domain is a conventional aft-tail, single-tractor electric aircraft with finite-battery/estimated packages and no authored landing gear or flaps. Broader capabilities elsewhere in the simulator do not automatically expand this compiler or its qualification.

For a Freewing SU-35 candidate, first identify actual source configuration and provenance. Twin EDF, retracts, mixing and possible vectoring need the corresponding propulsion/controls/gear owner plans and exact configuration tests. Do not substitute single-tractor thrust, a guessed trainer polar or merely animated nozzles and advertise imported flight fidelity.

Keep numerical stability, source agreement and measured physical calibration as separate claims. Existing load/schema success, trim or a short trial is not the full applicable Creator/physics campaign. AC-PX-07 and AC-PX-09 remain open until their owners provide exact candidate/backend/platform evidence.

## 13. Implementation order and decision gates

Use the [delivery sequence and acceptance matrix](verification.md#8-delivery-sequence) rather than starting with a general “import Phoenix” PR. Every stage records implemented profiles, unsupported cases and exact evidence. No implementation may silently broaden a profile to make a test pass.

The next concrete decisions are: platform capture mechanism; generic ZIP ownership and policy; complete raw namespace schema; incremental report budget/error contract; independent GEO fixtures/profile; provider-aware definition/adoption schema; content-bound recompile environment; closure retention/quota; and cancellation/commit integration. Each has a test oracle in the companion guide. Unresolved decisions stop their dependent feature, while bounded read-only inspection remains independently deliverable.
