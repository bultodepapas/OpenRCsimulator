# JETI input and setup implementation

Date: 2026-10-19. Scope: D6-JETI-01…03 and UI-15-JETI-01…02 software. The [active plan](../../../plans/jeti-support.md) owns remaining device/package qualification; [First launch](../../../FIRST-LAUNCH.md#controller-settings-current-source) owns usage. The [original email, PDF, CFG and USB descriptors](../D6-JETI-00/README.md) remain unchanged.

## Delivered behavior

- Strict VID `0x0483` / PID `0xA07C` plus corroborating JETI identity selects the DC/DS family starter. Missing, contradictory, emulated or duplicate identity cannot acquire that starter or inherit gamepad defaults. Display names remain separate from raw metadata; metadata/ambiguity changes invalidate cached connection ownership.
- The Mode 2 starter uses roll 0, inverted pitch 1, absolute throttle 2 and yaw 3. Its buttons are explicitly unbound, with Backspace/Escape recovery. Saved V2/legacy profiles take precedence. Existing JETI joystick profiles retain their kind, identity and calibration; cleanup is an explicit Save/Cancel draft.
- Shared V2 AUX accepts two-/three-position switch groups, inversion and optional physical names. Coherent polling produces absolute requests; malformed or contradictory groups fail closed. Startup/focus/reconnect require deliberate OFF evidence after a baseline. Radio low-throttle arming and Continue remain separate.
- Controls provides selected-device per-position capture, same-group button swaps, overlap rejection, live preview and EN/ES labels. Prompts and the flight control guide describe configured groups and preserve equipment availability. The [binding and arming contract](../../../plans/jeti-support.md#implemented-contract) is authoritative.

No physical Sa–Sj map is installed. Windows button numbering in the PDF does not establish Godot event indices. The missing initial `J` reported in the source PDF is not reproduced by these UI fixtures; a real F1 report must distinguish backend naming from the original build's layout.

## Verification

Engine: Godot `4.7.2.stable.official.ed1daf0bf`. Windows uses the native console build; Linux uses Ubuntu/WSL2 on its own filesystem. [Verification metadata](verification.json) records exact owned-source hashes and snapshot scope. The shared working tree contains unrelated concurrent changes.

| Check | Result | Evidence |
| --- | --- | --- |
| Native controller/session/UI regressions | 38/38 programs pass | [Results and log paths](native-results.json) |
| New JETI identity/runtime/setup, switch AUX and control guide on Linux | 5/5 programs pass | [Results and log paths](linux-results.json) |
| Complete app GDScript parse | 1,052/1,052 pass | [Per-script hashes and results](parse-all-linux.json); excludes generated `.godot`/captures |
| Original supplier CFG on a disposable copy | 9/9 checks pass | [Log](supplied-profile.log), [reproducible probe](../../../../../research/input/jeti/verify_supplied_profile.gd) |
| Native EN/ES setup fixtures | Four captures inspected | Captures below; synthetic controls, no hardware claim |
| Full `app/test.sh` | Fails in unrelated CR-29 preflight | [Log](full-app-preflight.log): stale generated `worked-examples.json`, before units/complete parse |
| Golden flight replay isolation | Four failures reproduced identically with original and candidate input | [Comparison and frozen physics hashes](golden-isolation/comparison.json), [original log](golden-isolation/original_input.log), [candidate log](golden-isolation/jeti_input.log) |

Identity has 52 checks, runtime 93, switch AUX 75, JETI setup 52 and the overlay manager 116. Regression coverage includes existing profile/store persistence and failed-save rollback, automatic selection, independent menu ownership, setup/capture safety, compact/large-text layouts, flight actions, helicopter/car input, diagnostics and flight logging. The final affected UI programs replace their earlier pre-fix runs in the native result index; unchanged input programs retain their passing run.

The full-suite preflight failure is outside this task's input/UI changes. Complete parse and focused tests were run separately afterward. Golden isolation uses an earlier input integration candidate and the original intake input against the same frozen physics/data; it establishes that those four failures predate this work, not final-source golden acceptance. Physics, aircraft data and golden recordings were not changed by this task. The whole repository is not claimed green.

## Reproduce

Import with the pinned engine as described in [TOOLS](../../../TOOLS.md#developer-setup). All four new unit programs are discovered by `app/test.sh`. For the focused native regression set from the repository root:

```powershell
$jetiGodot = '.tools/Godot_v4.7.2-stable_win64_console.exe'
$jetiCases = Get-Content docs/research/radio-input/D6-JETI-01/native-results.json | ConvertFrom-Json
foreach ($jetiCase in $jetiCases) {
    $jetiOutput = & $jetiGodot --headless --path app --audio-driver Dummy --script $jetiCase.script 2>&1
    $jetiOutput
    if ($LASTEXITCODE -ne 0 -or ($jetiOutput -match '^(SCRIPT |SHADER )?ERROR:|^FAIL\b')) {
        throw "Failed: $($jetiCase.script)"
    }
}
& $jetiGodot --headless --path app --audio-driver Dummy --script research/input/jeti/verify_supplied_profile.gd
```

For the four desktop captures, run `test_jeti_setup.gd` without `--headless`, with user arguments `--capture-dir=<existing-or-new-output-directory> --lang=en|es --size=1280x720|1920x1080`. Use each language/size combination. Their configured `Sa` indices 81/82/83 deliberately exercise high API indices; they are fabricated test inputs, not a JETI hardware map. Captures show one assigned channel and scrollable remaining channels.

| Locale | Compact | Normal |
| --- | --- | --- |
| English | [1280×720](captures/jeti-setup-en-1280x720.png) | [1920×1080](captures/jeti-setup-en-1920x1080.png) |
| Spanish | [1280×720](captures/jeti-setup-es-1280x720.png) | [1920×1080](captures/jeti-setup-es-1920x1080.png) |

## Remaining acceptance

F1 still needs a physical DC-16II report with build/OS/firmware/mode/switch metadata and observed axis/button transitions. F4 requires actual startup, capture, recovery, two-device and exported-Windows-package checks. Other models/platforms and filmed latency have independent gates. The optional branded 3D representation remains separate, subject to free-asset/license review and JETI permission. No device, latency or physical-flight qualification is inferred from these fixtures.
