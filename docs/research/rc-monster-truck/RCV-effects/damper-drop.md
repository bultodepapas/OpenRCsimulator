# RCV damper evidence: visual shocks and supported drop

**Date:** 2026-10-14. **Status:** bounded software evidence complete; damper calibration and physical landing qualification remain open. **Scope:** MT8 shock articulation checks, a neutral 0.45 m drop, and coefficient sensitivity runs. This record does not change the production damper model.

## Finding

The four shock assemblies (eight visible body/shaft pieces) close to their authored endpoints through the tested suspension poses. The full-vehicle drop is repeatable across the reference and native backends, and the candidate coefficient changes produce measurable differences. Those differences do not identify a better physical law: the spring, damper, and bump-stop coefficients in the vehicle data are engineering estimates, not measurements. Keep the existing passive baseline pending identified hardware and measured damper data.

The visual check recorded **46 checks, 0 failures** over 27 common and crossed travel/steering poses. Maximum shock-eye endpoint error was **1.68e-8 m** and maximum body/shaft axis mismatch was **1.17e-7**. Shaft tips stayed within the bodies, spring scales remained positive, and declared bump/droop/rest lengths matched their endpoints. These are geometry and transform checks; they do not measure damper force, prove loaded clearance, or establish physical suspension behavior. The [RCV-14a intake report](../RCV-14a/README.md) retains the wider asset identity and capture context.

## Supported-drop results

The probe raised the accepted practice-course start by **0.45 m**, applied neutral controls, and ran **480 ticks at 240 Hz**. First wheel contact occurred at tick 75 (**0.3125 s**); each profile exported 481 samples. The baseline reached **52.270 mm** maximum travel against the model's **50 mm** bump limit, with a **130.690 N** peak individual tire normal load.

| Profile | Maximum travel | Change from baseline | Peak individual tire normal load | Change from baseline |
| --- | ---: | ---: | ---: | ---: |
| Symmetric baseline | 52.270 mm | — | 130.690 N | — |
| Compression-biased (1.2 / 0.8) | 50.996 mm | −1.275 mm | 140.626 N | +7.6% |
| Rebound-biased (0.8 / 1.2) | 54.070 mm | +1.800 mm | 118.873 N | −9.0% |
| Progressive bump, 10 mm ramp | 52.007 mm | −0.263 mm | 130.690 N | unchanged |

The progressive profile raised the probe's peak suspension-plus-stop force from **117.296 N** to **138.402 N** (**+18.0%**) without reducing peak tire load. That tradeoff is a modeled result, not evidence that the physical shock needs a progressive law.

The baseline's pre-contact center-of-mass trajectory agreed with ballistic free fall to **3.33e-16 m** maximum height error and **1.78e-15 m/s** maximum vertical-speed error over 75 airborne samples. This verifies the software's free-flight segment only. In the separate supported-jump capture, airtime was **45.8 ms** (11 ticks), below the [80 ms lesson reward gate](../../../../app/vehicles/ground/ground_scene.gd#L696); the event ended as `upright_short_landing`, so it is not a scored jump or a damper-landing qualification.

## Method and limits

The run compared the existing symmetric law with compression-biased, rebound-biased, and 10 mm progressive-bump variants. The research wrapper selected normalized damping coefficients between public `Vehicle.step` calls. Directional variants choose one coefficient from the **mean of all four travel rates**, then hold it through that call's RK stages. They therefore do not implement a per-corner, state-dependent law at every RK stage and are sensitivity probes, not production candidates.

The reference and native backends produced **1,924 compared states** across the four profiles with **zero maximum state difference** (acceptance tolerance 2e-6). Reported force and travel peaks are public-tick samples, not internal RK-stage maxima. This establishes backend parity for this run, not physical accuracy. The fitted vehicle and synthetic practice course remain estimates; RCV-11 dynamic suspension, RCV-22 jump/landing lessons, and RCV-26/27 measurement and held-out validation gates remain open in the [active RCV plan](../../../plans/rc-monster-truck.md).

## Primary records and identities

The run used Godot **4.7.2 stable**, solver `openrc-ground-vehicle-dynamics-rk4-v3`, vehicle `mt8-bisonte-electric-4wd-estimate-v1`, and course `mt8-practice-course-estimate-v1`. Vehicle SHA-256 is `425f2a3fe810f82d609ad2b9dd9618b9fb45bcd813df57873cd8bc8759a750a5`; course SHA-256 is `55fd8cac65a004308a618d50a3034677d09d32b093768008e1b42f9716a290f5`. The MT8 travel limits are derived from the author-provided spec (SHA-256 `8d9a2ba3b41400fa934376ede5b110fcc046a05819b3f251076ea90e3fb2b5ef`). The model marks suspension damping **45 N·s/m**, bump-stop damping **80 N·s/m**, suspension stiffness **900 N/m**, and bump-stop stiffness **8,000 N/m** as engineering estimates; no external manufacturer damper curve or measured RC shock data was used.

| Primary source | SHA-256 |
| --- | --- |
| [Drop probe source](../../../../research/rc-monster-truck/dampers/run_drop_probe.gd) | `3d3e3d98c71b370e3b2f52f222e9d943ffd165d40a53021fb5c80040ef445ed0` |
| [Vehicle data](../../../../app/data/vehicles/ground/mt8_bisonte.json) | `425f2a3fe810f82d609ad2b9dd9618b9fb45bcd813df57873cd8bc8759a750a5` |
| [Vehicle data loader](../../../../app/physics/ground_vehicle/vehicle_data.gd) | `dd3207504fc26b70f75aaf8755e3520b1efd441ad7d207e9972db97c27494b37` |
| [Practice course](../../../../app/data/ground_vehicle/practice.json) | `55fd8cac65a004308a618d50a3034677d09d32b093768008e1b42f9716a290f5` |
| [Course sampler](../../../../app/physics/ground_vehicle/course.gd) | `313b43fe7e4816c54d4647c21644a2337640e1510536dcaaa95794f884bf0ca6` |
| [GDScript vehicle dynamics](../../../../app/physics/ground_vehicle/vehicle_dynamics.gd) | `957b3398d114ae57c71c455c1f1054f9b4646a793712d6e9f719aeef5d6a1a22` |
| [Native ground-vehicle kernel](../../../../research/rc-monster-truck/native/src/ground_vehicle_kernel.hpp) | `240575536d4016f8106157475ff025a779d7bd87002db18e0dbd4362b236b3ad` |
| [Native extension](../../../../research/rc-monster-truck/native/src/ground_vehicle_native.cpp) | `ae71bf3285094c96e9a4c47825d404d8df026f6bda3e005d9d24811fce8c577f` |
| [Visual articulation test](../../../../research/rc-monster-truck/visual/test_mt8_visual.gd) | `4fdc9d06f6d87a90f18a1a3ace8c1035db7e950ae399f87d6445ad98d4edbabb` |

The native backend identity in the probe is binary SHA-256 `adafd1f9682dff147e538fdb7686329c009edf255c639789ac28dc403bc6e65c`, source SHA-256 `e2ae0a5ffebc8d81636302d66238348035ee92bf51d2f40965db7053bb251541`, and toolchain SHA-256 `78bdd21d315683b45eee37c24b84716430cdba2a9b24066f59a68df476585b4d`.

## Retained outputs

| Retained output | SHA-256 |
| --- | --- |
| [damper-drop-probe.json](damper-audit/damper-drop-probe.json) | `6778834992205efc2f2c9cc880c568fbaa514d1de36c9f13816dbd9db61814b8` |
| [damper-drop-probe.csv.gz](damper-audit/damper-drop-probe.csv.gz) | `6b22a356970ef4a6beee956235afb097066827dac0e1ca9f681ed0fc79b19216` |
| [damper-supported-drop-analysis.json](damper-audit/damper-supported-drop-analysis.json) | `65d07554414edbb486469bea0313091b985cc4bd477a80fedc9df4f1b522b555` |
| [damper-supported-drop-baseline.json](damper-audit/damper-supported-drop-baseline.json) | `8a047c55d45a9a38d185dc25e896b88b87ae9433092815f308d0a7d74a54d6f1` |
| [damper-supported-drop-baseline.csv.gz](damper-audit/damper-supported-drop-baseline.csv.gz) | `37a69f7e891aaf1c4b14540058c29a246ac9721e6042fef5739110c430eab8cb` |
| [damper-supported-jump-landing.json](damper-audit/damper-supported-jump-landing.json) | `0cb5f3a9839f5881bd4e6bb6e217b0f1a028e25d4bbf1064d6e1068c920dc9b0` |
| [damper-visual-shocks.log](damper-audit/damper-visual-shocks.log) | `7d95f4565d86edc9402f728895aae302d5f0e31c0edaa50f785fe538e2c21389` |
| [damper-drop-probe.log](damper-audit/damper-drop-probe.log) | `04d9e984351d3ae29868c77550a156de755b1efb30d6b67a1fd8e7e3b2789b79` |
| [damper-supported-drop.log](damper-audit/damper-supported-drop.log) | `6bc63721d9516658af04909c5f9a49299d1ad302c2256c9bea356e32cd17ab56` |
| [damper-jump-landing.log](damper-audit/damper-jump-landing.log) | `e0314e442ea987e075a84fc3436e309c188e0470d601029d5e86856f52ab104d` |
| [retained-csv.json](damper-audit/retained-csv.json) | `2ef3a8ff290d7ef948656a44825278d2bec95465bab7b2abfbff11980ddfb1f6` |
