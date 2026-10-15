"""Validate and summarize the retained RCV-37 measurements without rerunning them."""
import hashlib
import json
from pathlib import Path
import re
from statistics import median

ROOT = Path(__file__).resolve().parents[4]
EVIDENCE = ROOT / 'docs/research/rc-monster-truck/RCV-37'
ERROR = re.compile(r'^(?:(?:SCRIPT |SHADER )?ERROR:|FAIL[: ])', re.M)


def read(relative):
    return json.loads((EVIDENCE / relative).read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def comparison(before, after):
    return {'baseline_us': before, 'candidate_us': after,
            'cpu_time_reduction_percent': 100 * (1 - after / before)}


def main():
    baseline = [read(f'baseline-{run}/activity.json') for run in range(1, 4)]
    candidate = [read(f'candidate-{run}/activity.json') for run in range(1, 4)]
    for result in baseline + candidate:
        assert result['complete'] and result['accepted_ticks'] == 1080
        assert result['physics_rate_hz'] == 240 and result['render_tape_rate_hz'] == 60
        assert result['trajectory_sha256'] == baseline[0]['trajectory_sha256']
        assert result['backend_identity'] == baseline[0]['backend_identity']
        assert result['draw_calls'] == baseline[0]['draw_calls']
        assert result['primitives'] == baseline[0]['primitives']
        assert result['max_dust_active_wheels'] == 4
        assert result['effects']['grime_overlay_count'] == 70
        assert result['effects']['particle_budget_total'] == 96
        assert result['exhaust']['particle_budget'] == 32
    for result in candidate:
        assert result['model_sha256'] == sha(ROOT / 'app/vehicles/ground/monster_car_2_model.gd')
    visual = read('checks/visual.json')
    assert visual['complete'] and visual['parity']['passed'] and visual['pinned_baseline_sha256_check']
    assert visual['candidate_sha256'] == sha(ROOT / 'app/vehicles/ground/monster_car_2_model.gd')
    rounds = visual['timing']['rounds']
    animation = comparison(median(r['baseline']['usec_per_draw'] for r in rounds),
                           median(r['candidate']['usec_per_draw'] for r in rounds))
    audio = read('checks/audio.json')
    assert audio['complete'] and audio['parity_complete'] and audio['parity_passed']
    assert audio['candidate_sha256'] == sha(ROOT / 'app/audio/nitro_voice.gd')
    sound = audio['benchmark_results']
    audio_cost = comparison(sound['baseline_median_usec'], sound['candidate_median_usec'])
    audio_cost['frames_per_run'] = sound['frames_per_run']
    activity = {metric: comparison(median(r['presentation_cost'][metric] for r in baseline),
                                   median(r['presentation_cost'][metric] for r in candidate))
                for metric in ('mean_us', 'median_us', 'p95_us')}
    session = read('checks/session.json')
    assert session['complete'] and session['exact_replay'] and session['checkpoint_restore_exact']
    assert session['backend_identity_probe']['matches_prepared_and_checkpoint_identity']
    assert session['backend_identity'] == baseline[0]['backend_identity']['backend_identity']
    verification = read('checks/verification.json')
    assert verification['complete']
    assert verification['model_sha256'] == visual['candidate_sha256']
    assert verification['voice_sha256'] == audio['candidate_sha256']
    assert verification['session_sha256'] == sha(EVIDENCE / 'checks/session.json')
    confirmation = read('baseline-confirmation/activity.json')
    assert confirmation['complete'] and confirmation['trajectory_sha256'] == baseline[0]['trajectory_sha256']
    for path in EVIDENCE.rglob('*.log'):
        assert not ERROR.search(path.read_text(encoding='utf-8-sig')), str(path)
    evidence_hashes = {str(path.relative_to(EVIDENCE)).replace('\\', '/'): sha(path)
                       for path in sorted(EVIDENCE.rglob('*'))
                       if path.suffix in ('.json', '.png', '.log') and path.name != 'summary.json'}
    report = {
        'complete': True, 'engine': baseline[0]['engine'], 'processor': baseline[0]['processor'],
        'video_adapter': baseline[0]['video_adapter'],
        'animation_cpu_per_draw': animation, 'audio_cpu_per_run': audio_cost,
        'activity_presentation_cpu': activity,
        'later_baseline_confirmation_mean_us': confirmation['presentation_cost']['mean_us'],
        'exact_visual_poses': visual['parity']['total_pose_count'],
        'exact_audio_frames': audio['parity_results']['compared_frames'],
        'exact_activity_trajectory_sha256': baseline[0]['trajectory_sha256'],
        'exact_driving_replay': session['exact_replay'], 'solver_changed': False,
        'scope': 'CPU callback and component timings, not full GPU frame time or a target-hardware FPS claim. Three native baseline runs followed by three candidate runs and a later baseline confirmation; component pairs alternate execution order. Existing unrelated desktop processes were left running. Later native captures omit text with both adapters; the native screenshots qualify the 3D vehicle only.',
        'remaining_physics_cost_us': session['tick_cost'],
        'evidence_sha256': evidence_hashes,
    }
    (EVIDENCE / 'summary.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'evidence_sha256'}, indent=2))


if __name__ == '__main__':
    main()
