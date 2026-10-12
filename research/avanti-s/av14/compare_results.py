"""Reduce AV-16 model deltas and explicitly selected timestep-refinement checks."""
import argparse
import json
from pathlib import Path


def metric(case, name, statistic='end'):
    return case['flight']['metrics'][name][statistic]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    reports = {name: json.loads((args.evidence / (name + '.json')).read_text())
               for name in ['baseline-240', 'baseline-480', 'candidate-240', 'candidate-480']}
    cases = {name: {case['id']: case for case in data['cases']} for name, data in reports.items()}
    ids = list(cases['baseline-240'])
    if any(set(group) != set(ids) or len(group) != 34 for group in cases.values()):
        raise SystemExit('Case identity/count mismatch')
    checks, changes = [], []
    for case_id in ids:
        old, new = cases['baseline-240'][case_id], cases['candidate-240'][case_id]
        changes.append({'id': case_id,
                        'speed_end_baseline_mps': metric(old, 'speed_mps'),
                        'speed_end_candidate_mps': metric(new, 'speed_mps'),
                        'altitude_change_baseline_m': metric(old, 'alt_m', 'delta'),
                        'altitude_change_candidate_m': metric(new, 'alt_m', 'delta'),
                        'max_rate_baseline_radps': max(metric(old, k, 'max_abs') for k in ['p_radps', 'q_radps', 'r_radps']),
                        'max_rate_candidate_radps': max(metric(new, k, 'max_abs') for k in ['p_radps', 'q_radps', 'r_radps']),
                        'candidate_trajectory': new.get('trajectory'),
                        'candidate_spin_windows': new.get('spin_windows')})
        selected = []
        if case_id.startswith('level_trim_') or case_id in ['engine_off_glide_21', 'inverted_hands_off_35']:
            selected = [('speed_mps', 'end', 1.0, 0.01), ('engine_rpm', 'end', 1.0, 0.01)]
        elif case_id.startswith(('roll_', 'pitch_', 'yaw_')) and not case_id.startswith('pitch_loop_'):
            axis = {'roll': 'p_radps', 'pitch': 'q_radps', 'yaw': 'r_radps'}[case_id.split('_')[0]]
            selected = [(axis, 'max_abs', 0.1, 0.05), ('speed_mps', 'end', 1.0, 0.05)]
        elif case_id.startswith(('throttle_', 'idle_descent_', 'idle_to_full_')):
            selected = [('engine_rpm', 'end', 1.0, 0.05), ('speed_mps', 'end', 1.0, 0.05)]
        for revision in ['baseline', 'candidate']:
            coarse, fine = cases[revision + '-240'][case_id], cases[revision + '-480'][case_id]
            for name, statistic, floor, band in selected:
                a, b = metric(coarse, name, statistic), metric(fine, name, statistic)
                relative = abs(a - b) / max(abs(b), floor)
                checks.append({'revision': revision, 'id': case_id, 'metric': name + '.' + statistic,
                               'at_240': a, 'at_480': b, 'normalization_floor': floor,
                               'relative_difference': relative, 'band': band, 'passed': relative <= band})
    result = {'interpretation': 'Predicted model changes and numerical refinement, not measured aircraft acceptance.',
              'refinement_rule': 'Steady speed/RPM 1%; smooth pulse axis peak/speed and throttle endpoint 5%. '
                                 'Denominator floors are 1 m/s, 1 RPM and 0.1 rad/s. Nonlinear and stochastic cases are descriptive.',
              'refinement_checks': checks, 'refinement_passed': all(item['passed'] for item in checks),
              'changes': changes, 'baseline_setup': reports['baseline-240']['setup'],
              'candidate_setup': reports['candidate-240']['setup'],
              'candidate_linearized_modes': reports['candidate-240'].get('linearized_modes')}
    (args.evidence / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    lines = ['# AV-16 flight matrix comparison', '', 'Model predictions, not independent physical validation.', '',
             '| Case | Final speed baseline → corrected (m/s) | Altitude change baseline → corrected (m) | Peak total-axis component baseline → corrected (rad/s) |',
             '| --- | ---: | ---: | ---: |']
    for change in changes:
        lines.append(f"| {change['id']} | {change['speed_end_baseline_mps']:.3f} → {change['speed_end_candidate_mps']:.3f} | "
                     f"{change['altitude_change_baseline_m']:.3f} → {change['altitude_change_candidate_m']:.3f} | "
                     f"{change['max_rate_baseline_radps']:.3f} → {change['max_rate_candidate_radps']:.3f} |")
    lines += ['', result['refinement_rule'], '',
              f"Selected refinement checks: {sum(item['passed'] for item in checks)}/{len(checks)} pass. "
              'Exact values and nonlinear trajectory/spin observations are in [comparison.json](comparison.json).']
    for item in checks:
        if not item['passed']:
            lines.append(f"- Outside band: {item['revision']} {item['id']} {item['metric']}: {100*item['relative_difference']:.3f}%.")
    (args.evidence / 'comparison.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f"{len(changes)} compared cases; {sum(item['passed'] for item in checks)}/{len(checks)} refinement checks pass")
    raise SystemExit(0 if result['refinement_passed'] else 1)


if __name__ == '__main__':
    main()
