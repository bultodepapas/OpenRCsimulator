"""Reproduce pool recovery falsely reporting no dispatch for a running local job.

Run from the repository root with PYTHONPATH including the repository, private
TEMP/TMP/TMPDIR and PYTHONDONTWRITEBYTECODE=1. Uses WorkerFixture's temporary
Git checkout, SQLite authority and a task-owned fake Python process: no Godot,
SSH, external host, or default authority. The platform label is mocked as
Windows to exercise the pool's local Windows request on the current OS; this
does not qualify Windows containment.
"""
import json
from unittest import mock

from tools.testqueue import snapshots
from tools.testqueue.pool import Pool
from tools.testqueue.test_worker import WorkerFixture, _ADAPTER, wait_until


fixture = WorkerFixture(methodName="runTest")
fixture.setUp()
try:
    # Pool hard-codes owner=automatic-pool. Make only the private fixture
    # adapter wait long enough to inspect the actual live owned fake process.
    original = 'elif owner.startswith("long"):'
    assert original in _ADAPTER
    fixture._write("tools/testqueue/adapter.py", _ADAPTER.replace(
        original, 'elif owner.startswith(("long", "automatic-pool")):'))
    fixture.snapshot = fixture.base / "long-snapshot"
    snapshots.capture(fixture.repo, fixture.snapshot, scope=("app", "tools"))

    config = fixture.base / "private-pool.json"
    config.write_text(json.dumps({"state_root": str(fixture.base / "pool"),
                                  "hosts": [{"id": "windows", "local": True}]}), encoding="utf-8")
    pool = Pool(config)
    calls = []
    accepted = []

    def local_fixture_rpc(operation, **payload):
        calls.append(operation)
        try:
            result = fixture._call(operation, **payload)
        except Exception as error:
            # The real JSON-RPC client surfaces a worker error response as
            # ValueError; a missing manifest is FileNotFoundError in-process.
            raise ValueError(str(error)) from error
        if operation == "submit" and not accepted:
            accepted.append(result)
            fixture.handles.append(result)  # fixture cleanup owns cancellation
            def started():
                status = fixture._status(result["job"])
                if status["state"] != "RUNNING" or not status["attempts"]:
                    return False
                directory = fixture.worker.root / "attempts" / status["attempts"][-1]["id"]
                return (directory / "started.json").is_file()
            wait_until(started, timeout=10)
            raise RuntimeError("injected lost acceptance acknowledgement")
        return result

    with mock.patch("tools.testqueue.pool.rpc", side_effect=local_fixture_rpc), \
         mock.patch.object(pool, "probe", return_value=[]), \
         mock.patch("tools.testqueue.pool.plan", return_value={"selected": "windows"}), \
         mock.patch("tools.testqueue.worker.platform.system", return_value="Windows"):
        submitted = pool.submit(fixture.snapshot, "res://tests/test_fixture.gd",
                                timeout=40, request_id="localrecoveryfixture")
        receipt_path = pool.root / "jobs" / "localrecoveryfixture.json"
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        assert submitted["state"] == receipt["state"] == "SUBMISSION_UNCONFIRMED", receipt
        assert len(accepted) == 1
        request = receipt["request"]
        actual = fixture._call("recover", request_id=request["request_id"],
                               request_secret=request["request_secret"])
        assert all(actual[key] == accepted[0][key] for key in ("job", "handle"))
        live = fixture._status(actual["job"])
        assert live["state"] == "RUNNING", live
        attempt = live["attempts"][-1]["id"]
        with fixture.worker.lock:
            owned_process = fixture.worker.active[attempt]
            assert owned_process is not None and owned_process.alive()
            before_claims = fixture.worker.store.db.execute(
                "SELECT COUNT(*) FROM claims WHERE attempt=?", (attempt,)).fetchone()[0]
        assert before_claims > 0

        # The accepted process now runs from its isolated copy; remove only the
        # private frozen manifest to model an unavailable input during replay.
        (fixture.snapshot / "manifest.json").rename(fixture.snapshot / "manifest.unavailable")
        calls.clear()
        result = pool.recover("localrecoveryfixture")
        replay_calls = list(calls)
        saved = json.loads(receipt_path.read_text(encoding="utf-8"))
        assert replay_calls == ["submit"], replay_calls
        assert saved["state"] == "NOT_DISPATCHED", saved
        assert result["state"] == "FINISHED" and result["cleanup"] == "CONFIRMED", result
        assert result["outcome"] == "INFRA_FAILED", result

        calls.clear()
        pooled_status = pool.status("localrecoveryfixture")
        assert calls == [], calls  # cached NOT_DISPATCHED masks authority lookup
        assert pooled_status["state"] == "FINISHED" and pooled_status["cleanup"] == "CONFIRMED", pooled_status
        still_live = fixture._status(actual["job"])
        with fixture.worker.lock:
            running = fixture.worker.active[attempt]
            assert running is owned_process and running.alive()
            after_claims = fixture.worker.store.db.execute(
                "SELECT COUNT(*) FROM claims WHERE attempt=?", (attempt,)).fetchone()[0]
        assert still_live["state"] == "RUNNING" and after_claims == before_claims, still_live
        assert len(still_live["attempts"]) == 1

        print("initial pool state: SUBMISSION_UNCONFIRMED after accepted reply was lost")
        print(f"authority before and after replay: RUNNING; live owned fake process; claims={after_claims}; attempts=1")
        print(f"pool.recover RPC calls: {replay_calls}")
        print(f"pool.recover reported: {result['state']}, outcome={result['outcome']}, cleanup={result['cleanup']}; receipt={saved['state']}")
        print(f"subsequent pool.status: {pooled_status['state']}, cleanup={pooled_status['cleanup']}, RPC calls={calls}")

        # Explicitly stop only the handle created by this private fixture and
        # verify teardown before the fixture destroys its temporary authority.
        fixture._call("cancel", handle=actual["handle"])
        finished = fixture._finish(actual["job"], timeout=12)
        assert finished["state"] == "FINISHED" and finished.get("cleanup") == "CONFIRMED", finished
        print(f"owned fixture cleanup: {finished['state']}, outcome={finished['outcome']}, cleanup={finished['cleanup']}")
finally:
    fixture.doCleanups()
