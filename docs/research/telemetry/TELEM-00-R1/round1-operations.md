# Telemetry follow-up: first-wave operations F05–F07

Research evidence retained after lead review; no deployment, configuration or test performed. Sources accessed **2026-11-18**. Repository baseline supplied: `48ae3016a655acf7d062da3f32d72b9050c9e59a`. Contract: 202 follows durable commit of the complete batch and dedup receipt; raw records and dedup indexes expire within 48 hours of each receipt, including copies, backups and recoveries.

<a id="f05"></a>

## F05 — Vector: delivery and acknowledgements

**Question.** Can a Vector relay preserve the project's durable 202, bounded lifetime and privacy?

**Exact English queries.** `site:vector.dev/docs/architecture end-to-end acknowledgements HTTP server source acknowledgements buffering block drop_newest`; `site:github.com/vectordotdev/vector http source BatchStatus::Delivered Rejected Errored response status code acknowledgements`; `site:vector.dev/docs http sink response status code retry 429 409 acknowledgements partial delivery`; `site:github.com/vectordotdev/vector intentional drop filter acknowledgement delivered status source`.

**Primary sources/revision.** [Guarantees](https://vector.dev/docs/architecture/guarantees/), [buffering model](https://vector.dev/docs/architecture/buffering-model/), [HTTP source](https://vector.dev/docs/reference/configuration/sources/http_server/), [HTTP sink](https://vector.dev/docs/reference/configuration/sinks/http/), [HTTP handling source](https://github.com/vectordotdev/vector/blob/master/src/sources/util/http/prelude.rs), [issue #12217](https://github.com/vectordotdev/vector/issues/12217). Documentation and source `master` are moving; tagged-source retrieval failed. The issue appeared open on access. No release is selected or tested.

**Finding.** Vector documents that a durable sink buffer can acknowledge upon persistence to that buffer, before downstream delivery; intentional transform drops may also be considered delivered. Issue #12217 reports success for some other discarded events. Memory buffers lose in-flight data on crash; `block` propagates pressure and `drop_newest` drops. The HTTP sink documentation lists about 9.22 × 10^18 default retry attempts and a 60-second request timeout; its maximum retry delay is not a total event lifetime. HTTP source options can add remote IP, headers and query fields. The inspected moving HTTP source maps `Rejected` to generic 400 and `Errored` to 500, not necessarily the downstream status.

**Inference / change.** Retain the direct receiver; a generic Vector 202 is insufficient evidence of an atomic database commit. Any future relay needs a pinned, reviewed topology without premature disk-buffer/drop success, preserving batch bytes/identity and failure status, with explicit bounded retry age and no IP/header enrichment or raw logs. Disk buffers are additional copies subject to the same 48-hour maximum.

**Test / limit / lead.** In a disposable pinned deployment, pause or crash before/after DB commit and lose the response; retry identical/conflicting IDs concurrently, saturate buffers, deliberately drop, fail/fan out sinks, and check exact client statuses, persisted rows, age limits and synthetic IP/header/body canaries. A 202 before full commit fails. No topology has been executed; inspect its exact source and cancellation behavior if later selected.

<a id="f06"></a>

## F06 — NGINX: temp files and request logging

**Question.** What can persist telemetry or IPs despite disabling the access log?

**Exact English queries.** `site:nginx.org/en/docs nginx access_log off client_body_buffer_size client_body_in_file_only proxy_request_buffering`; `site:nginx.org nginx proxy_request_buffering client_body_temp_path access_log off request body error log`; `site:nginx.org error_log client request remote address request line examples logs error_log request client nginx`.

**Primary sources/revision.** Live, unversioned NGINX [core HTTP directives](https://nginx.org/en/docs/http/ngx_http_core_module.html#client_body_buffer_size), [proxy request buffering](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_request_buffering), [access log](https://nginx.org/en/docs/http/ngx_http_log_module.html#access_log), [developer logging guide](https://nginx.org/en/docs/dev/development_guide.html#log), [core error log](https://nginx.org/en/docs/ngx_core_module.html#error_log), and maintainer [issue #1344](https://trac.nginx.org/nginx/ticket/1344); deployment version unknown.

**Finding.** The documented default body buffer is 8 or 16 KiB, smaller than a valid 32 KiB batch; larger bodies may spill to temp files. `client_body_in_file_only on` leaves files after processing. Even with `proxy_request_buffering off`, chunked input is buffered unless proxied with HTTP/1.1 or HTTP/2; other module-dependent exceptions exist. `access_log off` does not disable the separate error log, whose HTTP context can include the client address and request line. Response buffering can also use temporary files.

**Inference / change.** If selected, inspect complete `nginx -T` including default servers, inherited locations and errors. Candidate controls: access log off, 32 KiB request limit, appropriately sized buffer, file-only mode off, explicit supported proxy protocol and request buffering off. These reduce likely spills but do not prove none. Put every possible temp path on a bounded verified nonpersistent mount, accounting for swap, snapshots and dumps; separately prevent error logs from persisting sensitive context. Inventory the load balancer, WAF, application, stderr/journal, containers and APM. Bound total concurrency.

**Test / limit / lead.** With synthetic body, IP, header and request-line canaries, test 32 KiB and 32 KiB + 1, chunked and Content-Length, malformed requests, disconnects, upstream errors, timeouts and restart. Inspect temp paths, each log destination and provider backups during and after; verify response limits. No deployment was tested; canary absence alone cannot prove all copies absent.

<a id="f07"></a>

## F07 — PostgreSQL: expiry and recoverable copies

**Question.** How can a small pilot preserve global dedup uniqueness while meeting the hard per-record 48-hour maximum across live and recoverable data?

**Exact English queries.** `site:postgresql.org/docs/current partitioning drop partition retention delete vacuum PITR backup old archive`; `site:postgresql.org/docs/18 unlogged table not crash safe truncated WAL replicated standby`; `site:postgresql.org/docs/18 WAL recycling wal_keep_size replication slots retained indefinite pg_wal max_slot_wal_keep_size`; `site:postgresql.org/docs/18 partitioned unique constraint must include all columns partition key`; `site:postgresql.org/docs/18 pg_basebackup entire database cluster individual databases tables`; `site:postgresql.org/docs/18 pg_archivecleanup not suitable backup WAL archive multiple standby`.

**Primary sources/revision.** PostgreSQL **18** manuals: [VACUUM](https://www.postgresql.org/docs/18/sql-vacuum.html), [partitioning](https://www.postgresql.org/docs/18/ddl-partitioning.html), [WAL configuration](https://www.postgresql.org/docs/18/wal-configuration.html), [replication configuration](https://www.postgresql.org/docs/18/runtime-config-replication.html), [PITR](https://www.postgresql.org/docs/18/continuous-archiving.html), [pg_basebackup](https://www.postgresql.org/docs/18/app-pgbasebackup.html), [pg_archivecleanup](https://www.postgresql.org/docs/18/pgarchivecleanup.html), [CREATE TABLE](https://www.postgresql.org/docs/18/sql-createtable.html), [asynchronous commit](https://www.postgresql.org/docs/18/wal-async-commit.html). No provider or minor version is selected.

**Finding.** `DELETE` leaves dead tuples until vacuum; ordinary vacuum typically reuses space rather than returning it to the OS. WAL may be recycled or retained by failing archiving or stalled replication slots. Physical base backups cover the whole cluster and, with archived WAL, can restore prior state. Partitioned unique constraints must include all partition-key columns: uniqueness by `(batch_id, receipt_bucket)` does **not** prohibit a duplicate batch in another bucket. Unlogged tables are not crash-safe; asynchronous commit may report success before WAL is durable. Neither satisfies the durable 202 contract.

**Inference / change.** For a modest pilot, consider ordinary unpartitioned logged tables with indexed per-record expiry, global unique `batch_id` and `(session_id, sequence)`, and a single receipt/event transaction. Schedule deletion with safety margin and monitor expiry, locks and replica lag; suspend new ingestion on risk and purge already-held data. Verify synchronous commit and storage durability. If partitioning becomes necessary, a separately protected global dedup registry needs transactional cross-bucket enforcement and its own expiry.

**Retention blocker.** SQL expiry does not prove forensic/physical erasure or make WAL, snapshots and backups unreadable. A snapshot at receipt +47 hours retained for 48 hours could preserve data for about 95 hours. Expire or render every raw-bearing copy irrecoverable by the *oldest contained receipt's* deadline, including recovery copies. Separating a database within the same cluster does not isolate physical backups/WAL. Raw-store isolation, aggregate-only backups and possible cryptographic erasure need provider-specific proof and an accepted erasure standard; none is yet a solution. Do not weaken the 48-hour promise.

**Test / limit / lead.** On a synthetic instance, race duplicates across clock/day boundaries; crash before/after commit; block purge, lag replication and fail archiving. Verify 202 and single contribution, actual expiry of live data and each backup/WAL/recovery copy, and that aggregate-only backups lack IDs. Restoration tests must not rely on query filtering to excuse a retained expired copy. No instance or provider was tested; investigate raw-store separation and backup/key lifetimes before release.
