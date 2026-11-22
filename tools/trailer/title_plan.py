#!/usr/bin/env python3
"""Validate revision-bound global titles or create a synthetic type study.

Examples:
    python tools/trailer/title_plan.py validate --plan docs/plans/trailer-v2/title-plan-r7.json
    python tools/trailer/title_plan.py preview --out-dir tmp/trailer/r7-type-study-01

The preview contains no game footage. `publication=True` requires the caller
to bind a trial basis, but does not establish that the basis, footage, website,
or final visual review has been verified. Those remain production evidence.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import cinema_titles as cinema

REPO = Path(__file__).resolve().parents[2]
DEFAULT_PLAN = REPO / "docs/plans/trailer-v2/title-plan-r7.json"
FPS, TOTAL_FRAMES = 60, 9000
REQUIRED_R6 = {
    "electric-stick": ("label", "UGLY STICK · ELECTRIC 6S", 480, 660),
    "sky": ("headline", "A SKY WITHIN REACH", 855, 1050),
    "hx700": ("label", "HX-700 · MECHANICAL INSPECTION", 3060, 3300),
    "xcell": ("label", "X-CELL .60 · RESEARCH HELICOPTER", 3300, 3540),
    "input": ("headline", "FEEL EVERY INPUT", 3615, 3885),
    "failure": ("label", "FAILURE PRACTICE · ENGINE OUT", 3900, 4380),
    "companions": ("label", "AI FLIGHT COMPANIONS", 4380, 4620),
    "scenery": ("label", "IMPORTED SCENERY · EXPERIMENTAL RUNWAY", 4620, 4860),
    "lab-baseline": ("label", "BASELINE SETUP", 5580, 5745),
    "lab-changed": ("label", "CHANGED SETUP", 5835, 6000),
    "stick-scale": ("label", "UGLY STICK · .61 GLOW · 10%–500%", 6000, 6300),
    "scale-500": ("label", "GIANT · 500%", 6090, 6195),
    "scale-10": ("label", "TINY · 10%", 6195, 6300),
    "size-comparison": ("label", "CINEMATIC SIZE COMPARISON", 6300, 6540),
    "liveries": ("label", "PRESENTATION · LIVERY SHOWCASE", 6540, 7140),
    "hangar": ("headline", "EXPAND YOUR HANGAR", 7500, 7620),
    "phoenix": ("label", "PHOENIX RC · MODEL PREVIEWS", 7620, 7920),
    "clearview": ("label", "CLEARVIEW · MODEL PREVIEWS", 7920, 8220),
    "trial": ("label", "EXPERIMENTAL TEST FLIGHT", 8220, 8400),
    "end-brand": ("endcard", "OPEN RC SIMULATOR", 8700, 9000),
    "end-cta": ("endcard", "PLAY FREE", 8700, 9000),
    "end-url": ("label", "bultodepapas.github.io/OpenRCsimulator/", 8700, 9000),
}
_SHOT_ANCHORS_R6 = {
    "R4-05": (840, 1080), "R4-20": (3060, 3300), "R4-21": (3300, 3540),
    "R4-23": (3600, 3900), "R4-24": (3900, 4020), "R4-26": (4200, 4380),
    "R4-27": (4380, 4620), "R4-28": (4620, 4860), "R4-32": (5580, 5745),
    "R4-33": (5745, 5835), "R4-34": (5835, 6000), "R4-35": (6000, 6090),
    "R4-36": (6090, 6195), "R4-37": (6195, 6300), "R4-38": (6300, 6540),
    "R4-39": (6540, 7140), "R4-40": (7140, 7500), "R4-41": (7500, 7620),
    "R4-42a": (7620, 7680), "R4-42i": (7890, 7920),
    "R4-42j": (7920, 7980), "R4-42r": (8190, 8220),
    "R4-43": (8220, 8400), "R4-45": (8700, 9000),
}
# R7 retains every shot duration but moves complete chapters. Keep the legacy
# contract explicit so old manifests cannot silently acquire current timing.
_R7_WINDOWS = {
    "hx700": (2340, 2580), "xcell": (2580, 2820),
    "lab-baseline": (4380, 4545), "lab-changed": (4635, 4800),
    "stick-scale": (4800, 5100), "scale-500": (4890, 4995),
    "scale-10": (4995, 5100), "size-comparison": (5100, 5340),
    "companions": (5340, 5580), "scenery": (5580, 5820),
    "liveries": (6300, 6900), "hangar": (7560, 7680),
    "phoenix": (7680, 7980), "clearview": (7980, 8280),
    "trial": (8280, 8460),
}
REQUIRED_R7 = {key: (role, text, *_R7_WINDOWS.get(key, (start, end)))
               for key, (role, text, start, end) in REQUIRED_R6.items()}
REQUIRED_R7["lumber"] = ("label", "TURBO LUMBER", 8460, 8700)
REQUIRED = REQUIRED_R7
_SHOT_ANCHORS_R7 = dict(_SHOT_ANCHORS_R6, **{
    "R4-20": (2340, 2580), "R4-21": (2580, 2820),
    "R4-32": (4380, 4545), "R4-33": (4545, 4635), "R4-34": (4635, 4800),
    "R4-35": (4800, 4890), "R4-36": (4890, 4995), "R4-37": (4995, 5100),
    "R4-38": (5100, 5340), "R4-27": (5340, 5580), "R4-28": (5580, 5820),
    "R4-39": (6300, 6900), "R4-40": (6900, 7260), "R4-44": (7260, 7560),
    "R4-41": (7560, 7680), "R4-42a": (7680, 7740), "R4-42i": (7950, 7980),
    "R4-42j": (7980, 8040), "R4-42r": (8250, 8280), "R4-43": (8280, 8460),
    "R4-31": (8460, 8700),
})
_FORBIDDEN = ("RACE THE GATES", "TAKE CONTROL", "TUNE YOUR SETUP", "MAKE IT YOURS", "300+",
              "MUSIC:", "SCOTT BUCKLEY", "CC BY")
# Six source-timeline windows, 18.75 seconds total. These are samples, not an EDL.
# All three headline animations and the entire five-second end card are shown.
STUDY_WINDOWS_R6 = ((855, 195), (3060, 120), (3615, 270),
                    (7500, 120), (7620, 120), (8700, 300))
# Seven R7 windows, 22.75 seconds: additionally review the night identity cue.
STUDY_WINDOWS = ((855, 195), (2340, 120), (3615, 270),
                 (7560, 120), (7680, 120), (8460, 240), (8700, 300))
STUDY_MARK = "TYPOGRAPHY STUDY · NO GAME FOOTAGE"


def _read_snapshot(path):
    """Parse and identify exactly one bytes snapshot, rejecting duplicate keys."""
    def bad_constant(value):
        raise ValueError(f"non-finite JSON number: {value}")
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"{path}: duplicate JSON key {key!r}")
            result[key] = value
        return result
    raw = Path(path).read_bytes()
    data = json.loads(raw.decode("utf-8"), parse_constant=bad_constant, object_pairs_hook=unique_object)
    return data, hashlib.sha256(raw).hexdigest()


def _read_json(path):
    return _read_snapshot(path)[0]


def _shot_plan_check(source, revision):
    plan = source if isinstance(source, dict) else _read_json(source)
    if not isinstance(plan, dict) or plan.get("format") != "openrc-trailer-shot-plan":
        raise ValueError("shot plan has the wrong format")
    accepted = ("R5", "R6") if revision == "R6" else ("R7",)
    if plan.get("revision") not in accepted:
        raise ValueError("title and shot plan revisions do not match")
    if (type(plan.get("fps")) is not int or plan["fps"] != FPS
            or type(plan.get("duration_frames")) is not int or plan["duration_frames"] != TOTAL_FRAMES):
        raise ValueError("shot plan must be 60 fps and 9000 frames")
    shots = plan.get("shots")
    if not isinstance(shots, list) or not shots:
        raise ValueError("shot plan must have a nonempty shots list")
    found = {}
    cursor = 0
    for shot in shots:
        if not isinstance(shot, dict) or not isinstance(shot.get("id"), str):
            raise ValueError("invalid shot entry")
        start, end = shot.get("in_frame"), shot.get("out_frame")
        if (type(start) is not int or type(end) is not int or start != cursor
                or end <= start or end > TOTAL_FRAMES or shot["id"] in found):
            raise ValueError("shot plan must have contiguous, unique, positive frame intervals")
        found[shot["id"]] = (start, end)
        cursor = end
    if cursor != TOTAL_FRAMES:
        raise ValueError("shot plan does not end at frame 9000")
    anchors = _SHOT_ANCHORS_R6 if revision == "R6" else _SHOT_ANCHORS_R7
    for name, expected in anchors.items():
        if found.get(name) != expected:
            raise ValueError(f"shot plan boundary mismatch for {name}: expected {expected}")


def load(path, publication=False, trial_basis=None, shot_plan=None):
    """Read and validate a title plan; return renderer cues and metadata.

    `trial_basis` may only be `estimated` or `donor`. It binds the qualifier
    across the entire experimental trial; it does not prove the route. Missing
    basis blocks publication mode, while ordinary review can remain unresolved.
    `shot_plan` may be a path or mapping and checks the global edit boundaries.
    """
    if trial_basis not in (None, "estimated", "donor"):
        raise ValueError("trial_basis must be 'estimated' or 'donor'")
    if type(publication) is not bool:
        raise ValueError("publication must be a boolean")
    plan, source_sha256 = _read_snapshot(path)
    if not isinstance(plan, dict):
        raise ValueError("title plan must be an object")
    if "source_sha256" in plan:
        raise ValueError("source_sha256 is computed by the loader, not authored in the manifest")
    revision = plan.get("revision")
    if revision not in ("R6", "R7"):
        raise ValueError("revision must be R6 or R7")
    for field, expected in (("format", "openrc-trailer-title-plan"), ("version", 1),
                            ("fps", FPS), ("duration_frames", TOTAL_FRAMES)):
        if plan.get(field) != expected or (isinstance(expected, int) and type(plan.get(field)) is not int):
            raise ValueError(f"{field} must be {expected!r}")
    if not isinstance(plan.get("metadata"), dict):
        raise ValueError("metadata must be an object")
    cues = copy.deepcopy(plan.get("cues"))
    if not isinstance(cues, list):
        raise ValueError("cues must be a list")
    cinema.validate_cues(cues)
    by_id = {cue["id"]: cue for cue in cues}
    required = REQUIRED_R6 if revision == "R6" else REQUIRED_R7
    for name, (role, text, start, end) in required.items():
        cue = by_id.get(name)
        if cue is None or (cue["role"], cue["lines"], cue["in_frame"], cue["out_frame"]) != (role, [text], start, end):
            raise ValueError(f"required cue {name!r} has incorrect text, role or coverage")
    headlines = [cue for cue in cues if cue["role"] == "headline"]
    if len(headlines) != 3 or {cue["id"] for cue in headlines} != {"sky", "input", "hangar"}:
        raise ValueError("exactly the three approved headlines are required")
    for cue in cues:
        if cue["out_frame"] > TOTAL_FRAMES:
            raise ValueError(f"cue {cue['id']!r} exceeds the master")
        lake_start, lake_end = (7140, 7500) if revision == "R6" else (6900, 7260)
        if cue["in_frame"] < lake_end and cue["out_frame"] > lake_start:
            raise ValueError(f"the lake interval [{lake_start}, {lake_end}) must have no title text")
        content = " ".join(cue["lines"]).upper()
        if any(forbidden in content for forbidden in _FORBIDDEN) or re.search(r"\b(?:BETA|ALPHA)\b", content):
            raise ValueError(f"cue {cue['id']!r} contains inactive or unverified copy")
        if cue["role"] == "label" and (cue.get("fade_in_frames", 0) != 0 or cue.get("fade_out_frames", 0) != 0):
            raise ValueError(f"functional label {cue['id']!r} must be fully visible throughout")
        min_label, max_label = (36, 40) if revision == "R6" else (48, 56)
        if cue["role"] == "label" and not min_label <= cue.get("size", 32) <= max_label:
            raise ValueError(f"functional label {cue['id']!r} must use {min_label}–{max_label} px type")
        if cue["role"] == "headline":
            entrance = cue.get("fade_in_frames", 18)
            exit_ = cue.get("fade_out_frames", 12)
            if cue["out_frame"] - cue["in_frame"] - entrance - exit_ < 60:
                raise ValueError(f"headline {cue['id']!r} needs at least 60 fully settled frames")
            if (cue.get("align") != "left" or not 96 <= cue["x"] <= 256 or not 80 <= cue["y"] <= 240
                    or not 80 <= cue.get("size", 96) <= 112 or not 2 <= cue.get("tracking", 4) <= 6):
                raise ValueError(f"headline {cue['id']!r} does not match the intended film typography")
    for name in ("sky", "input", "hangar"):
        cue = by_id[name]
        expected = (8, 8, 4) if name == "hangar" else (18, 12, 8)
        actual = (cue.get("fade_in_frames", 18), cue.get("fade_out_frames", 12), cue.get("drift_px", 8))
        if actual != expected:
            raise ValueError(f"headline {name!r} has incorrect entrance, exit or drift")
    for name in ("end-brand", "end-cta", "end-url"):
        cue = by_id[name]
        if cue.get("align") != "center" or cue.get("fade_in_frames", 18) != 0 or cue.get("fade_out_frames", 12) != 0:
            raise ValueError("end-card copy must be centered and fully visible for all five seconds")
    shot_source_sha256 = None
    if shot_plan is not None:
        if isinstance(shot_plan, dict):
            _shot_plan_check(shot_plan, revision)
        else:
            shot_snapshot, shot_source_sha256 = _read_snapshot(shot_plan)
            _shot_plan_check(shot_snapshot, revision)
    if publication and trial_basis is None:
        raise ValueError("publication blocked: the accepted experimental trial basis is unresolved")
    if trial_basis is not None:
        by_id["trial"]["lines"] = [f"EXPERIMENTAL TEST FLIGHT · {trial_basis.upper()} PHYSICS"]
        # Revalidate real glyphs, safe area and overlap after binding the longer text.
        cinema.validate_cues(cues)
    result = copy.deepcopy(plan)
    result["cues"] = cues
    result["source_sha256"] = source_sha256
    if shot_plan is not None:
        result["shot_plan_sha256"] = shot_source_sha256
    result["metadata"]["trial_basis_binding"] = trial_basis or "unresolved"
    result["metadata"]["production_blockers"] = [
        (f"Verify the {trial_basis} physics binding against the accepted trial evidence." if trial_basis else
         "Establish and bind the accepted trial's estimated or donor basis."),
        "Recheck website availability before publication; browser, download, installation and runtime flows remain unverified.",
        "Accept real footage, graphics placement, actual indicators and full-motion readability.",
    ]
    result["metadata"]["publication_ready"] = False
    return result


def _sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _run(args):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f"command failed ({result.returncode}): {args[0]}\n{result.stderr[-4000:]}")
    return result.stdout


def _tool_version(executable):
    return _run([executable, "-version"]).splitlines()[0]


def _background(path):
    image = Image.new("RGB", (cinema.W, cinema.H), (28, 32, 37))
    draw = ImageDraw.Draw(image)
    # A neutral, nonrepresentational matte; it is not a scene or gameplay.
    for y in range(cinema.H):
        k = round(5 * y / (cinema.H - 1))
        draw.line((0, y, cinema.W, y), fill=(28 - k, 32 - k, 37 - k))
    font = ImageFont.truetype(str(cinema.FONT_DIR / "BarlowCondensed-Regular.ttf"), 28)
    draw.text((112, 1020), STUDY_MARK, font=font, fill=(199, 203, 206))
    image.save(path, format="PNG", compress_level=1)


def _link_or_copy(source, target):
    try:
        os.link(source, target)
    except FileExistsError:
        raise
    except OSError:
        with source.open("rb") as inp, target.open("xb") as out:
            shutil.copyfileobj(inp, out)


def _contact(path, background, cues, windows):
    samples = [cinema.CinemaCue(cue) for cue in cues]
    thumb_w, thumb_h, caption_h = 640, 360, 36
    rows = (len(windows) + 2) // 3
    sheet = Image.new("RGB", (thumb_w * 3, (thumb_h + caption_h) * rows), (17, 19, 22))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(str(cinema.FONT_DIR / "BarlowCondensed-Regular.ttf"), 20)
    for index, (start, length) in enumerate(windows):
        frame = start + length // 2
        frame_image = background.convert("RGBA")
        for sample in samples:
            if sample.in_frame <= frame < sample.out_frame:
                frame_image.alpha_composite(sample.frame(frame))
        x, y = (index % 3) * thumb_w, (index // 3) * (thumb_h + caption_h)
        sheet.paste(frame_image.convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS), (x, y))
        draw.text((x + 10, y + thumb_h + 5),
                  f"SOURCE TIMELINE {start / FPS:.2f}–{(start + length) / FPS:.2f} s",
                  font=font, fill=(210, 213, 217))
    sheet.save(path, format="JPEG", quality=85, subsampling=0)


def preview(plan_path, out_dir, ffmpeg="ffmpeg", ffprobe="ffprobe", shot_plan=None,
            trial_basis=None, windows=None):
    """Generate a neutral, permanently marked type study in a new directory."""
    plan = load(plan_path, trial_basis=trial_basis, shot_plan=shot_plan)
    if windows is None:
        windows = STUDY_WINDOWS_R6 if plan["revision"] == "R6" else STUDY_WINDOWS
    if (not isinstance(windows, (list, tuple)) or not windows
            or any(not isinstance(pair, (list, tuple)) or len(pair) != 2
                   or type(pair[0]) is not int or type(pair[1]) is not int
                   or pair[0] < 0 or pair[1] <= 0 or pair[0] + pair[1] > TOTAL_FRAMES
                   for pair in windows)):
        raise ValueError("study windows must be nonempty [start, frame-count] pairs within the master")
    ffmpeg_version, ffprobe_version = _tool_version(ffmpeg), _tool_version(ffprobe)
    output = Path(out_dir)
    output.mkdir(parents=True, exist_ok=False)
    movie = output / "typography-study.mp4"
    contact = output / "typography-contact.jpg"
    total = sum(length for _, length in windows)
    with tempfile.TemporaryDirectory(prefix=".study-work-", dir=output) as scratch:
        scratch = Path(scratch)
        background_path = scratch / "background.png"
        _background(background_path)
        frames_dir = scratch / "frames"
        frames_dir.mkdir()
        local = 0
        for index, (start, length) in enumerate(windows):
            segment = scratch / f"segment-{index:02d}"
            cinema.render_sequence(segment, plan["cues"], start, length)
            for frame in range(length):
                _link_or_copy(segment / f"{frame:05d}.png", frames_dir / f"{local:05d}.png")
                local += 1
        _run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-loop", "1", "-framerate", FPS,
              "-i", background_path, "-framerate", FPS, "-i", frames_dir / "%05d.png",
              "-filter_complex", "[0:v][1:v]overlay=shortest=1,format=yuv420p[v]", "-map", "[v]",
              "-an", "-frames:v", total, "-r", FPS, "-c:v", "libx264", "-preset", "veryfast",
              "-crf", "20", "-video_track_timescale", "60000", "-movflags", "+faststart",
              "-metadata", "comment=Synthetic typography study; no game footage", movie])
        with Image.open(background_path) as bg:
            _contact(contact, bg.copy(), plan["cues"], windows)
    probe = json.loads(_run([ffprobe, "-v", "error", "-select_streams", "v:0", "-show_entries",
                             "stream=codec_name,width,height,avg_frame_rate,nb_frames,duration:format=duration",
                             "-of", "json", movie]))
    streams = probe.get("streams", [])
    if (len(streams) != 1 or streams[0].get("width") != cinema.W or streams[0].get("height") != cinema.H
            or streams[0].get("avg_frame_rate") != "60/1" or int(streams[0].get("nb_frames", -1)) != total):
        raise ValueError("ffprobe did not confirm the expected study dimensions, frame rate and frame count")
    summary = {
        "kind": "synthetic typography study; no game footage",
        "watermark": STUDY_MARK,
        "plan": (Path(plan_path).resolve().relative_to(REPO).as_posix()
                 if Path(plan_path).resolve().is_relative_to(REPO) else str(Path(plan_path).resolve())),
        "plan_sha256": plan["source_sha256"],
        "renderer_sha256": _sha(cinema.__file__),
        "generator_sha256": _sha(__file__),
        "dependencies": {"title_assets": cinema.dependency_identity(), "ffmpeg": ffmpeg_version,
                         "ffprobe": ffprobe_version},
        "source_windows": [{"global_start_frame": start, "frames": length} for start, length in windows],
        "study_frames": total,
        "fps": FPS,
        "trial_basis_binding": plan["metadata"]["trial_basis_binding"],
        "publication_ready": plan["metadata"]["publication_ready"],
        "production_blockers": plan["metadata"]["production_blockers"],
        "ffprobe": probe,
        "outputs": {"mp4": {"file": movie.name, "sha256": _sha(movie)},
                    "contact": {"file": contact.name, "sha256": _sha(contact)}},
    }
    if shot_plan is not None:
        summary["shot_plan_sha256"] = plan.get("shot_plan_sha256")
    (output / "study-summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("validate", "preview"):
        sub = commands.add_parser(name)
        sub.add_argument("--plan", type=Path, default=DEFAULT_PLAN)
        sub.add_argument("--shot-plan", type=Path)
        sub.add_argument("--trial-basis", choices=("estimated", "donor"))
        if name == "validate":
            sub.add_argument("--publication", action="store_true")
        else:
            sub.add_argument("--out-dir", type=Path, required=True)
            sub.add_argument("--ffmpeg", default="ffmpeg")
            sub.add_argument("--ffprobe", default="ffprobe")
    args = parser.parse_args(argv)
    try:
        if args.command == "validate":
            plan = load(args.plan, publication=args.publication, trial_basis=args.trial_basis, shot_plan=args.shot_plan)
            result = {"ok": True, "cues": len(plan["cues"]), "fps": FPS, "frames": TOTAL_FRAMES,
                      "source_sha256": plan["source_sha256"],
                      "trial_basis_binding": plan["metadata"]["trial_basis_binding"],
                      "publication_ready": plan["metadata"]["publication_ready"],
                      "production_blockers": plan["metadata"]["production_blockers"]}
        else:
            result = preview(args.plan, args.out_dir, args.ffmpeg, args.ffprobe, args.shot_plan, args.trial_basis)
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0
    except (ValueError, OSError, KeyError, TypeError) as exc:
        print(f"title-plan: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
