# macOS Trust and Packaging Pipeline

2026-10-07 · DT-00-R1 · Scope: universal app, Developer ID signing, notarization, ZIP/DMG order, quarantine.

## Question and method

What exact pipeline turns the current ad-hoc universal app ZIP into a public direct-download candidate? I read the DT plan, Mac export preset, `app/export.sh`, Mac archive/version checks, app source inventory, first-launch guide, Godot 4.7 macOS export/GDExtension documents, and Apple’s current signing, packaging, and notarization material. Accessed 2026-10-07.

## Findings

| Question | Evidence | Consequence for this project |
| --- | --- | --- |
| What does Godot export today? | Godot 4.7 emits a Universal 2 `.app` for x86_64 + arm64 and can produce an `.app`, ZIP, or DMG; DMG export is supported only from macOS ([Godot macOS export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html)). | Keep the existing universal preset and Linux-built ZIP validation. A DMG needs a Mac packaging job. |
| What is the current trust level? | `app/export_presets.cfg` keeps bundle ID `io.github.bultodepapas.openrcsimulator`, enables built-in code signing, and disables notarization. `check_macos_export.py` verifies the main executable is executable, has x86_64 and arm64 slices, and is ad-hoc signed. | The audit proves no configured Developer ID release-signing/notarization path. The checker does not inspect hardened-runtime flags, entitlements, or timestamps, so their status is unknown. An ad-hoc signature is not Developer ID trust and does not establish Gatekeeper acceptance or offline-launch behavior. |
| What must be signed? | Apple requires Developer ID distribution signing and hardened runtime for notarization; include a secure timestamp, review the notary log, and do not use `get-task-allow=true` ([notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)). Apple’s signing guide says sign nested code inside-out and do not apply entitlements to library code ([signing guide](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)). | Sign every nested executable/library first, then the outer `.app`. Keep entitlements on the executable only; turn off Godot’s Debugging entitlement. |
| Which package gets signed/notarized? | Apple says sign code and each signable nested container from the inside out. A DMG can be signed, which protects its contents; only notarize the outermost container when distributing nested formats ([packaging guide](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)). | DMG route: sign nested code → sign app → build DMG → sign DMG → submit DMG → inspect result → staple DMG → validate final DMG. This project has one app bundle, so no installer PKG is justified. |
| What is the ZIP-specific order? | Apple says ZIP itself cannot be signed or stapled. It can be submitted to notarization, but staple the ticket to each packaged item (the `.app`) and then rebuild the ZIP ([custom workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)). Apple notes that un-stapled distribution may be blocked while offline ([packaging guide](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)). | ZIP route: sign app → `ditto` ZIP → notarize ZIP → staple ticket to app inside → recreate ZIP with `ditto` → hash final ZIP. Never staple the archive or hash it before repacking. |
| Does Godot allow signing from Linux? | Godot’s 4.7 guide documents `rcodesign` for signing/notarizing from Linux or Windows using a Developer ID PKCS#12 certificate and App Store Connect API key; it requires disabling the Debugging entitlement and supports stapling ([Godot macOS export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html#code-signing-and-notarization)). | This is a feasible alternative for app signing; it does not remove the Mac-host requirement for Godot’s DMG export or native Gatekeeper smoke. Pin/verify tools during DT-06, not in this research report. |
| How should GDExtension change the policy? | Repository scan found no `.gdextension`, `.dylib`, `.so`, `.framework`, or `.dll` under `app/`; `addons/build_info` is an editor-side GDScript plug-in. Godot’s `.gdextension` manifest selects native libraries by platform/architecture and places macOS dependencies under `Contents/Frameworks` ([GDExtension file](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/gdextension_file.html)). | No extension signing is needed in today’s app. If native code is added, require a universal Mach-O or explicit x86_64/arm64 variants, bundle dependencies in the documented location, sign each item inside-out, and check both slices in the exported app. |
| Which entitlements are justified? | Godot exposes “Disable Library Validation” for GDExtension, ad-hoc signing, or external add-ons ([Godot entitlement list](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html#entitlements)); Apple says entitlements grant executable privileges and libraries should not receive them ([Apple signing guide](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)). | The current app has no native extensions. For a Developer ID candidate, begin with minimal entitlements, no debugging, and library validation enabled; add a broader entitlement only after a native extension proves it necessary. |
| What must the user-download test cover? | Apple recommends testing a fresh distribution on another Mac when possible, plus upgrade, duplicate-location, and different-account cases. For ZIP/DMG, test first launch in place (Gatekeeper can translocate it), later launch, and launch after moving to Applications ([Apple packaging tests](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)). | Test the exact browser-downloaded, quarantined artifact with network available and disabled. Do not strip quarantine or weaken Gatekeeper in a public release path. |

## Local audit and limits

| Inspected item | Observed in repository | Not established |
| --- | --- | --- |
| `app/export_presets.cfg`, `app/export.sh` | `macOS` preset is universal, bundle ID is stable, built-in signing is on, notarization is off. Linux CI exports `OpenRC Simulator.zip`; the Mac checker parses the main Mach-O and permissions; version check reads plist fields. | No Developer ID release-signing identity/path, notarization, staple, DMG, or Mac GUI smoke is configured. Hardened-runtime state and timestamp are not inspected, so this audit does not establish whether either appears in an ad-hoc export. |
| `app/tests/check_macos_export.py` | Checks one `Contents/MacOS` binary for executable mode, both CPU slices, and an ad-hoc signature. | It does not inventory/signature-verify every nested code item, inspect hardened-runtime flags or entitlements, validate a notary ticket, assess Gatekeeper, or run either CPU architecture on hardware. |
| App source tree and first-launch guide | No current native extension payload under `app/`; `docs/FIRST-LAUNCH.md` tells users to remove quarantine with `xattr` for the “damaged” warning. | No Mac hardware, certificate, Xcode/notary credential, quarantined browser download, or offline test was available. The workaround is not public-channel acceptance evidence. |

Godot’s 4.7 documentation was directly opened and read. Apple’s HTML pages rendered as JavaScript shells, so this pass fetched and read the relevant official Apple DocC JSON directly: notarization workflow, packaging for distribution, distribution signing, and notarization requirements. The JSON confirms the ZIP/DMG sequence and inside-out signing rules described above. No build, signing, notarization, or native test was performed; steps below are proposed acceptance criteria, not measurements.

## Exact release-container sequence

For the preferred DMG path, freeze icons, plist/version fields, resources, and the bundle ID before signing. Then:

1. Enumerate every Mach-O/framework/helper in the app bundle; confirm every shipped architecture is intentional.
2. Sign nested frameworks, helpers, extensions, and libraries from the inside out with the distribution identity.
3. Sign the outer `.app` last with Developer ID Application, hardened runtime, secure timestamp, and only approved executable entitlements.
4. Verify the app’s nested signatures and both CPU slices before packaging. Do not use `codesign --deep` as a signing shortcut.
5. Create the read-only DMG from that verified app, then sign the DMG with Developer ID Application and a unique container identifier.
6. Submit the DMG as the outermost notary object; wait for `Accepted`, retain the full notary log, then staple the DMG.
7. Validate the staple and image, download the exact final DMG in a clean account, and calculate SHA-256 only after stapling.

Use the current Apple [notarytool workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) or documented Notary API, not obsolete upload tooling. Retain the submission identifier and inspect warnings even when status is accepted; a successful service response is not a substitute for local signature verification.

If retaining ZIP as an alternate, use Apple’s separate ZIP order: sign and verify the app, create the ZIP with `ditto --keepParent`, submit that ZIP, staple the accepted ticket to the `.app` inside the archive, rebuild the ZIP, and hash the rebuilt artifact. ZIP cannot carry a stapled ticket itself. Do not notarize both an inner app and an outer DMG when the DMG is the user-facing container; Apple’s nested-container guidance says to notarize the outermost package only.

First-run testing should retain the browser quarantine attribute. Test opening directly from the mounted DMG before moving the app, then move it to `/Applications` and test again; also test a later launch, an upgrade over an existing version, a duplicate copy, and an offline first launch after stapling. A ticket that is only discoverable online does not prove offline acceptance.

## Recommendation for existing DT phases

Keep the current stable bundle ID, preset name `macOS`, universal architecture, `0.1.0` numeric version fields, and `git describe` app identity. Retain the ad-hoc ZIP only as an engineering artifact until DT-09c. For the public direct-download candidate, prefer one signed/notarized/stapled DMG with drag-to-Applications presentation if the Mac runner can build it; keep ZIP as a separately tested option only if it adds distribution value. Do not add a PKG for a single self-contained app.

At DT-06, pin the Mac signing/notarization toolchain and establish a credential-free export check plus a trusted release signing lane. DT-08 must hash only after signing, notarization, and stapling. DT-09c must gate the final downloaded package rather than an unpacked build directory.

| DT-09c proof | Pass condition |
| --- | --- |
| Identity and slices | `codesign -dv --verbose=4` reports the intended Developer ID and stable bundle identifier; `lipo -archs` reports x86_64 and arm64 for the main binary and every native payload. |
| Signature and entitlements | `codesign --verify --deep --strict --verbose=2` succeeds; inspect each nested code item and the notary log; hardened runtime and secure timestamp present; no debugging entitlement or unneeded library-validation exception. Do not use `--deep` to sign. |
| DMG pipeline | Verify signed app and DMG before submission; record `notarytool` accepted status and full log; `xcrun stapler validate` and `hdiutil verify` succeed on the final DMG; record final SHA-256 after stapling. |
| ZIP alternative | ZIP contains the stapled app with executable mode preserved; extract with Finder and validate the app ticket; calculate hash only after repacking. |
| Quarantine/Gatekeeper | Download through a real browser to a clean account; assess first launch in place, move to Applications, relaunch, upgrade, and a duplicate-location case; repeat offline after stapling. No `xattr` removal or system-security change is allowed for public acceptance. |
| Flight behavior | On Intel and Apple Silicon when both are claimed: Home → Fly → pause → End → Quit, radio connect/calibrate/reconnect, fullscreen recovery, settings persistence, and no startup/runtime engine errors. |

## Primary sources

- [Godot 4.7 macOS export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html) and [GDExtension libraries](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/gdextension_file.html)
- Apple: [distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/), [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [custom notarization and ZIP stapling](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [package formats and test cases](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution). The corresponding official DocC JSON payloads were directly inspected for this report: [signing](https://developer.apple.com/tutorials/data/documentation/xcode/creating-distribution-signed-code-for-the-mac.json), [notarization](https://developer.apple.com/tutorials/data/documentation/security/notarizing-macos-software-before-distribution.json), [workflow](https://developer.apple.com/tutorials/data/documentation/security/customizing-the-notarization-workflow.json), and [packaging](https://developer.apple.com/tutorials/data/documentation/xcode/packaging-mac-software-for-distribution.json).
- [Godot 4.7 user-data paths](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html)
