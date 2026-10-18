import json
import subprocess
from pathlib import Path

root = Path(r"C:\DEVELOPMENT\OpenRCsimulator")
godot = root / ".tools" / "Godot_v4.7.2-stable_win64.exe"
project = root / "tmp" / "tree-continuation-assets" / "oak-native-preview-project"
source = root / "assets" / "landscape" / "vegetation" / "source" / "opengameart_oak_tree_lod_2026" / "gltf" / "lod0" / "oak_lod0.gltf"
output = root / "tmp" / "tree-continuation-assets" / "native-preview-oak-20261018"
command = [
    str(godot),
    "--path", str(project),
    "--audio-driver", "Dummy",
    "--rendering-method", "gl_compatibility",
    "--script", "res://oak_source_gallery.gd",
    "--",
    f"--source={source.as_posix()}",
    f"--out={output.as_posix()}",
    "--capture=on",
    "--frame_height_m=14.0",
    "--width=1280",
    "--height=1280",
]
result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=180)
print(json.dumps({"argv": command, "returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr}, indent=2))
raise SystemExit(result.returncode)
