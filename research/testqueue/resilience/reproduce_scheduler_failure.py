"""Isolated reproduction: failure to persist a scheduler error stops dispatch.

Run from the repository root with PYTHONDONTWRITEBYTECODE=1 and TMPDIR set to an
empty private directory. This uses only fake-worker fixtures and starts no engine.
"""
import sqlite3
import threading
import time
from unittest import mock

from tools.testqueue.test_worker import WorkerFixture

fixture = WorkerFixture(methodName="runTest")
fixture.setUp()
try:
    fixture.worker.stopping.set()
    fixture.scheduler.join(timeout=3)
    assert not fixture.scheduler.is_alive()
    fixture.worker.draining = True
    accepted = fixture._submit("queue-after-scheduler-failure")
    fixture.worker.draining = False
    fixture.worker.stopping.clear()
    errors = []
    def supervised_for_observation():
        try:
            fixture.worker.schedule()
        except Exception as error:
            errors.append(error)
    with mock.patch.object(fixture.worker, "schedule_once", side_effect=sqlite3.OperationalError("injected storage failure")), \
         mock.patch.object(fixture.worker.store, "event", side_effect=sqlite3.OperationalError("injected logging failure")):
        scheduler = threading.Thread(target=supervised_for_observation)
        scheduler.start()
        scheduler.join(timeout=2)
        assert not scheduler.is_alive() and len(errors) == 1
    time.sleep(0.3)
    hosts = fixture._call("hosts")
    status = fixture._status(accepted["job"])
    assert hosts["condition"] == "READY", hosts
    assert status["state"] == "QUEUED" and not fixture.worker.stopping.is_set(), status
    print(f"scheduler alive after logging failure: {scheduler.is_alive()}")
    print(f"unhandled scheduler error: {errors[0]}")
    print(f"after fault cleared: host={hosts['condition']}, job={status['state']}, stopping={fixture.worker.stopping.is_set()}")
finally:
    fixture.doCleanups()
