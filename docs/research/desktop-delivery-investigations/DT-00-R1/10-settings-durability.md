# 10 — Settings identity, durable writes and simultaneous instances

2026-10-07 · DT-00-R1 · **Investigated; isolated production-module probe executed. No storage implementation changed.**

## Question and method

Can an installed upgrade, display change or second application instance lose a pilot's preferences or calibration? Read `app/project.godot`, `app/app_state/preferences.gd`, `app/input/rc_calibration.gd`, Godot's pinned configuration writer and data-path documentation. Ran copied preferences/catalog/input modules in a disposable Godot 4.7.2 project with isolated XDG paths. [Probe](probes/pure_module_probe.py), [results and source hashes](probes/pure-module-results.json).

## Findings

| Finding | Evidence kind | Consequence |
| --- | --- | --- |
| The project uses the default `user://` directory, derived from application name; changing installer path does not relocate it | Project settings + [Godot data paths](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html) | Freeze user-data identity before branding changes; a portable ZIP is not automatically portable user data |
| The existing preferences store rejects writes to a future schema and preserves the file | Executed: schema 999, `writable=false`, error 10, identical bytes | Retain this protection; installer rollback must not silently downgrade saved data |
| Two readers can lose each other's changes | Executed interleaving: A loads; B loads; A saves Spanish; B saves aircraft using its old dictionary; final language becomes English | Decide a writer/instance policy before adding display persistence; rename alone cannot fix lost updates |
| Unknown keys under the current schema disappear on save | Executed: an extra key in schema 1 is absent after `load_from` → `save_to` | Add schema migration when new persistent fields are introduced; don't promise older binaries preserve arbitrary same-schema extensions |
| `ConfigFile.save()` is serialization, not a transactional settings protocol | Pinned [config_file.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/config_file.cpp) opens the destination for writing and serializes directly | A successful ordinary save is insufficient proof of recovery from interruption or full storage |
| Calibration now refuses to overwrite an unreadable existing calibration file and validates profiles | Current `rc_calibration.gd`, concurrent input-owner changes | Coordinate with that owner; the old DT-00 snapshot and earlier UI research predate this repair |

Godot exposes load/save errors and typed values through [ConfigFile](https://docs.godotengine.org/en/4.7/classes/class_configfile.html), while application validation and migration remain our responsibility. [FileAccess](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html) describes buffering/flush; it does not establish a cross-platform power-loss transaction. [DirAccess.rename_absolute](https://docs.godotengine.org/en/4.7/classes/class_diraccess.html#class-diraccess-method-rename-absolute) returns failure states that must be handled. A same-directory temporary replacement is a proposed implementation strategy, not a proven durability guarantee.

## Changes recommended for the plan

**DT-03a, coordinated with UI-07:** define one settings schema, migration rules, confirmed display state and user-data identity. Keep the existing application data location unless there is a concrete migration need. Freeze product name/custom-directory choices independently of install path and bundle identity. Stable/preview channels share data only by explicit policy; development/automation must use isolated paths.

Choose the smallest adequate concurrent-instance policy: one writable interactive instance per user-data directory, with an explicit secondary-instance outcome, or conflict-aware reload/merge under a real lock. Do not claim “single instance” from checking whether a lock file merely exists; crash recovery and races need tests. The first implementation may keep this narrowly scoped to writing preferences. Tests and command-line traces must not be blocked by an interactive singleton.

For storage, serialize and validate a candidate, preserve the confirmed file, and replace it only after checking write/readback/replace results. Keep the candidate and last known good state in the same user-data directory; define startup recovery for every interruption point. Avoid removing the only confirmed copy before replacement succeeds. Distinguish app-process interruption from sudden power loss in the guarantee.

**DT-09b/09c and DT-12:** installer upgrade/removal must not treat personal settings as disposable payload. Test old application/new schema, new application/old schema, installation path changes and preview/stable coexistence. Never silently transfer a calibration between ambiguous radio identities; see [12](12-radio-export-contract.md).

## Required proof

| Case | Required result |
| --- | --- |
| Interrupted candidate write / before replace / after replace | Next launch finds a valid confirmed configuration; no half-written mode becomes the new default |
| Full disk, write denied, replacement denied | Error visible, last known good file retained, current session can still exit/recover |
| Future schema and unsupported downgrade | Original file unchanged; readable supported values may be used without writing |
| Two interactive starts racing | Defined secondary behavior or no lost updates; retained lock recovers after process death |
| Display-only reset | Calibration file byte-identical; language/aircraft remain intact |
| Reinstall and changed install folder | Same intended data directory; settings/calibration available |
| Automation run | User settings and calibration are neither created nor modified |

Reproduce from repository root on Linux:

```bash
python3 docs/research/desktop-delivery-investigations/DT-00-R1/probes/pure_module_probe.py --godot "$(app/get-godot.sh)" --out /tmp/openrc-desktop-probe.json
```

The recorded run also used the Godot skill's optional `--linter`: before/after lint passed. The probe reproduces deterministic stale-reader interleaving, not simultaneous OS processes, file-system failure injection or power loss. It exercises no user's real files. The source hashes identify the exact modules despite the dirty shared repository. Vendor sources were opened on the report date; no third-party code was copied into the probe.
