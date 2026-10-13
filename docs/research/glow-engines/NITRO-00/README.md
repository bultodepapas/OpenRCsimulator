# NITRO-00 — Manufacturer evidence for RC glow engine families

2026-10-13 · **Status: initial primary-source review; no physical calibration or validation.** Pending work belongs to the [RC glow engine realism plan](../../../plans/RC_NITRO_ENGINE_REALISM_PLAN.md). Manufacturer recommendations and ratings below are not independent measurements.

## Manufacturer evidence

| Engine | Family | Verified published constraints | Source and limits |
| --- | --- | --- | --- |
| O.S. MAX-55AX, product 15612 | 2T glow | 8.93 cc; bore/stroke 23.0/21.5 mm; 1.7 PS at 16,000 RPM; practical 2,000–17,000 RPM; sport props 12×7–8 or 13×6–7 inches. | [Product specification](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/15612.htm); [manual](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/img/manual/15612.pdf), PDF pp. 1 and 4. Stock E-3071 silencer/40K carburetor. No full torque curve or measured transient series. |
| O.S. FS-64V, product 3AY00 | True 4T glow | 10.46 cc; bore/stroke 25.0/21.3 mm; 1.14 PS at 11,000 RPM; practical 2,400–11,000 RPM. Product props: sport/stunt 12×6–8 or 13×6–7; scale 14×6 inches. | [Product specification](https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html); [manual](https://www.os-engines.co.jp/english/line_up/engine/air/single/img/manual/3AY00.pdf), PDF pp. 1–2. Single-cylinder overhead valves, Type F plug, F-4051 silencer. The manual's starting prop table differs slightly from the product table; preserve both. |
| Saito FA-82B | True 4T glow | English manual: 13.47 cc; bore/stroke 29.0/20.4 mm; practical approximately 2,000–12,000 RPM, ground maximum approximately 9,000–11,000. APC 13×7–8 or 14×5–6 inches. Approximately 35 cc/min at full throttle and 10,000 RPM, explicitly load dependent. | [English manual](https://www.saito-mfg.com/PDF/instruction/eng/4st/FA-82Bhp.pdf), PDF pp. 1–4; [product page](https://www.saito-mfg.com/productstop/products-4st/fa-82b/). The flow is a manufacturer reference without full test conditions, not a measured multi-point map. No numerical torque/power curve in the inspected material. |
| YS FZ115S | True 4T glow, boosted/injected | 18.73 cc; 2,000–13,000 RPM. Props 14×11–12, 15×10–11 or 16×8 inches, selected for 7,000–11,000 RPM. | [Manufacturer manual](https://www.yspower.co.jp/en/data/pdf/fz115s.pdf), PDF p. 1. Crankcase-pressure air chamber/double-throttle charge system, injection and crankcase-pressurized tank/check-valve feed. No numerical torque, fuel-flow or response-time map. |
| YS DZ170 | True 4T glow, boosted/injected, fuel pump | 27.95 cc; 2,000–10,000 practical RPM; props 17×13–18×11 inches for 7,800–8,800 RPM. | [Manufacturer manual](https://www.yspower.co.jp/en/data/pdf/dz170.pdf), PDF p. 1. Explicitly uses a true fuel pump rather than the earlier high-pressure fuel system; crankcase supercharging retained. Do not copy the FZ tank-pressure model. No numerical torque/flow map. |
| ENYA SS35EX TN (RC version) | 2T glow | 5.52 cc; bore/stroke 19.5/18.5 mm; 0.8–0.9 HP; 2,500–16,000 RPM; published prop notation 10–11×6–4 inches. ENYA No. 3/4 plugs. | [Manufacturer product page](https://www.enya-engine.com/SS35EX.html). ABC piston/cylinder and revised exhaust port. The CL SS35EXS has a different RPM range; do not merge variants. Power's speed/test conditions and exact recommended prop combinations require clarification before normalization. |

Fuel, operation and distinctions:

- **MAX-55AX:** PDF p. 2 describes muffler-pressure feed and approximately 350 cc for 10–12 minutes, conditional on fuel/prop/throttle history. Its fuel paragraph names **46AXII** despite the 55AX cover/specifications: treat the printed minimum 18% oil and 5–20% nitro recommendation as an applicability conflict pending corroboration. PDF p. 3 explains that rich operation of this two-stroke can fire every fourth piston stroke instead of every second. It also describes excess-rich smoke/unstable RPM and lean cutout during throttle opening. These qualitative observations support instability research, not numerical stall thresholds.
- **FS-64V:** PDF p. 1 specifies methanol-based fuel with at least 18% lubricant and 5–20% nitro, factory adjustment for 18% oil/15% nitro, and muffler-pressure feed. PDF p. 2 links sluggish smoky pickup to rich idle mixture, cutout on opening to lean idle mixture, and overheating to too-lean operation. There are no temperature thresholds or measured throttle time constants.
- **FA-82B:** PDF p. 2 specifies 10–20% nitro and at least 20% lubricant by volume, warns about castor-related deposits, and uses muffler pressure. PDF p. 4 describes about 2,000–2,500 RPM idle and smooth idle-to-peak transitions; its tuning guidance stays about 300 RPM below peak. Neither this nor the flow point establishes universal 4T efficiency.
- **FZ115S:** PDF p. 1 recommends 15–30% nitro and 15–20% oil during break-in and slightly rich operation thereafter. About 2,300 RPM idle followed by 20–30 seconds before throttle advancement is an adjustment procedure, not a 20–30 second response lag. These fuel rules belong to this model.
- **DZ170:** PDF p. 1 recommends YS 20/20 fuel; its break-in section allows 15–30% nitro and 20–24% oil, synthetic with castor no more than 2%. Idle guidance is approximately 2,200 RPM, with a 15–20 second idle observation before advancement. It does not publish a pressure, torque or fuel-flow calibration.

## Conflicts and interpretation

The [2006 O.S. MAX-55AX launch page](https://www.os-engines.co.jp/english/2006autumn/max55ax.html) reports **1.75 PS at 16,000 RPM**, whereas the inspected product 15612/manual specifies **1.7 PS**. Preserve the product/manual revision; do not silently average ratings or import an older hardware weight/exhaust configuration. PS is metric horsepower; preserve its conversion rather than treating PS and mechanical hp as identical. A rated power/RPM point gives torque only at that point through `Q=P/(2π RPM/60)`; it does not identify a torque peak or a full curve.

The Saito product page reports rounded **13.5 cc**, **2,300–11,000 RPM** and approximately **462 g** body mass, whereas its linked English manual gives **13.47 cc**, approximately **2,000–12,000 RPM** and **477 g** body mass. The manual also distinguishes practical RPM, recommended loaded ground RPM and operation to avoid. Record the physical engine's production letter/manual context before setting limits or inventory mass. None of these differences justifies averaging incompatible revisions.

The published O.S. prop tables are starting recommendations, not measurements of propeller load. The [UIUC Propeller Database](https://m-selig.ae.illinois.edu/props/propDB.html) supplies wind-tunnel/static thrust and torque coefficient evidence, with propeller identity and Reynolds/RPM limits. A similar size or electric prop is not automatically suitable evidence for a glow installation. [Repository G1a1](../../propulsion/G1a1/README.md) retains these applicability limits.

The [NASA low-order engine/propeller study](https://ntrs.nasa.gov/citations/19950026495) is a useful precedent for torque-balance transient modeling; its general-aviation engine/variable-pitch results do not calibrate either RC family. The [G2 derivation](../../propulsion/G2a-RK4/sources.md) owns OpenRC's relative-spin/body coupling. [VAL-7a](../../validation/VAL-7a/README.md) and [VAL-7b](../../validation/VAL-7b/README.md) supply existing reduction tools, not real measurements.

## Readback and source identity

Checked official links on 2026-10-13. PDFs were downloaded unchanged to an external temporary directory, inspected for page/text coverage with `pypdf`, rendered with PyMuPDF and visually read at the relied-upon sections. O.S. PDFs have effectively no native text; Saito has native specifications on p. 1 but p. 2–4 require visual readback. YS native text was cross-checked against rendered p. 1. No OCR-derived numbers or complete third-party manuals are committed.

| PDF | Pages | SHA-256 of downloaded bytes |
| --- | ---: | --- |
| MAX-55AX `15612.pdf` | 4 | `629c2cf11d8d1bcfc96c9aa8b50649b2c621324a392e59e179c1c93bb96b521b` |
| FS-64V `3AY00.pdf` | 2 | `e40d025501ae9d16227520c2cf3a5c6da91aaf8ad3d8f7b3a5173f18b98481d6` |
| FA-82B `FA-82Bhp.pdf` | 6 | `1f83fb7ba8a3d9f8a7a2a1fdd5d1d8feb24ed5b0d7db3678e66dacd3bc1e006d` |
| FZ115S `fz115s.pdf` | 2 | `bd11a75462312606e0354e0dc6329cd537194ec7ef5d78ef1f2ab84af8002c5b` |
| DZ170 `dz170.pdf` | 2 | `4a4a2018fc2682ef91644ad2432ac6bc00f570f9151d349cdcf9f283bcedd67c` |

Refetch the linked PDFs, compare SHA-256, then inspect the same PDF page/section before reusing values. Hashes identify this snapshot, not permission to redistribute or proof of the manufacturer's test method. Sources are linked; no manufacturer illustrations, recordings or full tables are bundled.

## Remaining evidence

No matched measured torque/power curves, synchronized throttle transients, installed thermal maps, tach/audio/vibration campaign or controlled flight comparison for either baseline was obtained in this source review. The Saito flow datum and O.S. tank/time statements remain limited manual evidence. Both family research milestones must obtain original test records or new matched observations with uncertainty and held-out runs. Manufacturer marketing does not close calibration, efficiency, acoustic or pilot acceptance.
