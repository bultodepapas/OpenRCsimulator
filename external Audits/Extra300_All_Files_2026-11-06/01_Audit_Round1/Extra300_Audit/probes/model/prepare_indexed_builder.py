#!/usr/bin/env python3
"""Create only the pinned isolated Extra loft-indexing alternative."""
import argparse
import hashlib
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
raw = args.source.read_bytes()
expected = "b4a6d5b4784985b042c3ac59bdaf422d0c8ab5007b70b39a113124f6e82d6c51"
if hashlib.sha256(raw).hexdigest() != expected:
    parser.error("Source is not the pinned baseline builder; inspect before adapting.")
text = raw.decode()
start = text.index("static func _loft(")
end = text.index("\treturn st.commit()", start)
candidate = text[:end] + "\tst.index()\n" + text[end:]
if args.output.exists():
    parser.error("Output already exists; choose a new disposable path.")
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(candidate)
print(args.output)

