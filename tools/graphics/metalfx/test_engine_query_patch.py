"""Source-bound checks and an opt-in native runner for Metal triangle queries.

Portable controls compile actual patched validation/packing functions with small
C++ stand-ins. They do not execute Godot, Metal, or a GPU. The native runner
launches each expected-error case in a fresh process and retains its logs.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SPEC = importlib.util.spec_from_file_location("metalfx_patch_checks", HERE / "test_engine_patch.py")
CHECKS = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(CHECKS)
PATCHES = [HERE / "patches" / n for n in (
    "0001-metalfx-allocation-fallback.patch", "0002-metalfx-history-reset.patch",
    "0003-metalfx-debug-faults.patch", "0004-metalfx-frame-inputs.patch",
    "0005-metal-triangle-query.patch")]
FROZEN = (
    "f04167e05f452bfc37e85e90d512373d92c3f6ec808cef8431a0705e197d716a",
    "d7570f1b3639616e4e565a920cc4b9caca844bf7d1c8b3ec7d14d6e596c4ecc5",
    "cdacbdf81c80e44b96b200f1890236774225d93d8b54299f8e7db47b9f2c21cd",
    "2cfc1c4b466dfba51ae940d4c0529d290bf5a4502cd562d52edc4c4712e1ce18",
)
PROBE = ROOT / "research/engine-upgrade/metalfx/triangle_query_probe.gd"

GUARD_STUB = r'''
#include <cstdint>
#include <map>
#include <vector>
using RID = int;
namespace RDD { enum { ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL, ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL }; }
struct Driver { std::map<int, bool> valid; bool acceleration_structure_build_is_valid(int id) const {
    auto i = valid.find(id); return i != valid.end() && i->second;
} };
template<class T> struct Owner {
    std::map<int,T> objects;
    T *get_or_null(RID id) { auto it=objects.find(id); return it == objects.end() ? nullptr : &it->second; }
};
class RenderingDevice {
public:
    enum { SUPPORTS_METAL_TRIANGLE_QUERY };
    struct UniformSet { std::vector<RID> acceleration_structures; };
    struct AccelerationStructure { int type=0; bool invalidated=true; int driver_id=0; std::vector<RID> acceleration_structure_dependencies; };
    struct ComputeList {
        struct SetState { uint32_t pipeline_expected_format=0, uniform_set_format=0; RID uniform_set=0; };
        struct State { SetState sets[4]; uint32_t set_count=0; } state;
    } compute_list;
    bool feature=false;
    bool has_feature(int) const { return feature; }
    Owner<UniformSet> uniform_set_owner;
    Owner<AccelerationStructure> acceleration_structure_owner;
    Driver *driver=nullptr;
    bool _compute_list_triangle_query_sets_valid();
};
@GUARD@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    RenderingDevice rd; Driver driver; rd.driver=&driver;
    rd.compute_list.state.set_count=1;
    auto &set=rd.compute_list.state.sets[0];
    set.pipeline_expected_format=7; set.uniform_set_format=7; set.uniform_set=1;
    CHECK(rd._compute_list_triangle_query_sets_valid()); // capability off
    rd.feature=true;
    CHECK(!rd._compute_list_triangle_query_sets_valid()); // missing set
    rd.uniform_set_owner.objects[1].acceleration_structures={2};
    set.uniform_set_format=8; CHECK(!rd._compute_list_triangle_query_sets_valid());
    set.uniform_set_format=7; CHECK(!rd._compute_list_triangle_query_sets_valid()); // missing TLAS
    auto &t=rd.acceleration_structure_owner.objects[2];
    t.type=RDD::ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL; t.driver_id=10; t.invalidated=false;
    driver.valid[10]=true; CHECK(!rd._compute_list_triangle_query_sets_valid());
    t.type=RDD::ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL; t.invalidated=true;
    CHECK(!rd._compute_list_triangle_query_sets_valid());
    t.invalidated=false; driver.valid[10]=false; CHECK(!rd._compute_list_triangle_query_sets_valid());
    driver.valid[10]=true; t.acceleration_structure_dependencies={3};
    CHECK(!rd._compute_list_triangle_query_sets_valid()); // missing BLAS
    auto &b=rd.acceleration_structure_owner.objects[3]; b.invalidated=true; b.driver_id=11;
    driver.valid[11]=true; CHECK(!rd._compute_list_triangle_query_sets_valid());
    b.invalidated=false; driver.valid[11]=false; CHECK(!rd._compute_list_triangle_query_sets_valid());
    driver.valid[11]=true; CHECK(rd._compute_list_triangle_query_sets_valid());
    return 0;
}
'''


GEOMETRY_STUB = r'''
#include <cstdint>
#include <vector>
using RID = int;
#define ERR_FAIL_COND_V_MSG(c,v,m) do { if (c) return false; } while (0)
enum { SUPPORTS_METAL_TRIANGLE_QUERY, ACCELERATION_STRUCTURE_GEOMETRY_OPAQUE_BIT=1,
       DATA_FORMAT_R32G32B32_SFLOAT=2 };
namespace RDD { enum { BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT=1,
                       BUFFER_USAGE_DYNAMIC_PERSISTENT_BIT=2 }; }
struct Flags { uint64_t value=0; bool is_empty() const { return value==0; }
    bool has_flag(int bit) const { return (value & uint64_t(bit)) != 0; }
    explicit operator uint64_t() const { return value; } };
struct Handle { bool valid=false; bool is_valid() const { return valid; } };
struct Geometry { Flags flags; Handle index_buffer; int64_t index_offset=0, index_count=0;
    int vertex_format=DATA_FORMAT_R32G32B32_SFLOAT; int64_t vertex_offset=0, vertex_count=6, vertex_stride=16; };
using AccelerationStructureGeometry = Geometry;
struct Buffer { Flags usage; uint64_t size=0; };
static bool has_feature(int) { return true; }
bool geometry_ok(const std::vector<Geometry> &p_geometries, Flags p_flags, Buffer &buffer) {
@ADMISSION@
    for (uint64_t i=0;i<p_geometries.size();++i) {
@FIELDS@
        Buffer *vertex_buffer=&buffer;
@BOUNDS@
    }
    return true;
}
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    Geometry g; g.flags.value=1; g.vertex_offset=4; Buffer buffer; buffer.usage.value=1; buffer.size=96;
    CHECK(geometry_ok({g},{0},buffer)); // last float3 ends exactly at buffer end
    buffer.size=95; CHECK(!geometry_ok({g},{0},buffer)); buffer.size=96;
    auto bad=g; bad.vertex_offset=5; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.vertex_stride=10; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.vertex_count=0; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.vertex_count=7; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.vertex_count=-3; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.vertex_offset=4294967296LL; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.index_buffer.valid=true; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.flags.value=0; CHECK(!geometry_ok({bad},{0},buffer));
    CHECK(!geometry_ok({g,g},{0},buffer)); CHECK(!geometry_ok({g},{1},buffer));
    buffer.usage.value=0; CHECK(!geometry_ok({g},{0},buffer));
    buffer.usage.value=3; CHECK(!geometry_ok({g},{0},buffer));
    return 0;
}
'''

PACK_STUB = r'''
#include <cstdint>
#include <cstring>
#include <cmath>
#include <cstddef>
#define ERR_FAIL_NULL(x) do { if (!(x)) return; } while (0)
#define ERR_FAIL_COND_MSG(x,m) do { if (x) return; } while (0)
namespace MTL {
struct Matrix { float values[4][3]{}; float *operator[](int i) { return values[i]; } };
struct AccelerationStructureUserIDInstanceDescriptor { Matrix transformationMatrix; uint32_t options=0, mask=0, intersectionFunctionTableOffset=0, accelerationStructureIndex=0, userID=0; };
}
struct MDAccelerationStructure { enum class Type { BLAS, TLAS }; Type type=Type::BLAS; };
@INSTANCE@
namespace RDD {
struct Transform { struct Basis { float rows[3][3]{}; } basis; float origin[3]{}; bool finite=true; bool is_finite() const { return finite; } };
struct Flags { bool empty=true; bool is_empty() const { return empty; } };
struct AccelerationStructureInstance { Transform transform; uint32_t id=0, mask=0, hit_sbt_offset=0; Flags flags; struct { uint64_t id=0; } blas; };
}
class RenderingDeviceDriverMetal { public:
    using AccelerationStructureInstance=RDD::AccelerationStructureInstance;
    void acceleration_structure_instance_write(uint8_t *, const AccelerationStructureInstance &);
};
@PACK@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    RenderingDeviceDriverMetal rd; MDAccelerationStructure blas; RDD::AccelerationStructureInstance input;
    input.blas.id=uint64_t(&blas); input.id=0x123456; input.mask=0xa5;
    for (int r=0;r<3;r++) { input.transform.origin[r]=float(10+r); for (int c=0;c<3;c++) input.transform.basis.rows[r][c]=float(3*r+c+1); }
    alignas(8) uint8_t bytes[128]; std::memset(bytes,0xcd,sizeof bytes);
    rd.acceleration_structure_instance_write(bytes,input);
    MDAccelerationStructureInstance result; std::memcpy(&result,bytes,sizeof result);
    CHECK(result.blas==&blas && result.native.userID==0x123456 && result.native.mask==0xa5);
    for (int c=0;c<3;c++) for (int r=0;r<3;r++) CHECK(result.native.transformationMatrix[c][r]==float(3*r+c+1));
    for (int r=0;r<3;r++) CHECK(result.native.transformationMatrix[3][r]==float(10+r));
    for (int mode=0;mode<5;mode++) {
        std::memset(bytes,0xcd,sizeof bytes); input.id=0x123456; input.flags.empty=true; input.transform.finite=true; input.hit_sbt_offset=0; blas.type=MDAccelerationStructure::Type::BLAS;
        if (mode==0) input.id=0x1000000;
        if (mode==1) input.flags.empty=false;
        if (mode==2) input.transform.finite=false;
        if (mode==3) input.hit_sbt_offset=1;
        if (mode==4) blas.type=MDAccelerationStructure::Type::TLAS;
        rd.acceleration_structure_instance_write(bytes,input);
        for (auto value : bytes) CHECK(value==0xcd);
    }
    return 0;
}
'''

class TriangleQueryPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if hashlib.sha256(CHECKS.ARCHIVE.read_bytes()).hexdigest() != CHECKS.ARCHIVE_SHA256:
            raise RuntimeError("Pinned source archive differs")
        if tuple(hashlib.sha256(p.read_bytes()).hexdigest() for p in PATCHES[:4]) != FROZEN:
            raise RuntimeError("Frozen prerequisite patches differ")
        cls.temp = tempfile.TemporaryDirectory(prefix="openrc-metal-query-")
        cls.base = Path(cls.temp.name)
        names = set()
        for patch in PATCHES:
            for name in re.findall(r"^(?:---|\+\+\+) ([ab]/[^\r\n]+)$", patch.read_text(encoding="utf-8"), re.M):
                names.add(name[2:])
        with zipfile.ZipFile(CHECKS.ARCHIVE) as archive:
            members = set(archive.namelist())
            for name in names:
                member = f"godot-{CHECKS.COMMIT}/{name}"
                if member in members:
                    target = cls.base / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(member))
        for patch in PATCHES:
            subprocess.run(["git", "-c", "core.autocrlf=false", "apply", "--check", str(patch)], cwd=cls.base, check=True, capture_output=True)
            subprocess.run(["git", "-c", "core.autocrlf=false", "apply", str(patch)], cwd=cls.base, check=True, capture_output=True)
        cls.rd = (cls.base / "servers/rendering/rendering_device.cpp").read_text(encoding="utf-8")
        cls.shared = (cls.base / "drivers/metal/metal_objects_shared.h").read_text(encoding="utf-8")
        cls.driver = (cls.base / "drivers/metal/rendering_device_driver_metal.cpp").read_text(encoding="utf-8")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def compile(self, source: str, name: str) -> subprocess.CompletedProcess[str]:
        compiler = shutil.which("g++") or shutil.which("clang++")
        if not compiler:
            self.fail("A C++17 compiler is required")
        cpp = self.base / (name + ".cpp")
        binary = self.base / (name + (".exe" if os.name == "nt" else ""))
        cpp.write_text(source, encoding="utf-8")
        built = subprocess.run([compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", str(cpp), "-o", str(binary)], capture_output=True, text=True)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        return subprocess.run([str(binary)], cwd=self.base, capture_output=True, text=True)

    def test_prerequisite_stack_and_mutation_rejection(self) -> None:
        subprocess.run(["git", "apply", "--reverse", "--check", str(PATCHES[-1])], cwd=self.base, check=True, capture_output=True)
        target = self.base / "thirdparty/spirv-cross/spirv_msl.cpp"
        original = target.read_bytes()
        try:
            altered = original.replace(b"case SPIRType::AccelerationStructure:\n\t\t\tADD_ARG_IDX_TO_BINDING_NUM_LOOKUP", b"case SPIRType::Unknown:\n\t\t\tADD_ARG_IDX_TO_BINDING_NUM_LOOKUP", 1)
            self.assertNotEqual(original, altered)
            target.write_bytes(altered)
            refused = subprocess.run(["git", "apply", "--reverse", "--check", str(PATCHES[-1])], cwd=self.base, capture_output=True)
            self.assertNotEqual(refused.returncode, 0)
        finally:
            target.write_bytes(original)

    def test_real_dispatch_guard_and_negative_mutation(self) -> None:
        guard = CHECKS.cxx_function(self.rd, "bool RenderingDevice::_compute_list_triangle_query_sets_valid(")
        src = GUARD_STUB.replace("@GUARD@", guard)
        run = self.compile(src, "guard_controls")
        self.assertEqual(run.returncode, 0, run.stderr)
        mutated = src.replace("tlas->invalidated ||", "false ||", 1)
        self.assertNotEqual(mutated, src)
        run = self.compile(mutated, "guard_mutated")
        self.assertNotEqual(run.returncode, 0, "Control failed to detect a stale TLAS")
        for signature in ("void RenderingDevice::compute_list_dispatch(", "void RenderingDevice::compute_list_dispatch_indirect("):
            fn = CHECKS.cxx_function(self.rd, signature)
            self.assertLess(fn.index("_compute_list_triangle_query_sets_valid"), fn.index("draw_graph.add_compute_list_dispatch"))

    def test_real_geometry_admission_and_exact_bounds(self) -> None:
        start = self.rd.index("RID RenderingDevice::blas_create(")
        admission_start = self.rd.index("\tconst bool triangle_query =", start)
        admission_end = self.rd.index("\n\tthread_local", admission_start)
        fields_start = self.rd.index("\t\tconst AccelerationStructureGeometry &rd_geometry", admission_end)
        fields_end = self.rd.index("\n\t\tRDD::AccelerationStructureGeometry &", fields_start)
        bounds_start = self.rd.index("\t\tif (triangle_query) {", fields_end)
        bounds_end = self.rd.index("\n\t\tERR_FAIL_COND_V_MSG(rd_geometry.vertex_format", bounds_start)
        source = (GEOMETRY_STUB.replace("@ADMISSION@", self.rd[admission_start:admission_end])
                  .replace("@FIELDS@", self.rd[fields_start:fields_end])
                  .replace("@BOUNDS@", self.rd[bounds_start:bounds_end]))
        run = self.compile(source, "geometry_controls")
        self.assertEqual(run.returncode, 0, run.stderr)
        mutated = source.replace("end > vertex_buffer->size", "end >= vertex_buffer->size", 1)
        self.assertNotEqual(mutated, source)
        self.assertNotEqual(self.compile(mutated, "geometry_mutated").returncode, 0,
                            "Control failed to detect rejection of an exact-fit buffer")

    def test_real_instance_packing_and_invalid_inputs(self) -> None:
        instance = "struct MDAccelerationStructureInstance " + CHECKS.cxx_block(self.shared, self.shared.index("struct MDAccelerationStructureInstance")) + ";"
        pack = CHECKS.cxx_function(self.driver, "void RenderingDeviceDriverMetal::acceleration_structure_instance_write(")
        run = self.compile(PACK_STUB.replace("@INSTANCE@", instance).replace("@PACK@", pack), "instance_controls")
        self.assertEqual(run.returncode, 0, run.stderr)

    def test_scope_and_binding_routes(self) -> None:
        metal3 = (self.base / "drivers/metal/rendering_device_driver_metal3.cpp").read_text(encoding="utf-8")
        commands = (self.base / "drivers/metal/metal3_objects.cpp").read_text(encoding="utf-8")
        spirv = (self.base / "thirdparty/spirv-cross/spirv_msl.cpp").read_text(encoding="utf-8")
        self.assertIn('get_environment("GODOT_METAL_TRIANGLE_QUERY") == "1"', metal3)
        self.assertIn("sync_mode = HazardTracking", metal3)
        self.assertIn("setAccelerationStructure(accel->accel.get()", commands)
        self.assertIn("accel->resident_blases", commands)
        self.assertIn("addCompletedHandler", commands)
        self.assertGreaterEqual(spirv.count("case SPIRType::AccelerationStructure:"), 2)
        for sig, create in (("RID RenderingDevice::blas_create(", "driver->blas_create"),
                            ("RID RenderingDevice::tlas_create(", "driver->tlas_create")):
            fn = CHECKS.cxx_function(self.rd, sig)
            self.assertLess(fn.index("!has_feature(SUPPORTS_METAL_TRIANGLE_QUERY)"), fn.index(create))
        for sig in ("RID RenderingDevice::hit_sbt_create(", "RID RenderingDevice::raytracing_pipeline_create("):
            fn = CHECKS.cxx_function(self.rd, sig)
            self.assertIn("!has_feature(SUPPORTS_RAYTRACING_PIPELINE)", fn)
            self.assertNotIn("SUPPORTS_METAL_TRIANGLE_QUERY", fn[:fn.index(";")])

EXPECTED = {
    "off": None,
    "off_blas": "The current rendering device has neither raytracing pipeline nor ray query support.",
    "off_tlas": "The current rendering device has neither raytracing pipeline nor ray query support.",
    "happy": None,
    "bad_bounds": "Metal triangle vertices exceed the vertex buffer.",
    "bad_stride": "Metal triangle queries require non-indexed opaque float3 triangles",
    "bad_offset": "Acceleration-structure geometry fields must fit uint32.",
    "bad_capacity": "TLAS capacity must fit uint32.",
    "bad_id": "Invalid Metal triangle-query instance",
    "bad_mask": "Invalid Metal triangle-query instance",
    "bad_transform": "Invalid Metal triangle-query instance",
    "bad_sbt": "Invalid Metal triangle-query instance",
    "bad_flags": "Invalid Metal triangle-query instance",
    "empty": "Metal triangle-query TLAS is nonempty and can be built only once.",
    "rebuild": "Metal triangle-query TLAS is nonempty and can be built only once.",
    "pipeline": "The current rendering device has no raytracing pipeline support.",
    "sbt": "The current rendering device has no raytracing pipeline support.",
    "ray_list": "The current rendering device has no raytracing pipeline support.",
    "stale_direct": "Metal triangle-query compute dispatch has an invalid or stale TLAS uniform set.",
    "stale_indirect": "Metal triangle-query compute dispatch has an invalid or stale TLAS uniform set.",
    "rebuild_stale": ["Metal triangle-query TLAS is nonempty and can be built only once.", "Metal triangle-query compute dispatch has an invalid or stale TLAS uniform set."],
}

def native_runner(binary: Path, output: Path) -> int:
    if sys.platform != "darwin":
        raise SystemExit("Native Metal fixture requires macOS")
    binary = binary.resolve(strict=True)
    output.mkdir(parents=True, exist_ok=False)
    records = []
    fixture = PROBE.read_bytes()
    with tempfile.TemporaryDirectory(prefix="openrc-triangle-project-") as temporary:
        project = Path(temporary)
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Metal Triangle Query"\n[rendering]\nrenderer/rendering_method="mobile"\n', encoding="utf-8")
        (project / "triangle_query_probe.gd").write_bytes(fixture)
        for mode in ("argument", "direct"):
            for case, expected in EXPECTED.items():
                if case.startswith("off") and mode == "direct":
                    continue
                env = os.environ.copy()
                for key in ("GODOT_METAL_TRIANGLE_QUERY", "GODOT_MTL_DISABLE_ARGUMENT_BUFFERS", "GODOT_MTL_SYNC_MODE"):
                    env.pop(key, None)
                if not case.startswith("off"):
                    env["GODOT_METAL_TRIANGLE_QUERY"] = "1"
                if mode == "direct":
                    env["GODOT_MTL_DISABLE_ARGUMENT_BUFFERS"] = "1"
                env.update(MTL_DEBUG_LAYER="1", MTL_SHADER_VALIDATION="1", MTL_SHADER_VALIDATION_REPORT_TO_STDERR="1", MTL_SHADER_VALIDATION_ABORT_ON_FAULT="1")
                command = [str(binary), "--path", str(project), "--rendering-method", "mobile", "--rendering-driver", "metal", "--verbose", "--script", "res://triangle_query_probe.gd", "--", f"--case={case}"]
                try:
                    proc = subprocess.run(command, env=env, capture_output=True, text=True, timeout=180)
                    log = proc.stdout + "\n" + proc.stderr
                    code = proc.returncode
                except subprocess.TimeoutExpired as exc:
                    log = str(exc.stdout or "") + "\n" + str(exc.stderr or "") + "\nTIMEOUT"
                    code = -1
                name = mode + "-" + case
                (output / (name + ".log")).write_text(log, encoding="utf-8")
                lines = [line for line in log.splitlines() if line.startswith("METAL_TRIANGLE_QUERY ")]
                try:
                    verdict = json.loads(lines[0].split(" ", 1)[1]) if len(lines) == 1 else {}
                except (ValueError, IndexError):
                    verdict = {}
                errors = [line for line in log.splitlines() if line.lstrip().startswith("ERROR:")]
                expected_list = expected if isinstance(expected, list) else ([expected] if expected else [])
                expected_errors = len(errors) == len(expected_list) and all(want in got for want, got in zip(expected_list, errors))
                invalid_gpu = re.search(r"(?i)(failed assertion|GPU fault|MTLCommandBufferError|shader validation error)", log) is not None
                binding_observed = case.startswith("off") or ("Metal triangle query binding mode: " + mode) in log
                ok = code == 0 and verdict.get("ok") is True and verdict.get("case") == case and expected_errors and not invalid_gpu and binding_observed
                records.append({"mode": mode, "binding_observed": binding_observed, "case": case, "returncode": code, "verdict": verdict, "errors": errors, "ok": ok, "command": command, "environment": {key: env.get(key) for key in ("GODOT_METAL_TRIANGLE_QUERY", "GODOT_MTL_DISABLE_ARGUMENT_BUFFERS", "MTL_DEBUG_LAYER", "MTL_SHADER_VALIDATION")}})
                print(f"{name}: {'PASS' if ok else 'FAIL'}", flush=True)
    manifest = {"binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(), "fixture_sha256": hashlib.sha256(fixture).hexdigest(), "patch_sha256": hashlib.sha256(PATCHES[-1].read_bytes()).hexdigest(), "cases": records, "ok": all(r["ok"] for r in records)}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0 if manifest["ok"] else 1

if __name__ == "__main__":
    if "--native" in sys.argv:
        parser = argparse.ArgumentParser(description="Run each query case in a fresh native Metal process")
        parser.add_argument("--native", type=Path, required=True, help="Source-bound patched Godot editor binary")
        parser.add_argument("--out", type=Path, required=True, help="New evidence directory")
        args = parser.parse_args()
        raise SystemExit(native_runner(args.native, args.out))
    unittest.main()
