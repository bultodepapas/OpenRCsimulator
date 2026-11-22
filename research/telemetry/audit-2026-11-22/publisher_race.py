"""Two local publishers share a synthetic pending intent; the GitHub client is an in-process fake."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Barrier, Lock
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'services/telemetry'))
from openrc_telemetry.config import DEFAULT_SCHEMA_DIR
from openrc_telemetry.contract import load_contracts
from openrc_telemetry.publisher import publish
from openrc_telemetry.report import material, report_key
from openrc_telemetry.storage import AggStore

class FakeGitHub:
    def __init__(self):
        self.barrier, self.lock, self.created = Barrier(2), Lock(), []
    def list_issues(self, repo):
        self.barrier.wait(timeout=10)
        return [], True
    def create_issue(self, repo, title, body, label):
        with self.lock:
            issue = {'number': len(self.created) + 1, 'user': {'login': 'test-bot'}, 'title': title, 'body': body}
            self.created.append(issue)
            return 'created', issue

with TemporaryDirectory() as tmp:
    path = Path(tmp) / 'aggregates.sqlite'
    first, second = AggStore(path), AggStore(path)
    contracts = load_contracts(DEFAULT_SCHEMA_DIR)
    week, release, repo, now = '2026-W01', 'v0.3.0', 'example/private', 1768867200
    title, body, digest = material(contracts, first, week, release)
    # A durable pending intent can be left by a prior incomplete discovery or crash.
    first.create_publication(repo, report_key(week, release), digest, title, body, 'test-bot', now)
    fake = FakeGitHub()
    def run(agg):
        return publish(agg, contracts, week=week, release=release, repository=repo, approved_digest=digest,
                       execute=True, now=now, releases={release}, bot_author='test-bot', github=fake)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(run, (first, second)))
    print('outcomes:', [(r.outcome, r.issue_number) for r in results])
    print('created:', len(fake.created))
    print('final intent:', first.get_publication(repo, report_key(week, release))['issue_number'])
    assert len(fake.created) == 2 and all(r.outcome == 'published' for r in results)
    first.close()
    second.close()
