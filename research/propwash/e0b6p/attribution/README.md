# E0b6p complete-tick attribution

2026-10-07 · **Status: verified research tooling.** [Recorded measurements and next experiment](../../../../docs/research/propwash/E0b6p/attribution/README.md).

This research-only runner copies the full `app/` tree, installs the existing native adapter in that copy, then compares the uninstrumented 12-case swirl benchmark with a temporary instrumented build. The source app is never patched. The six regimes are forward, stall, static, spin, reverse fade and reverse off, each at zero and 0.4 swirl.

First build the [baseline native experiment](../../../../docs/research/propwash/E0b6p/native/README.md) if its library is absent. Run from the repository root:

```sh
python3 research/propwash/e0b6p/attribution/run.py \
  --project app \
  --godot "$(app/get-godot.sh)" \
  --library .tools/native-smooth-wake/libopenrc_slipstream.so \
  --output /tmp/e0b6p-attribution
```

`attribution.json` contains exclusive per-tick means and observer overhead. Raw timings and all 240 body, auxiliary and continuous-state boundaries per case are in `baseline-native.json` and `instrumented-native.json`; the runner requires exact boundary equality. The staged project is retained at `work/app` for inspection.

The exclusive buckets are Air.compute, Aero.loads, Propulsion.loads, Slipstream.loads, Ground.loads, the Flight `_pre_step` callback after subtracting its nested Air.compute calls, and the residual of `Simulation.step`. Air.compute calls from dynamics and pre-step are counted separately before they are combined. The residual formula subtracts each disjoint timed region from the full step, so the seven buckets sum to the mean measured step timer. The report also gives inclusive callback time for interpretation.

Observer overhead is the median of alternating paired enabled-minus-disabled batches in the same staged build. The disabled-build delta against the unmodified native-adapter baseline is only an observed difference with shared-host noise; it does not isolate scaffolding cost. The checks require native-kernel calls, expected component counts, all 12 cases, and exact body/auxiliary boundaries. Comparator mutations reject zero counts, a wrong regime, truncated or non-finite boundaries, and zero native-kernel calls.

This first pass does not split the GDExtension's dictionary decode from its C++ kernel. It also uses microsecond timers, so very small component values have quantization and measurement overhead. The fixture is not calibrated Stik data.
