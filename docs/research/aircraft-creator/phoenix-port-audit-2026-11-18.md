# Phoenix port and discovery audit — 2026-11-18

## 1. Outcome and exact scope

This second documentation pass closes twelve additional planning gaps around dependency closure, directory identity, discovery coverage, format ambiguity and a faithful Python-to-Godot port. It adds a [runtime port contract](../../plans/phoenix-aircraft-import/runtime-port.md), a [controlled GEO feasibility protocol](../../plans/phoenix-aircraft-import/geo-feasibility.md) and fourteen additional [acceptance specifications](../../plans/phoenix-aircraft-import/verification.md#9-runtime-port-and-discovery-regressions). The current guide contains **79 proposed acceptance cases**; the GEO protocol has **16 separately counted investigation rows**.

The work remains **documentation and original research evidence only**. No production application, research parser, compiled asset or simulator installation is changed. No GEO decoder, Godot/Builder execution, real-aircraft conversion, exported-platform campaign or flight qualification is delivered. The [parent plan](../../plans/phoenix-aircraft-import.md) remains the only AC-PX milestone owner.

| Baseline | Exact identity and use |
| --- | --- |
| Research/documentation branch | [`818581323f437f0c3ee1a5eac55cfcf2079d1ac8`](https://github.com/bultodepapas/OpenRCsimulator/tree/818581323f437f0c3ee1a5eac55cfcf2079d1ac8), `plan/flight-simulator-aircraft-import-2026-11-16` |
| Current-main source inspected | [`39fa2746ae4f4ba8698b87db279adcfe84ef5d17`](https://github.com/bultodepapas/OpenRCsimulator/tree/39fa2746ae4f4ba8698b87db279adcfe84ef5d17); unchanged from the first audit when this pass began |
| Application engine identified | `4.8.beta2.official.cafc17a19`; source-identified, not executed |
| Reference execution | Python 3.12.14, zlib runtime 1.3.2; trusted research source captured, hash-checked and compiled from those exact bytes |

Three bounded independent reviews examined port contracts, GEO experiments and adversarial plan/receipt details. The lead checked the relevant source, integrated the findings and executed the new original reference campaign. Helper review is evidence for review decisions, not a substitute for future application qualification.

The prior audit's 118 existing synthetic checks and five boundary fixtures remain [historical evidence](phoenix-plan-audit-2026-11-18.md). They were not rerun in this pass because their source/input baseline had not changed. The new campaign has **19 distinct cases**, including expected refusals. A second execution of those same nineteen inputs refined receipt scope/severity after review; it does not create nineteen additional cases.

## 2. New reference evidence

The [machine-readable vectors](phoenix-port-reference-vectors-2026-11-18.json) preserve each original input's full hex, byte count, SHA-256 and reference outcome. Accepted means research framing/tree or MOD syntax/summary returned; it does not mean runtime namespace, complete-aircraft or conversion admission. Detailed MOD diagnostics preserve severity, source location and occurrence path. Two accepted syntax cases contain conversion blockers.

| Original case family | Count | Observed research result / limit |
| --- | --- | --- |
| Small/full-window zlib controls | 3 | All pass Python framing/tree checks. The 512-byte-window long case emits a 5,142-byte body. Godot's existing small-window policy predicts refusal by source inspection only. |
| Tree/member data across chunk boundaries | 1 | Body/member identity and chunk-to-body intervals retained. It is not a compressed-byte-to-MOD one-to-one map. |
| Omitted file child-count bytes | 2 | Both expected truncation refusals; no valid zero field manufactured. |
| Frozen PKG/STL and PKG/MOD/STL inputs | 2 | Both pass research PKG framing/tree; source-derived STL arithmetic is finite/nondegenerate with positive bounds. The larger has readable `modelTypes.X={}`. No Godot or full-aircraft admission executed. |
| Decimal length/range boundaries | 3 | 64 digits and minimum positive fixed decimal parse; 65 digits give `NUMBER_LIMIT`. |
| Two nearest-even midpoint decimals | 2 | Exact expected binary64 bits, including opposite tie directions around 1. |
| Negative zero and leading/trailing zeros | 2 | Raw lexemes and rational values retained; negative-zero binary64 sign preserved in the reference projection. |
| Exact-equal and precision-collapsed pivots | 2 | Syntax returns, with `COINCIDENT_PIVOTS` / `PIVOT_PRECISION_LOSS`, both `conversion_blocker`. |
| Equal display, different raw string bytes | 2 | `c3 a9` versus `e9` retain separate input/lexical identities and `DISPLAY_DECODING_ONLY` observations. |

Total: **16 research parse/framing returns, three expected refusals, nineteen checked cases**. Every expected outcome assertion completed with exit 0. No statement here promotes the two source-derived STL checks or the zlib policy comparison into executed engine results. Original synthetic bytes are suitable to retain as test evidence; no downloaded aircraft binaries were committed.

### 2.1 Exact identities and reproducibility

| Item | SHA-256 |
| --- | --- |
| Captured/compiled `inspect_pkg.py` | `4f89ac322421842a9812e9c577c2b26f7e8436738ebd07104fb263f94c8cfdf9` |
| Captured/compiled `inspect_definition.py` | `678268321579b34ef75662102fba1b734deb9421b59d39f3f314c24057402550` |
| Observed reproduction script file, embedded below | `e411f170450640b7cd964bf3db4d3529b384b8945bc9d86ceabe2cccbb662360` |
| Published vector JSON | `caed03aff4fa0dd456e87d7f56cc98c6c0163f75d394718a1d1970ae17413b0c` |
| Original 134-byte PKG/STL vector | `3d385fa6c3196f91b6f6cafef7bc8f9f1cbfc6c1514650dcc3a5daf70c4d8e1a` |
| Original 184-byte PKG/MOD/STL vector | `cfe565dc09dfd0931fdea25612b27c6d34c6364c20679e7f6f0941d3db8e8b86` |

The parser identities refer to the same source bytes read, hash-checked and compiled by the reproduction; no parser bytecode cache is used. The script's own hash is an observation of its on-disk file after execution began, not an attestation against concurrent script replacement. The script was unchanged during this run and its embedded copy is checked against that observation. Compressed output from another zlib build may differ; retain the frozen vector bytes/hashes when comparing runtimes rather than assuming every compressor emits identical bytes.

Independent receipt review recomputed all nineteen input hashes/lengths, accepted stream/body/member identities, truncated-boundary shapes and numeric/source-span facts without executing the research parsers. It independently compared recorded numeric projections with exact rational values and adjacent binary64 values. Review found and corrected the missing distinction between parse return and conversion-blocker severity; it also prompted explicit script-hash scope. The final JSON retains those corrections.

## 3. Findings and required implementation consequences

Priority describes planning consequence, not vulnerability severity. Every runtime change in this table remains proposed; the documentation correction is complete.

| ID / priority | Evidence and problem | Correction / acceptance |
| --- | --- | --- |
| PX-B01 / High | Previous closure pseudocode visited direct MOD references only, then called the result closed. **Plan inspection.** A required second-hop leaf could remain unchecked. Review also found cached shared subtrees could hide excess depth on a longer incoming route. | Bounded typed graph traversal, exact scope/role identities, gray/black cycle handling, cached descendant height checked at every reuse, shared logical edges and no success with pending work. Both diamond traversal orders have the same depth verdict. Implementation section 5; PX-P09. |
| PX-B02 / High | Directory enumeration order had no canonical identity contract. **Plan inspection.** Two enumerations could assign different ordinals or first-match outcomes. | Capture complete bounded membership, validate collisions, then versioned raw-component ordering/manifest identity. Preserve source order for archives/MOD. PX-P10. |
| PX-B03 / High | A partial discovery list could be confused with complete/unique coverage. **Plan inspection.** | Explicit profile-scoped complete/incomplete/cancel states and unchecked/unsupported identities; separate enclosing namespace from selected closure and unselected unsupported payload. PX-P11. |
| PX-B04 / High | Content signatures need not be mutually exclusive: two original PKGs also satisfy inspected binary-STL conditions; one contains a readable empty MOD. **Python execution plus source-derived arithmetic, no engine pass.** | Collect competing matches; no first-match, suffix or failure-driven silent fallback. Explicit interpretation binds the complete selected contract. PX-P12. |
| PX-B05 / High | Existing image zlib policy treats small declared window as an output ceiling; raw-DEFLATE reuse lacks a complete zlib wrapper/window/checksum proof. **Source inspection plus new Python control.** | Separate qualified PKG adapter or explicit narrow policy; retain PNG restrictions. Check actual EOF/consumption, Adler/header/dictionary/distance and work. PX-P01. |
| PX-B06 / High | Short Godot decode helpers can return zero while Python's cursor refuses before reading; zero is a legitimate file child count. **API/source inspection plus Python truncation cases.** | Checked subtraction-based bounds before every primitive/slice; unchanged failure cursor and scoped failure location. PX-P02. |
| PX-B07 / High | Canonical-writer float recovery is not an arbitrary-decimal nearest-even parser. Earlier PX-D05 also proposed binary64 overflow impossible under its 64-byte fixed grammar. **Source/math review plus new exact-decimal vectors.** | Raw normalized decimal identity, bounded rational/RNE algorithm, independent midpoint/collapse oracles; use real token/float32 boundaries. PX-P05/06. |
| PX-B08 / High | Package offsets, inflated-body offsets and MOD offsets were not given explicit tagged coordinate spaces. **Source/plan inspection plus split-chunk vector.** | Capture/member identities and half-open tagged spans, chunk-to-body map; no arithmetic translation through compressed offsets. PX-P03. |
| PX-B09 / High | ClearView archive indexes a duplicate but hashes the caller's original bytes. **Source-derived ownership seam, not executed mutation.** | One private buffer for hash/index/decode, controlled original-argument mutation test, preserve source/profile fingerprints. PX-P07. |
| PX-B10 / High | Existing inflate sink is output-driven; raw decoder can classify cancellation as invalid input and stored copies lack inner-loop work/cancel checks. **Source inspection.** | Shared bounded work/ticket at all phases, explicit internal cancellation and checked Creator result adaptation; qualify native-call latency. PX-P08. |
| PX-B11 / Medium | Port/report semantics needed exact positive grammar boundaries and evidence levels: empty root, comments between symbol tokens, table-only depth and conversion blockers after syntax success. **Source/receipt review.** | Match the common byte grammar, preserve raw identity/severity, qualify narrower policies separately; no Boolean parse success promoted to readiness. PX-P04/06/13. |
| PX-B12 / Gate | GEO plan lacked controlled source→Builder-state→export separation and a falsifiable experiment sequence. **Plan/primary-source review; no newly verified GEO/source pair.** | Original OBJ oracle, repeat/noise controls, sixteen single-concept rows and independently frozen held-out comparisons. PX-P14; feasibility remains open. |

### 3.1 Pinned source anchors

| Concern | Inspected source |
| --- | --- |
| PKG and MOD reference | [inspect_pkg.py](https://github.com/bultodepapas/OpenRCsimulator/blob/818581323f437f0c3ee1a5eac55cfcf2079d1ac8/research/aircraft-creator/phoenix/inspect_pkg.py), [inspect_definition.py](https://github.com/bultodepapas/OpenRCsimulator/blob/818581323f437f0c3ee1a5eac55cfcf2079d1ac8/research/aircraft-creator/phoenix/inspect_definition.py) |
| Image zlib and raw DEFLATE policies | [inflate.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/inflate.gd), [clearview/deflate.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/clearview/deflate.gd) |
| Owned bytes, writer number semantics and errors | [clearview/archive.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/clearview/archive.gd), [bytes.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/bytes.gd), [result.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/result.gd) |
| STL conditions and current source routing | [stl_reader.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/stl_reader.gd), [source_importer.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/39fa2746ae4f4ba8698b87db279adcfe84ef5d17/app/workshop/creator/source_importer.gd) |

## 4. Primary external evidence and next decisions

The additional technical checks used [RFC 1950](https://www.rfc-editor.org/rfc/rfc1950.html), the [zlib manual](https://www.zlib.net/manual.html), [Godot PackedByteArray](https://docs.godotengine.org/en/stable/classes/class_packedbytearray.html), [Godot String](https://docs.godotengine.org/en/stable/classes/class_string.html) and the [Python 3.12 zlib API](https://docs.python.org/3.12/library/zlib.html). Online manuals are API/format references, not proof of this unexecuted engine build; the locally measured zlib runtime is 1.3.2 regardless of the manual's current release.

GEO workflow evidence comes from the original-user [Builder discussion](https://www.rcuniverse.com/forum/rc-flight-simulator-software-138/11612102-phoenix-builder.html), [Eagle II author account](https://mail.supermotoxl.com/projects-articles/ready-to-drive-fly-models/dancing-wings-hobby-eagle-ii-phoenix-r-c-simulator.html), a [Builder guide mirror](https://www.scribd.com/document/739064752/UserGuide) and the versioned [Blender 3.2 OBJ documentation](https://docs.blender.org/manual/en/3.2/addons/import_export/scene_obj.html). The [GEO protocol](../../plans/phoenix-aircraft-import/geo-feasibility.md#1-what-the-additional-research-actually-supports) states the provenance and precise limits of each source. No vendor document explains a complete verified GEO layout here.

The next implementation decisions are concrete: select a capture backend, qualify a PKG zlib adapter without altering PNG semantics, choose a bounded exact-decimal projection implementation, and implement typed complete dependency traversal/discovery reports. In parallel, obtain an owned and independently characterized source/Builder/export pair under the controlled protocol. These decisions advance inspection and evidence without presuming a complete visual or physical importer.

## 5. Reproduce the nineteen reference cases

Save the following exact code as a new private `round2_reference_probe.py` with LF endings. Use a trusted checkout whose two research parser hashes match the table, a fresh output filename and ordinary non-optimized Python. The script reads/executes only those hash-checked trusted parser sources, not aircraft scripts or external executables; it creates original tiny inputs and writes its report exclusively. The compiled module names are fixed by the harness, never supplied by a package.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 /absolute/private/round2_reference_probe.py \
  --repo /absolute/trusted/OpenRCsimulator \
  --report /absolute/private/phoenix-port-reference-new-run.json
```

Expected command result: exit 0, nineteen unique cases, `reference_checks` equal to `passed`, and `godot_executed` false. Do not demand identical new compressed hashes across zlib builds; use the published fixed input bytes for exact differential engine tests. This is not the application test command; engine work follows the [verification workflow](../../plans/phoenix-aircraft-import/verification.md#71-commands-for-application-implementation-work).

<!-- BEGIN EXACT ORIGINAL REFERENCE PROBE -->

```python
#!/usr/bin/env python3
"""Original port-reference vectors; captured research sources, no Godot/Builder."""
import argparse
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import platform
import struct
import sys
import types
import zlib

PINS = {
    "inspect_pkg.py": "4f89ac322421842a9812e9c577c2b26f7e8436738ebd07104fb263f94c8cfdf9",
    "inspect_definition.py": "678268321579b34ef75662102fba1b734deb9421b59d39f3f314c24057402550",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load_captured(root, filename):
    path = root / "research/aircraft-creator/phoenix" / filename
    source = path.read_bytes()
    if sha(source) != PINS[filename]:
        raise RuntimeError("Unexpected trusted source: " + filename)
    name = filename[:-3]
    module = types.ModuleType(name)
    module.__file__ = str(path)
    sys.modules[name] = module
    exec(compile(source, str(path), "exec"), module.__dict__)
    return module


def u16(n):
    return struct.pack("<H", n)


def u32(n):
    return struct.pack("<I", n)


def string(raw):
    return u16(len(raw)) + raw


def body(payload, name=b"x.bin"):
    return (b"\x01\x00\x01\x00" + u16(1) + b"\x00" + string(name)
            + string(b"") + u32(len(payload)) + payload + u16(0))


def package(parts, wbits=15):
    result = b"\x00" + string(b"1.000000") + u16(len(parts))
    for plain in parts:
        encoder = zlib.compressobj(wbits=wbits)
        compressed = encoder.compress(plain) + encoder.flush()
        result += u32(len(compressed)) + u32(len(plain)) + compressed
    return result


def frozen_polyglot(with_mod):
    label = b"1" * 64 + b".000000"
    if with_mod:
        first = bytes.fromhex("789c6364000000040002")
        second = bytes.fromhex(
            "789c63646062606065a8d0cbcd4f6160e067606000325273422a0b528bf5226c"
            "ab6b81228c0c490c0cb240c6ef456ff4c4f4fdaf18bf91e47ff7738fb5d3d939"
            "57ff7c3cc01f6811fb5d80810100cdcd17cc")
        sizes = (2, 76)
    else:
        first = bytes.fromhex("789c63040000020002")
        second = bytes.fromhex("789c636064606400a20a06064e060686a633dd2f9a6f5d9df38681010035140700")
        sizes = (1, 26)
    return (b"\x00" + string(label) + u16(2)
            + u32(len(first)) + u32(sizes[0]) + first
            + u32(len(second)) + u32(sizes[1]) + second)


def stl_source_arithmetic(data):
    count = struct.unpack_from("<I", data, 80)[0]
    assert count in (1, 2) and len(data) == 84 + 50 * count
    points = []
    for index in range(count):
        values = struct.unpack_from("<12f", data, 84 + 50 * index)
        assert all(math.isfinite(x) for x in values) and math.isfinite(sum(values))
        triangle = [values[3 + 3 * i:6 + 3 * i] for i in range(3)]
        a = [triangle[1][i] - triangle[0][i] for i in range(3)]
        b = [triangle[2][i] - triangle[0][i] for i in range(3)]
        cross = (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
        assert any(x != 0 for x in cross) and math.isfinite(sum(cross))
        points.extend(triangle)
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    assert all(high[i] > low[i] for i in range(3))
    return {"facet_count": count, "finite_non_degenerate": True,
            "bounds_min": low, "bounds_max": high, "actual_godot_executed": False}


def pivot_source(left, right):
    return (b"modelTypes.X={airfoils={{controlSurfaces={{root_pivot={x=" + left
            + b",y=0,z=0},tip_pivot={x=" + right + b",y=0,z=0}}}}}}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if not __debug__:
        raise SystemExit("Do not use optimized Python: fixture assertions are required.")
    pkg = load_captured(args.repo, "inspect_pkg.py")
    mod = load_captured(args.repo, "inspect_definition.py")
    cases = []
    full_body = body(bytes(range(256)) * 20)
    split_body = body(b"modelTypes.X={name=\"split\",v=1.25}", b"x.mod")
    package_inputs = [
        ("small-window-long-output", package([full_body], 9), None),
        ("full-window-long-output", package([full_body], 15), None),
        ("small-window-short-output", package([body(b"12345678")], 9), None),
        ("record-split-across-chunks", package([split_body[:11], split_body[11:28], split_body[28:]]), None),
        ("missing-one-file-child-byte", package([body(b"x")[:-1]]), "truncated"),
        ("missing-two-file-child-bytes", package([body(b"x")[:-2]]), "truncated"),
        ("pkg-stl-polyglot-134", frozen_polyglot(False), None),
        ("pkg-mod-stl-polyglot-184", frozen_polyglot(True), None),
    ]
    for case_id, data, refusal in package_inputs:
        entry = {"id": case_id, "kind": "pkg", "acceptance_scope": "Research framing/tree only; not runtime namespace or aircraft admission", "input_hex": data.hex(),
                 "input_bytes": len(data), "input_sha256": sha(data)}
        try:
            report = pkg.inspect(data)
        except pkg.FormatError as error:
            assert refusal and refusal in str(error)
            entry["reference"] = {"accepted": False, "exception": type(error).__name__, "message": str(error)}
        else:
            assert refusal is None
            entry["reference"] = {"accepted": True, "body_bytes": report["body_bytes"],
                                  "body_sha256": report["body_sha256"], "chunks": report["chunks"],
                                  "members": report["members"]}
            offset = 0
            windows = []
            for chunk in report["chunks"]:
                cmf = data[chunk["offset"]]
                window = 1 << ((cmf >> 4) + 8)
                windows.append(window)
                chunk["inflated_body_start"] = offset
                offset += chunk["inflated_bytes"]
                chunk["inflated_body_end_exclusive"] = offset
            entry["reference"]["declared_zlib_windows"] = windows
            if case_id == "small-window-long-output":
                assert windows == [512] and report["body_bytes"] > 512
                entry["source_derived_godot_policy"] = "STATUS_WINDOW before inflate; not an executed engine result"
            if "polyglot" in case_id:
                expected = ("cfe565dc09dfd0931fdea25612b27c6d34c6364c20679e7f6f0941d3db8e8b86"
                            if case_id.endswith("184") else
                            "3d385fa6c3196f91b6f6cafef7bc8f9f1cbfc6c1514650dcc3a5daf70c4d8e1a")
                assert sha(data) == expected
                entry["source_derived_stl_conditions"] = stl_source_arithmetic(data)
                if case_id.endswith("184"):
                    chunks = report["chunks"]
                    raw_body = b"".join(zlib.decompress(data[c["offset"]:c["offset"]+c["compressed_bytes"]]) for c in chunks)
                    member = next(x for x in report["members"] if x["path_components"] == ["x.mod"])
                    content = raw_body[member["body_offset"]:member["body_offset"]+member["bytes"]]
                    assert content == b"modelTypes.X={}" and sha(content) == member["sha256"]
                    assert mod.inspect(content)["target"] == "X"
                    entry["reference"]["parsed_mod"] = {"target": "X", "complete_aircraft": False}
        cases.append(entry)

    ties = [b"1.00000000000000011102230246251565404236316680908203125",
            b"1.00000000000000033306690738754696212708950042724609375"]
    numeric_sources = [
        ("numeric-64-bytes", b"9" * 64),
        ("numeric-65-bytes", b"9" * 65),
        ("minimum-positive-fixed-profile", b"0." + b"0" * 61 + b"1"),
        ("binary64-midpoint-even-lower", ties[0]),
        ("binary64-midpoint-even-upper", ties[1]),
        ("negative-zero", b"-0"),
        ("leading-trailing-zero-lexeme", b"0001.2500"),
    ]
    mod_inputs = [(name, b"modelTypes.X={v=" + value + b"}",
                   "NUMBER_LIMIT" if name == "numeric-65-bytes" else None, None)
                  for name, value in numeric_sources]
    mod_inputs += [
        ("exact-distinct-pivots-collapse", pivot_source(b"10000000000000000", b"10000000000000001"), None, "PIVOT_PRECISION_LOSS"),
        ("equal-decimal-pivots", pivot_source(b"1.0", b"1.00"), None, "COINCIDENT_PIVOTS"),
        ("utf8-display-identity", b'modelTypes.X={name="\xc3\xa9"}', None, "DISPLAY_DECODING_ONLY"),
        ("latin1-display-identity", b'modelTypes.X={name="\xe9"}', None, "DISPLAY_DECODING_ONLY"),
    ]
    for case_id, data, refusal, required_diagnostic in mod_inputs:
        entry = {"id": case_id, "kind": "mod", "acceptance_scope": "Research syntax/summary returned; conversion blockers remain independently binding", "input_hex": data.hex(),
                 "input_bytes": len(data), "input_sha256": sha(data)}
        try:
            definition = mod.parse(data)
            report = mod.summarize(definition)
        except mod.DefinitionError as error:
            assert error.code == refusal
            entry["reference"] = {"accepted": False, "code": error.code, "offset": error.offset,
                                  "line": error.line, "byte_column": error.column}
        else:
            assert refusal is None
            diagnostics = [d["code"] for d in report["diagnostics"]]
            assert required_diagnostic is None or required_diagnostic in diagnostics
            atoms = []
            for path, node in mod.walk(definition.root, (definition.target,)):
                if node.kind in ("number", "string", "symbol"):
                    atom = {"path": list(path), "kind": node.kind, "raw_hex": node.value.hex(),
                            "start_byte": node.start, "end_byte_exclusive": node.end}
                    if node.kind == "number":
                        value = float(node.value)
                        atom["binary64_le_hex_reference"] = struct.pack("<d", value).hex()
                        exact = Fraction(node.value.decode("ascii"))
                        atom["exact_decimal_rational"] = [str(exact.numerator), str(exact.denominator)]
                    atoms.append(atom)
            entry["reference"] = {"accepted": True, "target": definition.target,
                                  "token_count": definition.token_count, "node_count": definition.node_count,
                                  "diagnostic_codes": diagnostics, "diagnostics": report["diagnostics"],
                                  "conversion_preflight_blocked": any(d["severity"] == "conversion_blocker" for d in report["diagnostics"]),
                                  "atoms": atoms, "headers": report["headers"]}
            if case_id == "binary64-midpoint-even-lower":
                assert atoms[0]["binary64_le_hex_reference"] == "000000000000f03f"
            if case_id == "binary64-midpoint-even-upper":
                assert atoms[0]["binary64_le_hex_reference"] == "020000000000f03f"
            if case_id == "negative-zero":
                assert atoms[0]["binary64_le_hex_reference"] == "0000000000000080"
        cases.append(entry)
    assert len(cases) == 19
    output = {
        "schema": "openrc-phoenix-port-reference-vectors-v1", "date": "2026-11-18",
        "research_commit": "818581323f437f0c3ee1a5eac55cfcf2079d1ac8",
        "application_commit": "39fa2746ae4f4ba8698b87db279adcfe84ef5d17",
        "scope": "Original reference inputs; captured trusted Python research modules executed. Godot/Builder/real aircraft not executed. Source-derived STL and zlib-policy comparisons are not engine test results.",
        "python": platform.python_version(), "zlib_runtime": zlib.ZLIB_RUNTIME_VERSION,
        "executed_parser_source_sha256": PINS, "probe_script_sha256": sha(Path(__file__).read_bytes()),
        "probe_script_hash_scope": "Observed script-file bytes after execution began; not an attestation against concurrent script replacement",
        "source_identity": "Read, hash-check and compile the same captured trusted source bytes; no parser bytecode cache is used.",
        "fixture_count": len(cases), "cases": cases,
    }
    with args.report.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(output, handle, indent=2, ensure_ascii=True, allow_nan=False)
        handle.write("\n")
    print(json.dumps({"fixture_count": len(cases), "reference_checks": "passed",
                      "godot_executed": False, "report": str(args.report)}))


if __name__ == "__main__":
    main()
```

<!-- END EXACT ORIGINAL REFERENCE PROBE -->
