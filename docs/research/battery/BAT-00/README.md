# BAT-00 — Battery realism source review

2026-10-19 · **Status:** dated research snapshot for the [battery realism plan](../../../plans/battery-realism.md). Sources were read on 2026-10-19; no pack in the simulator is measured. Manifest: [sources.json](sources.json). Local copies: gitignored `references/battery-energy/`.

This record adds new sources to the earlier [EL1a-R1 battery investigations](../../propulsion/EL1a-R1/02-battery.md) and the [DR-01 battery notes](../../drone-racing/DR-01/README.md). It does not repeat them.

## Findings that change the plan

| # | Source | Finding | Plan consequence |
| --- | --- | --- | --- |
| F1 | Tremblay & Dessaint 2009 (EVS24) | Modified Shepherd model: `V = E0 − R·i − K·Q/(Q−it)·(it + i*) + A·exp(−B·it)`. It uses a filtered current `i*` and three datasheet points per chemistry, with examples for Li-ion, NiMH, NiCd and lead-acid. | A **datasheet tier** for packs that have only a published discharge curve (BAT-05). It ranks below measured ECM fits and is labeled `derived`. |
| F2 | Guo et al. 2016 (Sci. Rep., CC BY) | Over-discharge stopped early showed no discernible change. A plateau appears near −12 % SOC, and past it Cu dissolution and redeposition cause an internal short. The tested cells are large-format, not RC LiPo pouches. | This is the only mechanism-anchored threshold for the **severe** damage band (BAT-21). Mild-band magnitudes stay `estimated`. |
| F3 | Saha et al. 2011 (NASA) | 33 % Edge 540T: four 18.5 V 6 Ah Li-Po packs, current pulses up to ~80 A, voltage recovery after load steps, per-pack V/I/T logged at 30 Hz, and a 2 min landing margin on predicted end of discharge. | RC-scale evidence that relaxation (an RC state) is visible in flight loads. It also shapes the remaining-time alarm. No raw data were found. |
| F4 | Nyangweso & Bole 2014 (NASA) | Pack test bed with 5S2P pouch packs, per-cell thermocouples and emulated flight loads. | Template for the owner's pack characterisation card (BAT-27). |
| F5 | Galeotti et al. 2023 (Data in Brief, CC BY) | Free Li-Po cell dataset (1.1 Ah, 25 °C): capacity, rested partial-discharge ladder, EIS and a fitted R0 + 2·(R‖CPE) + Warburg + L model to 70 % SOH. | Free source for the **LiPo template** OCV/R0 trends and the R0-versus-SOH direction (BAT-05). The cell is small, so its scale needs a stated conversion. |
| F6 | PX4 battery docs | Remaining capacity uses load-compensated voltage with an internal-resistance estimate (typically 5 mΩ/cell). | The HUD's "remaining %" must be a **radio-side estimate**, not the simulator's true SOC (BAT-14). |
| F7 | Betaflight battery docs | Cell count is auto-detected from a maximum per-cell voltage (4.30 V), with separate warning and critical per-cell thresholds. | Cell-count detection and misdetection are part of the ESC/FC supervisor (BAT-11, BAT-24). |
| F8 | EdgeTX manual | Sensors are pack voltage, current, consumed mAh and cell voltages. The calculated `Cell` formula with index `Lowest` shows the weakest cell. | Sensor names and semantics for telemetry emulation (BAT-14) and the flight-log reducer (BAT-28). |
| F9 | Molicel P42A (reseller) | 21700 Li-ion: 4.2 Ah, 2.5 V cutoff, 30 A continuous (45 A only with 80 °C monitoring), about 16 mΩ DC. | Li-ion trades higher sag for endurance. Fetch the official datasheet before use (BAT-01). |
| F10 | UAF thesis (LiCoO2 polymer, to −20 °C) | Apparent cold capacity loss comes mainly from higher internal resistance. | Keep coulombic capacity independent of temperature. Cold "capacity loss" emerges from R0(T) plus the cutoff (BAT-07). |

## Values already in the repository (not re-searched)

- EL1a-R1: Suti 2022 (6S Li-Po HPPC, OCV hysteresis about 5 mV) and Di Nisio 2023 (4S 10 Ah, 20.68 mΩ, low-rate only).
- The Avian ESC family offers LVC at 2.8–3.8 V/cell, auto or fixed cell count, and a soft cut of 50 % over 3 s; its troubleshooting section says 60 %. The Timber manual sets 3.4 V/cell as a **transmitter alarm**, not the ESC cutoff.
- Roadmap investigation 05: Hobbywing Skywalker V2 LVC options off/2.8/3.0/3.4 V/cell and a soft cut to 60 % in 3 s.
- DR-01: Bauersfeld & Scaramuzza (4.5 mΩ/cell minimum, τ_RC 3.3 s, 43 mV RMSE). Fresh racing packs measure 2–6 mΩ/cell (community figure). MultiGP allows 4.35 V/cell (LiHV).
- EM-00 R02: Spektrum AR410 receiver is inoperative below 3.5 V.

## Dead ends and open checks

- The Mendeley public API returned non-JSON for the Galeotti dataset. Download it through the web page and record the licence (BAT-01).
- No public measured OCV–SOC table exists for an RC flight pack class (this confirms DR-01).
- No raw Edge 540 flight battery data was found. The NASA papers have figures only.
- The Kollmeyer HG2 licence is unconfirmed. The BPX repository licence is unrecorded.
- LiFePO4 and NiMH class voltages in the plan's chemistry table are conventions. BAT-01 must cite a datasheet for each before any template uses them.
