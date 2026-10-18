# FT-03: card v3 fleet baseline on the D10-R2 tree, diagnostics and measured-RC comparison

2026-10-18 · **Status: `ft-card-v3` baseline of all eight fixed-wing aircraft with D10-R2 applied. It is deterministic, `--diagnostics` is read-only, and the D10-R2 change only moves the four Stik variants. The fleet was compared with flight- and tunnel-measured RC-class data. Four findings go to their owning tracks.** [Tool, card and workflow](../../../../research/flight-test/README.md); previous baseline [FT-01](../FT-01/README.md) (card v2).

## Baseline

| Item | Value |
| --- | --- |
| Tree | `349984ba` with D10-R2 applied in the working tree ([run.json](run.json) lists the dirty paths and every aircraft's data SHA-256) |
| Engine and conditions | Godot 4.7.2 official, Linux headless, 240 Hz; calm standard air |
| Aircraft | Every fixed-wing catalog aircraft (eight) |
| Runtime | 155–443 s per aircraft (the glow Stiks are slowest) with 4 parallel jobs |

Each aircraft folder holds `profile.md`, `profile.json` and `run.log`; the CSV traces regenerate with `run.py`. These are model predictions, not physical validation. Compare a later candidate against this folder with `compare.py`.

## Verification

- **Same result as the verified D10-R2 copy.** On the main tree, the full card gives exactly the same result as the disposable D10-R2 copy that passed the whole `app/test.sh`. The comparison is at zero tolerance over all eight aircraft, with identical data SHA-256 ([report](verification/main-equals-verified-copy.md)). Two complete v3 runs therefore agree, which also shows the card is deterministic.
- **`--diagnostics` is read-only.** A Stik run with and without the flag compares with zero changes ([report](verification/diagnostics-read-only.md)). Adding the diagnostics code with the flag off also changes nothing ([report](verification/diagnostics-patch-determinism.md)). The 20 Hz diagnostic blend reproduces the production loads with zero residual over 9438 Stik rows ([D10-R2 evidence, section 7](../../flight-dynamics/stik-lateral-directional-2026-10-18/README.md#7-knife-edge-the-ft-batterys-finding-measured-in-flight)).
- **D10-R2 moves only the Stik variants** ([report](verification/d10r2-base-to-candidate.md)). The Extra, P-51, Ventage and Timber show zero changes. The electric Stik shows 157 changes and the three glow Stiks 144–149. The main ones:
  - hands-off heading change after 30 s falls from 374° to 32°, and height change from −88.8 m to +1.2 m, because the spiral is now stable;
  - Dutch roll ζ is 0.33;
  - Cnβ in `aero_sweep` is about 45 % lower at every sideslip.
  - The full-rudder knife-edge sinks faster (−12.7 against −5.6 m/s at full throttle, left) at 20.7° of sideslip instead of 17.2°. This exposes the side-force gap described in the D10-R2 evidence.

## Against measured RC-class data

Sources, caveats and local copies: [RC-class aerodynamic data sources](../../flight-dynamics/rc-aero-data-sources.md). Every reference is another airframe, so these comparisons screen magnitudes; they are not acceptance bands.

- **Spin** ([table](spin-state.md), from `spin_state.py`). The references are NASA FASER (Ultra Stick 120) and the UIUC Aero Testbed (35 % Extra 260), with the same entry.
  - The model matches their Ωb/2V (0.16–0.19 against 0.14–0.20), their roll rate and the FASER airspeed scaled by wing loading.
  - Both references yaw faster (150–160 against 78–112°/s) at higher α (about 30–35° against 19–23°).
  - The Extra 260 holds far more vertical force: coefficient 0.74–0.86 against the model Extra's 0.25.
- **Lift and drag** ([table](polar-fit.md), from `polar_fit.py`).
  - The Stik's CL at α 0 and CLα (0.107, 0.0799/deg) are within 5 % of the FASER tunnel (0.113, 0.0762/deg).
  - The fleet's CDmin (0.029–0.043) and e (0.75–0.79) lie in the measured small-UAV range. The fit needs the offset CL at least drag; without it, the cambered Stik and Timber give e of about 1.7, a fitting artifact.
  - Idle glides add 0.003–0.024 to CD for idle propeller and trim drag, the order Southampton measured for stopped propellers (0.01–0.03).
- **Static lateral derivatives.** These come from `aero_sweep` at 5° of sideslip.
  - The Avanti (CYβ −0.90, Clβ −0.138, Cnβ 0.187) is close to NASA's flight-identified T-2 jet at α 4° (−0.83, −0.149, 0.191).
  - Every Cnβ lies in the identified 0.046–0.167 range. The other aircraft give (CYβ, Clβ, Cnβ):
    - Stik −0.53, −0.079, 0.062;
    - Extra −0.52, −0.024, 0.162;
    - P-51 −0.46, −0.064, 0.046;
    - Timber −0.32, −0.080, 0.049.

## Findings for the owning tracks

1. **Post-stall spin (physics).** Against both measured spins, the developed spin is roll-dominated and too steep, with about a third of the vertical force. The card window is about three turns in, and airspeed still rises about 1 m/s per second, so a longer pro-spin hold should come first.
2. **Stopped propeller drag (propulsion).** [`propulsion.gd`](../../../../app/physics/propulsion.gd) returns zero loads for a non-glow propeller below 1 rpm.
   - The Timber's propeller stops in its idle glide, which flies at L/D 13.9.
   - Hartman and Biermann's locked-propeller data (NACA Report 641) predict ΔCD ≈ 0.017 for its 11×7.3 three-blade propeller, so L/D would be about 10.9.
   - The same method predicts the FliTePlat's measured increment.
   - A free-wheeling propeller drags less than a locked one, so a locked stop is the upper case.
3. **Stik dihedral effect (D10 follow-up).** Clβ at trim α is −0.079, twice the Ultra Stick 25e's flight-identified −0.039; the data's base value is −0.0545.
4. **Glow idle (glow engines; FT-01 finding 2).** The glow Stiks still turn 5,000–8,800 rpm at idle in the glide and do not descend at 1.3 and 1.6 Vs.

## Limits

- The references are other airframes and conditions.
- Several values are read from figures.
- The FASER spin is a video-corrected estimate.
- The full-scale propeller data understate blade drag at RC Reynolds numbers.
