#!/usr/bin/env python3
"""AUD-14: deterministic edits of downloaded CC0 wind/fabric recordings; no synthesis."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import wave

import miniaudio
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / 'research/audio/AUD-14/recordings/environment'
OUTPUT = ROOT / 'app/assets/audio/soundscape/recorded'
RATE = 22050
LICENSE_URL = 'https://creativecommons.org/publicdomain/zero/1.0/'
RECORDINGS = {
    'wind': dict(file='wind_trees_hq.mp3', author='SamuelGremaud', title='WIND - 1',
                 page='https://freesound.org/people/SamuelGremaud/sounds/547472/',
                 download='https://cdn.freesound.org/previews/547/547472_8031303-hq.mp3',
                 sha256='1e1a8479c6925c9ab35b9cf5f64c63fd448e284042da9a1d27cae5320d4bbc26'),
    'fabric': dict(file='tent_fabric_flapping_light_wind_hq.mp3', author='bmacphail',
                   title='Tent Fabric Flapping in Wind Ambient.wav',
                   page='https://freesound.org/people/bmacphail/sounds/569537/',
                   download='https://cdn.freesound.org/previews/569/569537_12816528-hq.mp3',
                   sha256='d1f8b022feaee421eb6a0b16754e90f1e0289bd4cf09253d6262ea6235ae3d95'),
}
# Start, duration, high-pass/low-pass knees, target RMS. One second is consumed by the loop crossfade.
EDITS = {
    'wind_low.wav': ('wind', 2.0, 20.0, 40.0, 3200.0, .080),
    'wind_high.wav': ('wind', .4, 19.0, 950.0, 8500.0, .055),
    # Later cloth section avoids the early isolated handling-like impulses.
    'windsock_fabric.wav': ('fabric', 24.0, 22.0, 150.0, 8500.0, .018),
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


def build():
    if np.__version__ != '2.4.6' or miniaudio.__version__ != '1.71':
        raise RuntimeError('Install exact tools/audio/requirements-recordings.txt versions')
    decoded = {}
    source_records = {}
    for key, source in RECORDINGS.items():
        path = SOURCES / source['file']
        if sha(path.read_bytes()) != source['sha256']:
            raise RuntimeError(f'Source checksum mismatch: {path}')
        stream = miniaudio.decode_file(str(path), output_format=miniaudio.SampleFormat.FLOAT32,
                                       nchannels=1, sample_rate=RATE)
        decoded[key] = np.asarray(stream.samples, dtype=np.float64)
        source_records[key] = dict(source, license='CC0-1.0', license_url=LICENSE_URL,
                                   retrieved='2026-10-19', format='public HQ MP3 preview; not the original WAV')
    outputs = {}
    entries = []
    for filename, (key, start, duration, low, high, target) in EDITS.items():
        x = decoded[key][round(start * RATE):round((start + duration) * RATE)].copy()
        if len(x) != round(duration * RATE):
            raise RuntimeError(f'Truncated source: {filename}')
        x -= np.mean(x)
        overlap = RATE
        phase = np.arange(overlap, dtype=np.float64) / overlap * np.pi / 2
        # Tail ends at the source head's next sample: the wrap has a real continuation.
        blend = x[-overlap:] * np.cos(phase) ** 2 + x[:overlap] * np.sin(phase) ** 2
        x = np.concatenate((x[overlap:-overlap], blend))
        freq = np.fft.rfftfreq(len(x), 1 / RATE)
        response = (1 - np.exp(-(freq / low) ** 4)) * np.exp(-(freq / high) ** 8)
        x = np.fft.irfft(np.fft.rfft(x) * response, n=len(x))
        x *= min(target / max(np.sqrt(np.mean(x*x)), 1e-12), .42 / max(np.max(np.abs(x)), 1e-12))
        blob, x = wav_bytes(x)
        seam = abs(float(x[-1] - x[0]))
        interior = float(np.quantile(np.abs(np.diff(x)), .99))
        if not np.isfinite(x).all() or seam > max(interior * 1.25, .001):
            raise RuntimeError(f'Unacceptable loop seam: {filename}')
        outputs[filename] = blob
        entries.append(dict(file=filename, source=key, sha256=sha(blob), sample_rate_hz=RATE,
                            channels=1, sample_count=len(x), duration_s=len(x)/RATE,
                            format='signed 16-bit PCM little-endian', loop=True,
                            edits=dict(start_s=start, source_duration_s=duration, crossfade_s=1,
                                       highpass_hz=low, lowpass_hz=high, target_rms=target, peak_cap=.42),
                            metrics=dict(rms=float(np.sqrt(np.mean(x*x))), peak=float(np.max(np.abs(x))),
                                         seam_step=seam, interior_step_p99=interior)))
    manifest = dict(format='openrc-recorded-wind v1', generator='tools/audio/import_wind_recordings.py',
                    dependencies=dict(numpy=np.__version__, miniaudio=miniaudio.__version__),
                    sources=source_records, assets=entries, decoded_pcm_bytes=sum(e['sample_count']*2 for e in entries))
    outputs['manifest.json'] = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    notice = 'CC0 1.0 Universal recordings, edited for OpenRC Simulator (AUD-14).\n'
    notice += 'These recordings are separate from the neighboring MIT synthetic sources.\n'
    for source in RECORDINGS.values():
        notice += f"\n{source['title']} by {source['author']}\n{source['page']}\n"
    notice += f'\nLicense: {LICENSE_URL}\nPublic HQ MP3 previews were used; original WAVs are not bundled.\n'
    outputs['LICENSE.txt'] = notice.encode()
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    outputs = build()
    if args.check:
        bad = [name for name, data in outputs.items() if not (OUTPUT/name).is_file() or (OUTPUT/name).read_bytes() != data]
        for name in EDITS:
            sidecar = OUTPUT / (name + '.import')
            if not sidecar.is_file() or not {'compress/mode=0', 'force/8_bit=false', 'edit/normalize=false', 'edit/trim=false'}.issubset(set(sidecar.read_text().splitlines())):
                bad.append(name + '.import (unmodified PCM required for the wrap guard)')
        if bad:
            raise SystemExit('Stale recorded wind outputs: ' + ', '.join(bad))
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for name, data in outputs.items():
            (OUTPUT/name).write_bytes(data)
    print(f"Recorded wind {'checked' if args.check else 'built'}: 3 PCM loops, {sum(len(v) for k,v in outputs.items() if k.endswith('.wav')):,} bytes")


if __name__ == '__main__':
    main()
