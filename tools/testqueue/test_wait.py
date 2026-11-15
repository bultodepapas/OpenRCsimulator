"""Polling behavior for queued jobs and quarantined attempts."""
from unittest import TestCase, mock

from tools.testqueue import common


class WaitTests(TestCase):
    def test_unknown_returns_immediately_even_with_stale_session(self):
        for ready in (False, True):
            with self.subTest(ready=ready):
                status = {"state": "UNKNOWN", "session": {"port": 47870}}
                with mock.patch.object(common, "rpc", return_value=status) as rpc, \
                        mock.patch.object(common.time, "sleep") as sleep:
                    self.assertEqual(common.wait("job", timeout=600, ready=ready), status)
                rpc.assert_called_once_with("status", root=None, job="job", deadline=mock.ANY)
                sleep.assert_not_called()

    def test_cleaning_session_does_not_count_as_ready(self):
        cleaning = {"state": "CLEANING", "session": {"port": 47870}}
        finished = {"state": "FINISHED", "outcome": "CANCELED"}
        with mock.patch.object(common, "rpc", side_effect=[cleaning, finished]) as rpc, \
                mock.patch.object(common.time, "sleep") as sleep:
            self.assertEqual(common.wait("job", ready=True), finished)
        self.assertEqual([call.args[0] for call in rpc.call_args_list], ["status", "status"])
        sleep.assert_called_once()

    def test_running_session_is_ready(self):
        status = {"state": "RUNNING", "session": {"port": 47870}}
        with mock.patch.object(common, "rpc", return_value=status) as rpc:
            self.assertEqual(common.wait("job", ready=True), status)
        rpc.assert_called_once_with("status", root=None, job="job", deadline=mock.ANY)

    def test_timeout_does_not_cancel_queued_job(self):
        queued = {"state": "QUEUED"}
        with mock.patch.object(common, "rpc", return_value=queued) as rpc, \
                mock.patch.object(common.time, "monotonic", side_effect=[10.0, 10.0, 11.0]):
            self.assertEqual(common.wait("job", timeout=0.5), {**queued, "wait_observation": {
                "state": "STALE", "reason": "DEADLINE_EXPIRED"}})
        rpc.assert_called_once_with("status", root=None, job="job", deadline=10.5)

    def test_zero_budget_never_observes_or_cancels(self):
        with mock.patch.object(common, "rpc") as rpc:
            with self.assertRaisesRegex(common.ObservationTimeout, "job owned.*retry status") as raised:
                common.wait("owned", timeout=0)
        self.assertEqual(raised.exception.reason, "DEADLINE_EXPIRED")
        rpc.assert_not_called()

    def test_invalid_budgets_are_rejected_before_rpc(self):
        for timeout in (-1, float("inf"), float("-inf"), float("nan"), 10 ** 1000, True, "1"):
            with self.subTest(timeout=str(timeout)[:32]), mock.patch.object(common, "rpc") as rpc:
                with self.assertRaises(ValueError):
                    common.wait("owned", timeout=timeout)
                rpc.assert_not_called()

    def test_first_rpc_deadline_expiry_reports_no_observation(self):
        with mock.patch.object(common, "rpc", side_effect=common.RpcDeadlineExceeded("expired")) as rpc:
            with self.assertRaisesRegex(common.ObservationTimeout, "owned.*retry status"):
                common.wait("owned", timeout=1)
        self.assertEqual([call.args[0] for call in rpc.call_args_list], ["status"])

    def test_timeout_returns_last_observed_status_without_canceling(self):
        queued = {"state": "QUEUED", "reason": "RESOURCE_BUSY"}
        with mock.patch.object(common, "rpc", side_effect=[queued, common.RpcDeadlineExceeded("expired")]) as rpc, \
                mock.patch.object(common.time, "monotonic", return_value=10.0), \
                mock.patch.object(common.time, "sleep"):
            self.assertEqual(common.wait("owned", timeout=1), {**queued, "wait_observation": {
                "state": "STALE", "reason": "DEADLINE_EXPIRED"}})
        self.assertEqual([call.args[0] for call in rpc.call_args_list], ["status", "status"])
        self.assertEqual([call.kwargs["deadline"] for call in rpc.call_args_list], [11.0, 11.0])

    def test_sleep_uses_only_remaining_budget(self):
        queued = {"state": "QUEUED"}
        with mock.patch.object(common, "rpc", return_value=queued), \
                mock.patch.object(common.time, "monotonic", side_effect=[10.0, 10.0, 10.45, 10.5]), \
                mock.patch.object(common.time, "sleep") as sleep:
            self.assertEqual(common.wait("owned", timeout=0.5), {**queued, "wait_observation": {
                "state": "STALE", "reason": "DEADLINE_EXPIRED"}})
        self.assertAlmostEqual(sleep.call_args.args[0], 0.05)

    def test_socket_step_timeout_is_distinct_and_marks_prior_status_stale(self):
        queued = {"state": "QUEUED"}
        with mock.patch.object(common, "rpc", side_effect=[queued, common.RpcStepTimeout("socket")]) as rpc, \
                mock.patch.object(common.time, "monotonic", return_value=10.0), \
                mock.patch.object(common.time, "sleep"):
            self.assertEqual(common.wait("owned", timeout=600), {**queued, "wait_observation": {
                "state": "STALE", "reason": "RPC_STEP_TIMEOUT"}})
        self.assertEqual([call.args[0] for call in rpc.call_args_list], ["status", "status"])

    def test_unavailable_is_not_fabricated_as_a_job_state(self):
        with mock.patch.object(common, "rpc", side_effect=RuntimeError("unavailable")):
            with self.assertRaisesRegex(RuntimeError, "unavailable"):
                common.wait("owned", timeout=1)
