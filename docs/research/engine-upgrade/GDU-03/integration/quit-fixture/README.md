# GDU-03: reused mocked-Quit fixture state

2026-10-25, official 4.8-beta1, headless/Dummy audio. The original
`test_ui_quit.gd` reproduces two failures with isolated preferences: Retry and
explicit Discard save/resolve their traces but report zero final quit requests.
Its other 49 checks pass, with zero engine errors or warnings.

The test overrides the terminal quit seam so the process stays alive. It then
reuses the same AppRoot for additional synthetic quit transactions, clearing
`quit_requests` and `_quit_audio_pending`. It omitted
`_home_preparation_quit_pending`, which production sets on final commit and
checks to prevent duplicate commits. That flag correctly remains set after a
real terminal quit. Later commits in the reused test fixture therefore return
before reaching its mocked quit seam. The later trial case uses a fresh root
and already passes.

The only change is two fixture resets beside the existing synthetic audio resets
in `app/tests/test_ui_quit.gd`. No production quit guard, recorder, trace data,
recovery choice, audio drain deadline or wait timeout changed. A disposable copy
with exactly those resets passes all 51 existing checks, zero engine errors or
warnings. Current root matches that passing copy after CRLF normalization.
The actual corrected root test also passes all 51 checks with zero diagnostics;
[root verification](root-verification.json) retains that direct invocation.
The direct Recorder case still writes and verifies its real versioned CSV in
the isolated test profile; Retry, Stay, explicit Discard and Workshop transaction
assertions remain intact.

[Verification](verification.json) retains both focused receipts, exact test/runtime
identities and the original failures. Raw logs and the passing copy stay at
`D:/OpenRCsimulator-experiments/gdu03-ui-quit-audit/`. No source was overlaid into
the concurrently running canonical integration tree. Its later coordinated
overlay/focused rerun remains with the root agent.
