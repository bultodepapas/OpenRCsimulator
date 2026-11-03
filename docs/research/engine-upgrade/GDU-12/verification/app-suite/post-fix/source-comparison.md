# GDU-12 post-fix source comparison

The Linux suite runs from a frozen copy based on commit
`46b004c7b469448c29ef96168da4f03cee2c6d23` with the migration changes and the
population-test correction applied. Its full parse roster digest is
`3fc5b1fa77533fb916bde7772ab5b2ec3100360bbcd3669d60f72ee5b5c632fb`; its unit
roster digest is `0237cf8841bf9afe50d7a5a369854d2d9e6bb3cd3a249fe39665acf267ddd374`.
These digests bind scripts and specified runners, not every transitive input.
The Windows working-tree parse and unit digests at this comparison were
`b2a62b148020431dfde4f3982f19fdd8ec0ec3708053d4d583827e133935803a` and
`86a06b563549e9ea1b0d35cd837e26b20c1638d2120bb76497323b699f8c310c`.
The receipt verifier checks exact bytes and commit IDs, so a successful check
against the frozen Linux copy does not directly verify the newer Windows
checkout.

A point-in-time comparison against the Windows working tree at commit
`a3314cdf23e8fd6e2b0f429e338c002e9c506012` read 10,076 tracked paths outside
`docs/`. It found 5,413 byte-identical paths and 4,663 paths differing only in
CRLF versus LF. Of those, 4,659 have no explicit `text` or `eol` attribute;
Windows Git reports `core.autocrlf=true`. The other four have explicit EOL
rules and remain distinct byte identities:

| Tracked path | Windows SHA-256 | Frozen Linux SHA-256 | Declared EOL |
| --- | --- | --- | --- |
| `app/data/aircraft/hx700_electric_3d_experimental.json` | `6805ea966fbcd07111d89743946b4dd7a46d58ad6057085c15bb21cfd0e0731e` | `b1d07c3c8a5e9e196f218fa3f049fb084f286dd262ac1aa317408311ecfb115a` | CRLF |
| `app/data/ground_vehicle/airfield_track.json` | `b178c5c22dd77160a48bd72d2e473f52e66a65c52843d25770b224f6cebbba81` | `31ee093d4fc968d8bfb083a7ee89315030373ce886f87195b78115000e680e29` | LF |
| `app/data/ground_vehicle/practice.json` | `55fd8cac65a004308a618d50a3034677d09d32b093768008e1b42f9716a290f5` | `e73d770799791cf8dafeb22c77c78cfd4d4adca3450093c140cb485233141d1c` | LF |
| `research/crash-economics/repair-recipes.json` | `093ac19f3714e60b27b05888a80f9e704622483d199e5560e2a81cbd8fac08db` | `ef1061301e658fca9c1609cd726fc58dd8967a2ba7505df75b196acfe0f50b02` | LF |

The Windows HX-700 file is LF while the frozen version is CRLF; the other
three are CRLF on Windows and LF in the frozen source. The fuel registry is
byte-identical at `6f4908ba7ea67eac4f5c01580ce88aae95355b76852586ee9ef299ba03f7e043`.
The separate [Linux aircraft-native build using Windows-workspace bytes](../../../native/nk3-lf-build-receipt.json)
and [Linux export-source build](../../../native/nk3-export-build-receipt.json)
bind their respective HX-700 identities. Matching after line-ending conversion
is not a claim of raw-byte equivalence or proof that a byte-sensitive consumer
can substitute one version for the other.

The comparison excluded documentation, ignored files and untracked files,
including staged native libraries. The isolated RAM test copy uses the frozen
ext4 documentation tree as a shared read-only input and has its own app import
cache and user profiles. The saved raw comparison is
`D:/OpenRCsimulator-experiments/gdu-beta2/postfix-source-preliminary-comparison.json`;
its workspace and frozen collection digests are respectively
`d969d51488415323fd4abc25f906d7f3ae19152c82d4ea82e23c9df92a7ad2ee` and
`c78cd067036693300b47cb74d82aa4762fc15c8b35451226ac13a3ce9ce5b097`.
