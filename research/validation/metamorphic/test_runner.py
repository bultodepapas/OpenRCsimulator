#!/usr/bin/env python3
"""VAL-4 harness regressions: engine errors, incomplete evidence and unsafe publication."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import run


def report():
    groups = {name: {"checks": 1, "failures": 0} for name in run.GROUPS}
    groups['energy']['checks'] = 7680
    return {"format": "openrc-metamorphic v1", "flights": 56, "ticks_per_flight": 240,
            "groups": groups, "failures": 0}


class Harness(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name)/'report.json'

    def run_fake(self, data, code=0, log=''):
        if data is not None:
            self.output.write_text(json.dumps(data))
        result = subprocess.CompletedProcess([], code, stdout=log)
        with patch.object(run.subprocess, 'run', return_value=result):
            return run.run_engine('/fake', Path('/app'), Path('/checks.gd'), self.output)

    def test_complete_positive_control(self):
        self.assertEqual(self.run_fake(report()), report())

    def test_engine_errors_with_zero_exit_are_failures(self):
        for log in ('SCRIPT ERROR: invalid call\n', 'ERROR: parse failure\n', 'WARNING: leaked resources\n'):
            with self.subTest(log=log), self.assertRaises(ValueError):
                self.run_fake(report(), log=log)

    def test_missing_or_partial_reports_fail(self):
        with self.assertRaises(ValueError):
            self.run_fake(None)
        for key, value in (('flights', 0), ('ticks_per_flight', 239), ('format', 'unknown')):
            data = report()
            data[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.run_fake(data)
        for group in run.GROUPS:
            data = report()
            del data['groups'][group]
            with self.subTest(group=group), self.assertRaises(ValueError):
                self.run_fake(data)

    def test_report_failure_cannot_pass_with_zero_exit(self):
        data = report()
        data['failures'] = 1
        data['groups']['mirror']['failures'] = 1
        with self.assertRaises(ValueError):
            self.run_fake(data)

    def test_mutation_must_fail_named_group_without_execution_fault(self):
        for failures, valid in (({'froude': 1}, True), ({'mirror': 1}, False), ({}, False), ({'froude': 1, 'integrity': 1}, False)):
            data = report()
            for group, count in failures.items():
                data['groups'][group]['failures'] = count
            data['failures'] = sum(failures.values())
            self.output.write_text(json.dumps(data))
            with patch.object(run.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, stdout='')):
                if valid:
                    run.run_engine('/fake', Path('/app'), Path('/checks.gd'), self.output, 'froude')
                else:
                    with self.assertRaises(ValueError):
                        run.run_engine('/fake', Path('/app'), Path('/checks.gd'), self.output, 'froude')

    def test_failed_publication_preserves_existing_evidence(self):
        self.output.write_text('previous\n')
        with patch.object(run.os, 'replace', side_effect=OSError('injected disk failure')):
            with self.assertRaises(OSError):
                run.atomic_json(self.output, report())
        self.assertEqual(self.output.read_text(), 'previous\n')
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    def test_timeout_is_propagated(self):
        with patch.object(run.subprocess, 'run', side_effect=subprocess.TimeoutExpired('godot', 90)):
            with self.assertRaises(subprocess.TimeoutExpired):
                run.run_engine('/fake', Path('/app'), Path('/checks.gd'), self.output)


if __name__ == '__main__':
    unittest.main(verbosity=2)
