# Apple Silicon closeout

Date: 2026-11-16. Owner: lead developer. Status: native default delivered on M1;
aggregate CI remains in progress.

## Decision and scope

Native physics is the normal macOS ARM64 Home/Quick Flight backend within the
screened stock production domain. Preserve explicit reference selection and
fallback for incompatible configurations or failed native validation. The previous
screen found no material FPS/CPU benefit; its results remain unchanged. Public
Developer ID distribution stays deferred.

## Five steps

| Step | Work | Result |
| --- | --- | --- |
| 1 | Change automatic admission and its regressions. | Done: no performance marker required; stock, immutable-context, engine/OS/library/source/package guards remain. |
| 2 | Freeze runtime and run fresh M1 correctness checks. | Done: `1bb0434c`, 650 native checks, positive/negative oracles, FPCR/domain guards and 74 automatic-route checks passed. |
| 3 | Export the ARM64 app with the existing Engine 26 pair. | Done: R10 passed all five package checks and local signature verification. |
| 4 | Verify normal source and packaged routes. | Done: native callbacks, exact replay, reference/fallback, two audio-enabled Home/restart/reentry cycles; no forced backend or renderer. |
| 5 | Deliver, retain evidence and run final CI. | App and evidence delivered; final CI submitted. Aggregate result pending. |

## Delivery and remaining gate

- App: `/Users/g/Desktop/OpenRC Simulator M1.app`, a physical app with its
  adjacent verified receipts. The previous Desktop symlink was replaced.
- Runtime source: `1bb0434c1dff01f9a9ee8f8927f15ee95ef7cce7`.
- CI head: `c6e81947b105c6cd0b8797620ce1f3e8cb9a9e75`; only the CI workflow
  differs. Runtime, research and tool trees are identical. Package/source
  evidence retains its original runtime identity.
- Companion qualification was refreshed using nine identical retained tape pairs;
  all 18 real replays and 49 tool controls passed. The official-M1 profile test passed.
- [MetalFX controls passed](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43921529985).
  [Aggregate CI is running](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43921525209).
  Its completion remains the integration/release gate; no merge or public release was performed.

The [canonical evidence](../research/desktop-delivery-investigations/DT-MAC-11a/README.md#2026-11-16-owner-directed-native-default)
contains source/package/Home hashes and limitations. The [decision](../DECISIONS.md#default-to-native-physics-on-supported-apple-silicon-flights)
owns the product policy. The four-feature [MetalFX plan](apple-metalfx.md) remains
separate; no additional rendering feature or engine build was added here.
