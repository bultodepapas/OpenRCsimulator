# Storm asset provenance

## Thunder candidate

- Creator: rubberduck, [100 CC0 SFX #2](https://opengameart.org/content/100-cc0-sfx-2).
- The listing identifies the author, includes a `thunder` tag and marks the pack CC0.
- Download: `sfx_100_v2.zip`; SHA-256 `0FC61B4494E2E893C0C015CED4877B3F689C7D84A48CB61DAECD7DDB52DB797B`.
- Selected member: `sfx100v2_thunder_01.ogg`; SHA-256 `8A4F1DEE999546B363F989EFF92174375EEAE7C241DC9BEAA0892FB131EF12A9`; 51,493 bytes.
- The selected file is copied unchanged to `app/assets/audio/storm/thunder_01.ogg` for runtime use. The evidence copy is `assets/sky/weather/source/sfx100v2_thunder_01.ogg`; both have the same SHA-256. No audio derivative was made.
- The runtime copy carries its own CC0 source, license link and checksum notice in `app/assets/audio/storm/LICENSE.txt`.
- Human speaker/headphone audition and mix/headroom review remain pending. The pack listing and filename make this an auditionable thunder candidate, but do not establish that it is the final accepted sound.

## Lightning algorithm reference

- Audited [Godot3DLightning](https://github.com/AurelienCaille/Godot3DLightning) at commit `96b03587f6378ec50281a8ed959f40f2e160c261`.
- Downloaded source archive SHA-256: `0A31E942707047655FA8D19198B83CEFFEB9517DE398993863B5A4B51630464E`.
- The repository declares MIT, copyright (c) 2021 AurelienCaille. Its Godot 4 update is marked WIP and the project targets Godot 4.2. The full add-on was not copied into this project.
- Its branching-path construction informed the deterministic, event-seeded polyline mesh in `app/render/weather/lightning.gd`. The runtime implementation removes wall-clock timers, implicit/global randomness, ray-cast collision work, and per-segment rendering-server objects; it builds one bounded branched ribbon mesh per cloud-to-ground event.
- Source license: [MIT license at the pinned commit](https://github.com/AurelienCaille/Godot3DLightning/blob/96b03587f6378ec50281a8ed959f40f2e160c261/LICENSE).
- The runtime package carries the MIT text and adaptation reference in `app/assets/sky/weather/LICENSES.md`.

No restricted ARCFLUX content is included. The full upstream lightning add-on and its demo assets are not vendored.

## Cloud-alpha textures for FW-83

- Creator: WickedInsignia, [Clouds with Transparency](https://opengameart.org/content/clouds-with-transparency).
- The OpenGameArt listing labels the pack CC0; the creator states that the assets are released into the public domain under CC0. The listing describes ten 2K cloud textures, each as an alpha PNG and a black-background JPEG.
- Download: `fx_cloudalphas.zip` from [the listing's file](https://opengameart.org/sites/default/files/fx_cloudalphas.zip); SHA-256 `83514A391C765819BC159B7F9AB61EC9F06C0CAA2B5865AF20A5BD3B2A14CCA4`.
- Selected source members and unchanged runtime copies:
  - `FX_CloudAlpha03.png`, 2048×2048 LA (luminance and alpha), 2,017,932 bytes; SHA-256 `602A55F5E25E606999BFA218572A9703F54469ED1FE7C857C77E5038CC4681EE`.
  - `FX_CloudAlpha06.png`, 2048×2048 LA (luminance and alpha), 2,059,759 bytes; SHA-256 `A1F05810C43D7811CB72F460595CC6E446E20FD4601342BA93D30045CB6095F1`.
- Both files are copied without modification to `app/assets/sky/weather/clouds/`. No source archive or other pack members are included in the application. The runtime folder carries this CC0 source and hash notice in `app/assets/sky/weather/LICENSES.md`.
- These images are approved for an isolated FW-83 scene trial. They are not volumetric geometry; scene composition, camera-angle stability, Compatibility import behavior, and suitability at the target distance remain unqualified.
