# Geometry capture checks before the upstream atlas change

This record covers the audit candidate based on `8ce11eb2`. Godot 4.8.beta2 parsed both capture scripts. All 26 Python capture-harness tests passed in 42.549 seconds. The five native checks ran headlessly. Source hashes, native log text, report hashes, expected exits and the fixture command are recorded in [receipt.json](receipt.json).

| Native check | Observed result |
| --- | --- |
| Hedge script parsing | Exit 0, zero warnings and errors |
| Furniture script parsing | Exit 0, zero warnings and errors |
| Hedge execution without a display | Expected exit 2 before it could publish a capture |
| Hedge camera and crop geometry | CPU nearest-sample estimate of 3,121 and 2,662 foreground pixels in the two clipped views, including 86 and 89 border pixels. The half-card crop removed 5,100 foreground samples in the first view. |
| Material identity control | Replacing the bound atlas caused the fixture to reject it. |

The shell harness exercises command order, early failures, completion milestones, source bindings and rejection of damaged output with disposable command stubs. It rejects a 24-byte PNG header even when the supplied SHA-256 matches those bytes. The four furniture cases require visible changes in their central image region when the target picnic table or bench is removed and recovery when its original mesh is restored.

Hosted rendering and inspection of the 1920×1080 furniture images were pending at this snapshot. The pre-merge hedge fixture uses the flower atlas with mip generation disabled. The upstream forest-shrub atlas enables mipmaps and requires new measurements on the merged source.
