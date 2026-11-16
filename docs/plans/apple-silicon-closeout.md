# Apple Silicon closeout

Date: 2026-11-16. Owner: lead developer. Status: implementing the owner's native-default decision.

## Decision and scope

Make native physics the normal macOS ARM64 Home/Quick Flight backend inside the
supported stock production domain. Preserve explicit reference selection and
fallback for incompatible configurations or failed library/package validation.
Performance promotion is separate: the previous screen found no material FPS/CPU
benefit and remains unchanged. Public Developer ID distribution stays deferred.

## Five steps to finish

| Step | Work | Acceptance |
| --- | --- | --- |
| 1 | Change the automatic policy and update its existing regressions. | Native needs no performance marker; stock, immutable-context, OS, source, library and package checks remain. |
| 2 | Freeze one source revision and run fresh M1 native qualification. | Current source-bound oracle, negative control, stage, lifecycle and replay results pass. |
| 3 | Export one ARM64 app using the existing Engine 26 pair. | Existing five package checks pass on that exact app. |
| 4 | Exercise normal source and packaged routes. | Native callbacks advance without a backend override; pause/restart/Home/reentry, exact replay and explicit reference work; incompatible routes fall back. |
| 5 | Run exact-head CI, update the Desktop app and record results. | Deliver the tested app location, source identity, checks and honest limits. |

## Progress

- [x] Policy and marker-independent regressions implemented; nine host controls pass.
- [ ] Fresh M1 qualification for `72d70596b73b92d97456743aeac5d908d5e65074`.
- [ ] R9 package and its five checks.
- [ ] Source default/replay and audio-enabled packaged Home routes.
- [ ] Final CI status, Desktop app and evidence.

No new engine, rendering feature, benchmark framework or sustained-performance
campaign belongs to this closeout. Earlier interrupted attempts remain historical,
never qualifying evidence. The [canonical evidence](../research/desktop-delivery-investigations/DT-MAC-11a/README.md#2026-11-16-native-cpu-closeout-on-angel)
retains the prior package and measured comparison. The [decision](../DECISIONS.md#default-to-native-physics-on-supported-apple-silicon-flights)
owns the new product policy. The four-feature [MetalFX plan](apple-metalfx.md)
remains separate and incomplete.
