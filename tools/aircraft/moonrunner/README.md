# MoonRunner X99 visual derivative

This pipeline creates a separate Abisal GLB with the wing and small technical
stencils changed to MoonRunner X99. It reads the original r4 delivery and the
legacy stock GLB, and does not alter either. Stock registration and legacy
`.orskin` compatibility are handled separately; preserve the original assets and
verify that compatibility when changing those bindings.

The original 4096 paint inputs were not included in the delivery. The pipeline
re-bakes the delivered geometry maps, runs the original procedural painter for
original, blank-stencil and new-stencil versions, and derives a mask from those
three results. It applies the paint delta only inside that mask to a losslessly
decoded copy of the shipped atlas. It uses the delivered Blender exporter and
checks all node, mesh, accessor, material and geometry-buffer data against the
shipped model; the non-base images must be byte-identical. The output is a new
PNG base image embedded in a separate GLB.

## Reproduce

The recorded output is pinned to Linux x86-64, Blender 5.2.2 LTS, its NumPy
2.3.4, the dependency wheels in [requirements-linux-cp313.txt](requirements-linux-cp313.txt),
and the DejaVu Bold and Mono Bold fonts checked in `blender_phase.py`.
The condensed font must be absent so the original painter takes its fallback.
Other platforms or font versions must not silently produce a replacement. Allow
at least 10 GiB for Blender and monitor system headroom; the full 4096 bake
and paint passes are resource intensive. These steps need a private Blender Lab
bridge; see [the Blender tool guide](../../blender/README.md).

Run these commands from the repository root in a Linux shell. The work directory
must be scratch, outside `app/` and the immutable delivery, and must be visible
to both the client and Blender. Use a fresh directory; phases refuse to
replace prior outputs.

```sh
export MOON_REPO="$PWD"
export MOON_WORK="$PWD/tmp/moonrunner-visual-build"
export MOON_DEPS="$MOON_WORK/python"
mkdir "$MOON_WORK"
tools/blender/mcp-setup.sh
.tools/blender-5.2.2-linux-x64/5.2/python/bin/python3.13 -m pip install \
  --no-deps --require-hashes --only-binary=:all: --target "$MOON_DEPS" \
  -r tools/aircraft/moonrunner/requirements-linux-cp313.txt
cp assets/source-deliveries/skywalker-x8-r4/skywalker_x8/r4/source/aircraft_game.blend \
  "$MOON_WORK/source.blend"
```

Start `tools/blender/mcp-bridge.sh "$MOON_WORK/source.blend"` in a separate
terminal and wait for the server-ready message. For each phase below, run the
command in the original terminal, stop the bridge, then start a fresh bridge
on the same scratch copy. This releases the large paint arrays and ensures the
export starts from an unmodified scene. The client uses the project's pinned
MCP environment.

```sh
.tools/blender-mcp/venv/bin/python tools/aircraft/moonrunner/lab.py bake \
  --repo "$MOON_REPO" --work "$MOON_WORK" --deps "$MOON_DEPS"
```

Repeat that command with `baseline`, `blank`, `candidate`, `compose`, then
`export` in place of `bake`, restarting the bridge before each phase.

The `bake` phase can exceed the official bridge's five-minute request timeout.
The client waits for a Blender-written success or failure marker; a timeout by
itself is not success. If the map hashes differ, the build stops. The work
folder retains the maps, three paints, `mask-evidence.json`, and
`export-evidence.json` for inspection. The pipeline does not create renders.

After `export` succeeds and its evidence is reviewed, install the separately
named output. This refuses to overwrite an existing file and verifies the
original and derived hashes before copying.

```sh
.tools/blender-mcp/venv/bin/python tools/aircraft/moonrunner/lab.py install \
  --repo "$MOON_REPO" --work "$MOON_WORK" --deps "$MOON_DEPS"
```

Output: `app/assets/aircraft/moonrunner-x99/moonrunner_x99.glb`, SHA-256
`54d67d9bbfe4ce4abdc4bafa523c3bf812422d6336ba1d0f151a2970e087b0f0`.
The existing stock GLB is SHA-256
`3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac`.

The 1080p BÓLIDO top view and its delivered painter show the livery names
BÓLIDO and VR-08; no X8 stencil was identified. Its separately named file is an exact copy, without repainting
or re-exporting. Install it independently with:

```sh
.tools/blender-mcp/venv/bin/python tools/aircraft/moonrunner/lab.py install-bolido \
  --repo "$MOON_REPO"
```

The original and copy both have SHA-256
`9ecaf7b49aec555bbea178b3b582378bb362bec3f816448932438db2c8da8f93`;
the copy is `app/assets/aircraft/moonrunner-x99/moonrunner_x99_bolido.glb`.
Both install commands create the new file atomically and refuse to overwrite an
existing destination. They leave the historical files untouched.

The Abisal mask contains 42,711 of 4,194,304 atlas pixels; there are zero changed
pixels outside it. The rebuilt baseline JPEG is very close but not byte-identical
to the shipped JPEG, so the full regenerated atlas is not substituted.

The scratch 1920×1080 top view confirms the wing lettering. The small
fuselage marking is too small and obscured in the inspection views to establish
its legibility or appearance in the running app.
