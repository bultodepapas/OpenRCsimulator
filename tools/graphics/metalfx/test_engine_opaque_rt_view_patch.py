"""Portable 0027 source controls; no Godot, SDK or GPU qualification."""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest
import zipfile

import engine
import test_engine_displaylink_resize_patch as baseline26

HERE = Path(__file__).resolve().parent
REPO = next(p for p in (HERE, *HERE.parents) if (p / "tools/graphics/metalfx/engine.py").is_file())
PATCH = HERE / "patches/0027-metalfx-opaque-rt-view.patch"
PATCH_SHA = "2fa501f6c06938a9d24f107661096641ca6ed8aa2257228fb09c3a89d3584f99"
BASE_CATALOG = "bf1cf4710eef2c008fdc8c08cb17a056e828fb02ca03d1ca68484969e1960e7c"
FINAL_CATALOG = "a4754c95a2ed6163f3648562287155e89f11001c8cb3bd5281dab178d5cd9707"
PRIMARY_SHA = "48fba8f7cee304a44f3b1fc9fd36480918497d557c6c98fdb345c3ae796df49a"
CONSUMER_SHA = "2f4af6efe4f6978da4970b426ef450993ff7e2888d7e6a38f4c1488eb15322bc"
EFFECT = "servers/rendering/renderer_rd/effects/"
STORAGE = "servers/rendering/storage/"


def section(path: str) -> str:
    text = PATCH.read_text(encoding="utf-8")
    marker = f"diff --git a/{path} b/{path}\n"
    if text.count(marker) != 1:
        raise ValueError("missing or duplicated patch section: " + path)
    return text.split(marker, 1)[1].split("\ndiff --git ", 1)[0]


def added_file(path: str) -> str:
    part = section(path)
    if not part.startswith("new file mode 100644\n--- /dev/null\n+++ b/" + path + "\n"):
        raise ValueError("expected a new regular file: " + path)
    hunks = re.findall(r"(?m)^@@ -0,0 \+1(?:,(\d+))? @@\n", part)
    if len(hunks) != 1:
        raise ValueError("unexpected new-file hunks: " + path)
    lines = re.split(r"(?m)^@@ -0,0 \+1(?:,\d+)? @@\n", part, maxsplit=1)[1].splitlines(keepends=True)
    count = int(hunks[0] or "1")
    if len(lines) != count or any(not line.startswith("+") for line in lines):
        raise ValueError("unexpected new-file contents: " + path)
    return "".join(line[1:] for line in lines)


def added_lines(path: str) -> str:
    return "".join(line[1:] for line in section(path).splitlines(keepends=True)
                   if line.startswith("+") and not line.startswith("+++"))


def compiler() -> str:
    result = os.environ.get("CXX") or shutil.which("g++") or shutil.which("clang++") or shutil.which("c++")
    if not result:
        raise unittest.SkipTest("a C++ compiler is required")
    return result


def compile_run(program: str, headers: dict[str, str] | None = None, flags: tuple[str, ...] = ()) -> int:
    with baseline26.local_temporary_directory() as root:
        for name, text in (headers or {}).items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8", newline="\n")
        source, executable = root / "main.cpp", root / ("main.exe" if os.name == "nt" else "main")
        source.write_text(program, encoding="utf-8", newline="\n")
        command = [compiler(), "-std=c++17", "-Wall", "-Wextra", "-Werror", *flags,
                   "-I", str(root), str(source), "-o", str(executable)]
        built = subprocess.run(command, capture_output=True, text=True, timeout=60)
        if built.returncode:
            raise AssertionError("control failed to compile:\n" + built.stderr)
        return subprocess.run([str(executable)], capture_output=True, timeout=20).returncode


CHECK = "#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)\n"


class OpaqueRTViewSourceControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if engine.sha256(PATCH) != PATCH_SHA:
            raise ValueError("0027 patch differs from its pin")

    def test_closed_gate_output_usage_and_exact_shaders(self) -> None:
        self.assertEqual(len(engine.patch_paths([PATCH])), 29)
        patch = PATCH.read_text(encoding="utf-8")
        self.assertNotIn("GUIDE_INPUT_RECEIPT_IMPLEMENTED = true", patch)
        self.assertNotIn("OPENRC_MFX_TEXTURE_MISMATCH", patch)
        effect = added_file(EFFECT + "metalfx_viewport_denoised.cpp")
        self.assertEqual(effect.count("GUIDE_INPUT_RECEIPT_IMPLEMENTED = false"), 1)
        admit = effect.split("bool MetalFXViewportDenoised::admit(", 1)[1].split("bool MetalFXViewportDenoised::can_record()", 1)[0]
        self.assertLess(admit.index('reject("guide_inputs_unqualified")'), admit.index("allocate(p_size)"))
        self.assertLess(admit.index('reject("guide_inputs_unqualified")'), admit.index("scene.build("))
        self.assertIn("sample | storage | RD::TEXTURE_USAGE_COLOR_ATTACHMENT_BIT", effect)
        self.assertIn("texture_is_format_supported_for_usage(formats[i], usage[i])", effect)
        self.assertIn("metalfx_rt_compute_pipeline_id(visibility.get_trace_pipeline()).id", effect)
        visibility = added_file(EFFECT + "metalfx_viewport_visibility.cpp")
        self.assertIn("rayQueryGetIntersectionInstanceCustomIndexEXT(primary, true)", visibility)
        self.assertIn("rayQueryGetIntersectionPrimitiveIndexEXT(primary, true)", visibility)
        self.assertIn("geometry.normals[range.x + primitive]", visibility)
        for symbol, expected in (("metalfx_viewport_visibility_shader", PRIMARY_SHA),
                                 ("metalfx_viewport_consumer_shader", CONSUMER_SHA)):
            marker = symbol + ' = R"GLSL('
            self.assertEqual(visibility.count(marker), 1)
            source = visibility.split(marker, 1)[1].split(')GLSL";', 1)[0].encode()
            self.assertEqual(hashlib.sha256(source).hexdigest(), expected)

    def test_compiled_startup_off_and_mutation(self) -> None:
        name = STORAGE + "metalfx_viewport_opt_in.h"
        header = added_file(name)
        source = r'''
#include "servers/rendering/storage/metalfx_viewport_opt_in.h"
#include <cstddef>
#include <cstdlib>
#include <new>
static std::size_t allocations = 0;
void *operator new(std::size_t n) { ++allocations; if (void *p=std::malloc(n)) return p; throw std::bad_alloc(); }
void operator delete(void *p) noexcept { std::free(p); }
void operator delete(void *p, std::size_t) noexcept { std::free(p); }
''' + CHECK + r'''
int main() {
    MFXViewportOptIn::StartupSwitch off; int lookups=0;
    off.initialize([&](){++lookups; return false;});
    const auto before=allocations;
    for (int i=0; i<1000000; ++i) CHECK(!off.requested());
    off.initialize([&](){++lookups; return true;});
    CHECK(!off.requested() && lookups==1 && allocations==before);
    MFXViewportOptIn::StartupSwitch on; on.initialize([&](){++lookups; return true;});
    CHECK(on.requested() && lookups==2);
}
'''
        needle = "return initialized && requested_value;"
        self.assertEqual(header.count(needle), 1)
        self.assertEqual(compile_run(source, {name: header}), 0)
        self.assertNotEqual(compile_run(source, {name: header.replace(needle, "return true;", 1)}), 0)

    def test_compiled_primary_ranges_and_command_receipts(self) -> None:
        geom = STORAGE + "metalfx_viewport_primary_geometry.h"
        callback = STORAGE + "metalfx_viewport_callback.h"
        g, c = added_file(geom), added_file(callback)
        source = r'''
#include "servers/rendering/storage/metalfx_viewport_primary_geometry.h"
#include "servers/rendering/storage/metalfx_viewport_callback.h"
#include <limits>
''' + CHECK + r'''
int main() {
    using namespace MFXViewportPrimaryGeometry;
    float tris[18]={0,0,0, 1,0,0, 0,1,0, 0,0,0, 0,1,0, 0,0,1};
    Normal n[2]={}; CHECK(build_normals(reinterpret_cast<const uint8_t *>(tris),sizeof(tris),n,2));
    CHECK(n[0].z==1 && n[1].x==1);
    Range ranges[2]={{0,1,1,0},{1,1,2,0}}; uint32_t index=99;
    CHECK(lookup(ranges,2,2,1,0,index) && index==0);
    CHECK(lookup(ranges,2,2,2,0,index) && index==1);
    CHECK(!lookup(ranges,2,2,2,1,index));
    ranges[0].instance_id=2; ranges[1].instance_id=1;
    CHECK(!lookup(ranges,2,2,1,0,index));
    ranges[0].instance_id=1; ranges[1].instance_id=2;
    ranges[0].offset=1; ranges[1].offset=0;
    CHECK(!lookup(ranges,2,2,1,0,index));
    tris[15]=0; tris[16]=2; tris[17]=0;
    CHECK(!build_normals(reinterpret_cast<const uint8_t *>(tris),sizeof(tris),n,2));
    tris[17]=std::numeric_limits<float>::quiet_NaN();
    CHECK(!build_normals(reinterpret_cast<const uint8_t *>(tris),sizeof(tris),n,2));
    using namespace MFXViewportCallback;
    CHECK(!same_command(0,0) && !same_command(1,2) && same_command(1,1));
    CHECK(!producer_receipts_ready(true,false,true));
    DispatchLedger ledger; CHECK(ledger.begin(42)); ledger.note(43,true); CHECK(!ledger.finish(42));
    CHECK(ledger.begin(42)); ledger.note(42,true); CHECK(ledger.finish(42));
    CHECK(ledger.begin(42)); ledger.note(42,true); ledger.note(42,true); CHECK(!ledger.finish(42));
}
'''
        self.assertEqual(compile_run(source, {geom: g, callback: c}), 0)
        needle = "return p_first != 0 && p_first == p_last;"
        self.assertEqual(c.count(needle), 1)
        self.assertNotEqual(compile_run(source, {geom: g, callback: c.replace(needle, "return p_first == p_last;", 1)}), 0)

    def test_compiled_shared_argument_copy_and_failed_mapping(self) -> None:
        name = "drivers/metal/openrc_immutable_argument_upload.h"
        header = added_file(name)
        source = r'''
#include "drivers/metal/openrc_immutable_argument_upload.h"
#include <memory>
#include <vector>
''' + CHECK + r'''
struct Buffer { std::shared_ptr<std::vector<uint8_t>> bytes; };
int main() {
    using namespace OpenRCImmutableArguments;
    CHECK(eligible(true,true,true,true,true)); CHECK(!eligible(true,true,true,false,true));
    CHECK(slots_fit(3,1,32)); CHECK(!slots_fit(3,2,32));
    int released=0; bool fail=false;
    auto alloc=[](std::size_t n){return Buffer{std::make_shared<std::vector<uint8_t>>(n)};};
    auto map=[&](Buffer &b)->void * {return fail ? nullptr : b.bytes->data();};
    auto release=[&](Buffer &b){++released; b.bytes.reset();};
    uint8_t input[2]={1,2}; Buffer output;
    CHECK(create(output,input,sizeof(input),alloc,map,release)); input[0]=9;
    CHECK((*output.bytes)[0]==1 && (*output.bytes)[1]==2);
    fail=true; Buffer missing; CHECK(!create(missing,input,sizeof(input),alloc,map,release));
    CHECK(!missing.bytes && released==1);
}
'''
        self.assertEqual(compile_run(source, {name: header}), 0)
        needle = "p_release(candidate);"
        self.assertEqual(header.count(needle), 1)
        self.assertNotEqual(compile_run(source, {name: header.replace(needle, "(void)p_release;", 1)}), 0)

    def test_compiled_active_renderer_guard_and_teardown_mutations(self) -> None:
        cull = added_lines("servers/rendering/renderer_scene_cull.cpp")
        match = re.search(r'auto \*forward_renderer = RendererSceneRenderImplementation::RenderForwardClustered::get_singleton\(\);\n'
                          r'\s*if \(!forward_renderer \|\| scene_render != static_cast<RendererSceneRender \*>\(forward_renderer\)\) \{\n'
                          r'\s*rejection = "unsupported_renderer";\n\s*\}', cull)
        self.assertIsNotNone(match)
        guard = match.group(0)
        forward = added_lines("servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp")
        retire = "if (singleton == this) { singleton = nullptr; }"
        self.assertEqual(forward.count(retire), 1)
        before = r'''
#include <cstring>
''' + CHECK + r'''
class RendererSceneRender { public: virtual ~RendererSceneRender() = default; };
class RendererSceneRenderRD : public RendererSceneRender {};
namespace RendererSceneRenderImplementation {
class RenderForwardClustered : public RendererSceneRenderRD {
public:
    static RenderForwardClustered *singleton;
    static RenderForwardClustered *get_singleton() { return singleton; }
    ~RenderForwardClustered() override { @RETIRE@ }
};
RenderForwardClustered *RenderForwardClustered::singleton = nullptr;
}
class Mobile : public RendererSceneRenderRD {};
static bool admit(RendererSceneRender *scene_render, int &locks, int &casts, int &gpu) {
    const char *rejection=nullptr;
@GUARD@
    if (rejection) return false;
    ++locks; ++casts; ++gpu; return true;
}
int main() {
    using RendererSceneRenderImplementation::RenderForwardClustered;
    Mobile mobile; int locks=0, casts=0, gpu=0;
    CHECK(!admit(nullptr,locks,casts,gpu)); CHECK(!admit(&mobile,locks,casts,gpu));
    auto *first=new RenderForwardClustered; auto *second=new RenderForwardClustered;
    RenderForwardClustered::singleton=first;
    CHECK(!admit(&mobile,locks,casts,gpu)); CHECK(!admit(second,locks,casts,gpu));
    CHECK(locks==0 && casts==0 && gpu==0); CHECK(admit(first,locks,casts,gpu));
    RenderForwardClustered::singleton=second; delete first;
    CHECK(RenderForwardClustered::get_singleton()==second);
    delete second; CHECK(RenderForwardClustered::get_singleton()==nullptr);
}
'''
        def program(g: str, r: str) -> str:
            return before.replace("@GUARD@", g).replace("@RETIRE@", r)
        self.assertEqual(compile_run(program(guard, retire)), 0)
        self.assertNotEqual(compile_run(program(guard.replace("!forward_renderer || scene_render != static_cast<RendererSceneRender *>(forward_renderer)", "!forward_renderer || scene_render == nullptr", 1), retire)), 0)
        self.assertNotEqual(compile_run(program(guard, "singleton = nullptr;")), 0)


class ExactEngine26StackControls(unittest.TestCase):
    def test_exact_catalog_apply_and_guard_order(self) -> None:
        archive = Path(os.environ.get("OPENRC_METALFX_SOURCE_ARCHIVE", str(REPO / ".tools/apple-metalfx-cache" / f"godot-{engine.COMMIT}.zip")))
        if not archive.is_file():
            self.skipTest("pinned source ZIP unavailable; set OPENRC_METALFX_SOURCE_ARCHIVE")
        patches = [HERE / "patches" / name for name, _ in baseline26.PINS]
        self.assertEqual([engine.sha256(p) for p in patches], [value for _, value in baseline26.PINS])
        self.assertEqual(engine.sha256(PATCH), PATCH_SHA)
        with baseline26.local_temporary_directory() as root:
            before = engine.expected_catalog(archive, patches, root)
            after = engine.expected_catalog(archive, [*patches, PATCH], root)
            self.assertEqual((len(before), engine.digest_catalog(before)), (14449, BASE_CATALOG))
            self.assertEqual((len(after), engine.digest_catalog(after)), (14462, FINAL_CATALOG))
            self.assertEqual({name for name in before.keys() | after.keys() if before.get(name) != after.get(name)}, engine.patch_paths([PATCH]))
            paths = engine.patch_paths([*patches, PATCH])
            tree = root / "source"
            tree.mkdir()
            with zipfile.ZipFile(archive) as package:
                members = set(package.namelist())
                for name in paths:
                    member = engine.SOURCE_PREFIX + "/" + name
                    if member in members:
                        target = tree / name
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(package.read(member))
            engine.git(tree, "init", "--quiet")
            for patch in patches:
                engine.git(tree, "apply", "--check", str(patch))
                engine.git(tree, "apply", str(patch))
            checked = subprocess.run(["git", "-c", "core.autocrlf=false", "-C", str(tree), "apply", "--check", "--verbose", "--whitespace=error", str(PATCH)], capture_output=True, text=True)
            self.assertEqual(checked.returncode, 0, checked.stderr)
            self.assertEqual(checked.stderr.count("Checking patch "), 29)
            self.assertNotIn("Skipped patch", checked.stderr)
            engine.git(tree, "apply", str(PATCH))
            for name in engine.patch_paths([PATCH]):
                self.assertEqual(engine.sha256(tree / name), after[name], name)
            cull = (tree / "servers/rendering/renderer_scene_cull.cpp").read_text(encoding="utf-8")
            branch = cull.split("if (mfx_rb.is_valid() && mfx_rb->is_metalfx_viewport_denoised_requested())", 1)[1]
            guard = branch.index("if (!forward_renderer || scene_render != static_cast<RendererSceneRender *>(forward_renderer))")
            for later in ("mfx_source_lock = std::make_unique", "material_storage->material_get_data", "static_cast<SceneShader::MaterialData *>", "state->admit("):
                self.assertLess(guard, branch.index(later))
            buffers = (tree / "servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp").read_text(encoding="utf-8")
            ensure = buffers.split("RenderSceneBuffersRD::ensure_metalfx_viewport_denoised()", 1)[1].split("\n}", 1)[0]
            self.assertLess(ensure.index("if (!is_metalfx_viewport_denoised_requested())"), ensure.index("make_unique"))
            forward = (tree / "servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp").read_text(encoding="utf-8")
            destructor = forward.split("RenderForwardClustered::~RenderForwardClustered() {", 1)[1].split("\n}\n", 1)[0]
            self.assertTrue(destructor.rstrip().endswith("#endif"))
            self.assertIn("#if defined(METAL_ENABLED) && defined(MACOS_ENABLED)\n\tif (singleton == this) { singleton = nullptr; }\n#endif", destructor)


if __name__ == "__main__":
    unittest.main(verbosity=2)
