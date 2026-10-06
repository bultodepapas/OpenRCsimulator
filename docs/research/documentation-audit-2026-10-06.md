# Auditoría de la documentación — 2026-10-06

Revisión senior de toda la documentación del repositorio (ocho documentos raíz, 17 planes en `docs/`, 167 informes y 297 ficheros de evidencia en `docs/research/`, `research/`, `tools/`, `assets/`, `prototypes/`). Objetivo: entender el proyecto, encontrar qué documento responde a cada pregunta, detectar contradicciones y dejar un sistema de documentación que tres desarrolladores en paralelo puedan mantener. Resultado principal: el [mapa de documentación](../README.md) y el [índice de investigación](README.md). Este informe recoge el método, los hallazgos con sus líneas, lo que se ha cambiado y lo que queda para cada pista.

**Método.** Lectura directa de los documentos raíz, el ROADMAP y las cabeceras de todos los planes; tres lectores paralelos de solo lectura (planes de aviones; planes de sistema; carpetas de investigación y enlaces) con comprobación de cada enlace relativo con `os.path.exists`; `git status`, `git log` y las fechas de modificación para saber qué estaba en curso. Nada de lo que otros tenían sin confirmar se ha tocado. Las líneas citadas son las del árbol de trabajo a las 12:40–13:30 UTC del 2026-10-06 y pueden haberse movido.

**Cifras.** Proyecto de dos días (primer commit 2026-10-05 13:26 UTC), 70 commits, tres prereleases (`v0.1.0-rc1…rc3`), cuatro aviones en el catálogo. `LEARNINGS.md` 115 KB (45 commits), `ROADMAP.md` 54 KB (35 commits), `RESEARCH.md` 321 KB (congelado de hecho: cero enlaces a `docs/research/`). Idioma: documentos raíz en inglés salvo LEARNINGS (mayoritariamente español); planes 15 español / 2 inglés (LANDSCAPE, FIRST-LAUNCH); `docs/research/` 149 español / 18 inglés. Trece espacios de nombres de pasos (D/E/F/G/PT, `-R`, M5-W, UI-, VQ-, L, SM-, US-/US-V, EX-, AV-, P51-/V) sin registro central.

## 1. El alma del proyecto, en una frase

Un simulador de aeromodelismo de código abierto visto desde el piloto, hecho por un piloto RC para que la radio en la mano y el avión en la pantalla se sientan como los reales; se construye en pasos pequeños con prueba objetiva, con cada número etiquetado por su evidencia, distinguiendo verificar de validar, parando en puertas donde decide el propietario y guardando toda la investigación en el repositorio. Está escrito en [docs/README.md § What this project is](../README.md#what-this-project-is).

## 2. Hallazgos

Gravedad: **A** rompe un clon limpio o induce a error a quien lo lea; **B** contradicción o estado obsoleto; **C** consistencia y limpieza. «Pista» es quien debe corregirlo. Lo marcado ✅ se ha corregido en esta entrega.

### A — rompen un clon limpio o engañan

| # | Hallazgo | Dónde | Pista |
| --- | --- | --- | --- |
| A1 ✅ | `.gitignore` tenía `references/` sin barra inicial, así que ignoraba también `docs/research/visual-quality-implementation/VQ-01b/references/` (dos fotos CC BY-SA 2.0 con `sources.json`); `VQ-01b/REFERENCES.md` quedaba roto en un clon limpio. Ahora `/references/` (solo la raíz) y la carpeta de VQ-01b aparece como sin versionar, lista para confirmar | `.gitignore:7`; `VQ-01b/REFERENCES.md:3,7,15` | Calidad visual confirma la carpeta |
| A2 ✅ | Ancla rota en la guía del jugador: `../README.md#aircraft`; el encabezado es «Aircraft hangar» | `docs/FIRST-LAUNCH.md:3` | — |
| A3 ✅ | `AGENTS.md` decía que Inicio ofrece tres aviones; el catálogo tiene cuatro (P-51D experimental) | `AGENTS.md:18` | — |
| A4 | 228 enlaces clicables apuntan a la carpeta ignorada `references/`: 9 en planes (`AVANTI-S-PLAN.md:9,107,138`, `UGLY-STIK-PLAN.md:45`, `UGLY-STIK-PLAN-v5.md:52`, `UGLY-STIK-VISUAL-PLAN.md:60-63`) y 219 en 30 informes (lista completa en la tabla del lector: `avanti-s-resources.md` 32 enlaces, `extra-300-resources.md`, `extra-300-round2.md`, `ugly-stik-local-audit.md`, `ugly-stik-new-files*.md`, `ugly-stik-resources.md`, `aircraft-reference-index.md`…). Todos resuelven en esta máquina y ninguno en un clon. Convención adoptada: mencionarlos como texto «solo local: `references/…`», no como enlace | planes e informes citados | Cada pista en su siguiente paso |
| A5 | Enlaces a `app/captures/` (ignorada) en informes del modelo | `ugly-stik-engine-v5.md:30-33`, `ugly-stik-model-v4.md:101` | Modelo |
| A6 | Enlaces a ficheros aún sin versionar: `docs/P51-VISUAL-PLAN.md`, `docs/research/p51-visual-review-v1.md`, `research/p51/p51-02/visual-review-2026-10-06/`, `…/photo/metrics-2026-10-06.json`, `visual-quality-implementation/L6c/` (y dentro de L6c, cuatro PNG y `kit/` todavía inexistentes). Se arreglan solos al confirmar; regla: el documento y lo que enlaza van en el mismo commit | ROADMAP, LEARNINGS, P51-PLAN, VQ-PLAN, LANDSCAPE-PLAN, L6c/README | P-51, calidad visual |
| A7 | El estado del ROADMAP es anterior a la reparación de vuelo: «full rudder holds 63° of sideslip» y «spiral stable both» siguen en *Known limits* y en D8b, cuando el informe de reparación da un pico de β de 19,9° en el doblete y una raíz espiral positiva a 10 y 15 m/s | `ROADMAP.md:44-49,130`; [informe](flight-repair-implementation.md) | Física |
| A8 | El catálogo define FLYABLE como «validated handling» mientras Gate 2 (validación con piloto) sigue abierta; el README y el plan dicen «under evaluation». O se cambia la definición o el Stik pasa a EXPERIMENTAL hasta Gate 2 | `app/app_state/aircraft_catalog.gd:7,23-24`; `README.md:30` | Propietario con física y UI |

### B — contradicciones y estado obsoleto

| # | Hallazgo | Dónde | Pista |
| --- | --- | --- | --- |
| B1 | Gate F («arquitectura del modelo antes de M2») no está etiquetada: la decisión del 2026-10-06 (cargas locales de ala y colas) ya hizo lo que Gate F preguntaba, pero la fila de DECISIONS no la nombra, el ROADMAP mantiene Gate F y E0a sin cambios y la nota dice «no declarar E0 completo». E1 (tren) ha empezado el 2026-10-06 antes de que Gate 2 y Gate F consten como decididas | `ROADMAP.md:144,150,290-300`; `DECISIONS.md` | Física, propietario |
| B2 | Apéndice en español dentro del ROADMAP (en inglés), colocado tras la revisión #3 en vez de en *Where we are*, que enlaza solo el informe y no los planes de reparación | `ROADMAP.md:290-300` | Física |
| B3 | El ROADMAP no enlaza LANDSCAPE-PLAN, SMOKE-PLAN, FLIGHT-MODEL-ROBUSTNESS-PLAN ni RUDDER-REPAIR-PLAN; Gate L no aparece; «three-entry catalog» (hay cuatro); «no menus beyond Home (UI-B)» cuando ya hay pausa y Ayuda; los puntos de M5 «camera options» y «settings persistence» pertenecen hoy a VQ-03 y UI-07/08 | `ROADMAP.md:32,50,185-186` | Física (dueña del ROADMAP) |
| B4 | DECISIONS tenía una decisión en prosa fuera de la tabla (reparación de vuelo) y «Open: … a second aircraft» con cuatro aviones en catálogo ✅ (fila añadida, prosa conservada como nota; lista *Open* actualizada) | `DECISIONS.md:73-88` | — |
| B5 | LEARNINGS declara «newest first within each section» pero las secciones fechadas por pista se añaden en orden cronológico creciente, con una de 2026-10-05 detrás de varias de 2026-10-06, y cuatro subtítulos sin fecha | `LEARNINGS.md:191-640` | Propietario: decidir estructura (§4) |
| B6 | EXTRA-300-PLAN se contradice: la línea 113 dice que solo EX-00/01/02/04 están hechos mientras la tabla marca ✅ EX-03/05/07/11 y la cabecera los da por hechos; «No se implementó código» (L148), «siguiente EX-01 → EX-02» (L150), «EX-03 o EX-04» (L152) y «rutas todavía inexistentes» (L63) obsoletos; «## 10.» duplicado (L146, L156); IDs con guion bajo `gp_extra_300s_60` (L19, L91) frente al catálogo `gp-extra-300s-60`; EX-07 hecho con su dependencia EX-06 abierta; la física usa la APC 12×6 del Stik y el visual una 12×8 sin anotarlo; `aircraft-reference-index.md:13,15` aún dice «planned second aircraft» | `docs/EXTRA-300-PLAN.md` | Extra |
| B7 | AVANTI-S-PLAN: «rutas aún inexistentes» (L55), «integración AV-02 pendiente» (L107, L134), «la maqueta permanece aislada» (L154) contradicen L156-160 (integrada como AV-03); AV-03 ✅ con AV-02 incompleta; AV-05 etiquetado G1 (G1 es la tabla de hélice) y AV-09 cita «E0» inexistente; ID `sebart_avanti_s_a200_p100rx` (L15) frente a `sebart-avanti-s-a200-p100rx`; no existe `appearance.json` (los colores van en `geometry.json`) y el README del asset dice «no livery» mientras el alt del README dice «blue, white and red»; cuatro informes no enlazados desde el plan (ahora sí desde el índice) | `docs/AVANTI-S-PLAN.md`; `aircraft-reference-index.md:30,38` | Avanti |
| B8 | P51-PLAN: la cabecera omite P51-02c y no sube la revisión; datum contradictorio («y = 0 en el eje de la hélice», L15, frente a la línea de referencia del fuselaje con el eje del cono 0,006 m arriba, P51-VISUAL-PLAN:31 y `source.json:34`, que es lo correcto; el README del asset repite la versión obsoleta); error de perfil «7,8 px» frente a 7,7; sin columna de dependencias (P51-07 hecho con P51-04/06 pendientes); `verify_p51.gd:1` dice «P5-02» | `docs/P51-PLAN.md:3,15,26`; `assets/aircraft/p51d-mustang-120/README.md:5` | P-51 (en curso: coordinar) |
| B9 | P51-VISUAL-PLAN: «Hito M1/M2/M3» locales chocan con los hitos M1–M5 del ROADMAP; V01–V11 sin prefijo chocan con el atajo «V01/V02» del plan visual del Stik; «Revisión 2» de un fichero nunca confirmado; política de la foto del propietario ambigua (L194) | `docs/P51-VISUAL-PLAN.md:175-180,194` | P-51 |
| B10 | UGLY-STIK-PLAN: reclama todo `assets/aircraft/` y `app/aircraft/` (L56), que hoy comparten cuatro pistas ✅ (acotado en AGENTS); coste de US-08 en la tabla es el de v3 (L18) frente a v4 (L28); L43-74 copiado de la v5 aunque US-02 está cerrado; motor v5 no mencionado; revisión 6 solo en git | `docs/UGLY-STIK-PLAN.md` | Modelo |
| B11 | UGLY-STIK-VISUAL-PLAN: el cuerpo (L26-160) sigue en futuro («V01 guardará») con todo marcado hecho; L59 «sin ruta local verificada» para las fotos A/B; contrato con `gear` (L135) frente al plan principal sin `gear` (L62) | `docs/UGLY-STIK-VISUAL-PLAN.md` | Modelo |
| B12 | MENU-PLAN: línea de estado «propuesta… no implementa pantallas» con UI-00…05 hechos; «Estado (2026-10-05)» con filas del 06 y fuera de orden; «primer cambio recomendado UI-00 → UI-01a» (L475); tres frases que aún proponen español por defecto (L254, L266, L508) superadas por UI-01d; «un único avión» (L86) y «avión n de 3» (L467); «`openrc-field v1` pendiente de L5» con L5 hecho (L88); etiqueta local `v0.1.0-rc1` (L99); anclas de código obsoletas (`flight_session.gd#L152/#L223`, `main.gd#L219`…) que ya no señalan lo que citan | `docs/MENU-PLAN.md` | UI |
| B13 | VISUAL-QUALITY-PLAN: numeración salta de §15 a §18; «siguiente L6a» (L335) obsoleto; L3 dice «después L9a» y L251 «en paralelo»; `extra_300s_model.gd` como «preview EX-02» (L22) cuando vuela; la tabla §6 aún lee como si Kenney fuera la elección (fue Quaternius); L5/L6a/b/c con estado duplicado en LANDSCAPE y aquí (tres sitios: ROADMAP, VQ, LANDSCAPE) | `docs/VISUAL-QUALITY-PLAN.md:3,22,142-143,251,335,350-356` | Calidad visual (en curso) |
| B14 | LANDSCAPE-PLAN: nombra `render/vegetation.gd`, que no existe (la arboleda es `treeline.gd`, `tree_assets.gd`, `treeline.gdshader`, `tree_identity.gdshaderinc`); `tools/terrain/` no existe; Filmic 0,8 (L51, L200) cuando L1b entregó ACES 0,6; L228 «assets en `assets/landscape/`» frente a L14 (`app/assets/landscape/`); L4 y L15d usan deriva «× `sim_clock`» que WIND-PLAN:368-372 prohíbe; fecha de cabecera anterior al contenido | `docs/LANDSCAPE-PLAN.md:3,51,144,183,200,225,228` | Calidad visual (en curso) |
| B15 | WIND-PLAN: la auditoría §2 y §4.5 describen el modelo de seis estaciones con déficit de pérdida, eliminado por D9-R2 (`physics/aero.gd:5`); el viento pasa ahora por `physics/dynamics.gd`; esto invalida la premisa de W05c. Introduce Gates W-A/W-B ausentes del ROADMAP | `docs/WIND-PLAN.md:33,175` | Física/viento antes de W01 |
| B16 | ROBUSTNESS y RUDDER: cuerpos en forma de propuesta («cambios de física pendientes», L5; «no aplica aún… a producción», L96; «la implementación permanece pendiente», RUDDER L75) con la actualización del 06 encima diciendo que está implementado; `D8b-R1` (matriz de manejo multi-eje) no aparece en ningún otro sitio; «D8a-R» significa «cerrar y entregar» en RUDDER y «evaluador compartido» (D8a-R1) en ROBUSTNESS y ROADMAP | `docs/FLIGHT-MODEL-ROBUSTNESS-PLAN.md:5,96`; `docs/RUDDER-REPAIR-PLAN.md:5,13,75` | Física |
| B17 | «Traza v4» reclamada por tres planes con contenidos distintos: WIND (L346), SMOKE (L279, que además propone fichero auxiliar) y ROBUSTNESS §6 (L84) | planes citados | Física coordina el formato de traza |
| B18 | SMOKE-PLAN no aparece en el ROADMAP (ni estado ni punto en M5); solo LEARNINGS lo enlaza ✅ (ahora el mapa y el índice) | `ROADMAP.md:176-189` | Física (ROADMAP) |

### C — consistencia y limpieza

| # | Hallazgo | Dónde | Pista |
| --- | --- | --- | --- |
| C1 ✅ | Sin índice de `docs/` ni de `docs/research/`; diez informes huérfanos (solo enlazados desde otro informe): `avanti-s-additional-angle-sources`, `avanti-s-controls-and-installation`, `avanti-s-geometry-followup`, `flight-robustness/repair-diagnostics`, `ugly-stik-local-audit`, `ugly-stik-model-v4-equipment`, `ugly-stik-new-files-cad`, `ugly-stik-new-files-visual`, `ugly-stik-sources`, `visual-quality-supplement-plugins-2026-10-06`. Todos enlazados ahora desde el índice | `docs/research/` | — |
| C2 ✅ | Siete `.pyc` versionados (`research/avanti-s/refinement-v4/__pycache__/`, `research/ugly-stik/model-v3/__pycache__/`, `research/p51/p51-02/silhouette/__pycache__/` y `photo/__pycache__/`) y `app/tests/__pycache__/` sin versionar. `.gitignore` ignora ahora `__pycache__/` y `*.pyc`; falta sacarlos del índice (§4) | `.gitignore` | Propietario |
| C3 | 61 ficheros `.uid` sin versionar junto a 87 versionados. La revisión #2 del ROADMAP (punto 10) dice confirmarlos cuando aparezcan | `app/**/*.uid` | Propietario |
| C4 | Nombres: IDs de paso en minúscula en `research/` (`av01`, `ex01`) y mayúscula en `docs/` (`L5`, `VQ-01a`); slugs del menú en inglés 01–10 y en español 11–25; sidecars JSON que no siguen el nombre del informe (`avanti-s-contour-v3-*.json` ↔ `avanti-s-contour-refinement-v3.md`); sufijos de fecha irregulares dentro de calidad visual. Registrado como convención observada en el índice; no se renombra nada | `docs/research/` | — |
| C5 | `tools/readme/` sin README (documentado en `docs/media/README.md`); `assets/landscape/` sin README (solo `PROVENANCE.json`); `research/p51/p51-01/` vacío | `tools/`, `assets/`, `research/` | Calidad visual, P-51 |
| C6 | Visores HTML de `research/avanti-s/` con diez destinos rotos, incluido un marcador `__REPORT__` sin rellenar en `refinement/review.html` | `research/avanti-s/*/*.html` | Avanti |
| C7 | GODOT-SKILLS instala en una ruta de Codex (`~/.codex/skills/`) no reproducible desde el repo; lenguaje de chat («desde el siguiente turno»); enlazado solo desde LEARNINGS ✅ (ahora desde el mapa) | `docs/GODOT-SKILLS.md` | Herramientas |
| C8 | Dos planes históricos (`UGLY-STIK-PLAN-v4/v5`) conviven con los vigentes en `docs/`; llevan banda de archivo correcta. Propuesta: `docs/archive/` cuando el equipo de modelo lo decida (hay que mover los enlaces de `UGLY-STIK-PLAN.md:3` y `v5:5`) | `docs/` | Modelo, propietario |
| C9 | Nota de proceso: el commit `db3b58c` («Refactor code structure for improved readability and maintainability») contiene la reparación de vuelo, cambios de UI y del Extra y regraba cuatro goldens, contra la regla 8 del ROADMAP (un equipo por commit, prueba en el mensaje) y repitiendo el hallazgo 16 de la revisión #3. En un árbol compartido donde el propietario confirma con `git add -A`, la única defensa es que cada pista deje su lista de ficheros y su mensaje listos (§5) | `git log` | Propietario |

## 3. Cambios aplicados en esta entrega

Solo ficheros nuevos y ficheros raíz que nadie tenía en edición, con sustituciones exactas que fallan si el texto no coincide. No se ha movido, renombrado ni borrado nada; no se ha confirmado ni preparado (`git add`) nada.

| Fichero | Cambio |
| --- | --- |
| `docs/README.md` (nuevo) | Mapa de documentación: alma, orden de lectura por perfil, documento canónico por pregunta, registro de pistas/planes/IDs/propiedad/evidencia, espacios de nombres de pasos, puertas, dónde vive cada cosa, convenciones, mantenimiento |
| `docs/research/README.md` (nuevo) | Índice de investigación: la regla de las dos carpetas, puntos de entrada por pista (incluye los diez huérfanos), patrones de nombres, cómo añadir investigación |
| `docs/research/documentation-audit-2026-10-06.md` (nuevo) | Este informe |
| `README.md` | Fila `docs/` y línea de enlaces apuntan al mapa y al índice |
| `AGENTS.md` | Enlace al mapa e índice en la cabecera; cuatro aviones en la descripción de Inicio; *Parallel work* remite al registro, acota la pista del modelo a `ugly-stik-60` y añade las pistas Extra/Avanti, menús y calidad visual con sus rutas; regla de comprobar `git status` antes de editar documentos compartidos; punto de convenciones en el acuerdo de trabajo. No se ha tocado la fila *Captures* que otra pista estaba editando |
| `CONTRIBUTING.md` | Sección *Documentation* con las convenciones en corto |
| `DECISIONS.md` | Fila para la decisión de reparación de vuelo (resumen fiel en inglés; la prosa en español se conserva bajo *Notes*), fila para el sistema de documentación (provisional, a confirmar por el propietario), lista *Open* sin «second aircraft». La fila E1 que la física añadió a la vez queda intacta |
| `docs/FIRST-LAUNCH.md` | Ancla `#aircraft-hangar` |
| `.gitignore` | `/references/` anclado a la raíz; `__pycache__/` y `*.pyc` |

**Prueba.** Comprobador de enlaces relativos y anclas (`linkcheck.py`, en el scratchpad de la sesión) sobre los ocho documentos tocados: 0 enlaces rotos. `git check-ignore`: `references/ugly-stik` sigue ignorado; `VQ-01b/references/sources.json` ya no; `__pycache__/` ignorado. `git status` muestra solo estos ficheros como míos; los ficheros de las pistas P-51, calidad visual y física siguen con sus propios cambios sin alterar. Entrega documental: no cambia código ni datos; `app/test.sh` no aplica.

## 4. Decisiones que necesitan al propietario

1. **Idioma.** Convención adoptada como provisional: raíz e índices en inglés; planes e informes en inglés o español, uno por fichero. Alternativas: todo en inglés (traducir 15 planes y 149 informes: caro) o todo en español (la cara pública del README y las releases ya está en inglés). Recomendación: mantener la provisional.
2. **LEARNINGS.md.** Hoy mezcla secciones temáticas en inglés (hasta la línea 190) con secciones fechadas por pista en español, en orden cronológico creciente. Opciones: (a) dejarlo así y declararlo (quitar «newest first»); (b) un fichero por pista (`docs/learnings/<pista>.md`) con LEARNINGS como índice; (c) ordenar por fecha descendente en una sola lista. Recomendación: (b) en cuanto las tres pistas activas confirmen, porque reduce los conflictos de edición en el fichero más tocado del repo (45 commits en dos días).
3. **ROADMAP.md.** *Where we are* tiene párrafos de 1.500 caracteres por pista que duplican los planes. Recomendación: una línea por pista con el estado y el enlace al plan (texto listo en §5), mover el apéndice en español de la reparación a *Where we are* en inglés, enlazar LANDSCAPE/SMOKE/ROBUSTNESS/RUDDER, y actualizar *Known limits* tras la reparación (A7).
4. **Gate F.** Etiquetar la decisión del 2026-10-06 como Gate F (y decir qué queda abierto: E0b propwash, G2) o reabrirla con la evidencia pendiente. Sin esto, M2 ha empezado (E1) con una puerta formalmente sin pasar.
5. **FLYABLE del Stik** (A8): definición o estado.
6. **Archivo.** Crear `docs/archive/` y mover `UGLY-STIK-PLAN-v4.md` y `-v5.md` (con los dos enlaces que los nombran) cuando el equipo de modelo lo acepte.
7. **Limpieza del índice de git:** `git rm --cached -r research/avanti-s/refinement-v4/__pycache__ research/ugly-stik/model-v3/__pycache__ research/p51/p51-02/silhouette/__pycache__ research/p51/p51-02/silhouette/photo/__pycache__` (la pista P-51 ya ha borrado dos de ellos del disco), y confirmar los 61 `.uid`.
8. **`VQ-01b/references/`**: confirmar la carpeta (licencias CC BY-SA 2.0 con atribución en `sources.json`) o renombrarla a `visual-references/` si se prefiere no tocar la regla del ignore; en ambos casos verificar desde un `git clone` limpio, como pide AGENTS.md para cambios de `.gitignore`.

## 5. Texto listo para pegar

**Una línea por pista para `ROADMAP.md` → *Where we are*** (sustituye los párrafos de UI, calidad visual, Extra y P-51; los detalles ya están en cada plan):

```markdown
- **Tracks** (full registry, owned paths and conventions: [docs/README.md](docs/README.md)):
  - UI ([MENU-PLAN](docs/MENU-PLAN.md)): UI-00…05 done (Home, language, pause, end flight, build identity, Help, aircraft selector); next UI-06/07/08.
  - Visual quality ([VISUAL-QUALITY-PLAN](docs/VISUAL-QUALITY-PLAN.md), L steps defined in [LANDSCAPE-PLAN](docs/LANDSCAPE-PLAN.md)): VQ-01a/b, L5, L6a/b done; L6c numbers done, owner playtest pending (Gate L); next L9a, VQ-02.
  - Extra 300S ([EXTRA-300-PLAN](docs/EXTRA-300-PLAN.md)): flyable, experimental; next EX-06, EX-08, EX-09.
  - Avanti S ([AVANTI-S-PLAN](docs/AVANTI-S-PLAN.md)): preview, Fly disabled until the turbine branch (AV-05).
  - P-51D 1/4 ([P51-PLAN](docs/P51-PLAN.md), shapes in [P51-VISUAL-PLAN](docs/P51-VISUAL-PLAN.md)): flyable, experimental; next P51-04/06/08/09 and V01–V03.
  - Flight-model repair ([FLIGHT-MODEL-ROBUSTNESS-PLAN](docs/FLIGHT-MODEL-ROBUSTNESS-PLAN.md), [RUDDER-REPAIR-PLAN](docs/RUDDER-REPAIR-PLAN.md), [report](docs/research/flight-repair-implementation.md)): D9-R1/R2, D4-R1, D1-R1, D8a-R1, D10-R done; Gate 2-R, E0b, G2 open.
  - Proposals, not started: [SMOKE-PLAN](docs/SMOKE-PLAN.md) (SM-00…09), [WIND-PLAN](docs/WIND-PLAN.md) (M5-W00…08).
```

**Entrada para `LEARNINGS.md`** (bajo *Process*, o como sección fechada «2026-10-06 · Documentación — mapa, registro e índice»):

```markdown
- **Un repositorio de dos días puede tener 17 planes, 167 informes y 13 espacios de nombres de pasos sin que nadie sepa dónde está el estado.** La revisión encontró el mismo paso con estado en tres sitios (ROADMAP, VQ-PLAN, LANDSCAPE-PLAN), planes cuya cabecera contradecía su propia tabla (EXTRA L113), un plan que auditaba un modelo ya eliminado (WIND tras D9-R2) y 228 enlaces a una carpeta ignorada. *Ahora:* `docs/README.md` registra pistas, planes, prefijos y rutas; el estado de un paso vive en su plan y el ROADMAP lleva una línea por pista; los enlaces se comprueban desde un clon limpio. Prueba: [auditoría](docs/research/documentation-audit-2026-10-06.md), comprobador de enlaces sin fallos sobre los ocho documentos tocados. (2026-10-06)
- **Con tres pistas en el mismo árbol, `git status` antes de editar un documento compartido.** ROADMAP, LEARNINGS, DECISIONS y AGENTS cambiaron en disco mientras se revisaban; las ediciones se hicieron como sustituciones exactas que fallan si el texto no coincide, sin tocar las líneas de otros y sin `git add`. (2026-10-06)
```

**Mensaje de commit para esta entrega** (ficheros: `docs/README.md`, `docs/research/README.md`, `docs/research/documentation-audit-2026-10-06.md`, `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `DECISIONS.md`, `docs/FIRST-LAUNCH.md`, `.gitignore`):

```
Docs: documentation map, track registry and research index

Add docs/README.md (canonical document per question, registry of 15 tracks
with plan, step-ID prefix, state, gate, owned paths and evidence; step-ID
namespaces; gates; folder rules; writing conventions) and
docs/research/README.md (entry points per track for 167 reports, naming,
how to add research). Record the audit in
docs/research/documentation-audit-2026-10-06.md.

Point README, AGENTS (four aircraft, full track ownership, git status rule)
and CONTRIBUTING at the map; DECISIONS gets the flight-repair decision as a
table row and the documentation system as a provisional decision.
Fix FIRST-LAUNCH anchor (#aircraft-hangar). .gitignore: anchor /references/
to the root (VQ-01b/references was being ignored), ignore __pycache__.

Proof: link checker 0 broken links/anchors on the 8 touched documents;
git check-ignore confirms root references/ still ignored and
VQ-01b/references not; documentation only, no code or data changed.
```

## 6. Qué queda para cada pista (resumen)

| Pista | Acciones |
| --- | --- |
| Física (ROADMAP) | A7, B1, B2, B3, B16, B17, B18; §5 línea por pista |
| Modelo (Stik) | A5, B10, B11; mención «solo local» para `references/` |
| Extra | B6 |
| Avanti | B7, C6 |
| P-51 | A6, B8, B9, C5 (`p51-01` vacío) |
| UI | B12 |
| Calidad visual / paisaje | A1 (confirmar carpeta), A6 (L6c), B13, B14, C5 |
| Viento | B15 antes de W01 |
| Propietario | §4 (idioma, LEARNINGS, ROADMAP, Gate F, FLYABLE, archivo, `git rm --cached`, `.uid`) |
