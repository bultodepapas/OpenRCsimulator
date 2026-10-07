# Desktop delivery research 08 — Native package test strategy

2026-10-07 · Research round **DT-00-R1** · Item 08. Supports [DT-01/02 and DT-12](../../../DESKTOP-DELIVERY-PLAN.md). This item number is research numbering; it is not plan milestone DT-08.

**Status:** repository/workflow audit plus official-source research. No native Windows or macOS run was available or attempted.

## Question

What is the smallest maintainable test design that separates app logic, export structure, real desktop startup, input/focus behavior and OS trust for the packages actually being delivered?

## Current test boundary

| Layer | Current proof | Does not prove |
| --- | --- | --- |
| `app/test.sh` | Broad headless parser, physics, session, keyboard/radio-event, menu and trace checks. Its UI tests use `Input.parse_input_event` through `tests/ui_driver.gd`. | OS input injection, native focus delivery, native display/window behavior or downloaded-release trust. |
| `app/capture.sh` / `.github/workflows/ci.yml` app job | Linux `ubuntu-24.04`, Xvfb plus Mesa; real Godot scenes/captures and UI evidence. | Physical GPU performance, monitor modes, native Wayland/window-manager behavior, Windows/macOS windowing, or physical scanout. |
| `app/export.sh` | Cross-exports Linux, Windows and universal macOS from Ubuntu; runs exported Linux headless flight/pack checks, checks macOS slices/ad-hoc signing and version metadata. | Launching the Windows `.exe` or macOS `.app`, authentic OS input/focus, Gatekeeper/SmartScreen, or actual Intel/Apple Silicon runtime acceptance. |
| `.github/workflows/ci.yml` release | Uploads one `release-builds` artifact; the tag job downloads it and attaches it, without rebuilding. | Installer lifecycle, browser download handling, a clean-user first launch or owner pilot acceptance. |

Godot documents that `--headless` disables rendering and window management and returns dummy rendering-server values. Headless remains valuable for logic and deterministic simulation, but cannot close GUI claims. Xvfb supplies a virtual X server; it is useful to run actual app scenes on Linux CI, but its current use is not a physical monitor/compositor test. [Godot RenderingServer](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html), [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

## Recommended three-layer design

### Layer A — Keep fast behavior tests

Keep `app/test.sh` as the pull-request gate for deterministic state, route precedence, saved preferences, focus-pause rules, calibration and traces. Extend a test only when a product behavior changes. These tests should continue using isolated settings paths and event fixtures; no real user profile should be touched.

### Layer B — Keep package-structure and headless smoke checks

On every candidate, validate each export's declared files, architecture, version, embedded pack, licenses and hashes. Continue the exported Linux headless trimmed-flight check: it verifies that the release binary can load its packed data and run physics. Label this precisely as a pack/flight smoke, not a desktop GUI result. Godot's command-line `--headless` mode explicitly removes window management/rendering, so do not infer UI or fullscreen success from it. [Godot command line](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html), [RenderingServer headless note](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html).

### Layer C — Add a short native final-package launch check

Run the already-built candidate artifact on a runner of the target OS, after downloading it from the build artifact. Use a fresh runner account/profile; launch the app from a path outside the checkout; record package SHA, OS build, architecture, display backend, app exit code, full log, and screenshots at Home and in flight. A concise fixed sequence is: Home is visible and focused → Fly → Pause → Continue → End flight → Quit. Put a hard timeout on every process and fail on engine errors, missing expected state evidence, no window, hung close, or nonzero exit.

Keep a single scenario definition and a very small host adapter for process control and key delivery on each OS. Reuse the menu track's screen/state assertions and the existing simulator route; do not build a generic cross-platform desktop automation framework. Godot's existing in-process `ui_driver.gd` injects engine events, so it verifies control logic but cannot replace a host-level keyboard/focus check. Add an app-owned machine-readable checkpoint only if the final package cannot otherwise prove Home/Fly/Pause/End transitions. The checkpoint should record state names and build identity, not mirror every control's internal implementation.

CI can automate deterministic launch and key sequence. A human still checks visual legibility, actual monitor fullscreen, multi-monitor/DPI changes, real USB radio and unmodified OS trust prompts before each platform is declared accepted. Keep those manual outcomes attached to the same candidate digest.

## Native runner coverage

The current `export` job is Ubuntu-only. GitHub's hosted-runner reference, checked on 2026-10-07, lists Windows x64 runners, Intel macOS runners, and separate Apple Silicon ARM64 macOS runners. In its standard-runner table, `macos-15` is ARM64 (M1), while `macos-15-intel` is Intel. These are different machine architectures, not labels for equivalent jobs. Confirm labels and image revisions when implementing because GitHub changes available runner images. [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

| Claimed package target | Automated native run | Remaining owner/release acceptance |
| --- | --- | --- |
| Windows x86_64 | Windows x64 host, downloaded x86_64 ZIP/installer; normal desktop route and process-level smoke. | Standard-user install/upgrade/uninstall; browser-download SmartScreen and real USB radio on a physical Windows account. |
| macOS universal | ARM64 Mac runner executes arm64 slice; Intel runner executes x86_64 slice when Intel is claimed. Capture `uname -m`, `file`, and `lipo -archs`/equivalent. | Finder launch from downloaded/stapled artifact; Gatekeeper online and offline paths; Retina/external display and physical radio. |
| Linux x86_64 | Keep Ubuntu CI pack check; add actual non-headless X11 launch on a host with a window/display server. Run Wayland only if native Wayland is included in the support promise. | At least one named distribution/compositor and actual GPU; download, execute bit, desktop integration, physical radio. |

A universal macOS binary's two slices are already structurally checked, but structural presence does not prove each slice starts. Rosetta can be a useful compatibility probe on ARM, but should be labeled translated execution; use Intel hardware/runner for an Intel-native claim. GitHub's hosted macOS ARM and Intel runner availability can support two separate execution jobs, while a personal clean Mac remains the final trust/display reference.

## Keep build, test and trust jobs separate

Use an unprivileged build job and native smoke jobs that need only read/download access. Use a separate trusted release/signing job for OS credentials. GitHub's runner reference says hosted jobs receive fresh runner instances; preserve that clean-runner property and never run untrusted PR code in a credentials-bearing signing job. Environment secrets can be withheld until configured rules pass. [Runner lifecycle](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [GitHub environments](https://docs.github.com/en/actions/concepts/workflows-and-actions/deployment-environments), [untrusted PR guidance](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target).

Keep the release job from rebuilding. Download the candidate built and checked earlier in the same run, verify its digest, then run target-host smoke against those exact files. The owner-facing package digest must match the eventual release attachment; otherwise the test only certifies a different candidate.

Do not promote CI virtual displays into the hardware performance matrix. Hosted virtual hardware, Xvfb and software rendering are efficient correctness runners, but do not establish GPU frame budgets, real refresh timing, real monitor topology, or radio latency. The existing plan correctly reserves DT-01 named hardware and DT-12 downloaded-package acceptance.

## Suggested evidence record

For every native run save one JSON or Markdown record containing: immutable artifact URL/run ID; SHA-256 of downloaded file; source commit/tag; OS version/build; runner label and architecture; package kind; display server/backend; effective window size/mode where observable; application build label; scenario checkpoints and times; exit code; engine errors; signature/trust checks; screenshot paths and hashes; and an explicit list of cases not exercised. Use the same record format in CI and manual pilot evidence.

The native launch smoke should prove that the packaged process opens from its release location and reaches a stable visible Home. Add only one controlled route through flight and pause. Do not use capture mode, headless mode or `--scripted` to claim the user-facing Home interaction; those routes are useful separate diagnostics. Keep the flight physics acceptance in existing trace/golden tests and use the exported binary route only for pack/runtime integrity.

## Proposed edits to the plan

1. DT-02 should require a test scenario on the final exported artifact, not merely a “native smoke harness” name. Define the three proof layers above and require host-level interaction on target OS.
2. DT-02's exit should identify runner labels/builds and report whether each run was native, translated, virtual-display, headless or physical-hardware.
3. DT-12 should require the tested artifact SHA to equal the exact release attachment SHA. Attach per-platform CI logs/captures plus a separate owner checklist for trust prompts and real hardware.
4. Set support tier explicitly: “exported/structurally checked”, “native CI launched”, or “owner-accepted on named OS/hardware”. Do not collapse these into one supported checkbox.
5. Retain the first platform smoke as a short three-to-five-minute process, timeout and input test. Expand only where a real regression reveals a missing case.

## Proof commands and limits

The current source evidence can be rechecked with `sed -n '1,260p' .github/workflows/ci.yml`, `sed -n '1,240p' app/export.sh`, `sed -n '1,200p' app/tests/ui_driver.gd`, and `rg -n 'headless|capture|trace|frametimes|smoke' app/test.sh app/tests`. The first implementation proof should preserve the SHA of the downloaded artifact and the CI run URL. No native-runner configuration or app code was changed here.

CI GUI input automation may need OS-specific permissions, window-server access, or runner-image setup; those prerequisites must be proven with a tiny spike before expanding the matrix. Hosted VMs are not owner's monitor/GPU/radio. GitHub's public runner documentation does not guarantee the desktop session semantics needed by this simulator. Therefore keep the real-host manual acceptance step even if GUI smoke is automated.

## Primary sources

- [Godot 4.7 command-line tutorial](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html) and [RenderingServer](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html).
- [GitHub-hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [choosing a runner](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job).
- [GitHub deployment environments/secrets](https://docs.github.com/en/actions/concepts/workflows-and-actions/deployment-environments) and [safe handling of untrusted pull requests](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target).
- Repository audit: `.github/workflows/ci.yml`, `app/export.sh`, `app/test.sh`, `app/tests/ui_driver.gd`, `app/tests/test_ui_home.gd`, `app/tests/test_ui_pause.gd`.
