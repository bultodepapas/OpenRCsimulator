# R11 contact contract fixture

The previous fleet assertion required `applied`, `legacy_fallback`, and `no_gear` all to appear in the aircraft catalog. That was a stale fixture expectation: every current non-rotorcraft catalog entry has gear, while the loader and contact contract explicitly support the no-gear route. The test still checks each catalog aircraft and now requires all fleet entries to land in a recognized profile state, with both current gear-equipped routes represented. It exercises all three profile states directly in isolated fixtures.

The no-gear case is made from the real Stik v2 input at test time. It retains the normalized hull and propeller, removes landing gear and authored identities, and sets `capabilities.gear` to `locked_up`, which is the v2 contract's valid absent-gear state. The test writes this temporary JSON under `user://`, loads it through `AircraftData.load_file`, then removes it. The file-backed profile fixture aliases the shipped Stik profile under a test-only ID; its physical quantities are unchanged. No catalog data or production source was edited.

The test checks that the loader assigns `no_gear`, the contact description has zero support points and the same ordered hull geometry, soft mode retains prop-strike selection for the Stik prop disc, and gear overtravel is unselected. It also checks that terminal mode selects neither prop-strike nor gear-overtravel. Applied and legacy-fallback are independently exercised through `WheelProfiles.apply_to_model` and `ContactContract.describe`, rather than inferred only from aggregate fleet counts.

Runtime basis: [AircraftData.load_file](../../../../../../app/physics/aircraft_data.gd) applies wheel profiles after v2 validation; [`_landing_gear`](../../../../../../app/physics/aircraft_data.gd) treats absent gear as optional in the numerical model. [WheelProfiles.apply_to_model](../../../../../../app/physics/wheel_profiles.gd) creates `no_gear` only for an empty gear object and `legacy_fallback` when a geared model lacks a profile. [AircraftContract](../../../../../../app/physics/aircraft_contract.gd) permits absent `landing_gear` when `capabilities.gear` is `locked_up`. [ContactContract](../../../../../../app/physics/aircraft_contact_contract.gd) emits support points only from gear contacts and chooses prop-strike/overtravel policies from the resulting disc/support sets.

Focused verification ran against a fresh copy of `app`, not the shared app tree:

```powershell
C:\DEVELOPMENT\OpenRCsimulator\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path C:\DEVELOPMENT\OpenRCsimulator\tmp\r11-contact-contract-fixture-run\app --audio-driver Dummy --script res://tests/test_aircraft_contact_contract.gd
```

Result: `722 checks, 0 failed`, captured in [focused-windows-full-precision.log](focused-windows-full-precision.log). The earlier logs are retained as debugging history: the first fixture omitted the required `locked_up` capability, and the second serialization pass did not request full float precision. The passing run uses the corrected capability and `JSON.stringify(..., full_precision=true)`. Linux focused verification is pending the R11 owner.
