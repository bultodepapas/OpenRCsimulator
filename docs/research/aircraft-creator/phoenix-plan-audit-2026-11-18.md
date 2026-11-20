# Phoenix plan audit — 2026-11-18

## 1. Outcome and scope

The Phoenix plan is a viable staged investigation, but it was not detailed enough to serve as an implementation contract at the source, geometry, authoring and persistence boundaries. This audit adds an [implementation guide](../../plans/phoenix-aircraft-import/implementation.md) with proposed records, algorithms and integration seams, and a [verification guide](../../plans/phoenix-aircraft-import/verification.md) with **65 proposed acceptance cases** and eight review slices. The [parent plan](../../plans/phoenix-aircraft-import.md) remains the sole owner of AC-PX-00…09 status.

This is a **documentation-only change**. It does not implement or fix a production importer, alter the research parsers, decode GEO, qualify an aircraft or enable flight. The reported research-tool behavior remains present at the pinned source; the guide now specifies how a future port must handle it.

Audited baselines:

| Baseline | Exact commit / scope |
| --- | --- |
| Research branch | [`3619c19362064a0a51b6fda360adce0bfeb38b3d`](https://github.com/bultodepapas/OpenRCsimulator/tree/3619c19362064a0a51b6fda360adce0bfeb38b3d), `plan/flight-simulator-aircraft-import-2026-11-16`; plans, corpus, PKG and MOD probes |
| Current main snapshot | [`39fa2746ae4f4ba8698b87db279adcfe84ef5d17`](https://github.com/bultodepapas/OpenRCsimulator/tree/39fa2746ae4f4ba8698b87db279adcfe84ef5d17); Creator, UI, Store/resolver, compiler and actual launch route |
| Engine identified in source | `4.8.beta2.official.cafc17a19` via `app/get-godot.sh`; identified, not executed in this audit |
| Executed research environment | Python 3.12.14, zlib runtime 1.3.2 |

Three independent read-only reviews covered package/MOD boundaries, geometry/motion and current-main runtime contracts. The lead independently reran the existing synthetic suites and the five new original boundary fixtures, integrated corrections and checked the documentation. Review does not substitute for future runtime qualification.

## 2. Evidence actually executed

The [machine-readable receipt](phoenix-plan-audit-verification-2026-11-18.json) includes the two full synthetic-suite receipts and the separate boundary receipt, with exact source hashes and input hashes.

| Check | Observed result | Scope |
| --- | --- | --- |
| Existing `check_probe.py` | 31 synthetic container checks and 26 capture/receipt checks; exit 0 | Research framing/tree/capture behavior only |
| Existing `check_definitions.py` | 61 synthetic definition checks; exit 0 | Observed MOD grammar and limited preflight |
| Report amplification fixture | 8,421-byte input hits default 1 MiB report refusal; no typed code/location | Reproduced research behavior |
| Report-size measurement | 512 diagnostics and 2,278,748 encoded report bytes after a temporary in-memory increase to 8 MiB | Isolated measurement, not default successful output; constant restored |
| Empty-directory/file collision | Directory `foo` plus file `foo` accepted as inert input; JSON contains count 1 and only the file path | Demonstrates incomplete tree representation, not path extraction |
| Duplicate file and empty name | Both accepted by the research probe as inert data | Product namespace must be independently admitted |
| Long nonzero trailer | 513 `X` bytes produce `zero padding limit exceeded` | Diagnostic classifies length before content |

Totals are **118 existing synthetic checks plus five additional fixture cases**, not 123 application tests. No original simulator was run, no third-party model code was executed, no real model corpus was rerun after restoring this checkout, and no Godot/validator/exported build or flight campaign was executed.

The five fixture hashes are in the receipt. A baseline pass is compatible with these findings: research code intentionally permits path-like strings in a read-only report, and its existing suite does not promise production path admission.

Source identity scopes differ: the existing harness receipts identify their captured executed parser source separately from checker files observed on disk. The five-fixture script uses ordinary imports and then hashes the parser files on disk; those hashes are post-import observations, not a universal proof of executed module bytes. It ran from fresh isolated trusted copies without an existing bytecode cache. `PYTHONDONTWRITEBYTECODE=1` prevents writing bytecode, not reading a pre-existing cache. Keep this distinction when comparing receipts or repeating the experiment.

## 3. Findings and required plan corrections

Priority below means consequence for the proposed importer: **Gate** blocks an advertised capability; **High** risks incorrect association/state/provenance if copied into a runtime design; **Medium** needs a concrete workflow or diagnostic correction. These are engineering planning priorities, not assigned vulnerability severities. “Inspection” and “hypothesis” are not executed failure claims.

| ID / priority | Finding and evidence | Required correction / status |
| --- | --- | --- |
| PX-A01 / Gate | Full GEO grammar and source correspondence remain unproven; successful PKG inflation does not establish geometry. | Owned source/export fixtures, documented narrow record profile, independent topology/frame/material/motion oracles. Implementation Section 7; open feasibility gate. |
| PX-A02 / High | Research PKG JSON drops directory identities and accepts empty/duplicate/path-like names as data. File/directory, file-ancestor and empty-directory conflicts cannot be established from that JSON. **Reproduced.** | Build complete raw occurrence tree before namespace admission; reject conflicts even in unselected entries. Section 4.3; runtime work open. |
| PX-A03 / Medium | MOD report limit is checked after full JSON construction; 8,421 input bytes yield a measured 2,278,748-byte representation and plain `ValueError`. **Reproduced.** | Incremental allocation/diagnostic/output budget, occurrence IDs instead of repeated long paths, typed `REPORT_LIMIT` and real or explicitly unavailable location. Section 6.3; prototype behavior not changed. |
| PX-A04 / Medium | A 513-byte nonzero trailer is called “zero padding limit exceeded.” **Reproduced.** | Neutral over-limit diagnostic; only classify zeros/nonzero contents after inspection. Section 4.2; do not infer corruption or version. |
| PX-A05 / Medium | Proposed 64 MiB archive limit conflicts with whole Jets/AllPublic corpus use; directory capture also needs its own aggregate enforcement. **Plan/catalog inspection.** | Whole large archives become limit-negative cases; bounded prepared fixtures have distinct lineage; directory bytes share a mandatory capture total. Section 3.3. |
| PX-A06 / High | Current bounded `FileAccess` reads do not establish cross-platform no-follow/nonblocking special-file capture or a coherent multi-file instant. **Inspection.** | Choose/qualify a platform capture mechanism, exact byte guarantee, process-wide staging/worker policy and mutation tests. Section 3.1–3.3; platform decision open. |
| PX-A07 / High | Existing UI routes every ZIP to ClearView; `Authoring` observation parameters, Definition versions and `SourceInstallation` are ClearView-specific. **Inspection.** | Shared content discovery, closed next provider-aware schemas and typed adapters; preserve old validators. Section 1/3/9. |
| PX-A08 / High | Ordinary authoring setters erase origin information; inventory uses one kind across mass/size/position and vector origins are aggregated. **Inspection.** | Atomic value+lineage adoption; property/component evidence or explicit deferral; honest borrowed/manual/estimated/derived mapping. Section 9.2. |
| PX-A09 / High | Compile binding v1 verifies hashes/profile label; `valid_pair` explicitly checks structure/domain/UUID/law, not definition-to-raw derivation. Existing mixed-pair fixture retains A's old binding. **Inspection.** | Recomputed-hash A/B counterexample and trusted exact recompile against verified package/implementation context. Section 10; no claim existing code promised authentication. |
| PX-A10 / High | Package ID, ID/SOC and document revision caches omit content that a stronger proof must bind. Consumed provenance can change raw bytes even with identical numeric values. **Inspection.** | Exact compiler projection including emitted evidence, immutable package contents and implementation/environment identity; bypass or content-key proof caches. Section 10. |
| PX-A11 / High | Current one-source-blob Store does not retain a Phoenix original closure; 4 GiB quota is append-only and archive frees no history. **Inspection.** | Versioned closure/retention guarantee and complete quota accounting; distinguish original enclosure from selected members and derived visual. Section 11.1. |
| PX-A12 / High | Generation-only commit checks would omit exact pointer/index, draft-record/revision CAS and Store ownership; Store is not thread-safe. Cancellation and uncertain readback need separate outcomes. **Inspection/design review.** | Single instance owner/actor, current writer rules, final shared arbiter and exact commit/readback outcome. Section 11.2–11.3. |
| PX-A13 / High | Current Creator GLB subset is narrower than generic glTF/Godot; an XY triangle fails zero-z-extent admission; every nonempty required-extension list is refused. **Inspection.** | Separate decoder-only and complete tetrahedron fixtures; exact target subset plus independent validator and source oracle. Section 7.3. |
| PX-A14 / High | Reflections, source winding, normals/tangents and arbitrary hinge frames need explicit math. Current binding offers sign × role angle, not arbitrary gain/mixing. **Mathematical review plus code inspection.** | Source convention evidence, per-instance normalization, safe axis normalization, pivot wrapper and intermediate/end-pose/transfer-function checks. Section 7.2/8. |
| PX-A15 / High | Actual draft launch is Creator → root → Main; PublishedTrial start remains unavailable. Compiler domain is conventional single-tractor electric and gearless, narrower than broader simulator features. **Inspection.** | Guard real routes, retain helper unavailability, keep SU-35 twin-EDF/retract/vectoring capability work with physical owners. Section 12. |
| PX-A16 / Medium | Current GLB highest-index comparison may miss the format's reserved maximum value when still below vertex count. **Inspection-derived hypothesis; not reproduced.** | Independent-validator fixture: 256 vertices and u8 index 255 must promote or refuse. Verification PX-G09; runtime result pending. |
| PX-A17 / High | Caller buffer passed to `inspect_bytes` is not explicitly duplicated before hashing/parsing; existing tests mutate returned copy or disk input, not original argument. **Inspection-derived ownership question; not reproduced.** | Privately own bytes and test original-buffer mutation at consuming boundaries. Verification PX-R01; do not assert engine alias behavior without test. |
| PX-A18 / High | Warm Store dedup cache trusts earlier hash/size; normal load rehashes. External same-size replacement needs a new-association oracle. **Inspection-derived hypothesis; not reproduced.** | Fresh verification of reused objects or qualified enforced immutability at the join. Verification PX-R17; no executed corruption claim. |

The guide also closes two pseudocode-level gaps found in review: optional references with multiple matches must fail ambiguity before omission logic; and “sealed” dictionaries/handles must be protected or reverified, not treated as immutable because a flag says so. These were corrected in the plan before publication.

### 3.1 Source anchors for reviewers

These links pin the inspected implementation, avoiding confusion with the older runtime files on the research branch:

| Concern | Pinned source |
| --- | --- |
| Research PKG and MOD behaviors | [inspect_pkg.py](https://github.com/bultodepapas/OpenRCsimulator/blob/3619c19362064a0a51b6fda360adce0bfeb38b3d/research/aircraft-creator/phoenix/inspect_pkg.py), [inspect_definition.py](https://github.com/bultodepapas/OpenRCsimulator/blob/3619c19362064a0a51b6fda360adce0bfeb38b3d/research/aircraft-creator/phoenix/inspect_definition.py), [check_definitions.py](https://github.com/bultodepapas/OpenRCsimulator/blob/3619c19362064a0a51b6fda360adce0bfeb38b3d/research/aircraft-creator/phoenix/check_definitions.py) |
| UI dispatch and live draft request | [aircraft_creator.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/ui/aircraft_creator.gd) |
| Authoring provenance and source types | [authoring.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/authoring.gd), [definition.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/definition.gd), [source_installation.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/source_installation.gd) |
| Compile association and caches | [compile_binding.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/compile_binding.gd), [compiled_publication.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/compiled_publication.gd), [compiler.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/compiler.gd), [packages.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/packages.gd) |
| Persistence and exact source ref | [store.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/store.gd), [source_resolver.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/source_resolver.gd) |
| Geometry, placement and rig | [glb_preflight.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/glb_preflight.gd), [placement.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/placement.gd), [visual_builder.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/visual_builder.gd) |
| Captured-source ownership | [source_importer.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/source_importer.gd), [inspected_source.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/inspected_source.gd) |
| Actual root/Main launch and unavailable saved helper | [app_root.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/app_root.gd), [main.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/main.gd), [published_trial.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/published_trial.gd) |

## 4. Primary internet references checked

The web research checked format/API references, not an undocumented universal GEO decoder. It supplements the project source audit:

| Primary reference | Use and limit |
| --- | --- |
| [PKWARE APPNOTE 6.3.9](https://pkwaredownloads.blob.core.windows.net/pkware-general/Documentation/APPNOTE-6.3.9.TXT) | ZIP structural/checksum concepts; the application chooses a narrower supported profile. PKG is a separate format. |
| [Python 3.12 zlib API](https://docs.python.org/3.12/library/zlib.html) and [zlib manual](https://zlib.net/manual.html) | Bounded stream output and explicit end/unused-input semantics; current manual versions do not identify the local runtime, which was 1.3.2. |
| [Khronos glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html) | Output format rules, including reserved index maxima; successful generic validation is distinct from Creator's admitted subset. The full HTML fetch timed out, and relevant official indexed specification text was checked. |
| [Khronos glTF-Validator](https://github.com/KhronosGroup/glTF-Validator) | Independent validation tool to pin for the future geometry campaign; not executed here. |

The [existing Phoenix evidence](phoenix-2026-11-17.md), [hardening follow-up](phoenix-hardening-2026-11-17.md) and [corpus catalog](phoenix-corpus-catalog-2026-11-17.md) remain the home of aircraft/forum/author links and historical specimen results. This audit does not imply those assets were freshly downloaded or revalidated.

## 5. Work still required

Implement and qualify the contracts through existing owners. The 65 acceptance rows specify concrete inputs/actions/oracles, and the eight delivery slices make each change reviewable without claiming the entire importer works. The immediate independent tracks are bounded container/definition inspection and owned GEO feasibility fixtures. Phoenix visual, retained-original and flight claims remain gated separately.

No legal permission or release clearance is newly established here. Preserve the earlier rights ledger and use original or expressly licensed distributable fixtures. No messages were sent to authors, and no third-party model assets were added to the repository by this audit.

## 6. Reproduce the five new boundary cases

Use a **new disposable directory** outside the repository. Copy the exact pinned `inspect_pkg.py` and `inspect_definition.py` into its `research/aircraft-creator/phoenix/` subdirectory. Save the following Python block as `reproduce.py` at that disposable root. The script checks those file hashes before its fixture assertions, writes only its own small generated inputs, and exclusively creates an optional report. Use `PYTHONDONTWRITEBYTECODE=1` and no `-O`.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 reproduce.py \
  --report /absolute/new/private/boundary-receipt.json
```

The copy below is the exact script executed for the recorded lead reproduction. Its SHA-256 is `b2605ff3ac02aecf558100d0c2fb6965d8f57e4ad68fcda88934b82567ba1e1e`. It raises a disposable module's report cap only inside a `try/finally` measurement and restores it; it does not edit any source file. A later Python/zlib version may encode compressed fixture bytes differently, so compare recorded environment and generated hashes rather than assuming byte identity across toolchains.

```python
#!/usr/bin/env python3
"""Owned synthetic cases for the pinned Phoenix research tools only.

Run with PYTHONDONTWRITEBYTECODE=1. No model, archive member, or third-party
asset is executed. The generated inputs and optional receipt stay beside this
script. Report sizes above the prototype cap are measured only after temporarily
raising its *in-memory research constant*, and are not production behavior.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import struct
import sys
import zlib

BASE = Path(__file__).resolve().parent
TOOLS = BASE / 'research' / 'aircraft-creator' / 'phoenix'
sys.path.insert(0, str(TOOLS))
import inspect_pkg as pkg  # noqa: E402
import inspect_definition as definition  # noqa: E402

PINNED = {
    'inspect_pkg.py': '4f89ac322421842a9812e9c577c2b26f7e8436738ebd07104fb263f94c8cfdf9',
    'inspect_definition.py': '678268321579b34ef75662102fba1b734deb9421b59d39f3f314c24057402550',
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def string(data):
    return struct.pack('<H', len(data)) + data


def leaf(name, data):
    return b'\x00' + string(name) + string(b'') + struct.pack('<I', len(data)) + data + b'\x00\x00'


def package(records, padding=b''):
    body = b'\x01\x00\x01\x00' + struct.pack('<H', len(records)) + b''.join(records) + padding
    block = zlib.compress(body)
    return b'\x00' + string(b'1.000000') + b'\x01\x00' + struct.pack('<II', len(block), len(body)) + block


def fixtures():
    fields = b','.join(('k%03d=' % index).encode('ascii') + b'"\xe9"' for index in range(512))
    for _ in range(29):
        fields = b'a' * 128 + b'={' + fields + b'}'
    return {
        'report-limit.mod': b'modelTypes.X={' + fields + b'}',
        'file-directory-collision.pkg': package([b'\x01' + string(b'foo') + b'\x00\x00', leaf(b'foo', b'x')]),
        'duplicate-file-path.pkg': package([leaf(b'foo', b'first'), leaf(b'foo', b'second')]),
        'empty-filename.pkg': package([leaf(b'', b'x')]),
        'long-nonzero-trailer.pkg': package([leaf(b'foo', b'x')], padding=b'X' * 513),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, help='new receipt file (exclusive create); default stdout')
    args = parser.parse_args()
    if not __debug__:
        raise SystemExit('Assertions are required; do not use optimized Python.')
    code_hashes = {name: sha((TOOLS / name).read_bytes()) for name in PINNED}
    if code_hashes != PINNED:
        raise SystemExit('Research source files do not match the audited copies.')
    inputs = fixtures()
    fixture_dir = BASE / 'inputs'
    fixture_dir.mkdir(exist_ok=True)
    for name, data in inputs.items():
        path = fixture_dir / name
        if path.exists():
            if path.read_bytes() != data:
                raise SystemExit('Existing fixture differs: ' + name)
        else:
            with path.open('xb') as destination:
                destination.write(data)

    source = inputs['report-limit.mod']
    try:
        definition.inspect(source)
    except ValueError as exc:
        error = {'class': type(exc).__name__, 'message': str(exc),
                 'code': getattr(exc, 'code', None), 'offset': getattr(exc, 'offset', None)}
    else:
        raise AssertionError('Expected a report-limit refusal')
    assert error == {'class': 'ValueError', 'message': 'definition report byte limit exceeded',
                     'code': None, 'offset': None}
    default_limit = definition.MAX_REPORT_BYTES
    try:
        definition.MAX_REPORT_BYTES = 8 * 1024 * 1024
        result = definition.inspect(source)
        measured_bytes = len(definition.serialized_report(result).encode('ascii'))
    finally:
        definition.MAX_REPORT_BYTES = default_limit
    diagnostic_count = len(result['diagnostics'])
    assert diagnostic_count == 512 and measured_bytes > default_limit

    packages = {}
    for name in ('file-directory-collision.pkg', 'duplicate-file-path.pkg', 'empty-filename.pkg'):
        result = pkg.inspect(inputs[name])
        packages[name] = {
            'result': 'research probe accepted as inert data',
            'directory_count': result['directories'],
            'member_paths': [m['path_components'] for m in result['members']],
            'member_raw_paths': [m['path_components_raw_hex'] for m in result['members']],
            'member_sha256': [m['sha256'] for m in result['members']],
        }
    assert packages['file-directory-collision.pkg']['directory_count'] == 1
    assert packages['file-directory-collision.pkg']['member_paths'] == [['foo']]
    assert packages['duplicate-file-path.pkg']['member_paths'] == [['foo'], ['foo']]
    assert packages['empty-filename.pkg']['member_paths'] == [['']]
    try:
        pkg.inspect(inputs['long-nonzero-trailer.pkg'])
    except pkg.FormatError as exc:
        trailer_result = {'class': type(exc).__name__, 'message': str(exc),
                          'actual_trailer_bytes': 513, 'all_trailer_bytes_nonzero': True}
    else:
        raise AssertionError('Expected a long-trailer refusal')
    assert trailer_result['message'] == 'zero padding limit exceeded'
    report = {
        'scope': 'Synthetic research-tool behavior only; no production importer or security qualification.',
        'research_commit': '3619c19362064a0a51b6fda360adce0bfeb38b3d',
        'python': platform.python_version(), 'zlib': zlib.ZLIB_RUNTIME_VERSION,
        'source_sha256': code_hashes, 'reproducer_sha256': sha(Path(__file__).read_bytes()),
        'inputs': {name: {'bytes': len(data), 'sha256': sha(data)} for name, data in inputs.items()},
        'report_limit': {'default_max_bytes': default_limit, 'refusal': error,
                         'diagnostics_after_in_memory_cap_increase': diagnostic_count,
                         'rendered_bytes_after_in_memory_cap_increase': measured_bytes},
        'package_tree_cases': packages, 'nonzero_trailer_case': trailer_result,
    }
    output = json.dumps(report, indent=2, ensure_ascii=True) + '\n'
    if args.report:
        with args.report.open('x', encoding='utf-8', newline='\n') as destination:
            destination.write(output)
    else:
        print(output, end='')


if __name__ == '__main__':
    main()
```
