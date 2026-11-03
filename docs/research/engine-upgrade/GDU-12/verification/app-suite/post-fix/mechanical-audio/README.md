# GDU-12 mechanical-audio investigation and first candidate

This record retains the initial test-only candidate and its evidence. Review
found that a frame observed after the deadline could pass its count-only check;
the [revised test and deadline control](../mechanical-audio-final/README.md)
are the final targeted result.

The frozen Linux shard 2 passed the original test's 103 assertions, but its
checked log reported four ObjectDB instances at shutdown. A separate earlier
beta2 invocation of that named test had no shutdown warning. Neither result
identifies the retained objects or establishes a production leak.

On an isolated beta2 Linux RAM copy, five unchanged quiet runs all reported
2–14 retained objects; three of five verbose runs reported 4–14. The verbose
logs identified `AudioStreamWAV` and `AudioStreamPlaybackWAV` instances. A
single process frame still left warnings in three of five test-only trials;
250 ms left none in five. A fixed delay alone did not establish release.

The first candidate was confined to `app/tests/test_mechanical_audio.gd`. Before
reconfiguration and teardown, the test records non-owning references to its
observed playbacks and streams. It retained the 103 existing assertions,
checked that both kinds were observed, and attempted a one-second drain check.
A playback-only trial demonstrated why both are needed: three runs still had
live stream references and shutdown warnings even after the tracked playback
references had cleared.

The combined draft observed 14 playback and 42 stream references per run,
including possible duplicates. Five normal runs drained within 0–58.2 ms.
Three controls retaining a playback and three retaining a stream each timed out
near one second, then drained after the strong reference was released. All 11
checked draft runs passed with warnings treated as errors. On the first candidate
bytes, one Windows and five isolated Linux checks each passed 106 assertions
without engine warnings or errors. Two additional disposable controls, made
from those candidate bytes, deliberately retained a playback or stream: each
failed only the new drain assertion after about one second, as intended.

The frozen suite used test SHA-256
`9cab0bb40a625b0f5af3cd7e433f9c26fd19b2a793102dab3fd25f8415046249`;
the first candidate test hash was
`a43576219a24e102e7029ca1f52d2d439477cf876caa73e9126204cb75511332`
on both platforms. Replacing only that file in the frozen Linux app copy changes
the full parse roster digest from
`3fc5b1fa77533fb916bde7772ab5b2ec3100360bbcd3669d60f72ee5b5c632fb` to
`22ea0fc5ed0ca071f51774e4c20e258d92ff1c90a411f1201eeda9ba312a5477`,
and the unit digest from
`0237cf8841bf9afe50d7a5a369854d2d9e6bb3cd3a249fe39665acf267ddd374` to
`ec19613c88bdb16dd09ebc1c6d09018d82d4cbe15137e2854614a1478688eb46`.
These computed overlay identities are not full-suite receipts for the changed
test. The frozen suite, visual and export sources were not edited.

The production audio scripts were not changed. Windows and frozen Linux
`mechanical_audio.gd` have different raw hashes because of CRLF/LF checkout
encoding; their normalized content matches. `mechanical_motion.gd` is
byte-identical. The [verification record](verification.json) binds source,
reports, logs, JUnit summaries and negative-control hashes. Raw collections are
retained under `D:/OpenRCsimulator-experiments/gdu-beta2/mechanical-audio-test-final/`
and the neighboring `mechanical-audio-lifecycle-*` directories. This check
establishes bounded release only for the references observed in these fixtures;
it is not a complete production lifecycle or perceptual audio qualification.
