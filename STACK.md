# Development stack

Research date: **2026-10-05**. This document surveys the current options for building the simulator, explains what "robust from the beginning" means for us, and records the stack we start with. Everything here is provisional: each choice names the evidence that would change it. Choices are recorded in [DECISIONS.md](DECISIONS.md); the route they serve is in [ROADMAP.md](ROADMAP.md). Earlier platform research lives in [RESEARCH.md](RESEARCH.md#engines-platforms-and-controls-several-viable-paths).

**How the evidence was gathered.** Versions and release dates come from the npm registry, queried directly on 2026-10-05, or from official project pages. Many web search results were SEO aggregator blogs; claims that rely only on such secondary sources are marked *(secondary)*. Two small experiments were executed; everything else is documentation-based and was not built or run.

## The starting stack at a glance

| Layer | Starting choice | Version on 2026-10-05 | Why | We change it if… |
| --- | --- | --- | --- | --- |
| Runtime target | Desktop browser (Chromium, Firefox, Safari) | — | No install; one link to share; works on every desktop OS | A transmitter cannot be read, or latency is poor |
| Language | TypeScript | 7.0.2 (native Go compiler, GA July 2026) | Types catch shape and unit-label mistakes; fast checking | — |
| Dev server / bundler | Vite | 8.3.2 (8.0 released 2026-03-12) | Mature, near-instant reload, no config for TS | — |
| Node / package manager | Node 24 LTS, npm | Node 24.19, npm 11.17 | Already installed; the boring default | — |
| Rendering | three.js, `WebGLRenderer`, built-in materials only | r186 (`0.186.1`) | Most widely used web 3D library; WebGL 2 runs everywhere | We need WebGPU features, or churn hurts (see Babylon.js) |
| Flight physics | Our own module, plain TypeScript, **float64 only**, no renderer imports | — | No library fits a 2-stroke RC plane; precision experiment below | Effort to rebuild mature features gets too high (JSBSim) |
| Physics engine library | None for now | Rapier 0.21, Jolt (WASM) 1.1 noted | Flight needs no general collision engine; ground contact starts as our own spring-dampers | Scenery collisions become complex |
| Tests | Vitest | 5.0.3 | Runs physics headless in Node; same config as Vite | — |
| Visual checks | Playwright | 1.63.0 | Screenshots of the airplane for human and AI review | — |
| Lint + format | Biome | 2.5.15 | One tool; does not depend on the TypeScript compiler API (see TS 7 caveat) | typescript-eslint supports TS 7 and we want type-aware rules |
| Debug panels | lil-gui | 0.21.0 | Tiny; used by three.js examples | — |
| Audio | Web Audio API (built in) | — | No dependency; oscillators and gain for an rpm-linked tone | — |
| Desktop download (later) | Installable PWA first; Electron if a real download is needed | Electron 44.5 | Same Chromium everywhere | — |

Total runtime dependencies to start: **three** and **lil-gui**. Everything else is development tooling.

## What "robust from the beginning" means here

1. **Open license, no vendor gate.** MIT, Apache-2.0, zlib or similar. A proprietary engine would make the project depend on terms we do not control.
2. **Boring where it does not matter, new only where it pays.** Use mature defaults (WebGL 2, npm, Web Audio). Take something new only when it brings a clear win now (TypeScript 7's speed costs nothing at runtime).
3. **The physics core outlives the renderer.** Flight dynamics are plain functions over plain data. They never import three.js. If the renderer, engine or platform changes, the core moves with us.
4. **Machine-checkable feedback.** Every layer has a command that answers pass/fail: type check, unit tests, screenshot. That matters doubly with AI-assisted development.
5. **Few dependencies, pinned exactly.** Commit the lockfile, pin exact versions, and upgrade one dependency at a time on purpose.
6. **Runs on every desktop without install.** Linux included, which rules out stacks with known Linux rendering trouble for this kind of app.

## Options surveyed

### Whole-application routes

| Route | Current state | License | Web | Native | Stability signal | Fit for us now |
| --- | --- | --- | --- | --- | --- | --- |
| **Browser library**: three.js / Babylon.js / PlayCanvas + TypeScript | three r186 (2026-09-08); Babylon 9.29 (9.0 on 2026-03-26); PlayCanvas 2.23 | MIT / Apache-2.0 / MIT | Native target | PWA, Electron | three breaks APIs between releases; Babylon promises backward compatibility | **Chosen.** Fastest path to a shareable airplane |
| **Integrated engine**: Godot | 4.7 stable (2026-06-18), 4.7.2 (2026-08-18), 4.8 at feature freeze (dev 7, 2026-09-29) | MIT | GDScript exports to web (Compatibility renderer); **C# cannot export to web** | Excellent | Mature, regular releases | Strongest alternative; see the in-depth section below |
| **Rust engine**: Bevy | 0.19 (2026-06-19); still pre-1.0 | MIT / Apache-2.0 | WebGL 2 or WebGPU builds, no automatic fallback | Excellent | Breaking changes every release (~every 3–6 months) | Not now: churn plus a slower learning loop |
| **Small native C**: raylib / sokol / SDL3 | raylib 6.0 (2026-04-23, adds a CPU software renderer) *(secondary)*; sokol gained a Vulkan backend (Dec 2025) *(secondary)* | zlib | Via Emscripten | Excellent | Simple, stable APIs | Good for a native port of the physics core later; more to build ourselves |
| **Proprietary**: Unity / Unreal | — | Proprietary terms (see RESEARCH.md) | Yes | Yes | — | Excluded: conflicts with an open-source project we fully control |

### Godot and other integrated engines, in depth

Godot is the strongest alternative to the browser route, so it gets a closer look. Facts below come from the Godot 4.7 documentation unless marked.

**Where Godot is better for an RC simulator:**
- **Native transmitter input.** Desktop builds use **SDL 3** for controllers (since 4.5), the same layer most PC games use. Native apps read joysticks directly, without the browser's "press a button first" gesture rule. Godot exposes up to **10 axes** (`JOY_AXIS_MAX`), enough for an 8-axis EdgeTX radio. The docs do say specialized peripherals (HOTAS, pedals) are "less tested."
- **A visual editor** for scenes, lighting, cameras, materials and importing aircraft models. With three.js, we would build every tool ourselves.
- **Native desktop builds** for Windows, macOS and Linux with no webview, plus Android and iOS later.
- **Physics included.** Jolt is the default 3D physics from 4.6 *(secondary)*, useful later for scenery collisions.
- **Maturity.** MIT license, large community, regular stable releases (4.7.2 in August 2026; 4.8 at feature freeze).

**Where Godot costs us:**
- **Math precision.** "float is 64-bit in GDScript, but Vector2, Vector3 and Vector4 are 32-bit." Our experiment shows 32-bit vectors lose small accelerations. Double-precision vectors require **recompiling the editor and every export template** with `precision=double`; no official double builds exist. The workarounds are physics state in plain 64-bit floats or `PackedFloat64Array` (clumsy), or C++ GDExtension physics (which must be compiled separately for the web).
- **Web export is a second-class target.** It is WebGL 2 only (Compatibility renderer). **C# cannot export to the web.** Gamepads are not detected until a button is pressed, and mappings may be wrong per browser/OS. The default audio mode has **no procedural audio**, which matters for an rpm-driven engine sound; the full-featured mode adds latency.
- **Download size.** A default 4.x web export is about **42 MB**. One author reached 2.7 MB brotli only by compiling custom templates *(secondary: [popcar](https://popcar.bearblog.dev/how-to-minify-godots-build-size/))*. A three.js page starts well under 1 MB.
- **Input defaults fight RC.** Input actions have a default deadzone of 0.5. We would read raw axes and bypass the action system.
- **Feedback loop for AI and tests.** Scenes are text (`.tscn`), and the CLI can run headless, import and export. But tests need an add-on (e.g. GUT or gdUnit4), and some work needs editor clicks. The browser route has plain `npm test` plus screenshots.

**The other "engines like that":**

| Engine | State | License | Why not first |
| --- | --- | --- | --- |
| **O3DE** | 26.05 (2026-05-27); Windows and Ubuntu binaries; PhysX 5 by default *(secondary)* | Apache-2.0 | Heavy AAA-style engine; large install; no web target |
| **Stride** | 4.3 stable (2025-11); 4.4 in beta *(secondary)* | MIT | C#/.NET; editor is Windows-centric; no web target |
| **Flax** | Active, source-available | **4% royalty** above $250k per quarter *(secondary)* | Not open source |
| **Defold** | Active; strong in 2D, 3D possible | Free, own license (not OSI) | 3D is not its focus |
| **Panda3D** | 1.10.16 (2025-12-25); 1.11 not released *(secondary)* | BSD | Old and robust, Python/C++, but desktop only and a slow release pace |
| **Bevy**, **raylib**, **Unity/Unreal** | See the routes table above | — | — |

**Bottom line.** Godot is the best choice if we want a **native desktop app with an editor**. The browser is the best choice if we want **zero install, a shareable link, small downloads, plain-text tooling, and float64 physics without custom engine builds**. The project principle "start small, show a little airplane" fits the browser slightly better. Godot's native input and editor become more valuable later, when transmitters and scenery matter.

These routes are not exclusive. The physics core is plain functions over plain data, so it can be ported to GDScript or C++ later. **The cheapest way to decide is to build Stage 0 in both** (the comparison planned in RESEARCH.md) and compare real setup time, edit/run loop, screenshot capture and radio input.

### Browser renderers compared

| | three.js | Babylon.js | PlayCanvas |
| --- | --- | --- | --- |
| Scope | Rendering library; we assemble the rest | Full engine: inspector, GUI, audio, physics plugins | Engine; best tooling is a hosted editor (commercial) |
| Release model | `r` releases roughly every 1–3 months in 2025–26 (r183 Feb, r184 Apr, r185 Jun, r186 Sep 2026); deprecated APIs removed after some releases | First "golden rule": *you cannot add code that breaks backward compatibility* | Semver 2.x |
| WebGPU | `WebGPURenderer` with automatic WebGL 2 fallback; uses TSL node materials, not old `ShaderMaterial` | WebGL and WebGPU engines | WebGL 2 first, WebGPU maturing *(secondary)* |
| Ecosystem / examples | Largest by far; most familiar to AI coding tools | Large, strong forum | Smaller |

**Why three.js despite the churn:** our rendering surface is tiny (a few meshes, a camera, a sky, a ground). We isolate it in one `render/` module and pin the exact version, so an upgrade touches one folder. In exchange we get the largest pool of examples and the smallest dependency. **Babylon.js is the robust fallback**: if three.js upgrades start costing real time, its compatibility promise is the strongest in this survey.

### WebGL 2 or WebGPU?

WebGPU status from the [gpuweb implementation-status wiki](https://github.com/gpuweb/gpuweb/wiki/Implementation-Status):

| Browser | Windows | macOS | Linux | Mobile |
| --- | --- | --- | --- | --- |
| Chromium | ✅ 113+ | ✅ 113+ | Partial: Intel Gen12+ (144+), NVIDIA on Wayland (147+), others behind a flag | Android ✅ for most GPUs |
| Firefox | ✅ 141+ | ✅ Apple Silicon 145+ | ❌ Nightly only, 2026 target | Behind a flag |
| Safari | — | ✅ 26+ | — | ✅ iOS 26+ |

**Decision:** start on `WebGLRenderer`. Firefox on Linux and many Linux Chromium setups still lack WebGPU, and our first scenes need nothing WebGL 2 lacks. If we avoid custom shaders and post-processing, a later switch to `WebGPURenderer` (with fallback) stays small.

### Language and toolchain

- **TypeScript 7.0** (npm `7.0.2`, 2026-07-08) is the compiler rewritten in Go, with roughly 8–12× faster builds *(secondary: [InfoQ](https://infoq.com/news/2026/08/typescript-7-released/), [Visual Studio Magazine](https://visualstudiomagazine.com/articles/2026/06/22/typescript-7-0-rc-moves-microsofts-go-rewrite-into-the-mainline-compiler.aspx))*.
  - **Caveat:** 7.0 has **no programmatic API** yet; it is planned for 7.1 (its beta was announced for 2026-10-06). Tools built on that API, notably **typescript-eslint**, do not support TS 7 yet.
  - Defaults changed too: `strict` is on by default, and `baseUrl` and `downlevelIteration` were removed.
  - **Consequence for us:** Vite strips types without the compiler, so it is unaffected. We run `tsc --noEmit` for checking, and use **Biome** for linting so we do not depend on that API.
- **Vite 8** requires Node `^20.19 || >=22.12`; Node 24 LTS satisfies it.
- **Bun 1.4** is a faster all-in-one alternative. npm is already installed and universally understood, so it wins on "boring."

### Physics: what to write, what to borrow

**Executed experiment: float32 vs float64.** Common JS math libraries store vectors in 32-bit floats by default. gl-matrix 3.4.4 sets `ARRAY_TYPE = Float32Array` (inspected in the package source). wgpu-matrix 3.4.2 defaults to float32 but also ships separate float64 variants. We simulated 60 s at 240 Hz with a small steady acceleration ([script](research/float32_vs_float64_integration.mjs), run with `node`):

| Steady acceleration | float64 Δv after 60 s | float32 Δv after 60 s | Exact |
| --- | --- | --- | --- |
| 0.1 m/s² | 6.0000 | 5.9875 | 6.0 |
| 0.01 m/s² | 0.6000 | 0.6043 | 0.6 |
| 0.001 m/s² | 0.0600 | 0.0549 (−8%) | 0.06 |
| 0.0001 m/s² | 0.0060 | **0.0000 (lost)** | 0.006 |

In float32, small force imbalances, the kind that decide trim and slow drift, vanish or get distorted. **Rule: physics state is stored in plain JS numbers (float64). Never use `Float32Array` in physics.** We write a small vector/quaternion module (~200 lines) instead of importing a graphics math library. The renderer may use float32; the conversion happens at the render boundary.

**Finding: JS math is not bit-identical across engines.** ECMAScript leaves `Math.sin`, `Math.cos`, `Math.atan2`, `Math.exp` and similar functions *implementation-approximated*. Only `+ − × ÷` and `sqrt` are exactly specified. A physics library reported its 900-step simulation diverging between Node 20 (V8 11.3) and Chrome 149 (V8 14.9) because of `Math.sin`/`Math.cos` in the quaternion integrator. An fdlibm-based replacement restored identical results at about 1.1× the cost ([Bounce issue #8, 2026-08-03](https://codeberg.org/perplexdotgg/bounce/issues/8)).

- **Policy:** replays and tests compare **within tolerance**, not bit-for-bit.
- All transcendental math goes through one `physics/math` module, so a deterministic implementation can be swapped in later if multiplayer or shared replays need it.

**Libraries considered and deferred:**
- **Rapier** (`@dimforge/rapier3d-compat` 0.21, Apache-2.0, still 0.x with frequent minor bumps) and **Jolt** (`jolt-physics` 1.1 WASM, MIT; Godot 4.6+ uses Jolt as its default 3D physics *(secondary)*) are general rigid-body engines. One airplane plus landing-gear springs does not need them. Revisit for scenery collisions.
- **JSBSim** has community proofs of WASM builds *(secondary)*, but no official web package (`jsbsim` is not on npm). Its piston model officially supports only four-stroke engines.

### Input

- Chromium's Gamepad implementation caps a device at **16 axes** (`kAxesLengthCap`). That covers EdgeTX's 8-axis classic joystick report.
- **Firefox on Linux** maps some controllers differently (e.g. triggers as axes, different axis order) *(secondary, consistent with the W3C spec allowing non-standard mappings)*.
- Our input layer must therefore show raw axes and let users map them. It must never assume the `standard` layout for a transmitter. WebHID remains a Chromium-only escape hatch.

### Desktop packaging, later

| Option | Engine underneath | Note |
| --- | --- | --- |
| Installable PWA | The user's browser | Zero extra cost; offline possible |
| **Electron** 44 | Bundled Chromium, identical on every OS | Large download (~100 MB class), but consistent WebGL/WebGPU and Gamepad behavior |
| Tauri 2.12 | The OS webview: WebKitGTK on Linux, WebKit on macOS | **Not for us now.** Tauri's own docs list Linux WebKitGTK problems: blank windows or crashes on NVIDIA (DMABUF), WebGL "silently landing on a slow path," and a masked GPU string that hides software rendering ([Tauri docs](https://v2.tauri.app/develop/debug/linux-graphics/)) |

### Other ecosystem notes

- **wasm-bindgen** (if we ever port the physics core to Rust/WASM) moved to its own organization when the rustwasm org was archived in 2025; it is still maintained ([Rust blog](https://blog.rust-lang.org/inside-rust/2025/07/21/sunsetting-the-rustwasm-github-org)).
- **Tweakpane** (4.0.5) has had no npm release since 2024-11; **lil-gui** (0.21, 2025-10) is the more active small option. **uPlot** (1.6.32) is a lean candidate for live plots later.
- **React Three Fiber** (9.8) adds React on top of three.js. Not needed: our UI is a few panels, and a simulation loop is easier to reason about without a UI framework's render cycle.

## Code layout we start with

```text
src/
  physics/   pure TypeScript, float64, no imports from render/ or three
  aircraft/  JSON parameter files with units and provenance
  input/     keyboard, gamepad, raw→mapped channels
  render/    the only folder that imports three
  app/       main loop: fixed-step physics, interpolated rendering
test/        Vitest, headless physics checks
research/    standalone scripts (Python stdlib / Node), unchanged role
```

## Upgrade policy

- Exact versions in `package.json`, lockfile committed.
- Upgrade one dependency per change, run type check + tests + screenshot, and read the release notes (three.js publishes a migration guide per release).
- At each roadmap stage's end, run `npm outdated` and decide deliberately. Staying one version behind is fine.

## New investigations opened by this pass

| Question | Smallest experiment | Triggers |
| --- | --- | --- |
| Does a real radio give all channels in each browser? | Raw gamepad inspector page; test Chrome, Firefox, Safari on available OSes | ROADMAP F1 |
| Is three.js pleasant enough to change? | The bake-off (B5–B6); count time lost to API changes or missing examples | Gate 1 |
| Does Playwright capture WebGL reliably headless and in CI? | Screenshot the Stage 0 scene in headless Chromium. **Locally confirmed 2026-10-05** (SwiftShader, 1.6 s build + capture); CI still open | ROADMAP A3 |
| How large is cross-engine drift in our own integrator? | Run the same scripted flight in Node, Chrome and Firefox; compare final states | ROADMAP C5 |
| When does TS 7.1 restore the API? | Watch the 7.1 release; then decide whether type-aware linting is worth adding | Passive |
| When is WebGPU worth switching to? | Re-check Firefox Linux status; try the `WebGPURenderer` swap on the flying scene | After Phase E |

## Sources

Primary and registry sources:
- npm registry metadata (queried 2026-10-05)
- [three.js releases](https://github.com/mrdoob/three.js/releases)
- [gpuweb implementation status](https://github.com/gpuweb/gpuweb/wiki/Implementation-Status)
- [Godot blog](https://godotengine.org/blog/)
- Godot 4.7 docs: [large world coordinates](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html), [web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html), [controllers](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html), [`JoyAxis`](https://docs.godotengine.org/en/stable/classes/class_%40globalscope.html)
- [O3DE release notes](https://www.docs.o3de.org/docs/release-notes/), [Flax FAQ](https://flaxengine.com/faq/), [Defold](https://defold.com/), [Panda3D downloads](https://www.panda3d.org/download/)
- [Bevy news](https://bevy.org/news/)
- [Babylon.js 9.0 announcement](https://blogs.windows.com/windowsdeveloper/2026/03/26/announcing-babylon-js-9-0)
- [Babylon.js contributing rules](https://github.com/kzhsw/Babylon.js/blob/master/contributing.md) (mirror of the upstream rules)
- [Tauri Linux graphics](https://v2.tauri.app/develop/debug/linux-graphics/)
- [Bounce determinism issue](https://codeberg.org/perplexdotgg/bounce/issues/8)
- [Chromium gamepad.h](https://gitcode.com/openharmony-tpc/chromium_src/blob/master/device/gamepad/public/cpp/gamepad.h) (mirror)
- [Godot forum: C# web export](https://forum.godotengine.org/t/is-there-an-update-on-exporting-c-projects-to-web/128821)
- [Rust: sunsetting rustwasm](https://blog.rust-lang.org/inside-rust/2025/07/21/sunsetting-the-rustwasm-github-org)

Secondary sources:
- TypeScript 7: [InfoQ](https://infoq.com/news/2026/08/typescript-7-released/), [Visual Studio Magazine](https://visualstudiomagazine.com/articles/2026/06/22/typescript-7-0-rc-moves-microsofts-go-rewrite-into-the-mainline-compiler.aspx), [TS 7 and ESLint](https://dev.to/the-modern-web/why-angular-vue-and-eslint-cant-upgrade-to-typescript-70-yet-and-why-ts-71-changes-441g)
- raylib 6.0: [Arch package](https://archlinux.org/packages/extra/x86_64/raylib/), [release summary](https://feedbagel.com/post/raylib-60-released-new-software-renderer-backend-and-major-feature-updates)
- Godot 4.6 and Jolt: [summary](https://app.cinevva.com/news/2026-02-27-godot-4-6-released)
- PlayCanvas WebGPU status: [comparison](https://app.cinevva.com/guides/playcanvas-vs-threejs)
- Firefox gamepad mapping: [Beej's notes](https://beej.us/blog/data/javascript-gamepad/)
