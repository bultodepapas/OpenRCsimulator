# SF-07 — Environment contract

2026-10-15 · **Status: implemented, byte-identical: the three vehicle sessions consume one environment object (physical weather, the owner's turbulence sample, the field's surface table with the terrain sampler, the lake, a ground-vehicle course, gravity); every fleet fingerprint stays identical to the SF-05 commit.** Step SF-07 of the [simulation foundation plan](../README.md).

## The contract

[`app/sim/environment.gd`](../../../../app/sim/environment.gd) (`SimEnvironment` in the sessions, because `Environment` is a Godot class) is a pure, deterministic query object sampled at a stage position and time:

| Query | Provider | Returns |
| --- | --- | --- |
| `wind(time_s)` | physical weather field, plus the owner's turbulence sample when it returns three values | wind in NED |
| `air(down_m)`, `air_density`, `engine_charge_ratio` | the weather's atmosphere law (uniform or ISA column) | the atmosphere record or its scalars |
| `terrain(north, east)`, `ground(north, east)`, `ground_max_height()` | the field's flat surface table through `physics/ground_terrain.gd`, the second with the lake applied | `[height_up, …]` |
| `water(north, east)` | the normalized lake | the lake terrain sample, or `{}` |
| `course(north, east)` | a ground-vehicle course sampler (`course_road`, moved from the truck session) | height, normal, surface, walls and wet zone, or `{}` |
| `gravity` | the vehicle's data | m/s² |
| `identity()` | all of the above | a diagnostic summary (not a checkpoint format) |

The turbulence callback returns an empty array when the owner has no turbulence this run, so calm wind keeps its exact bytes (adding 0.0 would turn −0.0 into +0.0).

## Change

| File | Change |
| --- | --- |
| [`app/sim/flight_session.gd`](../../../../app/sim/flight_session.gd) | Owns `environment`; `_weather`, `ground_surfaces` and `_lake` are views of it, so every existing consumer reads the same providers. `wind_at`, `environment_at`, `air_density`, `engine_charge_ratio` and the two direct terrain samples answer through the contract; the turbulence interpolation became the owner's `_turbulence_noise` callback. |
| [`app/sim/helicopter_flight_session.gd`](../../../../app/sim/helicopter_flight_session.gd) | Same views; `wind_at`, `air_density` and the four terrain samples go through the contract. |
| [`app/sim/ground_vehicle/session.gd`](../../../../app/sim/ground_vehicle/session.gd) | The course sampler is built by `SimEnvironment.course_road` and installed as the environment's `road`, with the model's gravity. |
| [`app/tests/test_sf_environment.gd`](../../../../app/tests/test_sf_environment.gd) (new) | 27 checks: the contract alone (exact bytes without turbulence, axis-wise addition with it, delegation, flat defaults, identity, Galilean air data under a uniform wind), the fixed-wing session (views, installed turbulence, wind and air through the contract, field change in the identity, terrain equality, a windy tick), the helicopter (views, queries, a tick) and the truck (road and gravity, deterministic course answers, identity). |

## Proof

| Check | Result | Record |
| --- | --- | --- |
| Contract test | 27 checks, 0 failed | [log](results/environment-test.log) |
| Fleet fingerprints, baseline commit `4fc22ba6` (SF-05) versus this tree | **24/24 identical** | [comparison](results/fingerprint-comparison.txt), [baseline](results/fingerprints-head.json), [SF-07](results/fingerprints-sf07.json) |
| Weather, turbulence, atmosphere, field, lake, helicopter, truck, kernel and replay suites on this tree | 23 programs, all pass (wind 51, turbulence 160, atmosphere column session 97, field integration, lake and water checkpoints, both helicopter sessions, RCV and nitro sessions, airfield track, every SF test, checkpoints, goldens, glow and electric sessions); the electric session was rerun alone because its batch run coincided with a transient edit of the truck evaluator | [log](results/focused-tests.log) |

## Limits

- The contract unifies the queries, not the data: wind, atmosphere, surfaces, lake and course keep their own formats and identities in each session's checkpoint.
- Water is a terrain-level lake sample; a free water surface with waves or currents for boats is a provider to add behind `water()` when a boat exists.
- Scenery collision proxies stay with the sessions' collision world; they are presentation-coupled geometry, not an environment field.

Commit message: `SF-07: environment contract (sim/environment.gd); fixed-wing, rotorcraft and ground-vehicle sessions query wind, air, terrain, water and course through it; fleet fingerprints byte-identical, 27-check contract test`
