#!/usr/bin/env bash
# CI and the local source phase share this exact generator roster.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
python3 assets/aircraft/ugly-stik-60/compile_geometry.py --check
python3 assets/aircraft/extra-300s-60/compile_geometry.py --check
python3 assets/aircraft/extra-300s-60/compile_appearance.py --check
python3 assets/aircraft/avanti-s-a200/compile_geometry.py --check
python3 assets/aircraft/p51d-mustang-120/build_geometry.py --check
python3 assets/aircraft/p51d-mustang-120/compile_geometry.py --check
python3 research/extra-300/ex14/ground_effect_vlm.py --check
python3 research/extra-300/ex05/derive_physics.py --check
python3 research/p51/p51-05/derive_physics.py --check
python3 research/timber/tt01/manifest.py --check
python3 assets/aircraft/turbo-lumber-evolution/build_geometry.py --check
python3 assets/aircraft/turbo-lumber-evolution/compile_geometry.py --check
python3 research/timber/tt07/derive_physics.py --check
python3 research/skywalker-x8/X8-00/manifest.py --check
python3 research/skywalker-x8/X8-02/install_assets.py --check
python3 research/skywalker-x8/X8-02/compile_model.py --check
python3 research/skywalker-x8/X8-06/derive_physics.py --check
