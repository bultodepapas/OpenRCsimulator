from pathlib import Path
import re, shutil
base=Path('/workspace/scratch/a1128d42a6f8/openrc-audit/app')
target=Path('/workspace/scratch/a1128d42a6f8/evidence/routing/probe')
todo=['input/multirotor_input.gd','input/airship_input.gd','tests/mr_fixtures.gd','sim/airship/session.gd']
seen=set()
while todo:
 p=todo.pop()
 if p in seen: continue
 seen.add(p)
 f=base/p
 if not f.exists(): raise FileNotFoundError(p)
 dest=target/p
 dest.parent.mkdir(parents=True,exist_ok=True)
 shutil.copy2(f,dest)
 source=f.read_text(errors='replace')
 todo.extend(k for k in re.findall(r'(?:preload|load)\s*\(\s*[\"\']res://([^\"\']+)',source) if k.endswith('.gd') and k not in seen)
(target/'project.godot').write_text('config_version=5\n[application]\nconfig/name="OpenRC routing audit probe"\n')
print('Copied',len(seen),'source files')

# A static dependency of the isolated airship session pulls in absent rendering
# assets. The pause probe never calls collision queries, so stub that dependency
# in this disposable project only; keep production session and adapter unmodified.
(target/'scenery/collision_world.gd').write_text("""# Disposable pause-probe stub: collision queries are not exercised.
extends RefCounted
static func _world_header_is_valid(_world: Dictionary) -> bool: return true
static func _proxy_is_valid(_proxy: Dictionary) -> bool: return true
static func nearby(_world: Dictionary, _n: float, _e: float, _d: float, _reach: float) -> Array[Dictionary]: return []
static func _aabb_sphere_overlap(_proxy: Dictionary, _n: float, _e: float, _d: float, _reach: float) -> bool: return false
""")
