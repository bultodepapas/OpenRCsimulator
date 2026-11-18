# Consent, transparency and player control

Status: proposed copy and behavior; not present in current game builds.
Authority: [master plan](../telemetry.md). Evidence: [privacy investigations P01–P12](../../research/telemetry/TELEM-00/privacy.md).

## Product decision

Recommend telemetry on at the first ordinary exported launch. A recommendation may appear selected, but the effective collection state remains pending/off until a deliberate telemetry-specific Enable action. A generic Continue, window close, timeout, Escape, controller back action, preselected preference, or input held when the notice appears is never a grant. Require release and a fresh deliberate action for held input. The first message cannot truthfully say “Telemetry is on” before the gate opens.

Use equally visible, equally reachable **Enable telemetry and continue** and **Continue without telemetry** actions. This preserves the desired easy acceptance while giving a real choice. Every later eligible launch can use the saved enabled choice automatically and show the requested “Telemetry is on” notice. Do not re-prompt a saved decline after routine updates.

The ICO source is a useful consent reference, not a universal legal determination. Actual distribution, recipients, children-related product choices and applicable requirements must be reviewed against the deployed design. Do not use IP geolocation to choose a weaker flow.

## First-launch copy — English

**Help improve OpenRC Simulator**

Recommended: share technical telemetry.

If you choose Enable, we will send performance summaries such as FPS and frame-time ranges, broad CPU/GPU and memory categories, operating system and graphics settings, and the built-in aircraft and activities you use. We also send the broad input method, activity duration and outcome, supported takeoff/landing and model-aircraft crash counts, and fixed categories of software errors. Model-aircraft crash counts are not application crash dumps. We use these reports to find slow configurations and improve the simulator.

We do not send your name, email, account, device serial number, custom aircraft names, saved flight history, control inputs, files, screenshots or raw logs. A temporary random session code groups reports. It is not saved on this device and a new code is created at launch; the receiving service retains it for at most 48 hours after receipt. Our receiving service processes your IP to receive the connection, but the analytics database does not store it. Hardware and session data can still be distinctive, so we do not promise complete anonymity.

Reports go to the project's receiving service. Only reviewed summaries may be published on GitHub. You can inspect the data and turn telemetry off at any time in Settings → Privacy. The simulator works the same with telemetry off.

**Enable telemetry and continue** · **Continue without telemetry**

Secondary links: **See exactly what we send** · **Privacy notice**

The expanded notice must also state: sealed pending data stays in memory for at most ten minutes; an active collection code rotates by four hours and the UTC day boundary, while an already sealed pending batch can retain its old code for the remainder of that ten-minute lifetime; raw minimized reports, temporary IDs and deduplication keys expire within 48 hours of receipt; ID-free internal aggregates expire within 180 days; reviewed public GitHub summaries can persist indefinitely. Any temporary IP-derived abuse control is memory-only and expires within 15 minutes. These are target controls to verify, not existing service guarantees.

Do not ship this copy until the service, provider/IP controls and retention below are verified. Replace “project's receiving service” in the final notice with the actual operator, endpoint origin, hosting recipient and contact.

## First-launch copy — Spanish

**Ayúdanos a mejorar OpenRC Simulator**

Recomendado: compartir telemetría técnica.

Si eliges Activar, enviaremos resúmenes de rendimiento, como FPS y rangos de tiempo por fotograma, categorías generales de CPU/GPU y memoria, sistema operativo y ajustes gráficos, y los aviones y actividades incluidos que utilizas. También enviamos el tipo general de control, la duración y el resultado de la actividad, los conteos disponibles de despegues, aterrizajes y accidentes del aeromodelo, y categorías fijas de errores del programa. Los conteos de accidentes del aeromodelo no son volcados de memoria por fallos de la aplicación. Usamos estos informes para encontrar configuraciones lentas y mejorar el simulador.

No enviamos tu nombre, correo, cuenta, número de serie del equipo, nombres de aviones personalizados, historial de vuelos guardado, movimientos de los controles, archivos, capturas ni registros completos. Un código aleatorio temporal agrupa los informes de la sesión. No se guarda en este dispositivo y se crea uno nuevo al iniciar; el servicio receptor lo conserva como máximo 48 horas desde su recepción. Nuestro servicio receptor procesa tu IP para recibir la conexión, pero la base de datos de análisis no la almacena. La combinación de hardware y sesión puede ser distintiva, por lo que no prometemos anonimato completo.

Los informes llegan al servicio receptor del proyecto. En GitHub solo podrán publicarse resúmenes revisados. Puedes consultar los datos y apagar la telemetría cuando quieras en Ajustes → Privacidad. El simulador funciona igual con la telemetría apagada.

**Activar telemetría y continuar** · **Continuar sin telemetría**

Enlaces: **Ver exactamente qué enviamos** · **Aviso de privacidad**

## Startup status on subsequent launches

| Effective state | English | Spanish |
| --- | --- | --- |
| Enabled and eligible | Telemetry is on. We share hardware categories, performance summaries and built-in aircraft usage. Settings | La telemetría está activada. Compartimos categorías del hardware, resúmenes de rendimiento y uso de los aviones incluidos. Ajustes |
| Saved off | Telemetry is off. Settings | La telemetría está desactivada. Ajustes |
| Pending new decision | Telemetry is paused until you review the updated notice. Review | La telemetría está pausada hasta que revises el aviso actualizado. Revisar |
| Forced off | Telemetry is off for this build or launch mode. | La telemetría está desactivada para esta versión o modo de inicio. |
| Enabled but offline | Telemetry is on; waiting for a connection. Sealed pending batches expire after 10 minutes. | La telemetría está activada; esperando conexión. Los lotes pendientes ya preparados caducan en 10 minutos. |
| Service suspended | Telemetry delivery is suspended. No new reports will be collected. Settings | El envío de telemetría está suspendido. No se recopilarán nuevos informes. Ajustes |

Use a nonblocking startup banner plus persistent Settings status. Do not require acceptance on every startup or place a toast over flight controls. Recommended banner duration is 8 seconds; it remains until focus leaves if a keyboard/screen-reader user is interacting with it. Status must be discoverable after dismissal.

## Settings → Privacy

One switch controls base telemetry. Display effective state, saved choice, last attempted/successful send status, pending batch count/bytes, destination origin and notice version. Do not show an “on” state when release or service policy prevents it.

Actions: **Show pending payload**, **Copy sanitized report**, **Clear pending reports**, **Open privacy notice**. Off closes the gate immediately; no confirmation is required. Copy/export is local and does not open a browser. The pending-payload view displays exact wire bytes; the separate manual report uses the restricted projector below and is not a raw-batch export. After admission, the preview uses the exact finalized JSON bytes selected for delivery, with headers/destination shown separately. Before admission, See exactly what we send shows only the static schema and clearly labeled synthetic examples; it must not trigger a telemetry-specific hardware probe or create a pending report. Its temporary session/batch tokens are inspectable but are not included in public aggregate reports.

After a successful off action:

> Telemetry is off. Pending reports on this device have been deleted. Reports already received will expire under the privacy notice; published aggregate statistics cannot be recalled. You can keep playing.

Spanish:

> La telemetría está desactivada. Se han eliminado los informes pendientes de este dispositivo. Los informes ya recibidos caducarán según el aviso de privacidad; las estadísticas agregadas publicadas no pueden retirarse. Puedes seguir jugando.

If saving fails, append:

> Your choice could not be saved. Telemetry is off for this session. The next launch may load your previous setting; check Privacy before enabling a connection.

Do not claim the denial survives restart unless the durable write was successful. Consider a startup-visible storage-error state and a packaged/local force-off switch as recovery options. A failed save must never reopen the current gate.

## State machine

| Event | Prior state | New effective state | Side effects |
| --- | --- | --- | --- |
| Fresh profile / unknown schema / damaged consent | Any stored ambiguity | Pending/off | No telemetry probe, DNS, request or queue |
| Explicit enable for current notice, eligible build | Pending/off | Enabled | New generation and memory-only session; collect only new observations |
| Continue without / Escape / close | Pending | Off | Save denial when possible; no re-prompt on ordinary launches after successful save |
| Turn off | Enabled | Off immediately | Fence callbacks first, cancel request, purge queue, clear identity, save |
| New material notice | Enabled | Pending/off | Stop and purge before asking; no automatic acceptance |
| Ordinary application upgrade | Saved off | Off | Retain choice |
| Headless/direct/replay/dev/forced off | Any | Forced off | Do not read/send past queue or initialize exporter |
| Service 401/403/410 | Enabled | Suspended/off collection | Cancel/purge; retain saved preference, explain state |
| Locale has no reviewed notice | Any | Forced off | Close gate and purge; a saved grant cannot silently resume in that locale. A newly reviewed notice requires a deliberate Enable action before collection resumes |
| Re-enable later | Off | Enabled if eligible | New session; no historical replay |

## Meaning of privacy promises

The notice version in a submitted batch is an untrusted client assertion, not proof that a person affirmatively accepted it. Before activation, the operator must assess whether local-only choice/notice evidence is sufficient for the actual distribution and processing obligations. Do not introduce a stable identifier as a shortcut: any alternative requires its own purpose, identity, retention and notice review. This is an operational review gate, not a universal legal conclusion.

We exclude direct identity and persistent cross-launch tracking. Temporary session IDs make raw reports linkable within a bounded session. Hardware combinations can still be identifying. Do not label raw records “fully anonymous,” “untraceable,” or “zero personal data.” The engineering goal is minimized telemetry and disclosure-controlled aggregate publication.

The network host processes IP addresses. The target is no IP in analytical persistence and no request-body logging; an in-memory abuse limiter may use an IP-derived key for up to 15 minutes. That exception and all hosting logs must appear in the deployed notice. If a provider cannot meet the chosen limit, either change the provider/configuration or revise the design and notice before enablement.

Declining telemetry sends no “declined” event. Turning off sends no final session, deletion or acknowledgment ping. Already delivered bytes cannot be recalled by client cancellation. We deliberately cannot search historical records by a player account/device because those identifiers are not collected. Explain automatic expiry and provide a contact; do not promise account-based deletion or retractable public Git history.

The separate GitHub update checker has its own setting. Telemetry off means no telemetry requests, not a claim that every other application network feature is off.

Keep separately initiated local flight/diagnostic recording distinct from this switch. Off must not imply that all local logs are erased. A notice being shown is not a notice being accepted; preserve explicit denial across stable, preview and future release channels. No candidate-build override may silently turn it back on. Follow-up F26–F29 in the [research register](../../research/telemetry/TELEM-00-R1/README.md) supply concrete versioned-choice and local-log counterexamples.

## Manual diagnostics and crash reporting

A separate local manual-report projector may export only approved build/context fields and user-selected aggregate diagnostics. It must not export session_id, batch_id, seq, raw per-window/session event arrays, automatic raw batches or arbitrary diagnostic dictionaries. The player may separately type optional exact CPU/GPU details into their report after review. This projector and its UI are pending implementation. Show before opening GitHub:

> This report is optional. A GitHub issue identifies your GitHub account. In a public repository, the issue and attachments may be readable by anyone. Review and remove anything you do not want to share.

Never put the full report in a URL, auto-submit an issue or automatically attach local logs. Sentry or any crash SDK requires a separate design/notice, default-disabled initialization and verified cache/opt-out behavior; base telemetry consent does not cover memory dumps.

Generate the manual artifact from the separate fresh typed allowlist, never by dumping a diagnostic object and hoping a warning is sufficient. The exact reviewed bytes must be the exported bytes, and manual content must not be inserted into a URL. Keep preview/copy/export inert, show the actual destination and ensure the reviewed bytes are the exported bytes; an edit or regenerated payload requires a new preview. Test private path, username, environment, exception and arbitrary-key canaries. Missing end-of-session/crash reports remain unknown and cannot be used as evidence of zero failures. These transfer lessons come from F21/F23/F24/F27/F30, not from a tested OpenRC UI.

## Accessibility and acceptance

Equal action prominence; logical focus order; no automatically focused acceptance activated by an unrelated controller button; screen-reader names; non-color status indicators; scrolling text at large scale; no countdown. Qualify EN, ES and every other offered locale before enabling telemetry in that locale; an unreviewed notice forces telemetry off. Test at 1920×1080 first, then higher resolutions, then 1280×720, except Apple Silicon Retina panels use their native physical-panel target under the Apple plan. The offline contract tests do not qualify any rendered UI.

Add a pseudolocalized expansion fixture, keyboard/controller traversal, held input as the panel appears, visible focus after hiding/reopening it and actual assistive-technology checks. Verify both actions remain reachable at large text/UI scales. The current registry offers English, Spanish, Simplified Chinese, Brazilian Portuguese, German, French, Italian, Russian and Japanese. Review translation accuracy, layout, focus and actual glyph coverage for each; pseudolocalized expansion alone does not establish Chinese/Japanese coverage. Apply the same gate to a newly offered language before it can enable telemetry. The Japanese Godot tutorial in F22 informs focus/minimum-size checks without proving runtime qualification.
