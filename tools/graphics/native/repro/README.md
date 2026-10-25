# Minimal DLSS Vulkan reproducer

This standalone Godot project removes OpenRC assets and scripts from the DLSS mode and resize validation case. It uses a generated grid of boxes, one large floor box, a directional light, and a camera. The project selects Forward+ and the Windows Vulkan driver, with D3D12 and Compatibility fallback disabled.

The DLSS run first requires `Viewport.SCALING_3D_MODE_DLSS` and the Streamline DLSS capability to be present and true. It disables MSAA, TAA, screen-space AA, and Godot's extra `fsr_sharpness` control, matching the app's DLSS path. It then renders 64 frames for each phase:

1. DLAA at 1920 × 1080.
2. Quality, Balanced, and Performance at 1920 × 1080.
3. Quality at 1600 × 900, then Quality after resizing back to 1920 × 1080.

Each phase prints `MINIMAL_DLSS|PHASE_START`, `MINIMAL_DLSS|PHASE_DONE` and its backend status. DLSS requires the native `Streamline.get_dlss_status()` API and at least one successful SDK evaluation per phase with no latched backend failure. `MINIMAL_DLSS|RUN_COMPLETE` means the sequence ran; it does not mean Vulkan validation was clean. Keep and inspect the full engine console output for validation errors, especially `VUID-vkCmdDraw-None-09600` and the image-layout details around `nv.ngx.dlss.Evaluate`.

Run from the repository root with the custom Godot editor that contains the Streamline integration:

```powershell
$Godot = (Resolve-Path '.tools/advanced-rendering/godot-135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/bin/godot.windows.editor.x86_64.console.exe').Path
$Project = (Resolve-Path 'tools/graphics/native/repro').Path
$env:VK_LAYER_PATH=(Resolve-Path '.tools/advanced-rendering/validation-layer').Path
$env:VK_INSTANCE_LAYERS='VK_LAYER_KHRONOS_validation'
$env:VK_VALIDATION_VALIDATE_SYNC='1'
python tools/godot/run_checked.py --label minimal-dlss --timeout 150 --require-text 'MINIMAL_DLSS|RUN_COMPLETE|provider=dlss' -- $Godot --verbose --path $Project --audio-driver Dummy --script res://minimal.gd
```

Use an installed Vulkan validation layer directory for `VK_LAYER_PATH`. Without the layer, a successful run cannot establish Vulkan validity.

The Native control uses the same small scene and resize path at full resolution, with 4× MSAA selected explicitly. It does not select DLSS; the custom engine still initializes Streamline. The separate-thread option additionally exercises device ownership during shutdown:

```powershell
python tools/godot/run_checked.py --label minimal-native-separate --timeout 150 --require-text 'MINIMAL_DLSS|RUN_COMPLETE|provider=native' -- $Godot --verbose --render-thread separate --path $Project --audio-driver Dummy --script res://minimal.gd -- --native
```

If Streamline or its DLSS capability is absent, the DLSS run exits with code 2 and a `MINIMAL_DLSS|UNAVAILABLE` marker. A headless run also exits early, so it cannot be mistaken for a graphics repro.

Repeat DLSS with `--fixed-fps 60 --render-thread separate` before `--path` to
cover capture-time token advancement and queued rendering. A reused token must
not silently pass through the capability check: per-phase dispatch progress is
required. A missing status API or stalled/failed backend exits 3.

The fixture deliberately retains automatic preset selection to reproduce the
original finding. Append `-- --preset=K` to the DLSS command for the application's
validated preset. Test-only `F` and `J` choices are also accepted; they have not
been qualified. The K comparison on the same RTX 3090, Streamline 2.11.1 and
driver completed 384 frames / 360 SDK evaluations with zero Vulkan errors.
Default selection still reports two 09600 errors. Do not infer that K fixes the
SDK internally or qualifies other drivers from this comparison.

On 2026-10-25, the same fixture in an isolated working directory completed with Streamline 2.11.1 on the RTX 3090. Native with the shutdown ownership patch exited zero with no engine errors (192 frames). DLSS exited zero after all 384 frames but emitted two `VUID-vkCmdDraw-None-09600` errors, so its checked validation failed. See the [dated evidence](../../../../docs/research/visual-quality-implementation/VQ-07/native-reconstruction-2026-10-24/README.md). Generated caches and logs must remain untracked.

## Canvas buffer synchronization regression

`canvas_waw.gd` isolates a separate native-renderer defect: a ColorRect followed
by an empty CanvasLayer leaves the canvas uniform buffer's final use as a write.
The next frame writes it again. The original graph resets its command indices
between frames and omits the required memory dependency for that same usage.
This case uses no 3D scene or reconstruction provider.

With the validation environment above, run:

```powershell
python tools/godot/run_checked.py --label canvas-buffer-sync --timeout 120 --require-text 'CANVAS_WAW|COMPLETE|frames=16' -- $Godot --verbose --path $Project --audio-driver Dummy --script res://canvas_waw.gd
```

Require zero validation errors as well as the completion marker. The unpatched
engine exits zero despite its write-after-write errors, so exit status alone is
insufficient. `buffer_write_sync.patch` adds the missing prior-frame dependency
for buffers; it does not change texture-slice or acceleration-structure tracking.
