#!/usr/bin/env python3
"""Exercise paused lighting edits through native X11 input in a Linux release export."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('native_driver', ROOT / 'docs/research/menu-investigations/UI-06c/export_gui_smoke.py')
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='tod08b-native-') as temp:
        data = Path(temp) / 'data'
        settings = data / 'godot/app_userdata/OpenRC Simulator/settings.cfg'
        driver.seed_settings(settings)
        env = dict(os.environ, XDG_DATA_HOME=str(data), XDG_CACHE_HOME=str(Path(temp) / 'cache'))
        with (out / 'engine.log').open('w') as log:
            process = subprocess.Popen([str(args.binary.resolve()), '--audio-driver', 'Dummy'], env=env, cwd=temp, stdout=log, stderr=subprocess.STDOUT)
            x = driver.X11()
            try:
                driver.wait_for_home()
                window = x.find_window('OpenRC')
                assert window, 'export window missing'
                x.focus(window[0])
                before = driver.grab_screen()
                x.tap(x.XK_RETURN)
                driver.wait_for_screen_change(before)
                x.tap(ord('t'))
                x.tap(x.XK_ESCAPE)
                x.tap(x.XK_DOWN)
                x.tap(x.XK_DOWN)
                x.tap(x.XK_RETURN)
                x.tap(0xFF09)  # Tab: preset picker
                x.tap(x.XK_RETURN)
                print('popup open errors:', (out / 'engine.log').read_text().count('ERROR:'), flush=True)
                driver.capture(out / 'preset-open.png')
                for _ in range(5):
                    x.tap(x.XK_DOWN)  # Night preset
                driver.capture(out / 'preset-selected.png')
                x.tap(x.XK_RETURN)
                print('preset selected errors:', (out / 'engine.log').read_text().count('ERROR:'), flush=True)
                driver.capture(out / 'night-draft.png')
                # Preset -> time slider -> exact time -> advanced toggle -> Cancel -> Apply.
                for _ in range(5):
                    x.tap(0xFF09)
                x.tap(x.XK_RETURN, settle_s=2)
                print('applied errors:', (out / 'engine.log').read_text().count('ERROR:'), flush=True)
                driver.capture(out / 'night-paused.png')
                assert 'astronomical' in settings.read_text(), 'Apply did not save selected time'
                x.tap(x.XK_ESCAPE)
                x.tap(ord('t'))
                trace = driver.wait_for_trace(settings.parent / 'traces', set())
                text = trace.read_text()
                metadata, columns, rows = driver.parse_trace(trace)
                timeline = json.loads(metadata['visual_timeline'])
                context = json.loads(metadata['visual_context'])
                assert len(timeline['events']) == 1
                assert timeline['initial']['config']['mode'] == 'legacy'
                assert context['config']['mode'] == 'legacy'
                assert timeline['events'][0]['config']['mode'] == 'astronomical'
                assert len(rows) >= 2
                (out / 'recording.csv').write_text(text)
                result = dict(ok=True, binary_sha256=driver.sha256_file(args.binary.resolve()), rows=len(rows), edit_tick=timeline['events'][0]['tick'], initial_mode=context['config']['mode'], selected_config=timeline['events'][0]['config'], route='Home → Fly → record → Pause → Time of day → Night → Apply → Continue → stop recording')
                assert 'ERROR:' not in (out / 'engine.log').read_text(), 'engine error in native run'
                (out / 'report.json').write_text(json.dumps(result, indent=2) + '\n')
                print(json.dumps(result))
            finally:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                x.close()
        assert 'ERROR:' not in (out / 'engine.log').read_text(), 'engine error in native run'


if __name__ == '__main__':
    main()
