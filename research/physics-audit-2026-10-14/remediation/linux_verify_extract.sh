#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 ARCHIVE SNAPSHOT_ROOT BEFORE_MANIFEST INTEGRITY_LOG" >&2
  exit 2
fi

archive="$1"
snapshot_root="$2"
before_manifest="$3"
integrity_log="$4"
snapshot_helper_rel="research/physics-audit-2026-10-14/remediation/linux_verify_snapshot.py"

if [[ -e "$snapshot_root" ]]; then
  echo "refusing to overwrite existing snapshot path: $snapshot_root" >&2
  exit 2
fi
mkdir -p "$snapshot_root" "$(dirname "$integrity_log")"
tar -xf "$archive" -C "$snapshot_root"
chmod +x "$snapshot_root/.tools/Godot_v4.7.2-stable_linux.x86_64"

git -C "$snapshot_root" init -b r11-linux-source-snapshot
git -C "$snapshot_root" config user.name "OpenRC Linux Verification"
git -C "$snapshot_root" config user.email "linux-verification.invalid"
git -C "$snapshot_root" add --force --all
git -C "$snapshot_root" rm --cached --force --ignore-unmatch -- .tools/Godot_v4.7.2-stable_linux.x86_64
git -C "$snapshot_root" -c commit.gpgsign=false commit -m "R11 fixed-commit Linux source snapshot with explicit overlays"

python3 "$snapshot_root/$snapshot_helper_rel" verify \
  --root "$snapshot_root" \
  --before "$before_manifest" \
  --archive "$archive" 2>&1 | tee "$integrity_log"
