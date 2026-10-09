# DATA-2b — Loader profiling and exact termination proof

**Status:** implemented verification tools. [Evidence, measurements and limits](../../../docs/research/aircraft-validation/DATA-2b/README.md).

From the repository root:

```sh
python3 research/aircraft-data/data2b/verify.py --output /tmp/data2b-evidence
```

The output directory must be empty. Python standard library and the repository's pinned Godot are sufficient. `--loader` can select an isolated candidate; it must contain the exact midpoint guard. The verifier constructs the old implementation by removing that guard in a temporary file, compares complete loader results as bytes, profiles envelope/induced-flow costs and inverse counts, tests varied maps and validation refusals, and detects an intentionally premature exit. It records all source hashes and refuses engine errors or incomplete output. GDScript files are private drivers whose environment is supplied by the verifier.

Timing is diagnostic: two alternating warm-cache runs on a shared host, without an application cache. Neither cold-start performance nor real-aircraft accuracy is established.
