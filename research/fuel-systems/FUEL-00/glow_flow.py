"""FUEL-00 audit: premix flow implied by the runtime 2T/4T per-cycle laws (no trapping in delivered flow).

Usage: python3 -I glow_flow.py <repo root>
Mirrors two_stroke.gd/four_stroke.gd delivered-premix arithmetic at k_feed = 1; not a runtime call.
"""
import json
import sys
R=sys.argv[1].rstrip("/")+"/app/data/glow/"
def interp(t,x):
    for i in range(len(t)-1):
        if t[i][0]<=x<=t[i+1][0]:
            a=(x-t[i][0])/(t[i+1][0]-t[i][0]); return t[i][1]+a*(t[i+1][1]-t[i][1])
    return t[-1][1]
def blend(p):
    f={k:v['value'] for k,v in p['fuel'].items()}
    mv=1-f['nitromethane_volume_fraction']-f['lubricant_volume_fraction']
    mm=mv*f['methanol_density_kg_m3']; nm=f['nitromethane_volume_fraction']*f['nitromethane_density_kg_m3']; om=f['lubricant_volume_fraction']*f['lubricant_density_kg_m3']
    rho=mm+nm+om; afr=(mm*f['methanol_stoich_air_fuel_ratio']+nm*f['nitromethane_stoich_air_fuel_ratio'])/(mm+nm)
    return rho,afr,om/rho
def flow(p,rpm,adm,mix=1.15,rho_air=1.225):
    rho,afr,oil=blend(p); par=p['parameters']; Vd=par['displacement_m3']['value']
    if p['family']=='glow_2t':
        eff=interp(par['delivery_ratio']['value'],rpm); fc=rpm/60
    else:
        eff=interp(par['volumetric_efficiency']['value'],rpm); fc=rpm/120
    kg_s=rho_air*Vd*adm*eff*mix/afr/(1-oil)*fc
    return kg_s, kg_s/rho*1e6*60  # ml/min
for name,wot_rpms,idle_adm in [('os_max_55ax_candidate',[9380,10330,16000],0.28),('os_max_61fx_candidate',[10976,12550,16000],0.28),('os_fs_64v_candidate',[7823,10000,11000],0.35)]:
    p=json.load(open(R+name+'.json'))
    rho,afr,oil=blend(p)
    print(name,'density=%.2f kg/m3 AFR=%.3f oil_mass_frac=%.4f'%(rho,afr,oil))
    for r in wot_rpms:
        kg,ml=flow(p,r,1.0); print('  WOT %5d rpm: %.3f g/s = %.1f ml/min -> 140 ml (0.12 kg) lasts %.1f min; 350 ml lasts %.1f min'%(r,kg*1e3,ml,140/ml,350/ml))
    for r in [2000,2800]:
        kg,ml=flow(p,r,idle_adm); print('  idle adm %.2f %4d rpm: %.3f g/s = %.1f ml/min'%(idle_adm,r,kg*1e3,ml))
# AIAA regressions for context
print('AIAA 2T fit 0.46x+28.6 mg/s at x=600/900 W:', [round((0.46*x+28.6)*60/1000,1) for x in (600,900)],'g/min')
print('AIAA 4T fit 0.34x+27.11 mg/s at x=400/600 W:', [round((0.34*x+27.11)*60/1000,1) for x in (400,600)],'g/min')
print('Saito FA-82B 35 cc/min @10000 rpm scaled by displacement to FS-64V 10.46/13.47:', round(35*10.46/13.47,1),'cc/min')
print('Endurance stand: 55AX 0.12kg/292.408s=%.3f g/s; FS64V 0.12/645.15=%.3f g/s'%(0.12/292.408*1e3,0.12/645.15*1e3))
