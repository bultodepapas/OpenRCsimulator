#!/usr/bin/env python3
"""AUD-15: reproducible edits of CC0 wheel-roll and sailplane-touchdown recordings."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import wave

import miniaudio
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / 'research/audio/AUD-15/recordings/landing-gear'
OUTPUT = ROOT / 'app/assets/audio/landing_gear'
RATE = 22050
LICENSE_URL = 'https://creativecommons.org/publicdomain/zero/1.0/'
RECORDINGS = {
    'hard': dict(file='hard_skateboard_roll_hq.mp3', author='FOSSarts',
                 title='skateboard rolling slow 2',
                 page='https://freesound.org/people/FOSSarts/sounds/740125/',
                 download='https://cdn.freesound.org/previews/740/740125_14631530-hq.mp3',
                 sha256='3ca0b4ea4e6d5df0c91aeedebb12793f675d0b8ffc1a22aec57872492c09c584'),
    'grass': dict(file='grass_footstep_texture_hq.mp3', author='FOSSarts',
                  title='stepping on grass 1',
                  page='https://freesound.org/people/FOSSarts/sounds/740144/',
                  download='https://cdn.freesound.org/previews/740/740144_14631530-hq.mp3',
                  sha256='c622700a7953800eeda4fc3075f5ce26f2d7ea1739bdf528b903fbf403e07747'),
    'gravel': dict(file='gravel_wheel_spin_hq.mp3', author='alexftw123',
                   title='Wheel Spin on Gravel.wav',
                   page='https://freesound.org/people/alexftw123/sounds/152657/',
                   download='https://cdn.freesound.org/previews/152/152657_2475830-hq.mp3',
                   sha256='bdcbb4e2fb5998673f9034140b0fdd29e4d913fcb066886f83a607843618088d'),
    'touchdown': dict(file='sailplane_landing_hq.mp3', author='Grotelue',
                      title='Sailplane Landing.wav',
                      page='https://freesound.org/people/Grotelue/sounds/204737/',
                      download='https://cdn.freesound.org/previews/204/204737_1858978-hq.mp3',
                      sha256='940a614406ed262135727d0b29664e75c9fe936a0d57ad80d951f1f18962a0ab'),
}
# Loop edits are chosen from the wheel/material action, not the source's start/stop handling.
# The grass layer is a quiet close-contact texture proxy, not a claim that a person is walking.
LOOPS = {
    'hard_roll.wav': dict(source='hard', start_s=0.35, duration_s=6.15,
                         crossfade_s=0.55, highpass_hz=55.0, lowpass_hz=4200.0,
                         target_rms=0.025, peak_cap=0.42),
    'grass_roll.wav': dict(source='grass', start_s=0.18, duration_s=3.25,
                           crossfade_s=0.42, highpass_hz=80.0, lowpass_hz=2600.0,
                           target_rms=0.012, peak_cap=0.38),
    # The wheel is clearly rolling over gravel in the first two seconds; later material is near-silence.
    'gravel_roll.wav': dict(source='gravel', start_s=0.28, duration_s=1.85,
                            crossfade_s=0.28, highpass_hz=70.0, lowpass_hz=4800.0,
                            target_rms=0.035, peak_cap=0.42),
}
# The first strong onboard gear impact occurs at about 1.9 s in the sailplane landing recording.
IMPACTS = {
    'touchdown.wav': dict(source='touchdown', start_s=1.86, duration_s=0.48,
                          highpass_hz=28.0, lowpass_hz=5200.0, target_rms=0.105,
                          peak_cap=0.72, fade_in_s=0.004, fade_out_s=0.055),
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def wav_bytes(samples):
    pcm = np.rint(np.clip(samples, -1, 1) * 32767).astype('<i2')
    out = io.BytesIO()
    with wave.open(out, 'wb') as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes(pcm.tobytes())
    return out.getvalue(), pcm.astype(np.float64) / 32768


def _filter(samples, highpass_hz, lowpass_hz):
    freq = np.fft.rfftfreq(len(samples), 1 / RATE)
    response = (1 - np.exp(-(freq / highpass_hz) ** 4)) * np.exp(-(freq / lowpass_hz) ** 8)
    return np.fft.irfft(np.fft.rfft(samples) * response, n=len(samples))


def _normalize(samples, target_rms, peak_cap):
    samples = samples - np.mean(samples)
    samples = _filter(samples, highpass_hz=1.0, lowpass_hz=RATE / 2.0 - 1.0)
    rms = max(float(np.sqrt(np.mean(samples * samples))), 1e-12)
    peak = max(float(np.max(np.abs(samples))), 1e-12)
    samples *= min(target_rms / rms, peak_cap / peak)
    return samples


def _loop(source, edit):
    start = round(edit['start_s'] * RATE)
    length = round(edit['duration_s'] * RATE)
    samples = source[start:start + length].copy()
    if len(samples) != length:
        raise RuntimeError(f"Truncated loop source at {edit['start_s']:.3f}s: {edit['source']}")
    samples = samples - np.mean(samples)
    crossfade = round(edit['crossfade_s'] * RATE)
    if crossfade <= 0 or crossfade * 2 >= len(samples):
        raise RuntimeError('Loop crossfade must fit inside the selected source range')
    phase = np.arange(crossfade, dtype=np.float64) / crossfade * np.pi / 2
    blend = samples[-crossfade:] * np.cos(phase) ** 2 + samples[:crossfade] * np.sin(phase) ** 2
    samples = np.concatenate((samples[crossfade:-crossfade], blend))
    samples = _filter(samples, edit['highpass_hz'], edit['lowpass_hz'])
    samples = _normalize(samples, edit['target_rms'], edit['peak_cap'])
    return samples


def _impact(source, edit):
    start = round(edit['start_s'] * RATE)
    length = round(edit['duration_s'] * RATE)
    samples = source[start:start + length].copy()
    if len(samples) != length:
        raise RuntimeError(f"Truncated impact source at {edit['start_s']:.3f}s: {edit['source']}")
    samples = _filter(samples - np.mean(samples), edit['highpass_hz'], edit['lowpass_hz'])
    fade_in = min(round(edit['fade_in_s'] * RATE), len(samples) // 4)
    fade_out = min(round(edit['fade_out_s'] * RATE), len(samples) // 3)
    if fade_in:
        samples[:fade_in] *= np.sin(np.linspace(0.0, np.pi / 2, fade_in)) ** 2
    if fade_out:
        samples[-fade_out:] *= np.cos(np.linspace(0.0, np.pi / 2, fade_out)) ** 2
    return _normalize(samples, edit['target_rms'], edit['peak_cap'])


def build():
    if np.__version__ != '2.4.6' or miniaudio.__version__ != '1.71':
        raise RuntimeError('Install exact tools/audio/requirements-recordings.txt versions')
    decoded = {}
    source_records = {}
    for key, source in RECORDINGS.items():
        path = SOURCES / source['file']
        raw = path.read_bytes()
        if source['sha256'] and sha(raw) != source['sha256']:
            raise RuntimeError(f'Source checksum mismatch: {path}')
        decoded_audio = miniaudio.decode_file(str(path), output_format=miniaudio.SampleFormat.FLOAT32,
                                              nchannels=1, sample_rate=RATE)
        decoded[key] = np.asarray(decoded_audio.samples, dtype=np.float64)
        source_records[key] = dict(source, license='CC0-1.0', license_url=LICENSE_URL,
                                   retrieved='2026-10-20', format='public HQ MP3 preview; original upload not bundled',
                                   decoded_duration_s=len(decoded[key]) / RATE)
    outputs = {}
    entries = []
    for filename, edit in {**LOOPS, **IMPACTS}.items():
        samples = _loop(decoded[edit['source']], edit) if filename in LOOPS else _impact(decoded[edit['source']], edit)
        blob, pcm = wav_bytes(samples)
        if not np.isfinite(pcm).all():
            raise RuntimeError(f'Non-finite samples in {filename}')
        seam = abs(float(pcm[-1] - pcm[0])) if filename in LOOPS else 0.0
        interior = float(np.quantile(np.abs(np.diff(pcm)), .99))
        if filename in LOOPS and seam > max(interior * 1.25, .001):
            raise RuntimeError(f'Unacceptable loop seam for {filename}: {seam:.6f}')
        outputs[filename] = blob
        entries.append(dict(file=filename, source=edit['source'], sha256=sha(blob), sample_rate_hz=RATE,
                            channels=1, sample_count=len(pcm), duration_s=len(pcm) / RATE,
                            format='signed 16-bit PCM little-endian', loop=filename in LOOPS,
                            edits=dict(edit, peak_cap=edit['peak_cap']),
                            metrics=dict(rms=float(np.sqrt(np.mean(pcm * pcm))),
                                         peak=float(np.max(np.abs(pcm))), seam_step=seam,
                                         interior_step_p99=interior)))
    manifest = dict(format='openrc-landing-gear-audio v1', generator='tools/audio/import_landing_gear.py',
                    dependencies=dict(numpy=np.__version__, miniaudio=miniaudio.__version__),
                    sources=source_records, assets=entries,
                    decoded_pcm_bytes=sum(entry['sample_count'] * 2 for entry in entries))
    outputs['manifest.json'] = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    notice = 'CC0 1.0 Universal recordings, edited for OpenRC Simulator (AUD-15).\n'
    notice += 'The grass roll is a quiet tactile grass-footstep proxy; no aircraft-wheel grass recording is claimed.\n'
    for source in RECORDINGS.values():
        notice += f"\n{source['title']} by {source['author']}\n{source['page']}\n"
    notice += f'\nLicense: {LICENSE_URL}\nPublic HQ MP3 previews were used; original uploads are not bundled.\n'
    outputs['LICENSE.txt'] = notice.encode()
    return outputs


def _lossless_import_sidecars(write):
    required = {'compress/mode=0', 'force/8_bit=false', 'edit/normalize=false', 'edit/trim=false'}
    stale = []
    for filename in [*LOOPS, *IMPACTS]:
        path = OUTPUT / (filename + '.import')
        if not path.is_file():
            stale.append(filename + '.import (run Godot import once to create the WAV sidecar)')
            continue
        lines = path.read_text().splitlines()
        settings = {line.split('=', 1)[0]: line for line in lines if '=' in line}
        if write:
            settings['compress/mode'] = 'compress/mode=0'
            updated = [settings.get(line.split('=', 1)[0], line) if '=' in line else line for line in lines]
            if 'compress/mode' not in {line.split('=', 1)[0] for line in lines if '=' in line}:
                updated.append('compress/mode=0')
            path.write_text('\n'.join(updated) + '\n', encoding='utf-8', newline='\n')
            lines = updated
        if not required.issubset(set(lines)):
            stale.append(filename + '.import (unmodified 16-bit PCM required)')
    if stale:
        raise SystemExit('Stale landing-gear import settings: ' + ', '.join(stale))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    outputs = build()
    if args.check:
        stale = [name for name, data in outputs.items()
                 if not (OUTPUT / name).is_file() or (OUTPUT / name).read_bytes() != data]
        try:
            _lossless_import_sidecars(write=False)
        except SystemExit as error:
            stale.append(str(error))
        if stale:
            raise SystemExit('Stale landing-gear outputs: ' + ', '.join(stale))
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for name, data in outputs.items():
            (OUTPUT / name).write_bytes(data)
        _lossless_import_sidecars(write=True)
    loops = sum(1 for name in LOOPS)
    print(f"Landing-gear recordings {'checked' if args.check else 'built'}: {loops} loops, "
          f"{len(IMPACTS)} touchdown one-shot, {sum(len(v) for k, v in outputs.items() if k.endswith('.wav')):,} bytes")


if __name__ == '__main__':
    main()
