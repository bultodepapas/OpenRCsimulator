# Live application smoke inspection

Baseline: `cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b`, pinned Godot 4.8-beta2, headless and muted. The repository debug bridge supplied keyboard/UI actions against the real application and an isolated test profile. [ui-observations.json](ui-observations.json) is the portable observation record; raw logs and host-specific metadata are excluded from publication.

| Action | Observed result |
| --- | --- |
| Home → Vehicles → ION R5 → FLY | Real multirotor activity opens paused with its menu. The bridge calls this generic activity slot `ground_vehicle`. |
| Course button | Practice oval 1 changes to Tower sprint, ID `openrc-tower-sprint-1`. |
| OSD settings → cycle Freestyle → close | Full layout becomes active. |
| Resume → E → G | Countdown advances to RACING. Captured state: tick 63,773, empty fault. The quad stayed on/near its pad; this was not a complete manual race. |
| G to cancel | ABORTED, zero pending results, empty fault. The activity writes the cancelled result with `saved=true`, reason code 9 and terminal tick 63,791, and writes its record book. |
| R → Escape | Pad reset and paused menu remain available, with Tower sprint selected. |
| Back to Home | Final route is Home; no engine-error records. |
| Stop | Clean stop, not forced; no crash and zero reported leaked objects. |

UI references came from fresh `look` results or visible labels. Read-only expression evaluation observed phase, course, layout, tick, pending count and fault; it did not manufacture a finish or bypass the race handlers. The bridge log contained no error/script-error/shader-error records. Headless hitches were not interpreted as a valid hardware performance benchmark.

A rendered launch could not start because this environment lacked a display and Xvfb. No screenshot, GPU quality, actual display layout, native latency or physical controller acceptance was established. An earlier Home launch failed because sparse-checkout authoring files were missing; tracked sources were restored before this clean flow and the final passing activity suite.

Complete three-lap scripted flight and exact race replay are separate passing suites in the [test matrix](test-matrix.md). This UI smoke does not qualify physical realism.
