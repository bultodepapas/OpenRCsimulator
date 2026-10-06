# Extra 300S .60: revisión visual automática de la vista previa (EX-02)

2026-10-06 · [Informe EX-01/EX-02](extra-300-model-v1.md) · [Plan](../EXTRA-300-PLAN.md) · Evidencia: [métricas y hojas de contacto](../../research/extra-300/ex02/review-2026-10-06/) · Herramientas: [inspector](../../app/aircraft/inspect_extra.gd), [capture.sh](../../research/extra-300/ex02/capture.sh), [review.py](../../research/extra-300/ex02/review.py)

**Resumen.** La forma coincide con el plano: las superposiciones del escaneo original encajan a nivel de línea, y la cadena datos → malla → render difiere menos de 1,5 mm salvo en la cabina, que queda +2,9 mm alta por un fallo propio. Lo importante para un simulador RC está en otra parte: **desde tierra no se distingue el extradós del intradós** (luminancia 127 frente a 139). El tren es la pieza menos fiel, y el fuselaje muestra facetado.

## 1. Cómo se genera

`research/extra-300/ex02/capture.sh` (46 s en la VM, sin GPU) renderiza cinco suites con el inspector propio del Extra:

| Suite | Imágenes | Qué mira |
| --- | ---: | --- |
| inspection | 8 | Ortográficas de frente, lateral, planta y vista inferior; oblicuas en reposo y con deflexión total |
| orbit | 36 | 12 azimuts × 3 elevaciones (−25°, +10°, +40°) a 2,7 m |
| detail | 20 | Carenado, cono, cabina, encastre del ala, alerón (ambos sentidos), punta, cola, rueda de cola, tren |
| distance | 12 | Vista de piloto (FOV 50°, 1280×720) a 20, 50 y 100 m: pasada lateral, alabeo ±60° y morro al piloto |
| scale | 3 + 3 | Ortográficas a 1280×720 y a 3840×2160 (1137 px/m) para medir y superponer el plano |

Antes de cada vista se restablecen todos los mandos, la actitud y la hélice, y el manifiesto registra cámara, luz, revisión y hashes. **Dos ejecuciones completas dan las 82 imágenes idénticas byte a byte.** Las vistas deflectadas usan ahora los recorridos altos del manual (p.43) convertidos con `asin(d/r)` en la cuerda más ancha de cada superficie: **alerón 17,6°, elevador 23,9°, timón 30,0°**. Antes heredaban los del Stik. Son valores visuales hasta EX-05.

`review.py` mide sobre las imágenes, sin intervención manual:

- recorte en el borde: ninguna vista que no sea de detalle sale recortada;
- huella del avión a cada distancia;
- contraste de orientación;
- fidelidad entre el render y `geometry.json`;
- superposición del plano y hojas de contacto.

Las superposiciones contienen tinta del plano escaneado (material de terceros). Se generan en local, bajo `app/captures/` o `references/`, y **no se versionan**; su lectura se resume aquí.

## 2. Fidelidad geométrica

**Render frente a datos** (vistas a escala, 0,88 mm/px):

- perfil lateral: 13 estaciones, superior e inferior;
- semianchos en planta: 8 estaciones;
- bordes de ataque y de salida del ala: 7 envergaduras por lado.

Todo queda por debajo de **1,5 mm**, excepto el techo de la cabina: **+1,9 a +2,9 mm** en sus 6 estaciones (tolerancia 2,5 mm). La causa está en el constructor (`_canopy`), que suma 2 mm a la altura para evitar que la cúpula atraviese la piel. Es un defecto propio y pequeño, y la comprobación lo aísla.

**Plano frente a render** (superposición a escala, leída en recortes ampliados):

- Lateral: cono, perfil del carenado, línea de cabina, deriva con el compensador del timón, borde de salida del timón y rueda de cola caen sobre las líneas del plano.
- Ala en planta: BA, punta, BS, línea de bisagra del alerón y su extremo en AR4 coinciden en toda la envergadura.
- Estabilizador: BA, punta, bisagra, BS del elevador y el corte en V junto al timón coinciden con el dibujo a tamaño real.
- Fuselaje en planta: el contorno del carenado y el cono de cola coinciden con la vista inferior del plano.
- **Tren:** la carena del plano es una gota (gruesa delante, afilada detrás) y la nuestra un elipsoide simétrico. La pata del plano es una pletina de aluminio ancha y la nuestra un cilindro de 9 mm.

## 3. Hallazgos y propuesta

| # | Gravedad | Hallazgo | Evidencia | Propuesta |
| --- | --- | --- | --- | --- |
| H1 | **Alta** (lectura en vuelo) | Extradós e intradós usan el mismo blanco. Con alabeo de ±60°, visto desde tierra, el ala da una luminancia media de **127 (extradós) frente a 139 (intradós)** a 20 m, y diferencias de −8 a −11 a 50 y 100 m: la cara de arriba es incluso algo más oscura | `orientation_contrast` en `review.json`; hoja `sheet_distance_zoom4x.png` | EX-10, adelantándola: intradós con las franjas azul/blanco de la foto 005 y paneles con estrellas arriba. Repetir esta métrica como criterio de aceptación |
| H2 | Media | Facetado longitudinal en el carenado y el fuselaje: la interpolación entre estaciones es lineal y las esquinas tienen 6 segmentos. Hay pliegues visibles en la barbilla del carenado y en el reflejo especular | `detail_cowl_chin_below`, `detail_canopy_left` | Interpolación suave (Catmull-Rom) entre estaciones al construir y más segmentos de esquina. Las estaciones medidas no cambian; `review.py` vigila que el perfil siga dentro de 2,5 mm |
| H3 | Media | Tren menos fiel que el resto: carena simétrica, pata cilíndrica, vía 0,32 m estimada | Superposición lateral (zona del tren); `detail_main_gear_front/side` | Carena en gota trazada del perfil del plano; pata de pletina. La vía necesita una fuente (vista frontal en las fotos .60/.40 o medida del propietario) |
| H4 | Media (EX-04) | Timón y elevador son placas de canto recto: al deflectar se abre una ranura visible. La holgura entre timón y elevador a 30° no está medida (a la vista no se cruzan) | `detail_tail_left_rear_full`, `detail_elevator_notch_top_full` | EX-04: bisel o canto redondeado en la bisagra; contención medida en extremos y combinaciones |
| H5 | Baja | Cabina +2 a +2,9 mm alta (margen añadido en el constructor) | `render_vs_geometry` en `review.json` | Aplicar el margen solo a la base de la cúpula |
| H6 | Baja | El frente de la cabina sale anguloso (13 puntos por anillo, esquina marcada en el parabrisas) | `detail_canopy_left` | Más puntos por anillo y transición redondeada en el arranque |
| H7 | Baja (contenido) | Falta detalle visible del plano y las fotos: tomas de aire del carenado, salida del escape, piloto, horns y varillas. La hélice son dos cajas de cuerda constante con punta cuadrada | `detail_cowl_spinner_front_left`, `detail_spinner_prop_side` | Priorizar lo que ayuda a leer el avión; el plan ya pide no microdetallar el motor antes de volar |
| H8 | Información | Huella en la vista de piloto: envergadura de **50 px a 20 m, 22 px a 50 m y 10–11 px a 100 m**; ninguna vista sale recortada | `distance_footprint` | Similar al Stik (≈12–15 px a 100 m); el zoom automático de D7 aplica igual |
| H9 | Información | La órbita de 36 vistas no muestra huecos, piezas sueltas ni caras invertidas visibles. El compensador del timón sobresale por encima de la deriva al deflectar, como en el avión real | `sheet_orbit_*` | — |

Orden propuesto: un paso pequeño **EX-02b** con H5, H6 y H2 (calidad de la malla, comprobada con `review.py`), después H3 (tren desde el plano). **H1 es el que más afecta al juego**, y conviene adelantar ahí la parte de EX-10 dedicada al intradós. H4 entra en EX-04.

## 4. Límites

- Luz de estudio fija, con un sol y un ambiente, y cielo plano: no es el escenario de la app. Los tonos dependen de esta luz; el contraste de H1 debe repetirse en la escena real cuando el Extra sea seleccionable (EX-03).
- llvmpipe sin GPU: sirve para la geometría y la repetibilidad, no para medir rendimiento.
- Las vistas de distancia son imágenes preparadas: miden píxeles y tono, **no** la capacidad de un piloto para leer la orientación (eso es la prueba humana de EX-10).
- La fidelidad frente al plano descansa en la escala de EX-01. La superposición comprueba la cadena entera, pero se lee visualmente, no se puntúa.

## 5. Revisión 2 (2026-10-06): EX-02b y EX-10a aplicados

Evidencia: [antes](../../research/extra-300/ex02/review-2026-10-06/) · [después](../../research/extra-300/ex02/review-2026-10-06-ex02b/) (revisión visual `gp-extra-300s-60-ex02b-red-stars`). Mismas cámaras, misma luz y mismos recorridos.

| Hallazgo | Cambio | Prueba |
| --- | --- | --- |
| H1 orientación | Decoración procedural propia (`extra_300s_finish.gd`, parámetros en `appearance.json`): extradós rojo con banda blanca, filetes y tres estrellas; intradós con franjas azules y blancas, borde de ataque rojo y alerones rojos; estabilizador con banda y estrella arriba y franjas rojas y blancas abajo; franja lateral recta en el fuselaje y panel del carenado con tres estrellas; franja en la deriva; cono rojo | Proporción de azul vista desde tierra, extradós/intradós: **0 % / 25,6 % a 20 m, 0 % / 22,9 % a 50 m, 0 % / 31,2 % a 100 m** (antes 0/0 en las tres). Criterio `orientation_contrast.ok` (diferencia ≥ 0,10 a cada distancia) en `review.py`. Mutación «decoración invertida»: las diferencias pasan a −0,18/−0,26/−0,20 y el criterio falla |
| H2 facetado | Interpolación cúbica monótona (Fritsch–Carlson) entre estaciones, anillos cada 15 mm y 10 segmentos por esquina | Pasa exactamente por cada estación medida y no sobrepasa los valores vecinos. Render frente a datos ≤ 1,16 mm; puntos originales del plano ≤ 0,99 mm |
| H5 cabina alta | La cúpula se asienta 2 mm bajo la piel y su cresta queda sobre la línea medida | Techo de cabina dentro de 1,2 mm (antes +2,9 mm) |
| H6 frente anguloso; «orejas» traseras | 25 puntos por anillo y 41 anillos; anchura limitada al ancho real de la piel sobre el lomo redondeado | Comparación antes/después en `detail_canopy_*` |
| H3 tren | Carena en gota trazada del perfil del plano (25 secciones con espaciado coseno: morro romo, cola truncada) y pata de pletina cónica (1,31 → 0,92 in) desde los cantos del plano; los nuevos puntos están en `picks.json` y salen de `measure.py` | La superposición del plano coincide con carena y pletina; `compile_geometry.py --check` coteja 197 valores con la metrología |

Decisión: la decoración es un **shader procedural** y no un atlas como el del Stik. El constructor escribe coordenadas del modelo en las UV (envergadura, fracción de cuerda, altura y z en metros), así que las bandas y las estrellas caen en su sitio en cada panel y en los mandos móviles, sin costuras ni texturas. Una banda definida como fracción de la altura local se escalonaba en el reborde de la cabina; definida en altura absoluta sale recta. `verify_extra.gd` (104 comprobaciones) verifica material, UV, rojo compartido y ausencia de `TIME`.

**Sigue pendiente:** H4 (bisel de bisagras y holguras, EX-04), H7 (tomas de aire, escape, piloto, horns, hélice real) y la prueba humana de orientación de EX-10. La vía del tren, la anchura de las carenas y el grosor de la pletina siguen estimados. Los tonos son una lectura a ojo de fotos con luz desconocida.
