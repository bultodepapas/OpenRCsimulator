# Telemetry final pre-release review — 2026-11-18

**Audit baseline:** `main` at [0a45e8c6ba2484607c38cb2a9c2e3b8927be5462](https://github.com/bultodepapas/OpenRCsimulator/commit/0a45e8c6ba2484607c38cb2a9c2e3b8927be5462) (UTC commit 2026-11-18 23:38).  
**Scope:** read-only product telemetry review: admission, consent UI, i18n, collection and data quality, delivery, release export, receiver, test evidence.  
**Isolation:** this is a new documentation file on `audit/telemetry-release-readiness-20261118`. No application code, schema, translation, receiver, build workflow, binary, tag, or release was changed by this audit.

## Executive disposition

**Client implementation: substantially complete; live-release activation: NOT READY / NOT PROVEN.** The implementation is deliberately dormant on source, headless, technical and ordinary unconfigured exports. The repository's own [master plan](../../../plans/telemetry.md) expressly states that no production receiver has been deployed and no build offers production telemetry; that must be reconciled with operational evidence before claiming the next release will send data. An exact-tag export will only admit it when the packaging workflow receives all three `OPENRC_TELEMETRY_ENDPOINT`, `OPENRC_TELEMETRY_OPERATOR`, `OPENRC_TELEMETRY_CONTACT` values and the receiver accepts that same release ID.

This finding is **not** a recommendation to silently collect telemetry or bypass the consent gate. The user-visible Enable action must remain explicit; a decline, closing the notice, or Esc must not grant.

## Findings matrix

| Area | Reviewed source / evidence | Disposition |
| --- | --- | --- |
| Default-off and release gate | `app/telemetry/telemetry_policy.gd`, `telemetry_release.gd`, `app/addons/build_info/export_plugin.gd`, `app/app_root.gd` | **Design passed static review.** No eligible export / interactive route / reviewed notice / explicit grant => no collection. Not verified in native packaged binaries. |
| Revocation | `telemetry_service.gd`, `telemetry_consent_store.gd`, `telemetry_sender.gd`, `telemetry_queue.gd` | Off closes the gate, cancels in-flight work, discards in-memory queue and token, and persists the choice. A failed decline removes a prior grant from disk. Request races require native/E2E recheck. |
| UI discoverability | `app/ui/telemetry_screen.gd`, `settings_screen.gd`, `app_root.gd` | First-launch consent notice and **Settings → Interface → Share technical telemetry** switch, privacy notice, exact queued-data preview and state text exist. Buttons arm after a quiet 600 ms; initial focus is neutral. Needs rendered, gamepad and assistive-technology qualification. |
| Languages | `app/i18n/{es,de,fr,it,ja,pt_BR,ru,zh_Hans}.po`, `telemetry_policy.gd` | Telemetry notices/UI are present in all nine offered languages including source English; static validation of 19 central UI/disclosure strings in all eight translated catalogs found no missing/empty translations or `%s`/`%d` mismatch. **Only English and Spanish are admitted**; other seven language modes remain intentionally off until fluent legal/UI review. No claim of native-speaking review for all seven. |
| Payloads | `telemetry_contract.gd`, `telemetry_hardware.gd`, `telemetry_frame_window.gd`, `telemetry_service.gd` | Bounded JSON contract; coarse CPU/GPU/OS/renderer/input/resolution categories, frame intervals/histograms, stock aircraft and activity summaries, a small fixed error taxonomy. No names, raw device strings, input commands, log text, saved history or installation ID are serialized by these builders. Receiver enforces schema/semantic limits independently. |
| Signal limitations | `app/app_root.gd`, `telemetry_frame_window.gd` | `graphics_profile` is currently `unknown`; frame `gpu_status` is `not_measured` and `gpu_ms` null. Do **not** promise graphics-preset attribution or GPU-time diagnosis from v1. Process/frame cadence and render-frame counts are useful but are not a full hardware benchmark. |
| Delivery | `telemetry_queue.gd`, `telemetry_sender.gd`, `services/telemetry` | In-memory best effort only: bounded count/bytes/time, backoff, rate budget, 202 success, 410 suspension, no redirects. Closing the app can lose untransmitted observations; appropriate to disclose in operational interpretation. |
| Backend tests | [Telemetry contracts workflow, main @ 0a45e8c](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44422442929) | **PASS**: schema/examples/reference checks, receiver unittest step, receiver Docker image build and localhost smoke. The receiver unittest step **skips Godot client E2E** when `OPENRC_GODOT` is unset; workflow success alone is not end-to-end gameplay qualification. |
| Full build/test pipeline | [CI, main @ 0a45e8c](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44422442974) | **NOT A GREEN RELEASE CERTIFICATE at review time**: many jobs in progress, and RC native Windows build already reported failure. Investigate with owning Windows/native track; no attribution to telemetry is justified from job status alone. |
| Local native test | Current audit environment | **NOT RUN**: no Godot executable or direct access to a usable interactive Windows/Linux installation; unauthenticated `git` network access from the audit container also unavailable. No invented test pass. |

## User-facing copy reviewed

- English: “Help improve OpenRC Simulator” / “Recommended: share technical telemetry.” The only grant is **Enable telemetry and continue**; decline is **Continue without telemetry**.
- Spanish: “Ayúdanos a mejorar OpenRC Simulator” / “Recomendado: compartir telemetría técnica.” The only grant is **Activar la telemetría y continuar**; decline is **Continuar sin telemetría**.
- Settings: “Share technical telemetry” / “Compartir telemetría técnica”, plus **See exactly what we send** / **Ver exactamente lo que enviamos**, and **Privacy notice** / **Aviso de privacidad**.
- Spanish full paragraphs explicitly discuss IP processing, possible distinctive hardware/session combinations, no guaranteed anonymity, retention and GitHub summary publication. They track the English disclosure on the static reading performed here.
- Do not change `REVIEWED_NOTICE_LOCALES` simply because the gettext catalogs have entries. Proof of fluent translation and layout review is a separate acceptance item.

## What the initial data can and cannot answer

**Can support:** per-release, per-OS/renderer and broadly bucketed hardware performance-window distributions; proportion of observed stock model-aircraft activities; coarse durations/outcomes; supported fixed-wing takeoff/landing/model-crash counters; broad error-category counts. Report denominators must be observed, consenting **sessions/windows**, not all installs or unique players. Published cohorts are suppressed under the receiver's minimum-size rule.

**Cannot yet support:** unique players or installation retention, stable DAU/MAU, reliably measured GPU milliseconds, a comparison of named CPU/GPU SKUs, individual graphics-setting attribution, absolute adoption among all installations, exact frame-by-frame traces, or delivery of every short/closed session.

A test deployment should validate actual on-wire batches, the receiver's aggregate rows, and usefulness of the weekly report against a small controlled pilot. Never fix a missing signal by introducing detailed identifiers without a new privacy/schema review.

## Activation blockers — do these BEFORE publishing a telemetry-enabled release

1. **Operator and privacy declaration:** choose and verify a real receiver operator/contact/region, hosting provider, TLS proxy, access controls, IP and proxy-log retention, backups, storage separation and erasure behavior. Independently confirm all privacy-notice promises.
2. **Production receiver:** deploy `services/telemetry` with durable aggregate storage, separately expiring raw store, monitor `/healthz`, verify ingress `202`, client `410` suspension, 48-hour raw/temporary expiry, ≤180-day aggregate expiry, no persistent IP/body proxy logs, abuse controls and alerts.
3. **Release variables:** configure repository variables for `OPENRC_TELEMETRY_ENDPOINT` (validated HTTPS `/v1/batches`), `OPENRC_TELEMETRY_OPERATOR` and `OPENRC_TELEMETRY_CONTACT`. Verify the exact exported package includes `res://telemetry_release.json` with all three values; do not rely on variable existence alone.
4. **Receiver allowlist:** configure `OPENRC_TELEMETRY_RELEASES` to include **the exact semver release tag** before the client is distributed; confirm the tag is allowed by `telemetry_contract.gd` and the pack has `build_info.json` from a clean exact-tagged release export. Development/untagged/dirty/manual exports intentionally remain off.
5. **Client E2E with a real engine:** set `OPENRC_GODOT` and run `services/telemetry/tests/test_godot_e2e.py`; inspect database rows and compare client `E2E sent` vs stored batches. Then conduct **interactive** Windows and Linux runs from the intended package, with a local qualification receiver first and production TLS only in a reviewed controlled pilot.
6. **Consent matrix:** fresh install, stored decline, stored enable, no response, Esc/gamepad Back/window close, rapid on/off during an HTTP request, restart persistence, offline/timeouts/redirects, HTTP 410, failed consent-file save, language changes, screen reader and high text scale. Validate no send before the positive choice and no further send after disable.
7. **Data quality + overhead:** 1080p vs large displays, Windows/Linux (plus macOS before a cross-platform release), keyboard/gamepad/RC input, Home/Workshop/flight, stock/custom vehicle, pause/minimize/focus, sustained play and graceful/abrupt exit. Compare FPS/frame overhead with telemetry on vs off on the same machines. Confirm no simulation/control changes.
8. **General release gate:** close or explicitly waive unrelated current failing CI jobs, especially Windows native RC build, on the **exact release candidate**. Existing receiver green tests do not supersede whole-product native packaging checks.
9. **Preview rollout:** small consenting preview cohort, real telemetry accepted, deduplicated and summarized, manual publication rehearsal with proper author/scope and frozen review; only then approve stable activation. Collecting data and publishing aggregate reports are distinct permissions.

## Repeatable local test recipe (NOT executed by this audit)

On a Linux development machine with a full source checkout, Godot 4.8 and the pinned receiver Python environment:

```sh
# From the repository root, after installing services/telemetry/requirements.txt
export OPENRC_GODOT="$(app/get-godot.sh)"
cd services/telemetry
python -m unittest discover -s tests -t . -p 'test_godot_e2e.py' -v
```

The test starts a loopback receiver, invokes `app/tests/telemetry_receiver_e2e.gd` with a real Godot process, counts stored batches and checks privacy-relevant strings. **This is still headless**, not proof of native menu layout or packaged Windows/Linux behavior.

Interactive qualification uses `OPENRC_TELEMETRY_QUALIFICATION_URL=http://127.0.0.1:8787/v1/batches` only in a **debug/source run** (not a production export); the local receiver must be started with the matching allowlisted qualification release. Follow `docs/plans/telemetry/verification.md` and `services/telemetry/README.md`. Never send test payloads to a public production collector.

## Handoff and ownership

This audit **intentionally changes no files owned by ongoing game, i18n, CI or telemetry tracks**. Keep the implementation stable while other features evolve; before a release, re-run the complete acceptance matrix against the **exact tagged source and built packages**. Close this review only after attaching real deployment/TLS, Windows/Linux packaged build and receiver-ingestion receipts. Do not label it release-ready simply because the contracts workflow is green.
