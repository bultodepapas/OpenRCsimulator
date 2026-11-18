"""Synthetic protocol tests: publication history, ambiguity and comparability."""
from copy import deepcopy
import unittest

from generate_examples import cohort, example
from publication import Approval, Policy, PublicationModel, RemoteIssue, material
from reference import ContractError, FrameWindow, aggregate_daily_gpu, encode


def report(count=20):
    return aggregate_daily_gpu([("2026-11-17", body) for body in cohort(count)],
                               "2026-11-17", "v0.2.7", as_of_utc="2026-11-18T01:00:00Z")


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.model = PublicationModel()
        self.report = report()
        self.releases = frozenset({"v0.2.7"})
        self.policy = Policy("example/private-telemetry", "report-bot[bot]", self.releases)

    def prepare(self, value=None, policy=None, approval=None):
        value = value or self.report
        return self.model.prepare(value, policy or self.policy,
                                  as_of_utc="2026-11-18T01:00:00Z",
                                  expected_key=f"daily-gpu-v1/{value['day']}/{value['release_id']}",
                                  approval=approval)

    def issue(self, decision, number=42, **changes):
        fields = dict(repository=self.policy.repository, number=number,
                      author=self.policy.bot_author, body=decision.body, is_pull_request=False)
        fields.update(changes)
        return RemoteIssue(**fields)

    def test_first_intent_is_created_once(self):
        self.assertEqual(self.prepare().action, "create")
        self.assertEqual(self.prepare().action, "reconcile")
        self.assertEqual(len(self.model.entries), 1)

    def test_success_then_same_digest_is_noop(self):
        intent = self.prepare()
        self.assertTrue(self.model.confirmed(self.policy.repository, intent.key, intent.token, self.issue(intent)))
        self.assertEqual(self.prepare().action, "noop")
        self.assertEqual(self.prepare().issue_number, 42)

    def test_lost_response_never_blindly_recreates(self):
        intent = self.prepare()
        self.assertTrue(self.model.uncertain(self.policy.repository, intent.key, intent.token))
        for _ in range(3):
            self.assertEqual(self.prepare().action, "reconcile")
            result = self.model.reconcile(self.policy.repository, intent.key, [], discovery_complete=True)
            self.assertEqual(result.action, "reconcile")

    def test_unique_verified_candidate_resolves_ambiguity(self):
        intent = self.prepare()
        self.model.uncertain(self.policy.repository, intent.key, intent.token)
        result = self.model.reconcile(self.policy.repository, intent.key, [self.issue(intent)], discovery_complete=True)
        self.assertEqual((result.action, result.issue_number), ("noop", 42))

    def test_incomplete_discovery_cannot_bind(self):
        intent = self.prepare()
        result = self.model.reconcile(self.policy.repository, intent.key, [self.issue(intent)], discovery_complete=False)
        self.assertEqual(result.action, "reconcile")

    def test_multiple_valid_candidates_need_review(self):
        intent = self.prepare()
        result = self.model.reconcile(self.policy.repository, intent.key,
                                      [self.issue(intent, 42), self.issue(intent, 43)], discovery_complete=True)
        self.assertEqual(result.action, "review_required")
        self.assertEqual(self.prepare().action, "review_required")

    def test_marker_alone_cannot_authorize_binding(self):
        intent = self.prepare()
        for changes in [dict(repository="attacker/other"), dict(author="some-user"),
                        dict(body=intent.body + "extra unreviewed text"),
                        dict(is_pull_request=True), dict(is_pull_request=None),
                        dict(is_pull_request=0), dict(is_pull_request=""), dict(number=True)]:
            issue = self.issue(intent, **changes)
            self.assertFalse(self.model.confirmed(self.policy.repository, intent.key, intent.token, issue))
            result = self.model.reconcile(self.policy.repository, intent.key, [issue], discovery_complete=True)
            self.assertEqual(result.action, "reconcile")

    def test_stale_attempt_cannot_bind(self):
        intent = self.prepare()
        self.assertFalse(self.model.confirmed(self.policy.repository, intent.key, intent.token + 1, self.issue(intent)))
        self.assertFalse(self.model.uncertain(self.policy.repository, intent.key, intent.token + 1))

    def test_changed_snapshot_needs_review_even_when_only_count_changes(self):
        self.prepare()
        self.assertEqual(self.prepare(report(21)).action, "review_required")

    def test_changed_status_is_a_new_disclosure(self):
        first = report(19)
        self.assertEqual(first["status"], "suppressed")
        self.assertEqual(self.prepare(first).action, "create")
        self.assertEqual(self.prepare().action, "review_required")

    def test_policy_change_cannot_reuse_previous_intent(self):
        self.prepare()
        changed = Policy(self.policy.repository, self.policy.bot_author, self.releases, "public")
        self.assertEqual(self.prepare(policy=changed).action, "review_required")

    def test_public_output_requires_digest_and_inventory_bound_receipt(self):
        public = Policy("example/public-telemetry", "report-bot[bot]", self.releases, "public")
        key, _, digest = material(self.report)
        self.assertEqual(self.prepare(policy=public).action, "review_required")
        wrong = Approval(key, public.repository, "0" * 64, "1" * 64)
        self.assertEqual(self.prepare(policy=public, approval=wrong).action, "review_required")
        valid = Approval(key, public.repository, digest, self.model.inventory_digest())
        self.assertEqual(self.prepare(policy=public, approval=valid).action, "create")

    def test_repository_casing_cannot_create_a_second_intent(self):
        mixed = Policy("Example/Private-Telemetry", self.policy.bot_author, self.releases)
        intent = self.prepare(policy=mixed)
        self.assertEqual(self.prepare().action, "reconcile")
        remote = self.issue(intent, repository="EXAMPLE/PRIVATE-TELEMETRY")
        self.assertTrue(self.model.confirmed("EXAMPLE/PRIVATE-TELEMETRY", intent.key, intent.token, remote))
        self.assertEqual(len(self.model.entries), 1)

    def test_stale_public_inventory_approval_cannot_compete_with_pending_intent(self):
        public = Policy("example/public-telemetry", "report-bot[bot]", self.releases, "public")
        other = deepcopy(self.report)
        other["day"] = "2026-11-16"
        first_key, _, first_digest = material(self.report)
        second_key, _, second_digest = material(other)
        old_inventory = self.model.inventory_digest()
        first = Approval(first_key, public.repository, first_digest, old_inventory)
        second = Approval(second_key, public.repository, second_digest, old_inventory)
        intent = self.prepare(policy=public, approval=first)
        self.assertEqual(intent.action, "create")
        self.assertEqual(self.prepare(other, public, second).action, "review_required")
        self.model.uncertain(public.repository, intent.key, intent.token)
        self.assertEqual(self.prepare(other, public, second).action, "review_required")
        renewed = Approval(second_key, public.repository, second_digest, self.model.inventory_digest())
        self.assertEqual(self.prepare(other, public, renewed).action, "create")

    def test_published_remote_edit_deletion_or_duplicate_requires_review(self):
        for bad_case in ["missing", "edited", "wrong_author", "duplicate"]:
            self.model = PublicationModel()
            intent = self.prepare()
            self.model.confirmed(self.policy.repository, intent.key, intent.token, self.issue(intent))
            candidates = {"missing": [], "edited": [self.issue(intent, body="edited")],
                          "wrong_author": [self.issue(intent, author="wrong")],
                          "duplicate": [self.issue(intent), self.issue(intent, 43)]}[bad_case]
            result = self.model.reconcile(self.policy.repository, intent.key, candidates, discovery_complete=True)
            self.assertEqual(result.action, "review_required")
            self.assertEqual(self.prepare().action, "review_required")

    def test_conflict_is_sticky_against_late_success_or_smaller_candidate_set(self):
        intent = self.prepare()
        result = self.model.reconcile(self.policy.repository, intent.key,
                                      [self.issue(intent), self.issue(intent, 43)], discovery_complete=True)
        self.assertEqual(result.action, "review_required")
        self.assertFalse(self.model.confirmed(self.policy.repository, intent.key, intent.token, self.issue(intent)))
        self.assertFalse(self.model.uncertain(self.policy.repository, intent.key, intent.token))
        result = self.model.reconcile(self.policy.repository, intent.key, [self.issue(intent)], discovery_complete=True)
        self.assertEqual(result.action, "review_required")

    def test_verified_published_artifact_remains_noop(self):
        intent = self.prepare()
        self.model.confirmed(self.policy.repository, intent.key, intent.token, self.issue(intent))
        result = self.model.reconcile(self.policy.repository, intent.key, [self.issue(intent)], discovery_complete=True)
        self.assertEqual((result.action, result.issue_number), ("noop", 42))

    def test_distinct_verified_late_success_after_reconciliation_is_sticky_conflict(self):
        intent = self.prepare()
        self.model.reconcile(self.policy.repository, intent.key, [self.issue(intent, 42)], discovery_complete=True)
        self.assertFalse(self.model.confirmed(self.policy.repository, intent.key, intent.token, self.issue(intent, 43)))
        self.assertEqual(self.prepare().action, "review_required")
        self.assertFalse(self.model.confirmed(self.policy.repository, intent.key, intent.token, self.issue(intent, 42)))
        result = self.model.reconcile(self.policy.repository, intent.key, [self.issue(intent, 42)], discovery_complete=True)
        self.assertEqual(result.action, "review_required")

    def test_published_artifact_audit_needs_complete_discovery(self):
        intent = self.prepare()
        self.model.confirmed(self.policy.repository, intent.key, intent.token, self.issue(intent))
        result = self.model.reconcile(self.policy.repository, intent.key, [self.issue(intent)], discovery_complete=False)
        self.assertEqual(result.action, "reconcile")

    def test_approval_for_another_destination_is_rejected(self):
        public = Policy("example/public-telemetry", "report-bot[bot]", self.releases, "public")
        key, _, digest = material(self.report)
        wrong = Approval(key, "example/other", digest, "1" * 64)
        self.assertEqual(self.prepare(policy=public, approval=wrong).action, "review_required")

    def test_open_day_and_non_utc_reference_are_rejected(self):
        for as_of in ["2026-11-17T23:00:00Z", "2026-11-18T00:59:59Z", "2026-11-18T02:00:00+01:00"]:
            with self.assertRaises(ContractError):
                self.model.prepare(self.report, self.policy, as_of_utc=as_of, expected_key=material(self.report)[0])

    def test_old_frozen_aggregate_can_publish_after_raw_expiry(self):
        result = self.model.prepare(self.report, self.policy, as_of_utc="2026-11-25T01:00:00Z", expected_key=material(self.report)[0])
        self.assertEqual(result.action, "create")

    def test_syntactically_valid_unapproved_release_is_refused(self):
        value = deepcopy(self.report)
        value["release_id"] = "v999.999.999"
        with self.assertRaisesRegex(ContractError, "^unapproved_release$"):
            self.prepare(value)
        self.assertEqual(self.model.entries, {})

    def test_report_must_match_independently_requested_identity(self):
        with self.assertRaisesRegex(ContractError, "^unexpected_report$"):
            self.model.prepare(self.report, self.policy, as_of_utc="2026-11-18T01:00:00Z",
                               expected_key="daily-gpu-v1/2026-11-16/v0.2.7")
        self.assertEqual(self.model.entries, {})

    def test_raw_or_arbitrary_extra_fields_cannot_reach_renderer(self):
        value = deepcopy(self.report)
        value["session_id"] = "a" * 32
        with self.assertRaises(ContractError):
            self.prepare(value)
        self.assertEqual(self.model.entries, {})


class InterpretationCounterexamples(unittest.TestCase):
    def test_percentile_order_statistic_differs_from_slowest_mean(self):
        # F02: 200 intervals, so two constitute 1%. No MangoHud invocation.
        milliseconds = [10] * 198 + [25, 100]
        worst = sorted(milliseconds, reverse=True)
        order_statistic_fps = 1000 / worst[1]
        slowest_mean_fps = 1000 / ((worst[0] + worst[1]) / 2)
        self.assertEqual(order_statistic_fps, 40)
        self.assertEqual(slowest_mean_fps, 16)
        window = FrameWindow()
        for value in milliseconds:
            window.record(value * 1000, draws=1)
        self.assertEqual(window.histogram, [0, 198, 1, 0, 1, 0, 0, 0])

    def test_population_mix_changes_pooled_fps_without_stratum_regression(self):
        # F20: exercise the actual reducer; both hardware strata remain identical.
        def measured(fast_windows, slow_windows):
            records = []
            for family, windows, fps, bin_index, base in [
                ("nvidia_rtx", fast_windows, 100, 1, 1),
                ("intel_integrated", slow_windows, 50, 2, 21),
            ]:
                for identity in range(base, base + 20):
                    payload = deepcopy(example())
                    payload["session_id"] = f"{identity:032x}"
                    payload["batch_id"] = f"{identity + 1000:032x}"
                    payload["context"]["gpu_family"] = family
                    payload["context"].update(vsync="off", fps_cap_bucket="unlimited")
                    event = payload["events"][0]
                    event["interval_count"] = event["rendered_frames"] = fps * 30
                    event["interval_sum_us"] = 30_000_000
                    event["interval_histogram"] = [0] * 8
                    event["interval_histogram"][bin_index] = fps * 30
                    payload["events"] = [dict(deepcopy(event), seq=seq) for seq in range(1, windows + 1)]
                    records.append(("2026-11-17", encode(payload)))
            value = aggregate_daily_gpu(records, "2026-11-17", "v0.2.7",
                                        as_of_utc="2026-11-18T01:00:00Z")
            rates = {row["gpu_family"]: row["rendered_frames"] * 1_000_000 / row["interval_sum_us"]
                     for row in value["rows"]}
            total = sum(row["rendered_frames"] for row in value["rows"]) * 1_000_000
            return total / sum(row["interval_sum_us"] for row in value["rows"]), rates

        before, before_rates = measured(5, 5)
        after, after_rates = measured(3, 7)
        self.assertEqual((before, after), (75, 65))
        self.assertAlmostEqual((after / before - 1) * 100, -13.3333333333333)
        self.assertEqual(before_rates, after_rates)
        self.assertEqual(before_rates, {"nvidia_rtx": 100, "intel_integrated": 50})

    def test_observed_hitch_does_not_invent_modeled_samples(self):
        window = FrameWindow()
        window.record(100_000, draws=1)
        event = window.event()
        self.assertEqual((event["interval_count"], event["interval_sum_us"], event["rendered_frames"]),
                         (1, 100_000, 1))
        self.assertEqual(event["interval_histogram"], [0, 0, 0, 0, 1, 0, 0, 0])
        # F13's independently specified model would be a DIFFERENT population.
        modeled = list(range(100_000, 0, -10_000))
        self.assertEqual((len(modeled), sum(modeled)), (10, 550_000))
        self.assertNotEqual(event["interval_sum_us"], sum(modeled))


if __name__ == "__main__":
    unittest.main()
