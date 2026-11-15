"""Private no-workload audit reproductions (not desired-behavior regression tests) (2026-11-15)."""
import json
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

from tools.testqueue.pool import Pool
from tools.testqueue.pool_batch import run_batch
from tools.testqueue import remote_agent

with tempfile.TemporaryDirectory(prefix="openrc-audit-pool-") as temp:
    root = Path(temp)
    cfg = root / "config.json"
    cfg.write_text(json.dumps({"state_root": str(root / "pool"), "hosts": []}))
    snapshot = root / "snapshot"
    snapshot.mkdir()
    # A readable but invalid snapshot is a concrete pre-dispatch refusal.
    (snapshot / "manifest.json").write_text('{"source_digest":"fixture"}')
    manifest = root / "batch-manifest.json"
    manifest.write_text(json.dumps({"snapshot": str(snapshot), "jobs": [{"script": "res://tests/test_sample.gd"}]}))
    state_path = root / "batch-state.json"
    pool = Pool(cfg)
    first = run_batch(pool, cfg, manifest, state_path, timeout=1, poll_interval=0)
    row1 = first["jobs"][0]
    identifier = row1["request_id"]
    assert first["result"] == "INCOMPLETE" and row1["phase"] == "BLOCKED", first
    assert "invalid snapshot" in row1["status"]["error"], row1
    assert not (pool.root / "jobs" / (identifier + ".json")).exists()
    second = run_batch(pool, cfg, manifest, state_path, timeout=1, poll_interval=0)
    row2 = second["jobs"][0]
    assert second["result"] == "INCOMPLETE" and row2["phase"] == "BLOCKED", second
    assert "No such file" in row2["status"]["error"], row2
    print("PRE_RECEIPT: invalid snapshot -> BLOCKED/UNKNOWN; receipt absent -> resume BLOCKED/UNKNOWN on missing receipt, still INCOMPLETE")

with tempfile.TemporaryDirectory(prefix="openrc-audit-ident-") as temp:
    base = Path(temp)
    roots = [base / "aliasA", base / "aliasB"]
    requests = []
    for index, root in enumerate(roots):
        (root / "incoming").mkdir(parents=True)
        (root / "jobs").mkdir()
        archive = root / "incoming" / "source.tar"
        archive.write_bytes(b"not executed fixture")
        requests.append({"request_id": f"job{index}", "preset": "checked",
                         "archive": {"path": str(archive), "sha256": remote_agent.digest(archive)},
                         "engine_path": sys.executable,
                         "options": {"script": "res://tests/test_sample.gd", "timeout": 90}})
    # Popen is replaced so no runner, engine, network or job starts.
    with patch.object(remote_agent, "authority_enrolled", return_value=False), \
         patch.object(remote_agent.subprocess, "Popen") as spawn:
        first = remote_agent.launch(roots[0], requests[0])
        try:
            another = dict(requests[0], request_id="same-root-other")
            remote_agent.launch(roots[0], another)
            raise AssertionError("same root should have refused")
        except remote_agent.Refused as exc:
            assert exc.code == "QUARANTINED", (exc.code, str(exc))
        second = remote_agent.launch(roots[1], requests[1])
    assert first["state"] == second["state"] == "STARTING"
    assert spawn.call_count == 2
    print("PHYSICAL_HOST: same-root second request quarantined; different roots on same process/machine both accepted STARTING (fake Popen, no workloads)")

with tempfile.TemporaryDirectory(prefix="openrc-audit-transient-") as temp:
    root = Path(temp)
    config = root / "config.json"
    config.write_text(json.dumps({"state_root": str(root / "pool"), "hosts": [{"id": "windows", "local": True}]}))
    snapshot = root / "snapshot"
    snapshot.mkdir()
    (snapshot / "manifest.json").write_text(json.dumps({"source_digest": "fixture", "files": {}, "source_root": str(root)}))
    manifest = root / "manifest.json"
    manifest.write_text(json.dumps({"snapshot": str(snapshot), "jobs": [{"script": "res://tests/test_sample.gd"}]}))
    state_path = root / "state.json"
    pool = Pool(config)
    from tools.testqueue import pool as pool_module
    original_acquire = pool_module.acquire_lock
    def one_dispatch_failure(path, timeout=60):
        if path.name == "dispatch.lock":
            raise RuntimeError("Timed out waiting for pool transaction lock")
        return original_acquire(path, timeout)
    # Only the dispatch lock is fault-injected; no host/network/engine is used.
    with patch.object(pool_module, "verify", return_value={"ok": True}), \
         patch.object(pool_module, "acquire_lock", side_effect=one_dispatch_failure):
        first = run_batch(pool, config, manifest, state_path, timeout=1, poll_interval=0)
    row = first["jobs"][0]
    identifier = row["request_id"]
    assert first["result"] == "INCOMPLETE" and row["phase"] == "BLOCKED"
    assert "transaction lock" in row["status"]["error"]
    assert not (pool.root / "jobs" / (identifier + ".json")).exists()
    # Fault cleared. Resume never even retries submit; status only finds no receipt.
    with patch.object(pool, "submit", wraps=pool.submit) as resumed_submit:
        second = run_batch(pool, config, manifest, state_path, timeout=1, poll_interval=0)
        assert resumed_submit.call_count == 0
    assert second["jobs"][0]["phase"] == "BLOCKED" and second["result"] == "INCOMPLETE"
    # A controlled direct repeat of the same ID now reaches the healthy fake authority.
    with patch.object(pool_module, "verify", return_value={"ok": True}), \
         patch.object(pool, "probe", return_value=[]), \
         patch.object(pool_module, "plan", return_value={"selected": "windows"}), \
         patch.object(pool_module, "rpc", return_value={"job": "fake-authority-accepted"}):
        direct = pool.submit(snapshot, "res://tests/test_sample.gd", request_id=identifier)
    assert direct["state"] == "SUBMITTED", direct
    print("TRANSIENT: injected dispatch-lock timeout before receipt -> BLOCKED; fault removed -> resume makes zero submissions and remains INCOMPLETE; direct same-ID retry reaches fake authority")

with tempfile.TemporaryDirectory(prefix="openrc-audit-budget-") as temp:
    import time
    root = Path(temp)
    config = root / "config.json"
    config.write_text('{}')
    snapshot = root / "snapshot"
    snapshot.mkdir()
    (snapshot / "manifest.json").write_text('{}')
    manifest = root / "manifest.json"
    manifest.write_text(json.dumps({"snapshot": str(snapshot), "jobs": [{"script": "res://tests/test_sample.gd"}]}))
    class SlowWaitingPool:
        def submit(self, *args, **kwargs):
            time.sleep(0.08)
            return {"state": "WAITING", "decision": {"selected": None}}
    started = time.monotonic()
    state = run_batch(SlowWaitingPool(), config, manifest, root / "state.json", timeout=0.01, poll_interval=0)
    elapsed = time.monotonic() - started
    assert state["result"] == "INCOMPLETE" and elapsed >= 0.07, (state, elapsed)
    print(f"OBSERVER_BUDGET: timeout=0.01s returned after {elapsed:.3f}s when one mocked submit took 0.08s; no remote work")

from tools.testqueue import pool_mcp, presets
markers = ["done"] * 129
accepted = pool_mcp._jobs([{"script": "res://tests/test_sample.gd", "require": markers, "platform": "any"}])
options = presets.validate("checked", {"script": accepted[0]["script"], "require": markers, "timeout": 90, "headless": True, "workload": "auto", "settings": {}})
request = {"request_id": "badmarkers", "preset": "checked", "archive": {"path": sys.executable, "sha256": "0" * 64}, "engine_path": sys.executable, "options": options}
try:
    remote_agent.validate_request(request)
    raise AssertionError("remote agent should reject 129 markers")
except remote_agent.Refused as exc:
    assert exc.code == "INVALID" and "markers" in str(exc)
print("PROTOCOL_VALIDATION: MCP/local validation accepts 129 markers, remote validation rejects INVALID before dispatch; no SSH or remote workload")
