#!/usr/bin/env python3
"""VAL-8a: reduce surveyed ground-video events; never infer airspeed."""
import argparse
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile


COLUMNS = ["id", "frame", "frame_u", "x_m", "x_u_m", "frame_x_correlation"]
LIMITATIONS = [
    "Along-runway net displacement only; distance equals ground path length only for a straight, non-reversing run.",
    "Average ground speed is neither instantaneous liftoff/touchdown speed nor airspeed or stall speed.",
    "Capture cadence must be constant with one annotated frame per original captured frame; playback FPS is not capture FPS.",
    "CFR, camera geometry, event definitions and survey validity are operator declarations, not verified by this reducer.",
    "Positions must be surveyed ground coordinates or independently corrected ground-plane positions, not raw image pixels.",
    "First-order standard uncertainties (k=1); no coverage probability or validation acceptance is assigned.",
    "Per-event time/position correlation and shared clock/length scale errors are modeled; other cross-event correlations are excluded.",
    "A shared coordinate origin and frame origin cancel in differences; do not add their uncertainty independently at each endpoint.",
    "Intervals sharing events or calibration errors are correlated; signed contributions retain those dependencies and must not be averaged as independent.",
    "Synthetic observations verify reduction only; real flights and simulator comparison remain VAL-8.",
]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def fields(value, names, label):
    require(isinstance(value, dict) and set(value) == set(names.split()), f"{label}: missing/unknown fields")


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def finite(value, label, minimum=None):
    require(type(value) in (int, float) and math.isfinite(value), f"{label}: expected finite number")
    require(minimum is None or value >= minimum, f"{label}: below minimum {minimum}")
    return float(value)


def identifier(value):
    return isinstance(value, str) and re.fullmatch(r"[a-z][a-z0-9_-]*", value) is not None


def load_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, f"duplicate JSON key: {key}")
            result[key] = value
        return result

    def invalid(value):
        raise ValueError(f"nonfinite JSON constant: {value}")

    return json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid)


def validate(campaign):
    fields(campaign, "format evidence aircraft configuration environment video survey annotations_source intervals", "campaign")
    require(campaign["format"] == "openrc-ground-video v1", "unsupported format")
    require(campaign["evidence"] in ("synthetic", "measured"), "invalid evidence kind")
    for key in ("aircraft", "configuration", "environment", "annotations_source"):
        require(nonempty(campaign[key]), f"missing {key}")
    video = campaign["video"]
    fields(video, "source sha256 frame_count capture_fps_num capture_fps_den fps_relative_u constant_capture_cadence_verified timing_source", "video")
    for key in ("source", "timing_source"):
        require(nonempty(video[key]), f"missing video.{key}")
    for key in ("frame_count", "capture_fps_num", "capture_fps_den"):
        require(type(video[key]) is int and 0 < video[key] <= 2**53, f"invalid video.{key}")
    require(video["constant_capture_cadence_verified"] is True, "constant capture cadence must be verified; VFR/duplicated/dropped frames unsupported")
    finite(video["fps_relative_u"], "fps_relative_u", 0)
    digest = video["sha256"]
    require((campaign["evidence"] == "synthetic" and digest is None)
            or (isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest)), "video SHA-256 required for measured evidence")
    survey = campaign["survey"]
    fields(survey, "axis_datum source scale_relative_u ground_positions_verified independent_event_residuals", "survey")
    require(nonempty(survey["axis_datum"]) and nonempty(survey["source"]), "survey needs datum and source")
    require(survey["ground_positions_verified"] is True, "ground positions must be established independently of raw image coordinates")
    require(survey["independent_event_residuals"] is True, "cross-event residual correlations unsupported")
    finite(survey["scale_relative_u"], "scale_relative_u", 0)
    require(isinstance(campaign["intervals"], list) and campaign["intervals"], "intervals required")
    seen = set()
    for interval in campaign["intervals"]:
        fields(interval, "id start end definition", "interval")
        require(all(identifier(interval[k]) for k in ("id", "start", "end")), "invalid interval/event ID")
        require(interval["id"] not in seen, "duplicate interval ID")
        require(nonempty(interval["definition"]), "interval needs its physical event definition")
        seen.add(interval["id"])


def read_events(raw, frame_count):
    reader = csv.DictReader(io.StringIO(raw.decode("utf-8"), newline=""), strict=True)
    require(reader.fieldnames == COLUMNS, f"CSV header must be {','.join(COLUMNS)}")
    events = {}
    previous = -1
    for row in reader:
        require(set(row) == set(COLUMNS) and all(v is not None and v.strip() for v in row.values()), "malformed/empty CSV row")
        name = row["id"]
        require(identifier(name) and name not in events, "invalid/duplicate event ID")
        require(re.fullmatch(r"0|[1-9][0-9]*", row["frame"]), "frame must be a nonnegative integer")
        frame = int(row["frame"])
        require(previous < frame < frame_count, "event frames must increase and lie within the original clip")
        event = {"frame": frame}
        for key in COLUMNS[2:]:
            event[key] = finite(float(row[key]), key)
        require(event["frame_u"] >= 0 and event["x_u_m"] >= 0, "negative standard uncertainty")
        require(-1 <= event["frame_x_correlation"] <= 1, "correlation must lie in [-1, 1]")
        events[name] = event
        previous = frame
    require(len(events) >= 2, "at least two events required")
    return events


def quantity(value, unit, derivatives, start_id, end_id, events, common):
    """Whiten each event's 2x2 covariance; names preserve shared latent errors."""
    terms = {}
    for name, (df, dx) in zip((start_id, end_id), derivatives):
        event = events[name]
        rho = event["frame_x_correlation"]
        terms[f"event:{name}:joint"] = df * event["frame_u"] + dx * rho * event["x_u_m"]
        terms[f"event:{name}:position_residual"] = dx * math.sqrt((1-rho)*(1+rho)) * event["x_u_m"]
    terms.update(common)
    for term in [value, *terms.values()]:
        finite(term, "derived value/contribution")
    uncertainty = finite(math.hypot(*terms.values()), "derived uncertainty", 0)
    return {"value": value, "unit": unit, "u": uncertainty, "kind": "derived", "standard_uncertainty_contributions": terms}


def reduce_interval(interval, events, campaign):
    start_id, end_id = interval["start"], interval["end"]
    require(start_id in events and end_id in events, "interval references missing event")
    start, end = events[start_id], events[end_id]
    n = end["frame"] - start["frame"]
    require(n > 0, "interval end must follow start")
    delta = finite(end["x_m"] - start["x_m"], "displacement")
    require(delta != 0, "nonzero displacement required")
    direction = math.copysign(1.0, delta)
    fps = campaign["video"]["capture_fps_num"] / campaign["video"]["capture_fps_den"]
    t, distance = n / fps, abs(delta)
    speed = distance / t
    require(all(math.isfinite(v) and v > 0 for v in (t, distance, speed)), "derived positive quantity overflowed/underflowed")
    clock_u = campaign["video"]["fps_relative_u"]
    scale_u = campaign["survey"]["scale_relative_u"]
    quantities = {
        "duration": quantity(t, "s", [(-1/fps, 0), (1/fps, 0)], start_id, end_id, events,
                             {"capture_clock": -t*clock_u, "survey_scale": 0.0}),
        "distance": quantity(distance, "m", [(0, -direction), (0, direction)], start_id, end_id, events,
                             {"capture_clock": 0.0, "survey_scale": distance*scale_u}),
        "average_ground_speed": quantity(speed, "m/s", [(speed/n, -direction/t), (-speed/n, direction/t)],
                                         start_id, end_id, events, {"capture_clock": speed*clock_u, "survey_scale": speed*scale_u}),
    }
    warnings = []
    # Diagnostic thresholds, not coverage intervals or universal validity bounds.
    if quantities["duration"]["u"] / t > 0.1:
        warnings.append("Large timing uncertainty: first-order ratio propagation may be inadequate.")
    if quantities["distance"]["u"] / distance > 0.1:
        warnings.append("Large displacement uncertainty: absolute-distance linearization may be inadequate.")
    return {**interval, "delta_frames": n, "signed_displacement_m": delta, **quantities, "warnings": warnings}


def reduce(campaign, events_raw):
    validate(campaign)
    events = read_events(events_raw, campaign["video"]["frame_count"])
    return {"format": "openrc-ground-video-result v1", "evidence": campaign["evidence"],
            "campaign": campaign, "events": events, "limitations": LIMITATIONS,
            "intervals": [reduce_interval(item, events, campaign) for item in campaign["intervals"]]}


def file_hash(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024*1024), b""):
            digest.update(block)
    return digest.hexdigest()


def refuse_alias(output, inputs):
    for path in inputs:
        require(output.resolve() != path.resolve() and not (output.exists() and path.exists() and output.samefile(path)),
                "output aliases an input or reducer")


def atomic_write(path, contents):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="\n", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("campaign", type=Path)
    parser.add_argument("events", type=Path)
    parser.add_argument("--video", type=Path, help="original clip; required when metadata declares its SHA-256")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        inputs = [args.campaign, args.events, Path(__file__)] + ([args.video] if args.video else [])
        if args.output:
            refuse_alias(args.output, inputs)
        campaign_raw, events_raw = args.campaign.read_bytes(), args.events.read_bytes()
        campaign = load_json(campaign_raw)
        report = reduce(campaign, events_raw)
        expected = campaign["video"]["sha256"]
        require((args.video is not None) == (expected is not None), "--video must be supplied exactly when a video SHA-256 is declared")
        video_hash = file_hash(args.video) if args.video else None
        require(video_hash == expected, "video SHA-256 mismatch")
        report["input_sha256"] = {"campaign": hashlib.sha256(campaign_raw).hexdigest(),
                                  "events_csv": hashlib.sha256(events_raw).hexdigest(),
                                  "video": video_hash, "reducer": file_hash(Path(__file__))}
        output = json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n"
        if args.output:
            refuse_alias(args.output, inputs)
            atomic_write(args.output, output)
        else:
            sys.stdout.write(output)
        return 0
    except (OSError, ValueError, TypeError, OverflowError, csv.Error) as error:
        print(f"VAL-8a: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
