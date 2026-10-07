# E0b6p native cost attribution

2026-10-07 · **Status: verified research tooling.** [Recorded measurements and next experiment](../../../../docs/research/propwash/E0b6p/attribution/README.md).

This runner profiles the six fixed `combined_raw()` fixture regimes through the direct GDExtension call and the research adapter. The builder creates an instrumented source/library copy under `.tools/native-wake-attribution`; it never replaces the baseline library. Source patching fails closed if the original load kernel or wrapper class changes.

## Reproduce

First build the [baseline native experiment](../../../../docs/research/propwash/E0b6p/native/README.md) if its library is absent. From the repository root:

```sh
python3 research/propwash/e0b6p/native-cost/build_attribution.py --jobs 2
python3 research/propwash/e0b6p/native-cost/run_attribution.py \
  --project app \
  --godot "$(app/get-godot.sh)" \
  --baseline-library .tools/native-smooth-wake/libopenrc_slipstream.so \
  --instrumented-library .tools/native-wake-attribution/libopenrc_slipstream.so \
  --output /tmp/e0b6p-native-cost
```

The runner profiles seven batches of 3,000 calls after 500 warm-ups per regime, compares baseline and instrumented output arrays exactly, and runs the 297-load native verifier. It checks sample counts, finite loads, adapter routes, and phase counters; startup mutation checks reject missing vectors, NaNs, and wrong native call counts. Raw and corrected phase counters, batch timing distributions, logs, verification results, and hashes are written to the requested output folder; the verified run is archived in the linked evidence.
