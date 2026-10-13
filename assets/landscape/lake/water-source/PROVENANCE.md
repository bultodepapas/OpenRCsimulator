# Lake water source provenance

## Shader reference

- Project: [Boujie Water Shader](https://github.com/Chrisknyfe/boujie_water_shader)
- Pinned source commit: `25f3c2da458e0a4f65bdb5903dc068b050930c06`
- Source file: `addons/boujie_water_shader/shader/water.gdshader`
- Source path: [raw shader at the pinned commit](https://raw.githubusercontent.com/Chrisknyfe/boujie_water_shader/25f3c2da458e0a4f65bdb5903dc068b050930c06/addons/boujie_water_shader/shader/water.gdshader)
- SHA-256 of preserved source shader: `09a74e3b97738da896c9f39c73946e38f9487035c6559433316c2136ce84f607`
- SHA-256 of preserved upstream README: `5f80b7fec0f39cea3e8879ca1bb31f9faf72f108a54f242c3ff43836cb33f74f`
- SHA-256 of preserved upstream license: `fbde0da26c3bec6344219a8da2936e5ecb7eee6254f6080d2fe47d6b315ae856`
- License: MIT; the exact upstream `LICENSE.md` is retained beside the source.
- Upstream README reports testing on Godot 4.1.1. This project pins Godot 4.7.2 and the app shader is a separate, reduced adaptation.

The adaptation retains the refraction, Fresnel, absorption, and shore-treatment ideas. It removes the infinite-ocean system, texture dependencies, and Gerstner vertex motion. Its finite-lake surface uses the normalized lake wave data, the shared `sim_clock`, UV2 shore distance, and the Compatibility/OpenGL depth conversion. No Boujie textures are copied or used, so their separate texture licenses do not apply to this adaptation.

The depth reconstruction follows [Godot 4.7's advanced post-processing guide](https://docs.godotengine.org/en/4.7/tutorials/shaders/advanced_postprocessing.html): normalized depth is converted to OpenGL NDC Z with `raw_depth * 2.0 - 1.0`, then transformed by `INV_PROJECTION_MATRIX`. The renderer remains Compatibility-safe: sky and scene reflections come from standard spatial specular, the active WorldEnvironment, and any bounded ReflectionProbe. The [Godot renderer comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) lists screen/depth textures and ReflectionProbe under Compatibility while built-in SSR and compute are unavailable there.

## Water sound prototype

Audio choices are deliberately sample assets for audition and interface prototyping. They do not claim to represent this simulator's lake acoustically.

| App file | Source | License | SHA-256 |
|---|---|---|---|
| `app/assets/audio/water/peludo-splash1.wav` | [Peludo, Water Splash and sand footsteps](https://opengameart.org/content/water-splash-and-sand-footsteps), `splash1.wav`; direct download: `https://opengameart.org/sites/default/files/splash1_0.wav` | CC0 1.0 | `e45d466f7e63e5d566f8a822a7a1a3f7d5131319d17ca0436dcc615b251e9277` |
| `app/assets/audio/water/peludo-splash2.wav` | [Peludo, Water Splash and sand footsteps](https://opengameart.org/content/water-splash-and-sand-footsteps), `splash2.wav`; direct download: `https://opengameart.org/sites/default/files/splash2_0.wav` | CC0 1.0 | `ad9472b711666de2d43c3b102d155a5d1118b1fcd0ecd29cb63177256ab63f31` |
| `app/assets/audio/water/randommind-vistula-short.mp3` | [RandomMind, Sea and river wave sounds](https://opengameart.org/content/sea-and-river-wave-sounds), `VistulaShort.mp3`; direct download: `https://opengameart.org/sites/default/files/VistulaShort_0.mp3` | CC0 1.0 | `8c24607e41edd6f018ec3582a07e5a8dbc57347276339cb68440951a0fb4cfb1` |

Both OGA pages identify the files as CC0. Peludo describes the splashes as a webcam-and-bucket water experiment and asks games to reference an itch.io page; no itch.io URL is present on the OGA page, so the source page is recorded here. RandomMind describes the ambience as waves recorded on the Vistula and supplies a five-minute short version. [CC0 1.0 deed](https://creativecommons.org/publicdomain/zero/1.0/).

An unused alternative pack is retained for later audition outside the app: [rubberduck, 40 CC0 water / splash / slime SFX](https://opengameart.org/content/40-cc0-water-splash-slime-sfx), direct ZIP `https://opengameart.org/sites/default/files/water-splash-slime-sfx.zip`, SHA-256 `7cd39abb49d4362a37ba18dc0e454c7dc1d08029d4e5b683149046bc237b2eba`. Its OGA page declares CC0 1.0 and describes 15 splash effects and six water/bubble/rain loops. None of this pack is copied into `app/assets/audio/water`.
