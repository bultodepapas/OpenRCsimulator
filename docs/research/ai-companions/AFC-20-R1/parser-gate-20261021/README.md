# AFC-20-R1 current-tree parser gate

The current native Windows working tree passed the full GDScript parser loop used by app/test.sh: Godot 4.7.2 ran --check-only --script once for each of 1,207 scripts under app/, excluding .godot/ and captures/. The checked runner reported zero failures, engine errors, or warnings. The 1,207-file source manifest is included here, and its before/after hashes match.

The first 640 checked reports completed sequentially. The dispatcher was then stopped during an in-flight attempt for script 641 while changing to four workers; its empty log and missing report are retained as an incomplete attempt. Four disjoint workers ran only the 567 scripts lacking a completed report. Script 641 completed once in that continuation; no completed path was rerun. Per-script reports and logs remain under the D: evidence path recorded in verification.json.

The source audit found no confirmed API regression from the crash presentation context or observation helper. Main is the sole production CrashDirector.configure caller and passes the typed context; the test fixture uses the same interface. The older configure(scene) call is for the separate scenery-damage presentation class. The observation helper remains behind Agent.observation() with the existing snapshot fields. Its exact arithmetic and runtime observation checks are separately recorded in AFC-00-R5; the current Main/companions shell check is a distinct 49-check receipt. These receipts remain separate from AFC-20-R1's original 385-check suite.

This supplement records parser and source-tree integration evidence only. It is not a fresh-checkout, full application-suite, package, timing, or physical-flight qualification.
