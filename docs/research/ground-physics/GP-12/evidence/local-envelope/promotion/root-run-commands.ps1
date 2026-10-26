# Repository root, AFTER root applies ONLY normal-interval.patch and creates
# app/tests/test_normal_compliance_interval.gd from the exact promotion payload.
# Do not copy the entire Normal draft over gp08's separate trial-receipt work.
python tools/godot/run_checked.py --out-dir tmp/gp11-local-envelope/main-checks --label interval-parse --warnings-as-errors --timeout 90 -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --script res://physics/normal_compliance.gd --check-only
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
python tools/godot/run_checked.py --out-dir tmp/gp11-local-envelope/main-checks --label interval-production --warnings-as-errors --require-text 'Normal compliance interval: 465 checks, 0 failed' --timeout 120 -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --script res://tests/test_normal_compliance_interval.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
python tools/godot/run_checked.py --out-dir tmp/gp11-local-envelope/main-checks --label existing-normal-production --warnings-as-errors --require-text '88 normal-compliance checks, 0 failed' --timeout 120 -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --script res://tests/test_normal_compliance.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
python tools/godot/summarize.py tmp/gp11-local-envelope/main-checks
