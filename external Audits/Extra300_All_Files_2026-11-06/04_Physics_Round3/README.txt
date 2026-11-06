Extra 300S — round-three investigation and evidence
2026-11-06

Start with Extra300_Round3_Investigation.txt. The PNG/SVG show the accepted
22 m/s right-roll case. The report states the scope and limits of every result.

Contents
--------
- Extra300_Round3_Investigation.txt: findings, mathematics and decisions.
- pulses/: all 12 original complete .orfl recordings and matching CSVs;
  results.json identifies trim, mass, commands and replay outcome.
- pulse_analysis.json, pulse_summary.csv: metrics derived from the CSVs.
- Extra300_Roll_Response.png/.svg: original figure, not a real-aircraft plot.
- static_propulsion_point.json and propulsion_analysis.json: new current-source
  shaft-balance calculation and separate arithmetic from selected source facts.
- propulsion_source.json: primary source identity and a few selected facts;
  no copyrighted PDF, book text, scans or full graph are redistributed.
- probes/: the original GDScript probes and Python pulse analysis script.
- config/project.godot: the minimal test project used for the root experiments.
- aero/, dynamics/: specialist handoffs and independent pulse review.
- checks/: accepted checked-runner report.json/engine.log pairs.
- prior_failures/: rejected setup/marker attempts, explicitly not accepted data.
- source_manifest.json, source_verification.json, support_assets_verification.json,
  closing_comparison.json: source identity and later GitHub comparison.
- verification.json: archive inventory, SHA-256 hashes and accepted-run checks.

Baseline and software
---------------------
Source: https://github.com/bultodepapas/OpenRCsimulator
Executed commit: 2e2e3492e67d30635cc4e727025581e2848cdf2e
Godot: 4.8.beta2.official.cafc17a19, Linux x86-64
Physics backend: gdscript_reference; 240 Hz; float64 state.
No production files, source repository settings, or generated data were edited.

The source_manifest lists the 3,528 files copied into the root runtime before
probes/configuration were added. It does not include the replacement project
configuration. All listed files were rechecked against that copy. Additional
scenery preloads are actual tracked source assets; untracked generated .import
sidecars are not claimed to be source. These tests do not render the scenery.

Reproducing the main experiments
-------------------------------
Use a complete checkout at the executed commit, including its required assets.
Create a disposable directory outside the working checkout; copy its app/
directory into that directory as runtime/. Put this package's project.godot
in runtime/, replacing only the disposable copy's project configuration.
Copy character_pulses.gd and static_propulsion_point.gd from probes/ to runtime/.
If a resource resolves a repository-level assets/ or tools/ path, provide a
read-only link beside runtime/ to the pinned checkout's corresponding directory.
Use empty, isolated XDG_DATA_HOME, XDG_CONFIG_HOME and XDG_CACHE_HOME directories.
The accepted runner commands are preserved in checks/*/report.json; substitute
your own absolute engine, runtime, output and pinned checkout paths.

First import with the pinned engine, --headless --editor --path RUNTIME --import,
through tools/godot/run_checked.py. Check the receipt, not just process exit.

Then use the same checked runner with:

  --require-text 'EXTRA_CHARACTER_PULSES_COMPLETE failures=0 cases=12'
  --timeout 900 -- GODOT --headless --path RUNTIME --audio-driver Dummy
  --script res://character_pulses.gd -- --out=NEW_PULSE_DIRECTORY

and:

  --require-text 'STATIC_EXTRA_POINT_COMPLETE checks=8 failures=0'
  --timeout 90 -- GODOT --headless --path RUNTIME --audio-driver Dummy
  --script res://static_propulsion_point.gd -- --out=NEW_STATIC_RESULT.json

Include --out-dir NEW_RECEIPT_DIRECTORY and a distinct --label before the
runner's -- separator. Output parents must exist. These symbolic commands are
templates; the retained JSON commands show the exact executed forms. Use new
output paths so the preserved baseline is not overwritten.

The pulse probe records and exactly replays each new flight itself. To regenerate
derived pulse JSON/CSV/figures with an installed Matplotlib:

  python3 probes/analyze_pulses.py NEW_PULSE_DIRECTORY NEW_ANALYSIS_DIRECTORY

The high-angle witness is self-contained after copying it into runtime/:
res://check_flat_plate_progression.gd, required marker
'PROGRESSION_OBSERVATION_COMPLETE: 16 checks, 0 failed'. The two existing aero
tests remain in the pinned checkout: test_wing_polar.gd and
test_spatial_aero_continuation.gd.

The original cooling probe deliberately retains its original absolute JSON
destination as part of the executed source identity. For a new run, change
only that destination in a disposable probe copy to a new writable path;
retain the original packaged source. Its marker is
'COOLING-PROBE 7 checks, 0 failures'. See the corresponding retained receipt.

Interpretation essentials
-------------------------
- A pulse peak is not steady roll rate; initial speed is not speed held by a
  controller. Coupled motion and trim/clipping remain present.
- The CSV aileron_deg is modeled right-aileron angle, positive trailing-edge up.
  raw_roll is a scripted target, not a physical controller sample.
- Exact replay compares the recorded physics fields after strict source/engine/
  timestep/backend identity checks. It is not pilot, UI or physical validation.
- The probe's solver_changed=false is a reporting default, not a separate
  measured field. Identity is enforced by Reader.prepare_replay; all 5,760
  compared physics ticks match. PULSE_REVIEW.txt explains this explicitly.
- Static shaft balance assumes nominal mixture and full firing; it is not a
  thermal/fuel equilibrium. The new historical bench setup is not matched to
  the simulated installed aircraft. No tuning is justified by its RPM alone.
- The aerodynamic and cooling alternatives are diagnostic model sensitivities,
  not production patches or new confirmed defects.
- No frame-time benchmark, FPS gain, physical-controller test or real flight
  validation was performed in this pass.

Failures retained
-----------------
The first root smoke run lacked scenery preloads and used an unsupported
format specifier. The next lacked one remaining texture. Their reported
process exits were insufficient; the checked runner rejected the diagnostics.
The accepted full matrix was run only after resolving those setup issues.
The aero witness's first completion-marker request used 14 rather than the
actual 16 checks. The first cooling attempt had missing assets and a negative
axial-flow control outside that diagnostic's domain. Their separate rejected
receipts are retained so they cannot be mistaken for passing evidence.

The final source checkout was clean. The closing GitHub ledger update was read
and cross-checked; no E300-01..08 item is re-reported as a new finding here.
