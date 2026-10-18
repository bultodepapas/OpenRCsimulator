# Frozen tree comparison inputs

The [freeze receipt](freeze.json) records every app-file hash in both native snapshots, the source Git revision, and the nine deliberate file differences. [Import receipts](import-report.json) establish clean serial native imports with no source or UID changes. These files describe a reconstructed visual baseline on the same shared runtime, not two historical releases.

To reconstruct the candidate, start at the recorded Git revision and overlay `candidate-overrides/` from this folder onto a disposable checkout. The overrides retain the exact app changes present at freeze time, including shared measurement code that was being developed concurrently. They are evidence snapshots, not a second implementation home. Make a second copy and overlay `baseline-overrides/` to restore the historical card shader, field layout, imported-tree alias selection and four texture import settings. Both copies retain the new unused source assets and the same simulator, audio and grass code. Use the accepted source/native-library setup from the repository guides where required.

The timing runner explicitly sets imported-tree wind off in the baseline and on in the candidate. Both use zero spatial cell size and the same default grass route. Native imports may regenerate `.godot/` caches; those caches are excluded from source identity. Verify the app hashes in `freeze.json` before running measurements. [Stored evidence hashes](stored-sha256.json) bind the overrides, receipt and freeze recipe.

The freeze is deliberately insulated from later changes in other tracks. A final tree result does not automatically qualify new grass, audio or simulator changes made after this snapshot.
