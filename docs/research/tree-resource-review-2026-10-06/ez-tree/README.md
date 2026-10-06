# ez-tree 1.1.0 offline generation trial

The browser generator works offline after package installation and produces organic-looking trees. The three upstream Large presets generate 19,392–22,566 indexed triangles each, so they are not close to the proposed 1,000-triangle budget as shipped. This is a source-generation result only; no decimation or production LOD was validated.

The per-preset vertex counts, bounds, branch/leaf triangle counts, package provenance, and browser version are in [metrics.json](metrics.json). The runner in [runner/](runner/) remeasures geometry in the browser and writes only `metrics.json`. It intentionally does not export or retain PNG/GLB files while the exact v1.1.0 leaf-image license remains unclear.

## Reproduce

The npm lock resolves `@dgreenheck/ez-tree@1.1.0` directly from the npm registry and pins Three.js 0.167.1 and Vite 5.4.21. From `runner/`, run `npm ci --no-audit --no-fund`, then provide a Playwright Core package path, a compatible Chromium executable, and an output directory:

```sh
PLAYWRIGHT_CORE_PATH=/absolute/path/to/playwright-core \
CHROMIUM_PATH=/absolute/path/to/chrome \
OUT_DIR=/tmp/ez-tree-metrics \
npm run measure
```

`OUT_DIR` is required and receives `metrics.json`. `PLAYWRIGHT_CORE_PATH` may be the Playwright Core package directory or its module entry. The script starts Vite on a local ephemeral port and launches the supplied Chromium binary in headless mode; it does not download a browser.

The package tarball SHA-256 is `4147b49d22b01f09c9d7f3c3c34f788ad37841103a758da25e399af3cbce2f98`, with registry integrity `sha512-6pvS6hD6B6h00dm0SnkgYeT4ABU5Y1Z9M44p1tXiV5C0eKrQy2sKECXshoaUv0qAOqYVL68w/PwadUxDFDiHUg==`. To download and check it independently:

```sh
mkdir -p /tmp/ez-tree-package
npm pack @dgreenheck/ez-tree@1.1.0 --pack-destination /tmp/ez-tree-package
sha256sum /tmp/ez-tree-package/dgreenheck-ez-tree-1.1.0.tgz
```

The recorded browser test ran in this container with the paths used by the original trial passed through the runner's environment: Playwright Core 1.62.1 from `/home/bulto/.npm/_npx/e41f203b7505f1fb/node_modules/playwright-core` and Chromium 153.0.8010.12 from `/home/bulto/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome`. The checked-in runner was exercised with those same paths and reproduced the counts in `metrics.json`; running it on a different host or with different path layouts has not been verified.

## License and asset provenance

The npm metadata and package root license identify ez-tree as MIT-licensed. The exact v1.1.0 archive contains `src/lib/assets/leaves/{ash,aspen,oak,pine}_color.png`, but neither the archive nor its matching source tag provides separate provenance or a per-image license for those four files. Their individual SHA-256 hashes are recorded in `metrics.json`. A later upstream commit says its demo app leaf images use the project license, but those later image bytes differ from the v1.1.0 archive. That later note therefore does not verify the exact v1.1.0 leaves; their file-level license status remains unresolved.

The v1.1.0 package's bark asset README maps Birch and Pine bark to TextureCan and Oak and Willow bark to Poly Haven. Both providers' official license pages state their textures are CC0. The ez-tree package does not hash-link each bundled bark image to a particular upstream download revision.

Primary sources:

- [npm package metadata for v1.1.0](https://www.npmjs.com/package/@dgreenheck/ez-tree/v/1.1.0)
- [Matching upstream source tag and MIT license](https://github.com/dgreenheck/ez-tree/tree/v1.1.0)
- [Upstream bark texture source note](https://github.com/dgreenheck/ez-tree/blob/v1.1.0/src/lib/assets/bark/README.md)
- [TextureCan terms: CC0 1.0](https://www.texturecan.com/terms/)
- [Poly Haven asset license: CC0](https://polyhaven.com/license)
- [Later upstream leaf-texture attribution note; not the exact v1.1.0 images](https://github.com/dgreenheck/ez-tree/blob/48dc193515135cff2b33515c47f0a8703b977e63/src/app/public/textures/LICENSE.md)
