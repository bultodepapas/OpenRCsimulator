"""Run the unchanged frozen pull-up CLI tests with only CANDIDATE overridden."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import unittest


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: run_frozen_pullup_override.py <frozen-test-module> <expected-app> <candidate-json>", file=sys.stderr)
        return 2
    test_path, expected_app, candidate_path = (Path(value).resolve() for value in sys.argv[1:])
    if not test_path.is_file() or not candidate_path.is_file():
        print("test module or candidate input does not exist", file=sys.stderr)
        return 2
    module_name = "frozen_07_test_pullup_cli"
    spec = importlib.util.spec_from_file_location(module_name, test_path)
    if spec is None or spec.loader is None:
        print("cannot load frozen test module", file=sys.stderr)
        return 2
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    original_values = {
        "APP": Path(module.APP).resolve(),
        "REFERENCE": Path(module.REFERENCE).resolve(),
        "CANDIDATE": Path(module.CANDIDATE).resolve(),
    }
    if original_values["APP"] != expected_app:
        print(f"frozen module APP mismatch: {original_values['APP']} != {expected_app}", file=sys.stderr)
        return 2
    # This is the sole test-module override. Test methods and other module globals stay untouched.
    module.CANDIDATE = candidate_path
    godot = os.environ.get("OPENRC_TEST_GODOT", "")
    receipt = {
        "format": "d8b-r2-frozen-pullup-candidate-override-run-v1",
        "test_module": str(test_path),
        "test_module_sha256": sha256(test_path),
        "app_from_frozen_module": str(original_values["APP"]),
        "expected_app": str(expected_app),
        "reference_from_frozen_module": str(original_values["REFERENCE"]),
        "reference_sha256": sha256(original_values["REFERENCE"]),
        "original_candidate_from_frozen_module": str(original_values["CANDIDATE"]),
        "candidate_override_only": str(candidate_path),
        "candidate_override_sha256": sha256(candidate_path),
        "godot_from_OPENRC_TEST_GODOT": godot,
        "godot_exists": Path(godot).is_file() if godot else False,
    }
    print("RUN_IDENTITY " + json.dumps(receipt, sort_keys=True))
    if not receipt["godot_exists"]:
        print("OPENRC_TEST_GODOT must name the pinned Godot binary", file=sys.stderr)
        return 2
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(module.PullupCandidateCli)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    print("RUN_RESULT " + json.dumps({
        "tests_run": result.testsRun,
        "failures": len(result.failures),
        "errors": len(result.errors),
        "skipped": len(result.skipped),
        "was_successful": result.wasSuccessful(),
    }, sort_keys=True))
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
