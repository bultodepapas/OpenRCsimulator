# R11 package probe integration

The immutable `20261015-08` candidate exports Linux, Windows and macOS, passes the Linux compiled-flight trace and bundle/version checks, then fails the rotorcraft resource check. The original `--main-pack` probe reports 8 checks with no assertion failure, but Godot reports that the editor cannot find the Linux native extension beside itself. The export script correctly rejects those engine errors. [Original export outcome](../next-candidate/materialized-20261015-08/README.md).

The native library's location is separate from the empty project directory used to prevent loose application resources from masking a bad pack. A corrected probe must preserve packed-project initialization and provide the matching host library beside its editor. Cross-platform checks under that editor qualify packed resources, not execution on the target operating system. Native backend selection needs its own host-matched check.

## Rejected late-mount attempt

An initial proposal mounted each pack inside an otherwise empty project before dynamically loading the rotorcraft scripts, following the field-resource check's pattern. All three positive cases fail to resolve `HeliRotorBlur` during script compilation and reach the unchanged 60-second timeout. The missing-pack negative control returns 1 immediately. [Bounded results and source identities](package-mount-01/results.json).

That proposal is rejected. Its [rotorcraft script](rejected-late-mount-rotorcraft_package_smoke.gd) and [export script](rejected-late-mount-export.sh) are retained with the original [source identities](source-before.json). The original rotorcraft script was restored byte-for-byte, including all eight assertions and its existing `--main-pack` calling convention. The failed positive runs are not passing package checks.

The independent [native receipt repair](../native-package-staging/receipt-merge-20261015-02/README.md) also supplies the previously absent Windows platform row. Presence of a DLL alone does not establish that the simulator selected its native backend. Neither frozen candidate was edited to hide these failures.

## Reviewed replacement

The replacement keeps the original rotorcraft script and its `--main-pack` initialization. The export harness stages an independent copy of the pinned Linux editor and the exact exported Linux library beside it. Its project path remains empty. The field and rotorcraft resource checks still cover all three packs; those Linux-host checks do not establish Windows or macOS execution.

The additional host-matched [native package probe](../../../../../../app/tests/check_native_pack.gd) checks the simulator's selected backend, a separately instantiated native class, the packed platform receipt, the executable-adjacent library hash, and the float64 IEEE-754 ABI. The export preflight checks both Linux and Windows artifact hashes and their shared source/backend/solver identity while preserving the different toolchains. A missing platform row is a failure even if the operating system can load its library.

Root review caught two defects before package qualification. Godot parses JSON `abi_version: 1` as a floating-point `1.0`, so requiring `TYPE_INT` rejects a valid receipt. The [probe against the exact frozen merged receipt](../package-smoke/frozen-merged-receipt-type-01/probe.log) establishes that behavior. The corrected check accepts numeric 1 or 1.0 and rejects booleans, nonfinite values and other numbers. The actual receipt schema stores `source_sha256` in each platform row, not in its envelope; source equality must compare those rows rather than require an absent envelope field. These repairs concern the verification harness, not a change to the receipt schema or native solver.

The first draft's parser errors and the later numeric-type defect are retained separately. A subsequent [failed negative attempt](../package-smoke/linux-missing-windows-row-expected-negative-01/probe.log) exposed an invalid explicit `free()` on the native `RefCounted` instance. The final probe lets its scoped reference release normally. These engine errors are failures of the probe, not successful package rejections.

The [corrected negative control](../package-smoke/linux-missing-windows-row-expected-negative-02/probe.log) runs against the unchanged frozen-08 Linux pack, whose receipt contains only a Linux row. It loads the exact native library and reports matching class/selected-backend/float64 identities, then exits 1 with only the intended two-platform receipt error. It has no engine/script error or timeout. This proves the probe detects the incomplete package contract even when the host's native implementation itself is available. The source hash is `2249f62dfa8a4c8ffdabe78cab853a6247044be329d94c382c612e91f516d3ba`.

The [standalone artifact preflight](../package-smoke/export-preflight-01/README.md) accepts the merged receipt and exact libraries, and rejects all five deliberate mutations: missing Windows row, boolean ABI, divergent platform source, divergent optional envelope source and a changed DLL byte. Root independently verified that the tested Python file is byte-identical to the block embedded in the reviewed export script. The retained first harness attempt misclassified the correctly refused DLL because it expected a different diagnostic phrase; the corrected harness changes no preflight or artifact acceptance rule.

The frozen package candidate deliberately retains native-v2/RK4-v3. A separate [read-only preflight of the live native-v3/RK4-v5 artifacts](live-artifact-preflight-01.json) also passes with identical before/after input hashes. This verifies that the new export contract is not hardcoded to the historical solver version. It does not qualify the live working tree or execute its packages, and no historical native artifact was copied into the live application.

## Accepted package verification

The [physical -09 candidate](../native-package-staging/derived-package-20261015-09/README.md) contains exactly the three reviewed source overlays. Its [canonical export and target-host evidence](../next-candidate/materialized-20261015-09/README.md) establish:

| Check | Result and scope |
| --- | --- |
| `app/export.sh` | Exit 0; Linux, Windows and macOS ZIPs and `SHA256SUMS` produced. Linux compiled Stik trim, field/rotorcraft resources in all three packs, macOS bundle and build versions pass. |
| Host-matched native probes | Linux and Windows both select the matching native backend; class identity, receipt, actual library hash and float64 IEEE-754 ABI agree. |
| Windows release application | Direct Stik and Jet executions each produce 721 rows, ticks 0–720 over 3 seconds, and pass the existing trimmed-flight bounds. |
| Original Windows defect | The [unchanged -08 Windows pack](../next-candidate/materialized-20261015-09/windows-missing-row-control-08/run.json) has the exact DLL and a loaded native class but selects `gdscript_reference` because its receipt lacks the Windows row. The new probe rejects it with exit 1, without engine errors or timeout. |
| Independent root review | All three ZIP hashes/CRCs and the Linux/Windows executable/library bytes [match the exported artifacts](../next-candidate/materialized-20261015-09/root-package-review-01.json). Both Windows traces [match the frozen aircraft inputs](../next-candidate/materialized-20261015-09/root-windows-review-01.json), with complete ticks, aligned times and finite states. |

The [post-export source audit](../next-candidate/materialized-20261015-09/post-export-source-audit-01.json) finds no changed or missing file among the original 14,924 source entries. It separately classifies 454 added cache/export/support files and UID sidecars. The new probe's [engine-generated UID](native-probe-uid-integration-01.json) was copied unchanged into the live source pair, following the repository's GDScript metadata convention; the frozen manifests were not rewritten.

The export log retains 216 invalid-resource-UID warnings (72 distinct messages repeated across resource checks) that use text-path fallback. There are no engine error markers. macOS execution, target GPU/radio/pilot acceptance and the full application test suite are not qualified by these checks. The configured [CI workflow](../../../../../../.github/workflows/ci.yml) still builds/uploads the Linux native artifact without assembling both platform artifacts in its export job; the [native guide's pending dual-platform CI assembly](../../../../../../research/rc-monster-truck/native/README.md#installing-and-exporting) remains a separate release gate. This local package result does not close that gate or the six ordinary physics/performance integration failures in the [R11 report](../README.md).
