#!/usr/bin/env bash
# props library -> UV -> QA per asset -> measurements -> engine assembly + fit checks
set -u
export BLENDER_EXE=/home/claude/tools/blender
S=/home/claude/ext/blender-skills-src/skills
R="python3 $S/blender-core/scripts/run_in_blender.py"
P=/home/claude/props
O=$P/out
L=$O/props_library.blend
cd $P
python3 $BLENDER_EXE -b --factory-startup --python build_props.py -- --save $L --json $O/props_build.json 2>&1 | grep -E "built|Error|Traceback" | grep -v EGL
OBJS=$(python3 $BLENDER_EXE $L -b --python-expr "import bpy; print('LIST:'+' '.join(o.name for o in bpy.data.objects if o.type=='MESH'))" 2>/dev/null | grep LIST: | cut -c6-)
$R --blend $L $S/blender-retopology-uv/scripts/uv_pack.py -- --objects $OBJS --method smart --angle 66 --save $L | cut -c1-60
python3 $BLENDER_EXE $L -b --python-expr "
import bpy, json
g = {}
for o in bpy.data.objects:
    if o.type != 'MESH': continue
    r = o
    while r.parent: r = r.parent
    g.setdefault(r.name, []).append(o.name)
json.dump(g, open('$O/qa_groups.json','w'))" > /dev/null 2>&1
python3 - <<PY
import json, subprocess
g = json.load(open("$O/qa_groups.json"))
res = {}
for root, objs in sorted(g.items()):
    out = subprocess.run(["python3", "$S/blender-core/scripts/run_in_blender.py", "--blend", "$L",
                          "$S/blender-asset-qa/scripts/qa_check.py", "--", "--objects", *objs, "--profile", "render",
                          "--eps", "0.0002", "--tol", "0.001"], capture_output=True, text=True).stdout
    try:
        d = json.loads(out[out.index("{"):])
    except Exception:
        d = {"pass": None, "raw": out[-400:]}
    res[root] = {"pass": d.get("pass"), "errors": d.get("errors"), "warnings": (d.get("warnings") or [])[:6],
                 "tris": sum(v.get("tris", 0) for v in (d.get("objects") or {}).values())}
    print(root, res[root]["pass"], res[root]["errors"], res[root]["tris"], flush=True)
json.dump(res, open("$O/qa_props.json", "w"), indent=1)
PY
python3 $BLENDER_EXE -b $L --python tools/check_props.py -- --out $O/check_props.json 2>&1 | grep -E "^(APC|MA|TT|DB)|Error|Traceback" | cut -c1-200
mkdir -p $O/assembly
python3 $BLENDER_EXE -b /home/claude/engine/v4/engine_se_bancada.blend --python tools/mount_props.py -- --lib $L --save $O/assembly/motor_bancada_helices.blend --show A --check $O/assembly/mount_check.json 2>&1 | grep -E "^(A|B|C|D) |Error|Traceback" | cut -c1-300
echo PIPELINE_DONE
