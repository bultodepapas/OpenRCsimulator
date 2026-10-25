"""Check the editable default livery and exported scalar channels."""
from pathlib import Path
import json,zipfile,xml.etree.ElementTree as ET
import numpy as np
from PIL import Image
P=Path(__file__).resolve().parents[2];D=P/'textures/liveries/midnight'
with zipfile.ZipFile(D/'source.ora') as z:
 layers=ET.fromstring(z.read('stack.xml')).find('stack').findall('layer')
 out=Image.new('RGBA',(2048,2048))
 for layer in reversed(layers):
  with z.open(layer.attrib['src']) as f:out=Image.alpha_composite(out,Image.open(f).convert('RGBA'))
 original=np.asarray(Image.open(D/'basecolor.png').convert('RGB')).astype(int)
 error=int(np.abs(original-np.asarray(out.convert('RGB')).astype(int)).max())
orm=np.asarray(Image.open(D/'orm.png'));rough=np.asarray(Image.open(D/'roughness.png'))
c={'id':'midnight','ora_recomposition_max_channel_error':error,'layers':len(layers),'insignia_independently_removable':any('National insignia' in l.attrib['name'] for l in layers),'metallic_zero':bool((orm[:,:,2]==0).all()),'roughness_matches':bool((orm[:,:,1]==rough).all())}
r={'passed':error<=2 and c['metallic_zero'] and c['roughness_matches'] and c['insignia_independently_removable'],'checks':[c]}
(P/'checks/layers.json').write_text(json.dumps(r,indent=2));print(r)
if not r['passed']:raise SystemExit(1)
