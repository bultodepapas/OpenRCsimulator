from pathlib import Path
import subprocess,zipfile,io,json,hashlib
r=Path.cwd();w=r/'tmp/perf-pass4-20261019'
commit=(w/'baseline-head.txt').read_text().strip();captured=json.loads((w/'source-hashes.json').read_text())
archive=zipfile.ZipFile(io.BytesIO(subprocess.check_output(['git','archive','--format=zip',commit,'app'])))
different=[];missing=[]
for rel,sha in captured.items():
 data=(w/'base/app'/rel).read_bytes();assert hashlib.sha256(data).hexdigest()==sha
 try: original=archive.read('app/'+rel)
 except KeyError: missing.append(rel);continue
 if original.replace(b'\r\n',b'\n')!=data.replace(b'\r\n',b'\n'):different.append(rel)
(w/'baseline-identity.json').write_text(json.dumps({'commit':commit,'compared_runtime_files':len(captured),'normalization':'CRLF to LF only','different':different,'missing':missing},indent=2))
print('Baseline identity',commit,'different',different,'missing',missing)
