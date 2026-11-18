# Telemetry follow-up: targeted operations F15–F17

Research evidence retained after lead review; all sources accessed **2026-11-18**. The first-ten checkpoint is `docs/research/telemetry/TELEM-00-R1/README.md`, starting commit `48ae3016a655acf7d062da3f32d72b9050c9e59a`. No database, service, backup or test was run. Proposed mechanisms require implementation and qualification; the 48-hour maximum and 202-after-durable-commit contract remain unchanged.

<a id="f15"></a>

## F15 — PostgreSQL: transaction and expiry races

**Question.** How can unpartitioned logged tables implement whole-batch idempotency under concurrent inserts and expiry?

**Exact English queries.** `site:postgresql.org/docs/18 transaction isolation read committed insert on conflict do nothing invisible unique concurrent returning`; `site:postgresql.org/docs/18 functions-datetime clock_timestamp now transaction start`.

**Primary sources/revision.** PostgreSQL 18: [INSERT](https://www.postgresql.org/docs/18/sql-insert.html), [transaction isolation](https://www.postgresql.org/docs/18/transaction-iso.html), [unique checks](https://www.postgresql.org/docs/18/index-unique-checks.html), [row locking](https://www.postgresql.org/docs/18/explicit-locking.html), [clock functions](https://www.postgresql.org/docs/18/functions-datetime.html), [asynchronous commit](https://www.postgresql.org/docs/18/wal-async-commit.html).

**Facts.** Unique indexes wait on conflicting uncommitted transactions. At `READ COMMITTED`, `ON CONFLICT DO NOTHING` can suppress insertion because of a concurrent row invisible to that statement's snapshot; `RETURNING` includes only inserted/updated rows. The next statement gets a fresh snapshot. `FOR SHARE` blocks update/delete while held; `now()` is fixed at transaction start whereas `clock_timestamp()` changes.

**Proposed specification, not verified SQL.** Validate the bounded body; digest its exact bytes and retain length. Use non-null, non-deferrable uniqueness for `batch_id` and `(session_id, sequence)`. In a bounded `READ COMMITTED` transaction, insert the immutable batch receipt using `ON CONFLICT (batch_id) DO NOTHING RETURNING`; expiry is based on first trusted receipt and never extended. If inserted, insert *all* events; overlapping event uniqueness rolls the entire transaction back and yields 409. Commit synchronously before 202. If no receipt returns, issue a **separate** `SELECT ... FOR SHARE`; once locked, check actual current time, then compare digest/length. End the transaction promptly: a matching unexpired receipt gets 202 without new events; a different digest gets 409. If cleanup removed the row, roll back and retry within a fixed budget. If expiry is reached or too near for safe completion, release locks and return retryable failure until cleanup. Bound lock/transaction times and give purge a safety margin. An uncertain commit gets retryable failure or a closed connection; retrying the same ID resolves it.

**Tests / limits.** Race two same-body requests, different bodies, overlapping sequences, purge/delete, deadline boundaries, lock timeouts, process death before/after commit and lost replies; assert one complete contribution, no partial rows and no early 202. Monitor clock skew and purge lag. Digest equality is a computational collision assumption, not literal proof of byte equality; resolve that distinction if the contract demands mathematical exactness. Locks, timeouts and SQL expiry do not establish deletion of physical copies.

<a id="f16"></a>

## F16 — pgBackRest: backup-chain retention

**Question.** Can pgBackRest retention or selected restore isolate raw telemetry from an aggregate backup while maintaining the deadline?

**Exact English queries.** `site:pgbackrest.org user guide backup retention full differential incremental expire restore backup chain`; `site:pgbackrest.org/configuration.html "repo-retention-full-type" "time" "expire"`; `site:pgbackrest.org configuration restore delta selective database exclude database zero files`; `site:pgbackrest.org/configuration.html "--db-exclude" "Restore excluding"`.

**Primary sources/revision.** [User guide](https://pgbackrest.org/user-guide.html), [configuration](https://pgbackrest.org/configuration.html), [command reference](https://pgbackrest.org/command.html), and [releases](https://pgbackrest.org/release.html). The accessed live guide's examples use pgBackRest 2.60.1 and PostgreSQL 17; no project deployment/version is selected.

**Facts.** Incremental backups expire with their full/differential parent; WAL needed for backup consistency remains until that backup expires. Count retention expires only after enough successful complete backups; time retention can retain an older full until another qualifying full exists. Automatic expiration follows a *successful* backup. Even explicit `--set` expiration must leave one full backup. `--db-exclude` is a **restore** option: it excludes selected databases from that restore, not from the original backup or shared WAL.

**Inference / plan change.** A pgBackRest count or day setting cannot by itself establish a 48-hour per-record maximum, including failed-backup periods. A candidate is separate raw and ID-free aggregate clusters, with backup only of the latter; alternatively, a tightly allowlisted aggregate-only logical export into a separate backup domain. Neither choice addresses the raw cluster's logged WAL, replicas, live volumes, snapshots, hidden provider copies or aggregate 180-day expiry. Define cross-store, idempotent rollup/recovery and required durability before adopting it. Avoid raw-bearing backup chains unless every readable copy and decryption key is proven gone or irrecoverable by the oldest possible contained record's deadline. SQL TTL, restore filtering and unlogged tables do not solve this. Raw-store isolation and any cryptographic-erasure standard remain unqualified release blockers.

**Tests / limits.** Using only synthetic data, test full/differential/incremental and WAL inventories, failed scheduled backups and expiration, versioned/object-locked storage, replica and snapshot copies, and each restore path before deadlines; remove synthetic restores before their own deadline. Verify aggregate backups cannot reconstruct raw IDs and examine every raw-bearing object or validated key-destruction evidence. A clean restored query is not physical-erasure proof. No provider, backup mechanism or cross-store transaction was tested.

<a id="f17"></a>

## F17 — Uvicorn, Starlette and FastAPI error paths

**Question.** What can leak rejected telemetry through application-server exceptions even when access logging is disabled?

**Exact English queries.** `site:uvicorn.org/settings "--access-log" logging disable server exception`; `site:github.com/encode/uvicorn "Exception in ASGI application" access_log response`; `site:fastapi.tiangolo.com RequestValidationError body log information validation errors exc.body input`; `site:starlette.io exceptions ServerErrorMiddleware debug traceback 500 response`; `site:docs.pydantic.dev latest errors error detail input input_value`.

**Primary sources/revision.** Live [Uvicorn logging](https://uvicorn.dev/concepts/logging/) and [settings](https://uvicorn.dev/settings/); moving `main` [h11](https://github.com/Kludex/uvicorn/blob/main/uvicorn/protocols/http/h11_impl.py) and [httptools](https://github.com/Kludex/uvicorn/blob/main/uvicorn/protocols/http/httptools_impl.py) source; moving FastAPI `master` [handler](https://github.com/fastapi/fastapi/blob/master/fastapi/exception_handlers.py), inspected through the indexed source rendering because direct open failed; [FastAPI error documentation](https://fastapi.tiangolo.com/tutorial/handling-errors/), [Pydantic error details](https://pydantic.dev/docs/validation/latest/errors/errors/) and [Starlette exception handling](https://www.starlette.io/exceptions/) (search rendering; direct open failed). Exact installed versions are unknown.

**Facts.** Uvicorn documents `--no-access-log` affects `uvicorn.access`, not `uvicorn.error`. Both inspected HTTP implementations log uncaught ASGI exceptions with `exc_info`. Starlette debug mode can return tracebacks; unexpected errors may propagate to the server. FastAPI exposes `RequestValidationError.body`; its inspected default validation handler returns `exc.errors()`. Pydantic documents that error details may include the rejected `input`.

**Inference / plan change.** Disable debug; implement fixed bounded error-category responses, including validation failures, rather than echoing `.body`, `.errors()`, exception reprs or arbitrary `HTTPException.detail`. Configure and verify error logger handlers and propagation before any persistent sink, replacing arbitrary exception text/tracebacks with safe fixed categories or nonpersistent handling; disabling access logs alone is insufficient. Review library, database-driver, service-manager, container and APM handlers too, and preserve useful aggregate failure counts. A custom 500 response by itself does not prove the re-raised exception is safe to log.

**Tests / limits.** Send unique synthetic canaries in invalid JSON, missing/extra fields, duplicate keys, malformed UTF-8, oversized bodies, paths and headers; induce validator, database, startup and post-response exceptions with canaries in exception messages, plus worker crashes. Inspect response, stdout/stderr, error handlers, parent process, journald/container logs and enabled collectors. Re-test exact pinned Uvicorn HTTP implementation and middleware stack; this is a proposal, not evidence that a production stack is clean.
