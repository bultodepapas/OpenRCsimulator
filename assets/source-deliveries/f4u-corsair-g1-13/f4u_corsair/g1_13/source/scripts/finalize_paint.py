# Compatibility entry point for the current revision.
from pathlib import Path
exec(compile(Path(__file__).with_name('finalize_super57.py').read_text(encoding='utf8'),str(Path(__file__).with_name('finalize_super57.py')),'exec'))
