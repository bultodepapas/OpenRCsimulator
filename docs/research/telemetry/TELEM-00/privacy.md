# Privacy, consent, transparency, and data minimization research

Research completed: **2026-11-18**. Authoring role: privacy and consent research workstream. This is a design proposal, not a statement that the current product already implements these controls or a universal legal compliance conclusion.

## Decision to carry into the main plan

The first-run screen must accurately distinguish a **recommended sharing choice** from actual collection. The product may recommend enabling telemetry, but must perform **no telemetry collection, SDK initialization with collection enabled, DNS lookup, connection, or upload before a deliberate Enable action**. Provide an equally visible Continue without telemetry action. A preselected switch followed by a generic Continue button is weaker than explicit enable/decline actions and must not be treated as sufficient consent by itself. On subsequent launches after acceptance, show the requested “Telemetry is on” notice with a direct settings action.

**Repository-specific boundary:** the project targets Godot 4.8 beta 2 and already has local flight statistics with persistent UUIDs, precise timestamps, and custom aircraft identities. Those existing records are outside the automatic upload contract. Never upload the local store/history wholesale and never backfill pre-consent flights. Create only new, sanitized post-acceptance summaries. The project also has an independent GitHub update checker. “Telemetry off” means zero telemetry traffic; update checks remain controlled by their own setting. Tests must distinguish those destinations or disable update checks for a fully silent capture. Existing gameplay timers and local-only statistics are not automatically telemetry collection; the gate applies to the new telemetry-specific pipeline.

The user’s wish to learn hardware, FPS, and aircraft use is compatible with a useful minimized technical dataset. It is not compatible with promising that arbitrarily detailed hardware and event timelines are automatically anonymous. The recommended wording is **“technical telemetry without your name or a persistent device identifier”**, accompanied by concrete disclosures. A hosted HTTPS service still receives the source IP at its network boundary. Treat raw session reports as potentially identifiable until an anonymity assessment demonstrates otherwise; publish only reviewed aggregates.

## Research ledger: 12 primary-source investigations

Each item below was opened and read, not merely inferred from a search snippet. The source URLs are portable citations for the repository. The active design is linked below.

<a id="p01"></a>

### P01 — Visual Studio Code: inspection and settings controls

- Source: <https://code.visualstudio.com/docs/configure/telemetry>
- Retrieved: 2026-11-18.
- Finding: VS Code exposes levels covering usage, errors, crashes, and off; it can display actual telemetry events and generate a per-build event inventory. Its docs also caution that extension telemetry can have independent controls.
- Reuse: provide Settings → Privacy → Telemetry, a readable live payload preview, the shipped event schema, and one authoritative gate covering every SDK and plugin.
- Do not copy: hashed NIC or persistent IDs. The product does not need user tracking to answer the initial performance questions.
- Concrete test: the privacy switch disables all exporters, including third-party diagnostic SDKs, not only the first-party HTTP uploader.

<a id="p02"></a>

### P02 — Go telemetry: public metric proposals and approved counters

- Source: <https://go.dev/doc/telemetry>
- Retrieved: 2026-11-18.
- Finding: Go distinguishes local, on, and off modes; upload requires opt-in, and only approved counters are included in uploaded reports. Proposed charts determine the counters that may be uploaded. Its documentation identifies sampling bias as a practical concern.
- Reuse: every metric must have an engineering question, named consumer, finite cardinality, documented aggregation, and expiry/review date. Ship an inspectable allowlist and reject unrecognized fields.
- Boundary: Go states its telemetry package is intended for Go-team tools and selected dependencies. Borrow governance and measurement patterns; do not assume its infrastructure is a general-purpose hosted backend.
- Concrete test: adding a new client property without an approved schema change causes validation failure.

<a id="p03"></a>

### P03 — KDE software privacy policy: device details without device identity

- Source: <https://kde.org/privacypolicy-apps/>
- Retrieved: 2026-11-18.
- Finding: KDE telemetry is opt-in, provides device specifications and usage details while excluding serial numbers, forbids user/installation/device identifiers, explains fields before enablement, and supports changing the choice later.
- Reuse: hardware classes and selected built-in aircraft IDs, with no installation UUID, device ID, serial number, username, or account linkage. Describe changes to the telemetry schema in release notes.
- Boundary: an organization’s privacy promise is inspiration, not evidence that any other implementation is anonymous.
- Concrete test: fixtures containing serials, hostnames, filesystem paths, or persistent IDs are rejected even if their values look innocuous.

<a id="p04"></a>

### P04 — Mozilla data-collection principles: pseudonymity and transport metadata

- Source: <https://firefox-source-docs.mozilla.org/contributing/data-collection.html>
- Retrieved: 2026-11-18.
- Finding: Mozilla describes ordinary telemetry client IDs as pseudonymous, requires review of new collection, and distinguishes local processing, encrypted sync, Oblivious HTTP, and aggregate protocols. Its OHTTP discussion warns that an otherwise harmless combination of fields can still identify someone.
- Reuse: label risks honestly, review the combined record rather than each field alone, and test network behavior rather than trusting a UI switch.
- Boundary: Firefox’s product-specific default-on policy does not establish a lawful basis or adequate consent design for this game.
- Concrete test: verify wire payloads plus reverse-proxy/CDN logs, not only the JSON serializer.

<a id="p05"></a>

### P05 — Mozilla data-review process: enforceable schema governance

- Source: <https://firefox-source-docs.mozilla.org/contributing/data-review.html>
- Retrieved: 2026-11-18.
- Finding: changes that add or expand collection require data classification, and unresolved classification prevents landing in Mozilla’s workflow.
- Reuse: telemetry schema, consent copy, metric catalog, and collector changes should have a review checklist owned by designated maintainers. A PR adding a field must explain purpose, sensitivity, retention, cardinality, and whether the existing consent still covers it.
- Concrete test: the CI contract test loads the schema and verifies that fixtures/documented events agree. Review remains necessary because a test cannot decide whether a purpose is justified.

<a id="p06"></a>

### P06 — Go telemetry privacy notice: inspectable local reports

- Source: <https://telemetry.go.dev/privacy>
- Retrieved: 2026-11-18.
- Finding: the notice explains local recording, explicit upload activation, uploaded report copies, approved counters, and commands for viewing and clearing local data.
- Reuse: Show what we send, Copy sanitized report, and Clear pending reports. Keep a bounded local inspection view containing the same sanitized representation as the uploader.
- Do not copy: automatically making individual uploaded reports public. This game’s hardware and aircraft combinations can be more identifying than the initial counter model suggests.
- Concrete test: preview and uploaded JSON are generated from the same finalized object, not separate UI approximations.

<a id="p07"></a>

### P07 — W3C fingerprinting guidance: combinations matter

- Source: <https://www.w3.org/TR/fingerprinting-guidance/>
- Retrieved: 2026-11-18. Published Group Note: 2025-09-25.
- Finding: observable device and configuration characteristics can correlate visits without cookies or names; mitigations reduce risk rather than guaranteeing elimination.
- Reuse: normalize CPU/GPU strings into reviewed families; bucket RAM, core count, resolution, and memory; exclude exact timestamps, custom labels, and high-dimensional public drilldowns.
- Boundary: this is web specification guidance, used here by analogy to desktop hardware telemetry. It is not a game-specific implementation specification or a legal determination.
- Concrete test: a rare hardware combination must not produce a publicly queryable single-report slice.

<a id="p08"></a>

### P08 — IETF RFC 9458: an established option for separating IP and payload

- Source: <https://datatracker.ietf.org/doc/rfc9458/>
- Retrieved: 2026-11-18.
- Finding: Oblivious HTTP uses encapsulation and a relay/gateway design to limit linking requests to client network identity. Ordinary HTTP requests expose connection metadata including source IP.
- Reuse: leave OHTTP as a later privacy enhancement if threat analysis justifies an independent relay and operational complexity. Do not invent custom encryption.
- Boundary: OHTTP is not needed for a minimal technical metrics pilot, and it does not make identifying payload contents safe.
- Concrete test if adopted: the gateway never receives the original client IP in forwarding headers, and relay operators cannot read the inner payload.

<a id="p09"></a>

### P09 — ICO anonymisation glossary: correct terminology

- Source: <https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/data-sharing/anonymisation/glossary/>
- Retrieved: 2026-11-18.
- Finding: anonymity requires addressing identifiability, including indirect identifiers and linkability. De-identification is not an automatic synonym for anonymity; aggregation and generalization are distinct techniques. The guidance is marked under review following UK law changes.
- Reuse: do not call a random persistent identifier “anonymous.” Document residual identification risk and public-release controls separately from transport encryption.
- Boundary: UK guidance is an engineering reference here, not a jurisdiction-wide legal conclusion. Distribution countries and actual processing must be reviewed before release.
- Concrete test: no UI, README, or privacy notice promises “completely anonymous” or “we cannot see your IP” when the deployed architecture cannot substantiate it.

<a id="p10"></a>

### P10 — ICO consent guidance: a real choice with an affirmative action

- Canonical source: <https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/lawful-basis/a-guide-to-lawful-basis/consent/>
- Readable official locale URL: <https://cy.ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/lawful-basis/a-guide-to-lawful-basis/consent/>
- Retrieved: 2026-11-18. The canonical English route returned 403 when opened; the official Welsh-site route served the English guidance in full.
- Finding: consent involves an affirmative opt-in, control, specificity, understandable information, withdrawal, and evidence of what was agreed. Preticked boxes/default consent are not accepted by this guidance. The guidance is under review.
- Reuse: explicit Enable telemetry and continue versus Continue without telemetry, same usability and no feature penalty. Store consent version and choice locally. Ask again when purposes materially expand.
- Boundary: do not claim a generic Accept and continue button or a checkbox default makes a release legally compliant.

<a id="p11"></a>

### P11 — KDE KUserFeedback: reusable UI and no-ID design

- Source: <https://github.com/kde/kuserfeedback>
- Retrieved: 2026-11-18.
- Finding: the framework supplies application libraries, QML bindings, server/analytics components, reference notification and configuration widgets, and no unique user/installation/machine identifier in its intended design. It explains time-based submissions as an alternative for reducing duplicate contribution.
- Reuse: study its feedback configuration and bounded submission patterns. This project uses Godot, so this is a design reference rather than a drop-in Qt SDK.
- Limitation: client-side submission limits do not prove unique people or resist modified clients. Never report “unique users” solely from session/report counts.
- Concrete test: honest local cadence limits and server deduplication operate without a durable installation identity.

<a id="p12"></a>

### P12 — Glean collection toggles and deletion requests: inspect SDK side effects

- Sources: <https://mozilla.github.io/glean/book/reference/general/toggling-collection-status.html> and <https://mozilla.github.io/glean/book/user/pings/deletion-request.html>
- Retrieved: 2026-11-18.
- Finding: disabling collection cancels scheduled uploads and clears client metrics, but also emits a deletion-request ping; that ping carries a client ID. Some custom pings may not follow the general collection-enabled switch.
- Reuse: disable must clear queues and cancel scheduled work, and SDK behavior must be integration-tested. If the product promises zero telemetry traffic while off, an SDK’s deletion traffic needs explicit handling and user-facing explanation.
- Decision: do not silently add persistent identity merely to obtain deletion-by-user capability. Anonymous-style aggregates and per-user erasure are different architectures; choose and explain the tradeoff.

## Integration outcome

These investigations informed the [consent copy and state contract](../../../plans/telemetry/consent.md), [data/retention contract](../../../plans/telemetry/data-contract.md) and [acceptance plan](../../../plans/telemetry/verification.md). Those documents own the integrated design; this file preserves dated evidence.

The final design uses a ten-minute memory-only queue and a disclosed 48-hour raw/dedup ceiling with daily rollups. Early exploratory retention ranges and UI drafts have been consolidated into those authoritative homes. The current notice explicitly distinguishes short-lived session usage from excluded saved flight history and separates telemetry from the independent update checker.
