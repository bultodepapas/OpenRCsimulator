# TELEM-08 acknowledgement timing, 2026-11-23

The real receiver accepted all three batches in the [hosted integration job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45091058487/job/137421394373). Its log records acceptance at 01:02:41.198, .244 and .379 UTC. The checked client then exited 1 with `E2E sent=2 queued=0 dropped=1 local_drops=0 status=on`. The [receipt](receipt.json) identifies the tested merge, the downloaded ZIP and its three members, the engine output and the source of each local control.

During its final drain, the original fixture advanced its simulated clock 61 seconds on every real process frame. A slow acknowledgement could therefore cross the production queue's ten-minute observation limit while a request was still active. The archived logs report client and server outcomes. The controlled experiment below establishes that acknowledgement timing can reproduce those outcomes.

The updated [driver](../../../app/tests/telemetry_receiver_e2e.gd) advances the simulated send cadence only while the sender is idle. Real frames continue to process HTTP. The driver still requires at least three successful sends, an empty queue, zero queue and local drops, and an enabled service. The [Python test](../../../services/telemetry/tests/test_godot_e2e.py) checks stored row count, build identity, event families and excluded identifying strings after a successful client exit.

| Driver and receiver | Receiver storage outcomes | Client sent / queued / dropped | Checked client time | Python result |
| --- | --- | --- | ---: | --- |
| Original, third acknowledgement delayed 400 ms | 3 accepted | 2 / 0 / 1 | 0.565 s | Failed |
| Updated, same delay | 3 accepted | 3 / 0 / 0 | 1.047 s | Passed |
| Updated, third reply replaced with HTTP 422 after storage | 3 accepted | 2 / 0 / 1 | 0.586 s | Failed |
| Updated, third and subsequent replies delayed six seconds | 3 accepted, 3 duplicate retries | 2 / 1 / 0 | 20.894 s | Failed |
| Updated, ordinary receiver and full project | 3 accepted | 3 / 0 / 0 | 1.149 s | Passed |

Every client reported zero local drops and zero engine warnings or errors. The six-second delay exercised the sender's five-second wall-clock timeout and the driver's 20-second final drain. Its last batch remained queued at exit.

## Reproduce the controls

Use disposable copies of the same checkout for the original and updated drivers. The receipt gives both Git blobs. Install `services/telemetry/requirements.txt` in a virtual environment, import the application with the pinned editor, then run the existing qualification.

```sh
OPENRC_GODOT="$(app/get-godot.sh)" OPENRC_REQUIRE_GODOT_E2E=1 \
  "$venv/bin/python" services/telemetry/tests/test_godot_e2e.py -v
```

For the timed controls, modify only the disposable receiver's `post_batches` in [ingress.py](../../../services/telemetry/openrc_telemetry/ingress.py). In the `status == 202` branch immediately after storage, put these lines before the existing return. This delays the response after the transaction commits.

```python
app.state.control_count = getattr(app.state, "control_count", 0) + 1
if app.state.control_count >= 3:
    import asyncio
    log.info("fixture-controlled-response attempt=%s", app.state.control_count)
    await asyncio.sleep(0.4)
```

Use `return error(422)` in place of the sleep for the refusal control and `await asyncio.sleep(6)` for the stall. Start a fresh receiver for each run. The storage and reporting paths, simulated observations and assertions are the same across the comparisons.

The fault-injection runs used a minimal project with the ten production GDScripts listed in the receipt. The ordinary full-project run verified all 6,015 application source files and executable modes against `8ce11eb2` plus the updated driver. That run reused an existing imported resource cache and completed the original Python test. All runs used the official Linux x86-64 Godot 4.8 beta 2 editor.
