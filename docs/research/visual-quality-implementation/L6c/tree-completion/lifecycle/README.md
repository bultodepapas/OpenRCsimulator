# Native Home / Fly lifecycle

2026-10-18, frozen candidate, Godot 4.7.2 Compatibility on RTX 3090. The retained production-UI loading fixture completed **20 Home → Fly → Home cycles** with no engine errors. All first-draw samples are unpaused at simulation tick 12. Nodes remain constant at **1,057 in flight and 604 at Home**, with **zero orphan nodes** throughout.

Shutdown releases audio, leaves zero playing streams and removes the isolated preference sidecar within the fixture's one-second bound. The exact command, fixture snapshot, full report, engine output and file hashes are retained here. The source application is identified in the [frozen comparison](../comparison/README.md).

This establishes lifecycle behavior for the recorded fixed-wing path. OS/import/shader caches were uncontrolled and the separate headless suite was running; construction times are diagnostic values, not cold/warm performance acceptance. This fixture does not exercise every RC vehicle or reset flow and does not replace the repository's broader desktop soak requirements.
