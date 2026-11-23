# Round-three telemetry follow-up evidence — 2026-11-23

This is a **discrete** documentation/probe review on the existing audit branch. See [the dated follow-up](../../../../docs/research/telemetry/TELEM-AUDIT-2026-11-22/follow-up-2026-11-23.md) for main-baseline reconciliation, the dynamic internal-resolution observation and remediation criteria.

## Bounded local probe

Run from any scratch directory with Python 3 and SQLite:

```sh
python3 research/telemetry/audit-2026-11-22/round3/quota_tail_probe.py
```

The Python script creates a disposable SQLite database under the OS temporary directory, copies the table/index DDL and relevant pragmas of current `RawStore`, computes the *live-page* quota using the exact `page_count`/`freelist_count`/`page_size` formula, and follows the same **quota-before-insert** ordering. It uses an 8 KiB synthetic byte string and inserts one synthetic dedup row. It does **not** call `RawStore` itself, the production HTTP endpoint, or the real JSON validator; its payload must **not** be represented as a valid telemetry batch. Nothing reads or sends player data.

Captured on Python **3.13.5**, SQLite **3.46.1**, an isolated temporary database, with local assertion that the precheck admitted the write, the post-insert live-page count exceeded the threshold, and exactly one row was stored:

- Initial live allocation: **32,768 B**
- Configured threshold: **36,864 B** (one 4,096-byte page headroom)
- Post-insert live allocation: **40,960 B**
- Overshoot: **4,096 B**
- Machine-readable capture: [evidence/quota-tail.json](evidence/quota-tail.json)

The finding concerns an **optional hard-ceiling requirement**, not a proof that the documented soft threshold is wrong. WAL/SHM and OS-resident size are deliberately not covered.

## Source and provenance

- Original audited source: `7940a4081e10994f34c858c4acac3d7a1a271464`.
- Inspected follow-up main: `85fc06ff3ed0074586691c1a7fce70687ea1558a` (after `ae3ef110c4b0ac52403f4618b55affea375de771`, with no changes to inspected telemetry source in between).
- Audit branch before additions: `fca0d912991e565b1ae72f121245c4bc4352ef07`.
- Local probe script SHA-256: `434c6c4788fc539ce2af5c6fc611a58daacf86e4361f0034dae1c1da45d503bc`.
- Local captured evidence SHA-256: `f7397c2efc0ecdc7e07d87962b29c1f95431fb6f288f0bb30ab700cdf2e68321`.
- Source anchor: [storage.py, RawStore._size and ingest](https://github.com/bultodepapas/OpenRCsimulator/blob/85fc06ff3ed0074586691c1a7fce70687ea1558a/services/telemetry/openrc_telemetry/storage.py#L152-L185).
- Dynamic scaling and telemetry context are **source-traced**, not executed. No Godot executable is available in this isolated audit runtime; no core suite, deployment or target-hardware profile was rerun.

**Scope boundary:** only documentation and synthetic audit files were written to the existing audit branch. Production code, configuration, credentials, remote service, raw data and external messages remain unchanged.
