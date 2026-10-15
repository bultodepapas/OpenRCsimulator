# D8b-R2 candidate staleness diagnostic

The frozen 2026-10-15-07 check failed because `candidates/steep.json` was stale, not missing. Its manifest entry exists (57,827 bytes, SHA-256 prefix `ee8e7cc6`), and the generator log reports a byte-freshness failure with exit 1, no timeout, and no engine error. The [original frozen pull-up suite](../next-candidate/materialized-20261015-07-01/diagnostic-tail-01/logs/021-pullup_cli_acceptance.log) completes with one failure in three tests: the runtime refuses the stale candidate because its non-polar data differs from the catalog. The later disposable-copy `F.` log is a separate incomplete attempt, described below.

Static comparison found all three frozen candidates retained older D11g data and provenance: `CLq` 1.977 vs 2.003, `Cmq` -7.944 vs -8.009, and `Cnr` -0.1354 vs -0.1335, plus the corresponding old source strings. These are candidate-generation identity differences. They do not establish whether either coefficient set is physically correct. The frozen baseline Stik input and `make_candidates.gd` still match the frozen source manifest.

I regenerated the three synthetic candidates with the existing upstream generator in disposable copy `.02`; its write and `-- --check` runs both succeeded, and each generated polar matches its pre-regeneration frozen candidate. The generator did not change catalog or other source inputs. `04-regeneration-verification.json` is a Python-parsed static comparison and reports one remaining decimal-lexeme difference for `Cldr.value`: frozen source `0.00045123687978342573`, generated text `0.00045123687978342`. Do not interpret that report as a Godot dictionary mismatch. The frozen Godot 4.7.2 probe parses both values to the same runtime value `0.00045123687978342`; validation and full-precision stringify preserve it, and the catalog/candidate dictionaries compare equal after removing `aero.wing_polar`. See [the probe output](execution/05-godot-cldr-parse-probe.log).

The unchanged frozen `test_pullup_cli.py` then passed all 3 tests using the regenerated intermediate candidate. The test module was loaded from frozen `-07`; its `APP` and `REFERENCE` stayed at frozen `-07`, and only its `CANDIDATE` module variable was overridden to `.02/intermediate.json`. The test method bodies and the candidate fixture bytes were untouched. [The captured output](execution/06-frozen-override-unittest.log) includes the complete test result and SHA-256 identities.

Root independently reviewed and copied the three qualified generator outputs into their live research fixture paths. Each file changes exactly six leaves relative to its previous fixture: the values and source descriptions of `CLq`, `Cmq` and `Cnr`. The polar, `Cldr` and every other parsed leaf remain unchanged. The [integration receipt](live-regeneration-promotion-01.json) records all before/after hashes and retains [the previous fixtures](previous-candidates/). The current Stik JSON, fixture and generator match the frozen inputs byte-for-byte; the other three bound text inputs differ only by CRLF line endings, with both identities recorded. This repairs generated test fixtures; no synthetic polar is promoted into the aircraft catalog.

The first scratch copy `.01` accidentally included the source `.godot` cache during broad copy preparation. It was never imported, generated, or tested. I retained it and prepared `.02` as a clean copy excluding `app/.godot`; only `.02` received Godot import, generator runs, and the earlier direct CLI attempt. Import produced 435 cache files and one generated native-extension `.uid` support file. The earlier direct CLI log ends `F.` without traceback or summary, so it remains inconclusive; the frozen-module override run above is the qualifying CLI result. No frozen-07 or live application files were modified.

The exact command outcomes, hashes, copy history, parse result, and test override are bound in [the final reproduction receipt](execution/07-final-reproduction-receipt.json). The logs are in [execution](execution/), while [the initial static diff](frozen-07-static-diff.json) remains bound to frozen input bytes. `copy-preparation.json` records `.02`'s source manifest and copied input hashes. The original 2026-10-11 `implementation/verification.json` remains historical and unchanged.

To reproduce the disposable regeneration (Godot import initializes only the `.02` copy):

```bash
APP=/mnt/c/DEVELOPMENT/OpenRCsimulator/tmp/physics-audit-r11-d8b-candidate-repro-02/app
GEN=/mnt/c/DEVELOPMENT/OpenRCsimulator/tmp/physics-audit-r11-d8b-candidate-repro-02/research/flight-robustness/d8b-r2/make_candidates.gd
GODOT=/home/bulto/openrc-r11-b09-r05b-20261015-07/.tools/Godot_v4.7.2-stable_linux.x86_64
"$GODOT" --headless --path "$APP" --audio-driver Dummy --import
"$GODOT" --headless --path "$APP" --audio-driver Dummy --script "$GEN"
"$GODOT" --headless --path "$APP" --audio-driver Dummy --script "$GEN" -- --check
```

To rerun the frozen test with its single intended module override:

```bash
GODOT=/home/bulto/openrc-r11-b09-r05b-20261015-07/.tools/Godot_v4.7.2-stable_linux.x86_64
OPENRC_TEST_GODOT="$GODOT" timeout 360 python3 \
  /mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/d8b-candidate-diagnostic/execution/run_frozen_pullup_override.py \
  /home/bulto/openrc-r11-b09-r05b-20261015-07/app/tests/test_pullup_cli.py \
  /home/bulto/openrc-r11-b09-r05b-20261015-07/app \
  /mnt/c/DEVELOPMENT/OpenRCsimulator/tmp/physics-audit-r11-d8b-candidate-repro-02/research/flight-robustness/d8b-r2/candidates/intermediate.json
```
