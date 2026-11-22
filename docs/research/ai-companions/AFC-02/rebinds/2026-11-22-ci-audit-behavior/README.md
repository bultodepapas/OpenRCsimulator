# Companion behavior renewal for the November 22 Club scenery changes

The previously accepted Stik profile refused admission after upstream changed `app_root.gd` and `scenery/collision_world.gd`. This renewal covers ordinary Home-to-Fly admission for one, two and three airborne Jensen Das Ugly Stik 60 companions at the Club field. The tested change updates the two source hashes in the behavior manifest and its digest in the aircraft profile. The solver pin stays at its previously accepted value. [Audit source](https://github.com/bultodepapas/OpenRCsimulator/commit/847d8d1a26b885124f6b634ee9badfe6684bef13) · [Upstream source](https://github.com/bultodepapas/OpenRCsimulator/commit/843f357c07af842054f3ccd6728f93beca9a57ef) · [Exact file identities](candidate-identities.json)

## Acceptance evidence

The final receipt covers **23 checked processes**. Twenty-two exited successfully. One deliberately ran normal admission with the stale manifest and exited 1 after identifying both changed files. All 23 matched their expected exits and required output markers. The numbers below count assertions within individual processes. [Complete receipt](bounded-checks.json) · [Exact drivers, engine logs and checked reports](external-harness-and-logs.tar.gz)

| Exercise | Observed result |
| --- | --- |
| Stale profile controls | Normal admission stopped after 7 checks with the two expected failures in 7.628956 s. The explicit refusal test passed 8/8 in 7.468117 s. |
| Renewed profile | Behavior and mutation checks passed 39/39 in 8.140680 s. Strict profile checks passed 95/95. |
| Club collision geometry | Trajectory checks passed 40/40, including both 35 m circuit samplings. The oracle found 58 intersections with zero omissions. Gate collision and destruction passed 117/117. |
| Occupied airspace | Airspace checks passed 49/49. The current world contained 7,295 proxies, including 72 protected proxies. The measured minimum vertical gap after allowances was 28.2949 m. |
| Home and lifecycle | Three fresh launches reached 240 accepted ticks with every requested companion active and airborne and zero faults or crashes. The requested counts were one, two and three. A separate three-pilot launch paused and restarted with two. Lifecycle checks passed 653/653 across 50 headless and 10 visual/audio node rebuild cycles. |

Every fresh Home launch observed the solver override disabled before and after flight and verified the accepted digest over 203 source files. The airspace receipt records the Club geometry and collision-world identities. [Solver guard review](solver-guard-review.json) · [Current Club airspace](current-club-airspace-closed.json)

## Source and limits

The isolated project contained all 6,015 tracked app files and 27 repository-relative aircraft authoring records required by the editor. Git checkout rules converted 29 files to CRLF. Postflight verification found only the two tested JSON files differed from the source checkout. The archive also preserves the external diagnostic fixture, strict drivers, derivation record and raw process reports. [App file inventory](source-inventory.json.gz) · [Checkout rules](checkout-attribute-verification.json) · [External source inventory](external-source-inventory.json) · [Engine and driver identities](harness-identities.json)

The runs used official Godot `4.8.beta2.official.cafc17a19` on headless Linux x86_64 with the GDScript reference backend. The checked runner recorded zero engine errors. Cold import emitted eight OBJ ambient-material warnings from the wheat, corn and reed assets. Runtime emitted nine warnings about selecting the reference backend. GPU rendering, native-backend performance, packaged exports and physical flight require separate evidence.

Three setup attempts are excluded from the 23 processes and their timings. Raw Git blobs produced incorrect worktree line endings. An early Home launch timed out when two external aircraft records were absent. An airspace repeat refused to overwrite existing output. The accepted controls used effective checkout bytes, the complete authoring set for Home and a fresh airspace output path. [Prior renewal procedure](../../../AFC-02-R6/README.md) · [Earlier Main and collision renewal](../2026-11-09-b0a074e4-to-a4ee8de9-behavior.json) · [Earlier behavior controls](../2026-11-15-temporal-cut-behavior.json)
