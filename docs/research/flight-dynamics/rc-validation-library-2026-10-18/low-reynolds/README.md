# Low-Reynolds-number, stall and control-surface evidence

Research snapshot: 2026-10-18 (Bogotá); retrieval timestamps in the [manifest](sources.json) use UTC. Part of the [RC validation library](../README.md), supporting the existing VAL-/DATA- physics research. This is a source collection, not an adopted aerodynamic model.

Originals are local-only under `references/rc-validation-library-2026-10-18/low-reynolds/`. The manifest records the exact URL, repository-relative path, hash, access outcome, relevance and limits. An already present Vahora 2018 PDF is reused from `references/rc-aero-data/`.

## Measured polars and downloadable tables

The [UIUC LSAT laboratory](https://m-selig.ae.illinois.edu/uiuc_lsat.html) publishes the five *Summary of Low-Speed Airfoil Data* volumes, the Williamson large-flap thesis, and *Airfoils at Low Speeds* (SoarTech 8). All seven reports/books and their seven data ZIPs were obtained. The [data page](https://m-selig.ae.illinois.edu/pd.html) distinguishes the later corrected Volumes 1–2 tables from earlier reductions. Use the retained ZIP version with its accompanying report and notices.

| Local collection | Potential comparison | Boundary |
| --- | --- | --- |
| Volumes 1–5 and ASCII ZIPs | Section lift/drag, Reynolds dependence, stall and, where available, pitching moment | Match the exact airfoil and run; moment channels differ between volumes |
| Williamson thesis and `volume06` ZIP | Large flap deflections, pitching moment, nonlinear control effectiveness | Section flap data do not measure a complete elevon/aircraft response |
| SoarTech 8 and `Stec8` ZIP | Independent Princeton low-Re section polars | Separate facility and reduction history |
| Ananda/Sukumar/Selig 2012 and 2015 | Finite-wing lift, drag, aspect/taper ratio, aerodynamic center | Three-dimensional wings; do not substitute section coefficients |
| Mizoguchi/Kajikawa/Itoh 2016 | Stall hysteresis versus aspect ratio | Thin rectangular wings, AR 0.5–1.5, Re 52,000 |

Representative archived tables were inspected without extraction: Volume 1 `DRAG01.TXT` contains concatenated airfoil runs; Volume 4 `e387_c_drg.txt` identifies the airfoil, surface condition, measured Reynolds number and drag columns; Williamson `ag40d_f0_drag.dat` also identifies flap setting. Preserve these headers when importing data; filenames alone omit test conditions.

The [2015 finite-wing paper](https://m-selig.ae.illinois.edu/pubs/AnandaSukumarSelig-2015-AeroSciTech-LowReWings.pdf) reports ten wings, AR 2–5 and Re 50,000–150,000, with measured span efficiencies around 0.3–0.8. Its flat-plate tests showed no angle-of-attack hysteresis; the [2012 study](https://m-selig.ae.illinois.edu/pubs/AnandaSukumarSelig-2012-AIAA-2012-3026.pdf) includes a different profiled-wing case near a critical Reynolds number. These are distinct experiments, not a universal hysteresis rule. The [Mizoguchi paper](https://www.jstage.jst.go.jp/article/tjsass/59/2/59_T-15-28/_article) provides another measured geometry-dependent case.

## Post-stall, autorotation and memory

- [Ragheb and Selig 2016](https://m-selig.ae.illinois.edu/pubs/RaghebSelig-2016-AIAA-Paper-2016-1073-StalledSpinningWingTunnelTests.pdf): measured spinning-wing loads at pitch angles 30°, 60° and 90°, AR 1–10, Re 3,000–25,000. Useful for checking dependence on nondimensional spin rate and wing geometry. The Reynolds range is much lower than typical Stik flight, and the test is wing-only.
- [Ragheb and Selig 2015](https://m-selig.ae.illinois.edu/pubs/RaghebSelig-2015-AIAA-2015-0548.pdf): a force-prediction methodology for spinning stalled wings. Keep its model predictions distinct from the 2016 tunnel measurements.
- [Ananda and Selig 2016](https://m-selig.ae.illinois.edu/pubs/AnandaSelig-2016-AIAA-Paper-2016-3541-GA-PostStallModeling.pdf): longitudinal stall/post-stall modeling of a GA aircraft; useful for comparing model structure, without treating that aircraft's law as Stik data.
- [Le Fouest, Deparday and Mulleners 2021](https://arxiv.org/abs/2102.04485): measured force transients and stall-delay dependence on pitch history. The journal copy prints Re 750,000, water speed 0.50 m/s and chord 0.15 m in section 2. Check that Reynolds value against the dimensional setup before using it for similarity; it is retained as printed, not independently established. This is a mechanism/time-scale comparator, not exact RC calibration.
- [NASA TP-1100](https://ntrs.nasa.gov/citations/19780009057): NACA0012 dynamic-stall pressure/load evidence at Re 2.5 million. Retained for experimental methodology and qualitative mechanisms; its Reynolds number limits direct RC transfer.
- [Boutet et al. dataset](https://data.mendeley.com/datasets/y5wt7htxdp/1), DOI `10.17632/y5wt7htxdp.1`: repository describes oscillating flat-plate/NACA0012/NACA0018 force and moment series. Only [DOI metadata](https://api.datacite.org/dois/10.17632/y5wt7htxdp.1) was downloaded; the data host returned HTTP 403. The local JSON is metadata, not measurements.
- [Sarlak et al. 2018](https://www.mdpi.com/1996-1073/11/6/1418): an identified S826 hysteresis/turbulence study. The PDF request returned HTTP 403; it remains a source lead, not a downloaded paper.

## Surface state, scaling and flight experiments

The manifest additionally indexes the Selig 2003 design lectures; Selig/Deters/Williamson 2011 tunnel methodology; McGranahan/Selig 2003 oil-flow measurements; Gopalarathnam et al. 2003 and Lyon et al. 1997 trip studies; S1223 high-lift design; spanwise profile-drag variation; and the 1996 airfoil experiments. These help interpret transition, roughness and measurement uncertainty before tuning a polar.

Vahora et al. 2018, Ananda et al. 2017 and Dantsker et al. 2017 cover aerodynamic/dynamic scaling and the GA-USTAR platform. Uhlig et al. 2010, Uhlig/Selig 2011 and Rao/Uhlig/Selig 2012 add motion-tracked MAV flight experiments. The [Rao paper](https://m-selig.ae.illinois.edu/pubs/RaoUhligSelig-2012-AIAA-2012-2768.pdf) identifies small foam Extra models, approximately 0.42 m span, tested near Re 25,000; they are distinct from the repository's much larger Extra and Stik.

## Search and inspection scope

Representative queries: `low Reynolds number dynamic stall NACA 0012 experimental`, `low Reynolds wing stall hysteresis experimental pdf`, `UIUC low speed airfoil data summary volumes`, `model aircraft spin thesis`, and `dynamic stall experimental dataset`. Discovery used laboratory publication indexes, J-STAGE, NASA NTRS, institutional repositories and DOI metadata. Search-engine dates were not treated as publication dates.

Each retained PDF passed magic-byte and `pdftotext` parsing checks; ZIPs passed CRC checks without extraction. Read depth is source/abstract/first-page inspection with selected experimental setup checks, not a full scientific reproduction or coefficient audit. Sources remain separate from accepted aircraft data. UIUC data notices are retained locally; public accessibility alone does not establish permission to redistribute books or papers.
