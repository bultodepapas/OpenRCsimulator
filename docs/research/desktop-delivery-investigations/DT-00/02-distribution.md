# DT-00/02 — Desktop distribution: packaging, signing, and native libraries

**Status:** research report, 2026-10-07. **Serves:** desktop-delivery planning. **Scope:** Windows and macOS distribution only; window/full-screen behavior and performance are tracked separately.

## Code audit

Observed in the current checkout; this is not a Windows or macOS execution test.

| Area | Current state |
| --- | --- |
| Export identities | Godot preset names are `Linux`, `Windows`, and `macOS`; keep these CLI names stable. `project.godot` is version `0.1.0`. Windows is x86_64 with an embedded PCK and product name `OpenRC Simulator`. |
| Windows output | `app/export.sh` produces `OpenRC Simulator.exe`, then `openrc-simulator-<git-describe>-windows-x86_64.zip`. The export preset has no Authenticode signing configured. This is a portable build, not an installer. |
| macOS output | The preset exports a universal app as `OpenRC Simulator.zip`, with bundle ID `io.github.bultodepapas.openrcsimulator`, ad-hoc signing enabled, and notarization disabled. The version fields defer to the project version. Preserve the preset and bundle identities. |
| CI and checks | Release CI runs on `ubuntu-24.04`. It checks the Linux exported flight and pack contents, inspects the Mac ZIP for executable permission, x86_64 + arm64 slices and ad-hoc signatures, and checks version metadata. It does not launch the Windows or macOS app on those systems. |
| Native extensions | No `.gdextension`, `.dll`, `.dylib`, or `.so` is present under `app/`. Native experiments are research-only; the shipped app currently has no GDExtension packaging requirement. |

The repository's first-launch guide currently asks Mac users to remove quarantine with `xattr` and says Windows Smart App Control must be turned off to run an unsigned build. Those are alpha workarounds, not acceptable instructions for a public release ([FIRST-LAUNCH.md](../../../FIRST-LAUNCH.md)).

## Findings from primary sources

### Windows: portable ZIP, installer, or Store package

Godot's Windows export bundles the project into an optimized executable and supports x86_64, x86_32, and arm64. Its documentation supports Authenticode export signing with Windows SDK SignTool or `osslsigncode` on other build hosts ([Godot 4.7 Windows export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_windows.html)).

| Delivery | Fit and obligations |
| --- | --- |
| Portable ZIP (current) | Lowest maintenance and suitable for a pilot build. It has no install, uninstall, or update flow. Sign the contained `.exe` before hashing and zipping if this becomes a public build. |
| Inno Setup installer | Appropriate if users need Start-menu shortcuts, a normal uninstall entry, or guided per-user installation. Its `[Setup]` and `[Files]` sections support these mechanics. Sign the installer and the app executable with Authenticode. Inno's own `.issig` integrity signature is not Authenticode and does not remove the Windows unknown-publisher warning ([Setup](https://jrsoftware.org/ishelp/topic_setupsection.htm), [Files](https://jrsoftware.org/ishelp/topic_filessection.htm), [signature distinction](https://jrsoftware.org/ishelp/topic_issig.htm)). |
| MSIX / Microsoft Store | Consider when Store discovery, managed installation, or Store updates justify packaging and submission work. Microsoft re-signs Store MSIX submissions; direct MSIX needs a trusted certificate and a separate update channel. The Store's MSI/EXE route still requires the publisher to sign the installer and its PE files ([Microsoft distribution paths](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/choose-distribution-path), [signing options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)). |

Microsoft documents that new signed downloads can still receive SmartScreen prompts until reputation accumulates; signing gives publisher identity, not instant trust. Its current documentation also limits Azure Artifact Signing availability by developer type and region, so check the maintainer's eligibility before choosing a signing provider. Do not tell general users to turn off Smart App Control; use a signed public channel and reserve unsigned exceptions for explicitly invited alpha testers ([SmartScreen reputation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation), [Smart App Control](https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview)).

Inno Setup defaults to administrative privileges; per-user installation must explicitly select `PrivilegesRequired=lowest` and compatible per-user paths/shortcuts. Test with a standard account rather than assuming the installer is non-elevating. [Inno privilege policy](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm).

All containers need the project's notice and applicable Godot/third-party license information. A product-name copyright field alone is not an attribution inventory. Include accessible offline notices and audit redistributed assets against their provenance. [Godot license compliance](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html).

### macOS: app ZIP, DMG, signing, and notarization

Godot's official macOS template produces a Universal 2 `.app` for Intel and Apple Silicon. It can package a ZIP on Linux; Godot only creates a DMG when exporting on macOS. The documented Linux/Windows path can also sign and notarize with `rcodesign`, a Developer ID certificate, and App Store Connect API credentials. Ad-hoc signing plus disabled notarization is explicitly the no-certificate mode, not the public release path ([Godot 4.7 macOS export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html)).

For default Gatekeeper acceptance of direct downloads outside the Mac App Store, use Developer ID signing and notarization. A notarized build needs hardened runtime and valid signatures on distributed executable code; Godot's export instructions say to disable its Debugging entitlement. Staple the ticket so Gatekeeper can validate the shipped artifact while offline. A ZIP is an acceptable direct-distribution container but cannot itself be signed or stapled: staple its app bundle, then recreate the ZIP. A DMG can be signed and stapled as the outer container and gives the familiar drag-to-Applications flow for a single app. Reserve a signed `.pkg` for multiple components, fixed destinations, or custom installation actions ([Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Godot 4.7 macOS export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html), [Apple ZIP stapling workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [Apple packaging choices](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)).

Recommendation: keep the current universal ZIP for private previews. Before public distribution, move to Developer ID signing, notarization, and stapling. The ZIP can retain Linux export through `rcodesign`; DMG creation needs a Mac packaging host. Native Mac launch and trust checks are required in either case. Keep `io.github.bultodepapas.openrcsimulator`; verify the signing team can maintain this existing identity before the first notarized release. The first-launch `xattr` workaround should be clearly labeled as private-preview troubleshooting, not the public install path.

### Future GDExtension packaging

Godot's `.gdextension` file maps feature tags to separate native libraries by platform, build type, architecture, and precision; the exporter selects and bundles matching libraries. If a native physics extension is later approved, require release binaries for every shipped target (currently Windows x86_64, Linux x86_64, and macOS x86_64 + arm64), and verify the required `double`/`single` ABI explicitly. A universal macOS app does not prove each extension slice is universal. Sign every shipped macOS code object before submitting the app or outer container for notarization. Godot exposes a “Disable Library Validation” entitlement for GDExtension loading; review and test that entitlement instead of enabling it as a packaging shortcut ([Godot `.gdextension` format](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/gdextension_file.html), [Apple signing requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)).

## Phased recommendation

| Phase | Work and exit evidence |
| --- | --- |
| 1. Preserve the portable preview | Keep current preset names, output names, Windows x86_64 artifact, Mac universal ZIP, project version, and bundle ID. Label private previews clearly. Keep SHA-256 manifests after final packaging. |
| 2. Windows public channel | First keep the ZIP unless pilots demonstrate install/uninstall or update needs. Add Authenticode signing to the exported `.exe`; verify its signature and publisher after export. Choose Inno Setup only when installer behavior is needed, then sign both setup and payload and prove clean per-user install, upgrade, launch, and uninstall. Consider MSIX/Store only after its distribution and hardware-input constraints are demonstrated. Expect SmartScreen reputation to build over releases. |
| 3. macOS public channel | Sign with Developer ID and hardened runtime; disable debugging entitlement; notarize, inspect Apple's log, and staple. Ship the ZIP if Linux CI is retained, or test a signed/stapled DMG built on macOS for the polished single-app install. Do not use `.pkg` without a concrete multi-component or custom-install need. |
| 4. Native library gate | Only after a measured case for GDExtension: add architecture-specific build artifacts and feature-tag mappings; make missing target libraries fail export; verify load, signatures, notarization, and physics contract per exported platform. |

## Evidence limits and open checks

This report is a static audit of `app/export.sh`, `app/export_presets.cfg`, `app/tests/check_macos_export.py`, `app/tests/check_build_versions.py`, `.github/workflows/ci.yml`, and `docs/FIRST-LAUNCH.md`, plus official documentation read on 2026-10-07. No export was run and no Windows or Mac hardware was available. Clean-machine launch, Gatekeeper and SmartScreen behavior, Apple Silicon/Intel runtime behavior, USB-radio compatibility, and GPU/full-screen presentation remain unverified. The current CI's structural checks cannot establish those outcomes.

Sources are linked inline; no vendor assets or copied documentation text are included. No certificates were obtained, purchases made, or releases published.
