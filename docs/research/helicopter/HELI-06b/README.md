# HELI-06b: Passive local airframe loads

**Date:** 2026-10-13. **Scope:** standalone fuselage, vertical-fin, and horizontal-tail loads with caller-supplied local wake velocities. The equations define a passive numerical extension; they do not qualify an aircraft or close the rotor wake.

## Source audit and selected signs

Gavrilets, Mettler, and Feron, [“Dynamic Model for a Miniature Aerobatic Helicopter”](https://users.encs.concordia.ca/~bwgordon/mit_heli_report.pdf), §§4.3–4.5, printed pp. 14–16, is the reference. The rendered pages are the cited source pages, not simulator output. The rigid-body equations on p. 4 put gravity in positive `ẇ`; the main-rotor force equation on p. 12 gives upward thrust as `Zmr = −T`; the air-relative velocity definitions on p. 6 subtract wind. Together these establish the paper’s forward/right/down force convention.

Several printed signs conflict with the stated conventions. Section 4.3’s initial low-speed and flat-plate `Xfus`/`Yfus` expressions have positive velocity terms despite describing drag that opposes motion; its final approximation gives negative terms. The same final approximation uses `wa + Vimr` for fuselage vertical speed, while tail-wake Eqs. 37 and 39 subtract `Kλ Vimr`. Section 4.5 Eq. 40 gives `Zht` the same sign as `wht`; with `+z` down, that makes its vertical force point with local vehicle-relative flow. This report records the equations as printed and treats all passive signs below as an explicit extension, not a claim about an erratum or an exact transcription. Gavrilets Eq. 35 already opposes fin side velocity. NASA’s [NDARC theory](https://ntrs.nasa.gov/api/citations/20160012474/downloads/20160012474.pdf) independently defines component velocity relative to air using body translation, `ω × r`, and subtracted air-interference velocities, then resolves aerodynamic drag opposite the velocity.

For each center of pressure, the caller supplies a wake-air velocity increment `v_wake` in body FRD. The local vehicle velocity relative to that air is

```text
vrel = vCG,air + ω × r − vwake
```

The selected forces are

```text
Ffus,i = −0.5 ρ Sfus,i vrel,i |vrel|
Fvf,y* = −0.5 ρ Svf (avf √(vrel,x² + vrel,z²) + |vrel,y|) vrel,y
Fht,z* = −0.5 ρ Sht (aht |vrel,x| + |vrel,z|) vrel,z
```

The vertical-fin force is capped at `0.5 ρ Svf |vrel|²`; the horizontal-tail force is capped at `0.5 ρ Sht (vrel,x² + vrel,z²)`. Each cap preserves its ideal force sign. Other surface-force axes are zero in this damping-only law. All component moments use `r × F`. Consequently each component satisfies `F · vrel ≤ 0`. Its power on the body may be positive when a supplied wake transfers energy: `Pbody = Prel + Pwake`, with `Prel = F · vrel` and `Pwake = F · vwake`.

## Reference and evidence

[`airframe.py`](../../../../research/helicopter/reference/airframe.py) requires all nine parameters and all five input vectors. `prepare` returns a flat read-only mapping with detached tuples; it has no aircraft defaults. Wake velocities are explicit and are not inferred from main- or tail-rotor states. The result includes component and total six-axis loads, local relative velocities, cap diagnostics, and relative/body/wake power.

[`airframe_oracle.json`](../../../../research/helicopter/reference/airframe_oracle.json) uses a numerical test fixture, not an aircraft profile. Its independent generator covers rest, three-axis drag, yaw and pitch damping, force caps, backward flow, full point-rate kinematics, and wake-to-body power transfer. Run from the repository root:

```powershell
python research/helicopter/reference/test_airframe.py
python research/helicopter/reference/make_airframe_oracle.py --check
```

These checks establish implementation consistency and the stated passivity properties only. No airframe flight data or physical validation is claimed.
