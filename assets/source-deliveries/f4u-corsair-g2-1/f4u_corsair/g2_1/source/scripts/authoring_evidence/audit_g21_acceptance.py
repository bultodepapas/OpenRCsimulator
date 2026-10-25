"""Independent, read-only F4U g2.1 acceptance audit. Run with Blender 5.2 background."""
import bpy, argparse, base64, hashlib, json, math, re, struct, sys
from pathlib import Path
from mathutils import Vector

WHEELS=("gear_wheel_left","gear_wheel_right","gear_wheel_tail")
ALLOWED={"propeller_rotor","canopy_glass",*WHEELS}
AO_MATS=("cockpit","alloy","engine_dark","gear_inner_coat","naval_blade_paint")
TOL=1e-5

def arguments():
    argv=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    ap=argparse.ArgumentParser()
    for n in ("candidate","g2-baseline","g1-baseline","glb","package","out-json","out-md"):
        ap.add_argument("--"+n,required=True)
    return ap.parse_args(argv)

def mesh_sig(m):
    h=hashlib.sha256(); h.update(b"OpenRC-wheel-mesh-v1\0")
    h.update(struct.pack("<III",len(m.vertices),len(m.edges),len(m.polygons)))
    for v in m.vertices: h.update(struct.pack("<3f",*v.co))
    for e in m.edges: h.update(struct.pack("<2I",*e.vertices))
    for p in m.polygons:
        h.update(struct.pack("<I",len(p.vertices)))
        h.update(struct.pack("<"+"I"*len(p.vertices),*p.vertices))
        h.update(struct.pack("<I?",p.material_index,p.use_smooth))
    h.update(struct.pack("<I",len(m.uv_layers)))
    for layer in m.uv_layers:
        b=layer.name.encode("utf8"); h.update(struct.pack("<I",len(b))); h.update(b)
        h.update(struct.pack("<I",len(layer.data)))
        for d in layer.data: h.update(struct.pack("<2f",*d.uv))
    return h.hexdigest()

def flat(m): return tuple(float(m[r][c]) for r in range(4) for c in range(4))
def delta(a,b):
    if a is None or b is None or len(a)!=len(b): return float("inf")
    return max(abs(x-y) for x,y in zip(a,b))
def digest(data): return hashlib.sha256(data).hexdigest()

def raw_image(im):
    try:
        if im.packed_file: return bytes(im.packed_file.data)
    except Exception: pass
    try:
        p=Path(bpy.path.abspath(im.filepath))
        if p.is_file(): return p.read_bytes()
    except Exception: pass
    return None

def snap(path, detailed=False, package=None):
    bpy.ops.wm.open_mainfile(filepath=str(path),load_ui=False)
    scene=bpy.context.scene
    col=bpy.data.collections.get("EXPORT_aircraft")
    objs=list(col.objects) if col else []
    by={o.name:o for o in objs}
    out={"path":str(path),"scene_frame":int(scene.frame_current),"names":sorted(by),
         "nodes":{},"meshes":{},"keyframes":{},"series":{},"wheels":{}}
    for name,o in by.items():
        out["nodes"][name]={"type":o.type,"parent":o.parent.name if o.parent else None,
            "parent_type":o.parent_type,"tag":o.get("openrc_section"),
            "parent_inverse":flat(o.matrix_parent_inverse)}
        if o.type=="MESH": out["meshes"][name]=mesh_sig(o.data)
    for f in (0,100):
        scene.frame_set(f); bpy.context.view_layer.update(); dg=bpy.context.evaluated_depsgraph_get()
        out["keyframes"][str(f)]={n:{"basis":flat(o.evaluated_get(dg).matrix_basis),
            "local":flat(o.evaluated_get(dg).matrix_local),"world":flat(o.evaluated_get(dg).matrix_world)} for n,o in by.items()}
    for f in range(101):
        scene.frame_set(f); bpy.context.view_layer.update(); dg=bpy.context.evaluated_depsgraph_get()
        out["series"][str(f)]={n:flat(o.evaluated_get(dg).matrix_world) for n,o in by.items()}
    for n in WHEELS:
        o=by.get(n)
        if not o or o.type!="MESH": out["wheels"][n]={"missing":True}; continue
        dims=[max(v.co[i] for v in o.data.vertices)-min(v.co[i] for v in o.data.vertices) for i in range(3)]
        row={"signature":mesh_sig(o.data),"triangles":sum(len(p.vertices)-2 for p in o.data.polygons),
             "bbox_size_m":dims,"parent":o.parent.name if o.parent else None,"frames":{}}
        for f in (0,100):
            scene.frame_set(f); bpy.context.view_layer.update(); ev=o.evaluated_get(bpy.context.evaluated_depsgraph_get())
            pts=[ev.matrix_world@v.co for v in o.data.vertices]
            row["frames"][str(f)]={"matrix":flat(ev.matrix_world),"ground_z_m":min(v.z for v in pts),
                "bbox_min_m":[min(v[i] for v in pts) for i in range(3)],
                "bbox_max_m":[max(v[i] for v in pts) for i in range(3)]}
        out["wheels"][n]=row
    if not detailed: return out,None
    info={"blender":bpy.app.version_string,"materials":{},"images":{},"rotor":{}}
    for mname in ("paint_body",)+AO_MATS:
        mat=bpy.data.materials.get(mname)
        if not mat: info["materials"][mname]={"missing":True}; continue
        nodes=[]
        if mat.node_tree:
            for n in mat.node_tree.nodes:
                r={"type":n.type,"name":n.name}
                if n.type=="TEX_IMAGE" and n.image:
                    data=raw_image(n.image)
                    r["image"]={"name":n.image.name,"filepath":n.image.filepath,
                        "bytes":len(data) if data is not None else None,
                        "sha256":digest(data) if data is not None else None}
                if n.type=="GROUP" and n.node_tree and "Occlusion" in n.inputs:
                    s=n.inputs["Occlusion"]
                    r["occlusion_links"]=[{"from_type":l.from_node.type,"from_node":l.from_node.name,
                        "from_socket":l.from_socket.name} for l in s.links]
                nodes.append(r)
        info["materials"][mname]={"nodes":nodes}
    for im in bpy.data.images:
        data=raw_image(im)
        info["images"][im.name]={"filepath":im.filepath,"bytes":len(data) if data is not None else None,
                                 "sha256":digest(data) if data is not None else None,
                                 "_raw":data}
    rotor=by.get("propeller_rotor")
    if rotor and rotor.type=="MESH":
        m=rotor.data; names=[x.name if x else None for x in m.materials]
        facecounts={}
        for p in m.polygons:
            mn=names[p.material_index] if p.material_index<len(names) else None
            facecounts[mn]=facecounts.get(mn,0)+1
        paintidx=next((i for i,x in enumerate(names) if x=="naval_blade_paint"),None)
        rows=[]
        if paintidx is not None and "NavalBladeUV" in m.uv_layers:
            uv=m.uv_layers["NavalBladeUV"]
            for k,a in enumerate([math.pi/2+i*2*math.pi/3 for i in range(3)]):
                cs,sn=math.cos(a),math.sin(a); count=tris=0; spans=[]; us=[]; angs=[]
                for p in m.polygons:
                    if p.material_index!=paintidx: continue
                    coords=[rotor.matrix_world@m.vertices[v].co for v in p.vertices]
                    c=sum(coords,Vector())/len(coords)
                    theta=math.atan2(c.z,c.x)
                    if math.hypot(c.x,c.z)<.08 or abs(math.atan2(math.sin(theta-a),math.cos(theta-a)))>math.radians(55): continue
                    count+=1; tris+=len(p.vertices)-2; angs.append(theta)
                    for li in p.loop_indices:
                        co=rotor.matrix_world@m.vertices[m.loops[li].vertex_index].co
                        spans.append(co.x*cs+co.z*sn); us.append(float(uv.data[li].uv.x))
                errs=[abs(u-s*.9/.42) for u,s in zip(us,spans)]
                rows.append({"axis_deg_expected":90+120*k,"paint_faces":count,"paint_triangles":tris,
                    "mean_axis_deg":math.degrees(math.atan2(sum(math.sin(x) for x in angs),sum(math.cos(x) for x in angs)))%360 if angs else None,
                    "uv_loops":len(us),"u_span_max_abs_error":max(errs) if errs else None,
                    "u_slope_through_origin":sum(u*s for u,s in zip(us,spans))/sum(s*s for s in spans) if spans and sum(s*s for s in spans)>0 else None})
        uvnodes=[]
        mat=bpy.data.materials.get("naval_blade_paint")
        if mat and mat.node_tree:
            uvnodes=[n.uv_map for n in mat.node_tree.nodes if n.type=="UVMAP"]
        info["rotor"]={"triangles":sum(len(p.vertices)-2 for p in m.polygons),"materials":names,
            "uv_layers":[u.name for u in m.uv_layers],"face_counts":facecounts,"paint_faces":facecounts.get("naval_blade_paint",0),
            "blade_uv_nodes":uvnodes,"blade_sectors":rows}
    paint_mat=bpy.data.materials.get("paint_body")
    paint_orm_names=[]
    if paint_mat and paint_mat.node_tree:
        paint_orm_names=[n.image.name for n in paint_mat.node_tree.nodes
                         if n.type=="TEX_IMAGE" and n.image and
                         re.search(r"(^|[_\-.])orm($|[_\-.])",n.image.name.lower())]
    info["paint_orm_images"]=paint_orm_names
    info["ao_graph"]={}
    for mname in AO_MATS:
        mat=bpy.data.materials.get(mname); found=[]
        if mat and mat.node_tree:
            for group in mat.node_tree.nodes:
                if group.type!="GROUP" or not group.node_tree or "Occlusion" not in group.inputs: continue
                for link in group.inputs["Occlusion"].links:
                    sep=link.from_node
                    row={"group":group.node_tree.name,"source_type":sep.type,"source_socket":link.from_socket.name,
                         "image":None,"image_is_paint_orm":False}
                    color_links=list(sep.inputs["Color"].links) if sep.type=="SEPARATE_COLOR" and "Color" in sep.inputs else []
                    if color_links:
                        tex=color_links[0].from_node
                        row["image"]=tex.image.name if tex.type=="TEX_IMAGE" and tex.image else None
                        row["image_is_paint_orm"]=row["image"] in paint_orm_names
                    found.append(row)
        info["ao_graph"][mname]=found
    info["native_ao_images"]=[n for n in bpy.data.images.keys() if re.search(r"(^|[/\\_.-])ao([/\\_.-]|$)|g2_r59_ao",n,re.I)]
    info["ao_sidecars"]=[]
    if package:
        for p in Path(package).rglob("*"):
            if p.is_file() and re.search(r"(^|[/\\_.-])ao([/\\_.-]|$)|g2_r59_ao",p.name,re.I):
                info["ao_sidecars"].append({"path":str(p),"bytes":p.stat().st_size})
    return out,info

def parse_glb(path):
    raw=Path(path).read_bytes()
    if len(raw)<20 or raw[:4]!=b"glTF": raise ValueError("not GLB")
    ver,total=struct.unpack_from("<II",raw,4)
    if ver!=2 or total!=len(raw): raise ValueError("bad GLB header")
    off=12; doc=None; blob=b""
    while off+8<=len(raw):
        ln,kind=struct.unpack_from("<II",raw,off); off+=8; chunk=raw[off:off+ln]; off+=ln
        if kind==0x4E4F534A: doc=json.loads(chunk.decode("utf8").rstrip(" \0"))
        elif kind==0x004E4942: blob=chunk
    if doc is None: raise ValueError("missing GLB JSON chunk")
    ib=[]
    for im in doc.get("images",[]):
        data=None
        if "bufferView" in im:
            v=doc.get("bufferViews",[])[int(im["bufferView"])]
            start=int(v.get("byteOffset",0)); data=blob[start:start+int(v["byteLength"])]
        elif im.get("uri","").startswith("data:"): data=base64.b64decode(im["uri"].split(",",1)[1])
        ib.append(data)
    return doc,raw,ib

def glb_mats(doc):
    rows={}
    for i,m in enumerate(doc.get("materials",[])):
        p=m.get("pbrMetallicRoughness",{}); bt=p.get("baseColorTexture") or {}
        mt=p.get("metallicRoughnessTexture") or {}; oc=m.get("occlusionTexture") or {}
        rows[m.get("name",f"material_{i}")]={"index":i,"base_texture":bt.get("index"),
            "base_texcoord":bt.get("texCoord",0),"orm_texture":mt.get("index"),
            "occlusion_texture":oc.get("index"),"occlusion_texcoord":oc.get("texCoord",0)}
    return rows

def main():
    a=arguments()
    p={k:Path(getattr(a,k.replace("-","_"))) for k in ("candidate","g2-baseline","g1-baseline","glb","package","out-json","out-md")}
    checks=[]
    def check(name,ok,detail=None): checks.append({"name":name,"ok":bool(ok),"detail":detail})
    cand,native=snap(p["candidate"],True,p["package"])
    g2,_=snap(p["g2-baseline"]); g1,_=snap(p["g1-baseline"])
    check("native g2.1 opens at frame 0",cand["scene_frame"]==0,{"saved_frame":cand["scene_frame"]})
    check("candidate has 82 EXPORT_aircraft nodes",len(cand["names"])==82,{"count":len(cand["names"])})
    check("all 82 node names preserved",cand["names"]==g2["names"],
          {"candidate_only":sorted(set(cand["names"])-set(g2["names"])),"g2_only":sorted(set(g2["names"])-set(cand["names"]))})
    hier=[]; keys=("type","parent","parent_type","tag","parent_inverse")
    for n in sorted(set(cand["nodes"])&set(g2["nodes"])):
        for k in keys:
            if k=="parent_inverse":
                d=delta(cand["nodes"][n][k],g2["nodes"][n][k])
                if d>TOL: hier.append({"node":n,"field":k,"delta":d})
            elif cand["nodes"][n][k]!=g2["nodes"][n][k]:
                hier.append({"node":n,"field":k,"candidate":cand["nodes"][n][k],"g2_0":g2["nodes"][n][k]})
    check("parents/tags/types preserved",not hier,hier[:30])
    rest=[]
    for f in ("0","100"):
        for n in sorted(set(cand["keyframes"][f])&set(g2["keyframes"][f])):
            for k in ("basis","local","world"):
                d=delta(cand["keyframes"][f][n][k],g2["keyframes"][f][n][k])
                if d>TOL: rest.append({"frame":int(f),"node":n,"matrix":k,"delta":d})
    check("frame 0 and 100 matrices preserved within 1e-5",not rest,rest[:30])
    pose=[]; maxpose=0.0
    for f in range(101):
        for n in sorted(set(cand["series"][str(f)])&set(g2["series"][str(f)])):
            d=delta(cand["series"][str(f)][n],g2["series"][str(f)][n]); maxpose=max(maxpose,d)
            if d>TOL and len(pose)<30: pose.append({"frame":f,"node":n,"delta":d})
    check("all 101 world-matrix poses preserved within 1e-5",not pose,{"max_delta":maxpose,"violations":pose})
    changed=[]
    if set(cand["meshes"])!=set(g2["meshes"]):
        changed.append({"candidate_only":sorted(set(cand["meshes"])-set(g2["meshes"])),"g2_only":sorted(set(g2["meshes"])-set(cand["meshes"]))})
    for n in sorted(set(cand["meshes"])&set(g2["meshes"])):
        if n not in ALLOWED and cand["meshes"][n]!=g2["meshes"][n]: changed.append({"node":n,"issue":"geometry/topology/material-index/UV signature differs"})
    check("all unaffected mesh geometry and UV signatures unchanged",not changed,changed[:30])
    wheel_sig={n:{"candidate":cand["wheels"].get(n,{}).get("signature"),"g1_24":g1["wheels"].get(n,{}).get("signature")} for n in WHEELS}
    check("all three wheel mesh and UV signatures exact g1.24",
          all(wheel_sig[n]["candidate"]==wheel_sig[n]["g1_24"] for n in WHEELS),wheel_sig)
    dim_errors=[]
    for n in WHEELS:
        cd=cand["wheels"].get(n,{}).get("bbox_size_m",[])
        gd=g1["wheels"].get(n,{}).get("bbox_size_m",[])
        if len(cd)!=3 or len(gd)!=3 or max(abs(x-y) for x,y in zip(sorted(cd),sorted(gd)))>1e-5:
            dim_errors.append({"node":n,"candidate_local_bbox_size_m":cd,"g1_24_local_bbox_size_m":gd})
    check("wheel radii and axle widths match g1.24 within 0.01 mm",not dim_errors,dim_errors)
    contact={}; werrs=[]
    for n in WHEELS:
        c,b,o=(x["wheels"].get(n,{}) for x in (cand,g2,g1)); row={}
        for f in ("0","100"):
            cm=c.get("frames",{}).get(f,{}).get("matrix")
            d=delta(cm,b.get("frames",{}).get(f,{}).get("matrix"))
            d1=delta(cm,o.get("frames",{}).get(f,{}).get("matrix"))
            if d>TOL: werrs.append({"node":n,"frame":int(f),"vs":"g2.0","matrix_delta":d})
            if d1>TOL: werrs.append({"node":n,"frame":int(f),"vs":"g1.24","matrix_delta":d1})
        cz=c.get("frames",{}).get("0",{}).get("ground_z_m"); bz=b.get("frames",{}).get("0",{}).get("ground_z_m"); oz=o.get("frames",{}).get("0",{}).get("ground_z_m")
        row={"triangles":c.get("triangles"),"local_bbox_size_m":c.get("bbox_size_m"),
             "candidate_ground_z_m":cz,"g2_0_ground_z_m":bz,"g1_24_ground_z_m":oz,
             "delta_vs_g2_0_mm":abs(cz-bz)*1000 if cz is not None and bz is not None else None,
             "delta_vs_g1_24_mm":abs(cz-oz)*1000 if cz is not None and oz is not None else None}
        for label,key in (("g2.0","delta_vs_g2_0_mm"),("g1.24","delta_vs_g1_24_mm")):
            if row[key] is None or row[key]>.01: werrs.append({"node":n,"vs":label,"delta_mm":row[key]})
        contact[n]=row
    check("wheel matrices and ground contacts preserved within 0.01 mm",not werrs,{"contacts":contact,"violations":werrs[:30]})
    rotor=native.get("rotor",{}); blade_mats=[(x or "").lower() for x in rotor.get("materials",[])]
    sectors=rotor.get("blade_sectors",[])
    check("three blades share naval_blade_paint and blade_tip is removed",
          "naval_blade_paint" in blade_mats and "blade_tip" not in blade_mats and len(sectors)==3 and all(s["paint_faces"]>0 for s in sectors),
          {"materials":rotor.get("materials"),"sectors":sectors,"paint_faces":rotor.get("paint_faces")})
    axis_errors=[{"expected_deg":s.get("axis_deg_expected"),"measured_mean_deg":s.get("mean_axis_deg"),
                  "error_deg":abs((s.get("mean_axis_deg",0)-s.get("axis_deg_expected",0)+180)%360-180)}
                 for s in sectors if s.get("mean_axis_deg") is None or
                 abs((s.get("mean_axis_deg",0)-s.get("axis_deg_expected",0)+180)%360-180)>5]
    check("blade paint regions align with world axes 90 plus 120 degrees per blade",
          not axis_errors,{"tolerance_deg":5,"sectors":sectors,"violations":axis_errors})
    check("blade paint explicitly uses NavalBladeUV second UV layer",
          len(rotor.get("uv_layers",[]))>=2 and rotor.get("uv_layers",[None,None])[1]=="NavalBladeUV" and "NavalBladeUV" in rotor.get("blade_uv_nodes",[]),
          {"uv_layers":rotor.get("uv_layers"),"uv_nodes":rotor.get("blade_uv_nodes")})
    uerrors=[s for s in sectors if s.get("u_span_max_abs_error") is None or s["u_span_max_abs_error"]>1e-5]
    check("axial U mapping is linear from root to 0.9 at 0.42 m",not uerrors,
          {"expected_U_equals_world_axial_span_times_0.9_over_0.42":True,"sectors":sectors,"violations":uerrors})
    blade_mat=bpy.data.materials.get("naval_blade_paint")
    blade_nodes=[n.image.name for n in blade_mat.node_tree.nodes if n.type=="TEX_IMAGE" and n.image] if blade_mat and blade_mat.node_tree else []
    blade_raw=next((native["images"].get(n,{}).get("_raw") for n in blade_nodes if native["images"].get(n,{}).get("_raw")),None)
    bpy.ops.wm.open_mainfile(filepath=str(p["g1-baseline"]),load_ui=False)
    g1im=bpy.data.images.get("naval_propeller_basecolor"); g1raw=raw_image(g1im) if g1im else None
    sides=[]
    for imgpath in p["package"].rglob("*.png"):
        if imgpath.name.lower() in {"propeller_basecolor.png","naval_propeller_basecolor.png"}:
            d=imgpath.read_bytes(); sides.append({"path":str(imgpath),"bytes":len(d),"sha256":digest(d),"matches_g1":d==g1raw})
    check("native blade image and shipped PNG bytes equal g1.24",
          bool(g1raw and blade_raw==g1raw and sides and all(r["matches_g1"] for r in sides)),
          {"g1_bytes":len(g1raw) if g1raw else None,"g1_sha256":digest(g1raw) if g1raw else None,
           "native_image_names":blade_nodes,"native_matches_g1":bool(g1raw and blade_raw==g1raw),"sidecars":sides})
    gltf,glbraw,glbimgs=parse_glb(p["glb"]); gm=glb_mats(gltf)
    glbmatnames=[(x.get("name") or "").lower() for x in gltf.get("materials",[])]
    check("GLB has no blade_tip material","blade_tip" not in glbmatnames,{"materials":glbmatnames})
    nm={x.get("name",""):(i,x) for i,x in enumerate(gltf.get("nodes",[]))}
    entry=nm.get("propeller_rotor"); paintprims=[]
    if entry and entry[1].get("mesh") is not None:
        for prim in gltf.get("meshes",[])[entry[1]["mesh"]].get("primitives",[]):
            mi=prim.get("material")
            mn=gltf.get("materials",[])[mi].get("name") if mi is not None and mi<len(gltf.get("materials",[])) else None
            if mn=="naval_blade_paint": paintprims.append(prim)
    bg=gm.get("naval_blade_paint",{})
    check("GLB blade base color uses explicit TEXCOORD_1",
          bg.get("base_texture") is not None and bg.get("base_texcoord")==1 and paintprims and all("TEXCOORD_1" in r.get("attributes",{}) for r in paintprims),
          {"blade_material":bg,"paint_primitives":len(paintprims),"attributes":[sorted(r.get("attributes",{})) for r in paintprims]})
    orm=gm.get("paint_body",{}).get("orm_texture")
    aerrs=[{"material":n,"occlusion":gm.get(n,{}).get("occlusion_texture"),"paint_orm":orm} for n in AO_MATS if gm.get(n,{}).get("occlusion_texture")!=orm]
    textures=gltf.get("textures",[]); images=gltf.get("images",[])
    orm_source=textures[orm].get("source") if orm is not None and orm<len(textures) else None
    texture_sources={n:(textures[gm[n]["occlusion_texture"]].get("source")
        if gm.get(n,{}).get("occlusion_texture") is not None and gm[n]["occlusion_texture"]<len(textures) else None)
        for n in AO_MATS}
    check("native AO inputs use the paint ORM red channel for all five materials",
          bool(native.get("paint_orm_images")) and all(len(native["ao_graph"].get(n,[]))>0 and
              all(x.get("source_type")=="SEPARATE_COLOR" and x.get("source_socket")=="Red" and
                  x.get("image_is_paint_orm") for x in native["ao_graph"][n]) for n in AO_MATS),
          {"paint_orm_images":native.get("paint_orm_images"),"graphs":native.get("ao_graph")})
    check("GLB occlusion uses the same paint ORM texture index for all five required materials",orm is not None and not aerrs,
          {"paint_body_orm_texture":orm,"paint_orm_image_source":orm_source,
           "occlusion_image_sources":texture_sources,"glb_images":images,
           "materials":{n:gm.get(n) for n in AO_MATS},"violations":aerrs})
    glbao=[x.get("name","") for x in gltf.get("images",[]) if re.search(r"(^|[/\\_.-])ao([/\\_.-]|$)|g2_r59_ao",x.get("name",""),re.I)]
    check("no standalone AO image in native file or GLB",not native.get("native_ao_images") and not glbao,
          {"native":native.get("native_ao_images"),"glb":glbao,"ao_sidecars":native.get("ao_sidecars")})
    check("no stale standalone AO sidecar remains in the package",not native.get("ao_sidecars"),
          native.get("ao_sidecars"))
    check("GLB material count does not exceed 16",len(gltf.get("materials",[]))<=16,{"materials":len(gltf.get("materials",[]))})
    first=next((x for x in checks if not x["ok"]),None)
    report={"audit":"Independent F4U g2.1 acceptance audit","read_only":True,"blender":native.get("blender"),
        "inputs":{k:str(v.resolve()) for k,v in p.items()},"checks_passed":sum(x["ok"] for x in checks),
        "checks_total":len(checks),"ok":all(x["ok"] for x in checks),"first_issue":first,
        "input_sha256":{k:digest(v.read_bytes()) for k,v in p.items() if k in {"candidate","g2-baseline","g1-baseline","glb"}},
        "wheel_contacts":contact,"rotor":rotor,"glb_materials":gm,
        "glb_images":[{"name":x.get("name"),"mimeType":x.get("mimeType"),
            "bytes":len(glbimgs[i]) if i<len(glbimgs) and glbimgs[i] is not None else None,
            "sha256":digest(glbimgs[i]) if i<len(glbimgs) and glbimgs[i] is not None else None}
            for i,x in enumerate(gltf.get("images",[]))],
        "glb_textures":[{"index":i,"source":x.get("source"),"sampler":x.get("sampler"),
            "image_name":gltf.get("images",[])[x["source"]].get("name")
            if x.get("source") is not None and x["source"]<len(gltf.get("images",[])) else None}
            for i,x in enumerate(gltf.get("textures",[]))],"checks":checks}
    outj=p["out-json"]; outm=p["out-md"]; outj.parent.mkdir(parents=True,exist_ok=True); outm.parent.mkdir(parents=True,exist_ok=True)
    outj.write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n",encoding="utf8")
    lines=["# Independent g2.1 acceptance audit","",
        "**Verdict:** "+("PASS" if report["ok"] else "FAIL")+f" — {report['checks_passed']}/{report['checks_total']} checks.","",
        "Read-only comparison of g2.1 against g2.0 and g1.24.","","## Checks",""]
    for x in checks:
        lines.append(f"- {'PASS' if x['ok'] else 'FAIL'} — {x['name']}")
        if not x["ok"]: lines.append("  - "+json.dumps(x.get("detail"),ensure_ascii=False)[:1800])
    lines.extend(["","## Wheel contact deltas",""])
    for n,r in contact.items(): lines.append(f"- {n}: {r['delta_vs_g2_0_mm']} mm vs g2.0; {r['delta_vs_g1_24_mm']} mm vs g1.24.")
    lines.extend(["","## First issue","", "None." if first is None else f"- {first['name']}: "+json.dumps(first.get("detail"),ensure_ascii=False)[:2500],""])
    outm.write_text("\n".join(lines),encoding="utf8")
    print("G21_ACCEPTANCE_AUDIT",json.dumps({"ok":report["ok"],"checks_passed":report["checks_passed"],
        "checks_total":report["checks_total"],"first_issue":first,"report_json":str(outj),
        "report_md":str(outm),"wheel_contacts":contact,"rotor_triangles":rotor.get("triangles"),
        "glb_materials":len(gltf.get("materials",[]))},ensure_ascii=False),flush=True)
    return 0 if report["ok"] else 1

if __name__=="__main__": sys.exit(main())
