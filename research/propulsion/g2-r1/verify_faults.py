"""G2-R1: inject solver faults only into a disposable copy of the app."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, default=ROOT / 'app')
args = parser.parse_args()
godot = subprocess.check_output([str(ROOT / 'app/get-godot.sh')], text=True).strip()
source = (args.app / 'physics/propulsion.gd').read_text()

def replace_once(text, before, after):
    assert text.count(before) == 1, before
    return text.replace(before, after)

with tempfile.TemporaryDirectory(prefix='openrc-g2-r1-faults-') as directory:
    app = Path(directory) / 'app'
    shutil.copytree(args.app, app, ignore=shutil.ignore_patterns('.godot', 'captures'))
    target = app / 'physics/propulsion.gd'
    def run(label, text, script, expected):
        target.write_text(text)
        result = subprocess.run([godot, '--headless', '--path', str(app), '--script', script],
                                capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        assert 'ERROR:' not in output and result.returncode == expected, (label, result.returncode, output)
        print(f'{label}: expected exit {expected}; verified')

    test = 'res://tests/test_shaft_equilibrium.gd'
    run('positive control', source, test, 0)
    unbracketed = replace_once(source, ' or low_torque < 0.0 or high_torque > 0.0', '')
    # Final residual checking also rejects the same bad endpoints. Disable it to isolate the bracket guard.
    residual_guard = 'if absf(residual) > SHAFT_TORQUE_TOL * maxf(1.0, maxf(absf(engine), absf(torque_load))):'
    unbracketed = replace_once(unbracketed, residual_guard, 'if false:')
    run('missing bracket and residual guards detected', unbracketed, test, 1)
    # The helper follows the main solve, so target its signature rather than every engine query.
    signature = 'static func _shaft_net_torque(rpm: float, throttle: float, u: float, prop: Dictionary, rho: float) -> float:\n'
    internal = str(ROOT / 'research/propulsion/g2-r1/fault_probe.gd')
    midpoint = replace_once(source, signature, signature + '\tif rpm == 8000.5:\n\t\treturn NAN\n')
    run('nonfinite midpoint refused', midpoint, internal, 0)
    missing_check = replace_once(midpoint, '\t\tif not is_finite(net):\n\t\t\treturn NAN\n', '')
    run('missing midpoint guard detected', missing_check, internal, 1)
    # Pretend the inner solve sees a discontinuity at 2000 RPM; actual torque is not balanced there.
    fake_residual = replace_once(source, 'return engine - torque_load if is_finite(engine) and is_finite(torque_load) else NAN',
                                'return 1.0 if rpm < 2000.0 else -1.0')
    run('false inner root refused by final physical residual', fake_residual, internal, 0)
    missing_check = replace_once(fake_residual, residual_guard, 'if false:')
    run('missing final residual guard detected', missing_check, internal, 1)
print('G2-R1: three negative controls and both internal-fault refusals passed.')
