# GDU-03: bounded Settings Graphics layout

2026-10-25, official Godot 4.8-beta1. The existing Settings test exposed a real
default-size layout overflow: its Graphics page required 582 pixels inside a
580-pixel body at 1920×1080, producing an unnecessary scrollbar.

The only runtime change is `app/ui/settings_screen.gd`: reduce the Graphics
page's eight inter-item gaps from 12 to 10 pixels. This frees 16 pixels without
changing control sizes, fonts, the bounded workspace, the body scrolling policy
or any test assertion/tolerance. Root and the frozen full-suite runtime file
match exactly; the package agent received the same path/hash.

The full existing `test_settings_ui.gd` passes both headlessly and natively,
with zero engine errors or warnings. A diagnostic copy of the native run adds
only a geometry receipt before the existing Graphics-page assertion. On the
RTX 3090 Compatibility renderer it records:

| Native layout measurement | Result |
| --- | --- |
| Root drawable and logical surface | 1920×1080 |
| Settings panel | 800×880 |
| Graphics body | 752×580 |
| Graphics page and minimum height | 752×566; minimum height 566 |
| Default Graphics scrollbar | Hidden |

All category-fit checks pass. The unchanged 200% text assertions also pass:
rows stack, only the body scrolls, title/actions remain pinned and focus reveals
the complete language selector. Persistence, Keep/Revert, focus transfer and
15-second recovery checks remain passing. No performance or package
qualification follows from this focused result.

[Verification](verification.json) retains both checked commands/log identities,
the original failure receipt, runtime/test hashes and measured native geometry.
Runs use isolated D-drive profiles/temp paths; raw logs and the diagnostic
test copy remain at `D:/OpenRCsimulator-experiments/gdu03-settings-layout/`.
No images were created. The GPU reservation was released to the package agent.
