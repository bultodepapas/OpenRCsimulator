#!/usr/bin/env python3
"""Render a measured, fixed-length Uprising trailer edit with the pinned FFmpeg."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


# Trailer section, [source start, source end), gain. The non-final sources have
# 50 ms of extra material at their ends so 50 ms equal-power crossfades leave
# the rendered trailer at exactly 60 seconds.
SECTIONS = [
    {"name": "anticipation", "timeline_start_s": 0, "timeline_end_s": 4, "source_start_s": 0, "source_end_s": 4.05, "gain_db": 0.0},
    {"name": "rise", "timeline_start_s": 4, "timeline_end_s": 31, "source_start_s": 4, "source_end_s": 31.05, "gain_db": 0.0},
    {"name": "storm_tension", "timeline_start_s": 31, "timeline_end_s": 42, "source_start_s": 110, "source_end_s": 121.05, "gain_db": 0.0},
    {"name": "impact_drop", "timeline_start_s": 42, "timeline_end_s": 45, "source_start_s": 121, "source_end_s": 124.05, "gain_db": 0.0},
    {"name": "repair_bill_quiet", "timeline_start_s": 45, "timeline_end_s": 48, "source_start_s": 124, "source_end_s": 127.05, "gain_db": -7.0},
    {"name": "pickup", "timeline_start_s": 48, "timeline_end_s": 50, "source_start_s": 127, "source_end_s": 129.05, "gain_db": 0.0},
    {"name": "formation_climax", "timeline_start_s": 50, "timeline_end_s": 57, "source_start_s": 129, "source_end_s": 136.05, "gain_db": 0.0},
    # This late source passage is measured as a natural decay: RMS falls from
    # -11 dBFS at 195 s to -38 dBFS by 198 s. It has not been auditioned.
    {"name": "resolved_tail_candidate", "timeline_start_s": 57, "timeline_end_s": 60, "source_start_s": 195, "source_end_s": 198, "gain_db": 0.0},
]

CROSSFADE_S = 0.05
SAMPLE_RATE_HZ = 48000


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def build_filtergraph() -> str:
    filters: list[str] = []
    labels: list[str] = []
    for index, section in enumerate(SECTIONS):
        gain = 10 ** (section["gain_db"] / 20)
        filters.append(
            f"[0:a]atrim=start={section['source_start_s']}:end={section['source_end_s']},"
            f"asetpts=PTS-STARTPTS,aresample={SAMPLE_RATE_HZ},"
            f"aformat=sample_rates={SAMPLE_RATE_HZ}:channel_layouts=stereo,"
            f"volume={gain:.9f}[s{index}]"
        )
        labels.append(f"s{index}")

    current = labels[0]
    for index, next_label in enumerate(labels[1:], start=1):
        output_label = f"x{index}"
        filters.append(
            f"[{current}][{next_label}]acrossfade=d={CROSSFADE_S}:c1=tri:c2=tri[{output_label}]"
        )
        current = output_label

    # A conservative sample-peak ceiling avoids encoding an over-range source
    # master; it is not a substitute for the final audiovisual mix check.
    filters.append(f"[{current}]alimiter=limit=0.891251:attack=5:release=80:level=false[out]")
    return ";\n".join(filters)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    if not args.ffmpeg.is_file() or not args.source.is_file():
        raise SystemExit("FFmpeg executable or source MP3 not found")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    filter_path = args.output.with_suffix(".filtergraph.txt")
    filter_path.write_text(build_filtergraph(), encoding="utf-8")

    command = [
        str(args.ffmpeg), "-hide_banner", "-y", "-i", str(args.source),
        "-filter_complex", build_filtergraph(), "-map", "[out]",
        "-t", "60", "-ar", str(SAMPLE_RATE_HZ), "-ac", "2",
        "-c:a", "pcm_s24le", str(args.output),
    ]
    subprocess.run(command, check=True)
    print(json.dumps({
        "output": str(args.output),
        "source_sha256": sha256(args.source),
        "source_offsets_s": [
            {"name": s["name"], "timeline_s": [s["timeline_start_s"], s["timeline_end_s"]],
             "source_s": [s["source_start_s"], s["source_end_s"]], "gain_db": s["gain_db"]}
            for s in SECTIONS
        ],
        "crossfade_s": CROSSFADE_S,
        "filtergraph": str(filter_path),
    }, indent=2))


if __name__ == "__main__":
    main()
