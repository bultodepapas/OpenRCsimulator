# Monster Car 2 session replay evidence

Run the focused session verifier from the repository root with the pinned Godot console build:

```powershell
$GodotRcv = (Resolve-Path '.tools/Godot_v4.7.2-stable_win64_console.exe').Path
$Verifier = (Resolve-Path 'research/rc-monster-truck/monster-car-2/session/verify_replay.gd').Path
& $GodotRcv --headless --path app --audio-driver Dummy --script $Verifier
```

The verifier selects `monster-car-2`, records 480 fixed-rate ticks, exports the session recording
under `user://rcv/`, restores a JSON-round-tripped tick-zero checkpoint and a final full-state
checkpoint, then replays the same control tape. It prints one `NITRO_SESSION_EVIDENCE=` JSON record
with state and tape hashes, the composite solver identity, recording hashes and exact replay result.
Each run uses a fresh export name; the CSV and metadata remain in Godot's user data directory.

Require exit status zero and `complete: true`. Matching final and replay state hashes establish
software replay determinism for this run. They do not establish physical validation or calibration
of the estimated engine, clutch, tire or chassis parameters.
