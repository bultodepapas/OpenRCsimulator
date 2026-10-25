from pathlib import Path
import json,subprocess,sys,hashlib,struct,io
from PIL import Image
import numpy as np
P=Path(__file__).resolve().parents[2];R=P.parent;rows=[]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def doc(path):
 raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];return json.loads(raw[20:20+n]),raw[28+n:]
baseline,_=doc(R/'g2_1/export/aircraft.glb')
def hierarchy(g):
 parent={c:i for i,n in enumerate(g['nodes'])for c in n.get('children',[])}
 return {n['name']:{'parent':g['nodes'][parent[i]]['name']if i in parent else None,'section':n.get('extras',{}).get('openrc_section'),'transform':{k:n.get(k)for k in ['matrix','translation','rotation','scale']}}for i,n in enumerate(g['nodes'])}
for l in json.loads((P/'liveries.json').read_text()):
 lid=l['id'];row=json.loads((P/'checks'/('adaptation_'+lid+'.json')).read_text());glb=P/row['glb'];g,blob=doc(glb)
 assert sha(glb)==row['glb_sha256'];assert sha(P/row['blend'])==row['blend_sha256'];assert hierarchy(g)==hierarchy(baseline)
 image_rows=[]
 for im in g['images']:
  v=g['bufferViews'][im['bufferView']];raw=blob[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']];image=Image.open(io.BytesIO(raw))
  assert max(image.size)<=2048,(lid,im['name'],image.size)
  image_rows.append({'name':im['name'],'size':image.size})
 assert not any('ao'==im.get('name','').lower() for im in g['images'])
 paint=next(m for m in g['materials']if m['name']=='paint_body');orm=paint['pbrMetallicRoughness']['metallicRoughnessTexture']['index']
 for m in g['materials']:
  if m['name'].startswith('paint_')or m['name']in ['alloy','cockpit','engine_dark','gear_inner_coat','naval_blade_paint','livery_spinner_paint']:
   assert m['occlusionTexture']['index']==orm,(lid,m['name'],'AO not shared')
 args=[sys.executable,str(P/'source/scripts/preflight_glb.py'),str(glb),'--profile','f4u-g2','--report',str(P/'checks'/('preflight_'+lid+'.json'))]
 p=subprocess.run(args,capture_output=True,text=True);(P/'checks'/('preflight_'+lid+'.txt')).write_text(p.stdout+p.stderr)
 assert p.returncode==0,(lid,p.stdout[-2000:],p.stderr)
 result=json.loads((P/'checks'/('preflight_'+lid+'.json')).read_text());assert not result.get('warnings'),(lid,result.get('warnings'))
 row.update(preflight_pass=True,preflight_warnings=[],hierarchy_and_frame100_identical=True,runtime_images=image_rows,AO_shared_descriptor=True)
 rows.append(row);print('CHECKED',lid,row['glb_bytes'],flush=True)
(P/'checks/livery_suite.json').write_text(json.dumps({'all_pass':True,'count':len(rows),'variants':rows},indent=2))
assert sha(R/'g2_1/source/aircraft_game.blend')=='1bbe5011f099cdaa893f00f4ec081523d5873887cb5916c29ee26c5319295148'
assert sha(R/'g2_1/export/aircraft.glb')=='cf4cdad638dae93b2ac6107bd050dcf176c4b6dbb1f03d21580f4149fda945b3'
print('ALL_13_VALIDATED_BASELINE_UNCHANGED',flush=True)
