"""Recheck retained synthetic classification and real-app metadata, not FPS."""
from pathlib import Path
import importlib.util
import json
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = next(parent for parent in HERE.parents if (parent/'app/project.godot').is_file())
sys.path.insert(0, str(ROOT/'research/performance'))
import native_summary

spec = importlib.util.spec_from_file_location('before', HERE/'native_summary_before.py')
before = importlib.util.module_from_spec(spec)
spec.loader.exec_module(before)
policy = json.loads((HERE/'summary-post-fix.json').read_text())['policy']
with tempfile.TemporaryDirectory() as temporary:
    for name, module, expected in [('before', before, 0), ('current', native_summary, 1)]:
        summary, status = module.summarize_directory(
            HERE/'synthetic-campaign', Path(temporary)/(name+'.json'), policy)
        assert status == expected and summary['performance_pass_count'] == 3, summary
        if name == 'current':
            assert not summary['lake_reflection_configuration_consistent']
            assert summary['lake_reflection_configuration_complete']

for name, requested, mode, active, size in [
    ('high-probe', '', 'probe', False, [0, 0]),
    ('high-planar', 'planar', 'planar', True, [640, 360]),
    ('standard-ignored', 'planar', 'probe', False, [0, 0]),
    ('no-lake', 'planar', 'absent', False, [0, 0]),
]:
    report = json.loads((HERE/(name+'.json')).read_text())
    evidence = report['visual_evidence'] if name == 'no-lake' else report
    assert evidence['render_settings']['lake_reflections'] == {
        'requested': requested, 'mode': mode, 'planar_active_at_report': active,
        'capture_size_at_report': size,
    }, name
print('Reflection identity: before/after synthetic campaign and four native metadata cases pass')
