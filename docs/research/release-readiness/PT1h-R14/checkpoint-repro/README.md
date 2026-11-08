# Checkpoint save reproduction

This fixture invokes the real `DebugBridge._cmd_checkpoint` save and load handlers with a small fake flight session.
It checks UTF-8 publication and link paths on Windows/POSIX, POSIX short writes and permissions, and native Windows
sharing failures. It does not launch a real flight or establish storage power-loss durability.

## Run against the current checkout

On a POSIX host with Python 3 and a verified Godot executable, from the repository root:

```sh
python3 -B docs/research/release-readiness/PT1h-R14/checkpoint-repro/run.py \
  --godot .tools/Godot_v4.8-beta2_linux.x86_64 \
  --out-dir tmp/checkpoint-repro
```

Native Windows uses the same command with `python` and
`--godot .tools/Godot_v4.8-beta2_win64_console.exe`. It runs eight applicable cases, including a real handle that
allows reads/writes but denies deletion. Failed publication preserves the original and a verified recovery copy;
the fixture checks both. It does not force a failure after the original has already been removed. Symlink cases
require permission to create Windows links. POSIX mode bits, file-size limits and the POSIX long-name case are
explicitly inapplicable there. Windows normalizes parent components in relative link targets before traversal;
its dangling-link case verifies safe refusal because Godot cannot resolve the missing target. Use a fresh output
directory; the receipt records the platform and applicable cases.

The default `--expect fixed` checks the corrected behavior and exits nonzero if an observation or a checked Godot run fails. The output directory receives `receipt.json` and one bounded `tools/godot/run_checked.py` report and engine log per case. The runner creates a disposable project beneath that output directory and removes it afterward. It copies the checkout's GDScript and shader sources, supplies a minimal `project.godot`, and replaces only `landscapes/catalog.gd` and `app_state/preferences.gd` with small unrelated stubs. No repository source, binary asset, existing checkpoint, or running app is modified.

The limited-write case sets `RLIMIT_FSIZE` to 64 bytes and ignores `SIGXFSZ` **in the Godot child only**. It starts with a 29-byte existing checkpoint and expects the write to fail while preserving those bytes and leaving no sibling files, including hidden files. The normal case verifies exact Unicode bytes, their reported count, and loading through the bridge. Other cases exercise a 240-byte filename, preservation of mode `0600`, an absolute symlink, a relative two-link chain, a directory symlink followed by `..`, creation through a dangling symlink, refusal of a cycle, and refusal of a missing intermediate directory before `..` without changing an unrelated file. The filesystem's symlink and mode observations come from Python after the Godot command, independently of the bridge's reply.

To reproduce the historical behavior, use a disposable checkout at commit `9db50cfc70904e262247d97e1c368f7c499ff23d`, copy this `checkpoint-repro` directory into the same path in that checkout, and run the command there with `--expect vulnerable`. In that mode, a PASS means the historical observations were reproduced: the short write returns success after truncating the file, and the UTF-8 byte field reports the character count. The symlink and mode controls check historical compatibility. Do not point the output directory at a checkpoint you want to keep.

## Recorded evidence

`verification.json` contains compact observations and source identities from the baseline and candidate runs. The recorded baseline bridge SHA-256 is `ac85e099cfa4c46cc3516d68da327d8b4b0f2710fe3a2dabd0fa94225f21d9c5`. The baseline run used a disposable script-only copy whose locally changed tracked scripts were restored from that commit, followed by the two stubs described above; it was not a full-asset checkout. The candidate is identified by its bridge SHA-256 because its test was run from an uncommitted working tree based on the same HEAD. Each checked report required the observation marker and reported zero engine errors and warnings.

The Linux runs used Godot `4.8.beta2.official.cafc17a19`; the executable's SHA-512 is recorded in the JSON. They do not establish the Windows recovery path, durability across a crash, preservation of ACLs or ownership, or behavior on every filesystem. Godot's pinned Windows `DirAccess` implementation removes an existing destination before moving the replacement; the candidate keeps a recovery copy for that path, but this fixture does not validate it on Windows.

Those are historical Linux receipts. The [2026-11-08 native follow-up](../README.md#native-windows-integration-and-d14-follow-up-2026-11-08)
and [native receipts](../verification-native.json) record the updated runner's Windows cases and their limits.
