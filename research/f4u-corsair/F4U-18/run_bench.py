"""F4U-18: set up the isolated render bench outside the repository and run it once per model, one at a time.

Copies bench/ into BENCH_DIR, copies each GLB into BENCH_DIR/models/ with the app's Corsair import settings
(LODs, shadow meshes, tangents, uncompressed vertices), imports headless, then runs bench.gd windowed per model:
textured (timing and screenshots) and clay (uniform grey material, screenshots for geometry comparison).

    python research/f4u-corsair/F4U-18/run_bench.py --bench D:/.../godot-bench --out D:/.../results/<new> \
        --godot .tools/Godot_v4.7.2-stable_win64_console.exe --resolution 1920x1080 name=path/to/model.glb ...
Run nothing else on the CPU or GPU meanwhile.
"""
import argparse, json, shutil, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/force_disable_compression=true
animation/import=false
gltf/naming_version=2
gltf/embedded_image_handling=2
gltf/texture_map_mode=1
"""


def run(cmd, log, timeout):
    t0 = time.time()
    with open(log, "w", encoding="utf-8") as f:
        code = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, timeout=timeout).returncode
    return code, round(time.time() - t0, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--godot", required=True)
    ap.add_argument("--resolution", default="1920x1080")
    ap.add_argument("--frames", default="300")
    ap.add_argument("--no-clay", action="store_true")
    ap.add_argument("--import-only", action="store_true")
    ap.add_argument("models", nargs="+")
    a = ap.parse_args()
    bench, out = Path(a.bench), Path(a.out)
    if out.exists():
        sys.exit(f"{out} exists; pass a new directory")
    out.mkdir(parents=True)
    (bench / "models").mkdir(parents=True, exist_ok=True)
    for name in ["bench.gd", "project.godot", "cameras.json"]:
        shutil.copy2(HERE / "bench" / name, bench / name)
    models = dict(m.split("=", 1) for m in a.models)
    for name, src in models.items():
        dst = bench / "models" / f"{name}.glb"
        if not dst.exists() or dst.stat().st_size != Path(src).stat().st_size:
            shutil.copy2(src, dst)
            (bench / "models" / f"{name}.glb.import").write_text(IMPORT, encoding="utf-8")
    code, secs = run([a.godot, "--headless", "--path", str(bench), "--import"], out / "import.log", 3600)
    summary = {"import_exit": code, "import_s": secs, "resolution": a.resolution, "runs": {}}
    print("import", code, secs, "s", flush=True)
    for name in ([] if a.import_only else models):
        for mode in ([] if a.no_clay else ["clay"]) + ["textured"]:
            tag = f"{name}-{mode}"
            args = [a.godot, "--rendering-driver", "opengl3", "--resolution", a.resolution, "--path", str(bench),
                    "--script", "res://bench.gd", "--", f"--model=res://models/{name}.glb",
                    f"--out={(out / (tag + '.json')).as_posix()}", f"--shots={(out / 'shots' / tag).as_posix()}",
                    f"--frames={a.frames if mode == 'textured' else 30}"] + (["--clay"] if mode == "clay" else [])
            code, secs = run(args, out / f"{tag}.log", 1800)
            summary["runs"][tag] = {"exit": code, "wall_s": secs}
            print(tag, code, secs, "s", flush=True)
    (out / "summary.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
