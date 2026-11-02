# GDU-12: native backend checks on Godot 4.8 beta2

2026-11-01. The optional ground-vehicle evaluator was rebuilt and tested with
official Godot `4.8.beta2.official.cafc17a19` on Windows and WSL Ubuntu 24.04,
using the existing godot-cpp `10.0.0-stable` / extension API `4.7` dependency.
Both builds loaded the extension, passed the float64 round-trip and all 733
evaluator checks, and returned 2,676 bit-exact lake scalars at 669 coordinates.

| Host | Evidence | Binary SHA-256 |
| --- | --- | --- |
| Windows x86_64, MSVC 14.51.36231, SDK 10.0.26100.0 | [Build and parity log](ground-windows-build.log), [receipt](ground-windows-receipt.json) | `5a89d82a25b0144859c7e96963ca2ef4888f19997acbf6a23d760bcd26235032` |
| WSL Ubuntu x86_64, GCC 13.3.0 | [Verifier](ground-linux-verification.json), [build log](ground-linux-build.log), [receipt](ground-linux-receipt.json) | `ea9896ecf7c5030501dcaae0fdce2db70529a204d7f4948fe1a917a2d17de884` |

The Linux verifier used a sparse, source-hashed copy of commit
`46b004c7b469448c29ef96168da4f03cee2c6d23` plus the working-tree native
toolchain changes. Windows used a separate app and native-source copy. The
checks are software parity, not physical validation or a performance claim;
other work shared the host. Previous [beta1 evidence](../../GDU-03/native/README.md)
retains its original build identity.

The normal `build.py --install-only` gate accepted both binary hashes, platform
receipts, current source/toolchain hashes and the pinned license in a disposable
app copy. Its [aggregate receipt](ground-installed-receipt.json) records both
platforms. The same gate then installed the verified pair in the root app; the
previous ignored artifacts were preserved under
`D:/OpenRCsimulator-experiments/gdu-beta2-identities/root-ground-before/`.
The [root production-path test](ground-root-checked.json) passed 55 checks,
including execution of both native and reference paths over a driven,
steered and braked 180-tick trajectory. Timings in its log are incidental.

For NK-3, an initial beta2 build with the Windows checkout's CRLF fuel registry
passed its installer oracles but failed the post-install fleet policy check:
[13 of 569 checks failed](nk3-crlf-runtime-domain-engine.log), all stemming
from P-51 and Avanti startup-configuration identities. The [checked report](nk3-crlf-runtime-domain-check.json)
records the failed gate; the [original oracle evidence](nk3-crlf-oracles/) is
bound to that CRLF input and is not the installed qualification.

The fuel registry is hashed as exact bytes. Its checkout contained CRLF while
the existing startup pins were recorded from the unchanged LF Git blob. On the
same sources, beta1 and beta2 produced the same mismatch; a disposable LF-only
registry replacement restored all four affected P-51/Avanti pins while four
Turbo Lumber controls remained unchanged. [Diagnosis and capture identities](fuel-eol-diagnosis.json)
retain both inputs and the independent comparison; the [probe](fuel-eol-probe.gd)
ran from a disposable native-kernel directory. The scoped `.gitattributes` rule
now preserves LF; a [fresh autocrlf=true checkout](fuel-eol-checkout.json)
verified the registry and sampled evidence byte hashes. No JSON values, physics
laws, startup assertions or goldens were changed.

With the canonical LF registry, the normal and separate mutant libraries were
rebuilt ([normal receipt](nk3-lf-build-receipt.json), [mutant receipt](nk3-lf-mutant-receipt.json)).
All [19 source-bound oracle gates](nk3-oracles/verification-index.json) passed;
the 14,400-tick CI trajectory recorded 156,030 identical comparisons, and the
negative control detected 28,305 differences. The loader recheck passed all
19 guarded cases and five qualification hosts ([log](nk3-lf-loader.log),
[checked runs](nk3-lf-loader-checks/)). All nine [installed-native fixture checks](nk3-lf-runtime-checks/)
passed, including 569 fleet-policy checks and six actual runtime-domain proofs;
the separate C++ rejection boundary passed [40 checks](nk3-glow-boundaries.log).
The short production reference/native [trim and runway smoke](nk3-lf-production-probe.json)
completed with matching fingerprints. The guarded installer then installed the
verified Linux library in the root app ([receipt](nk3-lf-installed-receipt.json)).
The [root production-path checks](nk3-root-checks/) then passed stage, session,
replay, helicopter and helicopter-radio native branches.

The frozen Linux export checkout uses different source-file bytes from the
Windows-root checkout, including the explicitly CRLF HX-700 aircraft file. A
separate locked build and qualification were therefore performed against that
checkout's bytes; the two normal binaries have the same SHA-256, but their
source and harness receipts differ. The [export selector](nk3-export-source-selector.json)
accepted all 19 proofs directly against the frozen checkout, and a 228-file
[source inventory](nk3-export-source-inventory.json) remained [unchanged](nk3-export-source-after.json).
The [export oracle index](nk3-export-oracles/verification-index.json),
[loader checks](nk3-export-loader-checks/), and [nine installed-native checks](nk3-export-runtime-checks/)
all passed, including 569 fleet-policy checks and six runtime-domain proofs.
The separate [production smoke](nk3-export-production-probe.json) matched trim
and runway reference/native fingerprints. This qualifies the native build inputs;
it does not by itself establish the exported package gate.

The retained aircraft library is Linux x86_64 only. The four canonical
MoonRunner rows remain unqualified, and these software checks do not establish
full-fleet, physical, target-hardware performance or other-platform acceptance.
