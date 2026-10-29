# DT-LNX-02a/b — export isolation and template integrity

2026-10-28. Implemented first increment of [DT-LNX-02](../../../plans/linux-support-distribution.md): protect existing outputs, select the successful CI artifact set and authenticate installed templates. Full release manifests and platform acceptance remain open. Current commands live in [TOOLS](../../../TOOLS.md#release-sequence).

## Delivered behavior

- `app/export.sh` reserves a new `dist/export-XXXXXXXX/`, or a new directory selected by `--output-dir`. Existing destinations and partial outputs survive. Canonical paths exclude the application and Git metadata, including linked-worktree metadata and symlink aliases.
- A checkout lock refuses a competing exporter before cache/import/native preparation. Separate checkouts can export independently; the lock does not coordinate an editor or unrelated build process, so an isolated export checkout is still required.
- The existing package qualification checks remain in place. Only after three named archives and their checksums succeed does the script emit the CI output directory and build version. CI uploads those exact files and verifies checksums after downloading them for release.
- `app/get-templates.sh` verifies all four installed release-template members against source-controlled SHA-512 pins on every invocation. Cold installation verifies the archive, staging and exclusively created destination files, preserving extracted permissions. Changed, incomplete or conflicting caches are retained and refused. A shared cache lock prevents competing getters from publishing simultaneously.

Independent review found symlinked-checkout path validation, truncation of an existing lock file and linked-worktree common metadata gaps. All three were corrected and covered by focused regressions. No runtime, renderer or simulation behavior changed in this increment.

## Verification

[validation.json](validation.json) records the exact LF-normalized source hashes, source HEAD, commands and results. A fresh shared-object clone checked out the relevant tracked subtrees and overlaid the identified working files; it was not a clean release candidate. Tests used disposable fixture repositories and dummy export payloads.

| Check | Result | Evidence boundary |
| --- | --- | --- |
| `python3 app/tests/test_export_identity.py` | 25 passed | Identity guards; output preservation; path/symlink/worktree protection; competing export; real shell ZIP/checksum/output-handoff commands with fixture payloads |
| `python3 app/tests/test_ci_partitions.py` | 9 passed | Existing CI partition contracts |
| `python3 -m unittest tools.godot.test_get_templates tools.godot.test_macos_universal_template` | 19 passed; 4 skipped | Cache/archive integrity, installation conflicts and macOS template correction; optional real-engine export controls skipped |
| `bash -n app/export.sh app/get-templates.sh` | Passed | Shell syntax |

The template/macOS helper suite also passed on Windows with Git Bash (19 passed, 4 skipped). The Linux cold-install fixture verifies that an executable template retains its extracted `0750` mode under a `022` umask; existing warm-cache permissions are not rewritten.

The template specialist also verified the actual 1,361,700,690-byte [official 4.8-beta1 template archive](https://github.com/godotengine/godot-builds/releases/download/4.8-beta1/Godot_v4.8-beta1_export_templates.tpz) against the pre-existing archive SHA-512 pin before deriving the four member pins in `app/get-templates.sh`. An isolated project and XDG data root with spaces passed cold installation and the real macOS correction. Removing the archive and blocking network access still allowed the warm cache; altering `version.txt` caused rejection without replacing it. This was a template acquisition check, not a Godot application export. Large temporary archive/template copies were removed after verification.

## Remaining evidence

No fully provisioned native application export, GitHub Actions artifact upload/release run, native macOS launch or GPU/controller/performance acceptance was performed. The existing NK-3 and ground-vehicle source/ABI/receipt/package checks were preserved. No packages were published and no additional distro or architecture is claimed supported.

Next complete DT-LNX-02's release manifest and tool provenance, run the provisioned export pipeline, and measure DT-LNX-01's final-payload ABI floor before selecting package runtime baselines. AppImage, Flatpak, DEB/RPM and ARM64 remain separate gated implementation steps in the Linux plan.
