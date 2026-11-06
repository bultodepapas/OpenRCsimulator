# App tests

- How to run one script, the full suite, and write a test: [docs/tools/shared.md](../../docs/tools/shared.md#one-godot-script).
- `app/test.sh` in full mode runs every `test_*.gd` here; this is not an instruction to run the full suite after every edit. Select the smallest relevant scripts and affected consumers during development using [local impact examples](../../docs/tools/shared.md#local-impact-examples). `capture_*`, `bench_*`, `check_*` and `probe_*` files are run by `app/capture.sh`, by hand, or by other tests.
- Run single scripts through `tools/godot/run_checked.py`; Godot can exit 0 after a `SCRIPT ERROR`.
