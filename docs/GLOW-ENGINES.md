# Glow engine installations

The catalog has three experimental finite-fuel Stik variants (`stik-glow-55ax-2t`, `stik-glow-fs64v-4t`, `stik-glow-61fx-2t`) and the finite-glow Extra `gp-extra-300s-60`. The MAX-61FX Stik is a separate configuration based on the engine fitted to the reference Stik; the base Stik retains prescribed fuel. These estimates have software evidence, but no completed matched bench, flight or pilot validation. See the [active NITRO plan](plans/RC_NITRO_ENGINE_REALISM_PLAN.md), [fuel standard](FUEL-SYSTEM.md) and the [aircraft contract](AIRCRAFT_CONTRACT.md).

## Fly and configure

Select a finite-glow Stik or the Extra in the catalog. For direct launch, append this suffix to the engine command in [TOOLS](TOOLS.md):

```text
-- --quick-flight --aircraft=stik-glow-61fx-2t
```

Use `stik-glow-55ax-2t` or `stik-glow-fs64v-4t` for the other engine families. Airborne starts use a warm trimmed engine. Runway starts leave the warm engine stopped; press **F7** to start it. **F6** cuts combustion, **F8/F9** lean or richen the mixture, and zero throttle requests idle. Opening the throttle does not restart a cut or stalled engine. The HUD shows RPM, remaining fuel, head-temperature proxy and engine status.

Start fill, reset/checkpoint policy, live mass/CG and remaining-fuel diagnostics follow the [shared fuel guide](FUEL-SYSTEM.md#launch-restoration-and-observation). Fuel burn can change trim as the tank empties. Selecting a fill does not enable consumption in an aircraft without a finite-fuel adapter.

## Supported variants and data

| Catalog ID | Engine | Main propeller | Generated alternate |
| --- | --- | --- | --- |
| `stik-glow-55ax-2t` | O.S. MAX-55AX, 2-stroke | APC Sport 12×7 | APC Sport 13×6 |
| `stik-glow-fs64v-4t` | O.S. FS-64V, 4-stroke | Master Airscrew K Series 14×6 | APC Sport 13×6 |
| `stik-glow-61fx-2t` | O.S. MAX-61FX, 2-stroke | APC Sport 12×6 | — |
| `gp-extra-300s-60` | O.S. MAX-61FX, 2-stroke | APC Sport 12×6 | — |

The 61FX profile is scaled from the 55AX data; it is not a matched 61FX measurement. Engine curves, propeller fits, installation values and fuel-feed pressures include estimates. Manufacturer limits and model support ranges are not interchangeable; use the [2-stroke](research/glow-engines/NITRO-2T/README.md), [4-stroke](research/glow-engines/NITRO-4T/README.md) and [61FX](research/glow-engines/NITRO-61FX/README.md) dossiers for provenance, supported combinations and caveats.

Finite glow fuel is admitted only by an explicit `propulsion.engine.glow_installation` and `capabilities.energy: finite_glow_fuel`. The historical `glow_prop` solver name alone does not select glow chemistry or finite consumption. Profiles and installations are generated from [`research/glow-engines/build_profiles.py`](../research/glow-engines/build_profiles.py) and [`build_installations.py`](../research/glow-engines/build_installations.py); edit those sources and regenerate rather than changing generated JSON. Each runtime quantity retains its unit and evidence source.

The throttle is a flow restriction (NITRO-06): the stick positions the barrel, whose lens-shaped opening admits air through a nozzle that chokes at small openings, so the charge per cycle falls with the engine speed when the throttle is closed and the idling engine neither pulls nor over-speeds in a glide. Each installation carries the three quantities of that law (`throttle_effective_area_m2`, `idle_opening`, `throttle_travel_exponent`, format `openrc-glow-installation v2`), derived from estimates and one dynamometer figure as the [NITRO-06 evidence](research/glow-engines/NITRO-06/README.md) records; the static rpm against the stick is a prediction, not a measured curve.

Launch trim searches the complete supported RPM mesh and selects the highest bracketed
restoring root. Engine and propeller preparation is reused within each search; the
[NITRO-04 trim evidence](research/glow-engines/NITRO-02/README.md#cruise-trim-preparation-nitro-04-2026-10-26)
records exact-result comparisons and local timing improvements.

The two-stroke and four-stroke paths use separate mean-cycle models, transport, combustion events and thermal feedback. The installed propeller model is a passive axial-flow surrogate with shaft reaction and windmilling support. An installation may give its section a cambered zero-lift angle (`propeller.zero_lift_angle_rad`, EX-14f), fitted to measured APC Sport data by `research/glow-engines/fit_section.py`; the Extra's installation does. An aircraft may add the propeller normal force, P-factor and the quasi-static tail slipstream, composed with the shaft through the stage's own thrust and torque (EX-14c); the transported wake is refused. It does not model measured crank torque ripple, reverse breakaway or fuel slosh. The [NITRO plan and evidence](plans/RC_NITRO_ENGINE_REALISM_PLAN.md) record software checks and open work; matched engine/propeller/fuel measurements, experienced-pilot review, target performance and physical accuracy remain acceptance gates.
