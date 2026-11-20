# Phoenix importer robustness: capture, definitions and lifecycle

Research date: 2026-11-17. This follow-up starts from research commit `7e316b7062c406da8e34e8c894ffe64038c68dc8`. The [AC-PX plan](../../plans/phoenix-aircraft-import.md) owns implementation status and product acceptance. The [original investigation](phoenix-2026-11-17.md) and [source inventory](phoenix-source-inventory-2026-11-17.json) retain the primary download URLs, exact package members and earlier evidence.

## 1. What this follow-up delivers

The package research checker now uses consistent captured inputs, confined local corpus reads on supported hosts, protected report creation and more truthful verification receipts. A new byte-based MOD parser preserves the six readable definitions without evaluating them. Its limited preflight catches specific conversion problems while retaining ambiguous or unfamiliar source structure for review.

The remaining product boundary is unchanged: no Phoenix GEO mesh has been reconstructed, no production Phoenix provider has been added to Creator, and no imported aircraft has passed a flight campaign. The code under [research/aircraft-creator/phoenix](../../../research/aircraft-creator/phoenix/README.md) is research tooling. Passing its grammar is not an aircraft compatibility claim.

| Delivered item | Evidence | What remains open |
| --- | --- | --- |
| Hardened PKG checker and bounded capture | [Container/capture receipt](phoenix-container-hardening-verification-2026-11-17.json): 31 framing checks, 26 capture/receipt checks, seven exact package inventory matches | Runtime port, Windows/macOS capture policy, asynchronous cancellation and complete resource qualification |
| Non-executing observed MOD grammar | [Definition receipt](phoenix-definition-verification-2026-11-17.json): 61 synthetic checks and six pinned readable MODs | Complete Phoenix syntax, version coverage and production observations schema |
| Limited context-aware preflight | Original synthetic zero/precision/shape cases; actual definitions retain repeated names, empty lists and raw byte names | GEO object/reference resolution, scale, coordinate frames, mirroring, articulation and physical semantics |
| Lifecycle acceptance refinements | Rechecked current-main source at `a7de9b35676d891bc2034cc344b910d9e1ef9c61`; cases PX-H-01…12 in the plan | Implemented and tested source closure, provider guards, cache/replay migration and Store integration |

The 118 generated-data checks above are named cases, not an assertion count or a universal safety proof. The seven PKGs and six MODs are overlapping specimens, not thirteen distinct supported aircraft. No third-party model bytes, simulator executables or installers are added to this branch.

## 2. Concrete research-tool failures corrected

These failures were reproduced with original bounded synthetic files, then addressed and reviewed independently. They concern the delivered research tools; do not describe them as already fixed in the application, which has no Phoenix route yet.

| Failure or misleading outcome | Correction and decisive check |
| --- | --- |
| Inventory A was used for comparison, but a second read could report the hash of replacement B. | Capture inventory bytes once; decode and hash the same buffer. A synthetic replacement after capture still produces A's identity and comparisons. |
| An inventory ID could be used as part of a relative path outside the selected sample directory. | Restrict IDs to a single short component. Open the selected directory once and read final children through its descriptor with no-follow behavior. Test separators, traversal, absolute/drive-like IDs and a sample symlink. |
| A FIFO could block before regular-file validation. | Nonblocking open followed by `fstat`, then a bounded read. Exercise both an input FIFO and a fixed repository tool-source FIFO in subprocesses with a timeout. This is tested on Linux; unavailable OS primitives are explicit. |
| A receipt could name new source bytes while Python used a timestamp-valid old `.pyc`. | Capture and compile only fixed trusted repository inspector sources; hash the same captured bytes. Test an equal-length, equal-timestamp source replacement with a stale compiled cache. Model bytes are never compiled. |
| `--report` could overwrite an input or an alias after successful checking. | Exclusive creation of new reports; refuse existing files, symlinks and hardlinks. The synthetic source bytes must remain unchanged. This protects existing files, not power-loss durability of a newly created report. |
| `python -O` could remove the assertions and even some operations that supposedly justified a passing receipt. | Both checker CLIs and synthetic entry points explicitly refuse optimized execution. Normal-mode tests verify that the optimized subprocess cannot emit a successful receipt. |
| Incomplete member metadata produced a traceback, nested path structures could amplify receipt output, or a JSON exponent could become infinity. | Validate consumed member shapes and bounded hex-component arrays; enforce a 2 MiB inventory limit, structural depth 64, finite numbers and duplicate-key refusal. Cap verification receipts at 2 MiB. Brackets inside JSON strings do not count as structural nesting. |
| A comment ending with bare CR could hide unsupported tokens from a lexer that only ended comments at LF. | This profile accepts LF/CRLF and rejects bare CR everywhere. Test both a comment boundary and a source-location case. No unsupported model code was executed in the reproduction. |
| A canonical symbolic name was reported as if it were the exact source lexeme, despite spaces/comments in the original. | Preserve the exact lexeme separately from the canonical allowed symbol and label their representations. Source spans still identify the original bytes. |
| Familiar field names in unrelated metadata could acquire geometric roles. | Apply geometry/pivot/axis blockers only in structural contexts observed in the corpus. Unknown contexts receive an unresolved observation and retain their original values. |

The inventory-depth policy is explicit rather than dependent on a Python interpreter's recursion threshold. The source-hash receipt is deliberately limited: captured inspector source identifies what the harness compiled in process; checker/harness hashes observe their files on disk, and subprocess checks use their on-disk tool files. This is not an atomic snapshot of the tool directory. Neither proves that local tools are authentic, that every imported dependency is trusted, or that a model author granted any particular rights.

The code keeps two distinct responsibilities. `inspect_pkg.py` reports untrusted package member names as data and has no extraction API. The checker uses its own restricted local specimen filenames to capture already-selected files. This does not establish a production package extraction policy or an atomic multi-file filesystem snapshot.

## 3. MOD profile and evidence that changes the design

The parser accepts one `modelTypes.<identifier>` table assignment, nested named tables or positional lists, exact quoted bytes, fixed-point decimal lexemes, line comments and the two observed `physics` symbols. It has explicit input/token/node/depth/string/number/diagnostic/output limits; the [tool guide](../../../research/aircraft-creator/phoenix/README.md#inspect-a-readable-definition) records them and the commands.

It does not implement general Lua. Unsupported escapes, expressions, additional assignments, exponent/hex numbers, mixed tables and unobserved line endings are refused with a byte offset and line/byte-column location. Numeric lexemes remain exact even though finite float64 representability is checked. Header output separates canonical symbols, quoted content and numeric lexemes from the exact original source span.

The in-memory representation retains all ordered entries and raw string bytes. JSON summaries expose selected observations rather than full aircraft definitions. Source hashes and offsets make the observations reviewable without redistributing models.

### Exact readable specimens

Member paths and original download provenance are in the unchanged source inventory. These SHA-256 values identify the locally inspected MOD bytes, not an author signature or a geometry/physics result.

| Specimen | MOD SHA-256 |
| --- | --- |
| Freewing SU-35 v23 | `b43e2a17418525873bad33ede75d4df108203514046e434e9b17bb884ba72681` |
| Extra 300SP v07 | `8a35d275c8e9ead987f7edd315d6b0fec19bd2c9f42cb6abed4d6a373c18bdb1` |
| Queen Wasp v18 | `70027729d1c2609717790e27ab3ed1c829778233cc157bd523dadc89282874ae` |
| Queen Wasp Amphib v20 | `214f8def8b758854b693a94af47e6dd8b48c761bc006c2151b7e0be9f85a8863` |
| Su-37 Terminator | `132d083b92f6877fa0849a51b374c1cd19a5c13042e4a924f90c049c5efe5764` |
| Agusta AW109 | `ec9354bc93fde0627c5a039175eae715ee9fb2db5bef26e40046c6a6c0b7ca8e` |

### Observed cases and required handling

Line numbers below are one-based in the exact MOD member. These are actual corpus observations, distinct from the synthetic malformed inputs used to exercise refusals.

| Observation | Importer consequence |
| --- | --- |
| All six use CRLF without a final newline. The Su-37 contains eight string occurrences with non-ASCII bytes; geometry references at lines 707–708, 734 and 774 include byte `E9`. | A UTF-8-only parser rejects a real specimen. Preserve bytes and source spans; selected UTF-8/Latin-1 display decoding must not become object identity or a universal encoding claim. |
| Wasp v18 uses `Root_chord`/`Tip_chord` at 256–257 and `Root_Chord`/`Tip_Chord` at 291–292 in another context. | Do not globally lowercase fields. The six-file scan found no exact duplicate keys or same-table case variants; those are synthetic boundary cases, not observed corruption. |
| Wasp v18 repeats `AILERONS` and `FLAPS` for separate controls; the SU-35 repeats `RUDDER` at 437 and 525. | Names and roles are not global unique IDs. Retain structural path, parent, order and every occurrence. |
| AW109 uses the same fuselage object for visual geometry and mesh collision at 162 and 169. | Preserve both references and their roles. A repeated reference alone is not a conflict or proof that two source objects should merge. |
| SU-35 stabilizers have empty geometry lists at 315–318 and 330–333 but collision data and separately declared elevator geometry. Wasp Amphib has wheel side lists empty at 805–820. | Empty visual lists need contextual treatment. Do not delete the enclosing mechanism, assume it is absent or reject every empty list. |
| Su-37 puts both elevator references in its first side while the second is empty at 394–404, although the parent is marked mirrored. Its left-rudder airfoil contains both rudder controls; the separate right-rudder airfoil has an empty control list. | Preserve the declared topology. Do not impose one reference per side, automatically mirror it or reparent controls without proven semantics. This observation does not validate or invalidate the authored behavior. |
| SU-35 pivots at 248–249 vary along all three axes. AW109 gear pivots at 652–653 are only about 0.06425 source-coordinate units apart. Su-37's wheel axis at 726 contains 1.000001 and signed zero. | Preserve oblique axes and small nonzero differences. Do not impose a broad arbitrary epsilon or exact unit-norm condition. Frames, units and appropriate physical tolerances remain unresolved. |
| Extra's `Engine` is numeric at 51 and a string at 702; AW109 nests an `Engine` string inside an `Engine` table at 406–408. | Interpret by full context and value kind. A global dictionary keyed by field spelling would conflate tuning, structure and labels. |
| Extra places size/weight/CG fields at 35–38 and position/length at 197–200 without establishing their unit/frame conversion. Airfoil, texture and engine names occur separately. | Retain raw quantities and unresolved dependencies. No common multiplier, polar, engine curve or calibrated inertia follows from parsing them. |
| The Extra blur-texture basename matches a package inventory member; several scheme BMP names have identical content hashes. Wasp Amphib uses the literal `Bouyant`. | A single basename match is not a complete resolution policy. Byte deduplication must preserve logical names and scheme aliases; preserve source spellings until a mapping is evidenced. |

No coincident pivot pair or zero explicit axis was found in the inspected vector roles of these six models. Those are generated robustness cases. The preflight checks exact decimal coincidence and direct float64 collapse without inventing a direction or silently changing the source. It does not claim that every nonzero pair is a valid mechanism.

The observed context allowlists cover geometry fields in body and airfoil/gear/widget sides; hinge endpoints in airfoil controls/flaps and gear/widgets; and axes in gear wheels. They are deliberately incomplete. Other references, including positional control-side lists and rotor forms, remain preserved in the tree without a claim of complete dependency enumeration. `nodeCount` and parser-node counts are unrelated measurements; neither establishes decoded GEO topology.

## 4. Current-main review and lifecycle acceptance

The earlier source audit at `3c91936ab8f9064daa798311b5fb3e89e28d3754` was rechecked against [`a7de9b35676d891bc2034cc344b910d9e1ef9c61`](https://github.com/bultodepapas/OpenRCsimulator/tree/a7de9b35676d891bc2034cc344b910d9e1ef9c61). The two intervening commits did not change the relevant Creator/Workshop, aircraft physics or plan files. This is a pinned source review; this research branch does not claim to include the current-main runtime, and no application tests were run for these research changes.

The following are future acceptance cases. The authoritative plan maps them to PX-H-01…12 and the existing owners.

### Capture and associations

Replace, truncate, grow or remove a source during capture, including a same-size replacement. Hash and subsequently consume the actual captured bytes; do not silently reopen a mutable path. A collection of hashes and before/after timestamps does not prove an instantaneous directory snapshot. The existing [single-file importer](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/workshop/creator/source_importer.gd) and [archive capture](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/workshop/creator/clearview/archive.gd) do not supply that multi-file contract.

Pair package A with valid definition, geometry, observations or visual B and recompute individual digests. The trusted import/reopen path must establish member membership, selected candidate and scheme, and the source-to-output relation from the captured closure under the pinned implementation, or state that the relation is unverified. This is separate from the plan's existing definition-to-physical recompilation requirement. [Compile-binding receipts](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/workshop/creator/compile_binding.gd) explicitly do not authenticate a compiler or association.

Remove mandatory geometry while placing an identically named object under another aircraft; the affected stage must stop. A missing optional sound may permit a labeled partial preview. Neither case permits an arbitrary filesystem or network search. A user-supplied replacement becomes a separately captured dependency with its own identity and renewed affected evidence.

### Provider guards and stale work

Within a known Phoenix draft/revision, remove the visual marker or saved receipt independently and introduce conflicting provider versions. Preserve a diagnosable draft where safe, while trial/verification/publication/resolution guards retain the provider's actual restriction. The existing [installation guard](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/workshop/creator/source_installation.gd) recognizes ClearView, so adding a Phoenix label does not create this behavior. A completely stripped GLB reimported independently cannot reliably be identified as Phoenix-derived; metadata and hashes are not origin authentication.

Delay work A, then cancel, close the wizard or select/edit B before A completes. A must not replace B, touch a destroyed scene, fill a success cache or publish. The [resolver](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/workshop/creator/source_resolver.gd) specifically notes that inspection has no cancellation parameter and callers must reject stale generations. Recheck generation and relevant inputs at adoption and commit. Distinguish cancellation before commit from a commit that already succeeded; preserve the Store's uncertain outcome when readback cannot confirm it.

### Caches, history and physics isolation

Change bytes under the same filename, candidate or scheme inside a package, user overrides, policy limits, converter implementation or compiler/package contents. Cache keys and replay must cover the actual relevant inputs. The existing [package cache](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/workshop/creator/packages.gd) uses logical IDs, and the [compiler summary](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/workshop/creator/compiler.gd) records package IDs; a future exact historical replay cannot assume those labels pin their bytes. Partial/cancelled work must never become cached success. Tightened current admission still applies, and unavailable old behavior must become an explicit unavailable/unqualified state. Migration creates a new revision.

Save revision 1, publish revision 2, restart and resolve the recorded revision 1 with its exact dependencies. [SourceRef](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/workshop/creator/source_ref.gd) rejects revision zero/latest. Exercise quota failure and interrupted transactions, shared source closures, archives, recovery drafts and old revisions. [Store](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/workshop/creator/store.gd) keeps accepted history append-only and promises interrupted-process recovery, not power-loss durability. Temporary cleanup cannot silently become accepted-object garbage collection. A retention change needs its owner's contract revision. Portable output must retain the complete permitted closure or explain/refuse the affected portability claim; omitted originals must not be fabricated on reimport.

Hold the physical definition, UUID, compiler and package inputs fixed while changing valid appearance, scheme, motion presentation or observation annotations. Canonical physical bytes and loaded physical inputs must remain unchanged. The compiler already removes review metadata from its physical inputs. An explicitly adopted physical field requires visible provenance, recompilation and renewed applicable gates. A source/report change may still invalidate source-dependent qualification even when canonical physics is unchanged.

## 5. Reproduction, review and next gate

Use the [tool guide](../../../research/aircraft-creator/phoenix/README.md) to run both synthetic suites or the exact external-file comparisons. The lead produced both final receipts after integration. Independent review included successful package and definition runs and found no remaining blocking issue within the reviewed research scope; the final package receipt was produced by the lead after a receipt-wording refinement. The receipts record source hashes, environment and individual outcomes; they are not a fuzzing campaign or a proof of safety.

The original [31-check receipt](phoenix-probe-verification-2026-11-17.json) remains unchanged evidence of commit `7e316b7062c406da8e34e8c894ffe64038c68dc8`. The new [container/capture receipt](phoenix-container-hardening-verification-2026-11-17.json) matches the same seven package inventories. The [definition receipt](phoenix-definition-verification-2026-11-17.json) independently checks six pinned MOD byte identities and their observed grammar. Its package paths/hashes are expressly inventory-reported claims: that command does not reread its PKGs. Run the separate package checker for the package comparison, and do not present either receipt as an authenticated provenance chain.

The next critical implementation gate is still GEO decoding against owned known-answer exports: topology, winding, UVs, material binding, nonidentity transforms, object identity and one arbitrary hinge. In parallel, the research grammar can inform the production provider and source-closure contract, with the exact diagnostics and rejection cases carried over. A renderable GLB must pass Creator admission; complete controls and flight remain separately qualified stages. Do not broaden compatibility counts from readable headers, successful container inspection or community page counts.
