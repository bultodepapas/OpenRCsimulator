# UI-16 · Update notice

**Date:** 2026-10-12. **Status:** implemented, software-verified and shown by an exported Linux build against the real GitHub API under Xvfb; native Windows/macOS launch of the exported notice is pending (DT-12 rehearsal). **Plan:** [MENU-PLAN](../../../MENU-PLAN.md#delivery-evidence). **Owner request (Spanish):** a small, elegant, unobtrusive notice when the player's version is old and a newer one is available, for the three platforms; manual update is acceptable.

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
- **Nothing moves, nothing waits.** The card hangs from Home's top-right anchors over the backdrop, so the column and the Fly focus are untouched; the request runs on a thread with a 10 s timeout and a 2 MB body limit.
- **Privacy.** One anonymous request; the `User-Agent` names the app version and OS, as GitHub requires a user agent. No account, no telemetry. `[updates] check=false` turns it off; the Settings screen (UI-24) will expose it.
- **Trust.** The API answer is data: only release-page URLs under the project are opened; the browser, not the app, downloads the ZIP next to its checksums.

## Proof

| Check | Result |
| --- | --- |
| `tests/test_update_check.gd`: parsing, 21 versions ordered pairwise (441 comparisons), selection with the real fixture and a mixed synthetic list, cache file round trip and corruption, the daily rule, headers; the checker end to end against a local fake of the API (200 → notice, +1 h cached, +25 h ETag → 304, Hide, a newly published rc8, running rc8, offline) | 53 checks pass, exit 0, no engine errors |
| `tests/test_ui_update_notice.gd`: the card (EN/ES texts, contrast ≥ 4.5:1 on its surface, anchors, Fly keeps focus, Enter on Download/Hide with real key events); the interactive route (development run never checks; fake API → card over Home; Download through `app_root`; Home → Fly → End flight keeps the card; Hide remembered in the cache; `[updates] check=false` makes no request) | 24 checks pass, exit 0 |
| The 24 shell, preferences and input tests that could see this change (`test_ui_*`, `test_controls_reference`, `test_field_integration`, `test_treeline`, `test_e2e_input`, `test_e2e_radio`, `test_build_info` and the two above), run one after another with nothing else on the machine | 24/24 pass. A first pass run while a direct-route smoke was flying in parallel failed two wall-clock/`user://` checks (`test_ui_help` hint timing, `test_ui_runway` file comparison); both pass alone, as [LEARNINGS](../../../learnings/runtime-and-delivery.md#godot-execution-and-test-isolation) warns about concurrent Godot runs |
| `app/test.sh` (full headless suite) | Import, generator, float64 guard, shader and parse checks of every script pass; the runner then stops at the pre-existing `test_atmosphere_flight.gd` failure (`reset recomputes a fresh trim for the extreme density`, a physics check that does not touch the shell, already recorded as the baseline failure in [UI-06d](../UI-06d/README.md) on 2026-10-11), before the UI tests in alphabetical order. Hence the subset run above |
| Direct route `-- --trace=… --t=3` | Trimmed level flight (720 ticks, 3.000 s, all samples finite), no engine error, no update cache file in the user data folder: the check never runs on technical routes |
| Captures under Xvfb (software OpenGL, `tests/capture_ui.gd --screen=home --update=v0.1.0-rc8`) | [EN 1280×720](ui-home-update-en-1280.jpg), [ES 1280×720](ui-home-update-es-1280.jpg), [EN 1920×1080](ui-home-update-en-1920.jpg); SHA-256 in [captures.sha256](captures.sha256) |
| **Exported Linux build, real GitHub API.** `--export-release Linux` with the `OPENRC_BUILD_*` identity of this tree (`v0.1.0-rc6-58-gc9d302e-dirty`: the local clone's newest tag is rc6), run under Xvfb with an isolated `XDG_DATA_HOME` and no environment override, screen read from the Xvfb framebuffer after 20 s | The card says **Update available: 0.1.0-rc7** over Home ([screen](ui-home-update-export-real-rc7.jpg)); the cache the build wrote ([export-real-update_check.cfg](export-real-update_check.cfg)) records `200 ok`, GitHub's ETag and `latest tag v0.1.0-rc7`, so TLS, gzip, parsing and the daily rule all work from the exported engine; no engine error in the log |
| Exported Linux build, `OPENRC_UPDATE_URL` at a local static list with an added rc8 | Card **0.1.0-rc8** ([screen](ui-home-update-export-fake-rc8.jpg)); the server log shows the single `GET /releases?per_page=10`; cache `latest tag v0.1.0-rc8` |

The captures show the card at x = 821 on a 1280-wide Home (right of the 440 px column), the Spanish sentence on one line, and the same card at 1080p without scaling (UI-23 owns scaling). The exported-build screens also show, unrelated to UI-16, that the UI-06d default weather summary (`1.5 m/s · 090° +0.6 + Turbulence · Evening, time passing`) widens Home's column past its 440 px panel; that belongs to the menu track's layout work (UI-25).

## Limits and next steps

- Linux only: the exported-build proof ran on this Ubuntu VM with software OpenGL. No native Windows/macOS launch of an exported build with the notice yet; DT-12 should include one launch of an older exported build after a newer tag exists, on each platform, and a click on Download (the browser hand-off is untested here: `OS.shell_open` was replaced by a seam in the tests).
- The 24 h rule depends on the system clock; a clock set back only causes one extra check.
- The macOS bundle is not notarized and Windows has no signature, so the downloaded update meets the same first-launch warnings as the first download.
- Open for the owner: a stable/rc channel preference once a release exists; exposing the toggle in UI-24 Settings; a toast restyle with motion in UI-28.
