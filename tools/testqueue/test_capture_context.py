"""Admission metadata must not weaken the capture's fixed graphics environment."""
import json
import os
import unittest
from unittest.mock import patch

from tools.ci.capture_groups import configuration
from tools.testqueue import common


class CaptureContextTests(unittest.TestCase):
    def test_routing_metadata_is_ignored_but_graphics_overrides_still_fail(self):
        fixed = {"OPENRC_SCENERY": "off", "OPENRC_SCENERY_BIRDS": "off", "OPENRC_ENGINE_SHADOWS": "off", "LP_NUM_THREADS": "1",
                 "OPENRC_TESTQUEUE_ROOT": "/private/authority"}
        with patch.dict(os.environ, fixed, clear=True):
            result = configuration(True)
            self.assertNotIn("private/authority", json.dumps(result))
            with patch.dict(os.environ, {"OPENRC_FOG": "off"}):
                with self.assertRaises(ValueError):
                    configuration(True)

    def test_inherited_capture_requires_valid_rendered_capability(self):
        fixed = {"OPENRC_SCENERY": "off", "OPENRC_SCENERY_BIRDS": "off", "OPENRC_ENGINE_SHADOWS": "off", "LP_NUM_THREADS": "1",
                 "OPENRC_TESTQUEUE_CONTEXT": "opaque-secret", "OPENRC_GODOT": "/registered/engine"}
        with patch.dict(os.environ, fixed, clear=True), patch.object(common, "inherited", side_effect=ValueError("forged grant")):
            with self.assertRaisesRegex(ValueError, "forged grant"):
                configuration(True)
        with patch.dict(os.environ, fixed, clear=True), patch.object(common, "inherited", return_value=True) as grant:
            result = configuration(True)
            grant.assert_called_once_with("rendered")
            self.assertNotIn("opaque-secret", json.dumps(result))


if __name__ == "__main__":
    unittest.main()
