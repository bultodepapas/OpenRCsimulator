EXTRA 300 CHARACTER RESEARCH PACK
2026-11-06

Read CHARACTER_RESEARCH.txt first. sources.json records primary URLs and source limitations. flight_cards.json contains proposed experiment specifications, not a directly executable simulator configuration.

calculate_extra.py and its JSON result are reproducible algebra from the pinned aircraft data. They do not run Godot or validate real-aircraft performance. Run the script with --help for its actual interface.

Baseline:
bultodepapas/OpenRCsimulator
8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd

Scope:
Great Planes GPMA0236 Extra 300S .60 kit. Later named RC Extra designs are comparison cases, not coefficient donors.

The report was cross-checked against the consolidated external audits and existing EX-14 research. Previously reported physics limitations remain prior work. No production source edits, remote repository writes, new simulator flights or physical flight tests are claimed.

This pack contains original interpretation, source links and experiment design. Original third-party manuals, magazine scans and forum captures are not included.


Reproduce from a checkout of the pinned commit:
python3 calculate_extra.py --source-root /absolute/path/to/OpenRCsimulator --out recomputed.json

The result embeds hashes of every source input. Reproduction requires the source checkout; copyrighted third-party references are not needed to run the arithmetic.
