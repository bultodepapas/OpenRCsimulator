# Investigaciones para la entrada y los menús de OpenRC

2026-10-20: [UI-30 — menu system audit at 1080p and above](UI-30/README.md). Software-rendered (Xvfb/llvmpipe) captures of the production app from 1920×1080 to 5120×1440 (16:9, 16:10, 21:9, 32:9; EN/ES; 150% text), code review of pause, aircraft switching, theme and chrome, and 62 graded findings. The repair order is UI-31…38 in [the redesign plan](../../MENU-REDESIGN-PLAN.md#11-ui-30-audit-repairs).

2026-10-19: [UI-03-R1 — window-close trace preservation and runtime audit](../visual-quality-implementation/VQ-01c/runtime-audit-2026-10-19/README.md). Actual Windows close reproduction, save-failure/Workshop regressions, scoped verification and explicit remaining golden/performance gates.

## UI-01-R1 — Fly directly into flight, 2026-10-19

Home's airplane Fly action now resumes the accepted session directly when controller readiness is verified. The deferred handoff samples without advancing incremental throttle, preserves the selected launch power, and yields to an explicit pause or a newer flight route. Unverified or unavailable controllers still show recovery; helicopter startup retains its existing flow.

Native Windows Godot 4.7.2 headless checks passed `test_controller_pause_recovery.gd` (59/59, now including direct Fly, runway idle and advancing ticks without Continue), `test_controller_menu.gd` (48/48) and `test_ui_input.gd`. All three changed scripts passed `--check-only`. `test_ui_home.gd` passed its launch assertions but retained 37 layout failures, also reproduced with the pre-change `app_root.gd` (blob `b6f2d8937`) in the isolated imported baseline. No Home layout, physics or aircraft data changed in this follow-up.

## UI-02-R2 — restart directly into flight, 2026-10-19

Airplane restarts from R, the mapped controller, Pause and the accident report now resume as soon as the accepted start and controls are ready. The shell samples controller readiness without advancing simulation or incremental throttle. An already armed radio retains readiness under unchanged device/profile ownership; low-throttle gates still apply to device/profile and focus recovery. Rate throttle uses the selected launch power, including runway idle. Unready, invalid or disconnected controls and rejected starts retain the visible recovery menu. Helicopter restart behavior is unchanged.

Native Windows Godot 4.7.2 headless verification passed:

- `test_controller_pause_recovery.gd`: 59/59, including repeated R restarts, menu Restart, accident restart, armed radio absolute throttle, zero runway rate throttle, frozen unverified input, invalid input, focus loss, rejected runway reset and explicit keyboard recovery.
- `test_controller_menu.gd`: 48/48, including separate flight/menu devices, held restart suppression and helicopter recovery.
- `test_controller_integration.gd`: 27/27; `test_controller_routing_audit.gd`: 21/21; `test_session_guards.gd`: 32/32; `test_accident_integration.gd`: 77/77.
- `test_ui_pause.gd` and `test_ui_screen_stack.gd`: all checks passed. The five changed GDScript files also passed `--check-only`.

`test_golden.gd` fails all four existing recordings. The same numerical errors were reproduced in an isolated imported app using the pre-change `flight_session.gd` from `bceb3bd40` (blob `1760f5b28fa8d038b5521fb21bba31418d892103`); physics and aircraft data match that baseline. No golden recordings were regenerated. These are software checks with synthetic devices, not physical-controller qualification.

## UI-02-R1 — pause and restart recovery, 2026-10-17

Native Windows Godot 4.7.2 probes reproduced four defects against `1ef60b44`: R and the accident report reset the selected controller's session into a pause with no visible Continue action; restarting after controller loss resumed simulation without explicit device recovery; rejected keyboard runway restarts closed Pause; and the runway reset installed idle simulation inputs but left pilot commands at the generic 50% throttle default. The next keyboard sample or staged gamepad resume reapplied that power. The shell now owns these interactive restart routes and holds the menu through reset validation. Failed starts retain their error, successful controller restarts focus Continue, and runway commands match their solved zero-throttle inputs.

The same synthetic-device probe before/after the repair observed:

| Restart source | Before | After |
| --- | --- | --- |
| R | Paused, no menu | Paused, Continue visible |
| Accident report | Paused, no menu | Paused, Continue visible |
| Lost controller | Running, no recovery menu | Paused, recovery menu visible |

[Controller recovery](../../../app/tests/test_controller_pause_recovery.gd) passed 60/60 checks: repeated restart/Continue cycles, actual engine RPM response, zero throttle after Continue, frozen state, rejected runway reset/retry, report restart, focus loss and explicit keyboard recovery. [Keyboard Pause](../../../app/tests/test_ui_pause.gd) also checks rejected-reset state preservation and repeated pause/restart. Native headless runs passed the runway fleet, controller integration/routing, screen stack, session guards, RC input, accident integration, glow session, language and four golden-flight regressions. No force law, aircraft data or golden recording changed. These checks use synthetic device events and do not establish physical controller or pilot acceptance.

The [neutral-input recording script](UI-06b/pause-restart-2026-10-17/record_neutral.gd) ran the same 120 keyboard-input ticks at 240 Hz, with two markers. Before the initializer repair, [baseline.orfl](UI-06b/pause-restart-2026-10-17/baseline.orfl) recorded 50% demand despite zero raw input. Its [exact replay](UI-06b/pause-restart-2026-10-17/baseline-exact.json) completed before the repair with `solver_changed: false`. The single [idle candidate](UI-06b/pause-restart-2026-10-17/idle-candidate.orfl) retains zero demand on the identical raw-input tape; [baseline CSV](UI-06b/pause-restart-2026-10-17/baseline.csv), [candidate CSV](UI-06b/pause-restart-2026-10-17/idle-candidate.csv) and [candidate export/identity report](UI-06b/pause-restart-2026-10-17/idle-candidate-export.json) retain the observations. Their post-conditioning commands intentionally differ, so they are not an exact-equivalence comparison. Replaying the original 50% command tape through the repaired source completed as a [candidate run](UI-06b/pause-restart-2026-10-17/command-tape-candidate.json), `solver_changed: true` because the session source changed, with [zero trajectory differences](UI-06b/pause-restart-2026-10-17/command-tape-comparison.json). This isolates the input initialization correction from the unchanged flight laws; it does not establish physical realism.

## Earlier investigations

2026-10-15 refinement: [UI-28-R3 — compact flows, categorized Settings and menu sounds](UI-28-R3/README.md). Native EN/ES 720p–4K, enlarged-text Settings, route/persistence checks and a native mixer recording.

2026-10-15 implementation: [UI-22–26-R2 — grounded Home, bounded menus and native 720p–4K evidence](UI-25-R2/README.md). Includes the new scene/scale/theme, compact Home/Pause, Settings/Conditions and EN/ES behavior checks.

2026-10-15 direction revision: [UI-20-R2 — cinematic composition, Godot feasibility and free-resource research](UI-20-R2/README.md). Documents the owner's rejection of the oversized composition, current camera/scale causes, inspected commercial references and implementation options. [Redesign plan revision 7](../../MENU-REDESIGN-PLAN.md) tracks the delivered core slice and remaining acceptance gates.

2026-10-15 implementation follow-up: [UI-22–26-R1 — scalable shell, Settings and compact Pause](UI-22-26-R1/README.md). Native EN/ES captures, 200% text, aspect ratios and display recovery checks.

2026-10-15 visual follow-up: [UI-20-R1 — native Windows menu audit, EN/ES, 720p–4K](UI-20-R1/README.md). Includes 78 native captures, measured text/scale findings, sampled navigation evidence and modern game references. The phased response is [redesign plan](../../MENU-REDESIGN-PLAN.md).

2026-10-14 implementation follow-up: [UI-05-R3 — responsive selection and bounded resource loading](UI-05-R3/README.md). Latest-selection ownership, background loading of selected scenes, headless/native lifecycle checks, five-process comparisons and explicit remaining first-visit stalls.

2026-10-14 research follow-up: [26 — faster aircraft selection without hiding stalls](26-menu-responsiveness-loading.md). Godot documentation, pinned engine source, forum and Reddit findings; ordered loading/texture/selection experiments, acceptance gates and rejected shortcuts. Proposals only; no runtime changes in this investigation.

2026-10-14 responsiveness follow-up: [UI-05-R2 — fast return to recent aircraft](UI-05-R2/README.md), with bounded model/shadow reuse, complete-selector timings, native visual comparisons and lifecycle tests.

2026-10-14 layout follow-up: [UI-06d-R2 — launch captions and live language](UI-06d-R2/README.md) closes the reproduced sidebar-width defect and stale helicopter launch translations, with native captures and input regressions.

2026-10-14 implementation follow-up: [UI-05-R1 — unchanged Home legend reuse](UI-05-R1/README.md), with native measurements, keyboard-layout regression coverage and reference/candidate visual comparisons. Remaining baseline layout and field-validation failures are recorded separately from the optimization's passing checks.

**Fecha:** 2026-10-05. Investigación en internet y contraste con el repositorio para mejorar [MENU-PLAN.md](../../MENU-PLAN.md). Los informes separan documentación, código observado, inferencias de diseño y pruebas todavía pendientes.

**Resultado:** ronda 2, diez informes (01–10) incorporados a la revisión 2 del plan; ronda 3, doce informes más (11–22) con sondas ejecutadas en el Godot 4.7.2 fijado, incorporados a la revisión 3. [sources.json](sources.json) indexa las fuentes de los 22 informes por página y por informe (se regenera con `python3 docs/research/menu-investigations/build_sources.py`); los enlaces explicativos permanecen junto a cada afirmación, no solo en el inventario.

## Ronda 2: las diez preguntas

| # | Investigación | Pregunta de decisión |
| --- | --- | --- |
| 01 | [Escenas, ciclo de vida y pausa](01-godot-shell-lifecycle.md) | ¿Cómo añadir Inicio sin arrancar el vuelo ni bloquear la calibración? |
| 02 | [Input, foco y aislamiento de radios](02-input-focus-radio-isolation.md) | ¿Cómo impedir que navegar mueva el avión o que una radio navegue el menú? |
| 03 | [Preferencias, contenido y versiones](03-settings-content-versioning.md) | ¿Qué guardar y cómo recuperar ajustes inválidos sin perder calibraciones? |
| 04 | [Navegación en simuladores RC](04-rc-simulator-navigation.md) | ¿Qué patrones de selección y acceso al vuelo merecen adaptarse? |
| 05 | [Primera conexión de radio](05-radio-onboarding.md) | ¿Cómo explicar detección, canales, calibración y armado sin exigir un tutorial? |
| 06 | [Entrenamiento y modos](06-training-modes-progression.md) | ¿Qué experiencia educativa cabe antes de aterrizajes, viento o puntuaciones? |
| 07 | [Estilo visual y recursos](07-visual-direction-assets.md) | ¿Qué aspecto propio puede tener OpenRC con los recursos que ya existen? |
| 08 | [Accesibilidad y lectura](08-accessibility-legibility.md) | ¿Cómo hacer legibles los estados, textos y controles y comprobarlo? |
| 09 | [Resoluciones e idiomas](09-responsive-localization.md) | ¿Cómo evitar que la UI se rompa al escalar o traducir? |
| 10 | [Pruebas, rendimiento y exportación](10-testing-performance-export.md) | ¿Cómo demostrar que el menú funciona en el binario que recibe el piloto? |

## Ronda 3: doce preguntas más (motor, herramientas, librerías, ejemplos)

| # | Investigación | Pregunta de decisión | Evidencia propia |
| --- | --- | --- | --- |
| 11 | [Novedades GUI de Godot 4.4–4.7](11-godot-ui-novedades-4x.md) | ¿Qué ofrece el 4.7.2 fijado que el plan no aprovecha o que lo contradice? | [sonda](probes/11-godot-ui-probe.gd) |
| 12 | [Identidad de radios y SDL3](12-identidad-joypads-sdl3.md) | ¿Con qué identidad estable recordar y elegir una radio EdgeTX? | [sonda](probes/12_joypad_identity_probe.gd) |
| 13 | [Plantillas y addons de menús](13-plantillas-menus-godot.md) | ¿Adoptar, adaptar o solo aprender de Maaack, GGT o Input Helper? | ejecución headless en scratchpad |
| 14 | [Demos oficiales de Godot](14-demos-oficiales-godot.md) | ¿Qué patrones de ajustes, escala, traducción y joypads dan las demos MIT? | [sonda](probes/14-demo-patterns-probe.gd) |
| 15 | [Herramientas de prueba de UI](15-herramientas-pruebas-ui.md) | ¿Arnés propio, gdUnit4 o GUT para foco, teclas y radio? | [sonda](probes/15-focus-input-probe.gd) |
| 16 | [Tipografía y fuentes](16-tipografia-fuentes.md) | ¿Fuente predeterminada o una OFL empaquetada, y cómo se ve nítida al 200 %? | [sonda](probes/font_probe.gd), [fontTools](probes/check_fonts.py) |
| 17 | [Autoría del Theme](17-theme-autoria.md) | ¿Cómo construir un Theme revisable en git y con contraste comprobable? | [sonda](probes/17-theme-variation-probe.gd) |
| 18 | [Pantalla, ventana y plataformas](18-pantalla-ventana-plataformas.md) | ¿Qué opciones de Pantalla son seguras en Windows, X11, Wayland y macOS? | sonda headless/Xvfb en scratchpad |
| 19 | [Audio en ajustes y pausa](19-audio-ajustes-pausa.md) | ¿Cómo dar volumen/silencio y congelar el motor sintetizado sin clics ni duplicados? | [sonda sobre la app](probes/19-audio-pause-probe.gd) |
| 20 | [Simuladores abiertos](20-simuladores-abiertos-ui.md) | ¿Qué enseñan FlightGear, CRRCsim, PicaSim y EdgeTX Companion en su código? | lectura de código en commits fijos |
| 21 | [Versión de build en el export](21-version-build-export.md) | ¿Cómo mostrar la misma versión que el ZIP sin Git en el ejecutable? | [sonda de export PCK](probes/21-build-info-probe.sh) |
| 22 | [Referencias UX de videojuegos](22-referencias-ux-juegos.md) | ¿Qué guías de la industria refuerzan, matizan o contradicen el plan? | lectura de guías |

Después de la ronda, la [sonda 23](probes/23-po-translation-probe.sh) comprobó el formato de traducción elegido para UI-01d: un `.po` carga sin importar, entra en el PCK sin filtro de inclusión, y el motor arranca en el idioma del sistema operativo. La [investigación 24 · pausa, foco y entrada](24-pausa-foco-entrada.md) precedió a UI-02: orden real de las notificaciones de foco (en X11 la de aplicación llega 250 ms después de la de ventana), liberación de teclas al perder el foco, orden `_input`/GUI/`_unhandled_input` y que un botón enfocado no consume Enter ni Espacio. La [investigación 25 · etiquetas de teclado](25-etiquetas-teclado.md) precedió a UI-04b: qué API da el carácter que imprime la distribución del jugador, qué devuelve cada plataforma y cómo probarlo sin pantalla.

Las sondas viven en [probes/](probes/), **fuera de `app/`**: `app/test.sh` no las parsea y no pueden romper el trabajo paralelo. Cada una indica en su cabecera cómo ejecutarla con `.tools/Godot_v4.7.2-stable_linux.x86_64`. Se ejecutaron sin GPU, sin pantalla real, sin sonido y sin radio conectada: lo que dependa de hardware sigue marcado como **Pendiente** en cada informe.

### Decisiones de la ronda 3

- **Sin plantillas, addons ni framework de pruebas.** Las plantillas revisadas pausan con `SceneTree.paused`, añaden autoloads y botones joypad a `ui_*` y escriben preferencias en ejecuciones headless (13). gdUnit4 entrega las teclas dos veces al nodo raíz y GUT crea teclas sin `physical_keycode` (15). Se extiende el arnés propio y se aprende de las demos oficiales (14).
- **Theme en código, foco de teclado visible, scroll que sigue al foco.** `ui_theme.gd` genera el Theme (un `.tres` guardado cambia 16 líneas sin cambiar valores) y un test mide contraste sobre el Theme real (17). Godot 4.6+ oculta el foco ganado con ratón y `ScrollContainer.follow_focus` es falso por defecto (11).
- **Radio identificada por familia USB, no por GUID.** La GUID de SDL3 incluye la versión de firmware de EdgeTX; todas las radios EdgeTX comparten `1209:4F54` (12).
- **El motor suena durante cualquier pausa hoy.** Medido en la app real; la corrección (`stream_paused` y hélice congelada) entra en UI-02 (19).
- **Pantalla: modo y tamaño de ventana, no resolución.** Godot 4.7.2 no cambia el modo de vídeo del monitor; Compatibility solo ofrece VSync activado o desactivado; nunca menos de 20 fps por la física a 240 Hz (18).
- **Versión de build inyectada al exportar.** Un `EditorExportPlugin` añade `build_info.json`; CI hoy nombra los ZIP con la rama y el `.exe` declara 1.0.0.0 (21).
- **Fuente predeterminada en UI-01; Atkinson Hyperlegible Next en un paso propio** con su OFL empaquetada (16). Remapeo de teclado y pista de primer vuelo suben de prioridad (22); calibración con «Atrás» y Volar protegido frente a doble pulsación (20).

## Cómo leer la evidencia

- **Documentado:** la fuente primaria explica la capacidad o el flujo; las afirmaciones llevan enlaces junto al texto.
- **Observado en código:** se inspeccionó el archivo del repositorio indicado. El trabajo paralelo puede cambiarlo después de esta fecha.
- **Calculado:** existe una operación reproducible, con entradas y límites explícitos.
- **Propuesto:** recomendación para OpenRC; no implica que la app o un producto consultado ya la implemente.
- **Pendiente:** prueba con el Godot fijado, screenshot, experimento o evaluación con piloto que aún no se realizó.

Los manuales comerciales sirven de referencia funcional, no de permiso para redistribuir sus imágenes ni de prueba independiente de calidad. Las guías WCAG/Xbox aportan criterios que podemos adoptar; no convierten este plan en certificación de accesibilidad. Las páginas de Godot `stable` pueden cambiar: verificar APIs y comportamiento en el binario fijado antes de implementar.

## Decisiones de la ronda 2 que cambian la implementación

- UI-01 retira navegación joypad implícita antes de mostrar botones: el tag exacto del motor ya asocia ejes a `ui_*`.
- Inicio adopta **Campo tranquilo**, con captura propia y panel opaco; «Club» y «Banco de trabajo» quedan como direcciones acotadas para paisaje y fichas.
- Se mantienen Volar y la combinación activa visibles. Se posponen filtros, categorías vacías, talleres 3D y lecciones puntuadas sin objetivos detectables.
- UI-09 se divide en **UI-09a** (escala, reflujo y pseudolocalización) y **UI-09b** (pantalla con confirmación/reversión). El temporizador de reversión funciona mientras la simulación está pausada.
- La pantalla de radio comunica conexión, perfil, movimiento observado y armado por separado; Classic/Advanced se comparan con hardware antes de cambiar la recomendación del repo.
- UI-11 comprueba tanto el Inicio exportado como el vuelo técnico; un smoke test de traza no acredita que el menú empaquetado funcione.

## Evidencia propia complementaria

[contrast-check.json](contrast-check.json) contiene la comparación de seis pares de una paleta candidata. Se reproduce con:

```sh
python3 docs/research/menu-investigations/check_contrast.py
```

El script usa solo la biblioteca estándar y guarda el resultado junto a sí mismo. Cinco pares cumplen su objetivo declarado; **rojo sobre panel oscuro da 2,61:1 y no llega al objetivo 3:1**. La recomendación es añadir etiqueta y borde adecuados, no confiar en rojo como único indicador. Es cálculo sobre colores planos, no lectura de una captura ni ensayo con usuarios.

Ninguna de las dos rondas ejecuta `app/test.sh` ni modifica `app/`: hay trabajo paralelo en el paisaje, el viento y el humo. La validación documental comprueba enlaces locales, estructura, los 22 informes y la reproducción del cálculo; la ronda 3 añade sondas ejecutadas con el binario fijado, cuya salida se transcribe en cada informe. Las pruebas de UI descritas en los informes pertenecen a su futura implementación.
