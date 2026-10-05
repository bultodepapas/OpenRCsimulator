# 11 · Windsock, tree sway, flags and ambient life

Date: 2026-10-05 · **Question:** how do we animate the windsock, trees, grass, flags, cloud shadows and sound from the *simulated* wind so that the motion is believable, can be tested against real standards, and stays byte-identical in captures?

## Findings

**Windsock: the standards give us a testable curve**

| Fact | Value | Source |
| --- | --- | --- |
| Sizes | Size 1: 2.5 m long, 0.45 m throat; Size 2: 3.75 m, 0.9 m | [FAA AC 150/5345-27E §3.2.2](https://www.faa.gov/documentlibrary/media/advisory_circular/150_5345_27e.pdf) [doc] (read) |
| Full extension | 15 kt (test tolerance +2/−1 kt) | same, §3.2.2, §4.2.6 [doc] |
| Alignment | ±5° of true direction at ≥ 3 kt; white, yellow or orange | same, §3.4, §3.2.3 [doc] |
| Droop vs speed | ≥ 15 kt horizontal; **10 kt → 5° below; 6 kt → 30° below** | [TC AIM AGA 5.9, Table 5.3](https://tc.canada.ca/sites/default/files/2021-09/AIM-2021-2_AGA-E.pdf) [doc] (PDF read) |
| ICAO | ≥ 3.6 m cone; two colours → orange/white, 5 bands; "1 stripe ≈ 3 kt" | [Wikipedia](https://en.wikipedia.org/wiki/Windsock) [sec] |

- A **lookup table** does the job. The 0 kt and 3 kt points are estimates. No dynamics study was found: use a first-order lag (τ ≈ 0.6 s, estimate) plus seeded flutter [inference].
- `air_data.gd` treats `wind_ned` as the **air velocity** (where the air goes *to*) [src]. The sock points along it, so there is no meteorological "from" conversion.

```gdscript
# Proposal (ours). Visual state, float64, 240 Hz tick.
const KT := 0.514444
const DROOP_KT  := [0.0, 3.0, 6.0, 10.0, 15.0]  # 6/10/15 kt: TC AIM [doc]; 0/3 kt: estimate
const DROOP_DEG := [88.0, 65.0, 30.0, 5.0, 0.0]
const TAU_S := 0.6  # estimate

static func droop_deg(v_ms: float) -> float:
	var kt := v_ms / KT
	for i in range(1, DROOP_KT.size()):
		if kt <= DROOP_KT[i]:
			var f: float = (kt - DROOP_KT[i - 1]) / (DROOP_KT[i] - DROOP_KT[i - 1])
			return lerpf(DROOP_DEG[i - 1], DROOP_DEG[i], f)
	return 0.0

## state = [yaw_rad, droop_deg]; wind_n/e = NED air velocity, m/s.
static func step(state: PackedFloat64Array, wind_n: float, wind_e: float, dt: float) -> void:
	var v := sqrt(wind_n * wind_n + wind_e * wind_e)
	var k := 1.0 - exp(-dt / TAU_S)
	if v >= 3.0 * KT:  # FAA: aligns at >= 3 kt
		state[0] += k * wrapf(atan2(wind_e, wind_n) - state[0], -PI, PI)
	state[1] += k * (droop_deg(v) - state[1])
```

Render as **5 stripe segments**; segment *i* sags more while V < 3·i kt (estimate).

**Vegetation**
- GPU Gems 3 ch. 16 (Crysis) splits plant motion into *main bending* (the whole plant, length-preserving) and *detail bending* (leaves). [doc](https://developer.nvidia.com/gpugems/gpugems3/part-iii-rendering/chapter-16-vegetation-procedural-animation-and-shading-crysis).
- Trees sway at 0.1–5 Hz depending on trunk diameter over height squared. The spectral slope stays constant from medium to high wind, so use a **fixed per-tree frequency, wind-scaled amplitude** [AP](https://bg.copernicus.org/articles/18/4059/2021/) (CC-BY 4.0). For 12–25 m trees, 0.2–0.5 Hz is an estimate.
- **Visibility** [inference, `spec.gd`: 50° FOV, auto-zoom down to 6°]: a 0.3 m tip sway at 400 m is about 1 px at 1080p, but about 5 px at 10° zoom. Far trees get main bending only and must not shimmer when zoomed.
- SimpleGrassTextured (MIT) drives grass from **global uniforms**, but it also adds `sin(TIME + rand)` [src](https://github.com/IcterusGames/SimpleGrassTextured/blob/main/addons/simplegrasstextured/shaders/grass.gdshaderinc). Copy the pattern only.

**Godot plumbing (Compatibility)**
- `global uniform` works in every shader type. Its value comes from Project Settings; defaults in the shader are ignored. Setting it each frame is cheap [doc](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html). The old Compatibility bugs for matrix ([#81473](https://github.com/godotengine/godot/issues/81473)) and sampler ([#80558](https://github.com/godotengine/godot/issues/80558)) globals are closed [iss]. **Use only `float` and `vec3` globals.**
- Instance uniforms work in Compatibility since 4.4 ([#96819](https://github.com/godotengine/godot/pull/96819), merged 2024-10-07) [repo, `gh api`]. In a MultiMesh, use `INSTANCE_CUSTOM` instead. **Compatibility packs it to 16 bits** [doc](https://docs.godotengine.org/en/stable/classes/class_multimesh.html), fine for a phase.
- `TIME` follows process time and wraps at `time_rollover_secs` (3600 s) [doc PR](https://github.com/godotengine/godot/pull/95381). Use sim time instead, wrapped in float64 on the CPU. If every frequency is a multiple of 1/1024 Hz, wrapping at 1024 s is seamless, and float32 still resolves 1.2e-4 s there [inference].

```glsl
// Proposal (ours; main bending after GPU Gems 3 ch.16). No TIME.
shader_type spatial;
global uniform vec3 wind_vec;    // render frame, m/s (frames.gd ned_to_render)
global uniform float wind_clock; // sim time wrapped to [0,1024) s
uniform float plant_height = 1.0;
uniform float bend_scale = 0.003; // estimate
uniform float sway_hz = 0.375;    // 1024*f integral
void vertex() {
	vec2 w = (wind_vec * mat3(MODEL_MATRIX)).xz;  // world→model, rotation-only
	float gust = 0.85 + 0.15 * sin(6.2831853 * (sway_hz * wind_clock + INSTANCE_CUSTOM.r));
	float bf = clamp(VERTEX.y / plant_height, 0.0, 1.0) * bend_scale * length(w) + 1.0;
	bf *= bf; bf = bf * bf - bf;  // Crysis curve
	float len = length(VERTEX);
	vec3 p = VERTEX; p.xz += w * bf * gust;
	VERTEX = normalize(p) * len;
}
```

**Flags, cloud shadows, sound, birds**
- **Flags:** CC0 vertex-wave shaders exist ([3D flag](https://godotshaders.com/shader/3d-simple-animated-flag-shader/)) [src], but they use `TIME`. Swap in `wind_clock`, scale amplitude with wind speed V, and hang the flag when V < 1 m/s.
- **Cloud shadows:** `DirectionalLight3D` has no projector texture, and the [proposal](https://github.com/godotengine/godot-proposals/discussions/5871) is still open [iss]. The analytic method (MIT) works inside `light()`: intersect `-LIGHT` with a cloud plane, sample noise, multiply `ATTENUATION` [src](https://godotshaders.com/shader/simulating-cloud-shadows-analytically/). Use a committed texture, offset = wind aloft × sim time.
- **Sound:** `render/engine_sound.gd` already synthesizes audio in testable GDScript [src]. Wind noise can follow the same pattern: seeded, filtered noise whose level follows V. Filter in the synth: bus effects fail with web sample playback ([#95991](https://github.com/godotengine/godot/issues/95991)) [iss]. For birdsong, Freesound filters by `license:"Creative Commons 0"` [doc](https://freesound.org/docs/api/resources_apiv2.html); the API needs a token, and downloads need OAuth2 [doc](https://freesound.org/docs/api/authentication.html).
- **Birds:** a few seeded analytic thermal circles as functions of sim time, drawn as MultiMesh "V" billboards. Off by default and in tests (a far bird looks like the airplane).

## Libraries / tools found

| Name | Version / last activity | License | Compatibility / web? | Fit for us |
| --- | --- | --- | --- | --- |
| SimpleGrassTextured | v2.1.0 (2026-04-03) | MIT | likely, not verified | Pattern only (uses `TIME`) |
| GodotGrass | last push 2024-08 | MIT | Forward+ demo | Bending reference |
| godotshaders flag / cloud-shadow shaders | — | CC0 / MIT | plain GLSL | Idea; remove `TIME` |
| Freesound (CC0 filter) | live | CC0 per file | — | Birdsong; record provenance |

## What this changes in LANDSCAPE-PLAN.md

1. **New L1b, "Wind clock + no-`TIME` guard"** (cheap, do it now). `test.sh` fails if any `.gdshader`/`.gdshaderinc` contains `TIME`. Add the globals `wind_vec` and `wind_clock` to `project.godot`, set them every tick, and keep the wind at zero for now. *Proof:* a mutated copy fails the guard, the clock wrap is phase-continuous in a unit test, and goldens and captures stay byte-identical.
2. **L10 windsock** built to FAA Size 1 proportions with 5 orange/white segments, hanging at zero wind. *Proof:* a test checks its dimensions against the field file.
3. **L11 grass** uses `wind_clock` + `INSTANCE_CUSTOM.r`. *Proof:* two captures at the same sim time are byte-identical; captures at t and t + 1 s differ only where the grass is.
4. **Split L15** (after M5 wind):
   - **L15a Windsock dynamics.** *Proof:* steady droop within ±1° of the TC table at 6, 10 and 15 kt; yaw within ±1° for wind_ned (5,0,0) and (0,−5,0); 63 % of the response at τ.
   - **L15b Tree main bending**, amplitude ∝ V². *Proof:* far-ring sway ≤ 1 px at 50° FOV and visible at 10°.
   - **L15c Grass, bushes and flag** scaled by V. *Proof:* at V = 0 the bytes equal the static capture.
   - **L15d Cloud shadows.** *Proof:* shadow speed measured from two captures equals the wind aloft within ±5 %.
   - **L15e Wind sound synth.** *Proof:* RMS rises monotonically with V; the same seed gives the same samples.
5. **L19+ Birds and birdsong**, optional; judge bird-vs-airplane confusion at Gate L.

## Not confirmed

- Whether globals in **sky** shaders trigger a radiance update in 4.7 Compatibility (affects L4/L15d alignment).
- The license of the GPU Gems listings (we re-implement them).
- The windsock size RC clubs use; how far 12–25 m treetops bend at 5–10 m/s.
- Whether a shader can use a global added at runtime instead of declared in `project.godot`, which the main line owns.
