# MoonRunner model and customization overlay

This separately versioned authoring input adds the MoonRunner visual family without
changing the legacy shared registry or its family hashes. The source geometry,
model, rig, textures and licensing provenance remain those of the retained r4
delivery; the overlay does not claim a new asset or change node names.

Generate and check in order:

```
python research/aircraft-standardization/build_overlay_proof.py
python research/aircraft-standardization/build_models.py --overlay-only
python research/aircraft-standardization/build_customization.py --overlay-only
python research/aircraft-standardization/build_overlay_proof.py --check
python research/aircraft-standardization/build_models.py --check --overlay-only
python research/aircraft-standardization/build_customization.py --check --overlay-only
```

The model output is `app/data/aircraft_model_overlays/moonrunner-x99.json`. The
customization output is a one-family `openrc-aircraft-customization-registry v1`
at `app/data/aircraft_customization_overlays/moonrunner-x99.json`. The ordinary
generator checks also check their respective overlays. Unknown files in either
overlay output directory are errors.

The explicit overlay resolvers validate the model, companion, exact family ID,
closed source set, and collision checks on each lookup. The export plugin includes
both legacy and overlay sources in the model proof package. As with existing model
proofs, these identify the exporter inputs; they do not independently verify the
compiled bytecode. The active aircraft catalog has not yet switched to this ID.
Legacy family bindings remain available for historical Workshop records and skins;
matching names are not a substitute for matching pinned identities.
