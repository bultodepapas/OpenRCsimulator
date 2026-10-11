# D6b-R2 rearming verification

2026-10-09 · **Status: implemented and verified.** [Evidence and limits](../../../docs/research/radio-input/D6b-R2/README.md).

```sh
python3 research/input/d6b-r2/verify.py --out /tmp/d6b-r2-proof
```

Requires Python's standard library and the repository's pinned Godot. The output folder must be new. Runs 365 checks in a minimal private project, then seven isolated reader defects; requires each intended assertion to fail and refuses engine errors or incomplete runs. It checks input hashes afterward and never edits the application.

Optional `--baseline /path/to/original-reader.gd` reproduces the old stale-history defect. The evidence report provides the retained reverse patch and source identities. This is software verification, not physical controller qualification.
