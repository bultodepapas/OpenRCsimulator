from pathlib import Path
import json,hashlib,shutil
r=Path.cwd();w=r/'tmp/perf-pass3-20261019';c=w/'candidate';c.mkdir(exist_ok=True)
files=['physics/lake_surface.gd','physics/ground_terrain.gd','physics/hull_contact.gd','physics/ground_wheels.gd','physics/ground_contact.gd','sim/flight_session.gd']
helper='''## Contact-only query for validated definitions. Outside the bank, callers receive only covered=false;
## they must not use this route for distances or finite-difference diagnostics outside coverage.
## Keep a full stencil margin so boundary tolerance and near-bank samples use the original sampler.
static func sample_covered_terrain_validated(lake: Dictionary, north: float, east: float) -> Dictionary:
\tif not is_finite(north) or not is_finite(east):
\t\treturn _invalid_sample()
\tif _outside_expanded_polygon_aabb(lake.bank_ne_m, north, east, SAMPLE_EPSILON_M):
\t\treturn {covered = false}
\treturn sample_terrain_validated(lake, north, east)


'''
for f in files:
 s=(w/'base/app'/f).read_text()
 if f=='physics/lake_surface.gd':
  i=s.index('## Returns bounded ground state only inside the bank polygon.');s=s[:i]+helper+s[i:]
 if f=='physics/ground_terrain.gd':s=s.replace('LakeSurface.sample_terrain_validated(lake, north, east)','LakeSurface.sample_covered_terrain_validated(lake, north, east)')
 if f=='physics/hull_contact.gd':s=s.replace('LakeSurface.sample_terrain_validated(lake, point_ned[0], point_ned[1])','LakeSurface.sample_covered_terrain_validated(lake, point_ned[0], point_ned[1])',1)
 # Store the production-intended bytes separately from benchmark-only dependency rewrites.
 p=w/'intended'/f;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
 for dependency in files:
  s=s.replace('res://'+dependency,(c/dependency).as_posix())
 p=c/f;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
shutil.copyfile(r/'research/performance/session_pair_probe.gd',w/'paired_session.gd')
print('Prepared 3-file production change plus isolated benchmark dependency paths')
