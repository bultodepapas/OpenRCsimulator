# EL2a-E1 Startup Probe

Status: exploratory runtime evidence for EL2a-E1; synthetic fixtures only; no physical acceptance.

The exact exploratory script is preserved as [startup_probe.gd](../../../../../research/propulsion/el2a-e1/startup_probe.gd). The paths below record the original commands; substitute this script path to reproduce. This probe is a diagnostic, not an acceptance runner: use the parent report's bounded qualification tools for completion/crash/error gates. The hash file records selected source/fixture hashes, not a full dependency manifest.

On 2026-10-11, Godot 4.7.2.stable.official.ed1daf0bf was used to run the same bounded startup probe against the checked-out baseline and `.tools/el2a-e1-dev/app`, on both Windows and WSL. The probe uses the `default` field threshold and the existing synthetic 4S and 6S battery fixtures. Fixture JSON is unmodified; SHA-256 hashes for both copies match. The candidate branch was exercised only in the isolated `.tools` copy; this audit made no production-source changes.

The baseline `reset_on_runway()` call fails for both battery fixtures. At zero duty, `steady_operating_point()` reports `unbracketed` and `steady_rpm()` returns NaN; `_apply_runway_start()` then rejects the non-finite RPM. The failure prints `runway start needs finite position, heading, controls, rpm, density and gravity`, while the public helper restores the airborne trimmed state. To measure the physical ground/start behavior without changing production code, the probe then explicitly seeds a zero-RPM runway state through `GroundStart.solve()`; this fallback is labelled `manual` in the baseline artifacts.

The candidate's electric zero-duty branch lets the public helper produce the same zero-RPM runway state. After 0.5 s at zero duty and 0.5 s at full duty, candidate values match the baseline manual-seed values for both packs. Neither route faults. The 4S case reaches 8,068 rpm and 1.451 m/s; the 6S case reaches 7,901 rpm and 1.594 m/s. The battery fixtures and propulsion code have matching hashes between baseline and candidate. The isolated candidate's `flight_session.gd` differs by the zero-RPM runway branch and electric-specific trace scenario description; see the recorded source hashes.

The probe is intentionally narrow: it demonstrates the runway-entry defect and verifies a parked zero-duty dwell followed by startup. It does not qualify takeoff, stall/recovery, depletion in flight, or physical pack behavior.

Each case takes 120 ticks (0.5 s at the app's configured 240 Hz), first at zero duty and then at full duty. These are the actual PowerShell commands used from the repository root; `*>` captured the raw console logs alongside the JSON written by the probe:

```powershell
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'app' --script 'C:\DEVELOPMENT\OpenRCsimulator\.tools\el2a_e1_probe.gd' -- '--output=C:\DEVELOPMENT\OpenRCsimulator\docs\research\propulsion\EL2a-E1\startup\baseline-windows.json' *> 'docs/research/propulsion/EL2a-E1/startup/baseline-windows.log'
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path '.tools/el2a-e1-dev/app' --script 'C:\DEVELOPMENT\OpenRCsimulator\.tools\el2a_e1_probe.gd' -- '--output=C:\DEVELOPMENT\OpenRCsimulator\docs\research\propulsion\EL2a-E1\startup\candidate-windows.json' *> 'docs/research/propulsion/EL2a-E1/startup/candidate-windows.log'
```

WSL was invoked through `wsl.exe` with the same app and script on `/mnt/c`:

```powershell
& 'wsl.exe' -e '/home/bulto/openrc-el2a-p2/baseline/.tools/Godot_v4.7.2-stable_linux.x86_64' --headless --path '/mnt/c/DEVELOPMENT/OpenRCsimulator/app' --script '/mnt/c/DEVELOPMENT/OpenRCsimulator/.tools/el2a_e1_probe.gd' -- '--output=/mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/propulsion/EL2a-E1/startup/baseline-wsl.json' *> 'docs/research/propulsion/EL2a-E1/startup/baseline-wsl.log'
& 'wsl.exe' -e '/home/bulto/openrc-el2a-p2/baseline/.tools/Godot_v4.7.2-stable_linux.x86_64' --headless --path '/mnt/c/DEVELOPMENT/OpenRCsimulator/.tools/el2a-e1-dev/app' --script '/mnt/c/DEVELOPMENT/OpenRCsimulator/.tools/el2a_e1_probe.gd' -- '--output=/mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/propulsion/EL2a-E1/startup/candidate-wsl.json' *> 'docs/research/propulsion/EL2a-E1/startup/candidate-wsl.log'
```

Raw results: [baseline Windows JSON](baseline-windows.json), [baseline WSL JSON](baseline-wsl.json), [candidate Windows JSON](candidate-windows.json), [candidate WSL JSON](candidate-wsl.json), with corresponding [baseline Windows log](baseline-windows.log), [baseline WSL log](baseline-wsl.log), [candidate Windows log](candidate-windows.log), and [candidate WSL log](candidate-wsl.log). Source and engine SHA-256 values are in [source-hashes.sha256](source-hashes.sha256).
