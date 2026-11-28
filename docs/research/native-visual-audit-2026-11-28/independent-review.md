# Independent review of the native visual audit

The baseline is `71306784a250d634854f0c8bab3a927cc46a61b8`. The final captured production source is `1e91cb28eaed0079837e9a49d9e0b5a90253ee3e`. I reviewed the nine specialist submissions against the production routes and primary sources, checked the shader implementations, and independently reconstructed the image and timing measurements. The ledger records the exact source hashes at initial integration and final capture. [Verification ledger](verification-ledger.json)

**Disposition.** Seventeen of 24 entries were validated in their stated scope. Two entries corroborate the same defect and one describes measurement limits. This gives 14 unique validated source defects or opportunities. Ten were implemented and four remain deferred. Six further entries describe conditional artistic/technical opportunities. The claim that software rendering establishes physical GPU performance was rejected. A source-level disposition is distinct from visual and hardware acceptance.

## Independent findings review

All nine specialist reports were inspected. The JSON ledger identifies the source claim, disposition, severity and missing evidence for every candidate, includes separate dispositions for two corroborating duplicates, and records conditional ideas and the rejected extrapolation from software rendering to shipping hardware. Severity concerns the demonstrated code in its actual product route. No distant pixel or pilot-visible severity is assigned from an isolated equation.

| Production area | Disposition on the proposed work |
| --- | --- |
| Club lake | N1/W1 validated. The existing shader feeds camera-axis distance to Beer absorption. L2/W2, double lighting of the transmitted bed, and W3, GGX density and visibility clamped to 1, are also validated. Their proposed corrections need exposure, fog, BRDF peak and motion safeguards. W4’s reflectance/planar filtering is an artistic calibration question. |
| Roof, Moon and lens | M1 and M2 validated by an orthogonal scale sweep, source normal map data and a symmetric four-pixel Moon footprint. N2 is a GLSL portability failure. P1 is a valid placement for a uniform dark-Moon return. A driver may fold the original lens square and hoist inactive Moon work. |
| Countryside, soil and windsock | PBR-01, L1 and PBR-02 validated through the owning data generators, shader resources, pinned engine source and independent arithmetic. The countryside contains 7,168 indexed triangles with constant tint per triangle. |
| Selected aircraft paint and rain | PBR-03 and ATM1 validated. A one-board footprint must integrate the 1.1 mm seam to 2.5581% on the 43 mm wing board at every phase. The shipped cloud alpha has zero endpoints at the sampled row, a 51.8172/255 whole-image mean, and imported mipmaps. |
| Aircraft and field motion | AVI1 and AVI2 validated. Both shipped HX-700 models assign carbon to all four modeled blades and native material code multiplies the duplicated tint. Fixed-wing spatial weather updates ground vegetation from the aircraft rather than a representative fixed ground sample. Each candidate needs an appropriate native integration and its own capture. |
| Art direction and cloud glare | Conditional. Historical pilot-orientation scoring is outstanding. The cool finish belongs to two selected paints; angular cloud fades and differing lunar scene/veil input curves are measurable. The specialist proposals require matched motion or pilot scoring before changing those behaviors. |

I independently reopened the pinned upstream source at `cafc17a19` for light packing, scene-lighting output, precision bounding, reference GGX and refraction. The controlling physics/graphics references are PBRT fourth edition §§9.6 and 11.2, Khronos GLSL §8, and the engine's color-space contract. The original club references and WMO observations characterize plausible field composition and clouds without measuring this simulator.

## Production candidate source review

The ten source files listed by SHA-256 in the ledger implement ten bounded changes, with M1 touching two files and M2/P1 sharing the Moon include. The changes follow the existing material bindings and stay within shader code. I checked the complete file diffs, the source of each built-in or interpolant that changed, and the corresponding unaffected controls.

- N1 uses perspective view cosine, orthographic unity and clamping after conversion. Foreground rejection and artistic depth modulation retain their own coordinate space.
- N2 uses a defined multiply for signed inputs. For a discriminating finite rim, include a negative argument in the support of `in_sheet`. The illustrative negative unit argument lies on its zero-coverage boundary.
- For M1 I generated 10,000 independent random tangent frames, including 5,041 mirrored frames. The new reconstruction matched Gram–Schmidt to within 6.3×10⁻¹³ in float64 on valid data. The relative UV and area guards handle zero UV or collapsed geometry. Texture derivatives are supplied explicitly.
- M2 keeps the radial coverage derivative. Its bounded new footprint chooses LOD 6.69265 in the symmetric 10-pixel case, with a physical equatorial differential reference of 6.03626. This is a deliberate conservative filter, not exact spherical filtering. The inactive uniform return in P1 precedes derivative work.
- L1 multiplies only the custom dirt specular contribution. PBR-01 converts only authored vertex RGB using the existing renderer-aware helper. PBR-02 changes the sleeve's analytic radius derivative without modifying its position. ATM1 retains the clamped source lookup and passes unwrapped derivatives.
- In PBR-03 material part selection is a uniform. The unfolded derivative precedes the varying wing-side branch. Across 501 signed phase positions and one, two and three board footprints, my float64 rectangle integral reproduced the correct seam mean within 9.8×10⁻¹⁶.

On both the initial shader candidate and the final production source, the surfaceless EGL probe passed all nine component groups, comprising 1,271 scalar/pixel cases, on Mesa 25.0.7 llvmpipe OpenGL 4.5. Of those, 1,000 were pixels in a single rain-gradient grid. I checked the actual probe source, its reported SHA-256 digest and every referenced production shader byte hash. An initial failure was diagnosed as a centered Moon test straddling adjacent 2×2 fragment quads. The corrected fixture legitimately represented its stated symmetric-quad oracle and returned baseline LOD 0 versus candidate 6.692645. The rain probe measured a baseline peak of 10.991318 versus the expected continuous 3.619178; it instrumented gradients without fetching the actual texture. Neither data set represents an in-game screenshot. My independent run on the final source reproduced every retained result and all eleven source hashes. A separate three-way source-bound probe recovered the original diagonal-limb footprint while preserving the center-quad result. [Final component receipt](evidence/shader-math-headland.json) · [Three-way lunar check](evidence/moon-floor-math.json) · [Initial passing component receipt](evidence/shader-math.json) · [Initial fixture diagnostic](evidence/shader-math-initial.json)

## Pinned-engine integration on the initial shader candidate

These checks used the shader bytes subsequently committed at `f066ef26c28947fbfa2f7893ececbc1f8657e5b3`. The later Moon and headland corrections have their own final-source component and rendered evidence. Nine candidate checks completed successfully. Eight suites reported **2,407 assertions and zero failures**. The separate building-roof gate checked seven surfaces, 32 triangles, nine mipmapped PBR maps, UVs and clockwise winding. Four matching baseline suites had the same assertion counts and verdicts. I recalculated the SHA-256 of every engine log, verified it against its checked-runner receipt, and matched the production shader hashes before and after the check campaign. [Integration receipts and reproduction instructions](evidence/integration.json)

| Candidate suite | Passed | Evidence limit |
| --- | ---: | --- |
| Lake world | 53 | Geometry/material binding and state |
| Lens effects | 81 | The dummy renderer skipped packed MultiMesh buffer layout |
| Moon sky | 62 | Sky state and shader parameters |
| Moon assets | 21 | Asset contents and map assumptions |
| Windsock | 19 | Geometry and cue data |
| Windsock motion | 37 | Main used reference physics; one warning reported the missing native stage library |
| Storm bank | 55 | Production weather presentation setup |
| Vehicle paint | 2,079 | Aircraft/paint loading and bindings |
| Building roofs | Separate geometry gate | Rendering and normal-map appearance require image evidence |

The first motion and paint attempts failed because the sparse working tree omitted tracked `assets/aircraft` authoring inputs. Both passed in new output directories after the exact inputs were hydrated. The integration receipt retains the original unsuccessful attempts and the subsequent passes. The baseline import also retained eight source-asset warnings. Eight offline capture-workflow tests passed at initial integration. The subsequent sharded capture workflow passed all twelve updated offline tests under independent review. [Workflow and child-process checks](evidence/capture-protocol-review.json)

## Render and performance acceptance

A local Xorg attempt failed to create a listening socket, even though Mesa and a dummy Xorg driver were installed. The local numeric receipt identifies OpenGL llvmpipe. No local hardware GPU was exposed or configured through the test pool. The production-app headless observations exercise bindings and state; framebuffer inspection requires a rendered engine.

For the hosted captures I rehashed the downloaded ZIPs against GitHub’s upload receipts, compared every archived file with its extracted original and fully decoded the baseline and candidate 1920×1080 PNGs. I checked their PNG/RGB hashes, observed device, scene conditions and material witnesses, then independently recalculated changed-pixel counts, bounds and field repeats. All 7,858 runtime inputs were checked against the source manifest. Its final SHA-256 is `262695ea4d6b30939e82372c8a607837e5893fe0982a282f5fa4c501ef205908`. [Hosted checkout, native image and timing evidence](evidence/hosted-independent-review.json)

### Corrections required by the native images

| First candidate | Independently reproduced result | Final static disposition |
| --- | --- | --- |
| Moon texture footprint | A diagonal close-disc edge changed from RGB (181, 182, 187) to (37, 58, 88) at (1166, 390) on Compatibility. A targeted capture found 141 close-view pixels at least eight levels away from baseline. Forward+ had 157 in the close view and three in the wide view at the same threshold. | On both native render methods, every pixel of the corrected close and wide views matches the original baseline. The source-bound center-quad test still returns the corrected LOD. Subpixel motion and broader lunar phases remain open. |
| Forward+ field headland | The original field-entry headland–row difference of 18.29 encoded Y′ levels rose to 75.79, creating a bright triangular patch at the parcel edge. | The single pigment correction measured 11.58 within the predeclared 6–30 range. The original rows, dirt tracks and stubble remain distinct. Relative to the rejected candidate, the registered row, track and stubble interiors and the 390×184 highway road control are pixel-identical. Compatibility retains its original 11.86 level difference. |

The pigment follow-up was isolated by identical untreated frames and a one-file production delta from the previous lunar-only commit. Every other file in that 7,858-path manifest was equal. Predeclared regions and the two initial rejection receipts remain available. [Lunar evidence](evidence/moon-limb-followup.json) · [Headland evidence](evidence/headland-followup.json) · [Final matched images](screenshots.md)


### Scoped checks for the seven isolated control views

The new fixture selects the production `DirtLoopSurface`, verifies all bound dirt texture paths and both dirt-material flags, and requires at least 99% course coverage at the target. It holds the camera, ambient illumination, exposure configuration, 1× 1920×1080 render target and 4× MSAA fixed across the lamp-off, powered-zero, 0.35 and 0.50 specular settings. Compare powered-zero with lamp-off to establish illumination. Within the lit views, the neutral 0.50 control should preserve the baseline result and 0.35 should reduce only the specular contribution. Output-encoded average brightness does not measure the exact ratio of the linear specular term.

The lens fixture feeds a deterministic strike to the real pilot `LensStack`. It checks the material path, selected view, active curtain, viewport, raw curtain age, seed and event key for a disabled chart, a 0.5-second partial curtain and a 1.5-second held curtain. These are a fixed procedural chart and a fixed presentation timeline. A captured difference between builds must fall within the film and survive comparison against the disabled control. Pixel identity on a driver that folds the old power operation is consistent with the portability fix.

I checked that the reducer compares the observed camera, target, FOV, clock, material, light/film state and renderer, and verifies each file hash before reading image differences. Independent pinned-engine parse-only verification succeeded with the absolute fixture path, zero errors and zero warnings. The first independent invocation resolved the external relative path inside the app and could not load the file; both receipts are recorded. The original eight offline tests covered input and reduction contracts. On both the initial and final hosted candidates, the two renderer methods preserved the lamp-off, 0.50 and all three lens charts pixel-for-pixel. In the final captures, the untreated powered lamp produced identical images at 0.00, 0.35 and 0.50. The corrected images visibly separated all three settings. Across every RGB channel, increasing the lamp specular setting never reduced the output level. The diffuse pool remained visible with powered specular set to zero. [Control fixture](../../../tools/graphics/capture_native_shader_controls.gd) · [Integration receipt](evidence/integration.json)


### Feature-level scope

| Native capture | Verified result |
| --- | --- |
| Roofs | At 2 m the actual pavilion and pit-shelter roof materials reported UV determinants of 2.24314×10⁻⁷ and 2.76123×10⁻⁷. Each close view changed at least 1.8 million pixels on each method. The five older views show the cost of using a broad field shot to infer a single material’s behavior. |
| Water | On Compatibility, the shoreline changed in 224,421 pixels, with channel changes from −3 to +5 codes. The overview changed by at most one code. The matched shoreline survives a repeat in each build. Forward+ field images also contain scenery changes, so a whole-frame difference cannot be assigned to water alone. |
| Windsock | The whole-sock, throat and fabric views changed on both methods. The isolated base was identical on both. These views show shading on fixed geometry at the recorded pose. |
| Selected aircraft paint | Front and top views confirm the Aserradero material was active. Relative to baseline, 8,608/9,754 pixels differed on Compatibility and 7,964/8,935 on Forward+. A static camera cannot qualify seam shimmer in flight. |
| Rain | The two Compatibility storm images changed at 189 and 213 pixels by one code. Forward+ wide imagery also contains a distant parcel. A native still and the gradient oracle establish the bounded sampling change. A motion sequence is required to assess visible seam stability. |

Actual presentation pacing, per-shader GPU cost and physical-device memory remain unmeasured. The local runner exposed neither a render device nor a configured remote test pool. On the hosted software renderer, the engine viewport CPU counter measures elapsed time around the viewport and can include waits. Direct-process user and system CPU seconds use separate OS counters. Positive GPU polls can refer to earlier frames. The hardware SKU and CPU core count were absent from the receipts. Each case therefore retains its own VM identity and A/B/B/A launch ordering. [Measurement contracts and pinned-engine sources](evidence/hosted-independent-review.json)


### Selected captures and replay

The selected campaign comprises 23 original workloads and one pavilion recovery, all on the final production source. I verified **60 baseline/candidate image pairs**, 30 per renderer. Their 120 native PNG files retain full 1920×1080 resolution. The 24 additional field repeat observations recorded matching encoded-PNG and decoded-RGB SHA-256 values and the harness removed the duplicate files. The 60 baseline frames also reproduced their earlier untreated captures. The side-by-side gallery JPEGs are reduced previews, and the three diagnostic PNG triptychs preserve nine actual unscaled source crops. [Gallery](screenshots.md) · [Native crop provenance](evidence/regression-triptychs.json)

All **48 selected field invocations** exited naturally. Of 24 image-only invocations, 19 exited naturally and five Forward+ processes received SIGTERM after their complete image sets remained hash-stable through a 30-second grace period. Those five comprise both windsock captures, both storm captures and the candidate roof capture. A completed image set and a natural teardown are separate observations. The optional Vulkan optimizer emitted 256 unsupported-opcode messages across the selected render logs. Pinned engine source retains the original SPIR-V in this situation. The delayed teardowns have no independently established cause. [Lifecycle record](evidence/hosted-capture-lifecycle-final.json) · [Pinned optimizer and driver evidence](evidence/hosted-initial-forward-plus.json)

The original Forward+ pilot job completed, so the predeclared rule selects its four measurements. The original Forward+ pavilion job completed three field invocations and its final baseline import before cancellation. All four measurements for that case come from the qualified recovery on a single VM. In both cases I checked the pinned engine, all harness bytes, production inputs and matching native image hashes. Both excluded attempts retain their raw numeric and checked-log evidence. [Pilot selection](evidence/pilot-selection-final.json) · [Pavilion selection](evidence/pavilion-selection-final.json)

I checked all 181 members of the selected numerical replay against the original archive contents and independently regenerated the performance JSON byte-for-byte. A second calculation reproduced all 648 timing statistics, 24 paired throughput differences and all 48 process CPU/RSS measurements. Per-pair measured throughput changes ranged from −0.66% to +2.25%. Eight of the twelve renderer/camera cases changed sign across their two paired comparisons. Three resource samplers reported that the direct process had exited at teardown and marked coverage partial. Their sampled values and raw diagnostics are retained. The data support within-job software-render comparisons. A repeatable physical-device speedup remains unqualified. [Per-case performance](evidence/hosted-field-performance.json) · [Standalone raw replay manifest](evidence/field-benchmarks-final-manifest.json)
