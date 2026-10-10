# Field atmosphere

2026-10-09 · Step prefix: **M5-ATM** · **Status: M5-ATM-1/2 and the first M5-ATM-3 shaft correction implemented and software verified, including 14 linked menu sliders. Physical, performance and Windows/macOS native acceptance remain open.**

Owns `app/physics/atmosphere.gd`, weather-v3 atmosphere settings, shared density/charge integration, and atmosphere tests/evidence. Coordinate UI, propulsion and field definitions with their owners. The geometric field elevation controls the pressure estimate; it does not move the rendered terrain or redefine NED/AGL geometry.

| Step | Delivery | Proof/status |
| --- | --- | --- |
| M5-ATM-1 | Strict field-level ISA/QNH, liquid-water Buck and ideal moist-air density; separate literal reference state | [Kernel and primary-source checks](research/atmosphere/M5-ATM-1/kernel/README.md), 29 checks; default density stays exactly 1.225 |
| M5-ATM-2 | One density through trim, aero, propeller, shaft load, wash, runway, HUD and v6 traces; v3 environment checkpoints; EN/ES UI with precise linked sliders | [Integration evidence](research/atmosphere/M5-ATM-2/README.md): complete 140-suite gate, fleet equilibrium, restart/rollback/replay, independent telemetry, 25 captures, Linux/source parity and observed cost |
| M5-ATM-3 | Explicit dry-air charge multiplier for the existing naturally aspirated shaft model; friction fixed | Estimated first-order correction; algebra/equilibrium tests, no measured altitude-engine acceptance. RPM-lag and turbine retain their own documented laws |
| M5-ATM-3b | Measured per-powerplant environmental response | Pending; actual engine/ECU/fuel maps and held-out data |
| M5-ATM-4 | Vertical sounding / in-flight density profile | Deferred; field density is uniform throughout the current flight |

Weather v3 contains the complete v2 wind/turbulence settings plus `atmosphere_mode`, `field_elevation_m`, `temperature_c`, `qnh_hpa`, `relative_humidity_pct`. Reference mode uses literal legacy density/charge and retains custom draft parameters. Custom mode uses geometric elevation −500…4000 m, temperature −20…45 °C, QNH 870…1085 hPa and RH 0…100% relative to liquid water. Below freezing this is a supercooled-water convention, not an ice-RH conversion.

Pressure follows the standard ISA altimeter reduction from QNH after geometric→geopotential conversion. Temperature is the ambient field input. This is a station-pressure estimate, not an observed vertical weather profile. Density is `(p−e)/(Rd*T)+e/(Rv*T)`. Aero/propeller use total moist density; the shaft engine's indicated torque uses dry-air charge density relative to its assumed reference, with friction unchanged. That separates oxygen displacement from aerodynamic mass density. Existing turbine density/ram maps and prescribed-RPM glow models remain approximations; no generic engine power multiplier is applied.

Initial catalog speed remains TAS. The six-axis solver refits at the selected density; an infeasible trim refuses flight. EAS is `TAS*sqrt(rho/1.225)` and is not an IAS/pitot calibration. Density altitude is a display equivalent in the standard atmosphere; it is not added to physical altitude. Gravity and aerodynamic coefficient/Reynolds assumptions remain unchanged.

Default/reference flights preserve legacy traces v3/v4/v5, checkpoints v1/v2 and unaided golden physics. Active custom atmosphere uses trace v6, metadata v5 and checkpoint v3. Weather/config identity is frozen with recording, malformed telemetry fails, and restore preflights environment/model/layout before mutation. Preferences v3 advertise outer schema 3; v1/v2 still save schemas 1/2 so older readers cannot overwrite new settings.

Hot-and-high and cool-dense presets are authored practice conditions. Software proves equations and consistency, not actual site meteorology, aircraft coefficients, calibrated power loss or pilot behavior. Full desktop/pilot and 500 µs acceptance stay open.


The conditions editor pairs 14 sliders with exact numeric inputs. Dragging quantizes only the selected control to its displayed step; untouched and typed values keep their source precision. The seed stays an integer entry. Active-tab focus, wheel-safe scrolling, disabled reference controls and 800×600 EN/ES layout are regression checked. This product addition is part of M5-ATM-2 and preserves all earlier wind/turbulence controls.
