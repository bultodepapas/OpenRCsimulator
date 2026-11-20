# Website analytics plan

Improves the public website's GA4 measurement and the operator dashboard's Website tab, based on the [GA4 audit, 2026-11-20](../research/website-analytics/ga4-audit-2026-11-20.md).

**Ownership.**

- WEB-17…WEB-23 belong to the website track ([site/README.md](../../site/README.md)).
- TELEM-24b belongs to the telemetry dashboard ([tools/telemetry](../../tools/telemetry/README.md)).
- GA4 and GTM settings are changed by the owner in Google's UI. The dashboard's credential is read-only.

**Principles.**

- `download_request` stays the single download metric.
- Collect only on the production host.
- Collect no personal data beyond what GA4 needs.
- Every site change keeps downloads working with analytics blocked or denied.

## Status, 2026-11-20

- **WEB-18, WEB-20 and TELEM-24b:** implemented. TELEM-24b's daily collection task is still open.
- **WEB-17:** waits for the owner. The dashboard's *Property setup* panel shows what remains.
- **WEB-19, WEB-21, WEB-22 and WEB-23:** open.

**Evidence.**

- `node --test site/test_downloads.cjs` passes 13 tests, and `python site/test_locales.py` passes 7.
- A Chromium check at 1920×1080 and on iPhone emulation, with Google and GitHub intercepted:
  - On `127.0.0.1`, no Google request is made and the desktop ZIP still starts.
  - On the production host, GTM loads and `download_request:automatic` is sent.
  - On iPhone, `download_handoff:shown` is sent and no ZIP is requested.
- Dashboard and collector tests pass 38. The live property returns host-filtered totals, funnels and the setup checklist.

## Order and steps

| Step | What | Why (audit finding) | Who / files | Effort | Done when |
| --- | --- | --- | --- | --- | --- |
| **WEB-17** Property hygiene | Set event retention to 14 months. Mark `download_request` as a key event and remove `purchase`. Register event-scoped custom dimensions `download_platform`, `release_version`, `download_source`, `download_method`, `handoff_action`, `metric_name`, `metric_rating` and custom metric `metric_value`. Add a hostname-based data filter (or *Define internal traffic*) for non-production hosts. | Two-month explorations; no goal; parameters not reportable; localhost hits | Owner, GA4 Admin | S | `ga4.py check` reports no unregistered dimensions; the Admin API shows retention and the key event |
| **WEB-18** Production-only collection | Load the GTM bootstrap only when `location.hostname === 'bultodepapas.github.io'`. Add the same guard to `downloads.js`; downloads keep working. Extend `test_downloads.cjs`. | About 4% of page views came from `127.0.0.1` | `site/index.html` → `build_locales.py`, `site/downloads.js`, `site/test_downloads.cjs` | S | Local preview sends no Google request; the tests cover the guard |
| **WEB-19** Consent and privacy | Consent Mode v2 with `analytics_storage` denied by default for EEA/UK/CH (GTM Consent Initialization). A small accessible banner with accept/reject. A privacy page in eleven languages, linked from every footer. Decide basic versus advanced consent mode. | GA4 loads unconditionally for a large EEA/UK share; no privacy notice | Owner decision + `site/` pages, locales, GTM | M | Denied visitors set no analytics cookies; the banner choice persists; the privacy link is on all pages |
| **WEB-20** Download measurement integrity | Deduplicate `download_request` per platform and release within a session (`sessionStorage`). On phones and tablets, do not auto-start a desktop ZIP: show a "download on your computer" hand-off (copy link / share) and send `download_handoff`. Document `file_download`/`click` as non-additive. | Repeated mobile requests (iOS about 7–8 per user); three overlapping signals | `site/downloads.js`, `site/README.md`, tests | S/M | Repeat opens send one request; mobile sends `download_handoff`, not a ZIP request |
| **WEB-21** Attribution scheme | One UTM convention table (`utm_source` = channel, `utm_medium` = `social`/`forum`/`release`/`video`, `utm_campaign` = release or post). Apply it to Reddit and forum posts, GitHub release notes, trailer descriptions and social profiles. Keep the README `readme` campaign. | Reddit, the largest referral, is untagged; README traffic converts at about 94% but other channels are opaque | `site/README.md` (convention), release-note template, `tools/trailer` descriptions | S | New posts and releases carry campaign tags; GA4 shows them per campaign |
| **WEB-22** Engagement events | Send `language_switch` (from → to), `aircraft_select`, `inspector_open`, `donate_click` (PayPal link, key event candidate) and `repo_click`, each with `page_locale`. No free text, no identifiers. | Only enhanced measurement exists; donations and 3D interest are unmeasured | `site/main.js`, `viewer.js`, `inspector.js`, `cinema.js` | M | Events appear in GA4 DebugView from the production host only |
| **WEB-23** Language reach | Use `language_switch` and browser-language data to decide whether the root page should suggest the visitor's language, without overriding a saved choice. | About 41% non-English browser languages; localized pages get about 4% of views | `site/main.js`, locales | M (after WEB-22) | Decision recorded in site/README.md with two weeks of data |
| **TELEM-24b** Dashboard follow-ups | Exclude non-production hosts in every query. Add a funnel tile and a table (users → download requests by source, device and OS) with engaged sessions as the traffic KPI. Add a release-version breakdown once registered, and key-event status. Warn when the refresh token is near expiry or refused (testing-mode consent screen). Add an optional daily collection task like the GitHub archive. | Dashboard gaps in the audit | `tools/telemetry/ga4.py`, `dashboard.py`, tests | M | Tests cover the filter and funnel; the tab shows conversion per source |

**Sequence.**

1. WEB-17 and WEB-18 first. They are cheap, and later data depends on them.
2. Next, WEB-19 (compliance) and WEB-20.
3. Then WEB-21 and WEB-22.
4. WEB-23 last, once there is data.
5. TELEM-24b can follow WEB-17 at any time.

## Notes

- Consent reduces measured EEA/UK traffic; compare trends before and after WEB-19 separately.
- Custom dimensions report only from registration onwards, so register them before the next release announcement.
- GA4 counts are website requests, not installs; GitHub release counters and in-app telemetry remain the download and usage sources of record.
- Publish the OAuth consent screen (or use a service account) so the dashboard credential does not expire weekly.
