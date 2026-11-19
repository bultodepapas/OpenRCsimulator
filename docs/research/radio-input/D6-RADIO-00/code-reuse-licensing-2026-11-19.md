# D6-RADIO-00 — EdgeTX code reuse and licensing

Research date: **2026-11-19, America/Bogota**. This follow-up answers which
upstream code to reuse, the applicable permission questions, and the most
efficient integration route. The [active plan](../../../plans/radio-display-edgetx.md)
owns delivery; the [initial investigation](README.md) owns the broader radio,
telemetry and flight-session evidence.

**Recommendation:** reuse a pinned EdgeTX firmware simulator as a cohesive
component, then write a small OpenRC adapter, radio presentation and lessons.
Start with T18-H7 on stable 2.12.5. Do not recreate the complete firmware or
translate scattered mixer/menu routines into GDScript. This is an engineering
recommendation with an unresolved distribution boundary, not a completed legal
opinion or a claim that a working integration exists.

## Exact scope and source identities

| Component | Inspected identity |
| --- | --- |
| OpenRC and prior plan | [24455097e7632817cc6503821f0f3d26d55d6c30][openrc-plan]; runtime baseline remains cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c |
| EdgeTX stable | v2.12.5, [0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99][stable] |
| EdgeTX development | [3dd6fe069657fcdb3237dec2df61d01c1b53facc][development]; capabilities here are not stable 2.12.5 features |
| EdgeTX package-tools | [0d1fc38ebd27e75c5a88549b137a5a4626f9e91f][package] |
| WAMR selected by development EdgeTX | WAMR-2.4.4, [8c18e3f68b16c4bcaf05996b2636f6ed2b4cf629][wamr-license] |

This is a targeted source, license-header and build-file inspection. It does not
audit every transitive dependency or asset. No upstream code or binary was
added to OpenRC, no license was changed, and no maintainer was contacted.
No EdgeTX build, timing measurement or physical-radio test ran.

## What to reuse, and where

| Candidate | Useful existing work | Proposed use and limit |
| --- | --- | --- |
| Native firmware simulator | The [stable build][native-build] combines `radiolib_native`, simulated hardware drivers and the target-specific runtime | Run this together in the helper; retain the actual menu, mixer and telemetry behavior instead of extracting isolated algorithms |
| Simulator interface and LCD | [SimulatorInterface][interface] accepts controls, exposes channels, accepts telemetry and supplies the display | Adapt the Qt/C++ interface inside the helper; Godot receives pixels and plain versioned messages |
| Telemetry parser/provider | [Firmware CRSF decoder][crsf-decoder] and [Companion provider][crsf-provider] implement opposite sides of sensor injection | Retain decoding in EdgeTX; evaluate provider extraction inside the GPL component, or write an original encoder from verified protocol facts |
| Model preparation and interpretation | Companion's [.etx storage][etx], [YAML importer][yaml] and [mix-field interpretation][yaml-mix] already know EdgeTX data | Prepare a matching private SD/settings layout for the runtime first; direct archive import is a separate unproven path; evaluate a semantic report later under the applicable GPL terms |
| Development simulator exports | [simulib.h][wasm-api] and [implementation][wasm-impl] expose controls, frames, channel copies and color-screen UI observations | Alternative backend only after a measured need; neither a complete Godot plugin nor a proven coherent control snapshot |
| Package-tools automation | [Scripting interface][scripting] and [WAMR host][package-runtime] provide actions, channel checks and screenshots | Useful reference or separately assessed development tool; do not transplant GPL-3.0-only implementation into a GPLv2-only component |
| General ZIP/YAML libraries | Stable build pins [miniz][miniz-fetch] and [yaml-cpp][yaml-fetch]; both have [MIT][miniz-license] [licenses][yaml-license] | Reusable independently with their notices; those licenses do not cover EdgeTX's surrounding schema/conversion code |

The simulated firmware supplies authentic software behavior for its selected
target. It does not establish real RF propagation, physical gimbal behavior,
hardware timing or exact physical-transmitter equivalence. Reuse saves duplicating
software semantics; hardware realism still needs separate evidence.

## Permission and license consequences

### Existing grants versus extra permission

The inspected core and Companion candidate-file headers specify **GPL version 2,
without an “or later” option**, as in [SimulatorInterface][interface]. Apply those file-level
terms; a repository badge alone is insufficient. The [GPLv2 text][gpl2] permits
copying, modification and distribution under its conditions, including commercial
distribution. Compliant reuse does not require a separate permission request.

A different license or exception requires a valid grant covering the relevant
copyright holders; a generic maintainer approval may not cover inherited or
third-party contributions. The [FSF FAQ][faq-rights] explains that authority.
There is also a [Companion license template][companion-notice] with a permissive
notice alongside the GPLv2 headers. Its scope is unresolved here. Do not use it
as blanket permission to relabel those files MIT.

OpenRC's [MIT license][openrc-license] is GPL-compatible, as the
[GNU license list][license-list] confirms for that license form. Original MIT
portions can keep their MIT grant and notices. If the distributed combination is
a GPLv2-covered work, the combination must satisfy GPLv2. This does not
automatically relicense every independent file or historical OpenRC release.

### Architecture is not an exemption

The helper is recommended for lifecycle, dependency and maintenance reasons.
Under the [FSF's interpretation][faq-aggregation], both communication mechanism
and semantics matter when distinguishing independent programs from one combined
work. Continuous custom control/frame exchange needs assessment. A folder,
process, WASM sandbox, optional download or user installation does not by itself
prove an MIT-only combined distribution is allowed.

If it is one covered work, assess GPLv2 distribution of that combination and
all selected dependencies. If the programs are independent, document that
conclusion and each component's terms. If those routes do not fit the product,
retain an independently used upstream simulator or implement a bounded original
feature set. Private experimentation generally does not require publication
[FAQ][faq-private]; distributing a helper or client-side WASM is a different step.

### Practical distribution record

For a distributed GPLv2 component, preserve copyright, license and warranty
notices, include a copy of GPLv2, identify changed files and dates, and use a
permitted source-delivery method. Corresponding source includes all modules in
the covered executable, including permissively licensed modules, associated
interface definitions and build/install scripts, subject to the license's
system-component exception. Preserve recipients' licensed rights without further
restrictions [GPLv2 §§1–3, 6][gpl2].

Our proposed release method is a matching source archive beside each binary,
including exact dependency revisions and patches. A manifest should identify
radio target, firmware/settings version, build flags, artifact hashes, licenses
and source location. This is a reproducibility choice, not the only lawful
source-delivery method. A link to an unrelated or moving upstream checkout is
not our proposed compliance mechanism.

When actual integration code is added, use a component inventory and notices,
for example `THIRD_PARTY_NOTICES.md`, `LICENSES/` and an EdgeTX runtime manifest.
Explain the root MIT license's scope. Adding an acknowledgment alone cannot
convert borrowed GPL code to MIT; translating it to another language remains
a modification under GPLv2 §0 [gpl2][gpl2]. This documentation change creates
no placeholder license grants and does not modify OpenRC's current license.

### Specific dependencies and exclusions

| Item | Finding and decision |
| --- | --- |
| GPLv2 core + GPLv3 package-tools | [Cargo.toml][package-license] specifies GPL-3.0-only. GNU documents the [version incompatibility][faq-versions]. Do not combine GPLv2-only and GPLv3-only code, in source or compiled form, into the same covered work without a valid compatible grant; independent-tool use still needs an actual boundary assessment |
| Qt | Stable `libsimulator` links Core/SerialPort, with Widgets needed by its build condition [native-build][native-build]. Official [Core][qt-core], [SerialPort][qt-serial] and [Widgets][qt-widgets] docs offer a GPLv2 route. Check the exact shipped version, modules and third-party dependencies; “Qt 6” is neither a blanket incompatibility nor a completed audit |
| WAMR | EdgeTX [fetches WAMR-2.4.4][wamr-fetch]. Its [license][wamr-license] is **Apache-2.0 WITH LLVM-exception**, not bare Apache-2.0. The GPLv2 exception concerns combined compiled forms and a waiver conditional on a competent court finding a conflict. Preserve those terms and assess their scope; a bare-Apache compatibility table is insufficient |
| Assets and output | Check licenses for each selected radio image, icon, font, SD resource and script. Software output is not automatically GPL merely because GPL software produced it, but included protected material can retain its own terms [GPLv2 §0][gpl2]. Do not imply brand endorsement |
| First package scope | Omit the full Companion editor, embedded web frontend, package-tools and unnecessary SD content from the proposed first deliverable. This reduces integration work and the dependency inventory; it does not remove obligations for code actually included |

No RadioLink firmware source grant was established in the [initial evidence](README.md#radiolink-configuration-research-lead).
Keep RadioLink appearances, original simulated telemetry and physical USB input
separate from an authentic RadioLink firmware claim. The manufacturer's use of
FreeRTOS/LVGL is not a license to copy its complete radio software.

## Efficient integration

### 1. Preserve the firmware as a component

Keep the upstream revision and a small explicit patch set. Reuse upstream target
generation and builds. A proposed native helper owns the firmware threads, Qt
event loop where needed, private SD/settings copy and simulator lifecycle.
OpenRC owns presentation, flight input admission and the transport client.

The transport carries target/version/capabilities, raw virtual controls,
telemetry, copied LCD frames, channels and freshness information. Do not share
Qt objects or firmware model-memory structures with Godot. This reduces technical
coupling; it is not the legal conclusion described above.

The physical USB radio remains on the existing input path. Its processed
channels are not fed through EdgeTX a second time. The [plan's restricted
logical-AETR admission](../../../plans/radio-display-edgetx.md#real-edgetx-a-bounded-first-integration),
rate/mix/trim ownership and pause/replay rules remain mandatory.

### 2. Show real settings before building a second interpreter

First prepare a **private SD/settings layout** for a matching T18-H7 model,
including the necessary radio settings and model/index files, through a verified
same-version preparation path. Point the runtime at that copy and prove that the
intended model loaded. This is not a claim that it directly opens an .etx ZIP:
the archive importer is Companion code, while the stable runtime's
setRadioData/readRadioData methods are no-ops [runtime implementation][native-runtime].
Expose the enlarged real LCD to inspect actual configuration menus. This gives
useful inspection without first implementing every field twice.

Then add a structured report only for fields with verified semantics. The
Companion importer is not a standalone YAML decoder: source-board identity and
settings version affect interpretation. A mix weight can be a number, GVar or
other reference [yaml-mix][yaml-mix]. Mark unknown/unsupported fields explicitly.

If extracting Companion interpretation saves work, assess it inside the GPL
helper with its dependencies and emit a normalized read-only report. Otherwise
use existing ZIP/YAML support for a bounded archive inventory and original
interpretation of a small verified subset. Do not build a universal converter
first. Preserve source files; training changes stay in the copy.

### 3. Reuse behavior for lessons

Start with reversal, expo, switch assignment and flight-mode selection. Each
lesson has a pinned starting model, actions, expected menu/settings changes and
channel assertions. A screen capture alone cannot establish the output behavior.

Package-tools illustrates this workflow, but its [catalog downloader][package-catalog]
uses a live service and filename cache. A pinned CLI commit alone does not pin
the downloaded firmware. Capture module and SD hashes or supply a controlled
matching build before using its results as a reference for stable 2.12.5.

### 4. Decide the backend from evidence

| Approach | Relative effort and fidelity judgment | Decision |
| --- | --- | --- |
| Stable native helper | Reuses real menus/mixes/telemetry; adds hosting, transport and native packaging | First functionality spike |
| Direct library/GDExtension inside Godot | Same firmware potential; couples native dependencies and crashes to the application; combination licensing still applies | Do not choose first |
| Development WASM helper | Attractive exported interface and optional color UI tree; threaded runtime, schema drift and synchronization still matter | Evaluate when a measured stable limitation justifies it |
| New host using stable SDL simulator pieces | Can reuse firmware and simulated drivers without the Qt wrapper; existing SDL host owns an interactive window/event loop [native-build][native-build] | Possible fallback, not a ready headless library |
| Original simplified OpenRC radio UI | Smallest scope for appearance/telemetry and a few exercises; does not reproduce arbitrary EdgeTX settings | Ship the display layer independently; retain as fallback |
| Complete independent firmware imitation | Must maintain menus, mixing, model versions, scripts and edge cases | Poor first investment for the requested fidelity |
| Independently used official simulator | Immediate upstream reference without custom embedding | Fallback while an integration or distribution issue remains unresolved |

Effort rankings are engineering judgments, not measured schedules or benchmarks.
Using native simulator code already avoids the need to emulate the radio's CPU
from scratch.

If MIT-only distribution is essential, the alternative is an original, limited
implementation based on documented behavior and public formats, using separately
licensed assets and permissive codecs. Upstream behavior can inform comparison
fixtures; copying or mechanically translating GPL implementation is a different
route. Declare the supported subset instead of calling it full EdgeTX execution.
Independent code also does not automatically settle artwork or branding rights.

## What the first proof must establish

Keep the existing work IDs. Add **D6-RADIO-00a** for the selected-component
license inventory and distribution decision; source facts are recorded here,
but package clearance remains open.

1. **D6-RADIO-01 — authentic behavior.** Boot the exact T18-H7 target; show its
   LCD; prove a named fixture loaded from its prepared private SD/settings layout;
   move a raw control; observe channels;
   discover a sensor and show injected telemetry; stop/restart without changing
   the original. Compare menu actions and reverse/expo/switch results with the
   same-version upstream simulator.
2. **D6-RADIO-01b — usable control timing.** Stable changed-output notification
   is nominally 50 ms, not measured end-to-end latency. Development
   `simuCopyChannelOutputs` performs a `memcpy` of shared channel values and
   shows no synchronization in that function [wasm-impl][wasm-impl]; its
   [header][wasm-api] describes roughly 50 ms host polling. Neither path yet
   proves a coherent faster snapshot. Inspect writer synchronization and, if
   necessary, make a bounded upstream patch rather than unsafely polling faster.
3. **D6-RADIO-02 — flight admission and failures.** Measure input send, helper
   receipt, qualified firmware publication and physics consumption. Report
   p50/p95/p99/max, stale/missed updates and loaded conditions against a declared
   flight budget. Test held controls, alive-but-frozen firmware, simultaneous
   channel changes and recovery. Preserve model-bound admission, fresh throttle/
   AUX checks and recorded-input replay.
4. **F4-RADIO-01 — distributable native package.** Record the selected license
   route, exact runtime and asset inventory, matching source release and
   platform receipts. Retain separate physical-device tests. A successful menu
   demonstration cannot close the flight or distribution gates.

Telemetry proof must include discovery and stream validity, defined units,
a fully known bundled frame and stale-data behavior. The [simulator CRSF
provider][crsf-provider] omits CRC for its direct simulator consumer; that is
not a physical-radio transport implementation. These requirements remain in the
[initial telemetry contract](README.md#telemetry-is-a-real-protocol-boundary).

## Review and current result

Source review supports the reuse-first recommendation. Independent engineering
and licensing review identified three material limits now reflected in the plan:
the helper boundary does not prove license independence; a channel-copy API
does not prove synchronization; and a configuration parser or CLI pin does not
prove matching firmware/model semantics.

The next useful implementation is the exact-target helper spike alongside the
original HUD improvements. We have not proved native runtime compatibility,
control latency, arbitrary-model support or a final release license boundary.

## Primary sources

Source links are pinned where practical. GNU material states the licenses or
the FSF's interpretation; it does not replace a fact-specific legal assessment.

[openrc-plan]: https://github.com/bultodepapas/OpenRCsimulator/commit/24455097e7632817cc6503821f0f3d26d55d6c30
[openrc-license]: https://github.com/bultodepapas/OpenRCsimulator/blob/24455097e7632817cc6503821f0f3d26d55d6c30/LICENSE
[stable]: https://github.com/EdgeTX/edgetx/tree/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99
[development]: https://github.com/EdgeTX/edgetx/tree/3dd6fe069657fcdb3237dec2df61d01c1b53facc
[package]: https://github.com/EdgeTX/edgetx-package-tools/tree/0d1fc38ebd27e75c5a88549b137a5a4626f9e91f
[native-build]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/targets/simu/CMakeLists.txt
[native-runtime]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/targets/simu/opentxsimulator.cpp
[interface]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/simulation/simulatorinterface.h
[companion-notice]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/targets/license.txt.in
[crsf-decoder]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/telemetry/crossfire.cpp
[crsf-provider]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/simulation/telemetryprovidercrossfire.cpp
[etx]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/storage/etx.cpp
[yaml]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/storage/yaml.cpp
[yaml-mix]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/firmwares/edgetx/yaml_mixdata.cpp
[wasm-api]: https://github.com/EdgeTX/edgetx/blob/3dd6fe069657fcdb3237dec2df61d01c1b53facc/radio/src/targets/simu/simulib.h
[wasm-impl]: https://github.com/EdgeTX/edgetx/blob/3dd6fe069657fcdb3237dec2df61d01c1b53facc/radio/src/targets/simu/simulib.cpp
[scripting]: https://github.com/EdgeTX/edgetx-package-tools/blob/0d1fc38ebd27e75c5a88549b137a5a4626f9e91f/docs/Scripting.md
[package-runtime]: https://github.com/EdgeTX/edgetx-package-tools/blob/0d1fc38ebd27e75c5a88549b137a5a4626f9e91f/src/simulator/runtime.rs
[package-license]: https://github.com/EdgeTX/edgetx-package-tools/blob/0d1fc38ebd27e75c5a88549b137a5a4626f9e91f/Cargo.toml
[package-catalog]: https://github.com/EdgeTX/edgetx-package-tools/blob/0d1fc38ebd27e75c5a88549b137a5a4626f9e91f/src/radio_catalog/mod.rs
[miniz-fetch]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/cmake/FetchMiniz.cmake
[yaml-fetch]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/cmake/FetchYamlCpp.cmake
[miniz-license]: https://github.com/richgel999/miniz/blob/89d7a5f6c3ce8893ea042b0a9d2a2d9975589ac9/LICENSE
[yaml-license]: https://github.com/jbeder/yaml-cpp/blob/28f93bdec6387d42332220afa9558060c8016795/LICENSE
[wamr-fetch]: https://github.com/EdgeTX/edgetx/blob/3dd6fe069657fcdb3237dec2df61d01c1b53facc/cmake/FetchWamr.cmake
[wamr-license]: https://github.com/wasm-micro-runtime/wasm-micro-runtime/blob/8c18e3f68b16c4bcaf05996b2636f6ed2b4cf629/LICENSE
[gpl2]: https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
[license-list]: https://www.gnu.org/licenses/license-list.html#Expat
[faq-rights]: https://www.gnu.org/licenses/gpl-faq.en.html#GPLIncompatibleLibs
[faq-aggregation]: https://www.gnu.org/licenses/gpl-faq.en.html#MereAggregation
[faq-private]: https://www.gnu.org/licenses/gpl-faq.en.html#GPLRequireSourcePostedPublic
[faq-versions]: https://www.gnu.org/licenses/gpl-faq.en.html#v2v3Compatibility
[qt-core]: https://doc.qt.io/qt-6/qtcore-index.html#licenses-and-attributions
[qt-serial]: https://doc.qt.io/qt-6/qtserialport-index.html#licenses
[qt-widgets]: https://doc.qt.io/qt-6/qtwidgets-index.html#licenses
