# GDU-12 mechanical-audio final targeted check

The [investigation](../mechanical-audio/README.md) reproduced a shutdown
warning and showed that tracking playbacks alone misses retained WAV streams.
Its first test-only candidate waited for both sets of WeakRefs, but could pass
if a frame resumed after the one-second deadline and the resources were already
gone. The final test requires both tracked counts to be zero **and** the elapsed
time to be at most one second. Its assertion names the tracked scope explicitly.
Production audio code was not changed.

The original 103 assertions remain; three checks confirm that playback and
stream references were observed and drained. Strict checked runs passed all
106 assertions once on Windows and five times on an isolated Linux copy, with
zero engine warnings or errors. Two disposable controls retained a playback or
stream and each failed only the new assertion after one second. A third
released its held stream but delayed observation: at 1.115823 seconds both
counts were zero and the assertion still failed, as required. These are
expected control failures, not failures of the final test.

The frozen suite's test SHA-256 is
`9cab0bb40a625b0f5af3cd7e433f9c26fd19b2a793102dab3fd25f8415046249`;
the final Windows and Linux test bytes hash to
`db634ee64dec8ee00cf1aaacbd8d4d882365d4b09a09b0f8e48f906cce4743dd`.
The frozen parse/unit roster digests are respectively
`3fc5b1fa77533fb916bde7772ab5b2ec3100360bbcd3669d60f72ee5b5c632fb`
and `0237cf8841bf9afe50d7a5a369854d2d9e6bb3cd3a249fe39665acf267ddd374`.
Replacing only this test in a frozen Linux app copy gives parse/unit digests
`e4e386fa9ba47db7c4727bd447f344672fe2c526ec3d75ce397d1211b0223110`
and `6e121d8f564e49aaa7da37430354cd8703c1de908ea49680cce24e2f5df459d2`.
Those are computed overlay identities, not full-suite receipts for the revised
test; the frozen suite, visual and export sources were not edited.

The Windows and frozen Linux `mechanical_audio.gd` files have different raw
hashes because of CRLF/LF checkout encoding, with matching normalized content.
`mechanical_motion.gd` is byte-identical. The [verification record](verification.json)
binds these identities, checked reports, logs, JUnit summaries and control
drafts. Raw results remain under
`D:/OpenRCsimulator-experiments/gdu-beta2/mechanical-audio-test-final-r2/`.
These checks establish bounded release of the references observed in the
fixture, not every mixer object or production lifecycle.
