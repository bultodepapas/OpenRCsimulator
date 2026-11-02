# Audio queue target control

2026-11-01. The beta2 full-suite run [failed one queue assertion](original-suite-failure/engine.log):
the current target can decrease while frames queued at the previous target are
still waiting for the mixer. The same behavior was reproduced with the unchanged
adapter and Dummy driver on [beta1](beta1-gap/engine.log) and
[beta2](beta2-gap/engine.log): the target fell from 2,926 to 2,176 frames while
2,926 frames remained queued, and the second refill pushed zero frames. This
control establishes an inherited timing-sensitive assertion, not a beta2 change.

The test now checks each refill against the live queue and push counter. Its
long-gap control also requires the excess queue to drain to the unchanged target.
The [instrumented beta2 run](beta2-drain-diagnostic/engine.log) observed the
target drop, no push and successful drain. The exact revised test passed 147
checks on [beta1](beta1-focused/engine.log), [beta2](beta2-focused/engine.log),
and [beta2 at nice +15](beta2-nice15/engine.log). It also passed 147 checks on
the [native Windows beta2 root app](windows-beta2/engine.log) with an isolated
user profile. An isolated mutation that added one extra frame to each refill
was rejected with 13 failures, including all 12 fleet queue checks
([log](beta2-excess-push-mutant/engine.log)). No production audio implementation
or target threshold changed.

The Linux focused runs used an isolated reduced source fixture with minimal
project settings. These are targeted checks, not a full application suite or
an audio-device qualification.
The [index](index.json) records source and evidence hashes. The copied checked
reports retain the original absolute log paths; adjacent logs are byte-identical.
The probe's hash is computed after CRLF-to-LF normalization for checkout
portability.

To reproduce the target-drop control with either verified Linux editor, run from
the repository root with `GODOT` set to that editor:

```sh
fixture=$(mktemp -d)
mkdir "$fixture/render"
cp app/render/engine_sound.gd app/render/engine_audio.gd app/render/engine_voice.gd "$fixture/render/"
cp docs/research/engine-upgrade/GDU-12/verification/audio-queue/gap-control.gd "$fixture/probe.gd"
printf 'config_version=5\n[application]\nconfig/name="Audio Queue Probe"\n' > "$fixture/project.godot"
python3 tools/godot/run_checked.py --label audio-gap --timeout 60 --out-dir "$fixture/checks" -- \
  "$GODOT" --headless --path "$fixture" --audio-driver Dummy --script res://probe.gd
```
