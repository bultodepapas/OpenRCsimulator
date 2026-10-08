# Blender aircraft delivery letter

2026-10-08 · Revision 1 · **Status: draft for the model developer; not sent.**

**To:** Aircraft modeling developer  
**Subject:** Preparing the Turbo Timber Evolution and future aircraft for OpenRC Simulator

Hello,

We are preparing the Turbo Timber Evolution for OpenRC Simulator, our Godot RC flight simulator. Your delivery includes geometry, separate control surfaces, hinge information and landing-gear construction details that we can use directly in the integration work.

For the next delivery, please provide an editable master and a lightweight export with a documented coordinate system and moving-part hierarchy. Our immediate goal is to import the aircraft at the correct size, articulate it reliably and repeat that process when you revise it. We will handle flight physics and the Godot adapter on the simulator side.

The requests below apply to the Timber and establish a proposed handoff convention for future aircraft. We should prove the convention on one small export before you spend time preparing every detail.

## Priorities for the Timber

These observations come from the supplied v12 files and a static inspection of their stored data. We have not yet evaluated the Blender scene or completed an export round-trip.

| Priority | What we found | What we need from you |
| --- | --- | --- |
| Confirm the aircraft | The package does not explicitly identify the hardware revision, battery or optional equipment represented. | State the intended revision and configuration: motor, propeller, battery, wheels/floats, slats and flap state. Mark uncertain items. |
| Reconcile dimensions | Combined STL bounds give approximately 1,548 mm span and 1,116 mm length. The manufacturer reference gives 1,555 mm and 1,040 mm. | Identify the endpoints and configuration used for each measurement. Explain the discrepancy before changing scale; a uniform length correction would also change span. |
| Explain the frames | CAD/sidecar coordinates appear to be millimetres, while Blender translations are already metre-sized. Gear code and sidecar wheel positions also suggest a longitudinal datum shift. | Document the units, axes, origin and conversion for each representation. Include a few corresponding landmarks to verify the conversion. |
| Separate presentation from aircraft pose | The stored aircraft root is raised and pitched, consistent with a ground presentation. | Supply an export in a documented neutral body pose, with presentation positioning kept outside the aircraft hierarchy. Preserve real incidence, dihedral and thrust angles. |
| Separate fixed and rotating motor parts | `Eje_motor` parents both the propeller and fixed mounting hardware. | Give the rotating assembly its own pivot under the fixed shaft frame. The motor mount must remain stationary when the propeller turns. |
| Reduce small-part complexity | The two spring STLs contain 765,356 triangles, about 67.5% of the complete STL triangle count. | Keep the detailed originals and simplify springs, supports and small hardware in the export. Preserve wing/tail outlines and control-surface geometry first. |
| Complete the handoff | Some CAD audit inputs and the full aircraft generator are absent. The sidecar's surface-member lists are less complete than Blender's parent hierarchy. | Include available generators, their required inputs and version information; list anything unavailable. Reconcile moving-part membership, including horns and markings. |

Please also identify whether full slats and floats exist in the source. We found slat-support names, but names alone do not establish which optional geometry is present. Their absence does not block the first wheels-only export.

## Coordinates and a stable aircraft origin

You can keep your preferred Blender authoring axes. What matters is that the conversion is explicit and applied exactly once. The simulator's aircraft model convention is **metres, +X right, +Y up, nose toward −Z**. “Left” and “right” always mean the pilot's view looking forward from inside the aircraft.

Choose a fixed geometric datum and describe it precisely. Record wing-root leading edge and thrust-axis anchors relative to it. Keep the center of gravity as separate data: moving the battery should not require moving every mesh origin.

For each delivery, include positions for both wingtips, a nose reference, a tail reference and the main wheel centers in the declared frame. These asymmetric landmarks let us catch incorrect scaling, mirroring and axis conversion quickly. State whether dimensions describe the CAD, the exported mesh, a manual specification or an actual measurement.

Keep the export root free of staging offsets and unwanted scale. Preserve each hinge's local rest orientation and document it. Applying transforms indiscriminately after rigging can change the meaning of those axes; use a prepared export copy and verify its neutral pose afterward.

## Moving parts and their pivots

We need independently movable surfaces with stable names and pivots on their actual rotation axes. Please provide this information for each articulation:

- A stable identifier, parent and complete list of moving objects.
- Pivot position, normalized axis direction and the coordinate frame in which both are expressed.
- Neutral/rest orientation, positive rotation direction and permitted angle range, with angle units stated.
- The source of the range: measured hardware, manual-derived travel or an authored approximation.

Suggested semantic names are `aileron_left_hinge`, `aileron_right_hinge`, `elevator_hinge`, `rudder_hinge`, `flap_left_hinge` and `flap_right_hinge`. Existing source names can stay if you supply a mapping. For split elevators or multiple rudders, retain separate pivots and identify which pilot control drives them.

A horn, paint strip or other attached detail must follow its moving surface. Preserve tilted and swept hinge axes. Supply a simple demonstration of neutral, positive and negative deflection so we can verify direction without guessing from Euler angles.

For the propeller, separate the fixed shaft orientation from rotor spin. Identify rotating blades, spinner and other rotating hardware explicitly. For wheels, separate axle rotation from steering and suspension movement. For retractable gear on future models, describe the mechanism and end positions separately from wheel spin.

Keep useful drivers and constraints in the editable master. Describe their purpose and inputs; we will implement the necessary live relationships in Godot. An exported animation is useful as a reference demonstration, but should not be the only description of how a control surface moves.

## Geometry and materials for the simulator

Maintain a detailed source and a curated export collection. Export only the aircraft and required pivots. Keep studio lights, cameras, ground, reflectors, measurement helpers and CG markers outside that collection.

Merge fixed pieces when they share material and motion; keep moving parts separate. Prioritize silhouette, underside/topside distinction and readable markings from the ground. Tiny screws, hidden electronics and densely tessellated springs can remain in the master without appearing in the flight export.

For the Timber's first optimized export, the proposed starting targets are **100,000 visible triangles and 40 mesh surfaces**. These are provisional planning targets, not measured hardware limits or universal requirements for every aircraft. Send counts and note any justified exception; we will measure the actual rendering cost in Godot before tightening budgets. LOD variants can follow once the first model imports correctly.

Check for zero-area faces, unintended duplicate/internal surfaces, reversed normals, shading seams and flickering coplanar markings. Closed solid geometry is useful for CAD analysis, but visual meshes do not all need to be watertight. Keep intentional thin surfaces explicit.

Use materials that survive the agreed GLB export. Include any required textures with relative paths or inside the GLB, and document texture color spaces and channel packing when used. Bake appearance that depends on unsupported procedural shading into the export representation while retaining the editable setup. Keep transparent glass limited to the parts that need it, and provide a plain-lit preview so appearance can be checked without the studio lighting.

## Geometric evidence and physical information

Please preserve the measurements and references used to construct the model. Useful handoff data includes wing/tail dimensions, incidence and dihedral, hinge lines, wheel radii/centers, ground contact locations, shaft position/direction and propeller dimensions. State measurement endpoints and configuration, especially for optional slats, flaps and floats.

For any number you provide, record **value, unit, evidence type and source**. Suitable evidence labels are `manual`, `measured`, `borrowed`, `estimated` and `derived`. Add a practical uncertainty or range when known. Unknown information should remain unknown rather than becoming an unexplained default.

If available, include component masses and positions, battery travel and the intended flight mass. A partial component inventory must be labeled partial. CAD volume alone is insufficient to infer the mass distribution of a foam airframe, hollow parts and installed equipment. We will derive and validate simulation mass/inertia and aerodynamic data separately.

Control travel needs a defined measurement point. If a manual gives millimetres of trailing-edge displacement, preserve that specification alongside any derived angle. Likewise, a modeled spring gives us its shape and attachments; stiffness and damping require their own evidence. You do not need to invent aerodynamic coefficients or build a flight simulator to deliver a useful model.

## Delivery package and revision discipline

Please use one versioned package with this suggested layout. Equivalent organization is fine if the README maps it clearly.

```text
aircraft-id/revision/
  README.md                 # identity, configuration, units, tools, known limits
  source/aircraft.blend      # editable master
  source/                   # available CAD, generators and required inputs
  export/aircraft.glb        # curated neutral aircraft
  metadata.json             # frames, anchors, articulations and evidence
  export-map.json           # source names to exported roles and exclusions
  textures/                 # only when external dependencies are needed
  previews/                 # neutral views and representative articulated poses
  CHANGELOG.md              # changes since the previous delivery
  LICENSE.txt               # authorship and redistribution terms
```

The metadata filenames describe a proposed exchange format, not an existing simulator API. We can agree the smallest useful schema after inspecting the first sample; a clearly labeled table is sufficient to resolve the initial frame and hinge questions.

Record the exact Blender version, required add-ons, export settings and export command/script if available. Include the inputs needed by any generator you expect us to rerun. Keep filenames portable, paths relative and object identifiers stable. List renamed/deleted parts and changes to scale, origin, pivots, materials or configuration in the changelog. Deliver a new revision instead of replacing files under the same version name; our intake will record file hashes.

Identify who created the model and the terms under which its geometry, textures and any third-party content may be redistributed with the simulator. Reference images can remain external when they cannot be redistributed; retain their source and explain what they support.

## First delivery and acceptance

Please start with the neutral aircraft export, the four primary flight controls, the propeller pivot and a short frame/landmark table. Include flap and wheel pivots when available, without making advanced suspension or linkage animation a prerequisite. This small sample will let us settle naming, scale and articulation before further finishing work.

Before handing it over, reimport the GLB into a clean Blender scene and compare dimensions, materials, hierarchy and neutral pose. Supply front, side, top, underside and three-quarter views, plus representative control extremes. Note visible discrepancies or unsupported effects.

We will then check the asset in the pinned Godot build, verify transformed landmarks and control directions, and measure its rendering cost. We will send back concrete import findings before requesting additional detail. Flight physics, input integration, sound and independent handling validation remain the simulator team's responsibility.

The outcome we want is a reusable aircraft asset whose dimensions, movable parts and evidence remain understandable after export and across revisions.

Thank you,

OpenRC Simulator integration team

---

Project references: [Timber integration plan](TIMBER-INTEGRATION-PLAN.md), [v12 audit and measurements](research/timber-integration/TT-00/README.md), [manufacturer and import references](research/timber-integration/TT-00/sources.md). The letter is self-contained; these links provide supporting detail for repository readers.
