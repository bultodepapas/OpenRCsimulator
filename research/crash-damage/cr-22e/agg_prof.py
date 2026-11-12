import re,collections,sys
lines=open(sys.argv[1],encoding="utf-8",errors="replace").read().splitlines()
must=sys.argv[2]; top=int(sys.argv[3])
idx=[i for i,l in enumerate(lines) if l.startswith("FRAME:")]+[len(lines)]
agg=collections.defaultdict(lambda:[0.0,0.0,0]); n=0; ticks=0
for a,b in zip(idx,idx[1:]):
    block={}
    for j in range(a+1,b-1):
        m=re.match(r"\d+:(.+)$",lines[j])
        if m:
            t=re.search(r"total: ([0-9.]+)/.*self: ([0-9.]+)/.*tcalls: (\d+)",lines[j+1])
            if t: block[m.group(1)]=(float(t.group(1)),float(t.group(2)),int(t.group(3)))
    hit=[k for k in block if must in k]
    if not hit or any("_run" in k and block[k][0]>0.05 for k in block): continue
    n+=1; ticks+=block[hit[0]][2]
    for k,v in block.items():
        x=agg[k]; x[0]+=v[0]; x[1]+=v[1]; x[2]+=v[2]
print("blocks",n,"ticks",ticks)
for name,(t,s,c) in sorted(agg.items(),key=lambda x:-x[1][int(sys.argv[4]) if len(sys.argv)>4 else 0])[:top]:
    print(f"total/tick {t*1e6/ticks:8.1f}us self/tick {s*1e6/ticks:8.1f}us calls/tick {c/ticks:7.2f} {name[-80:]}")
