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
                rpc.assert_called_once_with("status", root=None, job="job")
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
        rpc.assert_called_once_with("status", root=None, job="job")

    def test_timeout_does_not_cancel_queued_job(self):
        queued = {"state": "QUEUED"}
        with mock.patch.object(common, "rpc", return_value=queued) as rpc, \
                mock.patch.object(common.time, "monotonic", side_effect=[10.0, 11.0]):
            self.assertEqual(common.wait("job", timeout=0.5), queued)
        rpc.assert_called_once_with("status", root=None, job="job")
