#!/usr/bin/env bash
set -uo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 ARCHIVE SNAPSHOT_ROOT BEFORE_MANIFEST AFTER_MANIFEST TEST_LOG" >&2
  exit 2
fi

archive="$1"
snapshot_root="$2"
before_manifest="$3"
after_manifest="$4"
test_log="$5"
snapshot_helper_rel="research/physics-audit-2026-10-14/remediation/linux_verify_snapshot.py"

if [[ -e "$snapshot_root" ]]; then
  echo "refusing to overwrite existing snapshot path: $snapshot_root" >&2
  exit 2
fi
mkdir -p "$snapshot_root" "$(dirname "$test_log")" "$(dirname "$after_manifest")"
tar -xf "$archive" -C "$snapshot_root"
chmod +x "$snapshot_root/.tools/Godot_v4.7.2-stable_linux.x86_64"

git -C "$snapshot_root" init -b r11-linux-source-snapshot
git -C "$snapshot_root" config user.name "OpenRC Linux Verification"
git -C "$snapshot_root" config user.email "linux-verification.invalid"
git -C "$snapshot_root" add --force --all
git -C "$snapshot_root" rm --cached --force --ignore-unmatch -- .tools/Godot_v4.7.2-stable_linux.x86_64
git -C "$snapshot_root" -c commit.gpgsign=false commit -m "R11 fixed-commit Linux source snapshot with explicit overlays"

set +e
python3 "$snapshot_root/$snapshot_helper_rel" verify \
  --root "$snapshot_root" \
  --before "$before_manifest" \
  --archive "$archive" 2>&1 | tee "$test_log"
verify_status=${PIPESTATUS[0]}
set -e
if [[ $verify_status -ne 0 ]]; then
  echo "== snapshot verification exit=$verify_status; app/test.sh not run" | tee -a "$test_log"
  python3 "$snapshot_root/$snapshot_helper_rel" after \
    --root "$snapshot_root" \
    --before "$before_manifest" \
    --out "$after_manifest" 2>&1 | tee -a "$test_log"
  exit "$verify_status"
fi

{
  echo "R11 canonical Linux verification of fixed-commit snapshot"
  echo "snapshot_root=$snapshot_root"
  echo "source_manifest=$before_manifest"
  echo "synthetic_snapshot_head=$(git -C "$snapshot_root" rev-parse HEAD)"
  echo "source_tree_status_before_run:"
  git -C "$snapshot_root" status --short --untracked-files=all
  echo "pinned_godot_sha512:"
  sha512sum "$snapshot_root/.tools/Godot_v4.7.2-stable_linux.x86_64"
  echo "godot_version:"
  "$snapshot_root/.tools/Godot_v4.7.2-stable_linux.x86_64" --version
  echo "app/test.sh_sha256:"
  sha256sum "$snapshot_root/app/test.sh"
  echo "== full app/test.sh begins"
} | tee -a "$test_log"

set +e
(cd "$snapshot_root" && bash app/test.sh) 2>&1 | tee -a "$test_log"
test_status=${PIPESTATUS[0]}
set -e

echo "== full app/test.sh exit=$test_status" | tee -a "$test_log"
python3 "$snapshot_root/$snapshot_helper_rel" after \
  --root "$snapshot_root" \
  --before "$before_manifest" \
  --out "$after_manifest" 2>&1 | tee -a "$test_log"
manifest_status=${PIPESTATUS[0]}
echo "== post-run manifest exit=$manifest_status" | tee -a "$test_log"

if [[ $manifest_status -ne 0 ]]; then
  exit "$manifest_status"
fi
exit "$test_status"
