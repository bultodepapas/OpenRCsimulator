# DT-MAC-00-R1 — Twenty investigations for M1–M5

2026-10-24 · **Twenty internet investigations completed.** Primary Apple, Godot and GitHub documentation/source were consulted. These are research findings and test designs; no Mac performance measurement was performed.

The user confirmed a **MacBook Air M1 with 8 GB unified memory**. GPU core count, exact model identifier and macOS build are pending identification. The [updated execution plan](../../../plans/apple-silicon-performance.md) targets M1–M5 and starts with this low-memory/fanless host. Hardware availability and measured acceptance remain separate. The [initial source review](../../../research/apple-silicon-performance-2026-10-24.md) remains the earlier repository snapshot.

## The twenty investigations and their effect on the plan

Each numbered investigation has a question, sourced findings, a plan consequence, a specific test and limits. They are grouped into three reports to keep one coherent source home rather than twenty near-empty files.

| ID | Investigation / report | Resulting action in the plan |
| --- | --- | --- |
| I01 | [M1 GPU/RAM/chassis floor](01-hardware-memory.md) | DT-MAC-01 records the confirmed Air/8 GB and identifies its remaining GPU/OS details |
| I02 | [M2 scaling and configurations](01-hardware-memory.md) | DT-MAC-08a adds a named M2 row and holds workload/settings constant |
| I03 | [M3 architecture and optional features](01-hardware-memory.md) | Keep common raster baseline; do not require newer GPU paths on M1/M2 |
| I04 | [M4 base/Pro/Max differences](01-hardware-memory.md) | Separate variant/chassis/memory from generation when qualifying presets |
| I05 | [M5 documented hardware and variants](01-hardware-memory.md) | Include M5 in required generation coverage; distinguish base and higher tiers |
| I06 | [GPU-family, Metal and OS matrix](01-hardware-memory.md) | DT-MAC-05 records effective API/backend; newer OS is a separate comparison |
| I07 | [Unified memory and resource residency](01-hardware-memory.md) | DT-MAC-03/04/08 measure system pressure plus resource lifetime, not additive RSS+VRAM |
| I08 | [Native Metal, MoltenVK and OpenGL](02-rendering.md) | Native-driver trials retain a controlled baseline and conditional translation-layer comparison |
| I09 | [Mobile versus Forward+ parity](02-rendering.md) | DT-MAC-05 checks features before timing; High remains a separate visual profile |
| I10 | [MetalFX spatial/temporal integration](02-rendering.md) | DT-MAC-07 uses a renderer-specific support matrix and actual capability checks |
| I11 | [Shader/pipeline compilation and caches](02-rendering.md) | Cold-process, fresh-import and warm-cache runs have distinct identities |
| I12 | [Tile bandwidth, MSAA, shadows and reflections](02-rendering.md) | DT-MAC-06 changes one attributed GPU cost; no engine render-graph rewrite by default |
| I13 | [Texture formats across GPU generations](02-rendering.md) | Validate effective GPU imports/fallbacks on M1 and newer families before changing assets |
| I14 | [Vegetation, smoke, LOD and culling](02-rendering.md) | Profile existing landscape/smoke systems; preserve obstacle and attitude cues |
| I15 | [CPU scheduling, threads and loading](03-runtime-validation.md) | DT-MAC-04 preserves solver order; only independent measured work moves to existing workers |
| I16 | [Retina, ProMotion and pacing](03-runtime-validation.md) | 1080p drawable/60 Hz baseline; high refresh and buffer-count experiments are separate |
| I17 | [Thermals, power and Game Mode](03-runtime-validation.md) | DT-MAC-08 measures effective power/Game Mode and full-session behavior |
| I18 | [Profiling tools and version limits](03-runtime-validation.md) | DT-MAC-02 uses supported Instruments/HUD/counter workflows, with overhead controls |
| I19 | [Native packages and CI limitations](03-runtime-validation.md) | DT-MAC-08/09 validate the final ARM64 release; CI and profiling builds remain distinct |
| I20 | [Capability policy and M1–M5 qualification](03-runtime-validation.md) | DT-MAC-06a/08a add shared capability policy, preset recovery and five-generation evidence |

## Decisions this round changes

- **Scope:** all five requested generations are explicit acceptance rows, not an optional “newer Mac” comparison.
- **Readiness:** the M1 Air/8 GB is available for execution and matches the low-memory/fanless target. GPU variant, OS/build and access setup remain to be recorded; no benchmark has run.
- **Architecture:** one ARM64 application and a common render path, with optional capabilities and measured quality selection; no chip-name-only quality policy.
- **Rendering:** MetalFX support depends on method/device/OS as well as enum presence; supported scaling routes must be reflected honestly in the UI.
- **Evidence:** native 1080p comes first; the same package, workload and recorded settings propagate from M1 to M2–M5. Hardware launches, visual/numerical acceptance and sustained performance are separate claims.
- **Next delivery:** inventory, native release baseline, attribution and one candidate on M1. Research completion does not close those implementation gates.

## Method and limitations

Hardware and renderer questions were investigated independently, then reconciled with runtime/tooling research and the current plan. Decisive sources were opened, including tagged Godot 4.7.2 source and Apple product specifications. Apple DocC Markdown was used when HTML required JavaScript. Inline links identify the source of each external claim; proposals and unperformed tests are labeled.

Vendor bandwidth, core counts and comparative marketing results are not OpenRC speedups. An API capability is not engine adoption, and a successful engine launch is not sustained flight acceptance. M2–M5 hardware access is not established. Every claimed support configuration still needs the plan's evidence; missing hardware is recorded, never replaced by a synthetic extrapolation.

No new runtime code, engine dependency, asset, external service or benchmark image was added. The [desktop delivery plan](../../../DESKTOP-DELIVERY-PLAN.md) retains release/signing ownership and the [execution plan](../../../plans/apple-silicon-performance.md) owns DT-MAC status.
