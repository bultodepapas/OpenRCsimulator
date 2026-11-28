# Native kernel work and qualification

The [project roadmap](../../ROADMAP.md) sets priority. NK owns the aircraft C++ kernel, its GDScript adapters and their qualification. Simulation, configuration, audio and rendering owners review changes at their boundaries. The [backend policy](../STACK.md#native-backend-policy) defines runtime ownership. The [native guide](../../research/native-kernel/README.md) owns build commands, supported routes and receipts.

## Remaining work

| ID | Work and dependency | Evidence to finish |
| --- | --- | --- |
| NK-9c | Verify the current native paths in ordinary muted Corsair, glow Stik and P-51 flights on the owner's workstation at 1920×1080. | Record the actual backend, per-frame timings and positive counts for each exercised path. Check `native_audio_row_answers`, `native_approach_answers` and the glow voice's `native_render_answers` on the matching aircraft/conditions. |
| NK-6x | Prepare contact mode bits and the lake threshold once from the stage's admitted configuration. | Compare mode bits and threshold at their boundaries. Change the configuration and verify that the stale answer is refused. Measure complete ticks. |
| NK-6y | Prepare the immutable parts of glow finish terms and the substep preview base. Build liquid tick-context arguments from the admitted aircraft and current deflections. | Compare liquid and glow ticks through resource events and refusal paths. Time the affected aircraft separately. |
| NK-7n | Read the mechanical snapshot, airborne clearance, endpoint air and shaft torques in one call for the same published frame. | Compare the entire audio consumer output with the hook enabled and disabled, including a stale or unavailable endpoint. Measure the live frame. |
| NK-7o | Build the glow voice pump's detached telemetry from the admitted glow keys. | Compare hand-over and rendered PCM with the reference. Exercise a running voice and measure hand-over cost per frame separately from worker cost per block. |
| Guard roots | With the configuration owners, freeze additional roots that cannot change during an accepted flight. Replace property watches only where identity proves the same configuration. | Mutation and alias tests must reject a changed root before use. Measure guard cost on a production tick. |

The [November 28 Windows profile](https://github.com/bultodepapas/OpenRCsimulator/blob/8d4169f8febfd7d78a028eaa817414217a54f24b/docs/plans/native-kernel-roadmap.md#what-remains) preserves the original headless measurements used to select these batches. Live work includes observers and presentation. Existing Windows measurements cover the [substep count](../research/native-kernel/NK-6u/README.md), [clear-contact step](../research/native-kernel/NK-6v/README.md) and [shadow terrain sampling](../research/native-kernel/NK-8b/README.md) on their recorded workloads.

## Qualification

- Keep a switch back to the reference implementation for each new native answer. Compare the whole consumer output, include a mutation that the comparison detects, and check malformed inputs and refusal boundaries. The stage oracle covers at least 10,000 states. Check exact trajectories, accepted tick counts, actual native calls and checkpoint/fault/restore behavior. [Installer and trajectory gates](../../research/native-kernel/README.md#verification-and-local-installation)
- Rebuild the candidate, run affected suites and the platform's installer gates, and verify the actual install in both the qualification tree and the working app. Bind engine, toolchain, ABI, source/data and library to the receipt. Repeat the applicable release checks against the actual packaged executable. [Native CI](../../.github/workflows/ci.yml) · [Package verification](../../research/native-kernel/README.md#linux-release-packages)
- Record matched live timings and counters on the intended host. Keep per-tick, per-frame and per-audio-block results separate. Compare the same workload, output dimensions and observer configuration. [Measurement rules](../learnings/physics.md#measure-the-complete-workload) · [Published endpoint rules](../learnings/physics.md#native-answers-for-published-endpoints)

## Platform evidence still needed

Linux/WSL passed the nineteen installer gates at `d080ca630`. The individual NK-7 parity runs and current-candidate Linux NK-6/7/8 coverage still need recorded results. Apple Silicon needs corresponding batch parity on its admitted ARM64 route. Check NK-9a/b consumer parity on both platforms as well. Retain CI results for the specific candidate, and qualify any claimed package independently. [Linux gate record](https://github.com/bultodepapas/OpenRCsimulator/blob/8d4169f8febfd7d78a028eaa817414217a54f24b/docs/plans/native-kernel-roadmap.md#evidence-gaps) · [NK-7m scope](../research/native-kernel/NK-7m/README.md#scope) · [NK-9b scope](../research/native-kernel/NK-9b/README.md#scope) · [Mac source workflow](../../.github/workflows/native-macos.yml)
