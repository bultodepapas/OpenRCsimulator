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

## 3. Cambios aplicados (2026-10-06, dos pasadas)

Sustituciones exactas que fallan si el texto no coincide; nada confirmado ni preparado (`git add`) por la revisión. Los ficheros de la pista P-51 (en curso) no se han tocado.

| Fichero | Cambio |
| --- | --- |
| `docs/README.md` (nuevo) | Mapa: alma, orden de lectura por perfil, documento canónico por pregunta, registro de 15 pistas (plan, prefijo, estado, puerta, rutas, evidencia), espacios de nombres, puertas, dónde vive cada cosa, convenciones |
| `docs/research/README.md` (nuevo) | Índice de los 167 informes por pista (incluye los diez huérfanos y el informe E1), patrones de nombres, cómo añadir investigación |
| `ROADMAP.md` | *Where we are*: las pistas UI, calidad visual/paisaje y Extra en una línea cada una; líneas nuevas para la reparación de vuelo y las propuestas (humo, viento); *Known limits* y *Alpha will not have* actualizados tras la reparación y rc3; **Gate F ✅** (decidida por la reparación) y **E0a parcial**; M5 enlaza WIND y SMOKE y señala VQ-03/UI-07; el apéndice en español se retira (su contenido está en la línea de reparación y en los planes); enlace al mapa. La línea P-51 no se ha tocado |
| `DECISIONS.md` | Filas: reparación de vuelo (resumen fiel; la prosa en español se conserva en *Notes*; marcada como respuesta a Gate F) y sistema de documentación (**Chosen**, por delegación «decide tú»); lista *Open* sin «second aircraft». La fila E1 de física queda intacta |
| `AGENTS.md` | Enlaces al mapa e índice; cuatro aviones; *Parallel work* remite al registro, acota la pista del modelo y añade Extra/Avanti, menús y calidad visual con sus rutas; regla de `git status` antes de editar documentos compartidos; convenciones en el acuerdo de trabajo |
| `README.md`, `CONTRIBUTING.md` | Enlaces al mapa; sección *Documentation* |
| `LEARNINGS.md` | Cabecera describe la estructura real (temático arriba, entradas fechadas por pista al final) y entrada de esta revisión |
| `docs/EXTRA-300-PLAN.md` | Cabecera y L113 coherentes con la tabla; EX-00 ✅; rutas e IDs reales (`gp-extra-300s-60`); §10 marcada histórica, segundo «§10» → §11; nota de hélice 12×6/12×8 |
| `docs/AVANTI-S-PLAN.md` | Frases de «maqueta aislada / rutas inexistentes / integración pendiente» actualizadas a AV-03 hecho; ID de catálogo; AV-05 sin «G1»; AV-09 «E0a–E0b» |
| `docs/MENU-PLAN.md` | Línea de estado real (UI-00…05); cuatro aviones; L5 hecho; nota de que las anclas de código son de `bc078ef` y los defectos se corrigieron; primer cambio marcado hecho |
| `docs/VISUAL-QUALITY-PLAN.md` | Extra vuela como experimental; Kenney → Quaternius en L6a; «siguiente L6a» → hecho |
| `docs/LANDSCAPE-PLAN.md` | `treeline.*` en vez de `vegetation.gd`; ACES 0,6 frente al spike Filmic; rutas de assets fuente/derivados; `tools/terrain/` futuro; nota de viento variable en la deriva `sim_clock`; fecha |
| `docs/WIND-PLAN.md` | Nota: la auditoría de código es anterior a D9-R2; releer antes de W01, rediseñar W05c |
| `docs/FLIGHT-MODEL-ROBUSTNESS-PLAN.md`, `docs/RUDDER-REPAIR-PLAN.md` | Líneas de estado y frases «pendiente» actualizadas a implementado; D8b-R1 señalado como abierto |
| `docs/UGLY-STIK-PLAN.md`, `docs/UGLY-STIK-VISUAL-PLAN.md` | Coste v4 junto al v3; propiedad acotada a `ugly-stik-60`; nota de que la especificación visual se lee como registro de lo construido |
| `app/app_state/aircraft_catalog.gd` | Comentario: FLYABLE = modelo de referencia (trim, goldens, contraste independiente; validación con piloto pendiente en Gate 2); cita P51-03. Solo comentarios; `--check-only` en verde |
| `assets/aircraft/extra-300s-60/README.md`, `docs/FIRST-LAUNCH.md` | Título «flyable (experimental)»; ancla `#aircraft-hangar`; tecla V |
| `.gitignore` | `/references/` anclado a la raíz (A1); `__pycache__/` y `*.pyc` |

**Prueba.** Verificador de enlaces relativos y anclas sobre los 20 documentos tocados: 0 problemas. `--check-only` del catálogo: sin errores. `git check-ignore`: `references/ugly-stik` ignorado, `VQ-01b/references/sources.json` no. La línea P-51 del ROADMAP y la fila E1 de DECISIONS siguen idénticas. Entrega documental; `app/test.sh` no aplica salvo por el comentario del catálogo, cubierto por el parse.

## 4. Decisiones tomadas por delegación del propietario («decide tú», 2026-10-06)

1. **Idioma:** raíz e índices en inglés; planes e informes en inglés o español, uno por fichero (fila *Chosen* en DECISIONS).
2. **Estado en un solo sitio:** el plan es la fuente de verdad de sus pasos; el ROADMAP lleva una línea por pista. Aplicado.
3. **Gate F:** cerrada por la reparación del 2026-10-06 con la propuesta por defecto del ROADMAP (buildup por componentes a partir del oráculo lineal); quedan E0b y G2 como pasos, y Gate 2-R como validación con piloto. Registrado en ROADMAP y DECISIONS.
4. **FLYABLE del Stik:** se redefine la etiqueta (modelo de referencia con validación de piloto pendiente) en vez de degradar el Stik a experimental, que lo igualaría con aviones sin ningún contraste independiente.
5. **LEARNINGS:** se mantiene un solo fichero con la estructura real declarada (temático arriba, entradas fechadas al final). La división por pistas queda como opción si el fichero sigue creciendo (§5).

## 5. Operaciones bloqueadas por el clasificador de permisos: para el propietario

Un lote que movía, borraba y reescribía ficheros fue denegado como «modificación de recursos compartidos». Son operaciones correctas y pequeñas; se dejan con sus comandos para ejecutarlas a mano desde la raíz del repositorio.

1. **Archivar los planes históricos** (y actualizar el enlace de `docs/UGLY-STIK-PLAN.md:3` a `archive/UGLY-STIK-PLAN-v5.md`; dentro de los archivados, cada enlace relativo necesita un `../` más, salvo el que apunta al otro archivado):
   ```sh
   mkdir -p docs/archive && git mv docs/UGLY-STIK-PLAN-v4.md docs/UGLY-STIK-PLAN-v5.md docs/archive/
   ```
2. **Sacar del índice los `.pyc` versionados** (ya ignorados por `.gitignore`):
   ```sh
   git rm --cached -r --ignore-unmatch research/avanti-s/refinement-v4/__pycache__ research/ugly-stik/model-v3/__pycache__ research/p51/p51-02/silhouette/__pycache__ research/p51/p51-02/silhouette/photo/__pycache__
   ```
3. **Confirmar** los 61 `.uid` sin versionar (punto 10 de la revisión #2 del ROADMAP) y la carpeta `docs/research/visual-quality-implementation/VQ-01b/references/` (CC BY-SA 2.0 con `sources.json`); después verificar desde un `git clone` limpio que `VQ-01b/REFERENCES.md` resuelve.
4. **Enlaces a `references/` → texto «solo local»** (A4: 9 en planes, 219 en 30 informes). Expresión que lo hace en un solo paso sobre los ficheros no en curso (excluir los del P-51):
   ```sh
   perl -0pi -e 's/!?\[([^\]]*)\]\(<?(?:\.\.\/)+references\/([^)>]+)>?\)/$1 (`references\/$2`, solo local)/g' docs/AVANTI-S-PLAN.md docs/UGLY-STIK-PLAN.md docs/UGLY-STIK-VISUAL-PLAN.md docs/UGLY-STIK-PLAN-v5.md $(grep -rl 'references/' docs/research --include='*.md' | grep -v 'aircraft-reference-index\|p51-')
   ```
5. Opcional, si LEARNINGS (ya 680 líneas) sigue molestando: un fichero por pista en `docs/learnings/` con LEARNINGS.md como índice; el guion de división con prueba por hash quedó preparado y puede repetirse.

## 6. Qué queda para la pista P-51 (única activa)

- Al confirmar: `docs/P51-VISUAL-PLAN.md`, `docs/research/p51-visual-review-v1.md`, `research/p51/p51-02/visual-review-2026-10-06/` y `…/photo/metrics-2026-10-06.json` (A6).
- B8: cabecera de `P51-PLAN.md` con P51-02c y revisión; datum «y = 0» (la línea de referencia del fuselaje es la correcta, con el eje del cono 0,006 m arriba) también en `assets/aircraft/p51d-mustang-120/README.md:5`; «7,8 px» → 7,7; columna de dependencias; `verify_p51.gd:1` «P5-02».
- B9: escribir `P51-V01…` en prosa y renombrar los «Hito M1/M2/M3» del plan visual.
- `docs/research/aircraft-reference-index.md`: líneas 13/15 (Extra ya vuela) y 30/38 (Avanti integrada como vista previa).
- Carpeta vacía `research/p51/p51-01/`.

## 7. Mensaje de commit para los cambios de esta revisión

```
Docs: documentation map, track registry, research index and status cleanup

docs/README.md (canonical document per question; registry of 15 tracks with
plan, step-ID prefix, state, gate, owned paths, evidence; namespaces; gates;
folder rules; conventions) and docs/research/README.md (entry points for 167
reports). Audit in docs/research/documentation-audit-2026-10-06.md.

ROADMAP: one line per track, flight repair and proposals listed, Gate F
decided (component buildup from the linear oracle, 2026-10-06), E0a partly
done, known limits after the repair, Spanish appendix folded in. DECISIONS:
repair and documentation rows, Open list. AGENTS: four aircraft, full track
ownership, git-status rule, conventions. Plans without an active owner get
their status lines and stale statements fixed (Extra, Avanti, Menu, Visual
quality, Landscape, Wind, Robustness, Rudder, Ugly Stik). Catalog comment
redefines FLYABLE honestly. .gitignore anchors /references/ and ignores
__pycache__. FIRST-LAUNCH anchor and V key.

Proof: link/anchor checker 0 problems on 20 documents; godot --check-only on
aircraft_catalog.gd; documentation only otherwise.
```
