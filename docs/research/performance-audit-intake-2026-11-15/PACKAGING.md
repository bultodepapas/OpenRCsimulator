# Historical performance evidence packaging

These packages preserve historical reports, patches, measurements, checks and reproducer sources. They describe dated source snapshots, not the current implementation, CI state, performance or hardware qualification. Review historical patches against the current source and contracts before considering them.

The original archives remain untouched. Of 754 original members, the public packages retain 751 paths: 750 members retain their original bytes, and one historical ledger retains its original content except for two explicitly marked private attachment URL redactions. Round 1 omits exactly three generated files. Round 2 is a public derivative with all 471 original paths. The JSON provenance file records original and packaged identities, member dispositions, exact redaction count and omission reasons without exposing the private URLs.

The embedded manifests remain unchanged historical records of the originals. The round 1 embedded manifest still lists its three omitted files. The round 2 embedded manifest still lists the original digest of its redacted ledger, which differs from the public member. Use the external provenance manifest to verify each derivative.

The separate Round 3 Markdown Page export is not in either ZIP. Its filename, byte count and SHA-256 are recorded in the provenance file.

## Archives

- `performance-evidence-round1-compact.zip`: 580,800 bytes; SHA-256 `a2704cc143180f5819a62d4b279faa8edb4a1395094279f9f6f0c6dd93c8f301`; 280/283 original paths retained. Original `OpenRC-performance-evidence.zip`: 8,719,560 bytes; SHA-256 `d23bf89c119807338f2f5af862f1665dfe674baea5ba1a18cff4c018b99e39de`.
- `performance-evidence-round2-public.zip`: 1,248,746 bytes; SHA-256 `308006fcd605f3281360c129904de8c557127caf522688c01c2ecaa7c87a714b`; 471/471 original paths retained. Original `OpenRC-performance-evidence(1).zip`: 1,248,748 bytes; SHA-256 `2c5cb4e2a4f07e0b1b6c8611ca861421002fd03f1e733b1a1b6546aee3595b60`.

## Round 2 public redactions

- `OpenRC-review-r2/root-output/COMPLETED-AUDIT-WORK-300dc.txt`: two private account-scoped attachment URLs were replaced with `PRIVATE_ATTACHMENT_URL_OMITTED_FOR_PUBLICATION_1` and `PRIVATE_ATTACHMENT_URL_OMITTED_FOR_PUBLICATION_2`. All other bytes in this member are unchanged.
- Original member: 97,477 bytes; SHA-256 `6309bfbe93566a04494126fe8d5d9d2d392cde72809e96c8c6afd5eaeff9d81d`. Public member: 97,414 bytes; SHA-256 `636586a01d137b2a1a61f63ce6c23e2ba45dc3da9dd53296679a2dc26589e4f8`.

## Exact omissions from round 1

- `OpenRC-performance-evidence/cpu-output/audio-xdg/cache/godot/editor_doc_cache-4.8.res` — 3,350,501 bytes; SHA-256 `8a288ed90e051cd70ee9e623789f7196f3d3b2406965ec1ccea64a493a43e509`. Generated Godot 4.8 editor documentation cache, not a measurement, check receipt, fixture, source, report or patch.
- `OpenRC-performance-evidence/git-tree.txt` — 6,535,199 bytes; SHA-256 `8da25a91e8fd729349872bbc53405267822145d58fef0ce396c7394c2e0c1ae1`. Generated bulk inventory of repository tree; the reviewed Git commit identifies the tree and can regenerate an inventory. This removes the original inventory bytes from the compact package; its exact original SHA-256 is retained here.
- `OpenRC-performance-evidence/physics-output/xdg-cache/godot/editor_doc_cache-4.8.res` — 3,350,501 bytes; SHA-256 `24ec8da06e67c0dbb0b47dcd3b2c82f7073823644977e7a00d1c184f8ed6f0fd`. Generated Godot 4.8 editor documentation cache, not a measurement, check receipt, fixture, source, report or patch.

The bulk tree was recorded for reviewed base `8fb825a96dbc39fbbf99c1056ba643c9cde49b5d`; regenerate a tree listing from that Git object if needed and compare its recorded SHA-256 before assuming byte identity. No standalone image files were present in either supplied archive.

`evidence-provenance.json`: 305,866 bytes; SHA-256 `b06c31aa7b100f677a1f29e21fecd4326437560948ff5a280806d6a3d308d860`.
