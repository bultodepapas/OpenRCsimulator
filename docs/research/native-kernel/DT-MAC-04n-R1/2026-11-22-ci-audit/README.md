# macOS ARM64 stock collision world after the Club scenery changes

The required Mac source job rejected the collision world introduced on main at `843f357c`. It expected 6,139 collision proxies and found 7,295. The hosted ARM64 editor and the Linux portable geometry test agreed on the new count. Each platform computes its own full world identity because the hash includes trigonometric results. The macOS pin comes from the actual ARM64 diagnostic. [Original qualification and renewal procedure](../README.md) · [Apple Silicon plan](../../../../plans/apple-silicon-performance.md#dt-mac-04n-r1--keep-the-mac-native-default-after-world-changes)

| Evidence | Observed result |
| --- | --- |
| Hosted macOS ARM64, head `847d8d1a`, merge `22a1ae36` | On Apple's virtual M1 the guard passed 71 of 72 checks. The sole failed assertion checked the stock identity and count. Every one of 2,400 calls matched the frozen world. The process exited 1, so the subsequent install and no-flag launch did not run. |
| Linux x86_64, before renewal | The portable world test failed its two expected assertions for the count and geometry fingerprint. An independent check after regenerating the woodland recipe produced the same measurements. |
| Linux x86_64, source `c320d34d` | With the three renewed literals, the portable test passed all nine checks. It exercised a 2 mm proxy move, removal, part renaming and invalid non-finite coordinates. |

The Mac identity is `7e5fcff5098591708406da39142768107a594eac142b3862c2f684695876cc64`. The portable quantized fingerprint is `f020b4c86b7e98df77eacc2a35e2a95a3fc17a046e2cb9b5d719ac82abfd16a2`. The source-domain check still validates the current world, count and typed world bytes. The guard-call measurement is specific to that isolated loop. [Hosted Mac job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45079559400/job/137385028494) · [Source identities, artifact and diagnostics](domain-validation.json)

## Companion solver acceptance

Changing the domain pin alters the normalized identity of `app/sim`. The canonical rebind tool compared the committed source at `c320d34d` with the previously accepted solver from `70ee7e64`. Across nine retained tapes, the two sides produced byte-identical CSV outputs for all 25,929 rows. Each tape yielded 2,881 rows per side. The stored gzip and expanded ORFL identities matched the qualification record and both replay receipts. Only `app/sim/native_macos_domain.gd` changed in the solver source set. The tool then updated the solver identity in the companion profile and recorded the accepted revision. [Nine-tape receipt](../../../ai-companions/AFC-02/rebinds/2026-11-22-7e404f01-to-0954434e.json) · [Accepted solver and tape identities](../../../../../tools/companions/qualification.json)

The completed run used independently materialized app sources and project metadata. The two sides shared 1,433 immutable imported resource files to fit the local host. An ordered SHA-256 manifest of their paths and contents matched before and after the replays. The source validation record describes the exact archive and cache checks.

## Hosted acceptance

The updated macOS runner must pass the packed domain guard, install the new receipt and exercise native stage, lifecycle and replay. The final no-flag launch must emit `MACOS_DEFAULT_ROUTE verdict=pass` while the installed stage owns the flight. The first hosted Mac run exited before those operations. Physical-M1 performance, distribution and scene-budget acceptance have separate checks. [Mac CI runner](../../../../../research/native-kernel/ci_macos.py) · [No-flag route test](../../../../../research/native-kernel/test_macos_default.gd)
