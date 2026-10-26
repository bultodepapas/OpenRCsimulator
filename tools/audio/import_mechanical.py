#!/usr/bin/env python3
"""AUD-16 reproducible edits of licensed RC servo and retract-mechanism recordings."""

import argparse
import hashlib
import io
import json
from pathlib import Path
import wave

import miniaudio
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "research/audio/AUD-16/recordings"
OUTPUT = ROOT / "app/assets/audio/mechanical"
CC0 = "https://creativecommons.org/publicdomain/zero/1.0/"
BY40 = "https://creativecommons.org/licenses/by/4.0/"

SOURCES_INFO = {
    "s3003_90": dict(file="futaba_s3003_90_cc0_original.wav",
        sha="0bae7f973d0aae87bf01ad252878950b8b36ab17da60aff53c55c7dbe51d1a4a",
        title="Futaba S3003, 90 degree movement", author="Joseph Sardin", model="Futaba S3003",
        page="https://lasonotheque.org/servomoteur-1-90-2-s2910.html",
        download="https://lasonotheque.org/UPLOAD/bwf-fr/2910.wav", license="CC0-1.0", license_url=CC0,
        format="Original mono 48 kHz / 24-bit WAV; source page identifies model and movement angle",
        recording="Joseph Sardin; SoundDevices MixPre-3 and Neumann KM184; studio recording",
        fit="Named standard Futaba RC servo movement; source page does not specify load or aircraft installation."),
    "s3003_180": dict(file="futaba_s3003_180_cc0_original.wav",
        sha="e7f48be365dfa28191824396fecec4245d91d06b45d82ede939ff7fff91cd366",
        title="Futaba S3003, 180 degree movement", author="Joseph Sardin", model="Futaba S3003",
        page="https://lasonotheque.org/servomoteur-1-180-1-s2911.html",
        download="https://lasonotheque.org/UPLOAD/bwf-fr/2911.wav", license="CC0-1.0", license_url=CC0,
        format="Original mono 48 kHz / 24-bit WAV; source page identifies model and movement angle",
        recording="Joseph Sardin; SoundDevices MixPre-3 and Neumann KM184; studio recording",
        fit="Named standard Futaba RC servo movement; source page does not specify load or aircraft installation."),
    "ts315_90": dict(file="t2m_ts315_90_cc0_original.wav",
        sha="4939980e094faf197aa675c57d1c6536c2aa18708fdda63979dedb6f61f9de51",
        title="T2M TS-315, large servo, 90 degree movement", author="Joseph Sardin", model="T2M TS-315",
        page="https://lasonotheque.org/servomoteur-2-90-2-s2920.html",
        download="https://lasonotheque.org/UPLOAD/bwf-fr/2920.wav", license="CC0-1.0", license_url=CC0,
        format="Original mono 48 kHz / 24-bit WAV; source page calls it a large servo and identifies movement angle",
        recording="Joseph Sardin; SoundDevices MixPre-3 and Neumann KM184; studio recording",
        fit="Named large RC servo used for high_torque simulation role. No torque rating or loaded high-torque sound is established."),
    "ts315_180": dict(file="t2m_ts315_180_cc0_original.wav",
        sha="6e6af155055bd46effaaef02e058c2bbdac5bf52c02475476bedd4668eeb2282",
        title="T2M TS-315, large servo, 180 degree movement", author="Joseph Sardin", model="T2M TS-315",
        page="https://lasonotheque.org/servomoteur-2-180-1-s2921.html",
        download="https://lasonotheque.org/UPLOAD/bwf-fr/2921.wav", license="CC0-1.0", license_url=CC0,
        format="Original mono 48 kHz / 24-bit WAV; source page calls it a large servo and identifies movement angle",
        recording="Joseph Sardin; SoundDevices MixPre-3 and Neumann KM184; studio recording",
        fit="Named large RC servo used for high_torque simulation role. No torque rating or loaded high-torque sound is established."),
    "air_disconnect": dict(file="release_air_pffft_hq_preview.mp3",
        sha="56ba199e5b6e90bc2d671b41af1e150f91e2db635315a6026299f1c2d0c9d5c6",
        title="release_air_pffft.wav", author="reg7783",
        page="https://freesound.org/people/reg7783/sounds/131302/",
        license="CC0-1.0", license_url=CC0,
        format="Freesound HQ MP3 preview; page metadata says original stereo 44.1 kHz / 16-bit WAV, 1.906 s",
        fit="Pneumatic nail-gun air-line disconnect, used only as a non-RC release-hiss proxy; not a retract cylinder recording."),
    "compressor_valve": dict(file="garage_air_compressor_releasing_pressure_hq_preview.mp3",
        sha="130c6497038ed3b1d04607c88e69a9c114b2e65b241035fbe48a1dd3efacda58",
        title="Garage air compressor releasing pressure HQ preview", author="j_soundeffects",
        page="https://freesound.org/people/j_soundeffects/sounds/847748/",
        license="CC-BY-4.0", license_url=BY40,
        format="Freesound HQ MP3 preview; page metadata says original stereo 48 kHz / 16-bit WAV, 25.792 s",
        fit="Small garage compressor pressure-release valve/escaping air, used as a non-RC valve proxy. Its automatic closing pop is not used as a retract lock."),
}

STD = dict(sample_rate_hz=44100, highpass_hz=120, lowpass_hz=18000,
           eq="Light low-frequency cleanup and gentle rolloff above 18 kHz",
           playback_pitch_reference=1.0, target_rms=0.05, peak_cap=0.62)
LARGE = dict(sample_rate_hz=44100, highpass_hz=120, lowpass_hz=18000,
             high_shelf_db=-2.0, high_shelf_hz=5500,
             eq="Gentle 2 dB broad upper-shelf cut above 5.5 kHz; natural-pitch source file",
             playback_pitch_reference=0.82, target_rms=0.05, peak_cap=0.62)
ASSETS = {}


def add(name, kind, role, segments, profile, fit, **edits):
    data = dict(profile)
    data.update(kind=kind, role=role, sources=segments, fit=fit)
    data.update(edits)
    ASSETS[name] = data


# The servo clips are distinct source movements; neither direction is identified in page metadata.
add("servo_standard_loop.wav", "loop", "standard servo movement bed",
    [{"source": "s3003_180", "start_s": 0.04, "end_s": 0.60}], STD,
    "Recorded Futaba S3003 travel phrase; repeated only during movement, not a continuous aircraft recording.",
    crossfade_s=0.10, target_rms=0.055)
add("servo_standard_start.wav", "oneshot", "standard servo movement onset",
    [{"source": "s3003_90", "start_s": 0.0, "end_s": 0.19}], STD,
    "Source-derived onset; direction is not identified by the recording metadata.",
    fade_in_s=0.003, fade_out_s=0.020)
add("servo_standard_start_02.wav", "oneshot", "standard servo movement onset variation 2",
    [{"source": "s3003_180", "start_s": 0.0, "end_s": 0.22}], STD,
    "Source-derived onset variation; direction is not identified by the recording metadata.",
    fade_in_s=0.003, fade_out_s=0.020)
add("servo_standard_stop.wav", "oneshot", "standard servo movement deceleration/tail",
    [{"source": "s3003_90", "start_s": 0.28, "end_s": 0.4597916667}], STD,
    "Source-derived motion tail; no isolated lock click is claimed.",
    fade_in_s=0.003, fade_out_s=0.030, target_rms=0.045)
add("servo_standard_stop_02.wav", "oneshot", "standard servo movement stop variation 2",
    [{"source": "s3003_180", "start_s": 0.52, "end_s": 0.690875}], STD,
    "S3003 movement tail includes a strong waveform transient near 0.62 s; it has not been audibly verified.",
    fade_in_s=0.003, fade_out_s=0.030, target_rms=0.050, peak_cap=0.68)

add("servo_high_torque_loop.wav", "loop", "high_torque simulation-role servo movement bed",
    [{"source": "ts315_180", "start_s": 0.02, "end_s": 0.70}], LARGE,
    "Recorded T2M TS-315 large-servo movement; used for high_torque role, but torque/load are not measured.",
    crossfade_s=0.12, target_rms=0.055)
add("servo_high_torque_start.wav", "oneshot", "large-servo movement onset",
    [{"source": "ts315_90", "start_s": 0.0, "end_s": 0.18}], LARGE,
    "Recorded T2M TS-315 onset used for high_torque role; torque/load are not measured.",
    fade_in_s=0.003, fade_out_s=0.020, target_rms=0.055)
add("servo_high_torque_start_02.wav", "oneshot", "large-servo movement onset variation 2",
    [{"source": "ts315_180", "start_s": 0.0, "end_s": 0.22}], LARGE,
    "Recorded T2M TS-315 onset variation used for high_torque role; torque/load are not measured.",
    fade_in_s=0.003, fade_out_s=0.020, target_rms=0.055)
add("servo_high_torque_stop.wav", "oneshot", "large-servo movement deceleration/tail",
    [{"source": "ts315_90", "start_s": 0.30, "end_s": 0.4278541667}], LARGE,
    "Recorded T2M TS-315 motion tail; no measured lock or torque-loaded stop is claimed.",
    fade_in_s=0.003, fade_out_s=0.025, target_rms=0.050)
add("servo_high_torque_stop_02.wav", "oneshot", "large-servo movement stop variation 2",
    [{"source": "ts315_180", "start_s": 0.58, "end_s": 0.7644791667}], LARGE,
    "Recorded T2M TS-315 motion tail; no measured lock or torque-loaded stop is claimed.",
    fade_in_s=0.003, fade_out_s=0.030, target_rms=0.050)

# The electric travel bed joins two original servo movements and crossfades its loop seam.
add("retract_electric_loop.wav", "loop", "electric retract travel sound bed proxy",
    [{"source": "ts315_90", "start_s": 0.03, "end_s": 0.39},
     {"source": "ts315_180", "start_s": 0.05, "end_s": 0.71}], LARGE,
    "Two source-derived movements from a named large RC servo form a repeating travel proxy. Not an electric retract recording or measured actuator tone.",
    join_crossfade_s=0.07, crossfade_s=0.12, target_rms=0.052)
add("retract_electric_start.wav", "oneshot", "electric retract movement onset proxy",
    [{"source": "ts315_180", "start_s": 0.0, "end_s": 0.20}], LARGE,
    "T2M TS-315 servo onset used as an authored electric-retract start proxy; not recorded on an electric retract.",
    fade_in_s=0.003, fade_out_s=0.020)
add("retract_electric_lock.wav", "oneshot", "electric retract endpoint cue proxy",
    [{"source": "s3003_180", "start_s": 0.52, "end_s": 0.690875}], STD,
    "RC servo stop transient, authored endpoint cue, not measured retract lock.",
    fade_in_s=0.003, fade_out_s=0.030, target_rms=0.050, peak_cap=0.68)

# Pneumatic hiss/valve textures come from non-RC pressure-release recordings.
PNEU = dict(sample_rate_hz=22050, highpass_hz=90, lowpass_hz=9500,
            eq="Low-frequency cleanup and rolloff above 9.5 kHz",
            playback_pitch_reference=1.0, target_rms=0.04, peak_cap=0.50)
add("retract_pneumatic_loop.wav", "loop", "pneumatic continuous-air travel texture proxy",
    [{"source": "compressor_valve", "start_s": 23.10, "end_s": 24.10}], PNEU,
    "Stable compressor pressure-release segment used as non-RC steady-air texture; not a retract-cylinder recording.",
    crossfade_s=0.22, target_rms=0.030, peak_cap=0.48)
add("retract_pneumatic_hiss.wav", "oneshot", "pneumatic retract air-hiss proxy",
    [{"source": "air_disconnect", "start_s": 0.20, "end_s": 0.76}], PNEU,
    "Pneumatic nail-gun line-disconnect air burst used as non-RC hiss proxy; not a retract-cylinder recording.",
    fade_in_s=0.004, fade_out_s=0.035, target_rms=0.060, peak_cap=0.62)
add("retract_pneumatic_valve.wav", "oneshot", "pneumatic retract valve-actuation texture proxy",
    [{"source": "compressor_valve", "start_s": 15.04, "end_s": 15.70}], PNEU,
    "Pressure-release onset from a small garage compressor valve; non-RC proxy, not a retract spool-valve recording.",
    fade_in_s=0.004, fade_out_s=0.035, target_rms=0.042)
add("retract_pneumatic_lock.wav", "oneshot", "pneumatic retract endpoint cue proxy",
    [{"source": "s3003_180", "start_s": 0.52, "end_s": 0.690875}], STD,
    "RC servo stop transient, authored endpoint cue, not measured retract lock.",
    fade_in_s=0.003, fade_out_s=0.030, target_rms=0.050, peak_cap=0.68)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def decode_sources():
    if np.__version__ != "2.4.6" or miniaudio.__version__ != "1.71":
        raise RuntimeError("Install exact tools/audio/requirements-recordings.txt versions")
    records = {}
    for key, source in SOURCES_INFO.items():
        path = SOURCES / source["file"]
        raw = path.read_bytes()
        digest = sha(raw)
        if digest != source["sha"]:
            raise RuntimeError(f"Source checksum mismatch for {path}: {digest}")
        records[key] = dict(source, sha256=digest, file_bytes=len(raw),
                            source_file=str(path.relative_to(ROOT)).replace("\\", "/"),
                            retrieved="2026-10-25")
    return records


def _load(cache, key, rate):
    token = (key, rate)
    if token not in cache:
        path = SOURCES / SOURCES_INFO[key]["file"]
        decoded = miniaudio.decode_file(str(path), output_format=miniaudio.SampleFormat.FLOAT32,
                                        nchannels=1, sample_rate=rate)
        cache[token] = np.asarray(decoded.samples, dtype=np.float64)
    return cache[token]


def _filter(samples, rate, edit):
    samples = samples - np.mean(samples)
    freq = np.fft.rfftfreq(len(samples), 1.0 / rate)
    response = 1.0 - np.exp(-((freq / edit["highpass_hz"]) ** 4))
    response *= np.exp(-((freq / edit["lowpass_hz"]) ** 8))
    shelf_db = float(edit.get("high_shelf_db", 0.0))
    if shelf_db:
        knee = float(edit["high_shelf_hz"])
        shape = 1.0 / (1.0 + np.exp(-(freq - knee) / max(knee * 0.24, 1.0)))
        response *= 10.0 ** ((shelf_db * shape) / 20.0)
    return np.fft.irfft(np.fft.rfft(samples) * response, n=len(samples))


def _crossfade(left, right, count):
    if count <= 0 or count >= min(len(left), len(right)):
        raise RuntimeError("Crossfade must be positive and shorter than each source segment")
    phase = np.linspace(0.0, np.pi / 2.0, count, endpoint=True)
    mix = left[-count:] * np.cos(phase) ** 2 + right[:count] * np.sin(phase) ** 2
    return np.concatenate((left[:-count], mix, right[count:]))


def _segment(cache, segment, rate, edit):
    source = _load(cache, segment["source"], rate)
    start = round(segment["start_s"] * rate)
    end = round(segment["end_s"] * rate)
    if start < 0 or end <= start or end > len(source):
        raise RuntimeError(f"Invalid segment {segment}; decoded duration is {len(source) / rate:.6f}s")
    samples = _filter(source[start:end].copy(), rate, edit)
    return samples, dict(source=segment["source"], source_start_s=segment["start_s"],
                         source_end_s=segment["end_s"], source_start_sample=start,
                         source_end_sample_exclusive=end, decoded_rate_hz=rate,
                         source_segment_samples=end - start)


def _fade(samples, rate, in_s, out_s):
    samples = samples.copy()
    fade_in = min(round(in_s * rate), len(samples) // 3)
    fade_out = min(round(out_s * rate), len(samples) // 3)
    if fade_in:
        samples[:fade_in] *= np.sin(np.linspace(0, np.pi / 2, fade_in)) ** 2
    if fade_out:
        samples[-fade_out:] *= np.cos(np.linspace(0, np.pi / 2, fade_out)) ** 2
    return samples


def _normalize(samples, target_rms, peak_cap):
    rms = max(float(np.sqrt(np.mean(samples * samples))), 1e-12)
    peak = max(float(np.max(np.abs(samples))), 1e-12)
    samples *= min(target_rms / rms, peak_cap / peak)
    return samples


def _build_one(cache, name, edit):
    rate = edit["sample_rate_hz"]
    segments, segment_records = [], []
    for segment in edit["sources"]:
        clip, record = _segment(cache, segment, rate, edit)
        segments.append(clip)
        segment_records.append(record)
    samples = segments[0]
    if len(segments) > 1:
        join = round(edit["join_crossfade_s"] * rate)
        for segment in segments[1:]:
            samples = _crossfade(samples, segment, join)
    source_samples = len(samples)
    loop_xfade = 0
    loop_phase_offset = 0
    if edit["kind"] == "loop":
        loop_xfade = round(edit["crossfade_s"] * rate)
        if loop_xfade <= 0 or 2 * loop_xfade >= len(samples):
            raise RuntimeError(f"Loop crossfade does not fit in {name}")
        # Choose a nearby waveform phase with a low sample-to-sample step at the
        # wrap. The runtime still applies the 64-frame repeated-endpoint guard.
        seek = round(min(edit.get("phase_seek_s", 0.10), 0.10) * rate)
        boundary_steps = np.abs(samples[loop_xfade:loop_xfade + seek]
                                - samples[loop_xfade - 1:loop_xfade + seek - 1])
        if len(boundary_steps):
            loop_phase_offset = int(np.argmin(boundary_steps))
            samples = np.roll(samples, -loop_phase_offset)
        phase = np.linspace(0, np.pi / 2, loop_xfade)
        mixed = samples[-loop_xfade:] * np.cos(phase) ** 2 + samples[:loop_xfade] * np.sin(phase) ** 2
        samples = np.concatenate((samples[loop_xfade:-loop_xfade], mixed))
    else:
        samples = _fade(samples, rate, edit["fade_in_s"], edit["fade_out_s"])
    samples = _normalize(samples, edit["target_rms"], edit["peak_cap"])
    pcm = np.rint(np.clip(samples, -0.999969, 0.999969) * 32767).astype("<i2")
    f = pcm.astype(np.float64) / 32768.0
    stream = io.BytesIO()
    with wave.open(stream, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(pcm.tobytes())
    blob = stream.getvalue()
    rms = float(np.sqrt(np.mean(f * f)))
    peak = float(np.max(np.abs(f)))
    p99 = float(np.quantile(np.abs(np.diff(f)), 0.99)) if len(f) > 1 else 0.0
    seam = abs(float(f[-1] - f[0])) if edit["kind"] == "loop" else None
    if edit["kind"] == "loop" and seam > max(p99 * 1.25, 0.001):
        raise RuntimeError(f"Loop seam exceeds interior-step gate for {name}: {seam:.6f}")
    entry = dict(file=name, sha256=sha(blob), role=edit["role"], kind=edit["kind"],
        sample_rate_hz=rate, channels=1, sample_count=len(pcm), duration_s=len(pcm) / rate,
        format="signed 16-bit PCM little-endian", loop=edit["kind"] == "loop",
        playback_pitch_reference=edit["playback_pitch_reference"], source_segments=segment_records,
        edit={k: v for k, v in edit.items() if k not in {"sources", "role", "kind", "fit"}},
        fit_limitations=edit["fit"],
        metrics=dict(rms=rms, peak=peak, seam_step=seam, interior_step_p99=p99,
                     source_samples_before_loop_edit=source_samples,
                     loop_phase_offset_samples=loop_phase_offset,
                     loop_crossfade_samples=loop_xfade,
                     loop_crossfade_s=loop_xfade / rate if loop_xfade else 0.0))
    return blob, entry


def build(cache, source_records):
    outputs, entries = {}, []
    for name, edit in ASSETS.items():
        blob, entry = _build_one(cache, name, edit)
        outputs[name] = blob
        entries.append(entry)
    manifest = dict(format="openrc-mechanical-audio-v1", generator="tools/audio/import_mechanical.py",
        dependencies=dict(numpy=np.__version__, miniaudio=miniaudio.__version__),
        listening_status="No direct audition was performed during analysis or editing; human listening acceptance remains required.",
        playback_contract=dict(loop_guard_frames_required=64, guard_frames_embedded_in_wav=0,
            guard_note="Runtime must provide the repository 64-frame repeated-endpoint wrap guard.",
            profiles=dict(servo_standard=dict(reference_pitch=1.0),
                          servo_high_torque=dict(reference_pitch=0.82,
                              source_note="Natural-pitch TS-315 source; runtime pitch is an authored profile choice, not a measured hardware frequency."))),
        sources=source_records, assets=entries,
        decoded_pcm_bytes=sum(e["sample_count"] * 2 for e in entries))
    outputs["manifest.json"] = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    outputs["LICENSE.txt"] = (
        "AUD-16 mechanical sound bank source and license notice.\n\n"
        "Futaba S3003 and T2M TS-315 servo recordings by Joseph Sardin, LaSonotheque, are CC0 1.0. "
        "Their source pages explicitly allow commercial use, editing and redistribution.\n"
        "https://creativecommons.org/publicdomain/zero/1.0/\n"
        "The T2M TS-315 is described by its source page as a large servo; no torque value or loaded high-torque acoustic result is claimed.\n\n"
        "Freesound release_air_pffft.wav by reg7783 is CC0 1.0. Retained file is the HQ MP3 preview, not login-gated original WAV.\n"
        "https://freesound.org/people/reg7783/sounds/131302/\n"
        "Source is a pneumatic nail-gun air-line disconnect; it is used only as a non-RC hiss proxy.\n\n"
        "Garage air compressor releasing pressure by j_soundeffects is CC-BY-4.0. Retained file is the HQ MP3 preview, not login-gated original WAV.\n"
        "https://creativecommons.org/licenses/by/4.0/\n"
        "https://freesound.org/people/j_soundeffects/sounds/847748/\n"
        "Attribution: j_soundeffects, Garage air compressor releasing pressure, Freesound. "
        "This non-RC compressor valve is used as an air/valve proxy; its automatic closing pop is not used as a retract lock.\n\n"
        "OpenRC Simulator edits: mono conversion, resampling, trimming, filtering/EQ, level changes, fades and loop crossfades. "
        "Source URLs and exact edits for each derivative are in the accompanying manifest.json.\n\n"
        "Servo recordings used as retract start/end cues remain servo recordings and do not establish measured retract motor, spool-valve, cylinder or lock sounds.\n"
        "No direct audition was performed; boundaries were selected from source metadata and waveform/spectral analysis. Human listening acceptance remains required.\n"
    ).encode()
    return outputs


def sidecars(write):
    required = {"force/8_bit=false", "edit/normalize=false", "edit/trim=false", "compress/mode=0"}
    missing, stale = [], []
    for name in ASSETS:
        path = OUTPUT / f"{name}.import"
        if not path.is_file():
            missing.append(path.name)
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        settings = {line.split("=", 1)[0]: line for line in lines if "=" in line}
        if write:
            settings["compress/mode"] = "compress/mode=0"
            keys = {line.split("=", 1)[0] for line in lines if "=" in line}
            lines = [settings.get(line.split("=", 1)[0], line) if "=" in line else line for line in lines]
            if "compress/mode" not in keys:
                lines.append("compress/mode=0")
            path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        if not required.issubset(set(lines)):
            stale.append(path.name)
    return missing, stale


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--fix-import-settings", action="store_true",
                        help="set existing WAV sidecars to lossless PCM import")
    args = parser.parse_args()
    source_records = decode_sources()
    outputs = build({}, source_records)
    if args.check:
        stale = [name for name, data in outputs.items()
                 if not (OUTPUT / name).is_file() or (OUTPUT / name).read_bytes() != data]
        missing, bad = sidecars(False)
        if missing:
            stale.append("missing Godot WAV sidecars: " + ", ".join(missing))
        if bad:
            stale.append("non-lossless Godot WAV sidecars: " + ", ".join(bad))
        if stale:
            raise SystemExit("Stale mechanical audio outputs: " + "; ".join(stale))
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for name, data in outputs.items():
            (OUTPUT / name).write_bytes(data)
        missing, bad = sidecars(args.fix_import_settings)
        if missing:
            print("Godot WAV sidecars missing; run editor import, then --fix-import-settings:")
            for name in missing:
                print("  " + name)
        if bad:
            raise SystemExit("Non-lossless Godot WAV sidecars: " + ", ".join(bad))
    manifest = json.loads(outputs["manifest.json"])
    print(f"Mechanical audio {'checked' if args.check else 'built'}: {len(ASSETS)} cues, "
          f"{sum(len(outputs[n]) for n in ASSETS):,} WAV bytes, {manifest['decoded_pcm_bytes']:,} PCM bytes")


if __name__ == "__main__":
    main()
