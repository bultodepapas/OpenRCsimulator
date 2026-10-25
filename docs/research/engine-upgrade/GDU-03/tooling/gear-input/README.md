# GDU-03 retractable gear input teardown

The eight input assertions passed, then the test freed its session twice. `root.remove_child(flight)` invokes `Main._exit_tree()`, which frees an unattached session and clears the flight reference. The local test variable remains an invalid object; its explicit `session.free()` caused Windows heap corruption (`0xC0000374`).

The unchanged test reproduced the original suite failure on both official 4.8 beta1 and 4.7.2, with the same eight-check log and exit code. The retained [disposable diagnostic](ownership-diagnostic.gd.txt) logs session validity changing from true to false immediately upon flight removal. Skipping the second free completes normally.

The fix removes only the duplicate test free. All eight input assertions remain unchanged. The final-source fixture passes twice on 4.8 and once on 4.7, with normal exit and zero engine diagnostics. This is a pre-existing test ownership defect, not evidence of an input or simulation regression. No runtime/core/profile bytes or official engine pin changed. Headless runs use isolated user-data directories; elapsed times under shared CPU load are not performance qualification.

[Verification and retained reports/logs](verification.json) identify each run, including the original crashes. The original full-suite report is retained separately as [the triggering failure](original-suite-report.json).
