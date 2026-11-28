"""Count emitted warm copy traffic at the native tick-context ground/pose boundary."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

p=argparse.ArgumentParser()
p.add_argument("repo", type=Path)
repo=p.parse_args().repo.resolve()
here=Path(__file__).resolve().parent
def data(name):
    return json.loads((repo / "app" / "data" / name).read_text())
field=data("fields/default.json")
lake=data("fields/lake.json")
sizes=[6*(len(field["surfaces"])+1),2*len(lake["shoreline_offsets_ne_m"]),
       2*len(lake["bank_offsets_ne_m"]),len(lake["bed_profile"]),len(lake["bed_profile"])]
stock={}
for name in ("f4u_corsair_250", "p51d_mustang_120", "sebart_avanti_s_a200"):
    gear=data(f"aircraft/{name}.json")["landing_gear"]
    assert gear["retraction"]
    stock[name]=len(gear["contacts"])
assert all(n==3 for n in stock.values())
owner=(repo/"research/native-kernel/src/nk_kernel.cpp").read_text()
pose=(repo/"research/native-kernel/src/nk_retractable.hpp").read_text()
assert "tick_.posed_ground = stage_.ground;" in owner
assert "nk::retractable_pose(stage_.ground.gear, stage_.retraction, tick_.aux[index], tick_.posed_ground.gear)" in owner
assert "if (!m.enabled || extension == 1.0) { out = base; return true; }" in pose
flags=["-std=c++17","-O2","-fno-fast-math","-ffp-contract=off"]
with tempfile.TemporaryDirectory() as work:
    binary=Path(work)/"probe"
    subprocess.run(["g++",*flags,"-I",str(repo/"research/native-kernel/src"),str(here/"retractable_context.cpp"),
                    "-Wl,--wrap=memcpy","-Wl,--wrap=memmove","-o",str(binary)],check=True)
    output=subprocess.check_output([str(binary), *map(str,sizes)],text=True)
keys=["epoch","retractable","accepted","current_contact_bytes","candidate_contact_bytes","current_terrain_bytes","candidate_terrain_bytes"]
rows=[dict(zip(keys,map(int,line.split()))) for line in output.splitlines()]
print(json.dumps(dict(compiler=subprocess.check_output(["g++","--version"],text=True).splitlines()[0],
    stock_contacts=stock,stock_vector_lengths=sizes,flags=flags,cases=6*240,rows=rows),indent=2))
