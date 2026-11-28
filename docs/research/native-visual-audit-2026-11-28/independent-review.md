# Independent review of the native visual audit

The baseline is `71306784a250d634854f0c8bab3a927cc46a61b8`. The ten candidate shader paths and their exact SHA-256 values are recorded in the [verification ledger](verification-ledger.json). The reviewer inspected each specialist submission against the production source, data files and original technical reference, examined the integrated diff and ran the candidate integration checks independently.

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

The surfaceless EGL probe subsequently passed all nine component groups, comprising 1,271 scalar/pixel cases, on Mesa 25.0.7 llvmpipe OpenGL 4.5. Of those, 1,000 were pixels in a single rain-gradient grid. I checked the actual probe source, its reported SHA-256 digest and every referenced production shader byte hash. An initial failure was diagnosed as a centered Moon test straddling adjacent 2×2 fragment quads. The corrected fixture legitimately represented its stated symmetric-quad oracle and returned baseline LOD 0 versus candidate 6.692645. The rain probe measured a baseline peak of 10.991318 versus the expected continuous 3.619178; it instrumented gradients without fetching the actual texture. Neither data set represents an in-game screenshot. The corrected and initial receipts are preserved. [Passing component receipt](evidence/shader-math.json) · [Initial fixture diagnostic](evidence/shader-math-initial.json)

## Pinned-engine integration

Nine candidate checks completed successfully. Eight suites reported **2,407 assertions and zero failures**. The separate building-roof gate checked seven surfaces, 32 triangles, nine mipmapped PBR maps, UVs and clockwise winding. Four matching baseline suites had the same assertion counts and verdicts. I recalculated the SHA-256 of every engine log, verified it against its checked-runner receipt, and matched the production shader hashes before and after the check campaign. [Integration receipts and reproduction instructions](evidence/integration.json)

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

The first motion and paint attempts failed because the sparse working tree omitted tracked `assets/aircraft` authoring inputs. Both passed in new output directories after the exact inputs were hydrated. The integration receipt retains the original unsuccessful attempts and the subsequent passes. The baseline import also retained eight source-asset warnings. Eight offline capture-workflow tests passed independently.

## Render and performance acceptance

A local Xorg attempt failed to create a listening socket, even though Mesa and a dummy Xorg driver were installed. The local numeric receipt identifies OpenGL llvmpipe. No local hardware GPU was exposed or configured through the test pool. The production-app headless observations exercise bindings and state; framebuffer inspection requires a rendered engine.

For rendered acceptance, examine decoded 1920×1080 baseline and candidate PNGs at native size, with the actual renderer/device, camera, scene state, tick, exposure, selected material/feature and internal resolution identified. Compare the target region and an unaffected control, and review multiple matched frames for any temporal/readability claim. The two-pair static field campaign and single-pair detail views describe the hosted software installation. A positive root viewport GPU poll has unverified age. Direct-process CPU/RSS includes startup and all case views. Actual displayed pacing, shader GPU time, process and graphics memory outcome on a target device require matched physical-hardware runs. [Capture and cost scope](README.md#performance-acceptance)


### Scoped checks for the seven isolated control views

The new fixture selects the production `DirtLoopSurface`, verifies all bound dirt texture paths and both dirt-material flags, and requires at least 99% course coverage at the target. It holds the camera, ambient illumination, exposure configuration, 1× 1920×1080 render target and 4× MSAA fixed across the lamp-off, powered-zero, 0.35 and 0.50 specular settings. Compare powered-zero with lamp-off to establish illumination. Within the lit views, the neutral 0.50 control should preserve the baseline result and 0.35 should reduce only the specular contribution. Output-encoded average brightness does not measure the exact ratio of the linear specular term.

The lens fixture feeds a deterministic strike to the real pilot `LensStack`. It checks the material path, selected view, active curtain, viewport, raw curtain age, seed and event key for a disabled chart, a 0.5-second partial curtain and a 1.5-second held curtain. These are a fixed procedural chart and a fixed presentation timeline. A captured difference between builds must fall within the film and survive comparison against the disabled control. Pixel identity on a driver that folds the old power operation is consistent with the portability fix.

I checked that the reducer compares the observed camera, target, FOV, clock, material, light/film state and renderer, and verifies each file hash before reading image differences. Independent pinned-engine parse-only verification succeeded with the absolute fixture path, zero errors and zero warnings. The first independent invocation resolved the external relative path inside the app and could not load the file; both receipts are recorded. The eight offline tests verify input and reduction contracts. A completed rendered pair is required before attributing a displayed lighting or lens change. [Control fixture](../../../tools/graphics/capture_native_shader_controls.gd) · [Integration receipt](evidence/integration.json)
