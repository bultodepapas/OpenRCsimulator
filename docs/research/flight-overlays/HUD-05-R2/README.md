# HUD-05-R2 — Radiolink T16D and transmitter appearance chooser

Recorded 2026-10-20. Radiolink's [aircraft transmitter comparison](https://www.radiolink.com/comparison_of_aircraft_transmitters) lists the T16D above its 12-channel models with 16 fully proportional channels. The [T16D product page](https://www.radiolink.com/en/t16d) covers fixed-wing use; its [specifications](https://www.radiolink.com/t16d_specifications) document simulator support via USB-C. This establishes the T16D as the highest-spec aircraft transmitter in the checked official lineup, not a physical compatibility claim for OpenRCsimulator.

The [official frontal image and build instructions](../../../../assets/ui/radiolink-t16d/README.md) record the source and the user's stated permission. The product's transparent PNG has a blank LCD. O2 uses it with live Mode 1/2 sticks, trim marks and simulation values on the LCD. The title identifies the selected model; the footer still identifies the actual input device and its status.

Pause → Flight overlays → Radio appearance switches between `JETI DS-24 II` and `Radiolink T16D`. The choice is validated, previewed immediately and persisted in `[hud] radio_model`. Existing settings files default to JETI. The selector changes presentation only; it does not install a Radiolink hardware profile or imply a verified T16D USB mapping.

Evidence: [rendered selector at 1280 × 720](selector-720.png) and [live T16D crop](radiolink-live-720.png). Godot 4.7.2 resource import succeeded. `test_overlay_manager.gd` passed **131 checks**, including validation, preference round trip, dialog application and the Full layout without overlap at 720p. The captured radio and dialog were inspected for alignment and readable labels.
