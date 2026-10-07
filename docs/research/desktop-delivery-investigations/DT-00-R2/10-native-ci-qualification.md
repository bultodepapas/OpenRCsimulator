# 10 — Native Apple Silicon CI and owner qualification

2026-10-07 · DT-00-R2 · **Research complete; no macOS job or native launch executed.**

## Question and current gap

How can CI prove that the downloaded Godot application runs on ARM64 without misrepresenting a virtual machine as a pilot's M1 MacBook? The inspected `.github/workflows/ci.yml` runs source tests and exports on Ubuntu. `app/get-godot.sh` downloads only the Linux x86_64 editor; `app/test.sh` calls it directly and uses GNU `timeout`. Adding a macOS runner label alone will not make that script portable.

The exported macOS preset excludes `tests/*`. Source tests with a Mac editor and tests of the final application are therefore separate jobs. Do not reinsert the development test suite into the shipping package merely to reuse a runner command.

## Primary-source findings

GitHub currently identifies `macos-15` as an ARM64 M1 virtual runner, with three CPUs and 7 GB RAM, while `macos-15-intel` is Intel. Record the actual image/build and architecture on each run; a pinned label does not pin every installed tool. A virtual M1 runner is not a retail 8 GB M1 Air thermal/display test. [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

GitHub separately advertises GPU acceleration for its larger M2 macOS runner. That distinction does not establish the graphics capabilities of a standard job or a physical monitor. Run a capability check before making any native GUI/rendering claim; keep headless logic useful even if GUI access is unavailable. [Larger runners](https://docs.github.com/en/actions/reference/runners/larger-runners).

Godot's `--headless` selects the headless display and Dummy audio drivers. It cannot certify Metal/OpenGL rendering, fullscreen, CoreAudio or physical USB. The release executable supports engine options such as `--log-file`; app arguments follow `--`. [Godot command line](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html).

## Proposed job boundaries

| Stage | Runs where | Required proof / rejection |
| --- | --- | --- |
| Source ARM64 regression | Pinned Mac editor on an ARM64 runner | Engine version/digest/architecture, imported resources, existing numerical budgets, parse/runtime errors and timeout; no translated x86_64 process |
| Final package logic | Downloaded app outside checkout | Exact package digest; ARM64 headless trace validates active aircraft and completion; resource failure exits are checked |
| Native GUI capability | Logged-in Mac session with verified hardware backend | Home visible and host input delivered; effective renderer/driver, display and process architecture recorded; unavailable GUI is skipped/unsupported, never passed |
| Distribution trust | Final signed/notarized download on clean account | Finder launch, quarantine/Gatekeeper/offline acceptance; direct CLI execution does not substitute for this |
| Pilot qualification | Physical M1-class floor plus a newer supported Mac | Radio, Retina/fullscreen, sustained flight, battery/AC, sleep and audio; final artifact matches CI digest |

Coordinate a small platform adapter with the CI owner: select exact per-host editor archive/checksum, accept an explicit engine path in the test runner, replace GNU-only timeout assumptions with a verified portable process supervisor, and preserve error-log scanning. Do not update the Godot version while introducing Mac CI. Keep runner caches separated by engine/platform/import configuration.

Use a disposable macOS test account or runner for user-data isolation. Linux XDG overrides used by the previous probe do not establish isolation of Godot's macOS Application Support directory. Do not repurpose `HOME` or erase an owner's settings. [Godot data paths](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html).

## Native commands to qualify, not results

After verifying the downloaded hash, on a disposable Mac account with the app installed:

```sh
sw_vers
uname -m
file "/Applications/OpenRC Simulator.app/Contents/MacOS/OpenRC Simulator"
arch -arm64 "/Applications/OpenRC Simulator.app/Contents/MacOS/OpenRC Simulator" --headless --log-file /tmp/openrc-arm64-trace.log -- --trace=/tmp/openrc-arm64-trace.csv --t=3
python3 app/tests/check_trimmed_flight.py /tmp/openrc-arm64-trace.csv
```

Resolve the executable from `CFBundleExecutable` first; the path above is a candidate example, not a guaranteed exported basename. The source-side CSV checker is run by the harness, outside the app. Use unique output paths and enforce timeout, exit code, complete CSV and engine-error checks around the command. Native process architecture must also be recorded for the Finder GUI route; forcing `arch -arm64` only proves the CLI route.

**DT-02a:** establish ARM64 source and final-package jobs before marking macOS CI accepted. **DT-01/12:** add physical M1 floor and newer-Mac rows with OS/build, RAM, GPU cores, display, power state and available evidence. **DT-13:** advertise the validated OS/hardware matrix, not an unbounded promise for every future M-series machine.

Sources were accessed on 2026-10-07. This report specifies a test architecture; it did not configure CI, acquire hardware, spend runner minutes, or run the commands above. Source filenames were inspected in a concurrently edited tree; freeze a candidate before execution.
