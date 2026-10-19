# Glow engine installations

The aircraft catalog has three experimental finite-fuel Stik variants: `stik-glow-55ax-2t`, `stik-glow-fs64v-4t` and `stik-glow-61fx-2t`. The MAX-61FX variant is a separate configuration based on the engine fitted to the reference Stik; the base Stik remains on its legacy prescribed-fuel model. These estimates have software evidence, but no completed matched bench, flight or pilot validation. See the [active NITRO plan](plans/RC_NITRO_ENGINE_REALISM_PLAN.md), [fuel plan](plans/fuel-mass-balance.md) and the [aircraft contract](AIRCRAFT_CONTRACT.md).

## Fly and configure

Select a glow Stik in the catalog. For direct launch, append this suffix to the engine command in [TOOLS](TOOLS.md):

```text
-- --quick-flight --aircraft=stik-glow-61fx-2t
```

Use `stik-glow-55ax-2t` or `stik-glow-fs64v-4t` for the other engine families. Airborne starts use a warm trimmed engine. Runway starts leave the warm engine stopped; press **F7** to start it. **F6** cuts combustion, **F8/F9** lean or richen the mixture, and zero throttle requests idle. Opening the throttle does not restart a cut or stalled engine. The HUD shows RPM, remaining fuel, head-temperature proxy and engine status.

Open **More flight details** on Home to choose a starting tank fill: full, 75%, 50% or 25%. Full is the default. The direct-flight option is `--fuel=<fraction>` where `0 < fraction <= 1`, for example `--fuel=0.5`. The selector is available for finite-fuel catalog entries. In the current tree, the P-51 data declares an estimated gasoline consumption law and the Ventage Jet data a turbine fuel-flow map; the [fuel plan](plans/fuel-mass-balance.md) records their remaining integration and validation gates. Selecting a fill does not enable consumption for another aircraft. Home keeps the choice while switching aircraft in that menu.

Fuel burn changes live mass, center of gravity and inertia, so neutral controls do not guarantee a steady flight as a tank empties. `FlightSession.mass_properties()` supplies the accepted-state sample used by presentation and crash consumers. For glow, `GlowFlight.properties()` evaluates the shared `MassInventory.evaluate_reference()` model; `FixedDatumBody.derivative()` applies the fixed-datum dynamics. The tank moves no geometry, and the model does not include slosh or exhaust thrust.

## Supported variants and data

| Catalog ID | Engine | Main propeller | Generated alternate |
| --- | --- | --- | --- |
| `stik-glow-55ax-2t` | O.S. MAX-55AX, 2-stroke | APC Sport 12×7 | APC Sport 13×6 |
| `stik-glow-fs64v-4t` | O.S. FS-64V, 4-stroke | Master Airscrew K Series 14×6 | APC Sport 13×6 |
| `stik-glow-61fx-2t` | O.S. MAX-61FX, 2-stroke | APC Sport 12×6 | — |

The 61FX profile is scaled from the 55AX data; it is not a matched 61FX measurement. Engine curves, propeller fits, installation values and fuel-feed pressures include estimates. Manufacturer limits and model support ranges are not interchangeable; use the [2-stroke](research/glow-engines/NITRO-2T/README.md), [4-stroke](research/glow-engines/NITRO-4T/README.md) and [61FX](research/glow-engines/NITRO-61FX/README.md) dossiers for provenance, supported combinations and caveats.

Finite glow fuel is admitted only by an explicit `propulsion.engine.glow_installation` and `capabilities.energy: finite_glow_fuel`. The historical `glow_prop` solver name alone does not select glow chemistry or finite consumption. Profiles and installations are generated from [`research/glow-engines/build_profiles.py`](../research/glow-engines/build_profiles.py) and [`build_installations.py`](../research/glow-engines/build_installations.py); edit those sources and regenerate rather than changing generated JSON. Each runtime quantity retains its unit and evidence source.

The two-stroke and four-stroke paths use separate mean-cycle models, transport, combustion events and thermal feedback. The installed propeller model is a passive axial-flow surrogate with shaft reaction and windmilling support. It does not model measured crank torque ripple, propeller side force/P-factor, wake interaction, reverse breakaway or fuel slosh. The [NITRO plan and evidence](plans/RC_NITRO_ENGINE_REALISM_PLAN.md) record software checks and open work; matched engine/propeller/fuel measurements, experienced-pilot review, target performance and physical accuracy remain acceptance gates.
