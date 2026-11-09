"""Guard expensive optional work without weakening the required visual job."""
from pathlib import Path
import re
import unittest

WORKFLOW = Path(__file__).resolve().parents[2] / '.github/workflows/ci.yml'


def selected(condition, event, ref, enabled):
    # Evaluate only the small boolean vocabulary used by these gates. Unknown
    # expressions fail the fixture rather than acquiring skip semantics.
    expression = condition.removeprefix('${{').removesuffix('}}').strip()
    replacements = {'github.event_name': repr(event), 'github.ref': repr(ref),
                    'inputs.visual_shadow': repr(enabled), 'needs.scope.outputs.app': repr('true'),
                    '!cancelled()': 'True', 'true': 'True', '&&': ' and ', '||': ' or '}
    expression = expression.replace("'true'", "'selected-app'")
    replacements['needs.scope.outputs.app'] = repr('selected-app')
    for old, new in replacements.items():
        expression = expression.replace(old, new)
    return eval(expression, {'__builtins__': {}}, {})


class VisualWorkflowTests(unittest.TestCase):
    def test_shadow_campaign_requires_explicit_manual_opt_in(self):
        source = WORKFLOW.read_text(encoding='utf-8')
        self.assertRegex(source, r'workflow_dispatch:\s+inputs:\s+visual_shadow:')
        trigger = source.split('  workflow_dispatch:', 1)[1].split('\npermissions:', 1)[0]
        self.assertIn('type: boolean', trigger)
        self.assertIn('default: false', trigger)
        jobs = dict(re.findall(r'^  ([\w-]+):\n(.*?)(?=^  [\w-]+:|\Z)', source, re.M | re.S))
        conditions = [re.search(r'^    if: (.+)$', jobs[name], re.M).group(1)
                      for name in ('visual-groups', 'visual-shadow')]
        full = jobs['visuals']
        shadow_section = full.split('# Shadow-only steps', 1)[1].split('- name: Prepare identical', 1)[0]
        conditions += re.findall(r'^        if: (.+)$', shadow_section, re.M)
        self.assertEqual(len(conditions), 4)
        for condition in conditions:
            for event, enabled, expected in [('push', False, False), ('push', True, False),
                                              ('pull_request', True, False), ('workflow_dispatch', False, False),
                                              ('workflow_dispatch', True, True)]:
                with self.subTest(condition=condition, event=event, enabled=enabled):
                    self.assertIs(selected(condition, event, 'refs/heads/main', enabled), expected)
            self.assertFalse(selected(condition, 'push', 'refs/tags/v1.0', True))
        required_condition = re.search(r'^    if: (.+)$', full, re.M).group(1)
        self.assertNotIn('visual_shadow', required_condition)
        self.assertIn('- run: app/capture.sh', full)
        self.assertIn('name: captures-app', full)
        self.assertIn('name: capture-diagnostics', full)


if __name__ == '__main__':
    unittest.main()
