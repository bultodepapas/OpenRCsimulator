# AFC-20-R1 presentation context

The crash director now receives a typed presentation context assembled by Main. It carries the active session, model bindings, field and aircraft/trial data, CG, the existing interpolated pose and wind providers, and optional shadow, sun, and propeller-blur references. Invalid or repeated configuration is declined before allocating presentation children; reset ownership stays attached to the configured session.

The corrected isolated suite passed 385 checks across eight test groups with no engine errors. A separate run against the current C working tree passed the water-director fixture at 22/0. Existing vegetation/material warnings and the soft-contact camera warning are recorded in [verification.json](verification.json), along with two earlier setup failures caused by the external authoring tree being placed at the wrong path. All 24 current-root authoring JSON files were copied to the expected sibling assets tree and hash-matched; all 13 authoring paths referenced by the aircraft model manifests also match.

The isolated mirror's runtime asset tree differs from the current working tree in one generated `.gd.uid` sidecar; the discrepancy is recorded in the asset snapshot. The additional current-working-tree run confirms the Main water-director path with its actual transitive files.

This increment does not attach directors to companion agents and makes no physics, performance, or physical-flight claim. The checked crash-integration run uses Dummy audio and records native playback as skipped.
