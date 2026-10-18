# Final tree candidate: native lifecycle

2026-10-18, Godot 4.7.2 Compatibility / RTX 3090. The [final frozen R3 candidate](../comparison-final/README.md), source fingerprint `b18a46dfa66d800e8179b7e32be5ea7a27b8e253bacab7da2c23141ca85c3eea`, completes two separate twenty-cycle native fixtures with no engine errors:

| Route | Activity nodes | Home nodes | Result |
| --- | ---: | ---: | --- |
| Home → fixed-wing Fly → Home | 1,064 | 611 | Twenty cycles, first draw unpaused at tick 12 |
| Home → RC garage → reset → Home | 540 | 611 | Twenty cycles, garage and reset paused at tick zero |

All node counts are constant within each route; every cycle reports zero orphan nodes. Both shutdowns release all tracked audio and remove their isolated settings sidecar within the fixture's one-second bound. Each directory retains the complete report, command, exact fixture and engine log; `sha256.json` hashes their bytes.

The RC fixture allows two process frames between UI actions, matching the existing UI test driver's focus-settling contract. Its first diagnostic emitted deferred `grab_focus` errors when reset and Home were triggered in the same frame; that diagnostic was stopped and is [retained separately](../woodland-edges/lifecycle/rejected-rc-same-frame/console.log). No production focus behavior was changed. The corrected fixture passed a two-cycle check before the final twenty-cycle run.

These are lifecycle checks, not active RC driving, physical validation or a desktop soak. The broader CPU verification/export work was allowed concurrently, and OS/import/shader caches were uncontrolled. Recorded construction times are diagnostic; final live-flight performance is measured separately with those jobs stopped.
