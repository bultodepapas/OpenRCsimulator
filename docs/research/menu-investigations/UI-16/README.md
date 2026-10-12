# UI-16 · Update notice

**Date:** 2026-10-12. **Status:** implemented, software-verified and shown by an exported Linux build against the real GitHub API under Xvfb; reviewed independently and repaired (UI-16-R1, below); native Windows/macOS launch of the exported notice is pending (DT-12 rehearsal). **Plan:** [MENU-PLAN](../../../MENU-PLAN.md#delivery-evidence). **Owner request (Spanish):** a small, elegant, unobtrusive notice when the player's version is old and a newer one is available, for the three platforms; manual update is acceptable.

## What was built

- `app/app_state/update_check.gd`: pure rules. SemVer parsing and precedence (digit runs inside a prerelease identifier compare numerically, so `rc7 < rc10`; build metadata `+5.gabc1234.dirty` never orders), the release to offer (drafts and unparsable tags skipped; a release build is never offered a prerelease), the notice from the cached state, the cache file `user://update_check.cfg`, the once-a-day rule, request headers and answer parsing.
- `app/app_state/update_checker.gd`: the one network request. Announces a cached newer release at once, asks the list-releases endpoint when a day has passed, sends the cached ETag (304 keeps the cached answer), writes the cache, prints one line on failure and never shows a dialog or blocks Home.
- `app/ui/update_notice.gd` and the `Notice` theme variation: a card at Home's top right, outside the column, with the version, **Download** (the release page in the browser through `OS.shell_open`; only `https://github.com/bultodepapas/OpenRCsimulator/` URLs are accepted, anything else falls back to the releases page) and **Hide** (that tag is remembered; a newer one shows again). It never takes the focus from Fly; both buttons are reachable with the keyboard.
- `app_root.gd`: creates the checker after Home on the interactive route only when the preference allows it and the build is an export (a development run checks only when `OPENRC_UPDATE_URL` names a source); re-shows the notice on the Home rebuilt after End flight. Preferences gain `[updates] check` (default true). Spanish strings in `i18n/es.po`. `tests/capture_ui.gd --update=<tag>` renders the card.

Updating stays manual: the release page carries the three ZIPs, `SHA256SUMS` and the notes, and the macOS/Windows trust warnings of [FIRST-LAUNCH](../../../FIRST-LAUNCH.md#2-first-launch) apply to the new download as to the first. In-app download and replace needs the signing, notarization and installers of DT-09.

## Facts checked against the live API and engine (2026-10-12)

| Fact | Evidence |
| --- | --- |
| `GET /repos/bultodepapas/OpenRCsimulator/releases/latest` answers **404**: every published release (rc1…rc7) is a prerelease and GitHub documents latest as the newest non-prerelease, non-draft release | `curl` headers, `x-ratelimit-limit: 60`; [GitHub REST docs](https://docs.github.com/en/rest/releases/releases?apiVersion=2022-11-28) |
| `GET …/releases?per_page=10` lists the seven prereleases with their ZIP assets and `html_url` | [fixture](../../../../app/tests/fixtures/github_releases.json) (trimmed copy of the answer) |
| A conditional request with `If-None-Match: <ETag>` answers **304** with no body, but `x-ratelimit-used` still increments | curl and the Godot probe below: used 1 → 2 → 3 → 4 |
| Unauthenticated limit: 60 requests per hour per address | [Rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api); one request a day per player is far below it |
| The pinned headless Godot 4.7.2 completes HTTPS to `api.github.com` with its bundled CA set, decodes the gzip body (93 781 bytes, 690 ms) and gets 304 on the ETag retry (412 ms), with `use_threads` true and false | probe `probe_update.gd` (scratchpad) run twice; the engine docs say exported projects carry Mozilla's bundle and use the OS store first ([TLS certificates](https://docs.godotengine.org/en/stable/tutorials/networking/ssl_certificates.html)) |
| `HTTPRequest.request()` from `SceneTree._initialize()` fails with `ERR_UNCONFIGURED` (not inside the tree yet); one frame later it works | first probe run |

## Design choices

- **Once a day, by time.** The cache stores the last successful check; failures keep the old date so the next launch tries again. The ETag is kept for bandwidth, not for rate limits.
- **Channels.** A prerelease build (every build so far) sees the newest prerelease or release; a release build sees only releases. A CI build between two tags (`0.1.0-rc7+12.gabc1234`) counts as its tag.
- **Nothing moves, nothing waits.** The card hangs from Home's top-right anchors over the backdrop, so the column and the Fly focus are untouched; the request runs unthreaded (a little per frame, never a thread join), with a 10 s timeout and a 2 MB body limit.
- **The cache belongs to one build.** `for_version` records the build the selection was made for; another build starts from a fresh answer, keeping only the hidden tag. `notice()` also refuses a prerelease to a release build on its own, whatever the cache says.
- **Privacy.** One anonymous request; the `User-Agent` names the app version and OS, as GitHub requires a user agent. No account, no telemetry. `[updates] check=false` turns it off; the Settings screen (UI-24) will expose it.
- **Trust.** The API answer is data: only release-page URLs under the project are opened; the browser, not the app, downloads the ZIP next to its checksums.

## Proof

| Check | Result |
| --- | --- |
| `tests/test_update_check.gd`: parsing (including 20-digit components), 21 versions ordered pairwise (441 comparisons), selection with the real fixture and a mixed synthetic list, the notice rules (hidden, untrusted or unsafe URL, capital V, cached prerelease vs release build, `state_for`), cache file round trip and corruption, the daily rule, headers; the checker end to end against a local fake of the API (200 → notice, +1 h cached, +25 h ETag → 304, Hide, a newly published rc8, a withdrawn rc8, another build's cache, a 403 that waits a day, a silent server that times out at 2 s with frames running, offline) | 65 checks pass, exit 0, no engine errors |
| `tests/test_ui_update_notice.gd`: the card (EN/ES texts, contrast ≥ 4.5:1 on its surface, anchors, Fly keeps focus, Enter on Download/Hide with real key events, focus back on Fly after Hide); the interactive route (development run never checks; fake API → card over Home; Download through `app_root`; a browser that cannot open is reported on Home; withdraw/announce wiring; Home → Fly → End flight keeps the card; Hide remembered in the cache; `[updates] check=false` makes no request) | 28 checks pass, exit 0 |
| The 24 shell, preferences and input tests that could see this change (`test_ui_*`, `test_controls_reference`, `test_field_integration`, `test_treeline`, `test_e2e_input`, `test_e2e_radio`, `test_build_info` and the two above), run one after another with nothing else on the machine | 24/24 pass. A first pass run while a direct-route smoke was flying in parallel failed two wall-clock/`user://` checks (`test_ui_help` hint timing, `test_ui_runway` file comparison); both pass alone, as [LEARNINGS](../../../learnings/runtime-and-delivery.md#godot-execution-and-test-isolation) warns about concurrent Godot runs |
| `app/test.sh` (full headless suite) | Import, generator, float64 guard, shader and parse checks of every script pass; the runner then stops at the pre-existing `test_atmosphere_flight.gd` failure (`reset recomputes a fresh trim for the extreme density`, a physics check that does not touch the shell, already recorded as the baseline failure in [UI-06d](../UI-06d/README.md) on 2026-10-11), before the UI tests in alphabetical order. Hence the subset run above |
| Direct route `-- --trace=… --t=3` | Trimmed level flight (720 ticks, 3.000 s, all samples finite), no engine error, no update cache file in the user data folder: the check never runs on technical routes |
| Captures under Xvfb (software OpenGL, `tests/capture_ui.gd --screen=home --update=v0.1.0-rc8`) | [EN 1280×720](ui-home-update-en-1280.jpg), [ES 1280×720](ui-home-update-es-1280.jpg), [EN 1920×1080](ui-home-update-en-1920.jpg); SHA-256 in [captures.sha256](captures.sha256) |
| **Exported Linux build, real GitHub API.** `--export-release Linux` with the `OPENRC_BUILD_*` identity of this tree (`v0.1.0-rc6-58-gc9d302e-dirty`: the local clone's newest tag is rc6), run under Xvfb with an isolated `XDG_DATA_HOME` and no environment override, screen read from the Xvfb framebuffer after 20 s | The card says **Update available: 0.1.0-rc7** over Home ([screen](ui-home-update-export-real-rc7.jpg)); the cache the build wrote ([export-real-update_check.cfg](export-real-update_check.cfg)) records `200 ok`, GitHub's ETag and `latest tag v0.1.0-rc7`, so TLS, gzip, parsing and the daily rule all work from the exported engine; no engine error in the log |
| Exported Linux build, `OPENRC_UPDATE_URL` at a local static list with an added rc8 | Card **0.1.0-rc8** ([screen](ui-home-update-export-fake-rc8.jpg)); the server log shows the single `GET /releases?per_page=10`; cache `latest tag v0.1.0-rc8` |
| **After UI-16-R1** (unthreaded request, frame-counted timeout): exported Linux build `v0.1.0-rc6-67-gf0d1442-dirty`, real GitHub API, same Xvfb procedure | Card **0.1.0-rc7** again ([screen](ui-home-update-export-real-rc7-r1.jpg)); [cache](export-real-update_check-r1.cfg) records `200 ok`, the ETag, `for_version 0.1.0-rc6+67.gf0d1442.dirty`, `latest v0.1.0-rc7`, `prerelease true` |

The captures show the card at x = 821 on a 1280-wide Home (right of the 440 px column), the Spanish sentence on one line, and the same card at 1080p without scaling (UI-23 owns scaling). The exported-build screens also showed, unrelated to UI-16, that the UI-06d default weather summary widened Home's column past its 440 px panel; repaired in [UI-06d-R1](../UI-06d-R1/README.md).

## UI-16-R1 · Independent review and audit (2026-10-12)

A second agent reviewed the code without the author's conclusions, with read-only probes on the pinned engine. The owner also asked for an audit with pictures: [audit/](audit/captures.sha256) holds 16 captures (Home with each of the five catalog aircraft and the card, EN/ES; Help EN/ES; pause; the first flight with its hint; the weather editor; Home at 1080p). The card is identical with every aircraft, shows only on Home, and sits at the corner without scaling at 1080p.

| Finding | Severity | Repair |
| --- | --- | --- |
| `use_threads = true` runs the worker in blocking reads: a peer that accepts and then stays silent makes the 10 s timeout and the quit path wait forever on the thread join (reproduced by the reviewer with a silent server: main thread in `futex_wait`, process killed after 22 s) | bug, high | Unthreaded request (non-blocking per frame); `timeout_s` seam; `fake_releases.gd` gains `silent`; test: timeout fires at 2 s, frames keep running, next launch retries |
| The cache stored a selection made for one build while the ETag validates the list: after installing a release build, 304 kept offering the prerelease the rc build had cached (and the reverse) | bug, medium | `for_version` in the cache; another build starts fresh (`state_for`); `latest_prerelease` stored; `notice()` never offers a prerelease to a release build; tests |
| A 20-digit core component saturates `int()` with an engine `ERROR:` line on every launch and parses as the newest release | bug, low | Components longer than 18 digits are rejected; test |
| HTTP error statuses (403 rate limit, 404, 5xx) were retried on every launch | risk | Any HTTP answer records the date (one try a day); transport errors still retry next launch; test with a 403 |
| `OPENRC_UPDATE_URL` reached `request()` unvalidated (engine error on a bad scheme) | risk | Only `http(s)://` sources are accepted, else one console line |
| Frame-count caps in the tests are not seconds (145 fps headless) | risk, tests | Wall-clock caps of 15 s |
| Found while re-testing the unthreaded request on the exported build: `HTTPRequest.timeout` is wall clock, and the long first frames of a cold start (shader compilation, scenery under software OpenGL) spent the 10 s before the request had run; the real-API run ended in `transport error 13` ([cache](export-real-update_check-r1-wallclock-timeout.cfg)) | bug, medium | The engine timeout is off; the checker counts processed frames in `_process`, each capped at 50 ms, so a stalled frame costs 50 ms of the budget instead of its whole length; the silent-server test still times out at 2 s |
| Nits: no withdrawal when a fresh answer says nothing is newer; `V` prefix shown; `hide_update()` unused; checker started without a Home (field errors); browser error dropped; raw URL to `shell_open`; focus lost after Hide | nit | Withdrawal signal hides the card; `V` trimmed; `hide_update()` now called; guard on `home == null`; a note on Home when the browser cannot open; URLs with whitespace/control/quote characters fall back to the releases page; Hide returns the keyboard to Fly |

Found correct by the review: API names and Callable use, signal names, SemVer table, selection rules on fresh answers, cache typing and fallbacks, request lifecycle and `_announced_tag`, privacy (what leaves the machine), the preference and theme hooks, translation and test isolation. The reviewer's probes live outside the repository.

Observations outside UI-16 from the audit pictures: the P-51 and Avanti status notes pushed the CONTROLS legend below 720 px, and the UI-06d default weather summary widened the column past its panel. Both were repaired the same day in [UI-06d-R1](../UI-06d-R1/README.md).

## Limits and next steps

- Linux only: the exported-build proof ran on this Ubuntu VM with software OpenGL (repeated after UI-16-R1 with the unthreaded request: see the last proof row). No native Windows/macOS launch of an exported build with the notice yet; DT-12 should include one launch of an older exported build after a newer tag exists, on each platform, and a click on Download (the browser hand-off is untested here: `OS.shell_open` was replaced by a seam in the tests).
- The 24 h rule depends on the system clock; a clock set back only causes one extra check.
- The macOS bundle is not notarized and Windows has no signature, so the downloaded update meets the same first-launch warnings as the first download.
- Open for the owner: a stable/rc channel preference once a release exists; exposing the toggle in UI-24 Settings; a toast restyle with motion in UI-28.
