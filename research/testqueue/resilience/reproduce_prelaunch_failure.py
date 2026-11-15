"""Isolated reproduction: failure to open the pre-spawn log quarantines the host.

Run from the repository root with PYTHONDONTWRITEBYTECODE=1 and TMPDIR set to an
empty private directory. This uses only fake-worker fixtures and starts no engine.
"""
from pathlib import Path
from unittest import mock

from tools.testqueue import processes
from tools.testqueue.test_worker import WorkerFixture

fixture = WorkerFixture(methodName="runTest")
fixture.setUp()
try:
    fixture.worker.draining = True
    first = fixture._submit("prelaunch-log-failure")
    policy = first["scheduling"]["resources"]
    attempt = fixture.worker.store.allocate(first["job"], policy, fixture.worker.capacities,
        {"process": processes.host_identity()})
    original_open = Path.open
    def inject_log_open_failure(path, *args, **kwargs):
        if path.name == "worker.log":
            raise PermissionError("injected pre-spawn log denial")
        return original_open(path, *args, **kwargs)
    with mock.patch.object(Path, "open", new=inject_log_open_failure), \
         mock.patch("tools.testqueue.processes.subprocess.Popen", side_effect=AssertionError("unexpected process creation")) as popen:
        fixture.worker.execute(first["job"], attempt)
    assert popen.call_count == 0
    status = fixture._status(first["job"])
    assert status["state"] == "UNKNOWN", status
    assert "injected pre-spawn log denial" in status["error"], status
    assert status["cleanup"] == "UNCONFIRMED", status
    claim_count = fixture.worker.store.db.execute("SELECT COUNT(*) FROM claims WHERE attempt=?", (attempt,)).fetchone()[0]
    assert claim_count > 0
    second = fixture._submit("blocked-after-prelaunch-failure", headless=True)
    next_attempt = fixture.worker.store.allocate(second["job"], second["scheduling"]["resources"], fixture.worker.capacities)
    assert next_attempt is None
    blocked = fixture._status(second["job"])
    assert blocked["state"] == "QUEUED" and "unresolved cleanup" in blocked["reason"], blocked
    try:
        fixture._call("reconcile", handle=first["handle"])
    except ValueError as error:
        assert "cannot be proved" in str(error), error
        reconcile = str(error)
    else:
        raise AssertionError("same-boot reconciliation unexpectedly released the claim")
    print(f"Popen calls: {popen.call_count}")
    print(f"first state: {status['state']}; cleanup: {status['cleanup']}; claims: {claim_count}")
    print(f"error: {status['error']}")
    print(f"same-boot reconcile: {reconcile}")
    print(f"second state: {blocked['state']}; reason: {blocked['reason']}")
finally:
    fixture.doCleanups()
