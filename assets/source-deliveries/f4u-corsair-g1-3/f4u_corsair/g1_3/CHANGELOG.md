# g1.3 — request Revision 3 — 2026-10-22

- Uniformly enlarged accepted g1.2 from 1:5 to 1:4.5 by applying 10/9 to data and translation keys; node scales remain one.
- Runtime GLB now exports GearRetract frame 100 with export_current_frame=True; editing source opens frame 0.
- Updated dimensional metadata, separated exported/up and editing/down node transforms, and recorded actual mesh contact vertices alongside nominal tyre contacts.
- Re-ran source/GLB verification, roundtrip, motion and clearance witnesses, negative checks, independent re-export, and all previews.
- Preserved g1.2 topology, UVs, names, hierarchy, materials, and every livery file.
- This is the delivery for the supplied Revision 3 letter, separate from the earlier paint-only g1.3.

# g1.2 — 2026-10-22

- Recovered six upper wing-fold hinge covers from R59.
- Closed the visible top-wing cutouts and restored paint continuity.
- Kept section tagging, neutral pose and 54 surfaces; 90,861 triangles.
- Rechecked GLB import and sampled control clearances.

# g1.1 — 2026-10-22

- Rounded door edges at 0.35 mm.
- Relieved right forward tailwheel door/fuselage contact throughout 21 sampled positions.
- Added interior door coating through the existing atlas, preserving 54 surfaces and 11 materials.
- Reduced paint gloss and redesigned Scarlet wing bands; softened three-tone transitions.
- Updated 2048² layered liveries, exports and previews.
- 88,761 triangles, still below the 100,000 target.

# g1 — 2026-10-22

- Derived a separate 1:5 game scene from byte-preserved R59.
- Selected three-blade propeller; documented retained hub and length differences.
- Consolidated 8,725 source object decisions in export-map.json; omitted studio, reference images, stores, superseded parts and internal mechanism detail.
- Reduced to 83,587 triangles, 54 surfaces and 11 materials.
- Added game pivots, section extras and rigid sampled GearRetract action.
- Corrected wheel rolling and tail steering axis directions.
- Relieved neutral flap contacts by 0.5–2 mm aft and up to 1.1 mm down in hinge-local space, without changing pivots or limiting throws.
- Retained control stick and stowed hook; added a simple original gunsight proxy.
- Created shared UVs and three original layered 2048² liveries.
- Verified clean re-export, GLB reimport, metadata transforms and negative verifier cases.
- Included orthographic, livery, articulation, gear and exploded previews, sampled-clearance and surface-deviation reports.
