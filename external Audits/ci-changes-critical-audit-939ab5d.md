## My honest assessment

**The CI changes are substantial improvements, but the reviewed commit is not yet validated end to end.** The new checks have caught real problems that previously could have escaped through successful process exit codes. However, I also reproduced a false pass in a new numerical test, found several source changes whose dependent test evidence was not updated coherently, and confirmed that the visual parallelization experiment is still adding substantial work without establishing equivalence.

My recommendation is to **keep the stronger checks, repair their remaining weaknesses, and obtain one complete required green run at a single commit before promoting further optimizations**.

### What I reviewed

| Item | Reviewed scope |
|---|---|
| Repository | `bultodepapas/OpenRCsimulator` |
| Branch | `main` |
| Commit | [`939ab5df4de4fc615b1051d2b1e4cba51a423b27`](https://github.com/bultodepapas/OpenRCsimulator/commit/939ab5df4de4fc615b1051d2b1e4cba51a423b27) |
| Comparison baseline | `970c88902945780cbf2c2f212a17d037c7f9d869` — 47 commits earlier |
| Earlier integrated success | `19975334594f8d986ed6c10280c03626f2ce371e` |
| Run-status cutoff | November 8, 2026, **19:46:25 UTC** |
| Method | Source and history review, GitHub runs and job logs, artifact inspection, existing helper tests, and controlled negative tests with the pinned Godot executable |

I first read and cross-checked [CONSOLIDATED-AUDITS.md](https://github.com/bultodepapas/OpenRCsimulator/blob/939ab5df4de4fc615b1051d2b1e4cba51a423b27/external%20Audits/CONSOLIDATED-AUDITS.md). I am **not reopening the exact repaired A27 CI-01–08 and CI-10 issues**. Below, I distinguish new defects, regressions, previously pending qualification, and remaining limitations.

**Full report and evidence:** OpenRC-CI-Changes-Critical-Audit-939ab5d.zip[OpenRC-CI-Changes-Critical-Audit-939ab5d.zip](sandbox:/workspace/scratch/b2103663fdfc/deliverables/OpenRC-CI-Changes-Critical-Audit-939ab5d.zip). It contains the report, relevant logs and metadata, measured timings, artifact summaries, and the reproducible NaN mutation. No repository source was changed or published.

## Prioritized findings

| Priority | Finding | Classification | Practical consequence |
|---|---|---|---|
| **P1** | A new physics comparison accepts `NaN`; a deliberately corrupted script still passes **218 checks** | **New, reproduced test defect** | A successful result can conceal an invalid numerical result |
| **P1** | Four source-bound fixture families no longer match the physics/source identities they validate | **New integration regressions** | Native qualification, integration, shaft/weather checks, and downstream export are blocked |
| **P1 investigation** | Home launch controls fail the English/Spanish 200% text layout checks | **Confirmed test regression; user-visible impact needs isolation** | Accessibility/layout validation has regressed |
| **P2** | An older calibration recovery test still requires obsolete wording | **Confirmed stale expectation** | Another failure remains behind the earlier Home failure |
| **P2** | Seven visual shadow groups still disagree with the full capture | **Previously pending qualification, now with failed hosted comparisons** | Additional runner work and artifacts without a qualified replacement |
| **P2** | Visual “equivalence” excludes meaningful metrics stored only in logs | **Verified limitation of the comparison boundary** | Future equivalence could overlook quantitative differences |
| **P3** | Capture artifacts remain difficult to inspect despite successful deduplication | **Existing concern, materially improved but unresolved** | Diagnosing differences still requires unnecessarily large downloads |

---

## 1. The strongest new finding: a numerical test can pass with a NaN result

**Affected:** CI application units, currently units 3; [`app/tests/test_generator_rate_datums.gd:85–89`](https://github.com/bultodepapas/OpenRCsimulator/blob/939ab5df4de4fc615b1051d2b1e4cba51a423b27/app/tests/test_generator_rate_datums.gd#L85-L89), used by the comparisons at lines 174–183.

The helper implements this comparison:

```gdscript
if absf(a[i] - b[i]) > 1.0e-8 * maxf(1.0, absf(b[i])):
    return false
```

It returns `true` if no component exceeds the tolerance. However, an ordered comparison involving `NaN` does not behave like an ordinary numeric comparison: the `>` condition can remain false, allowing the helper to accept the result. Godot documents this special comparison behavior. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_float.html?utm_source=chatgpt.com)

### What I reproduced

I ran the complete test script in an isolated project containing the frozen physics source and data, using the **exact pinned Godot 4.8 beta2 executable** and the same 240 Hz physics setting.

Then, in a disposable copy, I inserted one line into the function that returns the computed wrench difference:

```gdscript
result[4] = NAN
```

That deliberately corrupts the computed pitch-moment difference.

| Execution | Reported checks | Failed | Process exit | Checked engine errors |
|---|---:|---:|---:|---:|
| Original script | 218 | 0 | 0 | 0 |
| Script with injected `NaN` | **218** | **0** | **0** | **0** |

The [current hosted units 3 job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42513754044/job/128832813265) independently passed the unmodified full-project test with the same count.

**This demonstrates a defective test oracle. It does not demonstrate that production currently produces NaN.** That distinction matters.

The script has finite-value checks elsewhere, but those cover different transition samples. They do not protect these attached-flow/reference/live-CG comparisons.

**Correction:** Check the six-component shape and reject non-finite values in both arrays before evaluating tolerances. Preserve the independent wrench and cross-product assertions.

**Verification:** The original script must pass; explicit `NaN`, positive infinity, and negative infinity controls must fail. The recorded one-line mutation must make the complete script fail through `run_checked.py`, followed by a focused hosted full-project execution.

This is my highest-priority finding because it concerns **misleading success**, rather than a visible red check.

---

## 2. Shared physics changes were not integrated with all dependent evidence

At the cutoff, [run 42513754044](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42513754044) remained in progress, but **five required jobs had already failed**, and export was skipped.

Four failures concern source-bound physics evidence:

| Failing job | Observed failure | Relevant implementation |
|---|---|---|
| [NK-3 native qualification](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42513754044/job/128832813106) | FS64V four-stroke aircraft identity mismatch; **54 checks, 1 failure** | `research/native-kernel/test_glow_rejection.gd:174–207` |
| [Application integration](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42513754044/job/128832813236) | **16 assertions fail across eight** fleet reset configurations | `research/native-kernel/fleet.gd:444–451, 765–800` |
| [Application units 4](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42513754044/job/128832813373) | Two frozen shaft traces fail; **155 checks, 2 failures** | `app/tests/test_shaft_publication.gd:67–89` |
| [Application units 6](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42513754044/job/128832813335) | Four weather traces fail; **196 checks, 4 failures** | `app/tests/test_weather_publication.gd:45–69` |

### Why these failures occurred

Several tests bind their expectations to more than numerical state:

- The FS64V native rejection fixture pins the exact aircraft file bytes. The file now contains three provenance-string changes advancing the wake law from v2 to v3. Its numeric coefficients are unchanged **within that file**, but its byte identity necessarily changes.
- The fleet proof includes a live-configuration identity. The aerodynamic law advanced to v3, and non-turbine configurations gained a coefficient-law identity.
- Shaft and weather tests hash whole checkpoints. Those checkpoints include the aerodynamic-law string and configuration identity, so the expected digest must change even if the numerical state were identical. See [`flight_session.gd:5624–5630`](https://github.com/bultodepapas/OpenRCsimulator/blob/939ab5df4de4fc615b1051d2b1e4cba51a423b27/app/sim/flight_session.gd#L5624-L5630).

**These observations do not justify blindly replacing the hashes.** Actual aerodynamic and propeller equations also changed. The present digest failures do not explain whether state trajectories changed, which changes were intended, or whether rejection behavior remains correct.

The fleet failures also should not be reported as sixteen separate product bugs: there are two failing assertions per affected configuration.

### Why this matters beyond the failing tests

After the glow identity failure, later NK-3 admission, paired runtime-domain refusal, production parity smoke, and export-input publication steps were skipped. Integration similarly stopped before its later application check and coverage receipt.

The Linux and Windows RC native production jobs passed, but that does **not** qualify those skipped NK-3 consumers.

**Correction:** Treat shared law changes as a coordinated source-and-evidence migration:

1. Preserve the original baselines.
2. Produce typed, field-level comparisons of old and current configuration, state, events, and refusal outcomes.
3. Explain intended numerical differences.
4. Requalify each affected fixture and its native/reference consumers.
5. Bind the accepted evidence to the resulting commit.

**Verification:** Run all four focused families, then the downstream native checks and export, and finally complete required CI at the same commit.

A useful optimization here is an **early dependency check for stale evidence identities**. Detecting an inevitable fixture mismatch before native compilation and long captures would save work without weakening validation.

---

## 3. Home layout has a real test regression, but the exact user impact is not yet established

**Affected:** application units 7; [`test_home_launch_conditions.gd:49–71`](https://github.com/bultodepapas/OpenRCsimulator/blob/939ab5df4de4fc615b1051d2b1e4cba51a423b27/app/tests/test_home_launch_conditions.gd#L49-L71), and the Home caption/action rail.

The [current job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42513754044/job/128832813222) reports **76 checks, 2 failures**:

- English, 200% text scale, Aircraft page.
- Spanish, 200% text scale, Aircraft page.

Both fail the assertion that the shared Fly and utility controls remain within the viewport bounds. These cases passed in the [earlier required-green run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42445418943/job/128623744884).

The changed launch summary now uses more vertical space. The fixture also retains a runtime-refusal message alongside an already inadmissible weather state. That combination is a plausible contributor, but I did not establish it as the isolated cause.

There is an additional diagnostic weakness: the test assigns `root.size` once, then compares against literal 1920×1080 bounds without asserting the settled viewport dimensions or printing individual control rectangles. Therefore, the evidence supports **a regression in this layout gate**, not an unconditional claim that ordinary native 1080p usage clips the controls.

**Correction:** Record the settled viewport, locale, text scale, page, visible messages, and Fly/Quit rectangles. Reproduce a reachable equivalent UI state, then fix the responsive rail or scrolling behavior if it genuinely overflows.

**Verification:** English and Spanish, both pages, 100% and 200% scale, with and without the relevant messages, plus actual 1080p inspection. Keep the accessibility assertion.

---

## 4. A stale calibration assertion will still fail after the earlier Home problem is fixed

**Affected:** application units 7; [`test_ui_recovery_dead_ends.gd:89–93`](https://github.com/bultodepapas/OpenRCsimulator/blob/939ab5df4de4fc615b1051d2b1e4cba51a423b27/app/tests/test_ui_recovery_dead_ends.gd#L89-L93).

The older recovery test requires:

> “Radio calibration cancelled”

Production now displays:

> “Calibration cancelled. Your controller settings remain active. Settings saved before calibration are kept.”

The old substring cannot match. An [earlier run failed on exactly this assertion](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42486859593/job/128751309874), and both the old assertion and new production wording remain in the reviewed commit.

The current shard stops at Home first. **This later failure is hidden by an earlier failure, not repaired.**

**Correction:** Update the expected communication contract while retaining the actual Escape, wizard dismissal, Pause state, settings preservation, and Resume checks. Avoid reducing the assertion to “some nonempty text appeared,” or deriving all expectations from the production formatter.

**Verification:** Run both the older recovery journey and the newer calibration-disclosure test, including their periodic refresh behavior, then the complete shard.

This is a small correction, but it reveals an integration habit worth improving: when a new test covers revised behavior, search for older tests that still encode the previous contract.

---

## 5. Visual parallelization remains an expensive qualification experiment

**Affected:** [`ci.yml:515–615`](https://github.com/bultodepapas/OpenRCsimulator/blob/939ab5df4de4fc615b1051d2b1e4cba51a423b27/.github/workflows/ci.yml#L515-L615), `visual-groups`, `visual-shadow`, and `tools/ci/capture_groups.py`.

The seven grouped capture jobs currently run **in addition to** the full required visual job on main/manual runs.

That is a reasonable qualification design temporarily. The evidence does not yet support promoting it:

| Source | Full/group execution | Shadow comparison |
|---|---|---|
| `1997533` | Full visuals and all seven groups passed | **10 image differences, 17 data differences** |
| `18b1319` | Full visuals and all seven groups passed | **10 image differences, 16 data differences** |

Sources: [first comparison](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42445418943/job/128642958088), [second comparison](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42486859593/job/128791296255).

All ten differing images were UI captures. Four Home/Help data differences in the first run reduce to the changed image hashes after normalization, so **10 + 17 should not be presented as 27 independent defects**. Pause/Hint metadata also differs beyond its image hashes.

Different CPU models appear in the records. Pause/Hint also wait one wall-clock second before freezing live flight state. Those are useful hypotheses for scheduling-dependent results; neither is a proven cause.

### The measured cost

At `1997533`, the seven shadow jobs added:

- **12,149 seconds — 3h22m29s — of summed job execution**.
- **904,872,353 bytes** of group/shadow artifacts.
- The **1h36m20s full visual job still ran**.

These are execution and storage measurements, not billing estimates or demonstrated savings.

The experiment is explicitly nonblocking, and `production_qualified` remains false. I found no reason to characterize this as a false green in the required aggregate. GitHub’s `continue-on-error` semantics support keeping such experimental failures nonblocking when deliberately configured. [GitHub Docs](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax?utm_source=chatgpt.com)

### The comparison also has an explicit boundary

The inventory excludes `scenario/history` and three regenerable L9c mutation-project trees. Fresh scenario groups have no previous-run history. A future `equivalent=true` therefore would not, by itself, establish history-dependent behavior or equality of those excluded trees.

**Correction:** Keep the full required gate. While these differences remain understood only partially, make the expensive shadow campaign deliberate/manual and first compare a small, matched UI subset with useful full-side images and sidecars.

**Verification before promotion:** Same-commit complete group coverage; explained image/data differences; structured metric comparison; separate history and mutation-project qualification; and matched measurements of both critical path and total runner work.

---

## 6. “Equivalent” currently omits some meaningful numerical evidence

**Affected:** [`capture_groups.py`](https://github.com/bultodepapas/OpenRCsimulator/blob/939ab5df4de4fc615b1051d2b1e4cba51a423b27/tools/ci/capture_groups.py), especially lines 441–442, 479–482, and 633–646; `test_capture_groups.py:640–650`; `test_lighting_segment_filter.gd:78–80, 167–191`.

The comparator treats log differences as informational and removes log hashes from normalized JSON. An existing fixture explicitly permits arbitrary log drift.

However, some lighting error measurements exist **only in `engine.log`**. Consequently, two passing captures can report different quantitative results while still satisfying this equivalence schema.

This is a limitation of the declared comparison boundary, currently outside the required gate. It becomes important before that comparison is used to justify replacing full captures.

**Correction:** Emit a compact structured record for semantically meaningful measurements. Compare those with explicit, justified tolerances; keep volatile timing and incidental wording informational.

**Verification:** Changing only a meaningful metric must fail comparison. Changing an allowed timestamp or path must pass.

There is a related wording issue in `app/capture.sh:243–249`: the comment promises a “complete assertion roster,” while the summarizer checks minimum counts and the number of `ok` lines, not assertion identities. A synthetic log with thirteen duplicate labels is accepted.

I did **not** find omitted assertions in the inspected hosted lighting logs. This is an overstatement of the guarantee, not evidence that those hosted cases were skipped. Narrow the comment, or add stable assertion IDs if exact case inventory is intended.

---

## 7. Artifact deduplication works, but evidence is still too cumbersome to inspect

This change deserves credit.

The hosted preparation at `1997533` verified **4,620 identical upload-eligible files**, representing **894,643,658 uncompressed duplicate bytes**, before choosing the compact upload. The helper checks the file roster, sizes, hashes, and modes; preserves original projects; reconstructs independent copies; and falls back to the complete upload when equivalence is not established. Fifteen existing helper fixtures passed during this review. Sources: [`capture_project_evidence.py`](https://github.com/bultodepapas/OpenRCsimulator/blob/939ab5df4de4fc615b1051d2b1e4cba51a423b27/tools/ci/capture_project_evidence.py), [hosted visual job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42445418943/job/128623744717).

The workflow also correctly checks the preparation step’s raw **`outcome`**, rather than its adjusted `conclusion`, when selecting the optimized path. That distinction matters for a step using `continue-on-error`. [GitHub Docs](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts?utm_source=chatgpt.com)

The remaining problem is usability: the resulting capture archive was still **2,381,483,814 bytes**. The available artifact tool refused it because its download limit is **536,870,912 bytes**. That is a limitation of this tool, not a claimed GitHub artifact limit.

As a result, I could inspect smaller group artifacts but could not retrieve the complete full-side capture archive needed for some comparisons.

**Correction:** Publish small summaries, diagnostics, and selected comparison images separately from large mutation-project bundles. Preserve the complete raw evidence.

**Verification:** A reviewer should be able to investigate a failure without downloading the entire archive. Separately qualify extraction and reconstruction against a real transferred artifact; local helper fixtures alone do not establish that complete hosted round trip.

---

## What improved meaningfully—and should be kept

### The asynchronous tests caught real engine failures

At `61efd99`, the checked runner rejected a zero-exit execution containing resumed coroutines whose scripts had already been freed. At `aa39ce5`, it rejected zero-exit null-material diagnostics. The later required-green run at `1997533` provides integration evidence for the subsequent repairs.

Sources: [coroutine-lifetime failure](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42440140032/job/128607938704), [null-material failure](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42442758356/job/128615857920), [later integrated run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42445418943).

This is valuable testing: cancellation, stale completion, reversal, owner teardown, and re-entry are being exercised with bounded semantic waits. Successful process termination alone would have missed the observed problems.

### Lighting now has real hosted execution evidence

The `1997533` full visual job executed:

- **13 skin checks**.
- **12 segment checks**.
- Two expected invocations, two completed passes, **zero skips**.
- Mesa llvmpipe rendering at a requested 1920×1080.

The segment comparison reported point-sampled far-red error **0.5**, versus filtered error **0.02959**. [Hosted evidence](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42445418943/job/128623744717).

That advances A27 CI-09 beyond its ledger state of awaiting hosted execution. Full closure still needs the deliberately broken rendered implementation to be rejected end to end; shell-marker fixtures are not the same proof.

### The stripe negative control targets the intended defect

I downloaded and checked the smaller [ground-group artifact](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42445418943/artifacts/13604183657).

Its summary confirms that `threshold_no_stripes` was rejected specifically because nearby stripes were erased instead of filtered. This is a useful improvement: an unrelated oblique-view failure cannot substitute for detecting that defect.

It remains a component fixture, not universal native 1080p visual qualification.

### Native branches, receipts, and exporter checks remain stronger

The installed native runtime checks require actual production branch markers. Script receipts reconcile disjoint unit execution and the parse complement. Selection is independently recomputed by the aggregate. The exporter uses checked execution and explicit completion semantics.

The historical successful export runs are meaningful; current export being skipped after its required native producer fails is **correct failure propagation**. See the [workflow](https://github.com/bultodepapas/OpenRCsimulator/blob/939ab5df4de4fc615b1051d2b1e4cba51a423b27/.github/workflows/ci.yml) and [successful baseline run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42378901695).

The newer wrench, propeller-boundary, checkpoint refusal, and reload tests also target useful software invariants. They should be retained while their comparison and integration weaknesses are corrected.

---

## CI map: what successful checks actually establish

The repository has one checked-in workflow, with no checked-in reusable workflows or composite actions. Its major relationships are:

| Stage | Connection and successful guarantee | Important limit |
|---|---|---|
| Triggers and scope | Main pushes, `v*` tags, PRs, manual dispatch; orchestration/preflight checks and selection receipt | Scope remains deliberately broad in shadow mode |
| Application matrix | Eight unit shards plus integration; successful script execution and roster reconciliation | Script coverage is not assertion or behavioral coverage |
| Native producers | Linux/Windows RC artifacts and NK-3 qualification | Later checks are unverified when an earlier gate fails |
| Native RC runtime | Uses the same run’s installed artifacts and requires production markers | Separate from all NK-3 admission/refusal evidence |
| Full visuals | Required capture campaign with checked diagnostics and completion evidence | Linux software rendering does not qualify every native renderer/device |
| Visual groups and comparison | Seven optional groups compared against the same run’s full capture | Experimental; outside the required aggregate |
| Export | Depends on native producers; packages, validates identity/resources, and exercises the Linux host package | Cross-export does not prove native Windows/macOS launch |
| `CI required` | Recomputes selection, checks upstream results, reconciles receipts | Its name does not configure repository merge enforcement |
| Tagged publication | Requires aggregate and export; verifies transferred files and source/run identity | Depends on the preceding qualification being complete |

Source: [reviewed workflow](https://github.com/bultodepapas/OpenRCsimulator/blob/939ab5df4de4fc615b1051d2b1e4cba51a423b27/.github/workflows/ci.yml).

Only superseded runs of the same PR cancel each other; main/tag/manual runs remain independent. The reviewed orchestration has explicit timeouts, and I did not find automatic test retries masking these failures.

The visible branch metadata reported `main` unprotected, with no required-check contexts, and the ruleset list was empty. The administration-only protection endpoint returned 403. That is an enforcement visibility limit; it does not invalidate the aggregate’s engineering checks.

---

## Performance: storage improvement is proven; overall speedup is not

These are **actual completed visual-job durations**, not estimates:

| Source | Visual job duration | Capture artifact bytes |
|---|---:|---:|
| [`997e212`](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42333181434/job/128284895924) | 2h31m39s | 3,122,106,181 |
| [`8306c72`](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42376164607/job/128414737885) | 1h37m04s | 2,381,235,246 |
| [`970c889`](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42378901695/job/128422626545) | 2h04m07s | 2,381,236,605 |
| [`1997533`](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42445418943/job/128623744717) | 1h36m20s | 2,381,483,814 |
| [`18b1319`](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42486859593/job/128751309766) | 2h37m06s | 2,381,643,409 |

All these visual jobs passed. Other jobs failed in the last run.

The duplicate-input removal is directly verified. The elapsed-time variation is too large, and source/host conditions differ too much, to attribute a reliable whole-job speedup to one optimization.

At `1997533`:

- Ground and vegetation consumed **3,187 of 5,594 capture-phase seconds**, approximately **57%**.
- Integration took **1h11m29s**.
- Therefore, even qualified grouped visuals around 54 minutes would not make the complete pipeline a 54-minute pipeline.

Those measurements support concentrating optimization on expensive capture phases and the integration critical path, while preserving exact execution receipts. They do not support further parallelization merely because more jobs can run simultaneously.

## Practical remediation order

1. **Repair the numerical oracle first.** Retain the exact NaN mutation as a negative control.
2. **Correct the stale calibration expectation and isolate the Home layout regression.** Preserve the meaningful user-journey and accessibility requirements.
3. **Reconcile the four source-bound fixture families with typed before/after evidence.** Avoid unexplained digest refreshes.
4. **Obtain one complete required green at the integrated candidate commit**, including the previously skipped native consumers and export. Record that exact run in the existing ledger.
5. **Focus visual qualification on interpretable differences.** Add structured metrics, compact comparison artifacts, and explicit history/mutation-project qualification before promotion.
6. **Then optimize the measured bottlenecks.** Use per-invocation timings for sharding and integration splitting, and measure both feedback time and aggregate runner work.

### Limits of this review

The current run was incomplete at the recorded cutoff. The five required failures and skipped export were observed; I am not presenting an invented final run conclusion.

The NaN mutation ran in a minimal isolated project with frozen source/data, not the complete application environment. Its unmodified counterpart also has independent hosted full-project evidence. The full capture archive exceeded the available download limit. I did not qualify physical radios, native Metal/GPU behavior, or complete Windows/macOS packaged launch.

**My candid conclusion is that the project now has more useful tests and a more honest CI harness, but integration discipline has not yet caught up with the pace of changes.** The next valuable milestone is a coherent, source-bound green result whose numerical assertions reject invalid values and whose optimized path has demonstrated the behavior it claims to preserve.