#!/usr/bin/env python3
"""Uniform side-profile diagnostic; reads original attachment without editing it."""
import hashlib,json
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
PHOTO=ROOT/'references/avanti-s/user-profile/avanti-s-perfil-recortado-usuario.png'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    im=Image.open(PHOTO)
    assert im.size==(1818,865) and im.mode=='RGBA'
    assert sha(PHOTO)=='4ab4d1ba032756c4c0877a00db53162c38cf4ecdfa79d8dedf83d74dbb8977e3'
    geometry=ROOT/'research/avanti-s/av02/geometry.json'
    landmarks={'nose':[0,0,-1.05], 'rear_body_proxy':[0,0,1.17], 'fin_top':[0,.51,.96], 'canopy_top':[0,.251,-.28]}
    picks={'nose':[1754,534], 'rear_body_proxy':[117,540], 'fin_top':[126,139], 'canopy_top':[1129,315]}
    # No anisotropic scale, camera rotation, silhouette warp or background replacement.
    scale=(picks['nose'][0]-picks['rear_body_proxy'][0])/2.22
    tx=picks['nose'][0]+scale*landmarks['nose'][2]
    ty=(picks['nose'][1]+picks['rear_body_proxy'][1])/2
    data=dict(schema='openrc-profile-picks-v1',model_geometry_sha256=sha(geometry),landmarks_m=landmarks,picked_px=picks,
              photo=str(PHOTO.relative_to(ROOT)),photo_sha256=sha(PHOTO),size_px=list(im.size),
              method='Orthographic side-view diagnostic: uniform display scale from approximate nose/rear-body horizontal extents; align mean height. No camera roll or image deformation.',
              limitations=['Exact photographed variant and original photographer unknown', 'Photo retains perspective; not an orthographic plan', 'rear_body_proxy is an inferred visible rear-body landmark, NOT a visible exhaust centre', 'Nozzle, wings, gear and fences do not share a common profile plane; no metric accuracy claim'])
    (HERE/'picks.json').write_text(json.dumps(data,indent=2)+'\n')
    errors=[]
    for key,p in landmarks.items():
        projected=[tx-scale*p[2],ty-scale*p[1]]
        errors.append(dict(key=key,role='fit' if key in ('nose','rear_body_proxy') else 'check',picked_px=picks[key],projected_px=projected,error_px=float(np.linalg.norm(np.array(projected)-picks[key]))))
    view=dict(id='profile',title='Perfil del usuario · alineación por extremos aproximados',photo=str(PHOTO.relative_to(ROOT)),photo_sha256=sha(PHOTO),size_px=list(im.size),projection='orthographic',orthographic_size_m=im.height/scale,camera_position_m=[4,(ty-im.height/2)/scale,(tx-im.width/2)/scale],camera_basis_columns=[[0,0,-1],[0,1,0],[1,0,0]],landmarks=errors,display_scale_px_per_model_m=scale)
    fit=dict(schema='openrc-profile-diagnostic-camera-v1',model_geometry_sha256=sha(geometry),picks_sha256=sha(HERE/'picks.json'),method=data['method'],limits=data['limitations'],views=[view])
    (HERE/'camera-fit.json').write_text(json.dumps(fit,indent=2)+'\n')
    print(json.dumps({'scale_px_per_model_m':scale,'landmarks':errors},indent=2))

if __name__=='__main__':main()
