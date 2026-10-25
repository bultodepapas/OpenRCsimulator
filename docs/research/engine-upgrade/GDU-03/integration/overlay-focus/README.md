# GDU-03 responsive overlay layout and focus

2026-10-25. The existing 672-case modal matrix found six geometry failures:
at 200% text, the overlay panel's 743-pixel minimum height exceeded the short
540/576/720-pixel viewports in both English and Spanish. Preset and Units now
join the scrolling body in short stacked layouts; title, tabs and Done stay
reachable, with no font-size reduction. The primary 1080p layout retains its
fixed header controls. The final unchanged matrix passes **672 cases, zero
failures**, including the primary and higher-resolution cases and live reflow.
[Geometry verification](responsive-verification.json) binds the original failures,
final checked run and exact source hashes. These are headless layout measurements.

The responsive overlay dialog moves Preset and Units into its scrolling body for large text in short viewports and restores them above it at full height. Godot drops descendant keyboard focus during `Node.reparent`. An external extension of the existing overlay-manager test reproduced four focus failures: each picker lost focus in both directions, while all six setup/parent assertions passed.

The fix captures the focus owner before the row moves and restores it only when the moved row contains that control. It preserves the responsive parent/order behavior and leaves unrelated controls' focus alone. The existing `test_overlay_manager.gd` now covers both pickers at 2x text across 1920×1080 → 1280×720 → 1920×1080, checks actual parent transitions and retained focus, and restores its original viewport/text settings.

The [bounded external extension](focus-extension.gd.txt) changes from 6/10 to 10/10 passing checks. The full amended overlay-manager test passes **198 checks**, zero failures and zero engine diagnostics. [Verification](verification.json) retains original failure, corrected focused run and full amended-suite reports/logs with exact source hashes. These headless runs establish layout and keyboard interaction behavior, with no rendered-image or performance claim. The final root checks ran separately while the unchanged frozen integration continued.
