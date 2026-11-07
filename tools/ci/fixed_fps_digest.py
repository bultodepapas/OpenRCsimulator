"""Extract exactly one complete digest from a fixed-FPS test invocation."""
import argparse
import re
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("field", choices=("state_sha256", "flight_sha256"))
    parser.add_argument("fps", type=int, choices=(30, 60, 144))
    args = parser.parse_args()
    output = sys.stdin.read()
    marker = args.field + "="
    matches = re.findall(r"(?<!\S)" + re.escape(marker) + r"([0-9a-f]{64})(?!\S)", output)
    if output.count(marker) != 1 or len(matches) != 1:
        print(f"{args.fps} fps: expected exactly one valid {args.field} digest", file=sys.stderr)
        return 1
    print(matches[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
