#!/usr/bin/env bash
# Pinned Python environment for visual capture checks (LANDSCAPE-PLAN L0c): flip-evaluator, numpy, pillow at the exact
# versions and SHA-256 hashes of tests/requirements-visual.txt, in <repo>/.tools/visual-venv. Prints its python.
# Needs only python3 (a venv without pip, so no python3-venv package) and a pip new enough for --python (≥ 22.3).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="$(git -C "$HERE" rev-parse --show-toplevel)/.tools/visual-venv"
REQ="$HERE/requirements-visual.txt"
STAMP="$VENV/.requirements.sha256"
if [ -x "$VENV/bin/python" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$(sha256sum "$REQ" | cut -d' ' -f1)" ]; then
  echo "$VENV/bin/python"; exit 0
fi
rm -rf "$VENV"
python3 -m venv --without-pip "$VENV"
python3 -m pip --python "$VENV/bin/python" install -q --require-hashes --no-deps --only-binary=:all: -r "$REQ" >&2
sha256sum "$REQ" | cut -d' ' -f1 > "$STAMP"
echo "$VENV/bin/python"
