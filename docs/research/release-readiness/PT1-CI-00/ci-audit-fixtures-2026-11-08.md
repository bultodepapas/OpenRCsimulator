# PT1-CI-00: source-bound fixture reconciliation

2026-11-08. The historical checkpoints and the original fleet and glow identities remain recorded. The publication tests now compare every complete typed checkpoint and the separate event tape after two explicitly checked identity substitutions. This is a bounded software-preservation result, not aircraft validation.

The [compressed evidence](ci-audit-fixtures-2026-11-08.json.gz) (SHA-256 `c6bfd8964c9cb52b5304ef4aed7de3912db6e3730df843ff2dddfbf011b4abe1`) contains 48 raw UTF-8 captures with their original hashes, 59 checked reports and exact log bytes, and nine observer/comparison recipes. Its `captures` entries contain `raw_utf8`; `checks` contain `report_raw_utf8` and base64 log bytes. Their individual hashes were verified after decompression.

## Source and engine identity

The pre-law source is `8ebb252acc341a5a1fc047e6bb931fabdb17b148`; the changed-law base is `75299d6869f0b80f955574ddda8ba95f4b4915f4`. The final tested fixed-wing overlay adds `sim/flight_session.gd` LF-normalized SHA-256 `9b93be96e64e7c8ff425a177fb1590c9032d1de6b2bd6f536fb6a7d836a098cc` and `sim/electric_contact_step.gd` `ef6bf63bd3babd77e44b11deb4e06070885bbdc6c3a7a3913b8e315955213b76`, matching commit `84a0d98d1e1ffaae4950532e653390f5a9abe590`. This is the named base plus those two files, not a claim to have tested every other change in that commit. The 18 listed source/data pins in the [fixture](../../../../app/tests/fixtures/publication_fixture_bridge.json) matched the shared tree after the checks. Script hashes canonicalize CRLF to LF only; aircraft, fuel and wheel-profile data use exact bytes.

The original Windows traces were captured with official Godot `4.8.beta1.official.4d10419ca` and the CRLF fuel registry (`cae59374…`). The current engine is official `4.8.beta2.official.cafc17a19`; the registry pinned for current checkouts is LF (`6f4908ba…`). The fixed-brake engine verifier checked the executable SHA-512 values on Windows and Linux. A disposable Git `checkout-index` test using the repository attributes passed all 18 source pins and the normalized fixture SHA with `core.autocrlf=false` and `true`; this is a targeted checkout test, not a full fresh-clone or release qualification.

## Historical and current observations

- On Windows beta1 with the historical CRLF registry, both original shaft hashes and all four pre-rebinding weather hashes reproduced. At identical source and data, beta1 and beta2 gave byte-and-type-identical complete values at all 150 endpoints. With beta2 fixed, CRLF-to-LF changed the checkpoint configuration and the fuel-registry identity in the model, without changing the other captured fields. The later weather LF rebind is preserved separately.
- On both Windows and Linux beta2/LF, the pre-change and `75299d686` source captures contain 50 shaft and 100 weather checkpoints each. All fields except `configuration` and `aero_loads_law` are byte-identical. The separate 25-sample event tapes are also byte-identical, but **all recorded event arrays are empty**; this does not test event-producing maneuvers.
- `configuration` is an opaque hash. A disposable exact-once observer captured the actual typed hash inputs for six publication cases and eight Linux fleet cases. Repeating the checkpoint/event and fleet-proof captures with the observer preserved their bytes. The checked 60-assertion comparison found only the v2-to-v3 aero declaration, the coefficient-law insertion for non-turbines, and the Stik model data identity change. The original and derived typed arrays and observer recipe are retained in the evidence.
- The changed aero equation multiplies the flap lift-offset couple by the local forward-flow fraction; the propeller table continuation uses a floor no greater than its last authored value. These changes were introduced in `174abfd02`. No numerical difference was observed in these short fixtures; that does not establish equivalence outside them. Each of the Stik, 61FX and FS64V JSON files changed exactly three `source` strings from wake-law v2 to v3; their other typed JSON values were unchanged.
- On Linux, all eight pre-change runway reset proofs reproduced their original frame, setup, refusal and live-configuration pins. The old/current typed comparison found only the embedded checkpoint-configuration identity changed. Current v3 live-configuration pins are separate from the retained originals. A same-source Windows baseline failed the existing platform-specific fleet pins in 16 assertions, so those Linux pins are not claimed to qualify Windows.
- The historical FS64V aircraft byte hash `c42f72ac…` is retained beside current `47c09726…`. On both hosts the fixed historical 2T/4T trials, source-off and moving controls, refusal detail, and all numerical payload values matched; only aircraft/model data identities changed. The real 805-tick native tape and current native diagnostic remain unqualified.

The final overlay comparison found identical full checkpoint, event and configuration captures for both hosts, identical fixed-trial glow payloads, and identical Linux fleet rows, reasons and proof fields. The fleet policy's `original_pin_matches` flag intentionally changed from false to true after its v3 pin update; it is not part of that equality claim.

## Checks and remaining gate

| Check on the named overlay | Result |
| --- | --- |
| Shaft publication, Windows and Linux | 214/214 each |
| Weather publication, Windows and Linux | 313/313 each |
| Linux fleet policy | 535/535; verified-native branches skipped |
| Typed configuration inputs | 60/60 across 14 cases |
| Disposable electric helper source mutation | Rejected: 154 checks, one expected fixture-identity failure |
| Four capture/comparison existing-output controls; optimized Python packer | Rejected as intended; the existing output was unchanged |
| Current Linux glow diagnostic with the existing installed library | Reference fixture passed for both families; 14 checks, two failures at native receipt verification |

The installed library's receipt cites an older `app/data/aircraft/f4u_corsair_250.json`. Its native diagnostic cannot run until the normal NK-3 producer rebuilds and qualifies a library and receipt against the final source. At inspection the locked GCC, SCons and godot-cpp cache were present, but D: had approximately 5.5 GiB available and the official builder requires at least 6 GiB. Its installation gate also requires the fresh family oracles, trajectory and mutant control. No receipt or space guard was bypassed. Native paired runtime-domain refusals, downstream export and required CI on the integrated candidate remain pending.

## Reproduction inputs

The retained capture recipes are [shaft](../../../../tools/godot/audit_fixture_shaft_capture.gd), [weather](../../../../tools/godot/audit_fixture_weather_capture.gd), [fleet](../../../../tools/godot/audit_fixture_fleet_capture.gd), [typed comparison](../../../../tools/godot/audit_fixture_compare.gd), and the fail-closed [fixture packer](../../../../tools/godot/audit_fixture_pack.py). Run the two publication captures with the checked Godot runner, an imported isolated project, and `OPENRC_AUDIT_CAPTURE` naming a fresh output file. The fleet capture must be copied beside `fleet.gd` in a disposable native-kernel snapshot so its relative preload resolves. The packer requires `--capture-dir` and a fresh `--output`; it checks the observed difference boundary and the exact source pins before writing. The compressed evidence also contains the original one-off config observer and comparison scripts, along with the intentionally failed Windows baseline and stale-native receipts. **Those historical one-off scripts predate the output guards: run them only with fresh scratch paths.**
