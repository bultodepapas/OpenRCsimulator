# Portable reproduction: controller profile audit

These instructions rerun the disposable fixtures after the `profiles` evidence directory is moved. They do not require the original `/workspace/...` paths. The retained `notes.md` and checked logs record the original run, including its original absolute paths; those records are not rewritten here.

The probes intentionally assert that the audited adverse behavior occurs. A successful probe therefore **reproduces the finding**, not a production regression-test pass. They use synthetic device observations and input events; no physical controller, SDL enumeration, native package, or actual flight is tested. The concurrency fixture adds a scheduler around the real store transaction so the two real saves read the same starting state before publication.

## Prerequisites

- Python 3.10 or later and a shell. The commands below are for Linux; the recorded engine and results were Linux x86-64.
- The pinned Godot `4.8.beta2.official.cafc17a19` executable. For the recorded Linux executable, SHA-512 was `428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9`. Verify the version and hash before claiming the original engine identity. A different platform or executable is new evidence, not an exact replay of the original run.
- `tools/godot/run_checked.py` from OpenRC snapshot `f41d0fd2eb5483c609bcd858bcf22776eb311e14`. Supply its path as `CHECKED_RUNNER`; it uses Python's standard library for these commands.
- The archived `repro/` directory, including its `input/`, `ui/`, `app_state/build_info.gd`, four generic SVG assets, project file, and four probe scripts. These copy scopes were checked against the target snapshot: 209 tracked input/UI/build-info files matched byte-for-byte. The disposable project file and probe scripts are audit fixtures; they are not production source.
- A writable evidence directory. Fresh import, checked logs, isolated user data, and race files are written beneath it. The original checked runs remain in uniquely named directories.

An imported `.godot/` cache is host-specific and need not be archived. **Import the disposable project after moving it**, before running scripts, so the SVG prompt assets and resource cache are available. Run all examples from the moved `profiles` directory and replace the two example absolute paths:

```sh
cd /path/to/archived/profiles
export GODOT_BIN=/absolute/path/to/Godot_v4.8-beta2_linux.x86_64
export CHECKED_RUNNER=/absolute/path/to/OpenRC/tools/godot/run_checked.py
export PROFILE_AUDIT_ROOT="$PWD"
export XDG_DATA_HOME="$PROFILE_AUDIT_ROOT/portable-userdata"
export XDG_CONFIG_HOME="$PROFILE_AUDIT_ROOT/portable-config"

"$GODOT_BIN" --version
sha512sum "$GODOT_BIN"
python3 "$CHECKED_RUNNER" --label portable-profile-import \
  --out-dir "$PROFILE_AUDIT_ROOT/checks" --timeout 60 -- \
  "$GODOT_BIN" --headless --path "$PROFILE_AUDIT_ROOT/repro" \
  --audio-driver Dummy --import
```

Inspect the import's `report.json` and `engine.log`: `ok: true` is required. An engine exit code alone is insufficient. The import writes only to the disposable project and selected user/config paths.

## Profile and capture probes

```sh
python3 "$CHECKED_RUNNER" --label portable-profile-probe \
  --out-dir "$PROFILE_AUDIT_ROOT/checks" --timeout 60 \
  --require-text 'AUDIT_PROBE_COMPLETE failures=0' -- \
  "$GODOT_BIN" --headless --path "$PROFILE_AUDIT_ROOT/repro" \
  --audio-driver Dummy --script res://probe.gd

python3 "$CHECKED_RUNNER" --label portable-capture-probe \
  --out-dir "$PROFILE_AUDIT_ROOT/checks" --timeout 60 \
  --require-text 'CAPTURE_PROBE_COMPLETE failures=0' -- \
  "$GODOT_BIN" --headless --path "$PROFILE_AUDIT_ROOT/repro" \
  --audio-driver Dummy --script res://capture_probe.gd
```

The first performs 12 observation checks: hidden draft loss, same-ID profile reassociation for gamepad and saved radio, and the conditional serial/GUID matcher case. The second performs 6 observation checks for AUX capture across a synthetic same-ID replacement and action remapping interrupted by a synthetic throttle event. Each invocation gets a new report directory under `checks/`; inspect `ok`, the full `engine.log`, and the completion marker. `user://` data is isolated by the exported XDG paths on Linux.

## Concurrent-store probe

After the import above:

```sh
python3 "$PROFILE_AUDIT_ROOT/run_concurrent_portable.py"
```

Alternatively pass explicit paths with `--godot-bin /path/to/godot --checked-runner /path/to/run_checked.py`; command-line values override the environment variables. The launcher finds the evidence root from its own file location. It starts A and B, waits until **both** have read the same empty store and reached their ready markers, releases A and waits for its successful checked completion, then releases B and waits for its successful checked completion. A third checked invocation reads the store. The original observed outcome was both saves reporting success while the final list contained only `Writer B`. The launcher creates a fresh `race-portable-*` directory for markers and the shared test store, and fresh `race-portable-*` reports under `checks/`. It does not use or change the original race directory.

The original `run_concurrent.py` is retained as historical evidence of the first run and contains the old host paths. Use `run_concurrent_portable.py` for a moved archive.

## Clean evidence to archive

Paths below are relative to the `profiles` evidence directory. Preserve the directory structure.

- `notes.md`, `PORTABLE_REPRO.md`, `run_concurrent.py`, and `run_concurrent_portable.py`.
- `repro/project.godot`, `repro/probe.gd`, `repro/capture_probe.gd`, `repro/concurrent_writer.gd`, `repro/inspect_store.gd`, `repro/input/`, `repro/ui/`, `repro/app_state/build_info.gd`, and `repro/assets/input_prompts/generic/`. Exclude the regenerable `repro/.godot/` cache.
- `checks/profile-audit-assets-import-yfc_tgwp/`, `checks/profile-audit-probe-clean-95t_jjdb/`, and `checks/capture-audit-probe-_6ptodtq/`.
- `checks/race-writer-A-voljxvdk/`, `checks/race-writer-B-5x8nh0xi/`, `checks/race-final-store-2eo9smvp/`, and `race-1794668650276559412/`.

Each listed checked directory contains its original `engine.log` and `report.json`. The earlier `profile-audit-probe-aqroftz6` and `profile-audit-probe-complete-hqcbb0k0` runs failed because the initial disposable fixture was missing a dependency or assets; they are disclosed in `notes.md` and are not the clean reproductions. `userdata/` and `config/` are disposable and are not needed to reproduce; a fresh run writes separate data.
