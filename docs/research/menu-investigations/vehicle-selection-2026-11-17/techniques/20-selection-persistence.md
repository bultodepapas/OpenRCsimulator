# T20 — Transaction-preserving selection-save coalescing

**Decision:** measure in UI-VS-00; optimize only if attributed, within UI-VS-01's persistence contract. **Researched:** 2026-11-17. [Twenty-investigation index](README.md).

## Question and search vocabulary

Can repeated vehicle/skin activation spend unnecessary time validating and publishing settings, and can that work be reduced without falsely reporting a saved selection?

Queries used included `site:docs.godotengine.org FileAccess flush performance automatically closed data crash`, `site:sqlite.org atomic commit batching transactions fsync performance durability`, and `site:sqlite.org/faq.html "grouped into a single transaction"`. Useful terms are **write coalescing**, **durability boundary**, **single-writer ownership**, and **generation-ordered publication**. This concerns user preferences, not the disposable asset cache in T14.

## Primary evidence and transfer limits

[Godot's FileAccess documentation](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html) warns about excessive flushing and explains close/flush behavior. [SQLite's transaction discussion](https://sqlite.org/faq.html) explains amortizing commit work across operations, while its [atomic-commit description](https://sqlite.org/atomiccommit.html) makes the failure-recovery and storage assumptions explicit. Accessed 2026-11-17. Their useful lesson is to reduce unnecessary transactions while preserving a defined commit contract. SQLite's historical throughput examples are not OpenRC estimates, and no database migration is proposed.

The [current selection setters](../../../../../app/app_root.gd#L1069-L1166) synchronously call Preferences.save_to. [Preference validation](../../../../../app/app_state/preferences.gd#L285-L355) spans more than the selected skin. [PreferencesFile](../../../../../app/app_state/preferences_file.gd#L155-L218) verifies temporary bytes, preserves previous content and handles publication failure, including Windows replacement behavior. These protections are existing correctness requirements; the cost of this path is not yet measured.

## Application to OpenRC

First instrument validation, serialization, temporary write/readback, backup and publication separately. Compare normal selected changes, repeat activation with no effective change, and save-error recovery. The initial optimization candidate is avoiding a provably redundant save after canonicalization when the complete persistent payload and necessary commit semantics are unchanged. Revalidate the current durable state and required recovery under the existing path ownership/lock before eliding the write; equality with an in-memory last-saved snapshot is insufficient after external deletion, corruption, restoration or replacement. If durable equivalence cannot be established, use the existing save. A prior failed save still needs a retry; equal labels are not sufficient proof of equality.

Only if meaningful burst cost remains, trial a single root-owned writer with immutable snapshots and monotonically ordered generations. At most the latest unstarted candidate may replace queued work. An already-started transaction completes safely; it cannot later overwrite a newer committed generation. All in-process writers of that profile must participate in the generation owner, or use a reviewed rebase/compare-and-swap protocol against the latest committed state. A path lock serializes file operations, not the age of snapshots created beforehand. Snapshots must include the full current accepted settings or use a reviewed merge protocol, so a delayed skin save cannot erase a subsequent language, weather or control change. Define external-writer conflicts as explicit retry/recovery outcomes.

Keep effective session selection separate from durable selection. The current UX already reports save failure; an asynchronous proposal needs a truthful pending state and completion/error acknowledgement. Define maximum unsaved age and explicit checkpoint behavior before claiming it is suitable. Accepted launch uses its captured in-memory tuple and does not reread an older file. Quit/restart and a read-only profile require specified recovery, not best-effort silence.

Do not move the current shared mutable dictionaries or arbitrary scene work into a thread. Isolate serializable values and review the existing per-path lock, exact-weather witness, retained-aircraft semantics and other writers before any worker design. Preserve the verified temporary/previous-file transaction. A successful rename or file flush is not, by itself, proof of a new cross-platform power-loss guarantee.

## Counterexample and risks

A debounce timer that saves only after browsing stops can lose the last choice on a crash and can postpone indefinitely during a long interaction. It also adds pending-state complexity to a path that may already be negligible. Skipping validation or backups to improve the benchmark is unacceptable. Keep synchronous behavior when its measured cost is small.

## Experiment and decision gate

Compare existing saves, redundant-write suppression and a narrowly scoped coalescing prototype with the same recovery checks. Measure first drawn acknowledgement, handler/transaction CPU, bytes and transaction count, maximum pending age, last selected versus last committed generation, and full preview latency. Inject write/readback/rename failures; delete, corrupt or replace the file after a successful same-session save. Interleave a queued older skin snapshot with an independently committed language/weather change, external-writer conflict, immediate launch and Quit.

Accept only a material complete-flow improvement with explicit persistence semantics, preserved recovery and no lost newer settings. Reject complexity without measurable value. This investigation does not authorize weaker recovery guarantees or acknowledging durability before successful publication.

**Plan impact:** add persistence attribution and no-op/recovery cases to UI-VS-00/01; any coalescing implementation is a conditional owner-reviewed slice, not a prerequisite for the catalog or skin pilot.
