# CR-22b research — fire and smoke by energy source

2026-10-13 · **Kind:** dated source review for presentation rules; no physical threshold is measured here. **Serves:** [crash realism plan](../../../plans/crash-realism.md) §3.4, decision D3.

## Sources and what they support

| Source | Finding | Used for |
| --- | --- | --- |
| [AMA Gas Turbine Program](https://www.modelaircraft.org/system/files/documents/510-A.pdf), approved 2024-10-26 | Fuels are kerosene, diesel or propane. Tanks must be rigid, "with consideration given to burst and puncture resistance". The ECU must shut the engine down within 2 s of failsafe. A B/C-rated extinguisher is required at every engine start. | Kerosene fire needs a severe or central impact (rupture estimate unchanged from CR-22a). A hot turbine is the ignition source. |
| [AMA document 511](https://www.modelaircraft.org/system/files/documents/511.pdf) | Same extinguisher and water-based equipment requirement for jet models. | Corroborates that fire is a recognised turbine-crash outcome. |
| [NSW RFS, common flammable liquids](https://www.rfs.nsw.gov.au/resources/publications/operational-procedures-and-guidelines/foundational/incidents-common-flammable-liquids); [USCG methanol response guide](https://www.dco.uscg.mil/Portals/9/DCO%20Documents/5p/LGCNCOE/docs/USCG%20RDC%20QRC%20B%20Methanol.pdf) | Methanol can burn with a flame that is invisible in daylight; responders must not rely on sight. | Glow fuel (methanol-based) shows no visible fire. It shows a wet fuel stain instead. |
| J. Preston, ["Safety Comes First"](https://library.modelaviation.com/article/safety-comes-first-67), *Model Aviation*, August 1985 | "With glow fuel you don't always see flames—you often see finishes turning dark brown very quickly." | Same as above. Glow is never a visible fireball. |
| NTSB full-size cases (exhaust/muffler cracks igniting fuel lines), e.g. [report 97240](https://data.ntsb.gov/carol-repgen/api/Aviation/ReportMain/GenerateNewestReport/97240/pdf) | A hot exhaust next to leaked fuel is a plausible ignition path. Full-size evidence, not RC. | Gasoline fire is possible but rare. It requires a ruptured tank, a hot running engine and a destroyed airframe. |
| LiPo hobby safety guides, e.g. [Unmanned Tech LiPo guide](https://www.unmannedtechshop.co.uk/pages/liposafety) and [Manoonpong LiPo safety sheet](https://manoonpong.com/Other/safetyLipoly.pdf) | After crash damage, move the pack to a safe place and observe it for at least about 30 minutes, because a damaged pack can heat and catch fire later. | A damaged pack vents smoke after a delay, not instantly. A flare appears only in the worst band. |
| [Pouch-cell nail penetration study (arXiv 2603.09254)](https://arxiv.org/pdf/2603.09254) | A slow nail did not cause thermal runaway in six large pouch cells; they self-discharged instead. | Not every damaged pack burns. Venting is gated by severity. |

## Gaps

- No source gives RC-specific crash fire rates or LiPo venting delays. The delay used (5–30 s, shorter for harder hits) is a presentation compression of the "observe for 30 minutes" advice, not a measurement.
- No source was found for gasoline RC crash fires specifically.
- Burn durations remain the CR-22a estimate (declared fuel / 0.035 kg/s, at most 50 s) for kerosene. Gasoline uses a faster 0.05 kg/s estimate.

## Rule set adopted (presentation)

| Source | Needs | Shows |
| --- | --- | --- |
| kerosene | hot running turbine, estimated rupture (C4, or a central C3 at ≥ 600 J) | fire with wind-drifted smoke (CR-22a, unchanged) |
| glow_fuel | estimated rupture | dark wet fuel stain, no flame |
| gasoline | engine running, C4, central impact | fire (faster burn); otherwise a fuel stain |
| lipo | C3+ central impact (the pack sits in the fuselage) | grey-white venting smoke after a severity-dependent delay; a short flare only at C4 with severity ≥ 0.8 |
| none / untagged | — | nothing |
