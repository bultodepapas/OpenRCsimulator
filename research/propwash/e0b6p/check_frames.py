#!/usr/bin/env python3
"""Compare all body/aux/load/input with swirl samples through Godot's real frame scheduler."""
import argparse
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    hashes = []
    frames = []
    for fps in (30, 60, 144):
        result = subprocess.run([args.godot, "--headless", "--path", str(ROOT / "app"),
                                 "--fixed-fps", str(fps), "--script", str(Path(__file__).with_name("frame_driver.gd"))],
                                text=True, capture_output=True, timeout=60)
        output = result.stdout + result.stderr
        assert result.returncode == 0 and "ERROR:" not in output, output
        match = re.search(r"E0b6p frame hash ([a-f0-9]{64}) ticks=(\d+) frames=(\d+)", output)
        assert match and int(match[2]) == 480, output
        hashes.append(match[1])
        frames.append(int(match[3]))
        print(f"{fps} fps: hash={match[1]} ticks={match[2]} frames={match[3]}")
    assert len(set(hashes)) == 1, "frame rate changed the physics trajectory"
    assert 0 < frames[0] < frames[1] < frames[2], "frame schedules were not distinct"
    print("E0b6p: identical body/aux/load/input with swirl hashes at 30/60/144 fps")


if __name__ == "__main__":
    main()
