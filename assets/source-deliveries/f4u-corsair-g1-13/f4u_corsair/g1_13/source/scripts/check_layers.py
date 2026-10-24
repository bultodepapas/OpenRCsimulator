"""Validate editable ORA composites and linear material channels. Python + Pillow + numpy."""
from pathlib import Path
import json,zipfile,xml.etree.ElementTree as ET,sys
try:import numpy as np;from PIL import Image
except ImportError:
 sys.path.insert(0,str(Path(__file__).resolve().parents[5]/'work/plot_R58_deps'))
 import numpy as np
 from PIL import Image
P=Path(__file__).resolve().parents[2];checks=[]
for lid in ['midnight','three_tone','scarlet']:
 D=P/'textures/liveries'/lid
 with zipfile.ZipFile(D/'source.ora') as z:
  layers=ET.fromstring(z.read('stack.xml')).find('stack').findall('layer')
  out=Image.new('RGBA',(2048,2048))
  for layer in reversed(layers):
   with z.open(layer.attrib['src']) as f:out=Image.alpha_composite(out,Image.open(f).convert('RGBA'))
  original=np.asarray(Image.open(D/'basecolor.png').convert('RGB')).astype(int)
  error=int(np.abs(original-np.asarray(out.convert('RGB')).astype(int)).max())
 orm=np.asarray(Image.open(D/'orm.png'));rough=np.asarray(Image.open(D/'roughness.png'))
 checks.append({'id':lid,'ora_recomposition_max_channel_error':error,'layers':len(layers),'insignia_independently_removable':any('National insignia' in l.attrib['name'] for l in layers),'metallic_zero':bool((orm[:,:,2]==0).all()),'AO_unoccluded':bool((orm[:,:,0]==255).all()),'roughness_matches':bool((orm[:,:,1]==rough).all()),'roughness_range':[int(rough.min()),int(rough.max())]})
passed=all(c['ora_recomposition_max_channel_error']<=2 and c['metallic_zero'] and c['roughness_matches'] and c['insignia_independently_removable'] for c in checks)
(P/'previews/layer-verification.json').write_text(json.dumps({'passed':passed,'checks':checks},indent=2))
print('LAYER_VERIFICATION',passed,checks)
if not passed:raise SystemExit(1)
