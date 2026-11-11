# Country flag assets

The landscape flag uses downloaded public-domain SVG artwork. The pinned file
revisions, source pages, dimensions, hashes and license records are in
[`SOURCES.json`](../../assets/landscape/flags/SOURCES.json). Runtime textures are
opaque PNGs with a 512 px long edge and mipmaps; original aspect ratios determine
the cloth dimensions. No network request occurs in the game.

Use the pinned Godot engine through the [checked runner](../godot/README.md):

```powershell
python tools/godot/run_checked.py --timeout 120 -- C:/DEVELOPMENT/OpenRCsimulator/.tools/Godot_v4.8-beta2_win64_console.exe --headless --path app --script res://../tools/flags/build.gd -- --check
```

Omit `--check` to regenerate PNGs, import settings, the path-only country manifest
and the packaged provenance notice. Generation verifies source hashes and refuses
unreviewed transparency or reverse policies. Import the regenerated resources
before running `app/tests/test_flag_identity.gd`.

To extend the set, download and record the exact original SVG revision, verify its
license and flag variant, then update the source manifest and regenerate. The
`spanish_selection` property admits a country to the Spanish pool. A new supported language
also needs a mapping in `app/app_state/flag_identity.gd`. Flags with different
front/back artwork require a renderer and manifest-policy extension; Paraguay is
currently excluded for that reason.

The application retains one cosmetic identity. Spanish is chosen once during
that application's lifetime using its own RNG; scenery rebuilds and changes away
from and back to Spanish preserve it. Other supported locales map directly to
their configured country. Runtime texture requests are coalesced per flag and
owned until completion, including when their landscape is unloaded.
