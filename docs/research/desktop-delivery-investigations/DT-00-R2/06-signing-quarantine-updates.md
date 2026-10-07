# 06 — Signature policy, quarantine, and whole-app updates

2026-10-07 · DT-00-R2 · **Static checker/source audit; no Developer ID, Gatekeeper, or update test.**

## Question and scope

Can the current macOS structural checker coexist with a Developer ID release, and what must be verified across native dependencies, first launch,
and replacement updates? The ZIP/DMG submission and staple order is already covered by [DT-00-R1-02](../DT-00-R1/02-macos-trust-pipeline.md); this
investigation concentrates on signature policy and lifecycle evidence rather than repeating container instructions.

## Findings

1. The current `macOS` preset requests universal export and built-in code signing, but sets `notarization/notarization=0`. The existing exported
   archive has ad-hoc CodeDirectories; no Developer ID release identity is configured in the preset. [Preset](../../../../app/export_presets.cfg),
   [DT-00-R1-02](../DT-00-R1/02-macos-trust-pipeline.md).
2. `app/tests/check_macos_export.py` checks executable mode, the two architecture slices, and CodeDirectory flags for the main executable. It
   accepts a slice only when `CS_ADHOC` is set, reporting the exact phrase `ad-hoc signed`; a valid non-ad-hoc Developer ID signature therefore
   fails the current policy. [Checker](../../../../app/tests/check_macos_export.py).
3. The checker parses flag bits only. It does not hash/verify signed code pages, identify a signing authority, inspect entitlements, enumerate
   nested code, verify a notarization ticket, or ask Gatekeeper to assess the downloaded artifact. A structurally plausible ZIP can pass without
   containing any valid cryptographic signature.
4. The isolated [checker-contract probe](probes/checker_contract_probe.py) confirms the boundary: synthetic ZIP metadata with flags `0x10002`
   (ad-hoc plus runtime) exits 0, while synthetic non-ad-hoc runtime flags `0x10000` exit 1. The [recorded
   results](probes/checker-contract-results.json) state that neither fixture contains a valid executable/signature and no macOS launch or trust
   verification occurred.
5. The existing ignored ZIP's CodeDirectories also report `0x10002` for both slices. That records `CS_ADHOC` and the hardened-runtime flag in this
   parsed artifact; the static probe does not establish signed content integrity, entitlements, Developer ID identity, timestamp, notarization, or
   Gatekeeper acceptance. [Artifact metadata](probes/macos_macho_probe.json).
6. Keep the useful structural assertions, but name the trust mode by pipeline stage: an engineering export may be required to be ad-hoc; a public
   candidate must meet the chosen Developer ID release policy. Do not treat “has runtime flag” or “is not ad-hoc” as cryptographic proof. Validate
   trust natively on macOS after export and after final package transforms.
7. For a Developer ID candidate, verify the complete code signature and identity, hardened-runtime options, timestamp, and notary result. Use
   `codesign --verify --deep --strict` for verification only; Apple warns against using `--deep` as a signing shortcut. Inspect nested items
   individually so a missing architecture or unsigned plug-in cannot hide behind a successful outer-bundle check. [Apple signing
   guide](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac),
   [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/).
8. Hardened runtime applies library validation by default: Apple and code signed by the same Team ID can be loaded, while other third-party code is
   rejected unless the app opts out. Do not add `com.apple.security.cs.disable-library-validation` as a convenience. If a GDExtension is later
   shipped, give it a matching architecture and sign it with the release team; only consider the exception after a concrete dependency proves it
   necessary. [Apple library-validation
   entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.disable-library-validation).
9. This repository currently has no production `.gdextension` or native library under `app/`; the experimental native-slipstream files and vendored
   test fixture are not shipped app dependencies. The present app has no source-audited reason to weaken library validation. Re-run the inventory
   whenever a native library is added.
10. Apple describes code identity across versions through a designated requirement. Preserve the intended bundle/code identifier and Team ID,
   inspect the actual designated requirements of old and new builds, and test a replacement update; bundle identifier equality alone is not proof
   that macOS recognizes the same code identity. [Apple
   TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
11. A signed app bundle is sealed against modification. Treat it as immutable after signing: do not patch the PCK, executable, or resources in
   place; quit the old app and replace the complete `.app` with the verified release. Keep preferences, calibration, traces, and logs in Godot's
   writable `user://` location, outside the bundle. [Apple bundle
   guidance](https://developer.apple.com/documentation/xcode/embedding-nonstandard-code-structures-in-a-bundle), [Godot data
   paths](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html).
12. Quarantined downloads can be translocated by Gatekeeper on first launch when launched from a randomized location. Do not rely on a working
   directory or unsigned resources beside the bundle; exercise the first Finder launch before moving the app, then test a later launch and an update
   in Applications. Keep the browser quarantine attribute intact in public acceptance. [Apple packaging and
   translocation](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).
13. The current app embeds its project resources within the app bundle and uses Godot's external user-data location for personal state; that is
   compatible with an immutable-bundle update model. Confirm exact exported layout and preserved user data on the candidate rather than relying only
   on source configuration. [Godot paths](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html).
14. General ZIP/DMG notarization and stapling order, offline ticket behavior, final artifact hashing, and clean-account launch cases remain in
   DT-00-R1-02/07/08. This report adds the specific need to compare signature identity and test a full version-N-to-N+1 replacement while quarantine
   and personal state are preserved.

## DT mapping

- **DT-08/08a:** retain structural architecture/mode checks and add an explicit trust-stage label. Tie every result to the exact candidate hash and
  source/build identity.
- **DT-09c:** require Developer ID identity, signature validity for every nested code object, intended entitlements, hardened runtime/library
  validation, accepted notary evidence, and Gatekeeper assessment of the exact downloaded package. Keep the public trust test on Mac.
- **DT-12:** from a clean user account, launch the quarantined download in place, move it to Applications, relaunch, then replace an installed prior
  version. Compare bundle ID, Team ID, designated requirement, package hash, settings/calibration/trace survival, and launch/trust results. Do not
  remove quarantine or weaken Gatekeeper to make a failing candidate pass.

## Native release acceptance — UNRUN

The following commands were not run here. Run them on the exact signed and notarized macOS candidate after extracting the final package.

```sh
APP="/Applications/OpenRC Simulator.app"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1
codesign -dr - "$APP" 2>&1
codesign -d --entitlements :- "$APP" 2>&1
spctl --assess --type execute --verbose=4 "$APP"
xcrun stapler validate -v "$APP"
xattr -p com.apple.quarantine "$APP"
```

Inventory every Mach-O/framework/helper, verify its architecture and signature, and record each entitlement set; do not infer nested validity from
the main executable's flags. Preserve the exact downloaded quarantine attribute, launch through Finder, and retain Gatekeeper/notary logs. On a
disposable account, install version N, create settings/calibration data, quit, replace the full app with N+1, then confirm launch and user-data
continuity. Commands and lifecycle cases above are acceptance proposals, not test results.

## Sources and limits

The current checker behavior and synthetic probe establish a parser-policy mismatch, not a macOS security bypass. Linux inspection cannot determine
whether any candidate is trusted by macOS. Notarization credentials, a Developer ID identity, a quarantined browser download, a Mac host, and a
clean-user update test were unavailable.

Sources accessed 2026-10-07: Apple [distribution code
signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac),
[TN2206](https://developer.apple.com/library/archive/technotes/tn2206/), [library
validation](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.disable-library-validation), [code
requirements TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), [bundle
structure](https://developer.apple.com/documentation/xcode/embedding-nonstandard-code-structures-in-a-bundle), [packaging and Gatekeeper
translocation](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), and Godot 4.7 [macOS
export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html) / [data
paths](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html). See the prior report for the separate [ZIP/DMG notarization
sequence](../DT-00-R1/02-macos-trust-pipeline.md).
