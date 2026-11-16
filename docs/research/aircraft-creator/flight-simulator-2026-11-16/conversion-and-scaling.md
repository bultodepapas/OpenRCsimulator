# Flight-model conversion and RC scaling specification

**Date:** 2026-11-16. **Status:** research-backed proposed design for AC-FS; no converter or flight qualification delivered. The [feature plan](../../../plans/flight-simulator-aircraft-import.md) owns implementation. This document separates documented source semantics, OpenRC's existing contracts, and engineering derivations. [Primary-source register](sources-and-examples.md#physics-and-units-sources).

## Conversion modes and destination boundary

The first usable workflow is **guided RC authoring**. Preserve the original full-scale configuration as reference, propose supported geometry/unit conversions, and construct a new target inventory and equipment installation inside a qualified Creator package. Later dynamic-similarity estimates and parameter fitting must carry their own assumptions and validation domains. Full-scale reference mode does not authorize launching a full-sized aircraft through the trainer compiler.

Final output remains ordinary `openrc-aircraft v2`. Each quantity is exactly `{value, unit, kind, source}`; recognized kinds are `manual`, `measured`, `borrowed`, `estimated`, `derived`. Detailed source paths, raw values, uncertainty, mapping status and field history belong in versioned Creator source/authoring records, not extra keys silently added to the closed physical schema. [OpenRC contract](../../../AIRCRAFT_CONTRACT.md#presence-evidence-and-defaults)

A faithfully extracted simulator parameter is not automatically a physical measurement. A unit-converted source declaration retains its original evidence and is normally borrowed/derived when adopted; a modeled RC effect is estimated. User confirmation records an adoption decision, not an upgrade to measured truth. Missing, invalid, inactive, unresolved and zero remain distinct.

This is a proposed adoption contract. Current Creator `Definition` accepts only `manual`, `measured` and `estimated` authoring evidence and generates generic source strings; its compiler strips `source_observations` before physical emission. AC-FS-02/07 must version Definition, Compiler, UI, Store and readers so an adopted value's evidence and source reference survive into the physical quantity. A versioned observation envelope alone cannot do that. Keep adoption unavailable until exact-byte compile/save/reopen and independent definition-to-physics correspondence checks pass. [Current definition](../../../../app/workshop/creator/definition.gd), [compiler](../../../../app/workshop/creator/compiler.gd)

## Field mapping and dispositions

Use a versioned mapping registry with these attributes: source family and field dialect; effective section/key and duplicate/override precedence; raw units/order/reference; conditions under which the source field is active; normalization equation; target meaning; evidence classification; refusal/confirmation rule; and an independent known-answer fixture.

MSFS can split configuration sections across files or retain them in `aircraft.cfg`; resolve the effective source rather than assuming a separate `flight_model.cfg` always exists. The modern/legacy FDM selectors and custom-runtime indicators must be captured before any aerodynamic interpretation. [P1](sources-and-examples.md#physics-and-units-sources), [F05](sources-and-examples.md#format-and-package-sources)

| Source information | Normalized observation | Proposed OpenRC disposition |
| --- | --- | --- |
| `[FLTSIM.n]` identity, model and texture selection | Explicit selected variant and dependency paths | Display/provenance only; source title does not select a runtime law |
| `wing_span`, `wing_area`, `wing_root_chord` | Metres/metres squared with source semantics | Propose Creator geometry after source-scale and planform review; no direct record patch |
| Wing sweep, taper, twist, dihedral, incidence | Geometric facts separated from virtual/tuning effects | Adopt only inputs represented by the selected law; unsupported sweep/twist cannot be hidden by a trainer substitution |
| Horizontal/vertical tail geometry | Areas, spans, positions and moving-surface inclusion | Reconcile source area conventions with target combined surfaces; avoid counting elevator/rudder area twice |
| `reference_datum_position`, `empty_weight_CG_position` | Explicit source origins and empty CG | Preserve reference; target CG comes from selected RC components, not copied passenger/fuel arrangement |
| `empty_weight`, `max_gross_weight`, `station_load.N` | Empty/maximum/loaded mass roles, kg | Reference and inventory consistency targets. Never treat maximum gross mass as current mass or distribute payload invisibly |
| Legacy scalar MOIs and `empty_inertia_tensor` | Tensor with unit, axes, origin, validity and selected precedence | Reference/fitting target; derive target inertia once from the OpenRC inventory |
| Airfoil name, lift/drag tables and moment derivatives | Active source-law data with normalization and domain | Initially reference-only unless an equation-level mapping exists; later fitting/derivation must be explicit |
| Elevator/aileron/rudder limits, effectiveness and source mixer | Travel, mechanical timing, aerodynamic effect and pilot input separated | Confirm actual RC throws, servo response and supported control topology; source animation/control signs are not automatically target signs |
| Engine type, rated power, propeller diameter/pitch/RPM and locations | Source installation and curves | Select supported RC motor/ESC/battery/propeller explicitly; rated HP is not a thrust curve |
| `point.N` contact data | Typed contact locations and heterogeneous per-column units | Reference/proposals only until AC-21 and the matching GP law can author them |
| Runway/start speed, weather, camera and controller settings | Source operating context | Do not overwrite OpenRC environment/device/start policy; selected target start is checked independently |
| Prose performance descriptions | Informational text with source path | Never authoritative numeric input; the inspected C-17 has conflicting prose and structured mass values |

Source semantics: [P3–P7, P10, P12](sources-and-examples.md#physics-and-units-sources). The final column is a design inference constrained by [`Definition`](../../../../app/workshop/creator/definition.gd), [`Compiler`](../../../../app/workshop/creator/compiler.gd) and the [trainer package](../estimated-trainer-package.md).

### Geometry is not a complete aerodynamic model

For a **confirmed simple trapezoidal planform**, area and root chord may support the derived candidate `c_tip = 2S/b − c_root`. This is a proposed geometric reconstruction, not a universal interpretation of swept, cranked or elliptical wings. Require a positive chord, matching measured/model landmarks and supported taper/AR; otherwise retain the area as reference and request the actual planform. Current Creator assumes a straight taper with an unswept quarter-chord line. [Package derivation](../estimated-trainer-package.md#formulas)

MSFS tail-area semantics distinguish fixed tail surfaces from their control surfaces. Its geometry also includes values that are virtual tuning quantities or inactive in particular modern versions. Preserve those distinctions rather than fitting a physical wing by copying all numbers. [P4](sources-and-examples.md#physics-and-units-sources)

## Units and parsing

Apply conversions per field and per table column. Do not infer units from magnitude, filename or adjacent keys. Validate complete finite tokens before conversion and check bounds afterward. Source simulation defaults are versioned observations, not undocumented OpenRC defaults.

| Source unit | SI conversion | Qualification |
| --- | --- | --- |
| ft | × 0.3048 m | International foot |
| in | × 0.0254 m | International inch |
| ft² | × 0.09290304 m² | Derived from international foot |
| lb mass | × 0.45359237 kg | Source weight/balance pounds are mass-like values; gravity is separate |
| lbf | × 4.4482216152605 N | Conventional standard gravity |
| slug·ft² | × 1.3558179483314004 kg·m² | Inertia, not lb·ft²; derived from lbf = slug·ft/s² |
| kt | × (1852/3600) m/s | Nautical mile per hour |
| ft/min | × (0.3048/60) m/s | Do not confuse with ft/s |
| mechanical hp | × 745.6998715822702 W | 550 ft·lbf/s; distinguish metric/electrical horsepower |
| deg | × π/180 rad | Field-specific; some target authoring fields intentionally remain degrees |
| RPM | × 2π/60 rad/s | Shaft angular speed; revolutions/s = RPM/60 |

Unit definitions/conversion basis: [NIST SP 811](https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b8) (P17); extra digits in composite factors above are derived from the defining constants, not copied from rounded tabulated values. The source weight/inertia/contact units are documented separately in [P3/P5/P12](sources-and-examples.md#physics-and-units-sources).

Two critical angle examples: modern `lift_coef_aoa_table` uses radians; legacy `pitch_moment_pitch_alpha_table` uses degrees and is inactive in the modern FDM. A global angle switch is incorrect. Source throttle/rudder/elevator effectiveness factors are dimensionless tuning values, not physical travel or a servo time constant. [P7](sources-and-examples.md#physics-and-units-sources)

## Frames, origins and inertia

### Points and directions

MSFS's documented body basis is `X=right, Y=up, Z=forward`, but **CFG tuple order belongs to each field and version**. Fields documented in longitudinal/lateral/vertical order, including the relevant `[WEIGHT_AND_BALANCE]` positions, use `(z,x,y)`, positive forward/right/up. In contrast, the 2024 `[OBJ_AIRGEO_WING.N]` and `[OBJ_AIRGEO_HTAIL.N]` `position` fields are documented as `(x,y,z)`. Normalize through a field-specific registry; never apply one tuple order to an entire CFG. Model/glTF coordinates require their own source convention and applied node transforms. [P2/P3/P5/P6](sources-and-examples.md#physics-and-units-sources)

OpenRC authors structural locations in `[aft,right,up]` metres relative to the wing leading-edge datum. The runtime body is FRD, and world position is NED. For a positional displacement **already decoded by its field schema** into `v = [forward,right,up]` in feet, unit/basis-only conversion is:

```text
v_LE_axes_m = 0.3048 × [-v.forward, v.right,  v.up]
v_FRD_m     = 0.3048 × [ v.forward, v.right, -v.up]
```

These are axis maps for a displacement, not complete point conversions. Resolve the documented datum-to-mesh translation and subtract the chosen LE origin before applying target scale. Record all transforms; do not add a datum translation twice. `aero_center_lift` is a documented exception: it is referenced to the model origin and is used to position surfaces, not a fixed runtime aerodynamic center. [P7](sources-and-examples.md#physics-and-units-sources)

For the target's fixed body datum O and structural point `p`, existing OpenRC owns:

```text
r_O = [-(p.x - c_O.x), p.y - c_O.y, -(p.z - c_O.z)]
r_live_CG = r_O - cg_body_m
```

Use the [existing contract](../../../AIRCRAFT_CONTRACT.md#coordinates-signs-and-units), including the distinction between reference-inventory CG and moving live CG. Do not recenter already O-relative propulsion offsets. Rendering converts only after the float64 boundary.

The CFG-to-structural/FRD map can involve a reflection. It is not a rotation quaternion. Rebuild mesh winding, normals and tangent handedness as required before strict GLB admission. Signed angular quantities and control rotations need their source convention and independent positive-roll/pitch/yaw tests; a point-coordinate map alone does not establish their signs.

### 2024 tensor conversion

The current 2024 definition is a list `Jxx, Jyy, Jzz, Jyz, Jxz, Jxy`, with the first three mandatory, in slug·ft² about the empty-aircraft CG. In MSFS XYZ the diagonal axes are pitch, yaw, roll. A valid tensor takes precedence over legacy scalar fields; absent/invalid tensor uses the documented source fallback. Preserve that resolution in the report. The source uses **negative mass products** off diagonal. [P5–P6](sources-and-examples.md#physics-and-units-sources)

Let the source matrix be assembled in MSFS XYZ order. For the axis map to FRD:

```text
R = [[0, 0, 1],
     [1, 0, 0],
     [0,-1, 0]]

I_FRD = R I_MSFS Rᵀ
      = [[ Jzz,  Jxz, -Jyz],
         [ Jxz,  Jxx, -Jxy],
         [-Jyz, -Jxy,  Jyy]]
```

Then apply the inertia unit factor and any explicitly selected mass/size scaling. This transformation is a mathematical consequence of the documented bases; it is not a demonstrated importer result. OpenRC's packed normalized inertia order is `[Jxx,Jyy,Jzz,Jxy,Jxz,Jyz]`, another reason not to copy the source six-element array. The legacy `empty_weight_coupled_MOI` needs a separate version-specific sign/order fixture; do not infer its convention from the modern tensor.

An independent matrix check should start with asymmetric mass locations or an explicit symmetric source tensor. For example, source `[[10,1,2],[1,12,3],[2,3,14]]` maps to `[[14,2,-3],[2,10,-1],[-3,-1,12]]` before unit scaling. Check symmetry, principal-moment positivity, physical triangle inequalities and the inverse used by the target loader. A positive diagonal alone does not prove a valid inertia tensor.

### Target mass inventory

For target components with masses `m_i`, centroids `r_i` and component tensors `I_i`, assemble:

```text
m = Σ m_i
r_CG = (Σ m_i r_i) / m
I_CG = Σ [I_i + m_i ((d_i · d_i) E − d_i d_iᵀ)]
d_i = r_i − r_CG
```

These are rigid-body/parallel-axis identities. Use supported inventory primitives and the existing loader as authority; any richer tensor-authoring primitive requires a separately reviewed AS extension. A source empty-airframe aggregate plus a new motor/battery must not double-count hardware that was already in the aggregate. Retain source loaded/empty mass roles, and make RC replacements explicit. Imported passenger/fuel stations are reference data unless deliberately represented in the selected target configuration.

An aggregate source CG/tensor can check or constrain an estimated distribution, but generally cannot identify every component mass/location uniquely. Do not invent hidden ballast to force a fit. Final mass properties are those derived from the emitted OpenRC bytes. Finite-fuel movement, battery state and other resource laws retain their existing owners.

## Aerodynamic conversion

OpenRC's conventional normalization is:

```text
qbar = 0.5 ρ V²
L = qbar S CL       D = qbar S CD       Y = qbar S CY
Mx = qbar S b Cl    My = qbar S c Cm    Mz = qbar S b Cn
p_hat = p b/(2V)    q_hat = q c/(2V)    r_hat = r b/(2V)
```

Its force convention is wind axes `[-D,Y,-L]`; aerodynamic moments are body-axis moments about ARP, then shifted to CG once by the runtime. Its coefficient chord is `c=S/b`, **not MAC**. MAC remains useful for planform/balance comparisons but is not interchangeable in moment/rate normalization. Per-radian aerodynamic controls use trailing-edge down for elevator/ailerons and left for rudder; pilot/render outputs use their existing different signs. [`ControlSurfaces`](../../../../app/physics/control_surfaces.gd) owns the sign/unit conversion. [OpenRC contract](../../../AIRCRAFT_CONTRACT.md#coordinates-signs-and-units)

A transferable coefficient needs the same force/moment axis, reference area/span/chord, reference point, angle unit, nondimensional rate, trim state and active source-law meaning. For unchanged dimensional pitch moment at the same state, changing only reference area/chord would give `Cm_target = Cm_source × (S_source c_source)/(S_target c_target)`; rate derivatives additionally include the source/target normalized-rate factors. This is a normalization derivation, not a formula for scaling an aircraft's physical forces. Reference-point shifts also add the force-arm moment and its derivatives.

Modern MSFS derives numerous damping/control effects from simulated surfaces and ignores many legacy coefficient fields even if present. Its lift table is a target in the source model's initialization/normalization, not a complete transportable force law. Flags for modern/legacy FDM, CFD and custom systems must accompany observations. Copying all legacy coefficients from a modern file can import inactive values. [P2/P7](sources-and-examples.md#physics-and-units-sources)

Recommended initial dispositions:

- Read dimensions, source mass roles and installation metadata exactly; propose only supported, confirmed target inputs.
- Keep source polars, derivatives, tuning scalars and AIR/CFD references visible as reference-only until a tested mathematical mapping exists.
- Compile a clearly labelled RC estimate from the selected supported package; record its donor assumptions and difference from source behavior.
- Add an optional later fit against independent RC measurements: lift/drag, trim, glide, power/thrust and control response over a preregistered domain. Do not fit more parameters than the measurements can identify.

A fitting campaign must hold out maneuvers and conditions, retain measurement uncertainty and source identities, and distinguish numerical error from model error. Matching cruise trim does not validate stalls, spins, ground effect or gust response. Simulator telemetry, where independently available under applicable terms, can describe source behavior; agreement with it does not establish RC realism or give permission to use restricted SDK benchmarking facilities.

### Legacy AIR and source runtime code

Microsoft ESP documents AIR as compiled token-based flight-model data, while Prepar3D documentation identifies aerodynamic data in the AIR file. It is not an INI file whose coefficients can be recovered from CFG alone. [P8–P9](sources-and-examples.md#physics-and-units-sources)

First detect the referenced AIR and report the limitation. A later reader must whitelist documented record dialects, lengths, table axes/units and precedence against CFG, retain unknown-record diagnostics, and qualify exact source versions. Existing legacy-import tools that require an external AirUpdate dump are evidence of another conversion boundary, not a license or correctness guarantee for OpenRC. [F16](sources-and-examples.md#format-and-package-sources)

Do not run gauges, WASM, DLLs or external FDM modules to make imported aircraft work. Flying Brick's custom code directly replaces normal flight behavior, making its readable CFG unsuitable as a behavior oracle. Such dependencies produce a partial/reference outcome or an explicitly newly authored OpenRC installation. [Inspected example](sources-and-examples.md#flying-brick)

## Propulsion, controls and contact

MSFS `max_rated_hp` does not force the actual produced power. Engine/propeller parameters, shaft state and model behavior matter. An RC target needs supported motor torque/speed, ESC limits, finite battery behavior, actual propeller and mounting data; full-scale fuel/engine selection is not an automatic RC equipment recommendation. [P10](sources-and-examples.md#physics-and-units-sources)

For small propeller data, a useful conventional representation is `J=V/(nD)`, `T=CT ρ n² D⁴`, `P=CP ρ n³ D⁵`, where `n` is revolutions per second. UIUC's low-Reynolds propeller work includes both static and advancing-flow measurements. Static thrust alone does not determine forward-flight performance. Use the existing OpenRC power-law/package contracts and pin the actual dataset/diameter/pitch/Reynolds assumptions rather than replace them with a nominal HP field. [P11](sources-and-examples.md#physics-and-units-sources)

Controls require four separate mappings: pilot input, real surface travel/timing, visual hinge motion, and aerodynamic authority. Source gauges may add limiting or mixing that does not exist in the target. Source maximum deflection and mesh keyframe amplitude are not enough to infer servo speed. A later similar-time estimate must not overwrite measured RC equipment timing.

Contact-point arrays mix feet, feet/minute, degrees, seconds and dimensionless damping. Resolve each field by its versioned definition. Preserve location/contact type separately from source solver stiffness/friction tuning. Rebuild target support geometry and load distribution around the final CG under the supported GP law. Gear contacts, Runway starts and retracts remain separately gated Creator extensions. [P12](sources-and-examples.md#physics-and-units-sources)

## Scaling laws

Define `λ = b_target/b_source > 0`. Geometric similarity gives lengths `λ`, areas `λ²` and volumes `λ³`. For rigid incompressible dynamic similarity at **equal ambient density and gravity**, retaining corresponding aerodynamic coefficients and mass distribution gives the following estimates. NASA's dynamic-model treatment motivates the mass/inertia/speed/time relations and their limits; the force, power and spring/damper rows are dimensional derivations. [P13](sources-and-examples.md#physics-and-units-sources)

| Quantity | Target/source factor | Assumption or derivation |
| --- | --- | --- |
| Length, CG arm, reference chord, propeller diameter | λ | Similar geometry; actual target hardware may differ |
| Area | λ² | Similar planform |
| Mass | λ³ | Equal relative density and ambient density |
| Inertia | λ⁵ | Mass × length²; same relative distribution |
| Speed | √λ | Equal Froude parameter V²/(gL) |
| Time | √λ | Length/speed |
| Angular rate | 1/√λ | Inverse similar time |
| Linear acceleration | 1 | Same gravity |
| Force/thrust | λ³ | Mass × acceleration |
| Moment/torque | λ⁴ | Force × length |
| Shaft/mechanical power | λ^(7/2) | Force × speed |
| Mass wing loading m/S | λ | Mass/area |
| Reynolds number | λ^(3/2) | Same kinematic viscosity and Froude-scaled speed |
| Linear spring stiffness | λ² | Similar force/displacement; not automatic gear-law mapping |
| Linear viscous damping coefficient | λ^(5/2) | Similar force/velocity; not a simulator damping scalar |

If source/target atmosphere differs, include the density/gravity/viscosity ratios and rederive the selected similarity conditions. The simple table must not silently mix source cruise-altitude data with a sea-level RC target. It is not a universal scaling rule for compressible jets, elastic structures, engine efficiency, battery capacity or servo hardware.

### Reynolds conflict

`Re = Vc/ν`. At fixed air properties, equal Reynolds number would require `V_target/V_source = 1/λ`, while equal Froude number requires `√λ`. For a reduced aircraft these are different speeds. Viscous separation, drag and stall therefore cannot be assumed preserved by geometric/dynamic scaling. Mach similarity is another constraint for compressible sources. [P14](sources-and-examples.md#physics-and-units-sources)

Use source coefficients as evidence-bearing seeds only where the selected target law/domain allows it. Low-Reynolds polar data or physical measurements are needed for a stronger RC claim. UIUC airfoil datasets are useful research candidates, subject to their specific notices and reuse conditions. [P16](sources-and-examples.md#physics-and-units-sources)

### User-selected RC mass

Let `μ = m_target/m_source`, independent of geometric scale. If normalized mass distribution is preserved only as an estimate:

```text
I_target = μ λ² I_source
```

Prefer actual target component assembly when available; it may change CG and products of inertia as well as total mass. Independent RC mass breaks the simple `√λ` stall-speed assumption. At 1g and a specified atmosphere/target `CLmax`:

```text
V_stall = sqrt(2 m g / (ρ S CLmax))
```

This is derived from the lift equation [P15](sources-and-examples.md#physics-and-units-sources). For a real supported installation, use its actual/estimated low-Reynolds `CLmax`; a numerical answer is conditional on that assumption. Do not preserve full-scale passengers/fuel, scale horsepower into a motor recommendation, or scale battery duration/servo timing without a separately justified law.

### Worked synthetic example

These invented values are an arithmetic fixture, **not a model of a Cessna, Corsair or any inspected aircraft**. Source: span 10 m, area 20 m², mass 1,000 kg, reference chord 2 m, representative speed 50 m/s, shaft power 100 kW and diagonal inertia `[1000,1500,2000]` kg·m². Target span 1.5 m gives `λ=0.15`.

| Result | Dynamic-similarity estimate | Independently selected 2.5 kg RC target |
| --- | ---: | ---: |
| Span | 1.5 m | 1.5 m |
| Area | 0.45 m² | 0.45 m² |
| Aspect ratio | 5 | 5 |
| Mass | 3.375 kg | 2.5 kg |
| Mass wing loading | 7.5 kg/m² | 5.55556 kg/m² |
| Inertia diagonal, same relative distribution | `[0.0759375,0.11390625,0.151875]` kg·m² | `[0.05625,0.084375,0.1125]` kg·m² |
| Corresponding representative speed | 19.3649 m/s | Recompute from target lift/trim; not inherited |
| Similarity power | 130.713 W | Select supported actual RC power package |

The 130.713 W result is ideal similarity arithmetic; it is not a sufficient motor specification or a validated flight condition. With illustrative `ν=1.5×10⁻⁵ m²/s`, source Reynolds number is approximately `6.667×10⁶`, while the dynamic-scale example is `3.873×10⁵`, only 5.81% of the original.

For the 2.5 kg target at `ρ=1.225 kg/m³` and `g=9.80665 m/s²`, assumed `CLmax=1.4` gives a stall estimate of **7.971 m/s**; assumed `CLmax=1.1` gives **8.992 m/s**. The difference demonstrates the consequence of an aerodynamic assumption; neither number is physical evidence.

**Domain counterexample:** 4 kg at the same 0.45 m² gives **8.88889 kg/m²**. It passes the current Creator mass/span limits separately but exceeds its 8 kg/m² loading boundary. At this area the loading ceiling limits mass to **3.6 kg**. The 3.375 kg example passes those nominal mass/span/AR/loading checks, but tail geometry, static margin, controls, complete inventory and supported propulsion are still undefined. It is not ready to compile or fly. [Current package bounds](../estimated-trainer-package.md#package-domain-development-bounds)

## Evidence and validation for implementation

Keep one traceable observation per source field: exact source revision/file/hash, section/key/line, raw token/unit, effective source mode, normalized value/unit, transform history, mapping disposition, evidence kind and adopted target field if any. Record whether an override came from source inheritance, the user, a package or a converter default.

Suggested report dispositions are `reference`, `converted`, `adopted`, `estimated`, `inactive`, `unresolved`, `unsupported` and `conflict`. They are proposed report states, not replacements for the physical schema's evidence kinds. Version and validate this vocabulary before serializing it. Use a visible omission/conflict count and never truncate a report so it appears complete.

Acceptance needs independent known-answer units/frames/tensor cases; `λ=1` identity and scale-once tests; target inventory reconciliation; package-domain corners/counterexamples; correct control and torque signs; finite states, trim/glide/step/upset checks and preregistered numerical refinement. Preservation of ARP/CG and reference chord must be tested at nonzero offsets, not only a symmetric origin case. The [feature verification table](../../../plans/flight-simulator-aircraft-import.md#8-verification-and-release-contract) owns the complete release gate.

Current AC-12 failure remains a flight dependency. Parser tests, source-FDM agreement, successful trim, pilot preference and physical RC calibration establish different things. No blanket 5%/10% fidelity threshold is proposed; choose measurable metrics and tolerances for named configurations before collecting the qualification results.
