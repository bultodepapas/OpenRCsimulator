# VQ-04a-F2: moving windsock shadows

2026-10-19. Local follow-up to [projected field shadows](../README.md) and [windsock motion](../../../wind-implementation/M5-W04b-R1/README.md).

The previous field caster deliberately included only the fixed mast. This delivery adds the swivelling basket and deforming sleeve to that same ground shadow. It retains the existing Compatibility projection, opacity, height-based softness, lighting controls and flat-ground receiver.

## Implementation

`windsock_projected_shadow.gd` specializes the existing projector. One 512² coverage map contains the fixed support plus two mesh proxies sharing the actual fabric and basket mesh resources. The sleeve's vertex deformation is extracted into `windsock_deformation.gdshaderinc`; both the visible fabric and the coverage shader use it. The basket proxy uses the same bearing yaw. No CPU mesh rebuild or independent animation clock is introduced.

The projector reads the visible material's current centreline, yaw and inflation after the world upload (process priority 80). Current conservative visual bounds frame the mask, including gusts and direction changes. New poses or visible shader flutter request `UPDATE_ONCE`; pause holds the cached mask. Approximate pose comparison and an inflation threshold of 0.0001 avoid redraw for invisible settling and micrometre-scale flutter after wind decays. The full visible shader continues using its original inputs.

The map replaces the old 256² mast map, adding 196,608 target pixels without adding a projector. Existing limits of 16 maps and 8,388,608 target pixels remain enforced. The coverage pass has three mesh draws; their overlapping silhouettes form one mask instead of stacking dark receivers. Native windsock shadow casting stays disabled, avoiding duplicate shadows and preserving the same result with native engine shadows off.

The field lighting cache now includes `shadow_strength` as well as direction and light energy, so opacity-only changes refresh immediately.

## Verification

Native captures use pinned Godot 4.7.2, Compatibility/OpenGL 3.3 and an NVIDIA RTX 3090. The seven fixed cases cover calm, light and strong wind, reversal, 15°/75° sun, and zero shadow strength. Hiding the receiver yields **zero changed visible pixels** against the pre-change shader in all seven cases. The original projection's independent native GPU oracle also passes.

Focused tests cover moving uniforms and bounds, pause/cache reuse, calm residuals, root pose, source visibility, lighting strength, map budgets and teardown. Native motion/oracle and component timing results are retained with the final verification record.

This is a flat-ground shadow. It does not add self-shadowing, cloth light transmission or shadows on other objects. Softness and opacity remain presentation estimates. Native timings on this desktop cannot establish complete flight frame budgets, minimum hardware or other platforms. A full application suite and owner playtest are separate checks.

## Reproduce and sources

Use the pinned engine from the repository root:

```powershell
godot --headless --path app --script res://tests/test_windsock_shadow.gd
godot --headless --path app --script res://tests/test_field_projected_shadows.gd
godot --path app --audio-driver Dummy --script tools/shadows/windsock_capture.gd -- --out=C:/absolute/new-directory
```

Use an absolute `--script` path if the engine resolves it relative to `app/`. Captures require a real renderer; headless script checks cannot qualify silhouettes.

Godot documents [shared shader includes](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shader_preprocessor.html#include) and [one-shot SubViewport updates](https://docs.godotengine.org/en/4.7/classes/class_subviewport.html). Existing [projection research](../research.md) explains Compatibility constraints, clipping and the independent ray-plane oracle. No asset download or new dependency was needed for these shadows.
