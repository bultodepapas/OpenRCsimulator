# DT-MAC-04n4: Apple Silicon source-default evidence

**Date:** 2026-11-13 UTC. **Status:** qualification in progress; no source-default marker has been adopted. Public distribution remains deferred. The [implementation plan](../../../../APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md) owns the outstanding gates. This ledger is a snapshot, not a promotion decision.

The measurements below used the Apple M1 MacBookAir10,1 with macOS 27.0.1 build `26A434` and the official native ARM64 Godot `4.8.beta2.official.cafc17a19`, SHA-256 `2051c48febe532a5b156ffd8dd0c9381f74e40fde9177faff07a713851baba80`. The task workspace is `/Users/gius/OpenRC-m1-work/macos-native-default-20261113T125500Z`; raw M1 evidence paths below are relative to it. The local source HEAD at this snapshot was `ba95b2329a11dd7733b25dbcffd8db7bd0cfe04e`; individual receipts bind their own collection inputs.

## B3 domain-guard trial

The B3 trial retains live packed Variants and compares them with detached byte snapshots. Its tested dylib SHA-256 is `3eb18f46b35f89ac0f6589701fd7073220fdd4d6073a43702f552353233f35c6`; its native-source SHA-256 is `b9f499fbdba33c5a2380262093d4dac07499546ac4f3a4b1a8e158fe378fdad1`. On the stock context, preparation recorded 6,092 scenery proxies, 154,131 visited nodes, 1,078 packed leaves and 76,816 packed bytes. The M1 trial reported 72 passing mutation controls, including the tested packed aliases and resize cases. These controls exercise the guard, not the complete application or every possible mutation.

Five quiet, alternating microbenchmark pairs measured the isolated guard. Values are per-pair mean microseconds; the retained summary is `evidence/guard-ab03/summary.json` in the task workspace.

| Pair | Baseline µs | B3 µs |
| --- | ---: | ---: |
| 1 | 89.5733 | 19.205 |
| 2 | 89.7142 | 19.25333 |
| 3 | 89.83375 | 19.14417 |
| 4 | 90.42542 | 19.31125 |
| 5 | 89.59417 | 19.275 |

These numbers describe isolated guard cost on this host and context. They do not establish complete-session speedup, frame pacing, sustained performance or qualification of B3. An earlier B1 candidate passed its 17 numerical oracles, negative FPCR control, focused consumers and sanitizer checks; B1 is superseded, so those results are not B3 qualification. The [earlier implementation assessment](../DT-MAC-04n1/README.md) retains separate source10 and diagnostic-host limitations.

## Companion route

The [solver rebind receipt](../../ai-companions/AFC-02/rebinds/2026-11-13-192efadc-to-f60ac8ed.json) records identical CSV bytes for nine retained reference tapes using solver SHA-256 `f60ac8ed1339556c996e395a6167da3e502d56376310c44c7b3a13f56e8f2867`. This is bounded tape parity, not exact replay or physical validation.

The [behavior receipt](../../ai-companions/AFC-02/rebinds/2026-11-13-main-macos-route-behavior.json) records 16 completed checked import, stale-input, companion and Home tests. Its observed companion-enabled flight retained the reference backend, with three active, airborne companions and no reported companion faults or crashes. The observed player tick advanced from 47 to 60 without a flight fault; the owned debug session stopped gracefully with zero reported leaked objects. This is a short admission observation, not sustained flight or evidence of native companion acceleration.

## Pending

- Exact B3 numerical, negative-control, consumer, lifecycle and replay qualification on the final bound inputs; earlier candidate results do not substitute for it.
- Current-candidate fixed-wing fleet, production-trim callback comparisons and sustained rendered trials, including the specified per-role repetitions and 1080p-first display evidence. Failures and unsupported rows remain open.
- Stable-candidate cross-platform checks and truthful native Mac CI, plus source-default marker creation and validation only after its required evidence is complete.
- Final signed package, distribution, quarantine, compatibility and recovery qualification. Source-editor evidence does not qualify a distributed package.
