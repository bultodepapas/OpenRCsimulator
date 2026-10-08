# G1a1 — Identified UIUC propeller knots

**Status:** offline source-normalization tool. [Evidence](../../../docs/research/propulsion/G1a1/README.md). Python standard library only; no application imports or aircraft writes.

```sh
python3 research/propulsion/uiuc-import/test_import.py
python3 research/propulsion/uiuc-import/check_mutations.py
python3 research/propulsion/uiuc-import/import_table.py \
  research/propulsion/uiuc-import/example.synthetic.json \
  research/propulsion/uiuc-import/example.synthetic.txt

# Download four pinned source files outside the repository and verify every source row.
python3 research/propulsion/uiuc-import/readback.py --raw-dir /tmp/uiuc-g1a1 --fetch
```

The importer emits `openrc-propeller-knots v1` JSON to stdout; invalid input exits 1 without a report. It reads both inputs once, checks the exact table bytes against the manifest SHA-256 before parsing, and records manifest/table/importer hashes. There is no network access in the importer, interpolation, extrapolation, coefficient fitting or data installation. Preserve the original external table and manifest alongside any locally generated report. Raw third-party files and full normalized tables are not bundled with this repository; checked-in test data are synthetic.

## Input and normalization

Use [example.synthetic.json](example.synthetic.json) as the manifest template. Each run is imported separately.

| Field | Meaning |
| --- | --- |
| `format` | `openrc-uiuc-source v1` |
| `id`, `notes` | Nonempty run identity and limitations |
| `evidence` | `measured-source` or `synthetic`; a declaration about source evidence, not independent validation |
| `table_kind` | `static` or `tunnel` |
| `source_url`, `source_sha256` | Declared HTTPS origin and exact lowercase 64-hex digest |
| `propeller` | Nonempty `manufacturer`, `family`, `nominal_size`, `source`; size is an opaque catalogue label |
| `coefficient_reference_diameter` | Explicit null if unknown; otherwise `{value, unit: m, kind, source}` identifying the diameter used to calculate the published coefficients. Positive finite value; kind measured/manual/derived/synthetic. Synthetic diameter refused for a measured source |
| `run_rpm_label` | Null or `{value, unit: rpm, source}` for a positive finite tunnel-run label. Always null for a static sweep |

The importer binds bytes to the supplied manifest; it does **not** authenticate the URL, family, size, measurement procedure or diameter declaration. Source-review evidence is separate. `sources.json` records four individually inspected UIUC sources, including their source listing links and unresolved diameter metadata. Neither the Sport 11×6 nor the Thin Electric 12×6 is automatically applicable to a Sport 12×6.

Only these whitespace-separated ASCII headers are accepted, with exactly the indicated number of cells per data row:

```text
RPM CT CP
J CT CP eta
```

Blank lines are allowed and still count toward physical source line numbers. Comments, unexpected headers/columns, nonnumeric tokens, nonfinite values and float64 overflow/nonzero underflow are refused. Static RPM must be positive; tunnel J must be nonnegative. Signed Ct, Cp and eta, including negative thrust/power and eta outside [0,1], are preserved without clamping. They are source observations, not a claim that every value is physically qualified.

Numeric identity is checked using exact decimal values before conversion to float64. Numerically identical complete rows collapse even if their spelling differs; every original line number remains attached. A repeated coordinate with any different coefficient or eta is refused, not averaged. Distinct decimal coordinates that would collapse to one float64 coordinate are also refused. At least two unique coordinates are required.

Unique knots are sorted by RPM or J. The report records input/unique/duplicate counts and whether the unique source order changed. This is a deliberate normalization of points, not preservation of acquisition order; line references retain the original order. Do not deduplicate only the last row or assume raw UIUC data are sorted.

## What remains unknown

- Static rows supply an RPM column at J=0. Tunnel files supply J but no per-row RPM: an optional filename/listing label is retained only in source metadata; each knot's RPM and `per_row_rpm_extent` remain null.
- Coordinate extents are endpoints of available knots, not continuous validated coverage, source uncertainty, or authorization to bridge a static/tunnel J gap.
- Nominal size is never parsed into a coefficient-reference diameter. Unknown diameter prevents justified conversion back to dimensional loads unless it is independently resolved.
- Full three-dimensional normal-force data, windmilling/stopped-propeller behavior, matched installation measurements and cross-RPM interpolation remain outside this tool.

[UIUC Volume 1](https://m-selig.ae.illinois.edu/props/volume-1/propDB-volume-1.html) distinguishes static sweeps and tunnel runs. [Volume 4](https://m-selig.ae.illinois.edu/props/volume-4/propDB-volume-4.html) warns that coefficient-reference diameter can differ from catalogue diameter. Both source families remain explicit in imported metadata.
