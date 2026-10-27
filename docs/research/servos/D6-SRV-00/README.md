# D6-SRV-00: servo load decisions and evidence

**Date:** 2026-10-27.

**Scope.** This record covers source review and the design decisions for the [servo load plan](../../../plans/servo-dynamics.md). Three things were not done: no runtime implementation, no bench test and no physical validation. The geometry re-derivation and the other D6-SRV-00 items listed in the plan remain open.

**Sources.** Each source is listed in the [manifest](sources.json), with URL, sha256 and license. Local copies are in the gitignored `references/servos/d6-srv-00/`.

## Owner input (2026-10-27)

The owner delegated decisions OD1–OD7 and settled three of them directly:

- **No wear between flights.**
- **Units of the same product reference are identical.** There is no per-unit scatter.
- **Manufacturers supply the data.** Manufacturer data replaces an owner bench as the primary parameter source.

## Findings

### Simulator practice

Every documented simulator models a servo as speed, rate, lag or a filter. None documents torque, load-dependent slowing, blowback, gear stripping or receiver brownout.

| Simulator | Servo model | Failures |
| --- | --- | --- |
| RealFlight G3.5 | One `SERVO SPEED` field (s/60°); "strength" exists only for wheel brakes | Probability events (reverse, stuck, trim, channel swap, lockout, interference, range), all enabled by default |
| JSBSim | Lag, rate, deadband, hysteresis, bias, limits | `fail_zero`, `fail_hardover`, `fail_stuck` set by property |
| ArduPilot SITL | 0.14 s/60° by default | — |
| YASim | Transition time; default 0, i.e. instantaneous | — |
| Aerofly | A speed-driven servo; an electrical actuator with voltage and current fields but no torque effect | — |

No servo documentation was found for Phoenix, ClearView, neXt or PicaSim. The loaded behavior planned here therefore has no documented precedent in RC simulation. It must be justified by physics and data, not by convention.

### Holding torque and the torque–speed line

**Hitec HS-755HB (2003 specification).**
- Standing torque 8.8 kg·cm at **5° hold-out**, which is 80 % of the 11 kg·cm stall torque at 4.8 V.
- Holding force therefore depends on position error. An analog servo has a proportional band of about 5°/0.8 ≈ 6.25° of shaft angle before it reaches stall torque.
- A fixed "holding torque multiplier" is the wrong model.
- Dead band 5 µs. Idle current 8 mA, no-load running current 230 mA, stall current 1500 mA.

**KST HS08 (2020 datasheet).**
- Rated torque is 0.15 N·m, a third of the 0.45 N·m stall torque, at 0.20 s/60°. No-load speed is 0.13 s/60°.
- A straight torque–speed line through no-load speed and stall torque predicts **0.195 s/60°** at rated torque, 2.5 % from the published value.
- Rated current 0.25 A against a stall current of 0.68 A also lies close to a line in torque.
- This is one product, not a general validation.

**Voltage.** The HS-755HB's speed, stall torque and stall current all rise by 1.20× from 4.8 to 6.0 V, a voltage ratio of 1.25. Pure proportional scaling would overstate them by about 4 %. A straight line through the two published voltage points reproduces them by construction.

### What manufacturers publish

| Status | Parameters |
| --- | --- |
| Published | Stall torque per voltage, no-load speed, operating voltage range, dead band, gear and motor type; stall current (Hitec, KST); idle and running current (Hitec) |
| Sometimes published | Rated torque and speed (KST), standing torque at a stated hold-out (Hitec 2003) |
| Not found in any datasheet | Gear-strip torque, back-drive torque, thermal/overload trip threshold and timing, servo cut-out voltage, small-signal time constant |

Overload protection is real but programmable: Hitec HFP-20 reduces torque by 10–50 %, factory default Off. A Pololu support reply calls back-drive torque "not a typical specification to give". No source was found for strip torque against stall torque by gear material. Hitec's claim that Karbonite gears are "four times stronger than nylon" has no stated method and was seen only on a retailer page.

### Receiver power

**Spektrum AR6335 (DSMX).**
- Below 3.5 V the system ceases to operate. With the transmitter on, it reconnects typically in about **0.04 s**.
- "Most servos cease to operate below 3.8 V."
- Brownout detection is not available in DSMX mode.

**Spektrum AR6110 (DSM2, 2009).**
- QuickConnect reconnects typically within a second. Below 3.5 V a reboot can take several seconds; a cold start takes 2–6 s.
- Power test: the voltage should stay above 4.8 V with every servo heavily loaded.

**Other receivers.** Futaba R7008SB, Jeti REX 12 and FrSky publish voltage ranges with a 3.5 V minimum, but no reboot time. Reconnect behavior is therefore a per-receiver datum, not a constant.

**Current.**
- One coreless digital servo was measured at 0.3 A holding and 1.3 A moving on average, with peaks of 5 A and 9.3 A (Model Aviation, 2017). Capacitance reduces the peaks.
- Those peaks are shorter than a 4.17 ms tick. A per-tick bus model sees averages, so a peak-current brownout needs either a separate peak law or manufacturer data.
- Example BEC limit: Castle CC BEC 2.0, 9 A continuous and 14 A peak.

### Flutter

- **NACA TN-4197** gives crude criteria for wing bending-torsion and stall flutter of missile surfaces. It treats control surfaces only qualitatively.
- **FAA AC 23.629-1A** gives statistically derived criteria for full-size airplanes below 260 kt EAS: aileron balance K/I, wing torsional flexibility, and free play below a specified maximum. Tab free play is 2 % or 1 % of tab chord. Its applicability to RC scale is not established.
- **RC practice sources** agree qualitatively:
  - slop is the main cause at high speed;
  - longer horns accentuate gear slop;
  - static balance is the usual remedy.
- No RC simulator was found that models flutter.

### Product names

The [licensing guide](../../../AIRCRAFT-LICENSING.md#trademarks-trade-dress-and-truthful-identification) already recommends three things:
- plain-text factual references;
- no logos unless cleared;
- no endorsement claims.

External sources agree:
- **INTA** describes nominative use: the product cannot readily be identified without the mark; only as much of the mark as needed, non-stylized; no suggestion of sponsorship.
- **EU Directive 2006/114/EC, Art. 4** requires objective comparison of material, relevant, verifiable and representative features, without denigration or confusion.
- **Game cases** separate a plain name from 3D likeness. 3D likeness was licensed or litigated: AM General v. Activision, then Jack Daniel's v. VIP limiting that defense. These are not legal advice and do not replace counsel for a branded release.

## Decisions

| # | Decision | Grounds |
| --- | --- | --- |
| OD1 | **Loaded response is part of an aircraft's physics, not a player option.** It applies per aircraft through the explicit `actuation.servo_load` capability. An aircraft adopts it only after D6-SRV-12 qualifies it, with an explained golden-flight re-record. Aircraft without the capability keep L1 byte-identical. There is no global "ideal servo" toggle. | Repository rules: goldens change only for an intentional, explained physics change, and stock activation is a separate gate (GP-16b/17b precedent). Other simulators keep servo speed always active, with no realism switch. |
| OD2 | **Servo damage is caused physics, not a failure injection.** The random-failure probability (default 0 %) does not gate it, because a crash is not gated either. Failure notices reuse the existing `notify` preference. A damage mode exists for a product **only** when its threshold comes from manufacturer data (`manual` or `measured`). No estimated strip or thermal threshold is used for a named product. Stall and blowback follow from published stall torque and stay active with the capability. | Strip, back-drive and thermal thresholds are unpublished. An invented threshold would show a real, partner-represented product failing at a level its maker never stated. The owner reports that manufacturers supply data. Tests use synthetic fixtures. |
| OD3 | **No per-unit scatter.** Every unit of a product reference uses the same parameters. | Owner decision. It also keeps replay and comparison simple: nothing is drawn at launch. |
| OD4 | **No wear or persistent servo state between flights.** | Owner decision. EM's default scope already excludes persistent wear. |
| OD5 | **Real products are named in plain text**, with their source and data date. A logo, stylized lettering, trade dress or 3D likeness requires written permission; Savox has product-representation permission. There is no "partner", "endorsed" or "better" label except the recorded Savox partner credit. Comparisons use objective values at stated voltage and load. A failure is described as an "undersized installation", never as a product defect. A stock aircraft installs the product its own source names when data exist; otherwise it installs a brand-neutral class record. | Licensing guide, INTA nominative-use conditions, EU Art. 4 objectivity, and the 3D-likeness game cases. |
| OD6 | **Manufacturer data is the primary parameter and validation source.** Import it through a request template and intake format. The owner bench is an optional cross-check. Commit only data the manufacturer authorizes for publication in this public MIT repository. Keep confidential raw files in gitignored `references/`, and publish only derived parameters that are permitted. | Owner input. The repository is public. Engineering data (curves, strip, thermal) is not public. |
| OD7 | **Flutter is out of scope.** There is no simulation and no numeric risk score. At most the Workshop shows sourced, qualitative setup guidance: slop and long horns increase risk at speed; static balance helps. | No validated control-surface flutter criterion exists at RC scale. TN-4197 does not apply. AC 23.629-1A is full-size and statistical. EM also excludes flutter. |

## Consequences for the plan

1. **Holding model.**
   - Replace the `k_hold` multiplier with a proportional band: `T = T_stall · min(1, e/e_sat)`, where e is the shaft position error. `e_sat` comes from published standing torque (HS-755HB: 5°/0.8) or from manufacturer data.
   - Above stall torque the servo is pushed back until `H(δ_eq)` equals stall torque.
   - Under partial load, a holding servo settles off command by `e = (T_load/T_stall) · e_sat`.
2. **Voltage law.**
   - Between published voltage points: a straight line through the published speed, stall torque and stall current. Pure proportional scaling is rejected (about 4 % error on the HS-755HB).
   - Below the lowest published point, during sag: scale proportionally from that point, labelled `derived`, down to the servo cut-out. The cut-out comes from manufacturer data; the "most servos below 3.8 V" statement is a `borrowed` fallback.
   - The nominal bus voltage must lie inside the published range.
3. **Brownout.** Receiver thresholds, glitch tolerance and reconnect time are per-receiver data. Spektrum DSMX: 3.5 V and about 0.04 s. Spektrum DSM2: up to several seconds.
4. **Scope changes.**
   - Per-unit scatter and wear are removed from the plan.
   - D6-SRV-13 becomes manufacturer-data intake and validation.
   - The data request covers:
     - torque–speed curves at each voltage;
     - idle, running and stall current;
     - standing torque and hold-out;
     - strip and back-drive torque;
     - thermal protection threshold and timing, or temperature against time at stall;
     - small-signal step response;
     - dead band;
     - frame rates;
     - cut-out voltage;
     - mass with and without cable and horn.
