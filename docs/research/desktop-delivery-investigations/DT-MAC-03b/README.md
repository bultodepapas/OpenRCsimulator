# DT-MAC-03b: graphics-option ladder on the M1 (ANGEL)

Run 2026-11-18. The campaign measures how one fanless M1 MacBook Air responds to each player graphics option,
using the real app route (Home → Fly) on its real 1080p display. It attributes graphics-option cost only. It
does not complete the [DT-MAC-03b plan](../../../plans/apple-silicon-performance.md#dt-mac-03b--attribution-and-baseline-soak):
no CPU profile, no GPU trace, and no workload manifest beyond the club field, Green Paradise and night. Method and
tools: [graphics ladder](../../../../research/performance/mac_graphics_ladder/README.md).

## Host, source and display

| Item | Value |
| --- | --- |
| Mac | ANGEL, MacBookAir10,1, Apple M1 (7-core GPU), 8 GB, fanless, on AC; macOS 27.0 (26A5425a); low-power mode off throughout |
| Display | External HDMI 1920×1080 at 60 Hz, main display, mirrored to the built-in 2560×1600 panel ("Master Mirror" / "Hardware Mirror"). 1080p is the target. |
| Engine | Godot 4.8-beta2 official (`cafc17a19`), `Mobile`/Metal = Standard, `forward_plus`/Metal = High |
| Source | Snapshot `212e9e7e44424608441a6ff6be92d44880f36f92`, project renamed so `user://` is isolated from the player's profile |
| Physics | GDScript reference for every run ("collision world differs from the screened stock context"). The snapshot has no macOS native kernel. The domain fix landed later in `680b98dfc`. The GPU was saturated (≈98 %) in every uncapped run, so the physics backend did not set the frame rate. |
| Plan | `plan-v2.json` (sha256 `b393864d…`): 139 runs, 36 configurations, 15 reference runs |
| Evidence | Outside Git on the owner's PC: `D:\OpenRCsimulator-evidence\gfx-ladder-20261118\` holds `runs/` (per-run `result.json`, frames, pilot, host state, logs, `clubhouse.jpg`/`crash.jpg`), `runs/conditions.json` and `summary-v2.json`/`.md`. Mac workspace: `/Users/g/OpenRC-m1-work/gfx-ladder-20261118/`. |

Each run seeds `user://settings.cfg.display`, launches the app, checks the saved and effective settings, and
measures Home for 8 s. It then flies the Ugly Stik 60 on a closed-loop 90 m orbit over the clubhouse at 40 m and
measures one two-lap window (~48 s, identical views). Finally it dives at the pilot station and measures the crash.
VSync is off unless stated, so fps is render throughput, not what a 60 Hz panel shows.

## Host conditions changed twice

The REF configuration (L09) ran every ten runs and exposed both changes:

| Segment | Runs | REF fps | Cause |
| --- | --- | --- | --- |
| Fanless, remote capture | 000–036 | 72.2 → 59.5 (heat-soaked) | No cooling. macOS `thermalState` stayed **fair** while the GPU lost up to a third of its throughput. |
| Cooled, remote capture | 037–101 | 71.7–72.6 | The owner placed external cooling under the Mac at 17:48. Thermal state was nominal from then on. |
| **Cooled, clean** | 102–138 | **77.3–78.3** | A RustDesk session from the owner's PC had been capturing the Mac's screen and audio since 12:21. It ended at 21:21:33 (`pmset -g log`). |

The RustDesk capture alone cost **7.9 %** of fps: 72.0 vs 78.2 at REF, with identical settings, render size,
power source, low-power state and thermal state. The headline values below use the clean segment, where every
configuration has one run. **Normalised** fps pools the two cooled segments: each run is scaled by its segment's
REF ratio (1.086), and capped runs are not scaled. Ladder steps are deltas paired within each pass, with a 95 %
t interval over four passes (two ascending, two descending). After normalisation the ascending-minus-descending
gap is at most 0.5 fps for every step except L10 (1.3 fps). The earlier ~3 fps "order effect" was the remote
session, not heat.

## Ladder: cost of each option (1080p, Standard renderer, cooled)

Each step adds options to the previous one. A step's delta is its marginal cost on top of the earlier steps.

| Step | Options added | fps clean | p95 ms | Δ fps paired (±95 %) | Δ % |
| --- | --- | --- | --- | --- | --- |
| L00 | Every option at its minimum | 88.4 | 14.7 | — | — |
| L01 | Scene detail Medium | 88.5 | 14.9 | +0.1 ± 0.7 | 0 |
| L02 | MSAA 2× | 85.4 | 15.1 | **−3.2 ± 0.1** | −3.6 |
| L03 | Projected shadows, planar aircraft cue | 83.8 | 15.3 | −1.1 ± 0.8 | −1.3 |
| L04 | Native sun shadows (Automatic technique, 300 m, PCF; 2048 atlas) | 82.2 | 16.0 | −1.5 ± 0.4 | −1.8 |
| L05 | Shadow quality Standard (4096, 16-bit, 2 cascades) | 81.2 | 16.0 | −1.1 ± 0.3 | −1.4 |
| L06 | Cloud shadows | 81.2 | 15.8 | 0.0 ± 0.5 | 0 |
| L07 | Birds Normal, flags, runway meadow, RC track | 80.7 | 16.1 | −0.4 ± 0.6 | −0.5 |
| L08 | Lens/impact effects, aircraft lighting Standard + VFX | 80.7 | 16.2 | +0.1 ± 0.5 | 0 |
| L09 | MSAA 4× (= product defaults with Scene detail Medium) | 78.1 | 16.7 | **−2.6 ± 0.5** | −3.2 |
| L10 | Scene detail High | 76.6 | 16.7 | −1.8 ± 1.7 | −2.3 |
| L11 | Shadows High (4 cascades, 32-bit), 600 m, Soft | 75.5 | 16.8 | −1.4 ± 1.2 | −1.8 |
| L12 | Scene detail Extreme | 75.0 | 16.9 | +0.1 ± 0.7 | 0 |
| L13 | Shadows Ultra (8192), lens Ultra, lighting High, birds Many, flags Detailed, splatter | 70.9 | 17.7 | **−4.6 ± 0.9** | −6.2 |
| L14 | MSAA 8× | 70.9 | 17.6 | −0.1 ± 0.2 | 0 |
| L15 | L14 on the High renderer (Forward+/Metal) | 55.4 | 22.2 | **−14.9 ± 0.7** | −21.0 |

- From floor to maximum on Standard (L00 → L14), fps falls 20 %. Moving that maximum to Forward+ costs another 21 %.
  On High, L09 runs at 57.3 fps (−27 % against Standard's 78.1) and draws 605 calls instead of 364.
- **MSAA is the largest cost the player controls on Standard.** 2× costs 3.6 %, 4× costs another 3.2 %, and MSAA off
  at L09 gives 83.4–83.8 fps (see the MetalFX Temporal note below).
- **MSAA 8× costs nothing on the M1.** Fps, p95 and reported video memory (1,512.8 MiB) are identical to 4×. The
  sample count is very likely clamped to 4×, so the option promises quality it does not deliver.
- **Several options cost nothing measurable in daytime flight:** cloud shadows, the scenery-life bundle,
  lens/impact effects with aircraft lighting, Scene detail Medium and Scene detail Extreme on top of High.
- Shadows cost 4.5 % up to Standard quality, 1.8 % for High and most of L13's 6.2 % for Ultra.
- Video memory rises from 1,015 MiB (L00) to 1,255 (L09), 1,513 (L13) and 1,768 (Forward+). Process RSS stayed at
  1.1–1.6 GiB of 8 GiB.

## Resolution, MetalFX, renderer, VSync, landscape and night (clean runs)

| Config | fps | p95 ms | vs L09 (78.1) |
| --- | --- | --- | --- |
| L09 windowed 1280×720 | 135.1 | 10.3 | +73 % (CPU 86 % of one core: CPU starts to matter) |
| L09 windowed 1600×900 | 100.5 | 13.2 | +29 % |
| L09 + MetalFX Spatial Quality (internal scale 0.667) | 100.0 | 13.3 | **+28 %**, the same as rendering 1600×900 |
| L09 + MetalFX Spatial 85 % | 82.1 | 15.8 | +5 % |
| L13 + MetalFX Spatial Quality | 91.1 | 13.8 | +28 % against L13 (70.9) |
| L09 "MetalFX Temporal" Quality / Native AA | 83.4 / 83.8 | 15.8 / 15.5 | Not Temporal; see below |
| L09 on High (Forward+) | 57.3 | 20.9 | −27 % |
| AUTO: every Automatic choice, borderless 1080p | 78.3 | 16.3 | Same as L09: Automatic picks Standard and Scene detail Medium |
| OOB: fresh-install display defaults (windowed, VSync on) | 60.0 | 18.4 | 1920×1018 window |
| L00 / L09 / L13 with VSync 60 Hz | 60.0 / 60.0 / 60.0 | 17.8 / 18.4 / 18.4 | GPU 71 / 79 / 86 % |
| Green Paradise L09 / L13 | 70.3 / 55.2 | 16.9 / 20.9 | −10 % / −22 % against the club field, with fewer primitives (113 k vs 242 k) |
| Night L09 / L13 | 98.8 / 86.7 | 13.2 / 14.7 | +26 % / +22 % |

**MetalFX Temporal did not run.** It is trial-gated (`OPENRC_METALFX_TRIAL`) and requires Forward+
([policy](../../../../app/render/metalfx_policy.gd)). On Standard the app correctly kept Native scaling. The
seeded MSAA-off setting still applied, so those runs measure L09 without MSAA. The ladder's effective-setting
check compared MSAA but not the scaling mode, so this was not flagged at run time.

**VSync pacing:** at 60 Hz every level held a 60.0 fps mean, but 3.6–3.9 % of frames exceeded 20 ms and the
1 % low was 36–39 fps. That includes L00 with the GPU 29 % idle, so the misses are pacing, not capacity.

## Fanless sustained play

Comparing the fanless pass with the cooled passes taken under the same remote capture shows the effect of heat
alone. The first ~90 minutes of back-to-back runs held full speed (L00 80.3 vs 81.0; L09 72.1 vs 72.3). From about
16:05 the heavy steps lost a fifth to a third, while `thermalState` reported only `fair`:

| Config (fanless start time) | Fanless fps | Cooled fps (same capture) | Loss |
| --- | --- | --- | --- |
| L12 (16:07) | 56.3 | 69.4 | −19 % |
| L13 (16:11) | 45.6 | 65.0 | −30 % |
| L15 (16:21) | 35.0 | 51.4 | −32 % |
| REF (16:37) | 59.5 | 72.0 | −17 % |
| X01 (17:06) | 44.4 | 53.0 | −16 % |

When cooled, both 14-minute soaks were flat: L09 72.1–72.6 fps and L13 64.8–65.1 fps over twelve two-lap windows.
A fanless Air in long sessions therefore sits near 60 fps at product defaults and below it at high settings.
Its thermal API cannot warn the app.

## Crash and Home

- **Crash** (dive into the pilot station plus 4 s after impact, clean runs): L00 74.7 fps, max 34 ms; L09 58.3 fps,
  p95 22.4 ms, max 39 ms; L13 44.1 fps, max 47 ms; L15 30.2 fps, max 66 ms. No clean crash had a hitch. Effects
  and close ground views cost about a quarter of the orbit's fps. The **first** crash of each configuration in
  the campaign included one-time pipeline compilation, up to 520 ms (L02, first MSAA 2× crash), 189 ms (L01)
  and 190 ms (L13). Every later crash in any configuration stayed at or under 72 ms. This hitch class belongs to
  [DT-MAC-03b-b](../../../plans/apple-silicon-performance.md).
- **Home renders slower than flight.** At L09 Home runs at 52.6 fps against 78.1 in flight, at L13 33.6 against
  70.9, and at L15 18.6 against 55.4. In the OOB (VSync) run Home reached 55.4 fps, below the 60 Hz display.
  Idling at Home heats a fanless Mac more than flying.

## Recommendations

1. Keep Standard (Mobile) as the M1 renderer. Forward+ costs 21–27 % for no option tested here.
2. On Apple GPUs, hide MSAA 8× or label it as 4×. It has no cost and almost certainly no effect. Confirm the
   effective Metal sample count before changing the picker.
3. Automatic's M1 choice (L09) leaves ~30 % headroom over 60 Hz when cooled. In fanless sustained play,
   MetalFX Spatial Quality (+28 %) is the only option worth more than a few percent that is not anti-aliasing.
   Consider recommending it, not forcing it, on fanless Airs at 1080p. The 1080p sharpness cost needs visual
   review first.
4. Leave cloud shadows, scenery life, lens effects and Scene detail Extreme free to enable on the M1. They do not
   affect daytime frame rate.
5. Budget by landscape. Green Paradise is 10–22 % heavier than the club field at the same settings.
6. Investigate VSync pacing (≈3.7 % of frames over 20 ms at every load) and the Home scene's GPU cost. Cap
   Home's frame rate or lighten its preview.
7. Never benchmark with a remote-desktop session attached (−8 %). Record cooling and remote sessions as campaign
   conditions; the analyzer now pools segments only through REF normalisation.

## Limits

- One Mac, one display, one aircraft and three scenes. The Mac had external cooling for the headline values; the
  fanless section is the sustained player case.
- Each configuration has a single clean run (REF repeatability in the segment ±0.6 %). Step deltas use four
  normalised passes, and normalisation assumes the remote capture scaled all configurations equally.
- The crash window includes the dive, and impact points vary by a few metres.
- The pilot adds ~24 bridge requests per second to every configuration. GDScript physics was used throughout.
- Software measurement on one host; it is not a sustained product qualification and not hardware-independent.
