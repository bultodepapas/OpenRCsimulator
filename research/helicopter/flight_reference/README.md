# Helicopter flight-reference index

This folder is the locator for the source and software reference cases used by the rotorcraft implementation. Source documents are linked, not copied. Current equation notes and limitations live in [HELI-07 drive evidence](../../../docs/research/helicopter/HELI-07/README.md) and [HELI-08 coupling evidence](../../../docs/research/helicopter/HELI-08/README.md).

The primary low-order model source is Gavrilets, Mettler and Feron, [*Dynamic Model for a Miniature Aerobatic Helicopter*](https://users.encs.concordia.ca/~bwgordon/mit_heli_report.pdf). The project also keeps independent Python oracles for the aerodynamic components in [`research/helicopter/reference/`](../reference/); those files do not supply measured engine, shaft-axis, or full-aircraft flight data for the generated X-Cell trainer.

Reproducible runtime checks are in [`test_heli_coupling.gd`](../../../app/tests/test_heli_coupling.gd), [`test_heli_flight.gd`](../../../app/tests/test_heli_flight.gd), and [`test_heli_trim.gd`](../../../app/tests/test_heli_trim.gd). The last test loads the generated v2 profile through the production data reader and records its current hover reserve. That model result is software evidence, not physical flight-reference data.
