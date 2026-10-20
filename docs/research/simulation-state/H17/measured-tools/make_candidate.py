from pathlib import Path
import shutil,difflib
r=Path.cwd();w=r/'tmp/perf-pass4-20261019';c=w/'candidate'
files=['physics/slipstream.gd','physics/dynamics.gd','sim/flight_session.gd']
for f in files:
 s=(w/'base/app'/f).read_text()
 if f=='physics/slipstream.gd':
  # Retained function template keeps the measured candidate reproducible.
  start=s.index('static func _segmented_increment(');end=s.index('\n\n## The tail law',start)
  s=s[:start]+(w/'segmented_increment_candidate.gd.txt').read_text()+s[end:]
 p=w/'intended'/f;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
 for dependency in files:s=s.replace('res://'+dependency,(c/dependency).as_posix())
 p=c/f;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
shutil.copyfile(r/'research/performance/session_pair_probe.gd',w/'paired_session.gd')
a=(w/'base/app/physics/slipstream.gd').read_text();b=(w/'intended/physics/slipstream.gd').read_text()
(w/'target.patch').write_text(''.join(difflib.unified_diff(a.splitlines(True),b.splitlines(True),fromfile='a/app/physics/slipstream.gd',tofile='b/app/physics/slipstream.gd')))
print('Prepared slipstream candidate and three-script benchmark dependency graph.')
