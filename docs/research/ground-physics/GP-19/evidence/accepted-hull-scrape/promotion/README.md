# GP19 hull scrape promotion payload (NOT promoted)

Prepared2026-10-26. Runtime sources remain only in tmp until root approval.
`manifest.json` pins the four exact current app source bases and all projected
payload bytes. `../draft/review.patch` is the minimal four-runtime-file patch;
its fresh git apply --check passed. Do not overwrite Session with a stale whole
file: validate the base SHA and apply that minimal patch against fresh source.
The payload mirrors final production paths and contains no tmp preloads.

New test names:
- app/tests/test_hull_friction_observation.gd
- app/tests/test_hull_scrape_audio.gd
- app/tests/test_hull_scrape_session.gd
- app/tests/fixtures/hull_friction_reference.bin

The9132-byte binary stores old-source prepared/default-load/dynamic-load results
under Godot4.8.beta1.official.4d10419ca, produced by the frozen pre-change Hull
source aa9cd474975d8e529dea14fef46baa0c6208ca78652ba28e8203773a04024e92.
Its SHA256 is66f4a8e91c6b5161db938ac3a3deadbed9993829703fcffdd00755937e082811.
The test pins the entire raw fixture and never loads a duplicate physics law.
The one-time capture script and checked receipt remain outside app under
../draft/freeze_reference.gd and ../checks/reference-02. This is a numerical
software baseline, not independently measured physical validation.

`attributes-snippet.txt` supplies one targeted -text line for that binary;
append it surgically to the current shared .gitattributes only at promotion,
preserving unrelated pending entries. The app/test.sh test_*.gd loop discovers
all three tests automatically; no runner registration/partition edits needed.

Promotion checks: verify all manifest base hashes; git apply --check the patch;
ensure new destination paths do not already exist; apply runtime patch; install
only the three new tests and exact fixture bytes; append the one attribute line;
verify new source/fixture hashes; run production-commands.ps1 from repo root.
Commands are read-only tests; the file is not a promotion script.

Current corrected draft501-check subset is complete/ok with zero engine
errors/warnings:367 metric fixture +46 audio +40 Session +12 existing CrashAudio
+36 existing soft contacts. These are explicit source/preload substitutions,
not a production app pass. Two existing full-scene regressions in the production
command list are next gates after reviewed promotion. They have generic literal
completion markers because their counts have not yet been measured here.

Capture-side cancellation only clears queues/requests a tagged stop; render
applies it before any fresh grains. Malformed packets fail quiet. Native capture,
listening/headroom and quiet-host timing remain deferred. Root's44-path native
fleet source identity list now includes this chain; older reusable captures do
not qualify the new hull/mechanical/accepted-contact runtime. No new native
capture has run, and no assets have been created or changed.
