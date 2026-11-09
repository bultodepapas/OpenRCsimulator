OPEN RC SIMULATOR CRASH COST AUDIT EVIDENCE
9 November 2026

BASELINE
Repository: https://github.com/bultodepapas/OpenRCsimulator
Commit: f47d1dc6cccb141936407d0217eafdc465558190
Engine: Godot 4.8.beta2.official.cafc17a19
Audit scope: source review, current catalog analysis, manufacturer/retailer research,
and focused economics execution in an isolated 240 Hz project. No production edits.

START HERE
The DOCX and PDF report contain the audit findings and implementation sequence.
verification_scope.json distinguishes executed checks from proposed work.
fleet_inventory.txt records each current route, priced rows and source bindings.
price_observations_2026-11-09.json contains 27 proposed evidence-import candidates.
implementation_contract_proposed.json is a design contract, not a runtime schema.
acceptance_matrix_proposed.json has 43 future cases and eight release gates.
Every proposed case is explicitly marked proposed_not_executed.

EXECUTED EVIDENCE
executed_verification/ contains the final successful checked-runner reports and logs
for 12 existing Godot scripts (674 assertions), plus the 10 custom audit probes.
audit_probe.gd and audit_probe_results.json reproduce CURRENT BEHAVIOR, not fixes.
Some probes intentionally demonstrate undesirable behavior; a passing probe means
its stated observation matched the pinned implementation. Calculator/helper inputs
are constructed fixtures, not flown graphical crashes. See each probe's scope.
The 67 Python test and two generator pass results are auditor observation records
in verification_scope.json; separate raw stdout was not retained for those steps.
Initial harness dependency/configuration and fixture corrections are disclosed there.

REPRODUCING THE FOCUSED HARNESS
1. Check out the exact commit. Use the repository-pinned Godot build and its normal
   tooling guidance. The full source tree is required; large rendering assets are
   not part of the delivered evidence archive.
2. Create an isolated working directory containing economy_harness/ and research/.
   For every entry in harness_manifest.json, copy app/<path> from the checkout to
   economy_harness/<path> and verify the recorded SHA-256. There are 217 source
   files in this manifest, including transitive preload dependencies.
3. Copy app/data into economy_harness/data, app/i18n/es.po into the matching i18n
   directory, and research/crash-economics/repair-recipes.json into the sibling
   research/crash-economics directory. Preserve any repository schema/dependency
   files required by the checked source; do not substitute altered source code.
4. Use harness_project.godot as economy_harness/project.godot. It intentionally has
   no game scene or autoload and retains 240 Hz plus the Spanish localization.
   Initialize required Godot imports/class metadata using the repository's tooling.
5. recorded_economy_runner.py is the actual runner used in this audit. Its BASE,
   checkout and engine paths refer to the audit workspace; adapt those locations
   before use. It imports the repository's tools/godot/run_checked.py, executes the
   manifest's 12 test scripts, and checks diagnostics plus the correct success text.
6. Place audit_probe.gd at the harness root and run it through the same checked
   runner with --headless --path <harness> --audio-driver Dummy --script
   res://audit_probe.gd. Its required success text is AUDIT PROBES: 10 checks, 0 failed.
   The runner must reject emitted engine errors even if a process exits zero.
7. Full-main checkpoint, live scene, graphical flight, native performance and physical
   calibration are separate gates. Do not label this harness as those verifications.

DATA IMPORT CAUTIONS
These observed prices do not prove physical compatibility. Package units, included
parts, exclusions and availability must be reconciled against the installation.
P01 is exact only for the default Jensen, 61FX Stik and Extra's authored LP12060.
The 55AX uses LP12070 12x7; FS64V uses Master Airscrew K14x6. Equal prices are not
identical parts. Electric Stik's four matched named-product observations total
US$414.84; this is not a whole-aircraft value. Unknown package details stay unknown.
JetCat's EUR350 threshold is NOT a flat fee. Labor durations are proposed game policy.

INTEGRITY
evidence_manifest.json lists hashes of the files in this evidence package.
Report provenance and source links are indexed in source_index.json and the report.
Current source copies remain in the Git repository; the archive does not duplicate
that repository. The audit generator is supplied in report_generation/ for traceability;
it uses original workspace paths and would need path adaptation before regeneration.
