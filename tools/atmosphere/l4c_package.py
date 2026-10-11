#!/usr/bin/env python3
"""Package completed L4c evidence without modifying or re-encoding engine captures."""
import argparse
import gzip
import hashlib
import html
import json
from pathlib import Path


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('visual','profile','integration','out'):
        p.add_argument('--'+key,type=Path,required=True)
    a = p.parse_args()
    for folder in (a.visual,a.profile,a.integration):
        assert (folder/'summary.json').is_file(), 'incomplete evidence: '+str(folder)
    a.out.mkdir(parents=True,exist_ok=True)
    assert (a.out/'README.md').is_file(), 'write the evidence report README.md before packaging'
    written=[]

    def save(name,data):
        target=a.out/name
        assert not target.exists(), 'evidence already exists: '+name
        target.write_bytes(data)
        written.append(name)

    for label,folder in [('visual',a.visual),('profile',a.profile),('integration',a.integration)]:
        save(label+'-summary.json',(folder/'summary.json').read_bytes())
        if (folder/'sources.json').exists():
            save(label+'-sources.json.gz',gzip.compress((folder/'sources.json').read_bytes(),mtime=0))
    for report in sorted(a.profile.glob('*/report.json')):
        save('profile-'+report.parent.name+'.json.gz',gzip.compress(report.read_bytes(),mtime=0))
    logs='\n'.join('== '+log.parent.name+'\n'+log.read_text() for log in sorted(a.profile.glob('*/engine.log')))
    save('profile-logs.txt',logs.encode())
    # Retain every capture; store identical PNGs once, indexed by logical path.
    import io,zipfile
    buf=io.BytesIO()
    with zipfile.ZipFile(buf,'w',compression=zipfile.ZIP_DEFLATED) as archive:
        files=list(a.visual.glob('*/*.png'))+list(a.visual.glob('*/report.json'))+list(a.visual.glob('*/engine.log'))
        files += [x for x in a.integration.iterdir() if x.suffix in ('.png','.json','.csv','.log')]
        manifest={}
        stored=set()
        for source in sorted(files):
            parent=a.visual if source.is_relative_to(a.visual) else a.integration
            name=('visual/' if parent==a.visual else 'integration/')+source.relative_to(parent).as_posix()
            data=source.read_bytes()
            digest=hashlib.sha256(data).hexdigest()
            member='images/'+digest+'.png' if source.suffix=='.png' else name
            manifest[name]={'member':member,'sha256':digest}
            if member in stored:
                continue
            stored.add(member)
            entry=zipfile.ZipInfo(member,date_time=(2026,10,11,0,0,0))
            entry.compress_type=zipfile.ZIP_DEFLATED
            archive.writestr(entry,data)
        entry=zipfile.ZipInfo('manifest.json',date_time=(2026,10,11,0,0,0))
        entry.compress_type=zipfile.ZIP_DEFLATED
        archive.writestr(entry,json.dumps(manifest,indent=2)+'\n')
    save('captures-and-integration.zip',buf.getvalue())
    pairs=[]
    for view in ('sun','cross','zenith'):
        for key in ('before','after'):
            save(key+'-'+view+'.png',(a.visual/(key+'-day')/(view+'-000.png')).read_bytes())
        pairs.append((view.title()+' · fixed field camera', 'before-'+view+'.png','after-'+view+'.png'))
    for case in ('day','sunrise','moon'):
        for key in ('before','after'):
            save('app-'+key+'-'+case+'.png',(a.integration/(key+'-'+case+'.png')).read_bytes())
        pairs.append(('Actual app · '+case,'app-before-'+case+'.png','app-after-'+case+'.png'))
    cards=[]
    for title,before,after in pairs:
        cards.append(f'<section><h2>{html.escape(title)}</h2><div class="pair"><figure><figcaption>Before</figcaption><a href="{before}"><img src="{before}" alt="Before: {html.escape(title)}" loading="lazy"></a></figure><figure><figcaption>After</figcaption><a href="{after}"><img src="{after}" alt="After: {html.escape(title)}" loading="lazy"></a></figure></div></section>')
    page='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>L4c · directional cloud relief</title>
<style>body{font:16px/1.55 system-ui,sans-serif;background:#101820;color:#e7eef3;margin:32px auto;max-width:1600px;padding:0 24px}a{color:#9cd9ff}h1{font-size:32px}h2{font-size:19px;margin-top:32px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:16px}figure{margin:0}figcaption{margin-bottom:8px;color:#aebfcf}img{width:100%;display:block}p{max-width:80ch}@media(max-width:850px){.pair{grid-template-columns:1fr}}</style>
<h1>Directional cloud relief</h1><p>Godot 4.7.2 · Compatibility · RTX 3090 · 4× MSAA. Original engine PNGs; click to inspect at full resolution. Fixed cameras, poses and simulation times. The small aircraft and calibrated lighting are preserved.</p>
<p><a href="README.md">Research, verification and limits</a> · <a href="profile-summary.json">Raw timing summary</a> · <a href="captures-and-integration.zip">All captures, logs and trace evidence</a></p>'''+''.join(cards)+'</html>'
    save('review.html',page.encode())
    hashes={name:hashlib.sha256((a.out/name).read_bytes()).hexdigest() for name in written}
    save('artifact-hashes.json',(json.dumps(hashes,indent=2)+'\n').encode())
    print('Packaged',len(written),'artifacts')


if __name__=='__main__':
    main()
