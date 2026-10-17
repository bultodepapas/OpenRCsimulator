#!/usr/bin/env python3
"""Signal-only beat/onset analysis and continuous Uprising cue renderer."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from scipy.ndimage import gaussian_filter1d, median_filter
from scipy.signal import find_peaks, stft


ANALYSIS_RATE = 22050
HOP = 220  # 9.98 ms onset grid
N_FFT = 2048
TARGET_BPM = 90.0
ACTION_CUTS = [
    {"time_s": 0.0, "name": "formation opens"},
    {"time_s": 7.0, "name": "formation to jet pass"},
    {"time_s": 11.0, "name": "jet to stik-bank"},
    {"time_s": 15.0, "name": "stik-bank to extra roll"},
    {"time_s": 19.0, "name": "extra roll to Mustang pass"},
    {"time_s": 22.0, "name": "Mustang pass to Turbo"},
    {"time_s": 25.0, "name": "Turbo to helicopter"},
    {"time_s": 30.0, "name": "helicopter to Bisonte"},
    {"time_s": 34.0, "name": "Bisonte to monster car"},
    {"time_s": 38.0, "name": "storm begins"},
    {"time_s": 41.0, "name": "wind begins"},
    {"time_s": 45.0, "name": "controls begin"},
    {"time_s": 49.0, "name": "approach begins"},
    {"time_s": 50.45, "name": "aftermath begins"},
    {"time_s": 51.5, "name": "repair report begins"},
    {"time_s": 55.0, "name": "restart begins"},
    {"time_s": 57.0, "name": "end card begins"},
    {"time_s": 60.0, "name": "trailer ends"},
]


def run(args: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def decode(source: Path, ffmpeg: Path) -> np.ndarray:
    result = run([
        str(ffmpeg), "-hide_banner", "-loglevel", "error", "-i", str(source),
        "-vn", "-f", "f32le", "-ac", "1", "-ar", str(ANALYSIS_RATE), "pipe:1",
    ])
    return np.frombuffer(result.stdout, dtype="<f4").copy()


def compute_features(samples: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    _, times, z = stft(
        samples, fs=ANALYSIS_RATE, window="hann", nperseg=N_FFT,
        noverlap=N_FFT - HOP, boundary="zeros", padded=False,
    )
    mag = np.abs(z)
    # Positive spectral change after log compression emphasizes attacks and
    # reduces the influence of the sustained orchestral bed.
    log_mag = np.log1p(mag * 500.0)
    positive = np.maximum(np.diff(log_mag, axis=1), 0.0)
    flux = np.sqrt(np.mean(positive ** 2, axis=0))
    flux_times = times[1:]
    baseline = median_filter(flux, size=101, mode="nearest")
    onset = np.maximum(flux - baseline, 0.0)
    onset = gaussian_filter1d(onset, sigma=1.2)
    scale = np.percentile(onset, 99.5)
    normalized = onset / max(float(scale), 1e-10)
    return flux_times, onset, normalized


def tempo_candidates(times: np.ndarray, env: np.ndarray, start: float, end: float) -> list[dict]:
    mask = (times >= start) & (times < end)
    region = env[mask].astype(np.float64)
    if len(region) < 100:
        return []
    region -= float(np.mean(region))
    # At ~100 Hz, this lag range corresponds to 60–180 BPM.
    ac = np.correlate(region, region, mode="full")[len(region) - 1:]
    lags = np.arange(len(ac), dtype=np.float64) * HOP / ANALYSIS_RATE
    valid = (lags >= 60.0 / 180.0) & (lags <= 60.0 / 60.0)
    ids = np.flatnonzero(valid)
    vals = ac[ids]
    peaks, _ = find_peaks(vals, distance=max(1, int(0.045 * ANALYSIS_RATE / HOP)))
    order = peaks[np.argsort(vals[peaks])[::-1]][:6]
    out = []
    for k in order:
        lag_i = ids[k]
        lag_s = float(lags[lag_i])
        bpm = 60.0 / lag_s
        # Normalize by zero-lag energy and the local background in the legal range.
        score = float(ac[lag_i] / max(ac[0], 1e-12))
        out.append({"bpm": round(bpm, 3), "period_s": round(lag_s, 5), "autocorrelation_score": round(score, 5)})
    return out


def grid_fit(times: np.ndarray, onset: np.ndarray, start: float, end: float, period: float) -> dict:
    mask = (times >= start) & (times < end)
    t = times[mask]
    s = onset[mask]
    if len(s) == 0:
        return {"phase_s": 0.0, "score": 0.0, "accent_histogram": []}
    phase_candidates = np.arange(0.0, period, HOP / ANALYSIS_RATE)
    radius = 0.035
    grid_scores = []
    phase_stats = []
    for phase in phase_candidates:
        beats = np.arange(start + phase, end, period)
        vals = []
        for beat in beats:
            near = np.abs(t - beat) <= radius
            vals.append(float(np.max(s[near])) if np.any(near) else 0.0)
        grid_scores.append(float(np.mean(vals)) if vals else 0.0)
        phase_stats.append(vals)
    best_i = int(np.argmax(grid_scores))
    phase = float(phase_candidates[best_i])
    beat_values = phase_stats[best_i]
    # Compare the four beat positions to infer which phase has the strongest
    # recurring accent. This is meter inference, not guaranteed downbeat truth.
    accents = [float(np.mean(beat_values[i::4])) if beat_values[i::4] else 0.0 for i in range(4)]
    accent_best = int(np.argmax(accents))
    return {
        "phase_s": round(phase, 5),
        "score": round(grid_scores[best_i], 7),
        "accent_histogram": [round(x, 7) for x in accents],
        "strongest_recurring_beat_slot": accent_best,
        "phase_sharpness_ratio": round(float(grid_scores[best_i] / max(np.median(grid_scores), 1e-12)), 4),
    }


def nearest_onset(times: np.ndarray, onset: np.ndarray, target: float, radius: float = 0.12) -> dict:
    mask = (times >= target - radius) & (times <= target + radius)
    if not np.any(mask):
        return {"time_s": None, "offset_s": None, "strength": 0.0}
    indices = np.flatnonzero(mask)
    idx = indices[int(np.argmax(onset[mask]))]
    return {
        "time_s": round(float(times[idx]), 4),
        "offset_s": round(float(times[idx] - target), 4),
        "strength": round(float(onset[idx]), 7),
    }


def rms_db(samples: np.ndarray) -> float:
    return float(20.0 * np.log10(max(float(np.sqrt(np.mean(np.square(samples, dtype=np.float64)))), 1e-12)))


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as src:
        for chunk in iter(lambda: src.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def analyze(source: Path, ffmpeg: Path, out_dir: Path) -> dict:
    samples = decode(source, ffmpeg)
    duration = len(samples) / ANALYSIS_RATE
    times, raw_onset, onset = compute_features(samples)
    ranges = [(0, 31), (110, 127), (127, 187), (187, 205)]
    tempo_by_range = {
        f"{a}-{b}s": tempo_candidates(times, onset, a, min(float(b), duration))
        for a, b in ranges
    }
    backend = tempo_by_range["127-187s"]
    selected = backend[0] if backend else {"bpm": TARGET_BPM, "period_s": 0.5, "autocorrelation_score": 0}
    measured_bpm = float(selected["bpm"])
    beat_period = 60.0 / measured_bpm
    fitted = grid_fit(times, onset, 127.0, min(187.0, duration), beat_period)
    # Open at the strongest measured transient just before the backend begins.
    beat_phase = fitted["phase_s"]
    beat_origin_src = 127.0 + beat_phase
    start_mask = (times >= 126.5) & (times <= 127.1)
    start_indices = np.flatnonzero(start_mask)
    if not len(start_indices):
        raise RuntimeError("no eligible opening-onset window in source")
    start_idx = start_indices[int(np.argmax(onset[start_mask]))]
    start_src = float(times[start_idx])
    opening_onset = {
        "time_s": round(start_src, 5),
        "strength": round(float(onset[start_idx]), 7),
        "selection_window_s": [126.5, 127.1],
        "selection_method": "maximum positive spectral-flux onset in the selected opening window",
    }
    tempo_ratio = TARGET_BPM / measured_bpm
    source_duration = 60.0 * tempo_ratio
    end_src = start_src + source_duration
    output_beat_period = beat_period / tempo_ratio
    output_sixteenth_period = output_beat_period / 4.0
    beat_origin_out = (beat_origin_src - start_src) / tempo_ratio
    local_peak_indices, _ = find_peaks(onset, distance=max(1, int(0.045 * ANALYSIS_RATE / HOP)))
    cue_peak_indices = local_peak_indices[(times[local_peak_indices] >= start_src) & (times[local_peak_indices] < end_src)]
    onset_peak_strength_floor = float(np.median(onset[cue_peak_indices])) if len(cue_peak_indices) else 0.0

    cuts = []
    for cut in ACTION_CUTS:
        output_t = float(cut["time_s"])
        nearest_sixteenth = beat_origin_out + round((output_t - beat_origin_out) / output_sixteenth_period) * output_sixteenth_period
        source_t = start_src + nearest_sixteenth * tempo_ratio
        onset_at = nearest_onset(times, onset, source_t) if source_t < end_src else {"time_s": None, "offset_s": None, "strength": 0.0}
        if onset_at["time_s"] is not None and output_t < 60.0:
            onset_at["output_time_s"] = round((onset_at["time_s"] - start_src) / tempo_ratio, 4)
        if output_t < 60.0:
            cut_source_t = start_src + output_t * tempo_ratio
            local_candidates = local_peak_indices[(times[local_peak_indices] >= cut_source_t - 0.25) & (times[local_peak_indices] <= cut_source_t + 0.25)]
            if len(local_candidates):
                nearest_idx = int(local_candidates[np.argmin(np.abs(times[local_candidates] - cut_source_t))])
                nearest_time = float(times[nearest_idx])
                nearest_output_time = (nearest_time - start_src) / tempo_ratio
                nearest_cut_peak = {
                    "time_s": round(nearest_time, 4),
                    "output_time_s": round(nearest_output_time, 4),
                    "residual_from_cut_s": round(nearest_output_time - output_t, 4),
                    "strength": round(float(onset[nearest_idx]), 7),
                    "above_cue_median_local_peak_strength": bool(onset[nearest_idx] >= onset_peak_strength_floor),
                }
            else:
                nearest_cut_peak = {"time_s": None, "output_time_s": None, "residual_from_cut_s": None, "strength": 0.0, "above_cue_median_local_peak_strength": False}
            local_candidates = local_candidates[onset[local_candidates] >= onset_peak_strength_floor]
            if len(local_candidates):
                detected_idx = int(local_candidates[np.argmin(np.abs(times[local_candidates] - cut_source_t))])
                detected_time = float(times[detected_idx])
                detected_output_time = (detected_time - start_src) / tempo_ratio
                cut_onset = {
                    "time_s": round(detected_time, 4),
                    "offset_s": round(detected_time - cut_source_t, 4),
                    "strength": round(float(onset[detected_idx]), 7),
                    "output_time_s": round(detected_output_time, 4),
                    "residual_from_cut_s": round(detected_output_time - output_t, 4),
                }
            else:
                cut_onset = {"time_s": None, "offset_s": None, "strength": 0.0, "output_time_s": None, "residual_from_cut_s": None}
        else:
            nearest_cut_peak = {"time_s": None, "output_time_s": None, "residual_from_cut_s": None, "strength": 0.0, "above_cue_median_local_peak_strength": False}
            cut_onset = {"time_s": None, "offset_s": None, "strength": 0.0, "output_time_s": None, "residual_from_cut_s": None}
        cuts.append({
            **cut,
            "nearest_measured_grid_sixteenth_output_s": round(nearest_sixteenth, 4),
            "cut_offset_from_grid_s": round(output_t - nearest_sixteenth, 4),
            "corresponding_source_grid_time_s": round(source_t, 4),
            "nearest_source_onset": onset_at,
            "nearest_local_peak_to_cut": nearest_cut_peak,
            "nearest_detected_onset_to_cut": cut_onset,
        })

    # Relative short-time RMS confirms there is no quiet opening in the
    # proposed continuous cue; report 1s values on the stretched output grid.
    per_second = []
    for sec in range(60):
        a = int((start_src + sec * tempo_ratio) * ANALYSIS_RATE)
        b = int((start_src + (sec + 1) * tempo_ratio) * ANALYSIS_RATE)
        per_second.append({"output_second": sec, "source_window_s": [round(start_src + sec * tempo_ratio, 3), round(start_src + (sec + 1) * tempo_ratio, 3)], "rms_dbfs": round(rms_db(samples[a:b]), 2)})

    per_half_second = []
    for half in range(120):
        out_start = half * 0.5
        a = int((start_src + out_start * tempo_ratio) * ANALYSIS_RATE)
        b = int((start_src + (out_start + 0.5) * tempo_ratio) * ANALYSIS_RATE)
        per_half_second.append({"output_window_s": [round(out_start, 2), round(out_start + 0.5, 2)], "rms_dbfs": round(rms_db(samples[a:b]), 2)})

    per_quarter_second = []
    for quarter in range(240):
        out_start = quarter * 0.25
        a = int((start_src + out_start * tempo_ratio) * ANALYSIS_RATE)
        b = int((start_src + (out_start + 0.25) * tempo_ratio) * ANALYSIS_RATE)
        per_quarter_second.append({"output_window_s": [round(out_start, 2), round(out_start + 0.25, 2)], "rms_dbfs": round(rms_db(samples[a:b]), 2)})

    cut_offsets = [abs(c["cut_offset_from_grid_s"]) for c in cuts]
    onset_offsets = [abs(c["nearest_source_onset"]["offset_s"]) for c in cuts if c["nearest_source_onset"]["offset_s"] is not None]
    cut_onsets = [c for c in cuts if c["time_s"] < 60.0 and c["nearest_local_peak_to_cut"]["residual_from_cut_s"] is not None]
    cut_onset_residuals = [c["nearest_local_peak_to_cut"]["residual_from_cut_s"] for c in cut_onsets]
    actual_cut_onset_table = [
        {
            "cut_name": c["name"],
            "cut_time_s": c["time_s"],
            "nearest_peak_time_output_s": c["nearest_local_peak_to_cut"]["output_time_s"],
            "nearest_peak_minus_cut_s": c["nearest_local_peak_to_cut"]["residual_from_cut_s"],
            "nearest_peak_strength": c["nearest_local_peak_to_cut"]["strength"],
            "nearest_peak_above_cue_median": c["nearest_local_peak_to_cut"]["above_cue_median_local_peak_strength"],
            "grid_selected_peak_time_output_s": c["nearest_source_onset"].get("output_time_s"),
            "grid_selected_peak_minus_cut_s": round(c["nearest_source_onset"]["output_time_s"] - c["time_s"], 4) if c["nearest_source_onset"].get("output_time_s") is not None else None,
            "grid_selected_peak_strength": c["nearest_source_onset"]["strength"],
        }
        for c in cut_onsets
    ]
    alignment_summary = {
        "music_grid_subdivision_s": round(output_sixteenth_period, 6),
        "cut_to_grid_mean_abs_residual_s": round(float(np.mean(cut_offsets)), 5),
        "cut_to_grid_max_abs_residual_s": round(float(np.max(cut_offsets)), 5),
        "measured_onset_matches": len(onset_offsets),
        "action_cut_count_excluding_trailer_end": sum(1 for c in cuts if c["time_s"] < 60.0),
        "onset_to_grid_median_abs_residual_s": round(float(np.median(onset_offsets)), 5) if onset_offsets else None,
        "onset_to_grid_max_abs_residual_s": round(float(np.max(onset_offsets)), 5) if onset_offsets else None,
        "phase_sharpness_ratio": fitted["phase_sharpness_ratio"],
        "interpretation": "Onset residuals use the strongest positive spectral-flux peak within ±120 ms of each expected sixteenth-grid point; the grid subdivision and residual do not prove perceptual downbeats or subjective sync quality."
    }

    # The continuous source passage retains the measured opening transient and
    # stays ahead of the original outro fade; short RMS windows expose gaps.
    result = {
        "source": str(source),
        "source_sha256": sha256(source),
        "source_duration_s_measured": round(duration, 6),
        "analysis": {
            "rate_hz": ANALYSIS_RATE,
            "hop_s": round(HOP / ANALYSIS_RATE, 6),
            "method": "positive spectral flux from 2048-sample Hann STFT, log-compressed magnitudes, 101-frame median baseline subtraction; beat candidates from onset-envelope autocorrelation over 60–180 BPM; beat phase from maximizing onset energy within ±35 ms of predicted beats. Sixteenth grid is a mathematical subdivision of the estimated pulse, not evidence that every subdivision is an audible hit.",
            "tempo_candidates_by_source_range": tempo_by_range,
            "backend_grid_fit_127_187": fitted,
            "estimated_source_bpm": round(measured_bpm, 4),
            "selected_target_bpm": TARGET_BPM,
            "tempo_ratio": round(tempo_ratio, 8),
            "tempo_adjustment_percent": round((tempo_ratio - 1.0) * 100.0, 4),
            "estimated_beat_phase_source_s_mod_period": beat_phase,
            "beat_grid_source_origin_s": round(beat_origin_src, 5),
            "beat_grid_phase_sharpness_ratio": fitted["phase_sharpness_ratio"],
            "action_alignment_summary": alignment_summary,
            "actual_cut_to_detected_onset": {
                "search_radius_s": 0.25,
        "local_peak_strength_floor": round(onset_peak_strength_floor, 7),
                "median_abs_residual_s": round(float(np.median(np.abs(cut_onset_residuals))), 5) if cut_onset_residuals else None,
                "max_abs_residual_s": round(float(np.max(np.abs(cut_onset_residuals))), 5) if cut_onset_residuals else None,
                "method": "For each non-terminal action cut, report the temporally nearest local positive spectral-flux peak within ±250 ms, with its strength and whether it exceeds the cue-median peak floor. Also include the independent strongest peak within ±120 ms of the estimated sixteenth grid. Residuals are output onset time minus action cut time; these measured events are separate from the beat-grid confidence estimate.",
                "table": actual_cut_onset_table,
            },
            "phase_confidence": "Signal-only estimate; sharpness ratio is modest and 120.273 BPM is a secondary autocorrelation candidate. Half/double-time and competing rhythmic subdivisions cannot be resolved without listening."
        },
        "cue": {
            "source_start_s": round(start_src, 6),
            "source_end_s": round(end_src, 6),
            "source_duration_s": round(source_duration, 6),
            "output_duration_s": 60.0,
            "output_bpm": TARGET_BPM,
            "method": "One continuous source interval beginning on the measured opening transient; mild pitch-preserving FFmpeg atempo targets 90 BPM from the measured backend pulse. No source skips, joins, or gaps. Limiter protects the PCM master from source MP3 overs; only the documented 8ms startup de-click and final one-beat fade are applied.",
            "fade_in_s": 0.008,
            "fade_in_curve": "linear",
            "fade_out_start_s": 59.333333,
            "fade_out_duration_s": 0.666667,
            "fade_out_curve": "linear",
            "opening_source_onset": opening_onset,
            "source_end_margin_before_original_outro_fade_s": round(196.0 - end_src, 4),
            "first_second_rms_dbfs": per_second[0]["rms_dbfs"],
            "last_second_rms_dbfs": per_second[-1]["rms_dbfs"],
            "per_second_rms": per_second,
            "per_half_second_rms": per_half_second,
            "per_quarter_second_rms": per_quarter_second,
            "action_cut_alignment": cuts
        },
        "audition_status": "Not auditioned: no audio-input capability. Report is signal-only."
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "analysis.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(17, 8), sharex=True)
    # 100 ms RMS energy envelope.
    win = int(0.1 * ANALYSIS_RATE)
    trimmed = samples[: len(samples) // win * win].reshape(-1, win)
    env_rms = np.sqrt(np.mean(trimmed.astype(np.float64) ** 2, axis=1))
    env_t = (np.arange(len(env_rms)) + 0.5) * 0.1
    ax1.plot(env_t, 20 * np.log10(np.maximum(env_rms, 1e-7)), lw=0.7)
    ax1.set_ylabel("100 ms RMS dBFS")
    ax1.set_ylim(-55, 0)
    ax1.axvspan(start_src, end_src, color="orange", alpha=0.15, label="candidate continuous cue")
    ax1.legend(loc="upper right")
    ax2.plot(times, onset, lw=0.6)
    ax2.set_ylabel("positive spectral flux")
    ax2.set_xlabel("Uprising source time (s)")
    ax2.axvspan(start_src, end_src, color="orange", alpha=0.15)
    for cut in cuts:
        ax2.axvline(cut["corresponding_source_grid_time_s"], color="crimson" if cut["name"] in {"formation opens", "storm begins", "aftermath begins", "end card begins"} else "gray", lw=0.5, alpha=0.6)
    ax2.grid(True, alpha=0.2)
    fig.tight_layout()
    fig.savefig(out_dir / "source-onsets-and-cue.png", dpi=140)
    plt.close(fig)
    print(json.dumps({"analysis_json": str(out_dir / "analysis.json"), "plot": str(out_dir / "source-onsets-and-cue.png"), "cue_start_s": start_src, "cue_end_s": end_src, "measured_bpm": measured_bpm, "tempo_ratio": tempo_ratio}, indent=2))
    return result


def render(source: Path, ffmpeg: Path, output: Path, analysis: dict) -> None:
    start = float(analysis["cue"]["source_start_s"])
    source_duration = float(analysis["cue"]["source_duration_s"])
    ratio = float(analysis["analysis"]["tempo_ratio"])
    graph = (
        f"[0:a]atrim=start={start:.9f}:duration={source_duration:.9f},"
        "asetpts=PTS-STARTPTS,"
        f"atempo={ratio:.9f},"
        "aresample=48000,aformat=sample_rates=48000:channel_layouts=stereo,"
        "atrim=duration=60,apad=whole_dur=60,"
        "alimiter=limit=0.891251:attack=5:release=80:level=false,"
        "afade=t=in:st=0:d=0.008:curve=tri,"
        "afade=t=out:st=59.333333:d=0.666667:curve=tri[out]"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    filter_file = output.with_suffix(".filtergraph.txt")
    filter_file.write_text(graph, encoding="utf-8")
    run([
        str(ffmpeg), "-hide_banner", "-y", "-i", str(source),
        "-filter_complex", graph, "-map", "[out]", "-ar", "48000", "-ac", "2",
        "-c:a", "pcm_s24le", "-t", "60", str(output),
    ])
    probe = run([
        str(ffmpeg.with_name("ffprobe.exe")), "-v", "error", "-show_entries",
        "format=duration:stream=codec_name,sample_rate,channels,bits_per_sample",
        "-of", "json", str(output),
    ])
    parsed = json.loads(probe.stdout)
    stream = parsed["streams"][0]
    duration = float(parsed["format"]["duration"])
    if (abs(duration - 60.0) > 1e-6 or stream["codec_name"] != "pcm_s24le"
            or stream["sample_rate"] != "48000" or stream["channels"] != 2):
        raise RuntimeError(f"unexpected output format/duration: {parsed}")
    rendered = np.frombuffer(run([
        str(ffmpeg), "-hide_banner", "-loglevel", "error", "-i", str(output),
        "-f", "f32le", "-ar", "48000", "-ac", "2", "pipe:1",
    ]).stdout, dtype="<f4").reshape(-1, 2)
    rendered_quarter = []
    for i in range(240):
        a, b = i * 12000, (i + 1) * 12000
        rendered_quarter.append(round(rms_db(rendered[a:b]), 2))
    rendered_half = [round(rms_db(rendered[i * 24000:(i + 1) * 24000]), 2) for i in range(120)]
    rendered_second = [round(rms_db(rendered[i * 48000:(i + 1) * 48000]), 2) for i in range(60)]
    peak_dbfs = 20.0 * np.log10(max(float(np.max(np.abs(rendered))), 1e-12))
    fade_start_quarter = int(59.333333 * 4)
    pre_fade_quarters = rendered_quarter[:fade_start_quarter]
    endcard_quarters = rendered_quarter[57 * 4:]
    final_beat_samples = rendered[int((60.0 - 2.0 / 3.0) * 48000):]
    final_sample_peak_dbfs = 20.0 * np.log10(max(float(np.max(np.abs(rendered[-2:]))), 1e-12))
    no_gap_failures = [i for i, level in enumerate(pre_fade_quarters) if level < -60.0]
    analysis["cue"]["rendered_audio_metrics"] = {
        "sample_peak_dbfs": round(float(peak_dbfs), 3),
        "rms_first_second_dbfs": rendered_second[0],
        "rms_last_second_dbfs": rendered_second[-1],
        "rms_min_quarter_second_dbfs": min(rendered_quarter),
        "rms_min_quarter_second_index": int(np.argmin(rendered_quarter)),
        "rms_max_quarter_second_dbfs": max(rendered_quarter),
        "no_gap_check_before_documented_fade": {
            "quarter_window_threshold_dbfs": -60.0,
            "checked_quarter_windows": len(pre_fade_quarters),
            "silent_or_near_silent_window_indices": no_gap_failures,
            "passes": not no_gap_failures and bool(np.isfinite(rendered).all()),
            "minimum_quarter_window_dbfs": min(pre_fade_quarters),
        },
        "endcard_quarter_second_rms_dbfs_57_to_60": endcard_quarters,
        "rms_final_one_beat_dbfs": round(rms_db(final_beat_samples), 2),
        "last_two_sample_peak_dbfs": round(float(final_sample_peak_dbfs), 2),
        "rendered_all_samples_finite": bool(np.isfinite(rendered).all()),
        "rendered_per_second_rms_dbfs": rendered_second,
        "rendered_per_half_second_rms_dbfs": rendered_half,
        "rendered_per_quarter_second_rms_dbfs": rendered_quarter,
    }
    analysis["cue"]["rendered_file"] = str(output)
    analysis["cue"]["rendered_sha256"] = sha256(output)
    analysis["cue"]["rendered_probe"] = parsed
    analysis["cue"]["render_filtergraph"] = str(filter_file)
    (output.parent / "analysis.json").write_text(json.dumps(analysis, indent=2), encoding="utf-8")
    print(json.dumps({"rendered": str(output), "sha256": analysis["cue"]["rendered_sha256"], "probe": parsed}, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args()
    result = analyze(args.source, args.ffmpeg, args.out_dir)
    if args.render:
        render(args.source, args.ffmpeg, args.out_dir / "music-v2.wav", result)


if __name__ == "__main__":
    main()
