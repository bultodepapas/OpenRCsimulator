"""Isolated reproduction: execution timeout excludes stalled preparation.

Run from the repository root with PYTHONDONTWRITEBYTECODE=1 and TMPDIR set to an
empty private directory. This uses only fake-worker fixtures and starts no engine.
"""
import threading
import time
import uuid
from unittest import mock

from tools.testqueue import processes, worker
from tools.testqueue.test_worker import WorkerFixture

fixture = WorkerFixture(methodName="runTest")
fixture.setUp()
release = threading.Event()
thread = None
try:
    fixture.worker.draining = True
    accepted = fixture._call("submit", owner="stalled-copy", preset="checked",
        options={"headless": True, "timeout": 1, "script": "res://tests/test_fixture.gd", "workload": "functional"},
        source=str(fixture.repo), snapshot=str(fixture.snapshot),
        request_id=uuid.uuid4().hex, request_secret=uuid.uuid4().hex)
    fixture.handles.append(accepted)
    attempt = fixture.worker.store.allocate(accepted["job"], accepted["scheduling"]["resources"], fixture.worker.capacities,
        {"process": processes.host_identity()})
    entered = threading.Event()
    original_copytree = worker.shutil.copytree
    def blocked_copy(*args, **kwargs):
        entered.set()
        if not release.wait(5):
            raise TimeoutError("fixture release missing")
        return original_copytree(*args, **kwargs)
    with mock.patch.object(worker.shutil, "copytree", side_effect=blocked_copy), \
         mock.patch.object(processes.OwnedProcess, "start", side_effect=AssertionError("unexpected process start")) as start:
        began = time.monotonic()
        thread = threading.Thread(target=fixture.worker.execute, args=(accepted["job"], attempt))
        thread.start()
        assert entered.wait(3)
        time.sleep(1.2)
        fixture._call("cancel", handle=accepted["handle"])
        status = fixture._status(accepted["job"])
        claim_count = fixture.worker.store.db.execute("SELECT COUNT(*) FROM claims WHERE attempt=?", (attempt,)).fetchone()[0]
        assert status["state"] == "DISPATCHING" and status["canceled"] == 1, status
        assert claim_count > 0 and thread.is_alive() and start.call_count == 0
        print(f"elapsed after allocation: {time.monotonic() - began:.2f}s; configured execution timeout: 1s")
        print(f"while copy blocked: state={status['state']}, canceled={status['canceled']}, claims={claim_count}, starts={start.call_count}")
        release.set()
        thread.join(timeout=5)
        assert not thread.is_alive()
        final = fixture._status(accepted["job"])
        assert final["state"] == "FINISHED" and final["outcome"] == "CANCELED" and final["cleanup"] == "CONFIRMED", final
        assert start.call_count == 0
        print(f"after copy resumes: state={final['state']}, outcome={final['outcome']}, cleanup={final['cleanup']}, starts={start.call_count}")
finally:
    release.set()
    if thread is not None:
        thread.join(timeout=5)
    fixture.doCleanups()
