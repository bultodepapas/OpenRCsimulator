# Small-propeller and slipstream measurements

Research snapshot: 2026-10-18 (Bogotá); see UTC timestamps and exact files in [sources.json](sources.json). Part of the [RC validation library](../README.md), supporting existing VAL-/DATA- and propulsion research. Originals are local-only under `references/rc-validation-library-2026-10-18/propulsion/`.

## Complete experimental database

The [UIUC Propeller Database](https://m-selig.ae.illinois.edu/props/propDB.html) contains static and advancing-flow wind-tunnel measurements for model-aircraft and UAV propellers. The complete Volumes 1–4 ZIP was downloaded: 90,906,721 bytes, 3,673 archive members including documentation and plots. Its MD5 `a41e484f1fd0fb6ff80b76e27410808b` matches the published value; ZIP CRCs also passed. This is one archive, not 3,673 independent experiments. SHA-256 is recorded in the manifest.

Use each original run's definitions for advance ratio, thrust/power coefficients, RPM and Reynolds number. The laboratory defines the reported static Reynolds number using chord and rotation speed at the 75% blade station. Comparing engine throttle alone is insufficient.

Inspection found **1,994 `.txt` members under the four volumes' `data/` directories** (1,116 / 414 / 319 / 145). Representative advancing-flow rows contain `J`, `CT`, `CP` and efficiency; static and geometry files have their own layouts. This counts files/runs, not distinct propeller designs, and the archive remains intact.

## Companion papers

| Paper | Why retain it |
| --- | --- |
| [Brandt/Selig 2011](https://m-selig.ae.illinois.edu/pubs/BrandtSelig-2011-AIAA-2011-1255-LRN-Propellers.pdf) | Test setup and low-Re propeller performance curves |
| [Deters/Ananda/Selig 2014](https://m-selig.ae.illinois.edu/pubs/DetersAnandaSelig-2014-AIAA-2014-2151.pdf) | Reynolds-number dependence of small propellers |
| [Dantsker et al. 2020](https://m-selig.ae.illinois.edu/pubs/DantskerCaccamoDetersSelig-2020-AIAA-Paper-2020-2762-CamPropsTesting.pdf) | Aero-Naut folding-propeller measurements, Volume 3 companion |
| [Dantsker et al. 2022](https://m-selig.ae.illinois.edu/pubs/DantskerCaccamoDetersSelig-2022-AIAA-Paper-2022-4020-APCEPropTestsVol4.pdf) | APC electric fixed-blade measurements, Volume 4 companion |
| [Deters/Ananda/Selig 2015](https://m-selig.ae.illinois.edu/pubs/DetersAnandaSelig-2015-AIAA-2015-2265-LRN-PropSlipstream.pdf) | Measured wake velocities for slipstream shape and decay |
| [Ananda/Deters/Selig 2013](https://m-selig.ae.illinois.edu/pubs/AnandaDetersSelig-2013-AIAA-2013-3193-PropSlipstream.pdf) and [2014](https://m-selig.ae.illinois.edu/pubs/AnandaDetersSelig-2014-AIAA-2014-2152.pdf) | Wing-force changes with propeller flow and planform |
| [Uhlig/Selig 2008](https://m-selig.ae.illinois.edu/pubs/UhligSelig-2008-AIAA-2008-407-PostStallProps.pdf) | Blade-stall effects on propeller performance |

The 2020 PDF identifies paper **2020-2762**. The propeller landing page lists **2020-2760** in one citation; the manifest follows the PDF and laboratory publication index. No silent renaming to the conflicting citation was made.

## Comparison limits and search scope

Match diameter, pitch, blade geometry, RPM, advance ratio and Reynolds number before comparing thrust/power curves. These sources do not establish an exact O.S. glow-engine torque curve, installed fuselage/propeller drag or complete wing/tail propwash field. Predictions and measured curves within a paper need separate treatment.

Queries included `UIUC propeller data experimental wind tunnel small UAV`, `post stall propeller behavior low Reynolds`, and `propeller induced flow wing planform measurements`. Discovery followed the laboratory [publication index](https://m-selig.ae.illinois.edu/publications.html) to the original papers. The retained landing-page HTML preserves the download context. PDFs passed magic-byte and text parsing checks; inspection covered source records and first-page abstracts, not a full aerodynamic reanalysis. Permission to redistribute is not inferred from availability.
