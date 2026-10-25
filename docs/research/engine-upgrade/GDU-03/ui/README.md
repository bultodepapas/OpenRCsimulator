# GDU-07: native Windows UI verification

2026-10-25. Official Godot 4.8-beta1 `4d10419ca`, RTX 3090, Compatibility.
Eight existing debug-bridge scenarios passed: flight/restart/Home, helicopter
arming, truck driving, settings revert, Workshop discard, widget presets, birds
settings and Corsair paint selection. Home and flight menu crawls reported no
screen failures or engine warnings/errors. Both inspected application exits
reported no crash and zero leaked objects.

The initial windowed request was clamped to 1920×1061. Accepted screenshots used
explicit fullscreen and measured 1920×1080 for both window and viewport.
[Verification and raw-log hashes](verification.json) identify the frozen source
and the two subsequent corrections:

- The bridge acknowledged `fly` before the rendered loading screen closed.
  It now waits for screen removal before returning the flight state. The existing
  widget scenario reproduces the original failure and passes with the correction.
- The helicopter scenario omitted its launch review. It now presses Continue
  before arming and verifies that the motor is armed. Production arming guards
  remain unchanged.

Invalid attempts are retained separately in the receipt. No physical controller
was connected; this does not qualify SDL device identities or radio calibration.
Concurrent headless tests exclude performance conclusions. Screenshots and full
logs remain under `D:/OpenRCsimulator-experiments/gdu03-suite/tmp/` outside Git.
