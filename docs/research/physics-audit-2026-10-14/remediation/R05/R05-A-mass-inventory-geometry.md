# R05-A — reusable fixed-datum mass geometry

**Status:** geometry service and software fixtures are implemented. This does not add variable-mass flight dynamics, fuel depletion, or physical validation.

[`MassInventory`](../../../../../app/physics/mass_inventory.gd) prepares dry components and removable resources against one named fixed body datum. Geometry inputs and outputs use SI float64 packed arrays. Dry components declare a stable `id`, `mass_kg`, centroid `center_body_m`, and full symmetric `inertia_centroid_kgm2`. Resources declare a stable `id`, `capacity_mass_kg`, centroid, full tensor at capacity, and the explicit `fixed_geometry_uniform_density_v1` distribution model. At evaluation, the caller supplies exactly one remaining mass for each prepared resource ID.

The service returns total mass `mass_kg`, first mass moment `first_moment_kg_m`, `cg_body_m`, full tensors about the fixed datum and current CG, and the inverse CG tensor. The six-entry tensor order follows [`RigidBody`](../../../../../app/physics/rigid_body.gd): `Jxx, Jyy, Jzz, Jxy, Jxz, Jyz`. Each component tensor must be PSD and its second-moment tensor `C = tr(I)/2·Id − I` must also be PSD, which enforces physical principal-moment triangle inequalities without diagonalization. These checks normalize by the largest tensor entry and use a `1e-12` rounding tolerance. The evaluated CG tensor must pass the same physicality test and be positive definite by scaled Sylvester minors. Its inverse is computed from normalized entries and checked finite and positive definite, avoiding raw determinant overflow/underflow for extreme finite tensors. Prepared dictionaries are detached normalized values and must be treated as immutable installation geometry.

For each resource, this first geometry law keeps its declared centroid and fixed-shape, uniform-density tensor per unit mass as quantity falls. This is one explicit inventory distribution model. It does not model a falling liquid level, pickup location, fuel in lines or engine, slosh, mass flux, or the body's open-system equations of motion. It does not change `sim.mass`, runtime integration, force application, contact, trim, or recording.

The only existing runtime consumer is a narrow delegation: [`Glow.FuelMass.tensor_per_kg()`](../../../../../app/physics/glow/fuel_mass.gd) calls the shared rectangular-box tensor kernel. A frozen copy of the former expression compares the returned packed-array bytes over three valid inputs. Glow's `evaluate()`, `datum_derivative()`, fuel state and lifecycle are unchanged.

The Avanti catalog **does** have a removable item: `inventory.id=fuel_flight`, `energy_source=kerosene`. Its current 1.28 kg mass is marked derived from a half-full 3.2 L assumption and 0.8 kg/L; its `[0.05, 0, -0.03] m` position and `[0.25, 0.14, 0.1] m` rough envelope are marked estimated. These are not measured as-built or usable-fuel data. The distinct `fuel_tank` entry is the 0.3 kg shell. See the generated catalog's [fuel entries](../../../../../app/data/aircraft/sebart_avanti_s_a200.json#L1202) and its cited source. R07 still needs evidence for usable/reserve quantity, real fill distribution and extraction/line inventory, and the turbine's cutoff and rundown modes. This service is not wired to either Jet or Glow live mass, and Jet fuel remains prescribed at runtime.

The independent fixtures cover two off-center resources at full, half and empty amounts, a rotated anisotropic tensor with a nonzero product of inertia, fixed-only geometry, inverse multiplication, stable/sorted IDs, validation failures, and translation to a distinct datum. They also reject diagonal and rotated SPD tensors outside the physical triangle cone, accept a physically valid semidefinite rod component, and prepare/evaluate very large and very small finite tensors with finite SPD inverses. The full and partial expected tensors are hard-coded from separate parallel-axis arithmetic; datum translation also preserves the central tensor and shifts first moment/CG as required. Glow rectangular-kernel delegation is checked for exact byte parity.

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_mass_inventory.gd
# R05-A mass inventory geometry: 65 checks, 0 failed

& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_glow_flight_physics.gd
# glow flight physics: 82 checks, 0 failed

& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_glow_installation.gd
# glow installation contract: 226 checks, 0 failed
```

Full command output: [mass inventory](mass-inventory-test.log), [Glow mass/physics regression](glow-fuel-mass-regression.log), and [Glow installation regression](glow-installation-regression.log). Software tests establish arithmetic and compatibility only, not the correctness of any aircraft's authored mass distribution.
