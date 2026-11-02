@google/model-viewer 4.4.0
Official source: https://github.com/google/model-viewer
Package: https://registry.npmjs.org/@google/model-viewer/-/model-viewer-4.4.0.tgz
License: Apache-2.0; see model-viewer-LICENSE.txt and bundled notices.
Package integrity: sha512-8z1SB5sPlzKoak5mdx/D31brBakPYm3Qi31EfAucHAUrtrHHCbabypkKvSwReYhUpPaxyJ46oT47uWE/hrs1Zw==
Unmodified dist/model-viewer.min.js SHA-256: 18b2e711035aa4705ee281530a55dc2338ff05eed3d70ae16d54105282a75ed5

The module is imported only when the visitor opens the 3D inspector.
GLBs use WebP textures without geometry compression; no remote decoder or
environment-image fetch is needed. The neutral environment is built in.
To update, review upstream changes, pin one exact version, verify package
integrity, copy the distribution and license, then run the website checks.

web-vitals 6.2.3
Official source: https://github.com/GoogleChrome/web-vitals
Package: https://registry.npmjs.org/web-vitals/-/web-vitals-6.2.3.tgz
License: Apache-2.0; see web-vitals-LICENSE.txt.
Package tarball SHA-256: 0345c05eceae57e921485b0696ab979ef559f3c3dda56abad6ad8145e399a262
Vendored dist/web-vitals.attribution.js SHA-256: a6cf8ad44934b04bd359ecc1f2602ec8f1c4582127f68cad1764548a2b93ec98
The only distribution change is removal of its sourcemap footer; the map is
not shipped. vitals.js loads this module on sampled public visits only.
