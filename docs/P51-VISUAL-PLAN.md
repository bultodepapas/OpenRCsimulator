# P-51D 1/4 — plan visual detallado: formas, detalles y acabado

2026-10-06 · Revisión 2 (especificación técnica) · Continúa [P51-02/02b/02c del plan general](P51-PLAN.md) a partir de la [revisión visual 1](research/p51-visual-review-v1.md) (18 hallazgos ordenados) y la [revisión por siluetas](research/p51-silhouette-review-v1.md). Las dimensiones y posiciones están medidas y confirmadas; este plan corrige **formas y detalles** sin moverlas, paso a paso, con prueba en cada entrega.

[Método de siluetas](../research/p51/p51-02/silhouette/README.md) · [comparativas](../research/p51/p51-02/visual-review-2026-10-06/) · [plan visual del Ugly Stik](UGLY-STIK-VISUAL-PLAN.md) (precedente: apariencia JSON, A/B con cámaras iguales, coste medido) · [acabado del Extra](../assets/aircraft/extra-300s-60/README.md) (precedente: sombreador procedimental en UV de modelo).

## 1. Objetivo y alcance

**Resultado buscado.** Un P-51D reconocible a distancia de vuelo por su cola, su toma ventral y su cabina burbuja; convincente en Inicio y en la vista cercana: metal natural con reflejos y paneles, tren con amortiguador y puertas, hélice de palas anchas con cuffs. Esquema de colores a elegir por el propietario (hoy provisional: cono rojo, antirreflejo oliva, timón y puntas amarillas).

**Dentro del alcance.** Geometría visual (`assets/aircraft/p51d-mustang-120/`, `app/aircraft/p51d_model.gd`), verificador (`app/aircraft/verify_p51.gd`), inspector, siluetas, acabado (nuevo `appearance.json` + sombreador), documentación.

**Fuera del alcance.** Datos físicos (`app/data/aircraft/p51d_mustang_120.json`) salvo el eje de empuje de V07, coordinado con P51-06; flaps y retráctiles animados (dependen de ROADMAP E/G); cualquier cambio de envergadura, longitud, cuerdas, posiciones de ala, cabina, toma, cola, cono o tren (están medidas con comprobaciones reservadas dentro del 0,7 %).

## 2. Arquitectura sobre la que se trabaja

```
assets/aircraft/p51d-mustang-120/source.json      cotas a escala real + valores del kit (editable a mano: solo los grupos *estimated*)
   ▲ research/p51/p51-02/silhouette/apply_metrology.py   vuelca metrology.json (grupos *measured*; idempotente)
   ▲ research/p51/p51-02/silhouette/measure.py           siluetas rellenas de la tres vistas AN 01-60-3 → metrology.json
   │
build_geometry.py  ──▶ geometry.json (metros de modelo, 1/4)  ──▶ compile_geometry.py ──▶ app/aircraft/p51d_geometry.gd (DATA, generado)
                                                                                           │
                                   app/aircraft/p51d_model.gd  build() → {root "airplane", propeller, hinges{4}, gear{4}}
                                   app/aircraft/verify_p51.gd  126 checks (contrato, geometría, signos, determinismo)
                                   app/aircraft/inspect_p51.gd suites inspection/orbit (xvfb)
                                   research/p51/p51-02/silhouette/{prepare.py, render.gd, review.py}   dibujo (3 vistas ortográficas)
                                   research/p51/p51-02/silhouette/photo/{fit.py, review_photo.py}      foto del propietario (perspectiva)
```

Convenciones que no se tocan: ejes del modelo +X derecha, +Y arriba, −Z morro; z = 0 en el borde de ataque de raíz extrapolado a la línea central; y = 0 en la línea de referencia del fuselaje (el eje del cono está 0,006 m por encima, `spinner.axis_y`). Jerarquía de bisagras `wing → wing_frame_<lado> → aileron_frame_<lado> → aileron_<lado>_hinge`, `tail_frame → elevator_hinge`, `fin_frame → rudder_hinge`; `render/airplane.gd::apply_surfaces()` solo gira los `*_hinge`. Nombres de nodos `airplane`, `propeller`, `wheel_left/right/tail`, `tail_steering`. Cada grupo de `geometry.json` lleva `evidence.<grupo>.kind ∈ {manual, measured, borrowed, estimated, derived}`.

## 3. Definición de hecho (común a todos los pasos)

1. **Datos antes que código.** Toda forma nueva entra por `source.json` (o por `measure.py`/`apply_metrology.py` si se lee del dibujo), nunca como constante en el builder. Lo que la tres vistas no da se declara `estimated` citando la foto que lo apoya.
2. **Regenerar, no editar.** `build_geometry.py` y `compile_geometry.py` (ambos `--check` en verde); `p51d_geometry.gd` y el JSON físico nunca se editan a mano.
3. **Parse y contrato.** `godot --headless --check-only` del builder y del verificador; `verify_p51.gd` sin fallos ni líneas `ERROR:`; los checks nuevos del paso llevan al menos una **mutación** probada sobre una copia (qué se rompió a propósito y qué check lo detectó), documentada en la cabecera del verificador.
4. **Siluetas con cámara congelada.** `prepare.py` → `render.gd` → `review.py --baseline research/p51/p51-02/silhouette/renders-after` y `photo/fit.py` → `render.gd --fit=…` → `photo/review_photo.py`. Umbrales globales: perfil ≤ 7,7 px, planta ≤ 15,0 px, IoU foto ≥ 0,80 (no empeorar); cada paso añade su umbral local (tabla del §5).
5. **Capturas.** `inspect_p51.gd --suite=inspection` y la órbita; se revisan a ojo las vistas afectadas y se guardan 4-6 PNG en `research/p51/p51-02/review-<fecha>-<paso>/` con `manifest.json`.
6. **Coste.** El verificador imprime mallas y triángulos (`p51 preview: N meshes, T triangles`); el paso anota el delta en su informe. Presupuesto total ≤ 80.000 triángulos y ≤ 110 mallas (hoy 67 y 39.811). Las mallas de superficies móviles no se funden con las fijas.
7. **Suite.** `app/test.sh` completo en verde (incluye `verify_p51`, `test_p51_handling`, `test_aircraft_catalog`, traza `--aircraft=p51d-mustang-120`).
8. **Documentar.** Fila del paso en este plan con su prueba, entrada en LEARNINGS y, si procede, en la revisión visual; mensaje de commit con la prueba.

## 4. Línea base

| Magnitud | Valor | Fuente |
| --- | --- | --- |
| Mallas / triángulos | 67 / 39.811 | `verify_p51.gd` |
| Perfil (dibujo) | 7,7 px media, p90 16,1, IoU 0,871 | `silhouette/review-2026-10-06/metrics.json` |
| Planta (dibujo) | 15,0 px, p90 51,1, IoU 0,827 | ídem (tramos 5-6 raíz alar 15-19 px; tramo 8 cono/palas 37 px) |
| Foto oblicua | ajuste 8,6 px RMS; contorno 8,6 px, IoU 0,801 | `silhouette/photo/metrics-2026-10-06.json` |
| Trimado | 22 m/s, 56 % gas, 18,2 kg | `test_p51_handling.gd` |

## 5. Pasos

Gravedad de los hallazgos: **A** identidad a distancia · **B** vista cercana e Inicio · **C** primer plano. Esfuerzo: S ≤ ½ día, M ≈ 1 día, L ≈ 2 días de trabajo con pruebas.

### V01 · Cola: deriva, timón, estabilizador y cono (hallazgos 1, 4, 12 · A · esfuerzo L)

**Qué está mal.** `_fin_outline()` dibuja la deriva como un borde recto desde `fin_root_le_z` a `fin_top_le_z` más una dorsal cuártica; `_rudder_te()` cierra el timón con una recta redondeada solo 3 cm en el tope; el timón cuelga bajo el cono con una esquina viva (`rudder_te_bottom`); `_stab_ring()` hace un trapecio de puntas cuadradas (redondeo de 25 mm de espesor, no de planta); la sección de deriva y estabilizador es un perfil delgado que de perfil se lee como una línea.

**Datos.** Nuevas claves en `source.json → full_size.tail` y `geometry.json → tail`, todas `measured` desde la tres vistas:
- `fin_le_outline: [[y, z], …]` (8-12 puntos del borde de ataque, desde `dorsal_start_z` hasta la cima), `fin_top_outline: [[y, z], …]` (cima redondeada hasta el borde de salida del timón), `rudder_te_outline: [[y, z], …]` (borde de salida y cabeza), `rudder_bottom_outline: [[y, z], …]` (remate bajo el cono y luz de cola).
  *Extracción:* `measure.py` recorre las columnas del perfil con z > 4,6 m y toma el contorno superior **menos** la línea del lomo ya interpolada (`top_f` sin `fin_zone`); el borde de ataque es el primer píxel por columna, el borde de salida el último en la zona z > `rudder_hinge_z`. La charnela no se detecta en el dibujo: se conserva 6,64 m (línea discontinua leída a mano, `estimated`).
- `stab_planform: {le: [[x, z], …], te: [[x, z], …]}` con las puntas redondeadas y el ángulo de la compensación de los elevadores (`elevator_horn: {span_from: x, chord_fraction: f}`), extraídos de la planta (columnas con z > 5,0 m, como ya hace `measure.py` para el ajuste del estabilizador, pero guardando los puntos).
- `fin_section` y `stab_section`: espesores relativos (`fin_thickness_ratio` 0,09 y `stab_thickness_ratio` 0,10 ya existen a escala real; pasar a usarlos por cuerda local en vez del valor absoluto).
- `tail_cone_cap: {z, y, radius}` (`estimated`, foto 44-74880) y `tailwheel_well: {z0, z1, half_width}` (`estimated`).

**Builder.** Sustituir `_fin_outline()` por una lectura de `D.tail.fin_le_outline` con `monotone()`; `_rudder_te(y)` lee `rudder_te_outline`; nueva `_rudder_bottom(y)`; `_fin_ring()` pasa a usar la cuerda local real (BA → BS) y un espesor proporcional; la dorsal deja de ser una losa: entre `dorsal_start_z` y el arranque de la deriva las secciones se ensanchan desde `fin_thickness` hasta `2·profile(z,1)·0,35` y su base sigue `skin_y(z, x)` (loft de unión al lomo, misma técnica que `_scoop_ring()` por arriba). `_stab_ring()` toma `le`/`te` de `stab_planform` y redondea la **planta** (no solo el espesor) con `_round_factor()` sobre la cuerda; los elevadores se cortan en `elevator_horn` para que la punta avance sobre la charnela. Nuevo `_tail_cone_cap()` (esfera cortada bajo el timón) y pozo del patín como `_throat()` invertido. Nombres de nodo sin cambios (`fin`, `rudder`, `stab`, `elevator_left/right`).

**Verificación nueva.** (a) cima de la deriva = `fin_top_y` ± 3 mm y punto más alto del timón ≤ cima; (b) borde de ataque monótono en z con y creciente (sin bucles); (c) holgura timón/deriva y elevador/estabilizador ≥ 0,5 mm a los recorridos del manual (33°/15°) y a 45°, con el mismo método que `extra_clearance.gd` (portar lo mínimo a un `p51_clearance.gd` o parametrizar el del Extra); (d) `rudder` sigue girando sobre +Y y moviendo el BS a la derecha; (e) planta del estabilizador: envergadura ± 5 mm y punta redondeada (ningún vértice en la esquina BA/punta a menos de 10 mm del rectángulo envolvente). Mutaciones: invertir el signo de la compensación; quitar el redondeo.

**Aceptación.** Perfil ≤ 7,0 px con el tramo 6 (cola) < 12 px; planta de la cola (tramos 1-2) ≤ 8 px; foto: cima de deriva dentro de 8 px. Coste +4.000 triángulos como máximo.

**Riesgos.** El pozo del patín y la tapa pueden tocar `nothing below the wheels`; el verificador ya excluye ruedas, no tapas: ampliar la lista de excepciones solo con nombres explícitos. El redondeo de planta cambia la caja del `stab` (`stab span` ± 5 mm): calcular la envergadura sobre los puntos BA/BS, no sobre la AABB.

### V02 · Raíz alar: extensión del borde de ataque, carenado de salida y puntas (hallazgos 2, 9 · A · M)

**Qué está mal.** El ala entra recta en el fuselaje. La tres vistas mide una extensión del BA de 0,21 m en el costado que baja a 0,05 m a 0,85 m del eje (escala real; `metrology.json → wing.root_extension`), y las fotos muestran el carenado de salida subiendo por el costado. Las puntas son esquinas vivas con un degradado de espesor (`TIP_ROUND_M`).

**Datos.** `wing.root_extension: [[x, dz], …]` (ya medido; `apply_metrology.py` lo escribe en `source.json` y `build_geometry.py` lo escala), `wing.tip_round_plan_m` (0,10 `estimated`), `wing.fillet: {te_rise_m, length_aft_m, half_width_factor}` (`estimated`, foto aire-aire).

**Builder.** `_le_z(span)` suma `monotone(root_extension, |x|)` para |x| < 0,85·k; la cuerda local crece en la misma cantidad (el BS no cambia), así que `_chord()` y `_hinge_point()` siguen coherentes y los alerones no se mueven. La extensión se construye como paneles `full` adicionales entre la raíz y `flap_inner` con el mismo `_foil_ring()`; el carenado de salida es un loft de 6-8 anillos que parte de la sección del ala en `x = profile(z,1)` y se eleva hasta `skin_y()` con `te_rise_m`, cerrado contra el fuselaje (técnica de `_scoop_ring()`: borde superior en la piel). Puntas: `_wing_ring()` recorta la cuerda con una elipse en planta en los últimos `tip_round_plan_m` (además del degradado de espesor).

**Verificación nueva.** Envergadura inalterada (± 1 cm); el BA en la raíz avanza `root_extension[0]` ± 3 mm; alerón y flap no se mueven (comparar `aileron_frame_*` con la revisión anterior por valores guardados en el verificador); ningún vértice del carenado fuera de la piel más de 3 mm.

**Aceptación.** Planta ≤ 10 px e IoU ≥ 0,87 (tramos 5-6 ≤ 10 px); perfil sin empeorar. Coste +3.000.

### V03 · Toma ventral y toma de carburador (hallazgos 3, 13 · A · M)

**Qué está mal.** `_scoop_ring()` es una superelipse n = 2,6 pegada al fuselaje: barriga lisa. La real es un conducto de lados casi verticales, boca ovalada aplanada separada del fuselaje por el canal de capa límite (2-3 cm a 1/4), cuerpo recto y compuerta de salida rectangular. La toma de carburador es un resalte plano casi invisible.

**Datos.** `scoop_stations` pasa a `[z, half_width, bottom, side_exponent]` con n = 4-6 en el cuerpo (`estimated`, fotos 44-74880 y del propietario); `scoop_gutter: {gap_m, length_m}`; `scoop_exit: {z, height, width, door_angle_deg}`; `carb_intake` gana `lip_height`, `exponent` y `throat_depth` (dentro de la silueta medida: su altura ya está en `fuselage_stations`).

**Builder.** `_scoop_ring()` con exponente por estación; los dos primeros anillos bajan del borde de la piel `gap_m` para abrir el canal (segundo loft fino para la pared superior del canal, oscura); `_throat()` más profunda (0,25 m) y `scoop_exit` como caja abierta con la compuerta a `door_angle_deg`. `_carb_intake()` con boca rectangular redondeada y labio.

**Verificación nueva.** `scoop depth` ya existe; añadir anchura máxima del conducto = `half_width` ± 3 mm y que el canal exista (hueco entre piel y conducto en la boca ≥ `gap_m` − 1 mm).

**Aceptación.** Foto: labio y fondo de la toma dentro de 8 px; perfil sin empeorar (la silueta de perfil ya es la medida: el cambio es de sección). Coste +2.500.

### V04 · Cabina y piloto (hallazgos 5, 15 · B · M)

**Qué está mal.** `_canopy()` es un loft único con una banda oscura en `frame_z`; no hay parabrisas plano, raíles ni respaldo; el piloto es cabeza y casco sobredimensionados.

**Datos.** `canopy.windscreen: {base_z, top_z, panels: 3, frame_width_m}`, `canopy.rail: {height_m, width_m}`, `cockpit: {headrest, armour_plate, gunsight}` (`estimated`, foto del propietario y fotos de archivo); `pilot` con medidas a 1/4 (cabeza 0,06 m, hombros 0,11 m) y `seat`.

**Builder.** Parabrisas como prisma de tres paneles planos (`_plate()` reutilizable del Extra o un loft de dos anillos) con marcos oscuros de `frame_width_m`; la capota corredera desde `frame_z` con el mismo loft actual; raíl como `_strip()` sobre el umbral; `armour_plate` ya existe (ajustar al nuevo `frame_z`); `gunsight` como caja pequeña tras el parabrisas; piloto reescalado. La transparencia sigue en `_glass()`.

**Verificación nueva.** `canopy crown` sin cambios; `pilot inside the canopy` sin cambios; nuevo: el parabrisas no sobresale de la silueta medida (`canopy.top`) más de 3 mm; marcos opacos.

**Aceptación.** Foto: cima de cabina ≤ 10 px; captura `inspection_cockpit_left` revisada a ojo. Coste +1.500.

### V05 · Escapes y capó (hallazgos 6, 17 · B · S)

**Qué está mal.** `_exhausts()` hace seis cilindros de 0,0875 m que sobresalen como un peine (muy visible en planta); el real lleva tubos cortos y altos en el costado, a veces carenados.

**Datos.** `exhausts: {z0, z1, y_fraction, count: 6, length_m, radius_m, shroud: bool}` en `source.json` (`estimated`, fotos; `z0/z1` ya medidos: −1,52 y −0,54 m a escala real). Elimina las constantes del builder (`0.11·f`, `0.45·f`, `6.0·f`).

**Builder.** Cilindros de `length_m` (≈ 1/3 del actual), inclinados 15° hacia atrás, en `y_fraction·profile(z,2)`; opción `shroud` como medio loft que los cubre.

**Verificación nueva.** Ningún vértice de escape a más de `length_m` + 2 mm de la piel.

**Aceptación.** Planta: el tramo 8 (morro) baja a < 25 px (lo que queda es el cono y las palas); perfil sin empeorar. Coste neutro.

### V06 · Tren principal y patín (hallazgos 7, 12 · B · M)

**Qué está mal.** `_gear()` hace patas verticales (`x_strut` fijo, `top` sobre la piel), puertas-placa rectangulares, cubos planos; el real tiene amortiguador inclinado con tijera, puerta interior solidaria con forma, tapas de pozo en el fuselaje, llantas con radios; el patín carece de puertas.

**Datos.** `gear.rake_deg` (inclinación hacia delante, `estimated` 8° por la foto del propietario), `gear.scissor`, `gear.inner_door: outline [[u, v], …]`, `gear.well_doors` (en el fuselaje/ala), `gear.hub_spokes: 6`, `gear.tailwheel_doors`. `main_axle` no cambia.

**Builder.** Pata desde el pozo del ala (a `rake_deg`) hasta el eje medido; tijera con dos `_strut()` cortos; puerta interior como `_plate()` con el contorno; tapas del pozo como `_plate()` sobre la piel del ala; llanta con radios (anillo + 6 radios, 10 segmentos). Mantener `wheel_left/right/tail` y `tail_steering`.

**Verificación nueva.** `main wheels touch the lowest point`, `nothing below the wheels` y `track` siguen; nuevo: la pata pasa por el eje (distancia eje-línea de la pata < 2 mm) y la puerta interior no cruza la pata.

**Aceptación.** Foto: contorno del tren ≤ 8 px en los tramos 1-2 y 7. Coste +2.000.

### V07 · Hélice y eje de empuje (hallazgos 8, 18 · B · S) — coordinado con P51-06

**Qué está mal.** `propeller.blade.chord_fraction_of_radius` describe una pala estrecha que desde arriba parece un palo; la Hamilton Standard es de pala ancha tipo remo con cuff en la raíz y punta redonda. El `thrust_frame` es axial aunque el dibujo acota 1°45' de empuje hacia abajo.

**Datos.** Nueva tabla `chord_fraction_of_radius` (cuff en 0,2-0,35 r, máximo 0,22 r a 0,55 r, punta redonda) y `thickness_fraction_of_chord`; `propeller.down_thrust_deg: 1.75` (`manual`, tres vistas).

**Builder.** `_blade_ring()` sin cambios de algoritmo (lee las tablas); `_propeller()` gira `thrust_frame.rotation.x` según `down_thrust_deg`. **Física:** el dato `propulsion.propeller.thrust_line_offset` y un futuro ángulo de empuje se tratan en P51-06 (hoy `propulsion.gd` es axial); hasta entonces el giro es solo visual y queda documentado como diferencia conocida (la hélice visual y la física difieren 1,75°).

**Verificación nueva.** `propeller diameter` y `blade meshes` siguen; nuevo: la cuerda máxima de la pala está entre 0,18 y 0,25 r; el eje del `propeller` forma `down_thrust_deg` con −Z.

**Aceptación.** Órbita el +40 revisada a ojo; siluetas sin cambio (la hélice no se compara). Coste neutro.

### V08 · Materiales y líneas de panel (hallazgo 10 · B · L)

**Qué está mal.** `_aluminium()` (roughness 0,35, metallic 0,8) lee como plástico gris porque la escena del inspector y el campo no aportan reflejos; no hay paneles ni remaches.

**Diseño.** Un `appearance.json` (como el del Extra, compilado a `p51d_appearance.gd`) con: materiales (aluminio: metallic 0,9, roughness 0,25-0,35 con variación por panel; acero del tren; goma; acrílico), rejilla de líneas de panel en **UV de modelo** (el builder ya puede escribir UV = (z, y) para el fuselaje y (|x|, fracción de cuerda) para el ala, como `extra_300s_model.gd`), y un sombreador `p51d_finish.gd` que dibuja líneas de panel y remaches procedimentales por parte (fuselaje, ala, cola) sin texturas. Reflejos: el inspector gana un `Sky` procedimental para el entorno (solo en el inspector; en la app el cielo ya existe) y se mide el A/B con la misma cámara.

**Verificación nueva.** El sombreador no lee `TIME` (regla de `test.sh`); los UV existen en todas las mallas de piel; `natural-metal fuselage` se mantiene (metallic ≥ 0,7).

**Aceptación.** A/B de `inspection_oblique_front_left` con y sin acabado, misma cámara; coste de sombreador medido con `--frametimes` en la app (headless: solo plomería; GPU real pendiente como en el Ugly Stik). Coste geométrico neutro.

### V09 · Esquema de colores (hallazgo 11 · B · S, bloqueado por la decisión del propietario)

`appearance.json → scheme` con colores, bandas (cono, morro, puntas, cola), escarapelas **genéricas** y rótulos inventados; sin marcas reales. Criterio EX-10a: extradós e intradós legibles desde tierra (capturas superior e inferior). Candidato si el propietario lo desea: metal natural con cola y puntas rojas y cono rojo (lectura de «Val-Halla» sin copiar sus marcas).

### V10 · Detalles (hallazgos 16, 17 · C · M)

Tres bocas de cañón por ala en el BA (`wing.gun_ports: [x…]`), pitot bajo el ala izquierda, luces de formación y de navegación, mástil de antena tras la cabina (`fuselage.antenna_mast`), tapas de combustible, trim tabs del timón y elevadores (`estimated`, fotos). Cada detalle ≤ 300 triángulos; verificación: posiciones relativas (cañones en el BA ± 5 mm, pitot bajo el ala). Coste +3.000.

### V11 · Cierre de la revisión visual 2

Repetir dibujo (3 vistas), foto del propietario, órbita completa y capturas de detalle; ajustar cámaras a las dos fotos de la USAF en tierra si se identifican ≥ 6 hitos (cono, puntas, cima de deriva, ruedas) para añadir dos vistas métricas; informe `p51-visual-review-v2.md` con tabla antes/después por paso, coste acumulado y hallazgos abiertos.

## 6. Orden, dependencias e hitos

```
V01 cola ──┐
V02 raíz ──┼─▶ Hito M1 «identidad a distancia» (siluetas: perfil ≤ 7,0, planta ≤ 10, IoU planta ≥ 0,87)
V03 toma ──┘
V04 cabina ─┐
V08 material┼─▶ Hito M2 «Inicio y vista cercana» (A/B de capturas, foto IoU ≥ 0,85)
V09 esquema ┘  (V09 espera la decisión del propietario; V08 no depende de él)
V05 escapes, V06 tren, V07 hélice, V10 detalles ─▶ Hito M3 «primer plano» (coste ≤ 80.000 tri)
V11 cierre
```

V01 debe ir antes que V02 solo por disciplina de medida (ambos amplían `measure.py`); V03 es independiente. V07 depende de P51-06 para que el eje visual y el físico coincidan; mientras tanto el giro es visual y documentado. V08 debe preceder a V09 (el esquema se dibuja con el sombreador).

## 7. Riesgos y mitigaciones

| Riesgo | Mitigación |
| --- | --- |
| Corregir formas moviendo dimensiones medidas | Umbrales de siluetas con cámara congelada en cada paso; `prepare.py` solo se vuelve a ejecutar si cambian las anclas (cono, timón, puntas) y entonces se anota |
| Trabajo paralelo de otras sesiones en `render/airplane.gd`, catálogo y `test.sh` | Este plan solo toca archivos del P-51 listados en AGENTS.md; nuevos verificadores entran como ficheros nuevos y una línea en `test.sh` |
| Scripts que no parsean cuelgan la suite headless | `--check-only` antes de guardar en `app/`; borradores en el scratchpad |
| Coste geométrico/sombreador sin GPU real en la VM | Presupuesto por paso; A/B de `--frametimes` como plomería; prueba en la 3090 del propietario como aceptación humana (igual que el Ugly Stik v4) |
| Fotos de terceros | Solo la foto del propietario y las de la USAF (dominio público) en el repo; composiciones con la del propietario bajo `references/` |
| Verificador frágil ante redondeos (AABB) | Medir sobre puntos del contorno, no sobre cajas; tolerancias explícitas |

## 8. Reproducción de un paso (plantilla)

```sh
python3 research/p51/p51-02/silhouette/measure.py --output /tmp/p51-sil            # si el paso lee algo nuevo del dibujo
python3 research/p51/p51-02/silhouette/apply_metrology.py
python3 assets/aircraft/p51d-mustang-120/build_geometry.py && python3 assets/aircraft/p51d-mustang-120/compile_geometry.py
G=$(app/get-godot.sh); $G --headless --path app --check-only --script res://aircraft/p51d_model.gd
$G --headless --path app --script res://aircraft/verify_p51.gd
python3 research/p51/p51-02/silhouette/prepare.py
xvfb-run -a -s "-screen 0 1280x720x24" $G --path app --rendering-driver opengl3 --audio-driver Dummy \
  --script res://../research/p51/p51-02/silhouette/render.gd -- --output-dir=/tmp/p51-renders
python3 research/p51/p51-02/silhouette/review.py --candidate /tmp/p51-renders --baseline research/p51/p51-02/silhouette/renders-after --output /tmp/p51-review --label "Vxx"
python3 research/p51/p51-02/silhouette/photo/fit.py
xvfb-run -a -s "-screen 0 1600x1000x24" $G --path app --rendering-driver opengl3 --audio-driver Dummy \
  --script res://../research/p51/p51-02/silhouette/render.gd -- --fit=res://../research/p51/p51-02/silhouette/photo/camera-fit.json --output-dir=/tmp/p51-photo
python3 research/p51/p51-02/silhouette/photo/review_photo.py --candidate /tmp/p51-photo --baseline research/p51/p51-02/silhouette/photo/renders-2026-10-06 --output /tmp/p51-photo-review
xvfb-run -a -s "-screen 0 1280x720x24" $G --path app --rendering-driver opengl3 --audio-driver Dummy --script res://aircraft/inspect_p51.gd -- --output-dir=/tmp/p51-inspect --suite=inspection
app/test.sh
```

## 9. Estado

| Paso | Estado | Prueba |
| --- | --- | --- |
| V01 cola | **Hecho 2026-10-06** | Contornos medidos (`tail.upper_outline` 68 puntos, `lower_outline` 27, `stab_planform` 37) → deriva con borde curvo, cima redondeada y dorsal fundida en el lomo; timón con cabeza, borde de salida inclinado y base biselada hasta el cono; cono acabado 2 cm antes de la charnela; estabilizador por planta medida con puntas redondeadas (0,06 m de modelo, estimado) y compensación de elevadores (cuerno 0,42 c desde 0,86 de semienvergadura, estimado). Siluetas con cámara congelada: perfil 7,7 → **7,2 px** (IoU 0,871), planta 15,0 → 15,2 px (ruido; el tramo de cola sube de 9,7 a 11,5 px porque la planta medida del estabilizador se recorta en la raíz), foto IoU 0,801 → 0,803. `verify_p51.gd` 131 checks (nuevos: borde de ataque monótono, punta redondeada, cuerno delante de la charnela, cono delante de la charnela); `verify_p51_clearance.gd` 12 checks (holgura mínima 2,1 mm a los recorridos volados y a 45°, 33 s). Coste 39.811 → 45.407 triángulos (+5,6 k, 1,6 k por encima del presupuesto del paso: anillos del estabilizador a ambos lados). [Comparación](../research/p51/p51-02/silhouette/review-2026-10-06-v01/index.html) · [capturas](../research/p51/p51-02/review-2026-10-06-v01/). Pendiente del paso: pozo del patín y puertas (tramo 6 del perfil sigue en 19,9 px por el patín extendido del dibujo). |
| V02-V11 | Planificados 2026-10-06 | — |

Las filas se completan por paso con métricas (siluetas antes → después, coste, checks) y enlace al directorio de capturas.
