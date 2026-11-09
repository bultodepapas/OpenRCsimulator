# Electric Stik presentation

This separate visual family builds the existing Jensen airframe per instance from
the unchanged `ugly_stik_*` geometry, finish, surface linkages and gear. Its
small generic outrunner and mount are visual estimates; their shape and fit have
not been measured against the selected motor. The electric builder does not add
the glow engine, tank, exhaust or throttle linkage. It keeps the public
`airplane`, `propeller` and control-hinge names.

The blade mesh uses the donor's authored diameter; the presentation adapter
scales it from the accepted electric propulsion diameter. The selected APC
12x8E is 0.3048 m in diameter. The profile is a visual stand-in, not a measured
APC blade or a structural failure model. Workshop paint and the independently
requested wingtip/tail smoke slots are retained. Electric has no combustion
source or exhaust smoke pump. Film-lighting skin masks are not registered for
this family; the ordinary light anchors remain available.

The model and customization bindings here feed the separately registered,
closed overlays. After changing their inputs, run in order from the repository
root: `python research/aircraft-standardization/build_overlay_proof.py`,
`python research/aircraft-standardization/build_models.py`,
`python research/aircraft-standardization/build_customization.py`, then
`python research/aircraft-editor/build_descriptors.py`. Check each with
`--check`. Source hashes prove the declared inputs, not physical fit or
rendered appearance.
