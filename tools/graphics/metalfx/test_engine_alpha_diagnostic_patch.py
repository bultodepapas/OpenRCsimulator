"""Portable actual-source controls for the optional bounded alpha-list diagnostic."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location("alpha_conditional19", HERE / "test_engine_conditional_reset_patch.py")
PREVIOUS = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = PREVIOUS
spec.loader.exec_module(PREVIOUS)
ENGINE, CHECK = PREVIOUS.ENGINE, PREVIOUS.CHECK
PATCH = HERE / "patches/0020-metalfx-alpha-diagnostic.patch"
PATCHES = PREVIOUS.PATCHES + (PATCH,)
HASHES = PREVIOUS.HASHES + (PREVIOUS.PATCH_HASH,)
PATCH_HASH = "64288c65bfedd5391b0032e7ac4feddbb6bfa5a4063ca38b9a648bdff30ec09c"

PAGE = r'''
#include <servers/rendering/storage/metalfx_alpha_diagnostic.h>
#include <cstdint>
#include <limits>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
struct Entry { uint32_t id=0; };
int main(){
    MetalFXAlphaSnapshot<Entry> page;
    page.begin(0,0); CHECK(page.offset==0 && page.count==0 && !page.truncated());
    CHECK(!page.append({1}));
    page.begin(7,3); CHECK(page.offset==0);
    for(uint32_t i=0;i<3;++i)CHECK(page.append({i+1}));
    CHECK(page.count==3 && !page.truncated() && !page.append({4}));
    page.begin(0,17); CHECK(page.offset==0 && page.count==0);
    for(uint32_t i=0;i<8;++i)CHECK(page.append({i}));
    CHECK(page.count==8 && page.truncated() && !page.append({9}));
    page.begin(1,17); CHECK(page.offset==8);
    for(uint32_t i=0;i<8;++i)CHECK(page.append({i+8}));
    CHECK(page.truncated());
    page.begin(2,17); CHECK(page.offset==16 && page.append({16}) && !page.append({17}));
    CHECK(page.count==1 && page.truncated() && page.entries[0].id==16);
    MetalFXAlphaSnapshot<Entry> repeated;
    repeated.begin(42,17); CHECK(repeated.offset==0);
    repeated.begin(42,17); CHECK(repeated.offset==8);
    repeated.begin(42,17); CHECK(repeated.offset==16);
    repeated.begin(42,17); CHECK(repeated.offset==0);
    page.begin(UINT64_MAX,UINT32_MAX);
    CHECK(uint64_t(page.offset)<uint64_t(page.total));
    for(uint32_t i=0;i<8 && uint64_t(page.offset)+i<page.total;++i)CHECK(page.append({i}));
    CHECK(uint64_t(page.offset)+page.count<=page.total && page.truncated());
    return 0;
}
'''

COMMON = r'''
#include <servers/rendering/storage/metalfx_alpha_diagnostic.h>
#include <cstdint>
#include <climits>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
struct RID {
    uint64_t id=0;
    bool is_null()const{return id==0;} bool is_valid()const{return id!=0;}
    uint32_t get_local_index()const{return uint32_t(id);}
    uint64_t get_id()const{return id;}
    bool operator!=(RID r)const{return id!=r.id;}
};
struct String {
    std::string text;
    size_t length()const{return text.size();}
    String substr(size_t a,size_t n)const{return {text.substr(a,n)};}
};
struct AABB { int marker=0; };
@ENTRY@;
@DIAGNOSTIC@;
'''

CAPTURE = COMMON + r'''
struct MaterialData { RID self; @MATERIAL_GETTER@ };
struct ShaderData { String path; };
namespace RSE { enum { INSTANCE_MESH=1,INSTANCE_MULTIMESH=2,INSTANCE_PARTICLES=3 }; }
struct GeometryInstanceForwardClustered {
    struct Data { RID base; int base_type=0; } *data=nullptr;
    uint32_t instance_count=0; AABB transformed_aabb;
};
struct GeometryInstanceSurfaceDataCache {
    enum { FLAG_PASS_ALPHA=4 };
    struct Sort { uint32_t geometry_id=0,shader_id=0,material_id_hi=0,material_id_lo=0; } sort;
    uint32_t surface_index=0,flags=0; void *surface=nullptr;
    MaterialData *material=nullptr; ShaderData *shader=nullptr; GeometryInstanceForwardClustered *owner=nullptr;
};
struct AlphaList {
    std::vector<GeometryInstanceSurfaceDataCache*> v;
    bool is_empty()const{return v.empty();} uint32_t size()const{return uint32_t(v.size());}
    GeometryInstanceSurfaceDataCache *operator[](uint32_t i)const{return v[i];}
};
struct RenderList { AlphaList elements; };
struct RenderSceneBuffersRD {
    bool enabled=true; std::unique_ptr<MetalFXAlphaDiagnostic> snapshot;
    MetalFXAlphaDiagnostic *begin_metalfx_alpha_diagnostic(uint64_t frame,uint32_t count){
        if(!enabled || !count)return nullptr;
        if(!snapshot)snapshot=std::make_unique<MetalFXAlphaDiagnostic>();
        snapshot->page.begin(frame,count);return snapshot.get();
    }
};
template<class T> struct Ref { T *p; T *operator->()const{return p;} };
namespace RendererRD {
struct MeshStorage {
    static MeshStorage instance;
    std::unordered_map<uint64_t,RID> multi;
    std::unordered_map<uint64_t,std::vector<void*>> surfaces;
    static MeshStorage *get_singleton(){return &instance;}
    RID multimesh_get_mesh(RID r){auto i=multi.find(r.id);return i==multi.end()?RID{}:i->second;}
    int mesh_get_surface_count(RID r){auto i=surfaces.find(r.id);return i==surfaces.end()?0:int(i->second.size());}
    void *mesh_get_surface(RID r,uint32_t n){return surfaces.at(r.id)[n];}
};
struct ParticlesStorage {
    static ParticlesStorage instance; int pass_reads=0;
    std::unordered_map<uint64_t,std::vector<RID>> passes;
    static ParticlesStorage *get_singleton(){return &instance;}
    int particles_get_draw_passes(RID r){return int(passes[r.id].size());}
    RID particles_get_draw_pass_mesh(RID r,int n){++pass_reads;return passes[r.id][n];}
};
MeshStorage MeshStorage::instance; ParticlesStorage ParticlesStorage::instance;
}
namespace RSG { struct Rasterizer {uint64_t frame=0;uint64_t get_frame_number(){return frame;}} instance; Rasterizer *rasterizer=&instance; }
struct RenderForwardClustered {
    enum { RENDER_LIST_ALPHA=0 }; RenderList render_list[1];
    void _capture_metalfx_alpha_diagnostic(Ref<RenderSceneBuffersRD>);
};
@CAPTURE@
static GeometryInstanceSurfaceDataCache surface(GeometryInstanceForwardClustered *owner,void *geometry,RID mesh,MaterialData *material,ShaderData *shader){
    GeometryInstanceSurfaceDataCache s; s.owner=owner;s.surface=geometry;s.material=material;s.shader=shader;
    s.flags=GeometryInstanceSurfaceDataCache::FLAG_PASS_ALPHA;s.sort.geometry_id=mesh.get_local_index();
    if(material){s.sort.material_id_hi=(material->self.get_local_index()>>24);s.sort.material_id_lo=material->self.get_local_index()&0xffffff;}
    s.sort.shader_id=37;return s;
}
int main(){
    auto &meshes=RendererRD::MeshStorage::instance; auto &particles=RendererRD::ParticlesStorage::instance;
    const RID mesh0{0x100000001ULL},mesh1{0x200000002ULL},mesh2{0x300000003ULL},ambiguous{0x400000003ULL};
    const RID multi{0x500000005ULL},particle{0x600000006ULL},many{0x700000007ULL},ambig_base{0x800000008ULL};
    int a=1,b=2,c=3;meshes.surfaces[mesh0.id]={&a};meshes.surfaces[mesh1.id]={&b};
    meshes.surfaces[mesh2.id]={&c};meshes.surfaces[ambiguous.id]={&c};meshes.multi[multi.id]=mesh1;
    particles.passes[particle.id]={mesh0,mesh2};particles.passes[many.id]=std::vector<RID>(33,mesh2);
    particles.passes[ambig_base.id]={mesh2,ambiguous};
    MaterialData material{{0x900000009ULL}};ShaderData shader{{std::string(300,'s')}};
    GeometryInstanceForwardClustered::Data d0{mesh0,RSE::INSTANCE_MESH},d1{multi,RSE::INSTANCE_MULTIMESH},
        d2{particle,RSE::INSTANCE_PARTICLES},d3{many,RSE::INSTANCE_PARTICLES},d4{ambig_base,RSE::INSTANCE_PARTICLES};
    GeometryInstanceForwardClustered o0{&d0,1,{11}},o1{&d1,6,{22}},o2{&d2,9,{33}},o3{&d3,33,{44}},o4{&d4,2,{55}};
    auto s0=surface(&o0,&a,mesh0,&material,&shader), s1=surface(&o1,&b,mesh1,&material,&shader),
         s2=surface(&o2,&c,mesh2,&material,&shader), s3=surface(&o3,&c,mesh2,&material,&shader),
         s4=surface(&o4,&c,mesh2,&material,&shader), bad=surface(&o0,&b,mesh0,&material,&shader);
    bad.flags=0;bad.sort.material_id_lo=10; // forced alpha with a mismatched material cache
    RenderForwardClustered renderer;renderer.render_list[0].elements.v={&s0,&s1,&s2,&s3,&s4,&bad,nullptr,&s0,&s1};
    RenderSceneBuffersRD buffers;RSG::instance.frame=0;renderer._capture_metalfx_alpha_diagnostic({&buffers});
    CHECK(buffers.snapshot && buffers.snapshot->page.total==9 && buffers.snapshot->page.offset==0 && buffers.snapshot->page.count==8);
    auto &p=buffers.snapshot->page;
    CHECK(p.entries[0].base.id==mesh0.id && p.entries[0].mesh.id==mesh0.id && p.entries[0].material.id==material.self.id);
    CHECK(p.entries[0].shader_available && p.entries[0].shader_local_index==37 && p.entries[0].shader_path.length()==256);
    CHECK(p.entries[1].base.id==multi.id && p.entries[1].mesh.id==mesh1.id && p.entries[1].instance_count==6);
    CHECK(p.entries[2].mesh.id==mesh2.id && !p.entries[2].mesh_lookup_truncated);
    CHECK(p.entries[3].mesh.is_null() && p.entries[3].mesh_lookup_truncated);
    CHECK(p.entries[4].mesh.is_null() && !p.entries[4].mesh_lookup_truncated);
    CHECK(p.entries[5].mesh.is_null() && p.entries[5].material.is_null() && !p.entries[5].material_from_alpha_pass);
    CHECK(p.entries[6].base.is_null() && !p.entries[6].shader_available);
    CHECK(particles.pass_reads==4); // 2 exact candidates + 2 ambiguous; no scan of 33-pass list.
    RSG::instance.frame=1;renderer._capture_metalfx_alpha_diagnostic({&buffers});
    CHECK(p.offset==8 && p.count==1 && p.truncated() && p.entries[0].mesh.id==mesh1.id);
    buffers.enabled=false;RSG::instance.frame=2;renderer._capture_metalfx_alpha_diagnostic({&buffers});
    CHECK(p.frame==1 && p.offset==8); // disabled snapshots never change.
    return 0;
}
'''

SCOPE = COMMON + r'''
struct RenderSceneBuffersRD {
    bool mfx_alpha_diagnostic_enabled=false;
    RID mfx_alpha_scope_viewport;
    uint64_t mfx_alpha_scope_viewport_generation=0,mfx_alpha_scope_producer_generation=0;
    std::unique_ptr<MetalFXAlphaDiagnostic> mfx_alpha_diagnostic;
    void set_metalfx_alpha_diagnostic_scope(RID,uint64_t,uint64_t);
    MetalFXAlphaDiagnostic *begin_metalfx_alpha_diagnostic(uint64_t,uint32_t);
};
@SCOPE@
@BEGIN@
int main(){
    RenderSceneBuffersRD b;
    b.set_metalfx_alpha_diagnostic_scope({123},5,6);
    CHECK(!b.mfx_alpha_diagnostic && b.mfx_alpha_scope_viewport.is_null());
    CHECK(b.begin_metalfx_alpha_diagnostic(10,3)==nullptr && !b.mfx_alpha_diagnostic);
    b.mfx_alpha_diagnostic_enabled=true;
    CHECK(b.begin_metalfx_alpha_diagnostic(10,3)==nullptr); // no viewport scope
    b.set_metalfx_alpha_diagnostic_scope({123},5,6);
    auto *old=b.begin_metalfx_alpha_diagnostic(11,3);CHECK(old && old->viewport.id==123);
    CHECK(old->viewport_generation==5 && old->producer_generation==6 && old->page.frame==11);
    b.set_metalfx_alpha_diagnostic_scope({456},7,8);
    CHECK(old->viewport.id==123 && old->viewport_generation==5 && old->producer_generation==6);
    CHECK(b.begin_metalfx_alpha_diagnostic(12,0)==nullptr && old->page.frame==11);
    auto *next=b.begin_metalfx_alpha_diagnostic(13,9);
    CHECK(next==old && next->viewport.id==456 && next->viewport_generation==7 && next->producer_generation==8);
    CHECK(next->page.frame==13 && next->page.total==9 && next->page.offset==0);
    next=b.begin_metalfx_alpha_diagnostic(13,9);
    CHECK(next==old && next->page.frame==13 && next->page.offset==8);
    return 0;
}
'''


class AlphaDiagnosticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if ENGINE.sha256(CHECK.ARCHIVE) != CHECK.ARCHIVE_SHA256:
            raise RuntimeError("Pinned Godot archive differs")
        if tuple(ENGINE.sha256(p) for p in PATCHES[:-1]) != HASHES:
            raise RuntimeError("Frozen 1–19 prerequisites differ")
        if ENGINE.sha256(PATCH) != PATCH_HASH:
            raise RuntimeError("0020 candidate differs")
        parent = (ROOT / "tmp/metalfx-alpha-diagnostic-port").resolve()
        if not parent.is_relative_to(ROOT.resolve()):
            raise RuntimeError("Control directory escaped workspace")
        parent.mkdir(parents=True, exist_ok=True)
        cls.tmp = tempfile.TemporaryDirectory(prefix="controls-", dir=parent)
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.base = Path(cls.tmp.name)
        with zipfile.ZipFile(CHECK.ARCHIVE) as archive:
            members = set(archive.namelist())
            for path in ENGINE.patch_paths(PATCHES):
                member = f"{ENGINE.SOURCE_PREFIX}/{path}"
                if member in members:
                    target = cls.base / path
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(member))
        ENGINE.git(cls.base, "init", "--quiet")
        for patch in PATCHES[:-1]:
            ENGINE.git(cls.base, "apply", "--check", "--whitespace=error", str(patch.resolve()))
            ENGINE.git(cls.base, "apply", "--whitespace=error", str(patch.resolve()))
        cls.original_forward = (cls.base / "servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp").read_text(encoding="utf-8")
        ENGINE.git(cls.base, "apply", "--check", "--whitespace=error", str(PATCH.resolve()))
        ENGINE.git(cls.base, "apply", "--whitespace=error", str(PATCH.resolve()))
        cls.forward = (cls.base / "servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp").read_text(encoding="utf-8")
        cls.buffers_h = (cls.base / "servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.h").read_text(encoding="utf-8")
        cls.buffers_cpp = (cls.base / "servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp").read_text(encoding="utf-8")
        cls.material = (cls.base / "servers/rendering/renderer_rd/storage_rd/material_storage.h").read_text(encoding="utf-8")

    def compile_run(self, code, name, include=None):
        compiler = os.environ.get("CXX") or shutil.which("g++") or shutil.which("clang++")
        self.assertTrue(compiler, "A C++17 compiler is required")
        source = self.base / (name + ".cpp")
        executable = self.base / (name + (".exe" if os.name == "nt" else ""))
        source.write_text(code, encoding="utf-8")
        command = [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror"]
        if include:
            command += ["-I", str(include)]
        command += ["-I", str(self.base), str(source), "-o", str(executable)]
        built = subprocess.run(command, capture_output=True, text=True, timeout=90)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        return subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)

    def common(self, code):
        return code.replace("@ENTRY@", CHECK.cxx_function(self.buffers_h, "struct MetalFXAlphaDiagnosticEntry")) \
            .replace("@DIAGNOSTIC@", CHECK.cxx_function(self.buffers_h, "struct MetalFXAlphaDiagnostic "))

    def test_actual_bounded_pages_and_mutation(self):
        self.assertEqual(self.compile_run(PAGE, "pages").returncode, 0)
        header = self.base / "servers/rendering/storage/metalfx_alpha_diagnostic.h"
        original = header.read_text(encoding="utf-8")
        changed = original.replace("++next_page >= pages", "next_page >= pages")
        self.assertNotEqual(changed, original)
        overlay = self.base / "mutated_page/servers/rendering/storage"
        overlay.mkdir(parents=True)
        (overlay / header.name).write_text(changed, encoding="utf-8")
        self.assertNotEqual(self.compile_run(PAGE, "pages_mutated", include=overlay.parents[2]).returncode, 0)

    def test_actual_capture_identities_and_mutation(self):
        control = self.common(CAPTURE).replace("@MATERIAL_GETTER@", CHECK.cxx_function(self.material, "RID get_diagnostic_rid() const")) \
            .replace("@CAPTURE@", CHECK.cxx_function(self.forward, "void RenderForwardClustered::_capture_metalfx_alpha_diagnostic("))
        self.assertEqual(self.compile_run(control, "capture").returncode, 0)
        changed = control.replace("meshes->mesh_get_surface(mesh, entry.surface) == surface->surface", "meshes->mesh_get_surface(mesh, entry.surface) != surface->surface")
        self.assertNotEqual(changed, control)
        self.assertNotEqual(self.compile_run(changed, "capture_mutated").returncode, 0)

    def test_actual_opt_in_scope_retention_and_mutation(self):
        control = self.common(SCOPE).replace("@SCOPE@", CHECK.cxx_function(self.buffers_cpp, "void RenderSceneBuffersRD::set_metalfx_alpha_diagnostic_scope(")) \
            .replace("@BEGIN@", CHECK.cxx_function(self.buffers_cpp, "MetalFXAlphaDiagnostic *RenderSceneBuffersRD::begin_metalfx_alpha_diagnostic("))
        self.assertEqual(self.compile_run(control, "scope").returncode, 0)
        changed = control.replace("mfx_alpha_diagnostic->producer_generation = mfx_alpha_scope_producer_generation;", "mfx_alpha_diagnostic->producer_generation = 0;")
        self.assertNotEqual(changed, control)
        self.assertNotEqual(self.compile_run(changed, "scope_mutated").returncode, 0)

    def test_original_gate_and_off_paths_remain_conservative(self):
        name = "static const char *metalfx_frame_scene_rejection("
        self.assertEqual(CHECK.cxx_function(self.original_forward, name), CHECK.cxx_function(self.forward, name))
        effect = CHECK.cxx_function(self.forward, "void RenderForwardClustered::_process_metalfx_frame(")
        self.assertLess(effect.index("if (!p_buffers->is_metalfx_frame_requested())"), effect.index("_capture_metalfx_alpha_diagnostic(p_buffers)"))
        self.assertLess(effect.index("p_buffers->reject_metalfx_frame(scene_rejection)"), effect.index("_capture_metalfx_alpha_diagnostic(p_buffers)"))
        self.assertIn("if (p_buffers->is_metalfx_alpha_diagnostic_enabled())", effect)
        self.assertNotIn("mfx_alpha_diagnostic", CHECK.cxx_function(self.buffers_cpp, "void RenderSceneBuffersRD::clear_metalfx_frame()"))
        viewport = (self.base / "servers/rendering/renderer_viewport.cpp").read_text(encoding="utf-8")
        draw = CHECK.cxx_function(viewport, "void RendererViewport::_draw_viewport(")
        self.assertIn("if (p_viewport->metal_fx_frame_requested && p_viewport->render_buffers.is_valid())", draw)
        self.assertLess(draw.index("render_buffers_create()"), draw.index("set_metalfx_alpha_diagnostic_scope("))
        self.assertIn('get_environment("OPENRC_METALFX_ALPHA_DIAGNOSTICS") == "1"', self.buffers_cpp)
        self.assertIn('"historical_alpha_render_list_not_pixel_contribution"', self.buffers_cpp)
        self.assertIn('"resources_may_match_multiple_scene_nodes"', self.buffers_cpp)
        self.assertIn('entry["shader_rid_available"] = false;', self.buffers_cpp)


if __name__ == "__main__":
    unittest.main()
