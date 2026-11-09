# Manual telemetry recovery

This tool reads the raw chunks of an interrupted **T** recording. F10 `.orfl` replay
and recovery remain in [the flight logging guide](../../docs/FLIGHT-LOGGING.md).

Run against a copied, inactive spool, using the pinned engine and the checked runner:

```powershell
python tools/godot/run_checked.py --out-dir tmp/trace-recovery --timeout 120 --require-text TRACE_CHUNK_RECOVERY_COMPLETE -- .tools/Godot_v4.8-beta2_win64_console.exe --headless --path app --audio-driver Dummy --script ../tools/trace/recover_chunks.gd -- --spool=C:/path/to/trace-spool --out=C:/path/to/new-recovery-directory
```

The tool reserves a new output directory and writes `recovered.csv` inside it. An
existing destination is refused. It validates packet lengths, schema, chunk order,
recording identity and checksums, retaining only the contiguous verified prefix.
The JSON result reports the path, row count and errors. Read it even when the process
fails: a verified prefix may have been retained before a damaged or missing packet.

Every recovery is explicitly **incomplete**. Buffered or in-flight rows and metadata
edits since the last published chunk may be absent. A normal successful T stop saves
the entire accepted recording, including its memory tail; this recovery tool cannot
reconstruct data that was never published. Flushed files are not a power-loss
durability guarantee. Recovering telemetry does not establish exact simulation replay.

Spools are under `user://trace_spools/` by default. The recorder reports its reserved
directory when it stops for storage pressure or I/O failure. Normal successful saves
release their spools when the trace owner is cleared or destroyed; unsaved published
prefixes remain for recovery. Original spool files are not edited by recovery.
