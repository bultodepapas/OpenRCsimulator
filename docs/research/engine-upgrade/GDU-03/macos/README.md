# GDU-08a: beta1 universal macOS template workaround

2026-10-25, Windows x86-64, official editor
`4.8.beta1.official.4d10419ca`. A project-local template corrects the reproduced
release/debug inversion without modifying the editor or installed official
templates. This is cross-export evidence, not native macOS execution.

The beta1 exporter skips the matching debug/release binary names when building a
universal executable. [Upstream PR #124757](https://github.com/godotengine/godot/pull/124757)
corrects that conditional. The local helper instead swaps the four official
binary payloads in a separate ZIP, retaining entry names, permissions, timestamps,
comments and nonbinary content. Both architectures retain their original payload
bytes before the exporter performs its normal bundle signing.

| Actual minimal-project export | arm64 and x86-64 result |
| --- | --- |
| Official ZIP, release export | Debug UUIDs: regression reproduced |
| Official ZIP, debug export | Release UUIDs: regression reproduced |
| Corrected ZIP, release export | Official release UUIDs |
| Corrected ZIP, debug export | Official debug UUIDs |

All four bundles pass the existing `app/tests/check_macos_export.py` check:
one executable, universal arm64/x86-64 and ad-hoc signatures on both slices.
The two imports and four exports have zero engine errors/warnings. All twelve
tests pass: eight unit checks and four real export controls. The installed
official ZIP's SHA-512 is unchanged after the tests. The UUIDs, payload hashes,
official archive/component pins, checked invocations and tool identities are in
[verification.json](verification.json).

`app/get-templates.sh` prepares the ignored
`app/.godot/export_templates/macos-universal-4.8-beta1.zip`, including when the
official templates are already installed. The macOS preset selects it through
`res://` for debug and release; actual exports prove resource-path resolution.
Windows and Linux preset sections are unchanged. A second getter run preserves
the cached ZIP's timestamp. The helper rejects unknown source ZIPs, unexpected
cached edits and non-universal macOS presets. Other projects retain the original
global templates.

Normal preparation remains `app/get-templates.sh`. To prepare only this cache:

```powershell
python tools/godot/macos_universal_template.py --source "$env:APPDATA/Godot/export_templates/4.8.beta1/macos.zip" --project app
python -B -m unittest tools.godot.test_macos_universal_template -v
```

Real controls are opt-in and require a new evidence directory. Put all temporary
and editor-cache locations on a drive with enough space:

```powershell
$env:OPENRC_MACOS_EXPORT_GODOT=(Resolve-Path '.tools/Godot_v4.8-beta1_win64_console.exe').Path
$env:OPENRC_MACOS_TEMPLATE_SOURCE=(Resolve-Path "$env:APPDATA/Godot/export_templates/4.8.beta1/macos.zip").Path
$env:OPENRC_MACOS_TEST_OUT='D:/OpenRCsimulator-experiments/gdu03-macos/new-export-controls'
$env:TEMP='D:/OpenRCsimulator-experiments/gdu03-macos/process-temp'
$env:TMP=$env:TEMP
$env:LOCALAPPDATA='D:/OpenRCsimulator-experiments/gdu03-macos/process-local'
New-Item -ItemType Directory -Path $env:TEMP,$env:LOCALAPPDATA -Force | Out-Null
python -B -m unittest tools.godot.test_macos_universal_template -v
```

The final raw artifacts are under
`D:/OpenRCsimulator-experiments/gdu03-macos/export-controls-20261025-r3/`.
Earlier rejected checks remain on D: the first fixture omitted required empty
include/exclude filters; the second encountered invalid Mach-O/signing diagnostics
while C filled and exporter temporary files still used C. The final run redirects
APPDATA, LOCALAPPDATA, TEMP and TMP to D. No diagnostic was suppressed.

This cache is **only for beta1 universal exports**. When using an engine containing
the upstream fix, remove both macOS `custom_template` keys and the helper call
from `get-templates.sh`, and return to the official template. Single-architecture
exports must also use the original official ZIP. The beta1 workaround must not
be carried forward unchanged.

The fixture does not establish full OpenRC macOS package qualification, native
launch on Intel or Apple Silicon, Gatekeeper acceptance, notarization or signing
with an Apple developer identity. Those [upgrade gates](../../../../plans/godot-4.8-upgrade.md)
remain separate.
