# GDU-12 native Windows headless checks

The checked runner and its integrity summarizer passed all three invocations with zero engine warnings or errors. The crash integration test used WASAPI and passed 244 assertions, including ten aircraft one-shot playback and ten hold/mute assertions. No Dummy-audio branch was skipped. The RCV session test passed 168 assertions with the installed Windows ground-native backend, including its backend-switch guards; no native-stage skip occurred.

The separate WASAPI glow-pump check passed 25 assertions with no fallback. During a 0.601-second main-thread stall, it captured 0.597 seconds of nonzero audio and the generator skip count stayed at zero. The test and two production audio scripts match the earlier [candidate input manifest](../final-brake-post-fix/input-identities.json); their hashes and the exact command are in the verification record. The Windows test file and frozen Linux test file match after line-ending normalization but have different byte hashes, so this is complementary platform coverage.

The full commands, timestamps and raw log hashes are retained beside [the verification record](verification.json). These checks establish software behavior, not audible quality, controller acceptance or physical validation.
