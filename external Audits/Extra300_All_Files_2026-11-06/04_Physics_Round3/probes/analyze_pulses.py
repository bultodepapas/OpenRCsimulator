"""Derive pulse metrics and a reproducible figure from accepted CSVs.

This analyzes simulation output; it does not estimate real-aircraft derivatives.
Run: python3 analyze_pulses.py PULSES_DIRECTORY OUTPUT_DIRECTORY
"""
import csv
import json
import math
import sys
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def read_csv(path):
    with path.open(newline='') as stream:
        return [{key: float(value) for key, value in row.items()}
                for row in csv.DictReader(stream)]


def analyze(folder, output):
    output.mkdir(parents=True, exist_ok=True)
    report = json.loads((folder / 'results.json').read_text())
    assert report['failures'] == 0 and len(report['cases']) == 12
    data = {}
    metrics = []
    for case in report['cases']:
        tag = case['case']
        rows = read_csv(folder / (tag + '.csv'))
        assert len(rows) == 480
        assert case['exact_replay']['ok'] and case['exact_replay']['complete']
        assert case['exact_replay']['ticks'] == 480
        data[tag] = rows
        # Rows hold post-step samples. Pre-step commands are on at .2, off at .7 s.
        pulse = rows[48:168]
        peak = max(pulse, key=lambda row: abs(row['p_radps']))
        baseline = rows[47]['aileron_deg']
        end = rows[167]['aileron_deg']
        p_release = abs(rows[167]['p_radps'])
        metrics.append({
            'case': tag,
            'initial_speed_mps': case['speed_mps'],
            'peak_abs_body_roll_deg_s': math.degrees(abs(peak['p_radps'])),
            'peak_time_s': peak['t_s'],
            'right_aileron_baseline_deg': baseline,
            'right_aileron_pulse_end_deg': end,
            'right_aileron_increment_deg': end - baseline,
            'servo_first_target_sample_after_on_s': next(
                row['t_s'] - .2 for row in pulse if abs(row['aileron_deg'] - end) < 1e-10),
            'servo_first_neutral_sample_after_off_s': next(
                row['t_s'] - .7 for row in rows[168:] if abs(row['aileron_deg'] - baseline) < 1e-10),
            'body_roll_deg_s_at_0p8s': math.degrees(rows[191]['p_radps']),
            'right_aileron_deg_at_0p8s': rows[191]['aileron_deg'],
            'first_half_release_roll_sample_after_off_s': next(
                row['t_s'] - .7 for row in rows[168:] if abs(row['p_radps']) <= .5 * p_release),
            'pulse_airspeed_range_mps': [min(row['V_mps'] for row in pulse), max(row['V_mps'] for row in pulse)],
            'pulse_alpha_range_deg': [math.degrees(min(row['alpha_rad'] for row in pulse)), math.degrees(max(row['alpha_rad'] for row in pulse))],
            'pulse_beta_range_deg': [math.degrees(min(row['beta_rad'] for row in pulse)), math.degrees(max(row['beta_rad'] for row in pulse))],
            'pulse_max_abs_pitch_rate_deg_s': max(abs(math.degrees(row['q_radps'])) for row in pulse),
            'pulse_max_abs_yaw_rate_deg_s': max(abs(math.degrees(row['r_radps'])) for row in pulse),
        })
    lookup = {case['case']: case for case in report['cases']}
    pairs = []
    for side in ['left', 'right']:
        for first, second in [('22_sport_' + side, '22_full_' + side),
                              ('22_matched_' + side, '22_normal_' + side)]:
            equal = lookup[first]['dynamics_sha256'] == lookup[second]['dynamics_sha256']
            assert equal
            pairs.append({'first': first, 'second': second, 'physical_array_hashes_equal': equal})
    payload = {
        'source_commit': report['source_commit'],
        'recordings': len(report['cases']), 'replayed_physics_ticks': 12 * 480,
        'pulse_on_s': .2, 'pulse_off_s': .7, 'recording_duration_s': 2.0,
        'initial_density_kg_m3': report['cases'][0]['initial_rho_kg_m3'],
        'initial_mass_kg': report['cases'][0]['initial_mass_kg'],
        'interpretation': 'Open-loop, scripted pre-servo stick steps; no real-aircraft, steady-rate, native performance or device-latency claim.',
        'equal_physics_pairs': pairs, 'metrics': metrics,
    }
    (output / 'pulse_analysis.json').write_text(json.dumps(payload, indent=2) + '\n')
    with (output / 'pulse_summary.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(metrics[0]))
        writer.writeheader()
        writer.writerows(metrics)

    plt.rcParams.update({'font.size': 11, 'axes.spines.top': False, 'axes.spines.right': False})
    fig, axes = plt.subplots(2, 1, figsize=(10.8, 7.4), sharex=True)
    for tag, label, color in [('22_normal_right', 'Normal / matched full command', '#2563a6'),
                              ('22_full_right', 'Full / sport', '#cb532c')]:
        rows = data[tag]
        times = [row['t_s'] for row in rows]
        axes[0].plot(times, [row['aileron_deg'] for row in rows], color=color, lw=2.4, label=label)
        axes[1].plot(times, [math.degrees(row['p_radps']) for row in rows], color=color, lw=2.4)
    for ax in axes:
        ax.axvspan(.2, .7, color='#e7edf1', zorder=-2)
        ax.axvline(.7, color='#7e8b94', lw=.9, linestyle='--')
        ax.grid(axis='y', color='#dfe4e8', lw=.7)
        ax.set_xlim(0, 1.2)
    axes[0].set_ylabel('Right aileron angle (degrees)')
    axes[0].set_ylim(-.5, 19.5)
    axes[0].legend(loc='upper right', frameon=False, fontsize=10)
    axes[0].text(.22, 18.3, '0.5 s roll command', fontsize=10, color='#46515b')
    axes[1].set_ylabel('Body roll rate p (degrees / second)')
    axes[1].set_xlabel('Simulation time (seconds)')
    axes[1].set_ylim(-8, 310)
    axes[1].annotate('Full / sport: 279.0 deg/s', xy=(.425, 279.0455), xytext=(.18, 300),
                     fontsize=10, color='#a83d1d', arrowprops={'arrowstyle': '-', 'color': '#a83d1d'})
    axes[1].annotate('Normal: 107.9 deg/s', xy=(.7, 107.8598), xytext=(.73, 180),
                     fontsize=10, color='#2563a6', arrowprops={'arrowstyle': '-', 'color': '#2563a6'})
    fig.suptitle('Extra 300S: the commanded travel changes both roll rate and stopping response',
                 fontsize=14, fontweight='bold', x=.09, ha='left')
    fig.text(.09, .925, '22 m/s initial trim • right roll • full fuel • unchanged production physics',
             color='#46515b', fontsize=11)
    fig.text(.09, .018, '240 Hz • commit 2e2e349 • first 1.2 s of each 2 s recording • all 12 recordings replayed exactly\n'
             'Simulated open-loop response, including coupled motion; not a measured real-aircraft roll rate.',
             fontsize=9, color='#46515b')
    fig.subplots_adjust(left=.09, right=.975, bottom=.15, top=.89, hspace=.13)
    fig.savefig(output / 'Extra300_Roll_Response.png', dpi=180)
    fig.savefig(output / 'Extra300_Roll_Response.svg')
    plt.close(fig)
    print(json.dumps({'accepted_recordings': 12, 'replayed_ticks': 5760, 'equal_pairs': len(pairs),
                      'outputs': str(output)}, indent=2))


if __name__ == '__main__':
    analyze(Path(sys.argv[1]), Path(sys.argv[2]))
