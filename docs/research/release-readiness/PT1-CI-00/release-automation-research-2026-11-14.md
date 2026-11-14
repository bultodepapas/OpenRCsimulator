# PT1-CI — 20 release-automation investigations

2026-11-14. Literature/API documentation review and code inspection, with focused follow-up tests. These are **20 distinct investigations, not 20 runtime experiments**. Sources were accessed on this date. The inspected working baseline was `7cdda3874bbbcd8211d722cc96835336aefec16e`; the release under observation remained `v0.2.8`, commit `bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c`, Actions run `43590594971`. Follow-up tooling changes do not alter that tag or its binaries.

The [operating manual](../../../../tools/release/README.md#patient-release-automation) owns commands; the [efficiency plan](../../../plans/release-ci-efficiency.md) owns outstanding CI qualification. This report records evidence and decisions. No repository protection, signing, attestation, workflow scheduling or release setting was changed. No token-saving percentage, CI speedup, physical validation or platform qualification was measured.

## 1. Conditional requests and ETags

**Question:** Can repeated observation transfer fewer bytes and consume less API quota?

Authenticated conditional responses can avoid primary quota charges when the server returns 304. That does not remove secondary limits. `gh` 2.87.3 treats 304 as a nonzero exit, so adding `If-None-Match` to the present JSON client would require deliberate cached-body handling. A read-only sample of the active workflow-run endpoint advertised an ETag; no 304 round trip or jobs-endpoint benefit was measured. [GitHub guidance](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api), [versioned CLI implementation](https://github.com/cli/cli/blob/v2.87.3/pkg/cmd/api/api.go).

**Decision: defer.** Measure request count, response bytes, 304 rate and detection latency first. Any cache must distinguish endpoint/query/page, authentication context and attempt; 304 must still pass identity and snapshot validation. Test 200→304→200, missing ETags and changed page/attempt before adoption.

## 2. Rate limits and retry timing

**Question:** Can the observer retry earlier than GitHub permits?

The original watcher discarded HTTP headers and retried after five and ten seconds. GitHub documents server-directed waits and a minimum one-minute fallback for identified secondary limits. An ordinary authorization 403 is different. No actual throttling was observed. [Rate-limit contract](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).

**Decision: implemented in follow-up.** Parse sanitized status and relevant headers, honor the later valid `Retry-After`/exhausted-quota reset, recognize secondary-limit messages, and stop ordinary authorization failures without repeated requests. Keep finite retries and the monotonic deadline. Fake-clock cases cover numeric/date waits, malformed headers, combined constraints and a wait longer than the deadline; no deliberate live throttling was performed.

## 3. Adaptive polling versus webhooks

**Question:** Is a webhook service justified for one bounded release watch?

The observer already sleeps, increases unchanged-state intervals to 300 seconds, and emits transitions and deduplicated alerts. Detection occurs on the next successful poll, not instantly. Webhooks add a reachable service, signature validation and delivery recovery; failed deliveries are not automatically redelivered. [Webhook practices](https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks), [redelivery](https://docs.github.com/en/webhooks/testing-and-troubleshooting-webhooks/redelivering-webhooks).

**Decision: retain polling; defer a service.** Compare scripted event-to-alert delay and request counts for candidate schedules, then use observed run timestamps if latency becomes a product need. Do not add infrastructure merely to eliminate a few quiet requests.

## 4. Pagination and coherent terminal state

**Question:** Do equal job counts establish an atomic snapshot?

No documented API guarantee makes multi-page job reads transactional. The observer checks duplicate IDs, total count, run/attempt identity and status before/after paging; it also retries a run-state transition. Job details can still change while an in-progress run retains the same overall status. Partial reruns also complicate attempt-only endpoints. [Jobs API](https://docs.github.com/en/rest/actions/workflow-jobs), [rerun behavior](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs).

**Decision: retain existing guards; defer extra terminal reconciliation pending a focused fixture.** Test unchanged counts with changed gate membership/state and partial-rerun outputs. A second terminal read could narrow a race window, but must not be described as transactional proof or adopted without measuring added requests.

## 5. Cache and artifact reuse boundaries

**Question:** Which cached bytes can tag jobs reuse safely?

GitHub permits default-branch cache restoration but does not generally share one tag's cache with another tag. Existing engine/template getters verify installed bytes; native artifacts and publication remain bound to the same Actions run. A main job still running when the tag starts may not yet have saved its cache. A cache hit establishes neither a qualified import nor valid test evidence. [Cache reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching), [cache/artifact distinction](https://docs.github.com/en/actions/concepts/workflows-and-actions/dependency-caching).

**Decision: retain verified caches; defer wider reuse.** Measure hit/miss, setup/import, restore/save and transfer costs on comparable runs. Corrupt a disposable cached member and verify rejection; preserve clean-cache coverage and all native/package checks.

## 6. Duplicate main and tag runs

**Question:** Can one same-commit run simply replace the other?

The current contract publishes from the tag run's own export and required aggregate. Main/tag refs, event context and recorded build identities differ; even tag visibility to `git describe` can differ by checkout time. Skipping a job can appear successful to protection, while dependencies and receipts still require actual coverage. [Event filters](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onpushbranchestagsbranches-ignoretags-ignore), [job conditions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions).

**Decision: reject time/commit-only deduplication.** Cross-run promotion needs a separately reviewed producer/promoter contract with artifact digests, source/ref/run checks, gate coverage and retention/failure behavior. First measure duplicate runner time. Wrong-ref, wrong-run, stale/missing artifact and failed/skipped producer fixtures must never publish.

## 7. Critical-path optimization

**Question:** Which phase should optimization target first?

Workflow elapsed time, queueing and summed job durations are different measurements. The existing DAG overlaps export with app/visual checks; existing visual phase summaries and compact diagnostics already expose useful detail. Historical long visual runs identify a candidate bottleneck, not the current run's cost or a demonstrated speedup. [Job timing](https://docs.github.com/en/actions/how-tos/monitor-workflows/view-job-execution-time), [dependency graph](https://docs.github.com/en/actions/how-tos/monitor-workflows/use-the-visualization-graph).

**Decision: measure before rescheduling.** Record comparable source/run/attempt/ref, runner/cache state, queue time, setup/import/case times, critical path and total runner minutes. Reconcile one completed run against its DAG and phase summary; inspect named failed-step logs instead of repeatedly loading full artifacts.

## 8. Tag and release immutability

**Question:** Do annotated tags and rechecks eliminate publication races?

An annotation is not necessarily a signature. Rechecking a peeled commit detects observed movement but cannot prevent a move-and-restore interval. Asset-bearing `gh release create` uses draft/upload/publication requests; immutability takes effect after publication and does not freeze every metadata field. Actual protection settings were not inspected here. [CLI creation contract](https://cli.github.com/manual/gh_release_create), [immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases), [tag rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets).

**Decision: document the limit; defer policy changes.** Review effective rules and bypasses read-only before proposing protections. Do not enable settings silently or claim existing protection. A disposable tag with a new annotation on the same commit demonstrates the distinction between annotation identity and peeled source identity.

## 9. Attestations and source-to-binary claims

**Question:** Would a signed statement prove reproducibility or trustworthy inputs?

The manifest records identities and detects input drift, but its hashes are not authenticated build provenance. Attestations can bind a subject digest to a builder/workflow statement; verification still needs a trusted identity and source/build policy. They do not establish independent reproducibility, OS acceptance or physical realism. [GitHub attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations), [Sigstore verification](https://docs.sigstore.dev/cosign/verifying/verify/), [SLSA v1.2 verification](https://slsa.dev/spec/v1.2/verifying-artifacts).

**Decision: defer to a scoped supply-chain change.** Prototype in a disposable repository with pinned action/minimum permissions and consumer policy. Wrong subject and wrong workflow must fail. Do not invent a SLSA level or silently change the six-file contract.

## 10. Independent downloads and bounded checksums

**Question:** Does downloaded-file verification have a concrete resource gap?

The verifier already checks exact inventory/schema, streamed artifact hashes/sizes, ABI binding and Mac receipt. The publisher verifies all six downloaded files against its same-run set. However, the original checksum comparison used unbounded `read_bytes()` even though the expected canonical length was known. Artifact-transfer digest warnings do not replace these explicit checks. [GitHub transfer validation](https://docs.github.com/en/actions/tutorials/store-and-share-data#validating-artifacts).

**Decision: implemented in follow-up.** Read only expected checksum length plus one and preserve exact equality. An oversized checksum fixture enforces the read budget; a small suffix proves the size-independent bound without filesystem-specific sparse allocation. Valid transfer and publication fixtures remain accepted. Hashes traveling with a payload still do not independently authenticate a publisher.

## 11. Publication retries and concurrency

**Question:** Is retrying creation equivalent to an atomic idempotent operation?

No. A timeout can leave a complete release or an incomplete draft. The existing helper accepts identical completed publication after byte verification and refuses differing/incomplete state. The same-tag concurrency group preserves its running job, but default single-pending behavior can replace an older pending entry. Run ID survives reruns while attempt changes. [Concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency), [run variables](https://docs.github.com/en/actions/reference/workflows-and-actions/variables).

**Decision: clarify recovery; retain fail-closed publication.** Inspect actual same-tag state after ambiguous failure; never overwrite a draft or different assets blindly. Use existing interrupted-create/identical-retry fixtures. Defer larger pending queues until a demonstrated requirement exists.

## 12. Archive inspection and trust boundaries

**Question:** Does matching a ZIP hash establish archive safety on every platform?

No. Linux export and Mac bundle validators inspect their archive entries under explicit bounds; generic downloaded-set verification does not rerun the Linux scan or open the Windows ZIP. Native build tar extraction also has a distinct producer/trust boundary. These are scope limits, not evidence of unsafe released files. Python cautions against extracting untrusted archives without inspection. [Python ZIP guidance](https://docs.python.org/3/library/zipfile.html#zipfile.ZipFile.extractall).

**Decision: document scope; defer a dedicated archive-policy change.** A future Windows validator needs traversal/absolute/duplicate/link/expanded-size fixtures and acceptance of real packages before extraction. Review tar handling separately; do not replace existing audits with an ad-hoc extractor or call byte verification OS validation.

## 13. Checksums, signatures and native launch

**Question:** Can integrity checks substitute for signing/notarization or device acceptance?

No. Current Mac packages are ad-hoc signed, not Developer ID notarized; the receipt does not establish signing trust. Final signing/stapling must precede receipt finalization. Downloaded/quarantined launch is a separate native test. Windows reputation and Linux driver/distro compatibility are also separate. [Godot macOS export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html), [Apple distribution testing](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), [Windows reputation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation).

**Decision: preserve current limits; defer signing infrastructure.** Verify an intentionally signed future candidate's exact downloaded bytes, signature identity, ticket/stapling and supported native launch outcomes. Do not acquire accounts/certificates or claim OS trust from checksums alone.

## 14. Crash-safe checkpoints and attempt provenance

**Question:** Can a partial local checkpoint or output set resume as a passed gate?

No. Exclusive output creation intentionally refuses overwrite and can leave partial files on I/O failure. A durable replacement protocol needs same-directory temporary data, flushing/synchronization and supported filesystem behavior; replacing an existing file would violate the release writer's different no-overwrite contract. Failed-job reruns may retain earlier successful outputs, so producing and observed attempts need separate identities. [Python fsync](https://docs.python.org/3.11/library/os.html#os.fsync), [replace semantics](https://docs.python.org/3.11/library/os.html#os.replace).

**Decision: improve recovery records; defer a durable writer.** Record attempts, evidence paths/hashes and first unmet gate; verify live state on resume. Use a fresh output directory after incomplete manifest writes. Future crash tests must reject corrupt checkpoints and distinguish two attempts sharing one run ID without blindly demanding all artifact attempts equal the latest gate attempt.

## 15. Progressive disclosure and AI context

**Question:** Can the skill remain concise without hiding release-critical constraints?

Skills initially expose metadata and load selected instructions later; lengthy descriptions and whole-manual reads undermine that design. The existing entrypoint already routes to operating sections and loads D11g/companions/export/site contracts conditionally. Actual token use was not measured. [OpenAI skill authoring and discovery](https://learn.chatgpt.com/docs/build-skills).

**Decision: retain the small entrypoint; keep this research outside it.** Forward-test pending-run resumption and version preparation separately; only the latter needs D11g detail. Compare recorded token counts for matched scenarios before claiming savings; byte count alone is insufficient.

## 16. Monitor ownership and patient resumption

**Question:** Does a recorded run ID or PID establish ownership of a local observer?

No. The CI run and local process are separate; a PID can be stale/reused and a lost client handle can leave an observer active. Existing one-monitor and attempt checks are useful, but the recovery instructions needed to name this uncertainty. [Rerun state and reused outputs](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs).

**Decision: manual/skill follow-up implemented.** Record nonsecret owner/session handle, launch time, attempt and last observation. Reconnect first; confirm termination before replacement. Never kill an unknown process or infer ownership from a checkpoint. A tabletop resume test should cover a valid handle, ended monitor and ambiguous/reused PID.

## 17. Actionable alerts versus structured event protocols

**Question:** Are all jobs outside the three publication gates merely informational?

No. An upstream required job can fail before its aggregate gate reports failure. The current observer deduplicates alerts, sanitizes names, supplies job URLs/log commands and distinguishes failed steps from final job conclusions; it did not label the immediate classification. [Job/step API](https://docs.github.com/en/rest/actions/workflow-jobs#list-jobs-for-a-workflow-run).

**Decision: implemented explicit `publication gate`/`other job` alert labels.** Keep original exit semantics. Existing fake gate-step and non-gate failure scenarios now assert those classifications. Defer a versioned JSONL interface until an actual consumer needs it; human text is not an undocumented machine protocol.

## 18. Reusing evidence by actual inputs

**Question:** When can an unchanged result be reused after another edit?

A cache key or path match does not establish the check's transitive inputs. Full commit equality can be unnecessarily strict for a reviewed metadata-only local comparison; matching filenames alone is too weak. Existing source-bound export inputs and final required coverage remain valuable. [Cache semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).

**Decision: add a lightweight per-check reuse record.** Preserve command, source/dirty state, data/tool/engine configuration, host and evidence identity; explain unchanged-input scope on resume. A plain unrelated guide edit and a project-version change need different decisions: the latter affects D11g. Do not create automatic path-only test skipping or replace final required CI with old local evidence.

## 19. Godot import reuse and D11g renewal

**Question:** Can a reused import cache eliminate the candidate import?

No. Godot stores imported resources in `.godot/imported`, but that is not a cross-platform/version compatibility guarantee. The retained v0.2.8 Linux pair took 542.238301 s for the clean baseline and 262.959797 s for the reused-cache candidate; warning counts differed and no controlled clean candidate was measured. This ordered pair cannot establish a cache-caused speedup. [Godot import process](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/import_process.html), [retained renewal evidence](../../aero-consistency/D11g/2026-11-14-release-v028-qualification.json).

**Decision: preserve sequential checked imports and drift checks.** Reuse only compatible imported-resource copies with relevant asset/import identity reviewed; do not share writable caches or copy class/extension metadata blindly. An isolated matched cold/warm experiment must include copy cost, warnings/errors, inventories and derivation/control results before a performance claim. No new import was run for this research.

## 20. Time, memory, interruption and subprocess cleanup

**Question:** Is a timeout a strict memory or descendant-process bound?

No. Python `communicate()` captures output in memory; `run(timeout=...)` controls its direct child and process creation can delay timeout delivery. The watcher uses no shell, disables prompts, caps request time by a monotonic deadline and redacts stderr, but raw subprocess output is not byte-capped. No production overflow or leaked child was observed. [Python subprocess behavior](https://docs.python.org/3.11/library/subprocess.html#subprocess.Popen.communicate), [monotonic clock](https://docs.python.org/3.11/library/time.html#time.monotonic).

**Decision: document the precise bound; defer stream/process-tree hardening to a focused fixture.** A future concurrent-drain implementation needs oversized stdout/stderr, stall, interruption and secret-output cases on Windows/Linux. A post-read length check is not a memory limit. Stopping observation must never imply cancellation of the remote CI run or authorize killing an unknown process.

## Implemented follow-up and verification

- HTTP-aware waits, finite retries and sanitized failures: **21 offline watcher tests passed** on native Windows; read-only observation of completed v0.2.7 run `43328373987` also passed with the header-aware client. Review controls cover malformed/oversized server waits, missing quota reset, forced CLI color and explicit gate labels.
- Exact bounded checksum comparison: **28 manifest tests and 11 publication tests passed** on Linux/WSL. The oversized-checksum case enforces a byte budget before an unbounded read; its final small fixture avoids sparse-file allocation assumptions. Fixtures do not export or publish a real simulator package.
- Skill/manual now distinguish process ownership, observed/producing attempts, evidence reuse, alert categories and resource-bound limits. The active v0.2.8 observer remains its already-loaded candidate version; no live reload or tag change was performed.

Deferred items above are proposals with discriminating checks, not completed gates. In particular, there is no measured ETag/token/CI saving, authenticated provenance, universal archive-safety result, strict watcher memory/process-tree bound or new platform qualification.
