"""Portable source-bound controls; native Core Animation behavior is separate."""
from __future__ import annotations

import os
import hashlib
import importlib.util
from contextlib import contextmanager
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
import zipfile

HERE = Path(__file__).resolve().parent
REPO = next(p for p in (HERE, *HERE.parents) if (p / "tools/graphics/metalfx/engine.py").is_file())
spec = importlib.util.spec_from_file_location("displaylink_resize_engine", REPO / "tools/graphics/metalfx/engine.py")
ENGINE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ENGINE)
RELATIVE = Path("drivers/metal/rendering_context_driver_metal.cpp")
PATCH = HERE / "patches/0026-metal-displaylink-resize.patch"
PINS = (
    ('0001-metalfx-allocation-fallback.patch', 'f04167e05f452bfc37e85e90d512373d92c3f6ec808cef8431a0705e197d716a'),
    ('0002-metalfx-history-reset.patch', 'd7570f1b3639616e4e565a920cc4b9caca844bf7d1c8b3ec7d14d6e596c4ecc5'),
    ('0003-metalfx-debug-faults.patch', 'cdacbdf81c80e44b96b200f1890236774225d93d8b54299f8e7db47b9f2c21cd'),
    ('0004-metalfx-frame-inputs.patch', '2cfc1c4b466dfba51ae940d4c0529d290bf5a4502cd562d52edc4c4712e1ce18'),
    ('0005-metal-triangle-query.patch', '825920ed18b56dd3d531eda30d25ffb9da33b6becb29dd849c03073ff375e155'),
    ('0006-metalfx-gpu-observation.patch', '565aec0587e8d5b8895f8e9025be316437a9cda0f7207e5c02214f0bf9cfd272'),
    ('0007-metalfx-denoised-binding.patch', 'd3ce4cb242eb311d214535ce695c744c2a15801b1226c940fb707b71bce64166'),
    ('0008-metal-paired-presentation.patch', 'e4b73172a8025a1702a04ee818b0e0591d68ec814610d22a6441420ebdfef18a'),
    ('0009-metalfx-frame-composition.patch', '5ca9396cc846a7f6b72a42f06d1785124e605e4a983e565a31cdf4273dc29333'),
    ('0010-metal-empty-submit-fence.patch', 'e72d1d5659213f34b582b2c55e88e2bf50a54c24bc38f3dc3c985130a3c063a4'),
    ('0011-metalfx-presentation-adapter.patch', 'd6ebee96e1717b7f2d6d5b3b63da82d0c3238582a9bb51bda5a749b70ff55640'),
    ('0012-rd-gpu-failure-stop.patch', '55c185f928b9e1d742568f3803d5bec70450177d30ddf976723f8f4197f33fdb'),
    ('0013-metalfx-real-completion.patch', '4557e956812dd07a5457763d9f59266520c39f04053ecf2977364c345c4e8cda'),
    ('0014-metal-present-callback-lock.patch', 'a15caae49bb4d543043e009fd63a63f88c433e8d8ccbbc139ade6acf6a991468'),
    ('0015-metal-present-decision-observation.patch', '5e1b25dc8e3296423dae24489cd8b936a6cfbaf32a0fc6b006c6bec0b1971b9d'),
    ('0016-metal-present-pacing.patch', '6592562afd4208d211e924cd1330b6fb58a05d88b0161f43a51d133d6863efbe'),
    ('0017-metal-present-submission-lifetime.patch', 'db0f4aad4eced890cd5a072be1b69aa5ca6331d41c1a700b12a8ed967357b746'),
    ('0018-metal-rt-scene-inputs.patch', '8339b8978c21a1133b8b6e144de0dc182a9c29a7cb39677fa628b3105dee5c82'),
    ('0019-metalfx-conditional-history-reset.patch', '6a71e3e6eee7542996f52a318085f892ada178b1800c28a173129e07b500b289'),
    ('0021-metal-rt-extension-abi.patch', '48eeb2f9a504d61af7c3222fabda86826e445cd539a7c2c3d4db85157ad90fca'),
    ('0024-apple-arm64-sha256.patch', '4cddc3ce281a7a5bed2f453a3fbad0db8c41836a9161007aa6d75c358dbcb348'),
    ('0025-metal-ordinary-drawable-observation.patch', '3e025791807d1854f3fd80e136a27e6ecbea03734b389be71b1c4d2d711035e3'),
    ('0026-metal-displaylink-resize.patch', '6f1ab3c9e511bca5430f4f98628f8016b49142dba3d5bcc36d01a6e4ba5147d1'),
)
BASE_SHA = "f303c9c64f8952205c3d18b5834c41b8cf1151e223e7baaf7660731518f30303"
WORK_SHA = "f0e955ce3e351252a47e669f40d4a4b32f912cee6dcd2051cde5e487f785dc86"
PATCH_SHA = "6f1ab3c9e511bca5430f4f98628f8016b49142dba3d5bcc36d01a6e4ba5147d1"


@contextmanager
def local_temporary_directory():
    root = Path(tempfile.mkdtemp(dir=HERE))
    if root.is_symlink() or root.resolve().parent != HERE.resolve():
        raise RuntimeError("temporary directory escaped the test workspace")
    try:
        yield root
    finally:
        for attempt in range(20):
            if root.is_symlink() or root.resolve().parent != HERE.resolve():
                raise RuntimeError("temporary directory changed before cleanup")
            try:
                shutil.rmtree(root)
                break
            except PermissionError:
                if attempt == 19:
                    raise
                time.sleep(0.1)


def sections(source: str) -> tuple[str, str]:
    begin = source.index("\tvoid openrc_presenter_stop() override {")
    end = source.index("\n\t}\n#endif", begin) + len("\n\t}")
    stop = source[begin:end]
    begin = source.index("\t\t// Metal supports a maximum of 3 drawables.", end)
    end = source.index("\n#if TARGET_OS_OSX", begin)
    return stop, source[begin:end]


HARNESS = r'''
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <vector>
#undef assert
// Return a failing status without a platform assertion dialog.
#define assert(condition) do { if (!(condition)) return __LINE__; } while (0)
#define MIN(a, b) std::min((a), (b))
#define ERR_CANT_CREATE 7
#define ERR_FAIL_COND_V_MSG(condition, value, message) do { if (condition) return (value); } while (0)

struct FakeLayer {
    uint32_t pool = 3;
    unsigned writes = 0;
    bool link_alive = false;
    bool invalid_set = false;
    void setMaximumDrawableCount(uint32_t count) {
        if (link_alive) { invalid_set = true; return; }
        pool = count;
        ++writes;
    }
};
struct Handle {
    bool active = false;
    FakeLayer *layer = nullptr;
    explicit operator bool() const { return active; }
    void reset() { active = false; }
};
namespace OpenRCMetalPresent {
void stop(Handle &handle) { if (handle.active) handle.layer->link_alive = false; }
}
struct FakeSurface {
    FakeLayer storage;
    FakeLayer *layer = &storage;
    Handle openrc_presenter;
    std::vector<int> frame_buffers;
    bool needs_resize = false;
    virtual ~FakeSurface() = default;
    virtual void openrc_presenter_stop() = 0;
    void start() { openrc_presenter = {true, layer}; layer->link_alive = true; }
    int resize_count(uint32_t p_desired_framebuffer_count) {
        REPLACE_COUNT
        frame_buffers.resize(p_desired_framebuffer_count);
        return 0;
    }
};
struct Surface : FakeSurface {
    REPLACE_STOP
};

int main() {
    Surface surface;
    assert(surface.resize_count(3) == 0 && surface.layer->pool == 3 && surface.frame_buffers.size() == 3);
    assert(surface.layer->writes == 1 && !surface.layer->invalid_set);
#ifdef MACOS_ENABLED
    surface.start();
    assert(surface.resize_count(2) == 0);
    assert(surface.layer->writes == 1 && !surface.layer->invalid_set);
    assert(surface.frame_buffers.size() == 3); // Preserve the pre-link ring.
    assert(surface.resize_count(3) == 0 && surface.layer->writes == 1);
    surface.openrc_presenter_stop();
    assert(!surface.layer->link_alive && surface.needs_resize);
    assert(surface.resize_count(2) == 0 && surface.layer->pool == 2 && surface.frame_buffers.size() == 2);
    assert(surface.layer->writes == 2 && !surface.layer->invalid_set);
    Surface empty;
    empty.start();
    assert(empty.resize_count(3) == ERR_CANT_CREATE);
    assert(empty.layer->writes == 0 && !empty.layer->invalid_set);
    Surface absent;
    absent.openrc_presenter_stop();
    assert(!absent.needs_resize);
#else
    assert(surface.resize_count(2) == 0 && surface.layer->pool == 2 && surface.frame_buffers.size() == 2);
    assert(surface.layer->writes == 2);
#endif
}
'''


class DisplayLinkResizeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        default = REPO / ".tools/apple-metalfx-cache" / f"godot-{ENGINE.COMMIT}.zip"
        archive = Path(os.environ.get("OPENRC_METALFX_SOURCE_ARCHIVE", str(default)))
        if not archive.is_file():
            raise unittest.SkipTest("pinned Godot ZIP unavailable; set OPENRC_METALFX_SOURCE_ARCHIVE")
        if ENGINE.sha256(archive) != ENGINE.SOURCE_SHA256:
            raise ValueError("source archive differs from the engine pin")
        patches = [(HERE / "patches" / name, digest) for name, digest in PINS]
        if any(ENGINE.sha256(path) != digest for path, digest in patches):
            raise ValueError("ordered 1–19, 21, 24, 25, 26 patch hashes differ")
        if ENGINE.patch_paths([PATCH]) != {RELATIVE.as_posix()}:
            raise ValueError("0026 patch modifies unexpected paths")
        cls.temporary = local_temporary_directory()
        root = cls.temporary.__enter__()
        cls.addClassCleanup(cls.temporary.__exit__, None, None, None)
        target = root / RELATIVE
        target.parent.mkdir(parents=True)
        with zipfile.ZipFile(archive) as package:
            target.write_bytes(package.read(ENGINE.SOURCE_PREFIX + "/" + RELATIVE.as_posix()))
        ENGINE.git(root, "init", "--quiet")
        top = subprocess.check_output(["git", "-C", str(root), "rev-parse", "--show-toplevel"], text=True).strip()
        if Path(top).resolve() != root.resolve():
            raise RuntimeError("patch fixture did not get its own Git root")
        applicable = 0
        for patch, _ in patches[:-1]:
            if RELATIVE.as_posix() not in ENGINE.patch_paths([patch]):
                continue
            arguments = ["apply", "--include=" + RELATIVE.as_posix()]
            ENGINE.git(root, *arguments, "--check", str(patch.resolve()))
            ENGINE.git(root, *arguments, str(patch.resolve()))
            applicable += 1
        if applicable == 0 or hashlib.sha256(target.read_bytes()).hexdigest() != BASE_SHA:
            raise ValueError("selected 1–25 source does not match the pinned baseline")
        cls.original = target.read_text(encoding="utf-8")
        ENGINE.git(root, "apply", "--check", str(PATCH.resolve()))
        ENGINE.git(root, "apply", str(PATCH.resolve()))
        if hashlib.sha256(target.read_bytes()).hexdigest() != WORK_SHA:
            raise ValueError("0026 patched source differs from the pinned result")
        cls.patched = target.read_text(encoding="utf-8")

    def setUp(self) -> None:
        self.assertEqual(ENGINE.sha256(PATCH), PATCH_SHA)
        self.source = self.patched
        self.stop, self.count = sections(self.source)

    def test_patch_applies_to_exact_selected_base(self) -> None:
        for normalize in (False, True):
            with self.subTest(normalized_lf=normalize), local_temporary_directory() as root:
                target = root / RELATIVE
                target.parent.mkdir(parents=True)
                original = self.original.encode("utf-8")
                expected = self.patched.encode("utf-8")
                if not normalize:
                    original, expected = original.replace(b"\n", b"\r\n"), expected.replace(b"\n", b"\r\n")
                target.write_bytes(original)
                subprocess.run(["git", "init", "--quiet", str(root)], check=True)
                git = ["git", "-c", "core.autocrlf=" + ("false" if normalize else "true"), "-C", str(root)]
                subprocess.run(git + ["apply", "--check", "--verbose", str(PATCH)], check=True)
                subprocess.run(git + ["apply", str(PATCH)], check=True)
                self.assertEqual(target.read_bytes(), expected)

    def test_only_count_and_stop_paths_changed(self) -> None:
        original = self.original
        old_stop, old_count = sections(original)
        self.assertEqual(self.source.replace(self.stop, old_stop, 1).replace(self.count, old_count, 1), original)
        self.assertIn("frame_buffers.resize(p_desired_framebuffer_count)", self.source)
        self.assertIn("layer->setDrawableSize(drawableSize)", self.source)
        self.assertIn("layer->setDisplaySyncEnabled(true)", self.source)
        self.assertIn("layer->setDisplaySyncEnabled(false)", self.source)

    def compile_and_run(self, stop: str, count: str, macos: bool) -> subprocess.CompletedProcess:
        compiler = os.environ.get("CXX") or shutil.which("g++") or shutil.which("clang++")
        if not compiler:
            self.skipTest("a C++ compiler is required")
        program = HARNESS.replace("REPLACE_STOP", stop).replace("REPLACE_COUNT", count)
        with local_temporary_directory() as root:
            source = root / "test.cpp"
            executable = root / ("test.exe" if os.name == "nt" else "test")
            source.write_text(program, encoding="utf-8")
            command = [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror"]
            if macos: command.append("-DMACOS_ENABLED")
            command += [str(source), "-o", str(executable)]
            subprocess.run(command, check=True, capture_output=True, text=True)
            return subprocess.run([str(executable)], capture_output=True, text=True, timeout=15)

    def test_compiled_ordinary_display_link_stop_and_nonmac(self) -> None:
        for macos in (True, False):
            with self.subTest(macos=macos):
                self.assertEqual(self.compile_and_run(self.stop, self.count, macos).returncode, 0)

    def test_compiled_guard_and_stop_mutations_fail(self) -> None:
        bad_count = self.count.replace("if (openrc_presenter)", "if (!openrc_presenter)", 1)
        bad_stop = self.stop.replace("if (had_presenter) { needs_resize = true; }", "(void)had_presenter;", 1)
        self.assertNotEqual(bad_count, self.count)
        self.assertNotEqual(bad_stop, self.stop)
        self.assertNotEqual(self.compile_and_run(self.stop, bad_count, True).returncode, 0)
        self.assertNotEqual(self.compile_and_run(bad_stop, self.count, True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
