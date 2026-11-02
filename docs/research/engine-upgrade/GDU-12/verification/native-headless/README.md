# GDU-12 native Windows headless checks

The checked runner and its integrity summarizer passed both invocations with zero engine warnings or errors. The crash integration test used WASAPI and passed 244 assertions, including ten aircraft one-shot playback and ten hold/mute assertions. No Dummy-audio branch was skipped. The RCV session test passed 168 assertions with the installed Windows ground-native backend, including its backend-switch guards; no native-stage skip occurred.

The full commands, timestamps and raw log hashes are retained beside [the verification record](verification.json). These checks establish software behavior, not audible quality, controller acceptance or physical validation.
