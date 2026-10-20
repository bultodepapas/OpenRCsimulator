# Flight-test comparison

Baseline `tmp/ft-05-baseline-final`, candidate `tmp/ft-05-glow-final`; tolerance max(0.0, 0.0 × |baseline|).

Card ft-card-v5 → ft-card-v5; commit 890b94fcd7 → bd713963b6 (candidate dirty).

## Great Planes Extra 300S .60 — 0 change(s)

## Ugly Stick · MAX-55AX — 0 change(s)

## Ugly Stick · MAX-61FX — 0 change(s)

## Ugly Stick · FS-64V — 0 change(s)

**4 change(s) beyond tolerance.**

The four glow aircraft were flown again on the final code (after the carburettor root solver moved from bisection to safeguarded Newton and the glow fuel-transport seed settles to its fixed point) and compared with the retained FT-05 profiles at zero tolerance: every reported value is identical. The four other aircraft were not re-flown (their files are bit-identical with and without the NITRO-06 files, see the same-tree report).
