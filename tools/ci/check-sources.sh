#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
	echo "check-sources.sh requires Linux or WSL2 Ubuntu." >&2
	exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

SCHEMA_REQUIREMENTS="$ROOT/research/aircraft-data/schema/requirements.txt"
SCHEMA_VENV="$ROOT/.tools/aircraft-schema-venv"
SCHEMA_PYTHON="$SCHEMA_VENV/bin/python"
mkdir -p "$ROOT/.tools"
if [[ ! -x "$SCHEMA_PYTHON" ]]; then
	python3 -m venv "$SCHEMA_VENV"
fi

echo "== Aircraft v2 schema and loader contract =="
"$SCHEMA_PYTHON" -m pip install -r "$SCHEMA_REQUIREMENTS"
"$SCHEMA_PYTHON" research/aircraft-data/schema/check.py
"$SCHEMA_PYTHON" research/aircraft-data/schema/test_contract.py
"$SCHEMA_PYTHON" research/aircraft-standardization/test_schema_v2.py --godot "$(app/get-godot.sh)"

echo "== Generated geometry and physics freshness =="
python3 assets/aircraft/ugly-stik-60/compile_geometry.py --check
python3 assets/aircraft/extra-300s-60/compile_geometry.py --check
python3 assets/aircraft/extra-300s-60/compile_appearance.py --check
python3 assets/aircraft/avanti-s-a200/compile_geometry.py --check
python3 assets/aircraft/p51d-mustang-120/build_geometry.py --check
python3 assets/aircraft/p51d-mustang-120/compile_geometry.py --check
python3 research/extra-300/ex05/derive_physics.py --check
python3 research/p51/p51-05/derive_physics.py --check
python3 research/timber/tt01/manifest.py --check
python3 assets/aircraft/turbo-lumber-evolution/build_geometry.py --check
python3 assets/aircraft/turbo-lumber-evolution/compile_geometry.py --check
python3 research/timber/tt07/derive_physics.py --check
