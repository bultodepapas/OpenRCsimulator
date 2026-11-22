"""Reproduce an accepted integral JSON number blocking the entire daily rollup.

Only temporary synthetic databases and Starlette's in-process client are used.
"""
import argparse
import json
from pathlib import Path
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    sys.path.insert(0, str(args.repo.resolve() / "services/telemetry"))
    from starlette.testclient import TestClient
    from openrc_telemetry.contract import ContractError, load_contracts
    from openrc_telemetry.ingress import create_app
    from openrc_telemetry.rollup import run_rollup
    from tests.support import FakeClock, batch, encode, make_config, unix

    receipt = unix("2026-11-20T12:00:00Z")
    with tempfile.TemporaryDirectory(prefix="openrc-audit-float-") as directory:
        config = make_config(directory)
        app = create_app(config, clock=FakeClock(receipt))
        statuses = []
        poison = batch(session=99)
        poison["events"][0]["interval_count"] = 1800.0
        with TestClient(app) as client:
            for number in range(1, 21):
                statuses.append(client.post("/v1/batches", content=encode(batch(number)),
                                           headers={"Content-Type": "application/json"}).status_code)
            poison_status = client.post("/v1/batches", content=encode(poison),
                                        headers={"Content-Type": "application/json"}).status_code
        error = None
        try:
            run_rollup(load_contracts(config.schema_dir), app.state.raw, app.state.aggregates,
                       "2026-11-20", unix("2026-11-21T02:00:00Z"), config.releases)
        except ContractError as exc:
            error = str(exc)
        result = {"healthy_batches": len(statuses), "healthy_http_statuses": sorted(set(statuses)),
                  "poison_http_status": poison_status, "poison_change": "interval_count: 1800.0",
                  "stored_batches": app.state.raw.count(), "rollup_error": error,
                  "daily_statuses": app.state.aggregates.day_statuses("2026-11-20"),
                  "rollup_commits": app.state.aggregates.rollup_commits()}
        app.state.raw.close()
        app.state.aggregates.close()
    print(json.dumps(result, indent=2, sort_keys=True))
    assert result["healthy_http_statuses"] == [202]
    assert poison_status == 202 and error == "insight_cell"
    assert not result["daily_statuses"] and not result["rollup_commits"]


if __name__ == "__main__":
    main()
