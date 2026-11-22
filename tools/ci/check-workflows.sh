#!/usr/bin/env bash
# Check workflow syntax, expressions, dependencies and action inputs with the CI version of actionlint.
set -euo pipefail

version=1.7.12
sha256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
if [[ "$(uname -s)/$(uname -m)" != Linux/x86_64 ]]; then
  echo 'The pinned actionlint distribution requires Linux x86-64.' >&2
  exit 1
fi

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
url="https://github.com/rhysd/actionlint/releases/download/v$version/actionlint_${version}_linux_amd64.tar.gz"
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  --connect-timeout 10 --max-time 60 --retry 3 --retry-max-time 100 "$url" --output "$work/actionlint.tar.gz"
printf '%s  %s\n' "$sha256" "$work/actionlint.tar.gz" | sha256sum --check --strict
tar -xzf "$work/actionlint.tar.gz" -C "$work" actionlint
"$work/actionlint" -shellcheck= -pyflakes=
