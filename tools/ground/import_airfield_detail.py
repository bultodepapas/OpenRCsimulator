#!/usr/bin/env python3
"""Download and verify unmodified CC0 Poly Haven airfield detail assets."""

from __future__ import annotations

import hashlib
import json
import urllib.request
from pathlib import Path
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "app/assets/landscape/airfield_detail"
API = "https://api.polyhaven.com/files/"
MODELS = ("flower_empodium",)
TEXTURES = {"river_small_rocks": ("Diffuse",), "sparse_grass": ("Diffuse",)}
ROCK_SOURCE = ROOT / "assets/landscape/vegetation/source/quaternius_stylized_nature_megakit_standard.zip"
ROCK_MEMBERS = ("Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3")
HEADERS = {"User-Agent": "Mozilla/5.0 (OpenRCsimulator asset importer)"}


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read()


def save(path: Path, record: dict) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    expected = record["md5"]
    if path.exists() and hashlib.md5(path.read_bytes()).hexdigest() == expected:
        data = path.read_bytes()
    else:
        data = fetch(record["url"])
        if hashlib.md5(data).hexdigest() != expected:
            raise ValueError(f"Supplier checksum mismatch: {path}")
        path.write_bytes(data)
    return {
        "path": path.relative_to(ROOT).as_posix(),
        "url": record["url"],
        "bytes": len(data),
        "md5": expected,
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def main() -> None:
    manifest = {
        "generated_by": "tools/ground/import_airfield_detail.py",
        "license": "CC0 1.0 Universal",
        "assets": {},
    }
    for slug in MODELS:
        metadata = json.loads(fetch(API + slug))
        source = metadata["gltf"]["1k"]["gltf"]
        entries = [save(DEST / slug / f"{slug}_1k.gltf", source)]
        for name, record in sorted(source["include"].items()):
            entries.append(save(DEST / slug / name, record))
        if slug == "flower_empodium":
            entries.append(save(DEST / slug / "textures/flower_empodium_alpha_1k.jpg",
                                metadata["Alpha"]["1k"]["jpg"]))
        manifest["assets"][slug] = {
            "source": f"https://polyhaven.com/a/{slug}",
            "license_url": "https://polyhaven.com/license",
            "type": "original glTF model set, 1K textures",
            "files": entries,
        }
    with ZipFile(ROCK_SOURCE) as archive:
        entries = []
        for name in (*ROCK_MEMBERS, "Rocks_Diffuse"):
            for suffix in ((".gltf", ".bin") if name in ROCK_MEMBERS else (".png",)):
                filename = name + suffix
                data = archive.read("glTF/" + filename)
                path = DEST / "quaternius_rocks" / filename
                path.parent.mkdir(parents=True, exist_ok=True)
                if not path.exists() or path.read_bytes() != data:
                    path.write_bytes(data)
                entries.append({
                    "path": path.relative_to(ROOT).as_posix(),
                    "source_member": "glTF/" + filename,
                    "bytes": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                })
        manifest["assets"]["quaternius_rocks"] = {
            "source": "https://quaternius.itch.io/stylized-nature-megakit",
            "source_archive": ROCK_SOURCE.relative_to(ROOT).as_posix(),
            "license": "CC0-1.0, embedded License_Standard.txt",
            "license_evidence": "assets/landscape/vegetation/source/License_Standard.txt",
            "type": "unmodified source rock meshes and atlas",
            "files": entries,
        }
    for slug, maps in TEXTURES.items():
        metadata = json.loads(fetch(API + slug))
        entries = []
        for map_name in maps:
            record = metadata[map_name]["2k"]["jpg"]
            entries.append(save(DEST / slug / f"{slug}_{map_name}_2k.jpg", record))
        manifest["assets"][slug] = {
            "source": f"https://polyhaven.com/a/{slug}",
            "license_url": "https://polyhaven.com/license",
            "type": "original 2K PBR texture maps",
            "files": entries,
        }
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {sum(len(a['files']) for a in manifest['assets'].values())} CC0 files")


if __name__ == "__main__":
    main()
