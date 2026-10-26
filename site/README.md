# OpenRC project website

WEB-01…08 own `site/` and the isolated `gh-pages` deployment. No simulator runtime files are changed.

## Design

Visual thesis: an RC club's aircraft catalogue, combining oversized workshop typography, original dark studio renders, ivory paper and field green.

Content: aircraft-led poster → OpenAI principal sponsor acknowledgment and manufacturer introduction → six-aircraft 360° hangar → platform downloads → day/night field → technical system index → asset/vehicle showcase → manufacturer partner details → development status and contribution paths. Spanish is the initial language; English and a page-wide night theme are selectable and saved locally. Downloads target the v0.1.7 release snapshot; the site distinguishes a stable software release from the simulator's early-alpha status and experimental aircraft and vehicle models.

Interaction thesis: a short hero entrance, restrained section reveals and real aircraft turntables with drag, angle slider and play/pause controls. Reduced-motion preference disables autoplay and offers deliberate single-frame steps; core content, technical disclosures and downloads work without JavaScript. The viewer loads only near the hangar, pauses offscreen/when hidden, and retains at most two decoded sheets.

Research, 2026-10-15: [NASA Quesst](https://www.nasa.gov/quesst-the-aircraft/) informed aircraft annotations and experimental status; [X-Plane](https://www.x-plane.com/) informed image-led feature rhythm; [RealFlight](https://www.horizonhobby.com/realflight/) informed the model/field/get-started navigation. These are composition references, not asset sources or endorsements.

WEB-02 extends the research with the [Boeing 777X](https://www.boeing.com/commercial/777x) product/gallery/specification sequence and [Airbus A350](https://www.aircraft.airbus.com/en/aircraft/a350) capability-led technical sections. The visual system keeps OpenRC's original typography and colors; no manufacturer design or aircraft assets are copied.

WEB-03 visual thesis: a quiet aircraft premiere, with sculpted studio light, deliberate camera movement and generous editorial space. The content sequence stays intact: aircraft-led opening, sponsor acknowledgment, hangar, downloads, field and technical depth. Interaction thesis: a slow studio camera arc, subtle scroll-linked depth in the opening/field, and a deliberate full-screen 3D inspection with camera presets. Native scrolling remains under the visitor's control.

Tool research: [model-viewer](https://modelviewer.dev/examples/loading/) provides an accessible, on-demand GLB inspector; [GSAP ScrollTrigger](https://gsap.com/docs/v3/Plugins/ScrollTrigger/) supports larger scroll timelines, but this page only needs bounded native transforms and intersection observers. Godot renders the actual project models. The optional inspector uses self-hosted model-viewer 4.4.0; no runtime 3D library is fetched until the visitor opens it.

WEB-04 visual thesis: the Ventage Jet leads the site, with wide studio views and deliberate close-ups of its canopy, wing and empennage. The existing sponsor → aircraft → download sequence remains; a compact detail study completes the hangar. Interaction thesis: a slow jet camera arc, manually selected close-up dissolves, and matching camera targets in the optional 3D inspector. [Boeing's detail-led presentation](https://www.boeing.com/commercial/777x/by-design) and [model-viewer's camera annotations](https://modelviewer.dev/examples/annotations.html) inform the approach. The inspector uses Khronos PBR Neutral tone mapping to retain material colors, based on [model-viewer's lighting guidance](https://modelviewer.dev/examples/lightingandenv/).

## Assets and scope

Aircraft renders are from [presentation media](../docs/media/README.md); field captures are from [LU-21](../docs/research/landscape-upgrade/LU-21/README.md). The current hangar uses turntable posters; `prepare_assets.py` generates field WebPs and a black Savox display WebP without changing their sources. Original media and its provenance remain authoritative. Fonts are freely licensed; bundled license files live alongside them. No remote font, analytics, application framework or paid asset dependency.

The six native model orbits have their own [capture pipeline and source-hashed manifest](TURNTABLES.md). The current Ventage Jet orbit reflects today's purple/orange builder, unlike the earlier blue/white/red still. The Bisonte image is the supplied studio render from `assets/source-deliveries/mt8-bisonte/MT8_Bisonte_entrega1_1/MT8_Bisonte/out/renders/01_tres_cuartos_delantero.png`; its [intake and permission](../research/rc-monster-truck/README.md#rcv-14a-mt8-visual-inspection) remain authoritative. [Brand sources and scope](BRANDS.md) document the official originals and resized Savox display copy. OpenAI support is a ChatGPT Pro subscription for open-source development; Codex is credited as an AI contributor. Savox's role is product-representation permission; catalogue integration remains planned.

The [cinema pipeline](CINEMA.md) creates the opening's 1600×1000 Ventage Jet poster, silent 12-second camera arc and three detail studies from the native aircraft builder. Automatic playback waits for the initial page load and two animation frames. The poster remains visible when motion is reduced, data saving is requested, the browser reports a 3G-or-slower connection, or playback is unavailable; visitors can deliberately play the clip. Playback pauses outside the opening, when the tab is hidden, and while the inspector is open. The retired Stik poster and MP4 are removed; its capture manifest remains for provenance.

The [browser model pipeline](MODELS.md) exports the six actual visual hierarchies to GLB, preserving visible node names, materials and embedded textures. The 1.07 MB model-viewer 4.4.0 module and a selected GLB (1.92–8.19 MB) load only after opening the inspector. A neutral studio environment is built in; no remote decoder or environment is fetched. Closing removes the viewer and its detached-model cache is disabled. These are visual presentations, not gameplay or physical validation.

## Preview and maintain

From the repository root: `python -m http.server 4173 --bind 127.0.0.1 --directory site`. Open `http://127.0.0.1:4173/`. The page uses relative asset URLs and works at GitHub's project subpath.

Regenerate images with Pillow 12.3.0 and `python site/prepare_assets.py`. Edit copy in `index.html` and its matching English translation in `main.js`. Update platform download links, version, checksums and sizes together after a release. Keep source-state claims separate from release contents and preserve experimental labels.

Additional WEB-02 copy and theme behavior live in `details.js`, presentation in `details.css`, and the orbit renderer in `viewer.js`. `main.js` owns catalogue/language/field selection. Keep all translations in sync with `data-i18n`, including dynamic viewer labels.

WEB-03 presentation lives in `cinema.css`, bounded page/film motion in `cinema.js`, and optional geometry inspection in `inspector.js`. The native modal supports Escape, focus restoration, camera presets, keyboard orbit and explicit zoom. Portrait camera framing differs from landscape framing. Changing aircraft cancels obsolete loads; loading failures preserve access to the existing turntable.

WEB-04 makes the jet the initial catalogue selection and adds direct inspector entries from the opening and the detail study. The study changes only on request; a failed image retains the last displayed view and its matching 3D entry. `assets/cinema/jet-views.json` supplies the three native camera targets in centered model coordinates. Camera moves respect reduced motion, and a failed camera-data request leaves overview, orbit and zoom available. Selecting another aircraft hides the jet-specific controls.

WEB-05 keeps the same composition while reducing work: preload the two opening fonts, show the hero poster immediately, cache scroll geometry between layout changes, and defer distant editorial rendering with `content-visibility: auto`. Intrinsic section sizes are estimates until first rendering; the browser then remembers measured sizes. The turntable schedules one animation callback per frame at its existing 125 ms interval, updates only angle UI per frame, cancels obsolete image loads, retries failed selections, and retains a two-sheet LRU cache. Language and theme changes avoid identical HTML/image assignments. Rebuild the black Savox display copy with `python site/prepare_assets.py --brands-only`.

HTML references styles/scripts with a shared release query (`?v=web08-seo-20261026`). Bump it when those files change so returning visitors do not combine cached JavaScript with new markup.

WEB-07 official identity, 2026-10-24: the header, hero, footer and README now use derivatives of the refined vector master based on the supplied official SVG. The favicon uses its RC contours, and Open Graph/Twitter metadata uses a 1200×630 PNG. [Source and regeneration](BRANDS.md#openrc-identity). The aircraft opening, navigation, translations and downloads retain their behavior. Local Chrome review covers 1920×1080, 390×844 and 320×740, both languages/themes, reduced motion, image loading and horizontal overflow. This is presentation verification, not a simulator release.

Publication uses a separate `gh-pages` branch with only the static website. GitHub Pages serves `/` from that branch; `.nojekyll` disables processing. The main working tree and its unrelated pending changes are never included in that publication. The website is a project showcase, not a browser build of the simulator.

The unpublished v0.1.2 draft refresh keeps download, first-launch and checksum links on the latest published v0.1.1 release, and labels the Settings, P-51 equipment and MONSTER CAR 2 highlights as current-source features. Archive sizes remain omitted. Local and public browser checks passed in English and Spanish: nonempty translated copy, no horizontal overflow, no broken images and no console warnings/errors. All 17 loaded local resource URLs returned HTTP 200. Public HTML and main.js match local SHA-256 values; all download URLs match the v0.1.1 release assets. Deployment `af902cc7e8e5370c731be2483639bc64c2986a7c` passed the [Pages workflow](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38917759203). No v0.1.2 package or public download is available.

The subsequent P51-22 update labels the Mustang's powered takeoff and loop acceptance as pending in both languages. Local and public aircraft-selection checks show the warning without horizontal overflow. Public HTML/main.js hashes match the local files; the browser reports no warnings or errors. Deployment `2e1475092c4a7a608fb30a63826c98cfda6622dd` passed [Pages](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38926987899). Download links still target v0.1.1.

Publish with `python site/publish.py --message "WEB-step: change; proof: completed checks"` after browser verification, replacing the message with the actual change and checks. It requires Git identity and an authenticated `gh` with repository admin access; it refuses to replace a different existing Pages source. Only HTML, sitemap XML, CSS, JS, favicon, `.nojekyll` and licensed assets are copied into a temporary checkout. No force push or changes to the working branch/index.

## Search metadata (WEB-08)

`index.html` owns the Spanish title, description, canonical URL, social preview and `SoftwareApplication` JSON-LD. `main.js` preserves those defaults and synchronizes the English title, descriptions and structured data when the visitor changes language. Keep metadata aligned with visible copy and the early-alpha status. Do not add fabricated ratings or claim eligibility for rich results: Google's [software-app guidance](https://developers.google.com/search/docs/appearance/structured-data/software-app) requires review/rating evidence that this site does not have.

`sitemap.xml` lists the single canonical page and ships through `publish.py`. Add only independently accessible, indexable pages; section fragments and local-storage language choices are not separate pages. The English translation currently shares the Spanish URL, so it has no separate `hreflang` entry. Separate translated URLs would be required for [localized-page annotations](https://developers.google.com/search/docs/specialty/international/localized-versions).

The [sitemap](https://bultodepapas.github.io/OpenRCsimulator/sitemap.xml) is linked from the page and can be submitted in Google Search Console for the project URL-prefix property. Submission and search-index coverage have not been verified. A project-level `robots.txt` would not control crawling: robots rules must live at the host root, `https://bultodepapas.github.io/robots.txt`, outside this deployment. That root returned 404 on 2026-10-26. See Google's [sitemap instructions](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap) and [robots.txt placement rules](https://developers.google.com/search/docs/crawling-indexing/robots/create-robots-txt).

WEB-08 local verification, 2026-10-26: Chromium checks passed at 1920×1080, 390×844 and 320×740, switching Spanish → English → Spanish and reloading the saved English preference. Titles, descriptions and JSON-LD stay consistent; no empty translations, broken loaded images, broken section links, horizontal overflow, page exceptions or HTTP errors were found. Spanish content, metadata, downloads and the sitemap link remain in static HTML without JavaScript. Asset references, sitemap XML, JSON-LD, JavaScript and publisher syntax passed. These checks do not establish search rankings or indexing.

Published WEB-08 deployment: `1ed14df22f1553cdb1b617475e9fcf10eb73807a`; GitHub Pages reports `built`. The same browser checks passed on the public URL. Public HTML, `main.js` and `sitemap.xml` return HTTP 200 and match local bytes. A fresh `gh-pages` clone resolves static asset references and includes the sitemap and `.nojekyll`, without simulator files.

## WEB-01 verification — 2026-10-15

Browser checks: 1440×1000 desktop and 390×844 mobile; all five aircraft select and load, one selection at a time; day/night images load; Spanish/English copy and aircraft metadata switch; no missing translations, broken fragment links or horizontal document overflow. Reduced motion is respected. JavaScript syntax and local asset references pass; browser console has no warnings/errors. Lighthouse snapshot after the logo accessibility correction: accessibility 100, best practices 100, SEO 100; 33 audits passed, zero failed. This is not a performance audit or simulator validation.

Total bundled assets are approximately 416 kB; all runtime assets are local. Downloads and exact archive sizes were checked against GitHub's v0.1.1 release API. The design and preparation tools do not require changes to simulation tests or golden flights.

Published at [OpenRC Simulator](https://bultodepapas.github.io/OpenRCsimulator/), deployment commit `58445beabe2c8fd20459e7445ce2db1aead74474`. A fresh `gh-pages` clone passes local asset resolution and contains `.nojekyll`, with no simulator files. Public HTML/CSS/JS and sampled image/font SHA-256 hashes match local files. All five aircraft, both locales and the night image were exercised on the public URL, with no console warnings/errors. GitHub reports Pages status `built`.

## WEB-02 verification — 2026-10-15

Six actual model turntables × 36 angles (216 views), plus six matching posters. All sheets decode and views at 0°/180° differ for every model. The angle slider also passes a native keyboard ArrowRight check. Play advances frames; pause holds the angle. Reduced motion suppresses autoplay. A failed sheet retains the static model and an explicit localized fallback message.

An intentionally failed first manifest request displayed the static fallback; selecting another model retried successfully without reloading. Offscreen rotation holds its frame. Reduced-motion stepping has no toggle state, and the partner's accessible name follows the selected language.

Reviewed 1440×1000 desktop and 390×844 mobile compositions, including the sponsorship panel, hangar and technical sections. At 320×740, both languages × both themes have no horizontal document overflow. Official black/white logos load in the corresponding themes. All 161 translated static elements have content; the six catalogue entries, viewer labels and theme control also localize. Native details elements expose seven technical areas. Local file references and JavaScript syntax pass.

Lighthouse snapshots: desktop and mobile accessibility 100, best practices 100, SEO 100, 38 passed and zero failed. These are not performance scores. Runtime assets total approximately 3.27 MB including all six lazily loaded sheets, fonts and original brand variants; the viewer bounds decoded sheets to two. The latest release was checked as v0.1.1 before publication. Simulator code, physics data and golden flights were not edited.

Published WEB-02 deployment: `ef114a08b7d860d499ad5f671bd8646eca390c33` ([successful workflow](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38780742254)). A fresh deployment clone resolves versioned asset URLs. Public HTML, scripts, styles, manifest and sampled SVG match local source after normalizing Git line endings; the helicopter sheet matches by SHA-256. The public viewer loads the helicopter and switches language/theme without console warnings or errors. The deployed HTML references the current `web02-2` asset version.

## WEB-03 verification — 2026-10-15

The cinema poster and loop were visually reviewed; the encoder probe confirms H.264, 1280×800, 24 fps, 288 frames, 12 seconds and no audio. Browser playback advances, pauses on command and holds its time offscreen. With reduced motion enabled at navigation, no MP4 is requested; deliberate playback still works. The browser requests no third-party resources.

All six GLBs load and render in the optional inspector. Reviewed desktop 1440×900 and mobile 390×844/320×740, including aircraft framing and camera presets. Keyboard Tab reaches the model; ArrowRight changes the camera, zoom decreases its radius, and Escape restores focus to the launcher, unlocks scrolling and removes the viewer. A deliberately rejected model fetch shows the localized fallback; selecting another model recovers without reload. Switching models in the inspector does not fetch hidden turntable sheets; closing loads the selected sheet when visible.

The initial page requests neither model-viewer nor a GLB. The shipped assets total 33.70 MB, dominated by the six optional models; this is not the initial page transfer. At 320×740, both languages and both themes have no horizontal overflow or missing translated content. Reduced motion removes scroll depth and camera interpolation. Scripts pass syntax checks; 45 IDs are unique and all 74 HTML references resolve. Normal browsing has no console warnings or errors.

Lighthouse snapshots after correcting small-label contrast: desktop/light and mobile/night score 100 for accessibility, best practices and SEO, with 38 audits passed and zero failed. Inspector snapshots on desktop and mobile also score 100 in those categories, with 27 passed and zero failed. These are not performance audits or simulator validation. No runtime geometry, physics or golden-flight files were changed by WEB-03.

Published deployment: `f8f97c79c1c563950047e2e3d33d525490bfc371` ([successful Pages workflow](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38783996490)). A fresh `gh-pages` clone resolves all static references and includes the six GLBs and `.nojekyll`, without simulator files. Public HTML, cinema CSS/JS, inspector, catalogue script, poster, MP4, Stik GLB and vendored module match local SHA-256 values (text line endings normalized). The public opening plays, initially requests no GLB/module, opens the Stik in 3D, and returns with Escape without console warnings or errors.

## WEB-04 verification — 2026-10-15

The jet is first in the opening, catalogue and inspector. Reviewed the native poster at 1440×1000, 1024×768 and 390×844; the tablet composition preserves the nose, and the mobile film control remains separate from the two actions. At 320×740, both languages and both themes have no horizontal overflow or overlapping opening controls. All 184 translated elements have content.

The three detail images load and update their accessible names, selection and matching 3D entry. Keyboard Enter selects a view. A deliberately failed image decode retains the previous image and camera entry; rapid choices settle on the latest selection. The inspector returns focus to the corresponding opening/detail launcher on Escape, removes its model on close and hides the detail controls for other aircraft. A simulated first camera-data failure keeps overview/orbit/zoom usable; reopening retries successfully without reloading the page.

Camera targets, radii and fields of view were checked in the live viewer, including portrait framing and overview reset. Explicit field-of-view bounds avoid model-viewer's initial 30° maximum clamping the native 38°/36°/34° detail presets. The 12-second, 1280×800 silent jet clip plays, pauses offscreen and pauses while inspecting; no GLB or model-viewer module loads on initial entry. Reduced motion retains deliberate controls and suppresses automatic motion.

JavaScript syntax and all 20 local HTML asset references pass. Browser console has no warnings or errors. Lighthouse snapshots score accessibility 100, best practices 100 and SEO 100 on desktop and mobile (38 passed, zero failed); the mobile inspector also scores 100 (27 passed, zero failed). These are not performance audits or physical validation. WEB-04 changes presentation and its native capture pipeline; no simulator runtime or physics files were edited by this track.

Published deployment: `aa2c2cc2b0095b5523646ddc02ea77a3b4e14f3c` ([successful Pages workflow](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38799929595)). A fresh `gh-pages` clone resolves all static references and contains six GLBs, seven jet cinema files and `.nojekyll`, without simulator files. Public HTML, changed styles/scripts and all seven jet files match local SHA-256 values (text line endings normalized). The public opening plays with the jet selected and no initial GLB request; the tail study opens its matching 3D camera, Escape restores focus, and the console remains free of warnings and errors.

CTA follow-up: `web04-2` replaces the opening label with “Descargar” / “Download”, retaining the platform-download target. Both locales were verified locally and publicly. Deployment `b821e2fb152e3201479a91d80588f75a16999811` completed in the [Pages workflow](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38801925068).

## WEB-05 verification — 2026-10-15

Performance decisions follow web.dev's guidance on [layout thrashing](https://web.dev/articles/avoid-large-complex-layouts-and-layout-thrashing), [LCP render delay](https://web.dev/articles/optimize-lcp) and [content visibility](https://web.dev/articles/content-visibility). Cold Chrome traces used localhost, a 390×844 mobile viewport, Fast 3G network throttling, 4× CPU throttling and normal motion. The baseline reported 937 ms of forced layout attributed to `updateDepth`; the final trace no longer reports that insight. Baseline/final LCP samples were 5,473/4,468 ms, both with CLS 0. A browser restart and variable full-document layout cost affected intermediate runs, so these are diagnostic lab samples, not a reliable speedup percentage or field-performance claim.

On the same unthrottled 120 Hz browser, instrumentation over two seconds counted 241 turntable animation callbacks before and 15 callbacks/15 draws after (94% fewer callbacks at the same intended eight-frame-per-second cadence). Pausing produced zero callbacks and draws in 500 ms. Savox black/white transfers fell from 90,980/86,285 bytes to 10,180/10,190 bytes. Each derivative is 768×261 instead of 4167×1417, reducing nominal RGBA decoded size from 23.6 MB to 0.8 MB; original PNGs remain preserved.

All six aircraft load. Deferred-manifest rapid selection requested only the final jet sheet; a deliberately failed Extra sheet decode retained the poster and recovered on same-model reselection. Reduced motion holds the angle, while explicit stepping and native slider keyboard input still work. With a controlled 3G connection signal the page requests no MP4 automatically; explicit play succeeds. The optional jet inspector loads, selects its wing camera, pauses the film, and closes with Escape.

Desktop 1440×1000 and mobile 390×844 were reviewed. At 320×740, both languages × both themes have no horizontal overflow or missing copy among 184 translated elements; the opening keeps “Descargar” / “Download” and its download target. Native technical/partner/download anchors remain aligned after deferred section rendering; field switching and scroll depth work. JavaScript syntax, the asset-preparation Python syntax, all 22 local HTML references and transparent Savox variants pass. Clean-page console checks report no warnings or errors. Desktop/mobile Lighthouse snapshots score 100 for accessibility, best practices and SEO (38 passed, zero failed); these are not performance scores.

Published deployment: `7fb6ee884f36370c1efa30a5aa0fd331de0550a5` ([successful Pages workflow](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38805787288)). A fresh `gh-pages` clone resolves all 22 static HTML references and contains six GLBs and `.nojekyll`, without simulator files. Public HTML, all five scripts, all three stylesheets and both Savox WebP files match local SHA-256 values (text line endings normalized). The public jet film plays, then pauses outside the opening; its turntable advances and holds its angle on pause. Both locales, night-theme logo and download label work, with no initial GLB/module request or console warnings/errors.

Release-status update, 2026-10-16: source `0fd2632b` keeps v0.1.1 downloads and
identifies the Stik recovery, R02 yaw and experimental P51-22 checks as open work
toward v0.1.2. The draft-notes link replaces the unpublished release link. Local
390×844 and 1280×900 checks cover both languages, no horizontal overflow and no
console errors; the desktop notice was visually reviewed. Deployment
`658611dbb1590978c2ed334ac453953a1cb560d4` passed the
[Pages workflow](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38946280463).
The public page serves `source-20261016-release-work`, displays the Spanish status
notice, has no unpublished v0.1.2 asset/tag links, and reports no console errors.
This publishes website status only, not a simulator release or physical qualification.

Stable-preparation site refresh, 2026-10-16: the public page now serves
`source-20261016-stable-preparation`. It keeps all three desktop downloads and
`SHA256SUMS` on v0.1.1, links the preparation notice to
`docs/releases/v0.1.2.md` on `main`, and states in English and Spanish that open
experimental-aircraft checks do not block the stable software release. The page
still labels v0.1.2 as in preparation. Public browser checks at 390×844 and
1280×900 in both languages found no horizontal overflow or console errors; the
release-notes link returned HTTP 200. Deployment
`0e56ef4ad43d736dbb273344402d61ee6f9a0daf` passed the
[Pages workflow](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38956887159).
The v0.1.2 stable packages are now published; the preparation-page deployment is retained above as history.

Published v0.1.2 refresh, 2026-10-16: deployment
`fdda436a6f53058fb7af09bc3b35ffa08beba9a6` passed the
[Pages workflow](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/38965585237).
The public page serves `stable-v012-20261016`, links all three platform packages
and `SHA256SUMS` to v0.1.2, and identifies the remaining experimental-aircraft
limits in both languages. Public browser checks at 1280×900 and 390×844 in
English and Spanish found no horizontal overflow, console warnings or errors.
A cache-refresh request returned HTTP 200 with the published release links.


## WEB-06 — Manufacturer acknowledgments, 2026-10-17

The README and partner section credit Savox, SonicModell and Hitec within their product-representation permission scopes. Official SonicModell and Hitec logos are retained unchanged; [brand provenance and permission scope](BRANDS.md) remain authoritative. The website uses three responsive columns, a single-column mobile layout, Spanish/English copy and both themes. Integration remains planned/pending and no physical validation is claimed.

2026-10-24 update: the partner section and project README add scoped text acknowledgments for FLYWING, GEMFAN, KONTRONIK and Leomotion Drives, plus REVOC Custom's community support and Aloft Hobbies' forum sharing. [The permission summary](BRANDS.md) records each limit. No additional logo or product asset was introduced.

Later on 2026-10-24, the Savox tiles switched to the official orange-and-black variant for light backgrounds. The prepared WebP trims excess transparent canvas while retaining clear space; [brand provenance](BRANDS.md) records the source and preparation.
Visual review at 1920×1080 and 390×844 checked the support logo strip and partner section: Savox, SonicModell and Hitec load, remain in order and have comparable visual scale. The mobile page has no horizontal overflow. The desktop partner row was also reviewed in night mode. Review screenshots stayed outside the Git repository.

2026-10-24 logo follow-up: the partner section and README now show the official FLYWING and REVOC Custom logos within their written acknowledgment scopes. GEMFAN, KONTRONIK, Leomotion Drives and Aloft Hobbies remain linked by name because their correspondence does not expressly permit logo use.
Visual review at 1920×1080 and 390×844 confirmed that all five logos load in order; the two additional logos stack on mobile and the page has no horizontal overflow. Review screenshots remain outside the Git repository.

Verification: JavaScript syntax checks passed. Browser checks at 1280×900 and 390×900, both languages × both themes, found three decoded logos, no missing translations and no horizontal overflow. Desktop/day and mobile/night captures were visually reviewed. Console: zero errors or warnings. The eight partner captures are retained in [site media evidence](../docs/media/site/).

WEB-06 support-strip refinement: centered the support content at a maximum 1280 px, enlarged development credits, replaced the single tiny Savox introduction with all three official logos and a clear partner link. Verified 3714, 1280 and 390 px widths × ES/EN × day/night: no overflow, missing translations or failed logo decodes. Desktop and mobile night captures were visually reviewed; [desktop](../docs/media/site/support-desktop.png) and [mobile](../docs/media/site/support-mobile.png) captures are retained.

## WEB-07 — v0.1.7 release page preparation, 2026-10-20

Prepared Spanish and English release copy from `docs/releases/v0.1.7.md`. The page links the three platform archives, `SHA256SUMS`, first-launch guide and release notes to tag v0.1.7. It identifies the release as stable software for an early-alpha simulator, retains the open Stik sideslip and R02 yaw checks, and removes the superseded P51-22 pending-acceptance claim. ZIP signing and macOS notarization limits are stated accurately. Local Chrome checks of both languages show the expected URLs and no console warnings or errors. At 390×844, the page has no horizontal overflow; the opening and download section were visually reviewed. The v0.1.7 tag and assets are not public yet, so those external URLs and the deployed page remain unverified.

## WEB-07 — public v0.1.7 deployment, 2026-10-21

The [tag CI](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/39583319215) passed every job and published the [stable release](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.7). The downloaded `SHA256SUMS` file matches its published SHA-256 digest, and its three ZIP hashes match the corresponding release-asset digests. [Pages deployment](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/39597561362) succeeded at `ee4833792a61a19c7683566f1a4eaf1fad0ef0db` on `gh-pages`.

The public Spanish and English pages show all four v0.1.7 download links, the tagged first-flight guide and release notes. All six release links returned HTTP 200. Chrome at 390×844 showed no horizontal overflow or empty translations, and no console warnings or errors. The opening and download section were visually reviewed on the public page.

## WEB-07 — v0.1.8 release page, 2026-10-24

Updated the Spanish and English release copy from `docs/releases/v0.1.8.md`: version labels, highlights (F4U Corsair, Scene detail, 3D field trees and far woods, optional High profile), the three platform archives, `SHA256SUMS`, first-launch guide and release notes on tag v0.1.8, and the `release-v018-20261024` asset query. The open Stik sideslip and R02 yaw checks remain listed. All six release links returned HTTP 200. Local Chromium at 1440×1000 and 390×844, both languages: no horizontal overflow, no empty translations, no remaining v0.1.7 text and no console warnings or errors; the mobile download and release sections were visually reviewed.
