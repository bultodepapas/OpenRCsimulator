# GDU-12: desktop export evidence

2026-11-01. Two isolated Linux-host `app/export.sh` runs used official Godot
`4.8.beta2.official.cafc17a19` and produced Linux x86-64, Windows x86-64 and
macOS universal development archives. Both completed the existing package gates,
release-manifest verification, SHA-256 checks and separate ZIP CRC scans. The
source commit was `46b004c7b469448c29ef96168da4f03cee2c6d23`; both working
trees were dirty. No release was published.

The first run predates the concurrent warm-cache getter fix. The second includes
that fix, but both predate the subsequent Timber generated-provenance update and
the audio test correction. Their source-diff SHA-256 values were respectively
`0df408d5feee46f02f1744fe85eac2f9ab3415a9e28338d564a94a1d40f253d4` and
`70634e476add570e6a2eb460b142bafcd23d3250148efd065d599404ebf8fb9b`.
A current-source export remains pending completion of the application partitions.

| Gate | Observed result |
| --- | --- |
| Export-source native admission | All 19 oracle prerequisites, 19 guarded-loader cases and five hosts, nine installed-runtime gates, and 40 C++ boundary checks passed. The trajectory completed 14,400 ticks; the mutant produced 28,305 differences. |
| Exported Linux executable | Stage, lifecycle, replay, helicopter and helicopter-radio qualifications passed; default/reference/fallback checks and the 720-tick finite trimmed trace passed. |
| Exact player replay | Native flight replay was `complete=true`, `solver_changed=false`, `mode=exact`, with 65 rows. |
| Pack and metadata | Three field/resource checks and three eight-check rotorcraft smokes passed. Ground-native Linux/Windows payload hashes matched their receipts. The macOS bundle had executable arm64/x86-64 slices with ad-hoc signatures; Windows and macOS version fields matched `0.1.9`. |
| Provisional Windows startup | The second, pre-Timber Windows executable completed a checked headless 720-tick trimmed trace. It reported the supported GDScript reference backend; aircraft-native is Linux-only. This is not a current-source package result. |

Each run's pack checks emitted 312 nonfatal invalid-UID warnings, with valid text
paths used as fallbacks; they are not warning-free. Raw logs, captured input
metadata, ABI reports, checksums, CRC results and the retained native-run evidence
are under `D:/OpenRCsimulator-experiments/gdu-beta2/` in
`export-pre-getter-evidence/`, `export-after-getter-evidence/`,
`export-production.log`, `export-final.log` and
`windows-pre-timber-startup/`. The private deliberately mutated package copies
were omitted after their checked logs and reports were retained.

The package checks and WSL Linux execution do not establish a native Linux desktop
or macOS launch, controller behavior, target-hardware performance or physical
flight validation. The provisional Windows run is headless; final Windows visual
startup still needs its own current-source capture.
