import json,collections,hashlib,pathlib
root=pathlib.Path('/workspace/scratch/bf9c4bc414d0/audit_work/OpenRCsimulator')
data=json.loads((root/'app/data/economy/catalog.json').read_text())
catalog=(root/'app/app_state/aircraft_catalog.gd').read_text()
import re
routes={m.group(1):m.group(2) for m in re.finditer(r'id = "([^"\n]+)"[\s\S]*?data = "res://([^"\n]+)"',catalog)}
offers={o['id']:o for o in data['offers']}
for d in data['aircraft']:
 cs=d['components']; mapped=sum(c['unit_minor'] is not None for c in cs); u=[c for c in cs if c['unit_minor'] is None]; known=sum(c['quantity']*c['unit_minor'] for c in cs if c['unit_minor'] is not None)
 lo=sum(c['quantity']*(c['low_unit_minor'] if c['low_unit_minor'] is not None else (c['unit_minor'] or 0)) for c in cs); hi=sum(c['quantity']*(c['high_unit_minor'] if c['high_unit_minor'] is not None else (c['unit_minor'] or 0)) for c in cs)
 sig=d['physical_signature']; inv=set(sig['inventory']); bound={x for c in cs for x in c['physical_inventory_ids']}; ex={x for e in d['exclusions'] if e['scope']=='inventory' for x in e['physical_inventory_ids']}; contacts=set(sig['contacts']); contactmap=set(d['contact_components']); hash_now=hashlib.sha256((root/'app'/routes[d['aircraft_id']]).read_bytes()).hexdigest() if d['aircraft_id'] in routes else None
 print('\n##',d['aircraft_id']);print('complete',d['complete'],'rows',len(cs),'priced',mapped,'unpriced',len(u),'prices bases',dict(collections.Counter(c['price_basis'] for c in cs if c['unit_minor'] is not None)))
 print('priced subtotal nominal/low/high',*[f'${x/100:,.2f}' for x in (known,lo,hi)], '(not whole-build total if incomplete)')
 print('inventory signature',len(inv),'bound',len(bound),'excluded',len(ex),'uncovered',sorted(inv-bound-ex),'contacts signed/mapped/unmapped',len(contacts),len(contactmap),sorted(contacts-contactmap))
 print('propeller',d['propeller_component_id'],'prop_inspections',d['propeller_inspection_ids'],'source hash match',hash_now==d['source_sha256'])
 print('unpriced', ', '.join(c['id']+' x'+str(c['quantity']) for c in u) or '-')
 print('priced rows:')
 for c in cs:
  if c['unit_minor'] is None: continue
  x=offers.get(c['offer_id'],{}); print(' ',c['id'],'x'+str(c['quantity']),f'${c["unit_minor"]/100:.2f}',f'[{(c["low_unit_minor"] if c["low_unit_minor"] is not None else c["unit_minor"])/100:.2f}–{(c["high_unit_minor"] if c["high_unit_minor"] is not None else c["unit_minor"])/100:.2f}]',c['price_basis'],c['offer_id'],x.get('availability',''))
