# AV-17-R4 native fleet runway boundary

Verdict: the existing strict Avanti crosswind runway refusal was observed again with the corrected data, for ideal battery and soft-hull contacts on and off. For each setting, separate reference and native backend requests reached the same bounded reset refusal while retaining the reference owner; neither produced a flight or exercised native evaluation. The former pins rejected these observations. The current pins accept them without relaxing any proof predicate.

## Observation

On 2026-11-10 on Ubuntu WSL2, the checked runner executed [capture.gd](capture.gd), which selects the declared Avanti rows and calls the existing `fleet.gd` `_build_fleet_session` once for each backend request. [pre-observations.json](pre-observations.json) contains all four actual results, both before/after status records, typed bytes and digests. Its SHA-256 is `3ea187539c6f3e71ad4f5260eeba100840cc8fd02ccb37c223549c0f9482212f`. The [checked report](checks/avanti-boundary-pre-v709ixz3/report.json) passed, complete, with process exit 0 and no recognized engine errors; its [log](checks/avanti-boundary-pre-v709ixz3/engine.log) records both rows and the old-pin rejection. The log also reports the experimental wing polar's provenance and post-stall review notice.

Each request refused at reset with `idle support pose unresolved: bounded line search found no feasible descent step` and `numerical_unresolved`. Each retained reference callbacks, reference model and backend identity, frame, configuration, guards and selected inputs. The paired typed frame, setup, outcome and live-configuration bytes matched. The explicit native request remained reference-owned with `pending configuration requires reset`; this is pre-native evidence.

| SHA-256 | Both settings or soft-hull on | Soft-hull off |
| --- | --- | --- |
| Aircraft input | `77674df18312f6235352a28a797c497013ef18451a41eb0141e3f16dffd220b9` | Same |
| Frame | `0de0b838cd3db1f12fa815852333a9204b7f2d8a0bf77ab98c3acf457f652014` | Same |
| Outcome | `6daae9ec4959442f88cac3cb61b87cf9595c2d5ea699f41eecbade6e467f1d06` | Same |
| Setup | `538382d692b329fbf227c0f54fcbb239ff8667880dea650b2395add0a16cf2bc` | `847a2023caa0b2ba18bbb43178ca786643e25b094884d0df971fc6439300d565` |
| Live configuration | `608ea5ba0dec238cda690638be83e4ca6171de957bd62c55392cd4916e407e12` | `15f9d0f9f73c36a3653a542dbfac293d445ec5ab5ad615361f533c73e57d303d` |

The frame and outcome digests match the pre-update observations; the input, setup and live-configuration digests differ. Their previous values remain explicitly labeled as historical in both fleet consumers, and the original v3 and earlier live-configuration pins are preserved. No historic pin is accepted as the new input identity.

## Focused verification

- The existing `fleet.gd` `_fleet_case` was then run on both rows through the [checked runner](checks/fleet-case-62ze_s1h/report.json). Both emitted `reference-refused` with incomplete reference and native requests. [fleet-case-results.json](fleet-case-results.json) has SHA-256 `fa02e6ff1d6ad6f4cdc0c1ff8b285564a1dd0a93dc2b3db78a8967552a56159b`. The independent Python validator accepted both emitted rows and confirmed their paired proofs exactly match the earlier capture; see [fleet-case-consumer.log](fleet-case-consumer.log) and [validate-fleet-case.py](validate-fleet-case.py).
- The checked [captured-proof test](checks/captured-proof-carwmln7/report.json) passed the actual two pairs against the refreshed Godot validator, and rejected ten paired mutations covering the previous aircraft identity and coherently rehashed frame, setup, outcome and live-configuration payloads.
- [verify-campaign.py](verify-campaign.py) adapted the observed reset results into the campaign row envelope and passed both through the independent Python validator; ten equivalent mutations were rejected. [Result](verify-campaign.log).
- `test_fleet.gd` passed 586 checks, zero failed, via the [checked runner](checks/fleet-policy-5zqn0nad/report.json). Its verified-installed-library reset checks were skipped, as the verified app library was unavailable. Failure lines in the [log](checks/fleet-policy-5zqn0nad/engine.log) are intentionally exercised synthetic negatives.
- `python3 research/native-kernel/test_fleet_campaign.py`: 44 tests passed. [Log](fleet-campaign-tests.log). `git diff --check` passed for the two changed consumers.

## Identity and scope

The capture began at HEAD `3699b237a417413f3942736bbfa2bb229a2d6125`. A concurrent external commit advanced HEAD to `096f0574162408ba18b3440b6f833c4214346df8` before the verification; the fleet pins remain uncommitted. The 143 source, aircraft, harness and engine identities in [before-identities.json](before-identities.json) and [pre-after-identities.json](pre-after-identities.json) match exactly across capture. The corresponding [post-before](post-before-identities.json) and [post-after](post-after-identities.json) identities match across verification. Between those two intervals, only `fleet.gd` and `fleet_campaign.py` changed among these identities. The same 143 identities also match [before](final-identities.json) and [after](fleet-case-after-identities.json) the direct fleet-case check. The pinned Godot 4.8-beta2 Linux engine SHA-256 was `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`.

No backend was installed and no full fleet or native-flight qualification was run. The earlier separate liquid-stage oracle is recorded in `docs/research/avanti-realism/AV-17-R4/native/README.md`. These results do not establish physical validation or a physical runway limit.
