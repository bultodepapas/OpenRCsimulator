# GDU-03: Windows outfit-manifest portability

2026-10-25. The integration suite's existing SC-HUM-07 outfit gate failed two
checks on native Windows. Runtime manifest keys used Windows backslashes while
the recorded contract uses POSIX paths. All six outfit JSONs also had CRLF
checkout bytes while their recorded raw SHA-256 hashes bind LF bytes.

`test_outfits.py` now serializes relative paths with `as_posix()`. The six specs
were restored to their exact recorded LF bytes, and an explicit `.gitattributes`
rule preserves those bytes on subsequent checkouts. Raw hash checks and recorded
manifests remain unchanged. No outfit content, generated people, texture, Blender
pipeline or runtime geometry changed.

Evidence:

- [Original byte proof](line-ending-proof.json): every CRLF spec matches its
  recorded hash after changing line endings alone.
- [Fresh-clone proof](checkout-proof.json): a disposable repository containing
  the actual attributes/specs was cloned with `core.autocrlf=true` and `false`;
  all six files retain the recorded raw hashes in both clones.
- All seven existing tests pass in the [root tree](root-tests.log) and
  [frozen integration tree](frozen-tests.log).
- [Verification receipt](verification.json) fingerprints the changed inputs.

This fixes Windows checkout/path portability. It does not requalify the
appearance or geometry of the population assets.
