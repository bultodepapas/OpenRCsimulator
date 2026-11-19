# Radio catalog and compact telemetry — HUD-RADIO-01/02a

Date: **2026-11-19 (America/Bogota)**. Branch:
`plan/radio-display-edgetx-2026-11-18`.
Implementation baseline: `1bfeddaf51f2f71ece67446aac7089d7e988c9d5`.
The [active plan](../../../plans/radio-display-edgetx.md) owns remaining work.

## Delivered behavior

The existing Radio appearance picker now reads a versioned
[catalog](../../../../app/render/overlays/radio_catalog.gd). Its stable order is
JETI DS-24 II, Radiolink T16D, Jumper T18-H7, Radiolink T12D. The first two saved
IDs and the existing default remain intact. Each definition supplies its label,
asset, canvas, gimbal centers, LCD rectangle, accent and firmware capability
metadata. Definitions returned to callers are deep copies.

The two new radios use original schematic SVGs. Their simplified silhouettes
are presentation artwork, not manufacturer drawings. [Artwork provenance](../../../../app/assets/ui/RADIO-ARTWORK.md)
records the MIT grant and distinguishes the unchanged existing PNGs. Product
identity and firmware capability remain separate: RadioLink definitions have
no EdgeTX target, and choosing any appearance does not modify a controller
profile, calibration or input mapping.

The [display formatter](../../../../app/render/overlays/radio_display.gd) reads
accepted OpenRC telemetry and the existing sampled/quantized battery sensor
view. It provides elapsed simulation time, airspeed, height above terrain,
flight-pack voltage and consumed mAh. The compact LCD paints a **SIM** header
and as many rows as fit; smaller displays omit lower rows. It does not invent
RSSI, transmitter-battery readings, state of charge or a firmware model name.
Unavailable/nonfinite data remains unavailable.

The [overlay manager](../../../../app/render/overlays/overlay_manager.gd) feeds
the display at its existing 10 Hz accepted-snapshot boundary, independently of
stick movement. Hidden displays avoid text churn; reopening schedules a fresh
snapshot. Explicit reset clears the display immediately, including a reset at
the same simulation timestamp. A rewind uses the existing reset and battery
sensor lifecycle. The formatter returns presentation strings and does not write
controls or simulation state.

The [existing dialog](../../../../app/ui/overlays_dialog.gd) supplies catalog
labels, a schematic-art tooltip and help identifying AS, AGL, SIM and battery
data. Both new messages are present in all eight translated catalogs. English
remains the source language.

## Verification

The stable candidate passes the focused pinned-engine checks. The engine is Godot
`4.8.beta2.official.cafc17a19`; its official archive and executable hashes were
checked by `app/get-godot.sh`. This isolated Linux environment has no configured
shared test-pool host (`testctl.py pool hosts` reported a missing pool config),
so focused checks use the repository's checked runner locally.

| Check | Observed result |
| --- | --- |
| Required-resource import | Checked verdict passed; complete, exit 0 |
| `test_overlay_manager.gd` | **277 checks, 0 failed**; checked verdict passed, complete, exit 0; completion marker required |
| `test_ui_language.gd` | **All UI language checks passed**; eight translated catalogs each cover all 4,213 source messages; format arguments and bundled glyph checks pass |
| Whitespace and source review | `git diff --check` passes; independent review findings resolved |

[Verification receipts and source hashes](verification.json) bind these results
to the candidate files. Native-stage binaries were not installed; the existing
flight-scene portion used the GDScript reference backend. The full fresh asset
import exceeded its bounded attempts in unrelated vehicle and aircraft GLBs.
The final focused checkout retained all source scripts, ordinary resources and
the Stik engine GLB required by these tests, while omitting other GLB assets.
That import and both complete tests passed; this is not full-asset or package
qualification. The original schematic SVGs were also rasterized and visually
inspected independently of Godot; that does not substitute for native HUD captures.

The expanded [overlay test](../../../../app/tests/test_overlay_manager.gd)
covers saved IDs and all four picker choices, defensive geometry copies,
artwork presence, layout at 1920 × 1080 then 1280 × 720, existing stick modes,
metric/imperial readings, sensor quantization, stationary-stick updates,
hide/reopen freshness, missing/nonfinite data and reset/rewind behavior. It
also retains the existing flight-scene and pause/overlay checks.

Independent source review found missing locale additions, schematic trim-track
misalignment and insufficient contrast for a tiny red timer. All three were
corrected: complete messages in every catalog, tracks aligned with the common
trim geometry, and the existing high-contrast LCD text color for the header.

## Limits and next increment

This completes the first catalog implementation and the compact-display part
of HUD-RADIO-02. An enlarged keyboard-accessible LCD, aircraft/model naming,
native rendered captures and EN/ES readability qualification remain open.
Headless layout assertions do not establish small-text readability or GPU
rendering quality. The full simulator suite, platform packages and physical
radio tests are outside this localized increment.

There is no EdgeTX runtime in the HUD yet. The separately reviewable
[native observation host](../../../../tools/radio_runtime/README.md) advances
D6-RADIO-01; its output is not admitted as flight control. Copied-model loading,
sensor discovery/telemetry injection, channel freshness and the Godot transport
retain their gates in the active plan.
