# L10a field cue data contract

Status: implementation contract, 2026-10-08. Step: L10a.

`openrc-field v1` may include an optional root `flight_cues` array. It accepts zero or one cue. If the key is absent, normalized legacy fields keep their existing shape. A present empty array normalizes to an empty array.

Each cue has exactly these keys: `id`, `type`, `collides`, `north`, `east`, `pole_height`, `length`, `throat_diameter`, and `tail_diameter`. The current type is `windsock`; `collides` must be `false`. IDs share the field-wide uniqueness check, must be valid Godot node names, and cannot use the generated `NearGrass` or `Scenery` child names. Every dimension and coordinate uses the field quantity form `{value, unit, kind, source}` in metres. The loader validates quantity metadata, finite numbers, and exact keys before returning unwrapped float values.

Cue coordinates must lie within ±1,000,000 m. `pilot.down` must be 0 m. The windsock's conservative horizontal envelope radius is `length + throat_diameter + 1 m`; that envelope must fit inside a rough rectangle, avoid runway and mown rectangles, and stay at least 2 m beyond the envelope radius from the pilot. Only the exact 40 km square rough surface uses `Horizon.mesh`, so its envelope must also stay within 1,500 m of the rough center. Other rough rectangles stay flat and have no 1,500 m radial limit.

Policy bounds are estimates for a readable, bounded visual prop: pole height 2–10 m, cloth length 0.5–5 m, and throat diameter 0.1–1 m. Tail diameter must be positive and smaller than the throat. The pole must exceed `length + throat_diameter` to clear the cloth in calm conditions. These bounds are layout policy, not aviation certification limits.

The default station is north −6 m, east −12 m, with a 3.6 m pole, 2.5 m cloth, 0.45 m throat, and 0.18 m tail. FAA AC 150/5345-27E supports the 2.5 m length and 0.45 m throat for Size 1; the first 3/8 of the cloth is the rigid framework. Pole and tail dimensions and placement margins are visual estimates. See [windsock source notes](../../landscape-investigations/11-wind-animation-ambience.md). This data adds no wind dynamics, collision, or physics support.
