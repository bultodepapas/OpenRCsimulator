# AS-04 model and flight integration checks

Status: passed (2026-10-11; verification only).

The five model-contract scripts and four real-app trimmed-flight traces passed with pinned native Godot 4.7.2. A Windows export pack was also built without downloading export templates and inspected by mounting it from an empty probe project.

## Model contracts

| Script | Result | Evidence |
| --- | ---: | --- |
| `verify_model.gd` | 807 checks, 0 failed | [verify_model.log](verify_model.log) |
| `verify_extra.gd` | 123 checks, 0 failed | [verify_extra.log](verify_extra.log) |
| `verify_p51.gd` | 248 checks, 0 failed | [verify_p51.log](verify_p51.log) |
| `verify_p51_clearance.gd` | 12 checks, 0 failed | [verify_p51_clearance.log](verify_p51_clearance.log) |
| `verify_avanti.gd` | 137 checks, 0 failed | [verify_avanti.log](verify_avanti.log) |

## Real-app trimmed-flight traces

Each trace used the catalog aircraft through the production app with `--quick-flight`, ran for 3 seconds at 240 Hz, and passed `app/tests/check_trimmed_flight.py` with its exact aircraft JSON supplied as input. Each CSV contains 721 samples: the initial sample plus 720 simulation ticks. All samples were finite and the checker confirmed altitude stayed at 30 m and initial speed matched the configured trim.

| Catalog ID | Input speed | Trace / checker evidence |
| --- | ---: | --- |
| `jensen-das-ugly-stik-60` | 15 m/s | [CSV](trace-jensen-das-ugly-stik-60.csv), [run](trace-jensen-das-ugly-stik-60.log), [check](check-jensen-das-ugly-stik-60.log) |
| `gp-extra-300s-60` | 17 m/s | [CSV](trace-gp-extra-300s-60.csv), [run](trace-gp-extra-300s-60.log), [check](check-gp-extra-300s-60.log) |
| `p51d-mustang-120` | 25 m/s | [CSV](trace-p51d-mustang-120.csv), [run](trace-p51d-mustang-120.log), [check](check-p51d-mustang-120.log) |
| `sebart-avanti-s-a200-p100rx` | 29 m/s | [CSV](trace-sebart-avanti-s-a200-p100rx.csv), [run](trace-sebart-avanti-s-a200-p100rx.log), [check](check-sebart-avanti-s-a200-p100rx.log) |

Ugly Stik emitted the existing non-fatal data warning that `Jyy = 0.3871 kg·m²` is 2.11 times the scaled UltraStick25e comparison value. No saved run log contains a Godot engine-error or failure marker.

## Export pack

Pinned Godot reported `4.7.2.stable.official.ed1daf0bf`; its archive SHA-512 matched the repository's pinned checksum (`83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb709bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993`). `--export-pack Windows` produced a 13,921,356-byte PCK at `.tools/as-integration/openrc-as04-windows.pck` (SHA-256 `94e84a1a84b635b1462686c1c9ce0e981959b55abe279456100232271f7933d7`). This was a pack-only check, not a release build; no export templates were downloaded.

The PCK was mounted in an isolated empty Godot project with `ProjectSettings.load_resource_pack()`. The probe found and parsed both `data/schema/aircraft-contract-v2.json` and `data/schema/openrc-aircraft-v2.schema.json`, plus all eight `data/aircraft/*.json` fleet entries; each aircraft file parsed as an `openrc-aircraft v2` object. The packed `openrc-aircraft-v2.schema.json` SHA-256 exactly matches the current live file (`1141f9683492ee99feb991c6ab44a37b899eecc6cc02d11d86982359db7b64d9`). See [pack-probe.log](pack-probe.log) and [pack-schema-hash.log](pack-schema-hash.log). The manual export emitted the expected build-info warning because `OPENRC_BUILD_*` variables were unset; the command exited successfully and no engine error was logged. Godot documents the pack-only export and PCK mounting APIs in its [export guide](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html) and [PCK guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html).

## Source snapshot

[inputs-before.json](inputs-before.json) and [inputs-after.json](inputs-after.json) hash 1,031 files across `app/` and `assets/aircraft/` (excluding `.godot`) and the pinned Godot executable/archive. No files were added or removed. One file hash changed during the run: `app/data/schema/openrc-aircraft-v2.schema.json` changed from `13499359411506bf781031e5bf335e39a2ab219e41ede31fb03c8cd86640710f` to `1141f9683492ee99feb991c6ab44a37b899eecc6cc02d11d86982359db7b64d9`. Its working-tree timestamp is 5:13:50 PM, before the pack export at 5:15:08 PM; the PCK probe confirms the pack contains that current file exactly. No other app or aircraft-asset source hashes changed in the window. This audit did not modify application source.

These checks do not replace the full `app/test.sh` suite or release-platform smoke tests.
