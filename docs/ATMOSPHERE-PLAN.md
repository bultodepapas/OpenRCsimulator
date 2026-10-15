# Field atmosphere

2026-10-14 · Step prefix: **M5-ATM** · **Status: M5-ATM-1/2, the first M5-ATM-3 shaft correction and the M5-ATM-4 dry reference column implemented. Focused software checks pass; physical and full release acceptance remain open.**

Owns `app/physics/atmosphere.gd`, weather-v3/v4 atmosphere settings, shared density/charge integration, and atmosphere tests/evidence. Coordinate UI, propulsion and field definitions with their owners. The geometric field elevation anchors the atmosphere; it does not move the rendered terrain or redefine NED/AGL geometry.

| Step | Delivery | Proof/status |
| --- | --- | --- |
| M5-ATM-1 | Strict field-level ISA/QNH, liquid-water Buck and ideal moist-air density; separate literal reference state | [Kernel and primary-source checks](research/atmosphere/M5-ATM-1/kernel/README.md), 29 checks; reference mode stays exactly 1.225 kg/m³, custom mode derives density from field conditions |
| M5-ATM-2 | One density through trim, aero, propeller, shaft load, wash, runway, HUD and v6 traces; v3 environment checkpoints; EN/ES UI with precise linked sliders | [Integration evidence](research/atmosphere/M5-ATM-2/README.md): complete 140-suite gate, fleet equilibrium, restart/rollback/replay, independent telemetry, 25 captures, Linux/source parity and observed cost |
| M5-ATM-3 | Apply dry-air charge ratio to the existing naturally aspirated shaft model; keep friction fixed | Implemented and software verified as an estimated first-order correction; no measured altitude-engine acceptance. RPM-lag and turbine retain their own current laws |
| M5-ATM-3b | Measured per-powerplant environmental response | Pending; actual engine/ECU/fuel maps and held-out data |
| M5-ATM-4 | Explicit in-flight dry ISA density profile | [Kernel](research/physics-audit-2026-10-14/remediation/R09/README.md) and [stage integration](research/physics-audit-2026-10-14/remediation/R09/integration.md) implemented; −500…11000 m geometric altitude, no extrapolation. Measured soundings and rotorcraft adoption remain pending. |

Weather v3 contains the complete v2 wind/turbulence settings plus `atmosphere_mode`, `field_elevation_m`, `temperature_c`, `qnh_hpa`, `relative_humidity_pct`. Reference mode uses literal legacy density/charge and retains custom draft parameters. Custom mode uses geometric elevation −500…4000 m, temperature −20…45 °C, QNH 870…1085 hPa and RH 0…100% relative to liquid water. Below freezing this is a supercooled-water convention, not an ice-RH conversion.

Pressure follows the standard ISA altimeter reduction from QNH after geometric→geopotential conversion. Temperature is the ambient field input. This is a station-pressure estimate, not an observed vertical weather profile. Density is `(p−e)/(Rd*T)+e/(Rv*T)`. Aero/propeller use total moist density; the shaft engine's indicated torque uses dry-air charge density relative to its assumed reference, with friction unchanged. That separates oxygen displacement from aerodynamic mass density. Existing turbine density/ram maps and prescribed-RPM glow models remain approximations; no generic engine power multiplier is applied.

Initial catalog speed remains TAS. The six-axis solver refits at the selected density; an infeasible trim refuses flight. EAS is `TAS*sqrt(rho/1.225)` and is not an IAS/pitot calibration. Density altitude is a display equivalent in the standard atmosphere; it is not added to physical altitude. Gravity and aerodynamic coefficient/Reynolds assumptions remain unchanged.

Reference and uniform modes retain their density behavior. Active custom atmosphere uses trace v6, metadata v5 and checkpoint v3 unless a propulsion/gear extension requires a later version. The independent R02 aerodynamic repair intentionally changes the force/wake law and its goldens; it is not an atmosphere migration. Weather/config identity is frozen with recording, malformed telemetry fails, and restore preflights environment/model/layout before mutation.

Weather v4 adds `standard_column`: dry ISA pressure, temperature and density at geometric altitude `field_elevation_m - NED_down`, sampled at each body integration stage. Field elevation remains active; custom temperature/QNH/RH remain validated inert drafts. The profile is a controlled reference, not observed meteorology. Column traces use v11 with separate endpoint and k1 atmosphere fields; column checkpoints identify the law. Preferences use schema 5 for weather v4; older weather/lighting combinations retain schemas 1–4. The fixed-wing family adapters are integrated; rotorcraft explicitly refuses this mode until qualified.

Hot-and-high and cool-dense presets are authored practice conditions. Software proves equations and consistency, not actual site meteorology, aircraft coefficients, calibrated power loss or pilot behavior. Full desktop/pilot and 500 µs acceptance stay open.


The conditions editor pairs 14 sliders with exact numeric inputs. Dragging quantizes only the selected control to its displayed step; untouched and typed values keep their source precision. The seed stays an integer entry. Active-tab focus, wheel-safe scrolling, disabled reference controls and 800×600 EN/ES layout are regression checked. This product addition is part of M5-ATM-2 and preserves all earlier wind/turbulence controls.
