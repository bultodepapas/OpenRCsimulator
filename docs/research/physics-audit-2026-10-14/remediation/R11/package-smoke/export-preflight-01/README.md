# Native export receipt preflight

This evidence checks the `PYRECEIPT` Python block embedded in `app/export.sh` without running an export. The exact extracted source is `preflight.py` (SHA-256 `724f14787ca7c91228c3fdc99c7f1d1a1716c6f9b5fd3a4a38e3ccf5c6f5d258`); `app/export.sh` at the time of extraction hashes to `dd7230a202a0ca01f805a6797963c37ece39306d8fbed956f5ed8d733c2a75e4`.

The positive case used the merged receipt `receipt-merge-20261015-02/build-receipt.json` (SHA-256 `8718896783cb792f949732a5a4d74c6d08a1bde0bd52c43f9d1982efb3fd9ff7`), the actual -08 Linux library (SHA-256 `08c8c08e74bd9c9465d1c0f732b082fc23829dcf243287eac51f25ed4e98f3a3`), and the historically verified Windows DLL (SHA-256 `adafd1f9682dff147e538fdb7686329c009edf255c639789ac28dc403bc6e65c`). The Linux and Windows receipt rows share source `e2ae0a5f…`; each retains its own toolchain hash.

Command:

```text
wsl -d Ubuntu -- python3 /mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/package-smoke/export-preflight-01/run_preflight_cases.py /mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/native-package-staging/receipt-merge-20261015-02/build-receipt.json /home/bulto/openrc-r11-package-20261015-08/app/native/ground_vehicle/libopenrc_ground_vehicle.so /mnt/c/DEVELOPMENT/OpenRCsimulator/tmp/physics-audit-r11-native-package-staging-20261015-01/bin/openrc_ground_vehicle.dll /mnt/c/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/package-smoke/export-preflight-01/results-run-02
```

`results-run-02/results.json` records six cases, all passed (SHA-256 `06f9142f1a421904ec54ba3750ec1c34b202cbbf0cca5c903ce29bbb850ca8c2`):

| Case | Result |
|---|---|
| Actual merged receipt and both artifacts | Exit 0; both file hashes match their platform rows. |
| Missing Windows row | Exit 1; refuses the missing platform record. |
| Windows row ABI set to JSON `true` | Exit 1; rejects booleans as non-integer ABI values. |
| Windows row source changed | Exit 1; rejects disagreement with the shared source identity. |
| Optional top-level source changed | Exit 1; rejects disagreement with the platform rows. |
| One byte changed in a disposable Windows DLL copy | Exit 1; rejects the artifact hash mismatch. |

The canonical receipt schema has no top-level `source_sha256`; the check derives the shared identity from the platform rows and checks an optional top-level value if present. Original artifacts were read only. The corrupted DLL and mutated receipts are disposable fixtures under `results-run-02/fixtures/`.

`results-run-01/` is retained as an initial harness attempt: the preflight correctly rejected the corrupted DLL, but the harness expected a more specific phrase and marked that case false. `run_preflight_cases.py` was corrected to match the actual diagnostic; no preflight source change was needed between runs. The final harness SHA-256 is `fbf4fdfd00ee6ecda2458735918716af874888a1faf2a414fac4449fdac3e36e`.

For probe provenance, [the original draft](check_native_pack-before-json-abi-fix.gd) retains the earlier parse-passing source (SHA-256 `8084810a036e4a601596322550ff1b616f84e41bd0cfe514a5f220e8240365aa`). The corrected [app probe](../../../../../../../app/tests/check_native_pack.gd) hashes to `2249f62dfa8a4c8ffdabe78cab853a6247044be329d94c382c612e91f516d3ba`; its [parser result](../native-package-draft-parse-04/check-only.log) and [clean missing-row expected-negative](../linux-missing-windows-row-expected-negative-02/probe.log) are retained. The earlier attempted negative with invalid `free()` remains in [its own log](../linux-missing-windows-row-expected-negative-01/probe.log) and is not counted as a passing check.

This verifies the receipt preflight in isolation; it does not establish that an exported package or target platform runs.
