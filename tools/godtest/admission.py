"""Size a managed GOD TEST execution lease for the complete expanded plan.

The worker enforces the resulting lease from adapter process creation. Queueing,
submission, and worker preparation before that point are separate. The lease
is not a completion guarantee: filesystem, socket, and report-reduction work
does not have a hard time bound, even though it receives an allowance here.
"""
from __future__ import annotations

from fractions import Fraction
import math

from tools.godtest import catalog


# The queue validates the same maximum in tools/testqueue/presets.py.
QUEUE_EXECUTION_LIMIT_S = 21600

# Adapter history preparation: git clone (300 s), git reset (60 s).
ADAPTER_HISTORY_ALLOWANCE_S = 300 + 60
# A missing import cache causes one run_checked import (600 s). Allow its
# Windows taskkill (10 s), process wait (10 s), output-reader join (2 s), and
# one second of polling slack. This is reserved even if an import may be
# unnecessary: the worker decides from the captured manifest after submission.
ADAPTER_IMPORT_ALLOWANCE_S = 600 + 10 + 10 + 2 + 1

# runner.source_identity invokes three 30 s Git commands both before and after
# each case. The launcher may retry bridge readiness once after a port collision;
# each readiness timeout is min(180, scenario timeout). The first readiness wait
# overlaps the scenario's launch-based deadline, so one additional wait is
# reserved, along with the runner's 10 s deadline grace and five seconds for
# readiness polling/socket slack.
CASE_IDENTITY_ALLOWANCE_S = 2 * 3 * 30
CASE_LAUNCH_RETRY_MAX_S = 180
CASE_DEADLINE_GRACE_S = 10
CASE_LAUNCH_POLL_ALLOWANCE_S = 5

# runner can call debugctl.stop twice. Each call has a 5 s socket timeout and
# a 60 s graceful-stop loop. Round the 0.2 s polling and 0.5 s forced-stop
# sleeps up to whole seconds. The optional GPU join, frame-watch join, and
# post-shutdown join use 3, 15, and 3 seconds respectively.
CASE_SHUTDOWN_ALLOWANCE_S = 2 * (5 + 60 + 1) + 1
CASE_MONITOR_ALLOWANCE_S = 3 + 15 + 3

# Hashing/copying frozen inputs and reducing reports have no duration limit.
# This finite planning allowance is deliberately not presented as a bound on
# their runtime; the worker's execution lease remains the enforced boundary.
CASE_FILES_AND_REDUCTION_ALLOWANCE_S = 120


def execution_budget(cases: list[dict] | tuple[dict, ...]) -> int:
    """Return the bounded lease in seconds for all already-expanded cases.

    Reject malformed/empty plans and any plan whose calculated lease does not
    fit the queue. Rounding is upward, and no case or repetition is removed.
    The caller must calculate this before submitting the managed job.
    """
    if not isinstance(cases, (list, tuple)) or not cases:
        raise ValueError("GOD TEST admission requires a nonempty expanded case list")
    allowances = []
    for index, case in enumerate(cases, start=1):
        try:
            catalog.validate(case)
        except (ValueError, TypeError, KeyError, OverflowError) as error:
            raise ValueError(f"invalid GOD TEST admission case {index}: {error}") from error
        # Keep fractional seconds exact when adding many cases. A float sum
        # can round a value just above the queue ceiling back down to it.
        timeout = Fraction(case["timeout_s"])
        allowances.append(
            timeout + min(CASE_LAUNCH_RETRY_MAX_S, timeout)
            + CASE_DEADLINE_GRACE_S + CASE_LAUNCH_POLL_ALLOWANCE_S
            + CASE_IDENTITY_ALLOWANCE_S + CASE_SHUTDOWN_ALLOWANCE_S
            + CASE_MONITOR_ALLOWANCE_S + CASE_FILES_AND_REDUCTION_ALLOWANCE_S
        )
    budget = math.ceil(sum(allowances, ADAPTER_HISTORY_ALLOWANCE_S + ADAPTER_IMPORT_ALLOWANCE_S))
    if budget > QUEUE_EXECUTION_LIMIT_S:
        raise ValueError(
            f"GOD TEST execution budget {budget} s exceeds the queue limit "
            f"of {QUEUE_EXECUTION_LIMIT_S} s for {len(cases)} expanded cases; "
            "split the requested plan into separate runs"
        )
    return budget
