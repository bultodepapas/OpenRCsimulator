# LU-11 — Ground resources and rendering audit

Status: research complete; no assets downloaded and no application changes, 2026-10-12.

## Local review

The [LU-07 native report](../LU-07/README.md) pins Godot `4.7.2.stable.official.ed1daf0bf`, Compatibility/OpenGL 3.3, and records the 1920 × 1080 captures. The [parking capture](../LU-07/day/car_park.png) shows the gravel apron as broad flat color cells beside finely textured grass; the [dusk capture](../LU-07/dusk/postcard_club.png) has a strong orange cast across the sky and most surfaces. These are visual observations, not a diagnosis of the sky-state code. The [ground ledger](../LU-07/ground-details.md) records 2,899 apron triangles, 400 packed vertex colors, and no added texture, cell, or draw.

The existing ground implementation is already suitable for a bounded material test: the procedural apron is part of the existing scenery batches, and `ground.gdshader` uses world-position derivatives for filtering. The tree capture also shows large faceted crowns with little visible color separation between faces. Baked palette variation is a lower-cost option for trees and shrubs than adding materials or textures.

## Free gravel candidates

| Source | Current download facts | License and fit |
| --- | --- | --- |
| [ambientCG Gravel 001](https://ambientcg.com/view?id=Gravel001) | The page lists PBR-map ZIPs at 1K JPG 5 MB, 2K JPG 13 MB, and 4K JPG 40 MB. It is tagged clean, small, and variety; it does not publish a physical tile width on that page. | [CC0 1.0](https://docs.ambientcg.com/license/): the downloadable maps may be modified, redistributed, and included raw in commercial games; credit is optional. Useful as an offline reference or fallback, but the bundled maps are more than a color-only stylized test needs. |
| [Poly Haven Gravel Floor 02](https://polyhaven.com/a/gravel_floor_02) | A photographed coarse gray driveway surface, 2 m wide. The page lists 1K–8K; the official [files API](https://api.polyhaven.com/files/gravel_floor_02) reports 1K diffuse JPG 1,240,441 B, normal-GL JPG 1,545,680 B, rough JPG 680,926 B; at 2K those are 4,698,557 B, 5,894,173 B, and 2,698,006 B. The page lists the 8K package at 97 MB. | [CC0](https://polyhaven.com/license): asset files can be modified and redistributed, including in commercial products, without attribution. The site’s separate previews, logos, and text are not CC0. The 2 m repeat and photographic gray rocks may look too realistic or repetitive against this low-poly warm apron. |

Final choice: neither source was adopted for LU-12. No image or map was downloaded. The filtered procedural material passed close/far native image and incremental-cost checks, so it adds no texture allocation or download dependency. If a texture study is later justified, keep a small selected map with its provenance and hash and do not fetch assets at runtime. [Material proof](materials.md).

## Godot Compatibility findings

Godot’s [4.7 shader function reference](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shader_functions.html) documents fragment-stage `dFdx`, `dFdy`, and `fwidth`; it explicitly marks the fine/coarse variants unavailable in Compatibility. The production [ground shader](../../../../app/render/ground.gdshader) already uses `fwidth`, `dFdx`/`dFdy`, and `textureGrad`; LU-07’s native Compatibility captures exercise that path on the pinned 4.7.2 build. Keep new filtering on these documented functions and still compile/capture the new shader on the pinned renderer.

For texture-backed materials, Godot 4.7’s [`BaseMaterial3D.TextureFilter`](https://docs.godotengine.org/en/4.7/classes/class_basematerial3d.html) offers linear filtering with mipmaps and an anisotropic option. The docs say anisotropic filtering improves oblique-surface quality at a small performance cost. Recheck actual shader-sampler behavior in a 4.7.2 Compatibility capture before relying on it.

Compatibility 3D color is tonemapped into an R10G10B10A2 UNORM target and stored as sRGB; [Godot’s rendering architecture](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html) states that this renderer has no HDR support. Godot’s [environment guide](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html#tonemap) describes exposure as a brightness adjustment before tonemapping. Therefore compare material and sunset changes using matching exposure and post-tonemap captures; do not treat an emission value or shader-space RGB as display luminance.

## Twilight references and bounded direction

Clear twilight does not support tinting the whole scene orange. Hulburt’s measured/theoretical [1953 twilight paper](https://opg.optica.org/josa/abstract.cfm?uri=josa-43-2-113) found that ozone absorption helps explain the observed blue zenith sky through sunset and twilight. Saito, Iwabuchi, and Hayasaka’s free-access [2013 study](https://doi.org/10.2151/sola.2013-004) combines sky photographs, radiometry, and radiative-transfer simulations; it reports that aerosol optical depth changes horizon color and that bluish multiply scattered light can dominate there. Lee and Mollner’s [2017 measurements and 3D Monte Carlo study](https://opg.optica.org/ao/abstract.cfm?uri=ao-56-19-G179) likewise finds aerosol and multiple-scattering effects vary between solar and antisolar regions. These papers describe atmospheric behavior; they do not calibrate this simulator’s palette.

For LU-13, test a bounded **artistic** chromaticity correction on the diffuse sky only: retain the existing time, sun direction, exposure, and scalar brightness; let sky color vary with view elevation and angular distance from the sun instead of washing the entire image with the sunset hue. Compare pre/post linear luminance targets and the final Compatibility pixels at fixed exposure. Keep terrain and prop albedos untinted by any global post-process, and reject the change if aircraft contrast falls. This is a palette approximation, not photometric or atmospheric calibration.

## Recommended LU-12 material test

Use a deterministic world-space procedural grain on the existing apron batch and multiply it gently into the current vertex-color palette. Band-limit/fade the fine signal with the supported screen-footprint derivatives so it averages out before it aliases; keep the broad cell colors and grass-feathered edge as the low-frequency structure. Start with zero-mean color modulation of only a few percent as an art estimate, then tune from close parking, club, and distant approach views. Keep the surface flat and preserve current batches, collision, geometry, textures, and draw counts. For trees and shrubs, prefer small seed-driven vertex-color differences between existing crown/clump faces, baked during mesh construction.

Proof should include close and far native Compatibility captures plus unchanged draw counts and a measured material-frame cost against the LU-11 baseline. Do not add new per-prop materials, a plugin, network access, or a texture solely to solve the apron’s color uniformity.
