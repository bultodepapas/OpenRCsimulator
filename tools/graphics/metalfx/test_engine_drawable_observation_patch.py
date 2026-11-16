"""Source-bound controls for the optional ordinary Metal drawable observer."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

HERE = Path(__file__).resolve().parent
REPO = next(p for p in (HERE, *HERE.parents) if (p / "tools/graphics/metalfx/engine.py").is_file())
spec = importlib.util.spec_from_file_location("drawable_engine", REPO / "tools/graphics/metalfx/engine.py")
ENGINE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ENGINE)

NAMES = (
    "0001-metalfx-allocation-fallback.patch", "0002-metalfx-history-reset.patch",
    "0003-metalfx-debug-faults.patch", "0004-metalfx-frame-inputs.patch",
    "0005-metal-triangle-query.patch", "0006-metalfx-gpu-observation.patch",
    "0007-metalfx-denoised-binding.patch", "0008-metal-paired-presentation.patch",
    "0009-metalfx-frame-composition.patch", "0010-metal-empty-submit-fence.patch",
    "0011-metalfx-presentation-adapter.patch", "0012-rd-gpu-failure-stop.patch",
    "0013-metalfx-real-completion.patch", "0014-metal-present-callback-lock.patch",
    "0015-metal-present-decision-observation.patch", "0016-metal-present-pacing.patch",
    "0017-metal-present-submission-lifetime.patch", "0018-metal-rt-scene-inputs.patch",
    "0019-metalfx-conditional-history-reset.patch", "0021-metal-rt-extension-abi.patch",
    "0024-apple-arm64-sha256.patch", "0025-metal-ordinary-drawable-observation.patch",
)
HASHES = (
    "f04167e05f452bfc37e85e90d512373d92c3f6ec808cef8431a0705e197d716a",
    "d7570f1b3639616e4e565a920cc4b9caca844bf7d1c8b3ec7d14d6e596c4ecc5",
    "cdacbdf81c80e44b96b200f1890236774225d93d8b54299f8e7db47b9f2c21cd",
    "2cfc1c4b466dfba51ae940d4c0529d290bf5a4502cd562d52edc4c4712e1ce18",
    "825920ed18b56dd3d531eda30d25ffb9da33b6becb29dd849c03073ff375e155",
    "565aec0587e8d5b8895f8e9025be316437a9cda0f7207e5c02214f0bf9cfd272",
    "d3ce4cb242eb311d214535ce695c744c2a15801b1226c940fb707b71bce64166",
    "e4b73172a8025a1702a04ee818b0e0591d68ec814610d22a6441420ebdfef18a",
    "5ca9396cc846a7f6b72a42f06d1785124e605e4a983e565a31cdf4273dc29333",
    "e72d1d5659213f34b582b2c55e88e2bf50a54c24bc38f3dc3c985130a3c063a4",
    "d6ebee96e1717b7f2d6d5b3b63da82d0c3238582a9bb51bda5a749b70ff55640",
    "55c185f928b9e1d742568f3803d5bec70450177d30ddf976723f8f4197f33fdb",
    "4557e956812dd07a5457763d9f59266520c39f04053ecf2977364c345c4e8cda",
    "a15caae49bb4d543043e009fd63a63f88c433e8d8ccbbc139ade6acf6a991468",
    "5e1b25dc8e3296423dae24489cd8b936a6cfbaf32a0fc6b006c6bec0b1971b9d",
    "6592562afd4208d211e924cd1330b6fb58a05d88b0161f43a51d133d6863efbe",
    "db0f4aad4eced890cd5a072be1b69aa5ca6331d41c1a700b12a8ed967357b746",
    "8339b8978c21a1133b8b6e144de0dc182a9c29a7cb39677fa628b3105dee5c82",
    "6a71e3e6eee7542996f52a318085f892ada178b1800c28a173129e07b500b289",
    "48eeb2f9a504d61af7c3222fabda86826e445cd539a7c2c3d4db85157ad90fca",
    "4cddc3ce281a7a5bed2f453a3fbad0db8c41836a9161007aa6d75c358dbcb348",
    "3e025791807d1854f3fd80e136a27e6ecbea03734b389be71b1c4d2d711035e3",
)


def patch_path(name: str) -> Path:
    local = HERE / "patches" / name
    return local if local.is_file() else REPO / "tools/graphics/metalfx/patches" / name


PATCHES = tuple(patch_path(name) for name in NAMES)
HEADER = "drivers/metal/openrc_drawable_observation.h"
CHANGED = {
    HEADER, "drivers/metal/rendering_context_driver_metal.h",
    "drivers/metal/rendering_context_driver_metal.cpp", "servers/rendering/rendering_device.h",
    "servers/rendering/rendering_device.cpp",
}


def added_header() -> str:
    text = PATCHES[-1].read_text(encoding="utf-8")
    part = text.split("diff --git a/" + HEADER + " b/" + HEADER + "\n", 1)[1]
    lines = part.split("@@ -0,0 +1,56 @@\n", 1)[1].splitlines()
    if len(lines) != 56 or any(not line.startswith("+") for line in lines):
        raise ValueError("unexpected added-header hunk")
    return "\n".join(line[1:] for line in lines) + "\n"


HARNESS = r'''
#include "drivers/metal/openrc_drawable_observation.h"
#include <exception>
#include <thread>
#include <vector>
using namespace OpenRCDrawableObservation;
int main() {
    auto first=allocate_scope(), second=allocate_scope();
    if (!first || second!=first+1 || !Tracker(0).snapshot().failed) return 1;
    Tracker t(first); t.record(true,1920,1080,80); t.record(true,1920,1080,80);
    auto a=t.snapshot(); if(a.scope!=first || a.attempts!=2 || a.observed!=2 || a.missed || a.changes) return 2;
    t.record(true,1280,720,80); t.record(true,1920,1080,80);
    t.record(false,1920,1080,80); t.record(true,0,1080,80); t.record(true,1920,1080,0);
    auto b=t.snapshot(); if(b.attempts!=7 || b.observed!=4 || b.missed!=3 || b.changes!=2 ||
        b.width!=1920 || b.height!=1080 || b.pixel_format!=80) return 3;
    Tracker concurrent(second); std::vector<std::thread> threads;
    for(int i=0;i<8;i++) threads.emplace_back([&concurrent,i](){
        for(int j=0;j<4000;j++) { concurrent.record(true,i&1?1920:1280,i&1?1080:720,80);
            auto s=concurrent.snapshot(); if(s.attempts!=s.observed+s.missed ||
                (s.observed && s.height*16!=s.width*9)) std::terminate(); }
    });
    for(auto &thread:threads) thread.join();
    auto c=concurrent.snapshot(); if(c.failed || c.attempts!=32000 || c.observed!=32000 || c.missed) return 4;
    next_scope.store(LIMIT,std::memory_order_relaxed); if(allocate_scope() || allocate_scope()) return 5;
    return 0;
}
'''


class DrawablePatchControls(unittest.TestCase):
    def test_patch_identity_and_paths(self):
        self.assertEqual(ENGINE.sha256(PATCHES[-1]), HASHES[-1])
        self.assertEqual(ENGINE.patch_paths([PATCHES[-1]]), CHANGED)
        self.assertIn("never retains a Metal object", added_header())

    def test_actual_tracker_and_mutations(self):
        compiler = shutil.which("g++") or shutil.which("clang++") or shutil.which("c++")
        if not compiler:
            self.skipTest("C++ compiler unavailable")
        original = added_header()
        mutations = {
            "extent": ("value.changes++;", "/* omitted */"),
            "unrequested": ("!p_framebuffer_requested || ", "(p_framebuffer_requested && false) || "),
            "zero_format": ("p_format == 0 || ", ""),
            "missed": ("value.missed++;", "/* omitted */"),
        }
        with tempfile.TemporaryDirectory(prefix="drawable25-tracker-") as folder:
            root = Path(folder)
            (root / "drivers/metal").mkdir(parents=True)
            main = root / "main.cpp"
            main.write_text(HARNESS, encoding="utf-8")
            for name, source in [("actual", original), *[(name, original.replace(old, new, 1)) for name, (old, new) in mutations.items()]]:
                if name != "actual":
                    self.assertEqual(original.count(mutations[name][0]), 1)
                (root / HEADER).write_text(source, encoding="utf-8", newline="\n")
                exe = root / (name + (".exe" if os.name == "nt" else ""))
                subprocess.run([compiler, "-std=c++17", "-pthread", "-Wall", "-Wextra", "-Werror", "-I", str(root), str(main), "-o", str(exe)], check=True, capture_output=True)
                result = subprocess.run([str(exe)], check=False, capture_output=True)
                self.assertEqual(result.returncode == 0, name == "actual", name)


class ExactStackControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        default = REPO / ".tools/apple-metalfx-cache" / f"godot-{ENGINE.COMMIT}.zip"
        archive = Path(os.environ.get("OPENRC_METALFX_SOURCE_ARCHIVE", str(default)))
        if not archive.is_file():
            raise unittest.SkipTest("pinned Godot ZIP unavailable; set OPENRC_METALFX_SOURCE_ARCHIVE")
        if ENGINE.sha256(archive) != ENGINE.SOURCE_SHA256:
            raise ValueError("source archive differs from the engine pin")
        if tuple(ENGINE.sha256(p) for p in PATCHES) != HASHES:
            raise ValueError("ordered 1–19, 21, 24, 25 patch hashes differ")
        cls.temporary = tempfile.TemporaryDirectory(prefix="drawable25-stack-")
        cls.root = Path(cls.temporary.name)
        paths = ENGINE.patch_paths(list(PATCHES))
        with zipfile.ZipFile(archive) as package:
            members = set(package.namelist())
            for name in paths:
                member = ENGINE.SOURCE_PREFIX + "/" + name
                if member in members:
                    target = cls.root / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(package.read(member))
        ENGINE.git(cls.root, "init", "--quiet")
        top = subprocess.check_output(["git", "-C", str(cls.root), "rev-parse", "--show-toplevel"], text=True).strip()
        if Path(top).resolve() != cls.root.resolve():
            raise RuntimeError("patch fixture did not get its own Git root")
        for patch in PATCHES[:-1]:
            ENGINE.git(cls.root, "apply", "--check", str(patch.resolve()))
            ENGINE.git(cls.root, "apply", str(patch.resolve()))
        cls.baseline = (cls.root / "drivers/metal/rendering_context_driver_metal.cpp").read_text(encoding="utf-8")
        ENGINE.git(cls.root, "apply", "--check", str(PATCHES[-1].resolve()))
        ENGINE.git(cls.root, "apply", str(PATCHES[-1].resolve()))
        cls.catalog = ENGINE.expected_catalog(archive, list(PATCHES), cls.root)

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "temporary"):
            cls.temporary.cleanup()

    def test_engine_intake_catalog_matches_changed_files(self):
        for name in CHANGED:
            self.assertEqual(ENGINE.sha256(self.root / name), self.catalog[name], name)
        self.assertEqual((self.root / HEADER).read_text(encoding="utf-8"), added_header())

    def test_existing_drawable_off_path_and_lifetime_guard(self):
        source = (self.root / "drivers/metal/rendering_context_driver_metal.cpp").read_text(encoding="utf-8")
        rd = (self.root / "servers/rendering/rendering_device.cpp").read_text(encoding="utf-8")
        self.assertEqual(source.count('get_environment("OPENRC_NATIVE_DRAWABLE_OBSERVATION") == "1"'), 1)
        self.assertIn("if (openrc_drawable_requested())", source)
        self.assertEqual(source.count("openrc_drawable_tracker && frame_buffer.has_texture(0)"), 2)
        self.assertEqual(source.count("openrc_record_drawable(framebuffer_requested, drawable)"), 2)
        for signature in ("void present(MTL3::MDCommandBuffer *p_cmd_buffer) override {",
                          "MTL::Drawable *next_drawable() override {"):
            body = source.split(signature, 1)[1].split("\n\t}", 1)[0]
            self.assertLess(body.index("frame_buffer.has_texture(0)"), body.index("frame_buffer.get_drawable()"))
            self.assertLess(body.index("openrc_record_drawable(framebuffer_requested, drawable)"), body.index("frame_buffer.reset()"))
        self.assertIn("p_framebuffer_requested && p_drawable ? p_drawable->texture() : nullptr", source)
        self.assertIn("openrc_drawable_tracker->record(texture != nullptr", source)
        self.assertEqual(source.count("layer->nextDrawable()"), self.baseline.count("layer->nextDrawable()"))
        self.assertEqual(source.count("frame_buffer.get_drawable()"), self.baseline.count("frame_buffer.get_drawable()"))
        self.assertIn("RenderingContextDriverMetal::openrc_presenter_requested() || openrc_presenter", source)
        getter = rd.split("Dictionary RenderingDevice::openrc_drawable_observation() const {", 1)[1].split("\n}", 1)[0]
        free = rd.split("Error RenderingDevice::screen_free(", 1)[1].split("\n}", 1)[0]
        self.assertIn("ERR_RENDER_THREAD_GUARD_V", getter)
        self.assertIn("_THREAD_SAFE_METHOD_", getter)
        self.assertIn("_THREAD_SAFE_METHOD_", free)
        self.assertIn("screen_swap_chains.has(DisplayServerEnums::MAIN_WINDOW_ID)", getter)
        self.assertIn('"query_before_usec"', getter)
        self.assertIn('"query_after_usec"', getter)
        self.assertNotIn("nextDrawable", getter)
        self.assertIn('"acquired_framebuffer_texture_not_scanout"', source)


if __name__ == "__main__":
    unittest.main()
