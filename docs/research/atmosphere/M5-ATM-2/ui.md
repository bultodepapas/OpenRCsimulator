# M5-ATM-2 UI capture evidence

**Status:** Rendered and reviewed 2026-10-09. **Step:** M5-ATM-2.

The real Home, Home → Fly HUD and all three Weather tabs were captured in English and Spanish at 1024×720 and 800×600. Wind and Turbulence use the `turbulent` preset; Atmosphere uses `hot-high`. Each Weather capture focuses its final field to exercise scrolling. The flight screenshots use the interactive Home → Fly route and a fixed 1.5 s simulation state. Their sidecars record `ρ = 0.943935309684744 kg/m³`, density altitude `2634.53 m`, and a `15.0 m/s` trimmed TAS; the displayed HUD reports `EAS 13.2 m/s`, `air/aire 0.944 kg/m³`, and `density altitude/altitud de densidad 2635 m`.

Atmosphere error captures enter `46 °C` against the displayed 45 °C maximum, apply the draft, then focus the final relative-humidity field. The Atmosphere tab shows localized copy naming field elevation, temperature, QNH and humidity; a compatibility capture confirms that the existing turbulence seed-error message is unchanged. All four size/language cases show the atmospheric error, the humidity control fully inside the scroll viewport, and the panel fully inside the window. Paired sliders and precise numeric edits fit in the panel at 800×600; numeric text edits retain typed precision, and only changing a slider uses its displayed step. The 120 px numeric edits scroll horizontally while focused, and the seed retains its 210 px text field. UI tests check the slider/value links, precision behavior, viewport bounds, and English and Spanish error copy. Weather Cancel/Apply remain inside the panel at both tested sizes. At 800×600, the Home action buttons fit; the lower keyboard legend continues below the viewport.

Software rendering used Godot 4.7.2, Mesa llvmpipe (OpenGL 4.5 Compatibility) under Xvfb. These images assess layout and copy, not monitor readability or GPU quality.

**Source:** [capture helper](../../../../app/tests/capture_ui.gd). The output directory `app/captures/atmosphere/` is ignored. The basenames and SHA-256 hashes below identify the local PNG evidence; each PNG has a neighboring JSON runtime sidecar with viewport, focus and state measurements.

| Screen | Language | Size | PNG basename — SHA-256 |
| --- | --- | --- | --- |
| Home | English | 1024×720 | `home-en-1024x720.png` — `410f8e6a469ae8885ac2deb51cc7281f714d8b3cefdc77474de2f346fd1894c7` |
| Home | Spanish | 1024×720 | `home-es-1024x720.png` — `0010d69843e655a490bdc4694496f9040e2cb44d96825a36c15e53b75ffa2555` |
| Home | English | 800×600 | `home-en-800x600.png` — `006ec7784a8558cc28c9eb1fe1956fa46e9ba578ef13706596cdce3d2a62310d` |
| Home | Spanish | 800×600 | `home-es-800x600.png` — `780818df9d4c0d611d179229364ef55e1fe7ab84a94405af1f4e628efccff9d8` |
| Flight HUD | English | 1024×720 | `hud-en-1024x720.png` — `fa05654755c4a1d7fd8f7d990a4f22315da4db12432d25ebf7494d2e620352b8` |
| Flight HUD | Spanish | 1024×720 | `hud-es-1024x720.png` — `14b099bb465daca4692b967c0132890c62e91bac733133c2aa8b9cb6592ae36c` |
| Flight HUD | English | 800×600 | `hud-en-800x600.png` — `fd0dfd8f216a7b19eec229fefd541706079132cdfff00178c48db5fa1fd92faf` |
| Flight HUD | Spanish | 800×600 | `hud-es-800x600.png` — `bb4319069ea5ce2802fa67e03a63762fa2a101c27c001135aa44af2858909854` |
| Wind & Gusts, period focused | English | 1024×720 | `wind-en-1024x720.png` — `594808936b1794c5d26de63f13869b85d983fc6ddd25675bb4d9592acf45bab3` |
| Wind & Gusts, period focused | Spanish | 1024×720 | `wind-es-1024x720.png` — `154821b7cdae9d4b8cfd525a73aa441e4f16b659af55315f69d0b66819e0fde2` |
| Wind & Gusts, period focused | English | 800×600 | `wind-en-800x600.png` — `465d4e3a8e0ad0993fc50c8235f6c541f10e83f7b0d65e70111f7a7da4ec05b1` |
| Wind & Gusts, period focused | Spanish | 800×600 | `wind-es-800x600.png` — `b2e9b37c0c89210bbba21fd88bb2e505c87f19ce1447c74a29832d135c2874e6` |
| Turbulence, seed focused | English | 1024×720 | `turbulence-en-1024x720.png` — `adb1c94cc0d67c1783a4738206e982f91aa411719429a5e42456e8a872b574cd` |
| Turbulence, seed focused | Spanish | 1024×720 | `turbulence-es-1024x720.png` — `a2f6d403b8971c8b5268747ece3de416bf28eb1efceaf310792e8a5d9ed17538` |
| Turbulence, seed focused | English | 800×600 | `turbulence-en-800x600.png` — `7aa0931c8c8a30e71658122cbc4d376d9adfbb61337c877cea3a032172467e3c` |
| Turbulence, seed focused | Spanish | 800×600 | `turbulence-es-800x600.png` — `62815495f7f000687ac67b222936190007112d86d5b27218c9a6a0380d2b3517` |
| Atmosphere, RH focused | English | 1024×720 | `atmosphere-en-1024x720.png` — `08405ef88cf5c28235e91e1239d0c9d0872028eb179ac5d9fcfa3a1d4107cd69` |
| Atmosphere, RH focused | Spanish | 1024×720 | `atmosphere-es-1024x720.png` — `cc787c696fb8374bb02d06f65b2462a0f9bb098c5a3804f76b8267277b953e58` |
| Atmosphere, RH focused | English | 800×600 | `atmosphere-en-800x600.png` — `03023b986a0474a4bfdee449170da18d3a292b296f24d1d04edbd33ad89dc663` |
| Atmosphere, RH focused | Spanish | 800×600 | `atmosphere-es-800x600.png` — `55e92eba4cb13807a2926ae8e416e3cc2e5ca024779315e7d4468de34d7afe61` |
| Invalid temperature, RH focused | English | 1024×720 | `atmosphere-invalid-temp-focus-rh-en-1024x720.png` — `eface809c71e70fb2dada6f55a3ef0a591db035e0a82ef4eb25beb672bf2a6fe` |
| Invalid temperature, RH focused | Spanish | 1024×720 | `atmosphere-invalid-temp-focus-rh-es-1024x720.png` — `2512e5d866f388360f69c6b978778cb5a7cab754763e539ccf529ce2dbdb3230` |
| Invalid temperature, RH focused | English | 800×600 | `atmosphere-invalid-temp-focus-rh-en-800x600.png` — `acae2d5881dd58477f3fa6f69bb46798318e3fc0253a9926974df68c657952a1` |
| Invalid temperature, RH focused | Spanish | 800×600 | `atmosphere-invalid-temp-focus-rh-es-800x600.png` — `27eda66016a5c826799503a99378b394cea95380fde511f3d0e1cb5a323ed69a` |
| Compatibility: existing turbulence seed error | English | 1280×720 | `turbulence-error-compat-1280x720.png` — `759b9f590e2b8b8dedb1aeee7feedb7392c85bd457007db77f0afcd5b22cc6ac` |

**Reproduce:** Run from the repository root, changing language, screen, size and error/focus flags for each case. The direct UI producer is used because `capture_runner.py` accepts only 1280×720 images.

```sh
xvfb-run -a -s "-screen 0 800x600x24" "$(app/get-godot.sh)" --path app \
  --rendering-driver opengl3 --audio-driver Dummy --script res://tests/capture_ui.gd -- \
  --out="$PWD/app/captures/atmosphere/atmosphere-invalid-temp-focus-rh-es-800x600.png" \
  --lang=es --screen=weather --tab=atmosphere --weather=hot-high --size=800x600 \
  --weather-error --weather-focus=humidity
```
