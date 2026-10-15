# DT-11a — reuse projected-shadow framing

2026-10-15. CPU presentation refinement of VQ-04a projected shadows.

`refresh()` now reuses the previous framing rectangle when the model bounds,
basis, light direction and height-derived blur are exactly unchanged. It reuses
the existing mask signature and adds only an AABB and a float; there is no growing
cache, retained geometry or new GPU resource. Translation, opacity, visibility and
receiver placement still update normally. Hidden shadows clear the signature as
before, so revealing them still schedules the required mask redraw.

When framing changes, the projection slope is calculated once for all eight box
corners. Each corner retains the original multiplication/subtraction order and
the same rectangle expansion sequence.

## Paired native measurement

Godot 4.7.2 `ed1daf0bf`, Windows, Compatibility/OpenGL, RTX 3090, Dummy audio.
Five fresh processes run six alternating reference/candidate pairs per workload,
reversing the starting order between processes. A sample performs 4,000 refreshes;
moving workloads include the same pose/light assignment in both variants. Setup,
state snapshots and teardown are outside the timers. Pair zero remains in raw
data; the following medians pool 25 warm samples per variant/workload.

| Workload | Reference, µs/update | Candidate, µs/update | Reduction |
| --- | ---: | ---: | ---: |
| Unchanged pose and light | 7.100 | 3.587 | 49.5% |
| Translation only | 6.818 | 3.783 | 44.5% |
| Changing orientation | 8.732 | 6.658 | 23.7% |
| Changing light direction | 7.661 | 6.132 | 20.0% |

All five process medians improve for every workload. [Summary](summary.json) and
[manifest](manifest.json) retain results, commands and source identities. Host
activity is uncontrolled. This saves roughly 1.5–3.5 µs in a single shadow update;
it does not establish whole-game FPS, GPU render-time or loading improvements.
The timing fixture uses a small box; the refresh arithmetic depends on bounds,
not the source model's triangle count. Fleet geometry is covered by integration.

The [initial candidate](initial/manifest.json) kept a separate framing helper and
duplicated its cache key. Its pooled medians improved stable cases but regressed
changing orientation/light by about 8–9%; it was rejected before integration.
The final implementation reuses the existing signature and removes repeated
slope calculations. Initial and final campaigns are separate host-load samples.

## Verification

All **5,250 native state pairs** match byte for byte: each process checks 1,024
transition steps, hide/reveal after a consumed redraw request, 24 timed-block
endpoints and source destruction. The transition tape is repeated across five
processes, not 5,250 unique scenarios. Snapshots include receiver transform and
visibility, opacity/blur, all mask uniforms, request/signature state and viewport
update mode. Bounds, orientation, low-angle light, blur, parent/source visibility
and opacity change independently across the sequence.

A separate [4,096-case check](framing-parity.json) preserves exact standalone
framing results for randomized boxes, reflected/nonuniform bases, the horizon
clamp, degenerate bounds and non-finite inputs. This checks arithmetic equivalence;
it does not claim that non-finite inputs are valid rendered-flight data.

Six permanent regression checks cover translation with opacity changes, all four
framing-key invalidations and height changes beyond the blur cap. The existing
fleet and lifecycle tests continue to run. A stale test reference to the removed
`AirplaneBuilder.AVANTI_ID` constant was replaced with the unchanged catalog ID
`sebart-avanti-s-a200-p100rx`; the initial parse failure is retained. Production
builder APIs and the selected five-family test coverage are unchanged.

| Integration suite | Result |
| --- | --- |
| Projected shadows, headless | 43 checks; clean exit |
| Projected shadows, native | 43 checks; clean exit |
| Home preview cache, headless | 18 checks; clean exit |

[Checks and commands](checks.json) retain the logs. Runtime, benchmark and test
drafts were parsed outside `app/` before integration. These results do not close
the previously recorded helicopter texture or intermittent Home audio shutdown
issues. Full CI, exports, pixel captures and pilot acceptance were not run here.

## Reproduce

```powershell
python research/visual-quality/shadow-framing/run.py --godot .tools/Godot_v4.7.2-stable_win64.exe --out tmp/shadow-framing-reproduction
```

Use a fresh output directory. The runner expands the frozen reference and compares
the current runtime, or a parsed draft selected with `--candidate`. Frozen runtime
and test sources, diffs and an evidence manifest identify the accepted change.
`framing_parity.gd` accepts `--reference`, `--candidate` and `--out` after Godot's
`--` separator for the standalone formula check.

Primary source consulted 2026-10-15: [Godot SubViewport update modes](https://docs.godotengine.org/en/stable/classes/class_subviewport.html#enum-subviewport-updatemode).
`UPDATE_ONCE` returns to disabled after rendering. The implementation preserves
that scheduling contract; it skips CPU framing work rather than redraw requests.
