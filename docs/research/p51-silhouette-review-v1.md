# P-51D · revisión 1 por siluetas sobre la tres vistas oficial

2026-10-06 · Geometría `p51d-mustang-120-v1` tras aplicar la metrología; comparación con la primera maqueta (cotas a ojo). [Visor antes/después](../../research/p51/p51-02/silhouette/review-2026-10-06/index.html) · [métricas](../../research/p51/p51-02/silhouette/review-2026-10-06/metrics.json) · [metrología](../../research/p51/p51-02/silhouette/metrology.json) · [método y reproducción](../../research/p51/p51-02/silhouette/README.md) · [renders del inspector v6](../../research/p51/p51-02/review-2026-10-06-measured/).

## Método

Es la técnica del Avanti con una referencia mejor: en vez de fotos con perspectiva, la **tres vistas acotada de North American (AN 01-60-3 p. 30, dibujo 106-00001, dominio público)**, ortográfica y con cotas impresas. Dos anclas por vista fijan una cámara ortográfica de escala uniforme (perfil: punta del cono y borde de salida del timón sobre la línea de referencia del fuselaje; planta y frontal: puntas de ala). El modelo se renderiza con fondo transparente y material plano cian al tamaño del recorte, sin hélice, y se superpone sin tocar el dibujo. Antes de comparar, cada vista del dibujo se convierte en silueta rellena para extraer su contorno y, de paso, medir estaciones.

Calibración por eje con cotas impresas: 3,11 px/in en horizontal y 3,00 en vertical en el perfil (la reproducción de 1945 es un 3,4 % anisótropa ahí), 3,14/3,17 en la planta. Comprobaciones reservadas (cotas impresas no usadas para calibrar): envergadura del estabilizador **+0,5 %**, área alar trapezoidal **+0,6 %** (236,5 frente a 235 ft²), MAC **+0,7 %** (80,1 frente a 79,6 in).

## Resultado

Distancia media (px, ≈ 490 px por metro de modelo) de cada píxel del contorno del dibujo al borde más cercano del render, e IoU de las siluetas rellenas; palas de la hélice excluidas en perfil y planta.

| Vista | Antes → después (media) | p90 después | IoU antes → después | ≈ mm sobre el modelo |
| --- | --- | --- | --- | --- |
| Perfil | 22,4 → **7,8 px** | 16,1 px | 0,681 → **0,871** | 16 mm |
| Planta | 31,3 → **15,0 px** (30,7 → **10,7 px** con la métrica corregida de V02, que ignora los bordes de las cajas de exclusión) | 51,1 px (12,0) | 0,603 → **0,827** (0,681 → **0,907**) | 30 mm (22) |
| Frontal (mitad izquierda, cualitativa) | 21,6 → 13,5 px | 36,1 px | 0,446 → 0,464 | 27 mm |

Por tramos (ocho, de morro a cola): el perfil queda en 2,5-7 px salvo el tramo del patín de cola extendido del dibujo (20 px: el modelo lleva el patín en otra posición y sin puertas). La planta queda en 2-10 px salvo la raíz alar (15-19 px: la extensión del borde de ataque y el carenado de salida del D no están modelados) y el morro (37 px: el cono y el resto de las palas). La frontal no separa las cuatro palas dibujadas del cuerpo: su IoU no es comparable; sirve para ver diedro, vía, altura del tren y de la punta alar, que ahora coinciden.

## Cambios de geometría (metros a escala real)

| Zona | Primera maqueta (a ojo) | Medido en la tres vistas |
| --- | --- | --- |
| Punta del cono respecto al borde de ataque de raíz | −2,35 | **−2,676** (el ala estaba 0,33 m demasiado adelantada) |
| Plano de cuerda en la raíz bajo la línea de referencia | −0,30 | **−0,673** (cota impresa 26½ in: el ala estaba 0,37 m demasiado alta) |
| Cuerdas raíz/punta, flecha del BA en punta | 2,64 / 1,27 / 0,34 | 2,667 / 1,227 / 0,37 (25 % de cuerda sin flecha, 0,1°) |
| Cabina | z 1,95-3,65, cima 1,02 en 2,75 | **z 0,70-2,90, cima 0,947 en 1,13** (casi 1 m más adelante) |
| Toma ventral | labio 2,05, fondo −1,12, salida 4,35 | **labio 1,19, fondo −1,17, salida 4,08** |
| Estabilizador | BA raíz 5,85, cuerda 1,40, semienvergadura 1,995 | **5,14, 1,30, 2,018** (0,7 m más adelante) |
| Deriva | cima 1,95, BA 5,90, dorsal 5,30 | **cima 1,767 (cota impresa), BA 5,70, dorsal 4,60**, charnela 6,64 |
| Tren principal | eje [0,10, −1,65] | [0,10, **−1,70**]; rueda ~82 in bajo la línea de referencia en ambas vistas |
| Patín | [6,45, −0,50] | **[5,13, −0,64]** |
| Fuselaje | 19 estaciones a ojo | 37 estaciones medidas: semianchura máx. 0,458, lomo 0,651, vientre −0,812; cono de cola interpolado bajo la deriva |
| Cono | radio 0,345, eje en la línea de referencia | **radio 0,389**, eje +0,023 sobre ella |

Los grupos medidos pasan de *estimated* a *measured* en `source.json`; siguen estimadas las anchuras de la toma y de la cabina, los exponentes de sección, las fracciones de alerón y flap, la hélice y la extensión del borde de ataque de raíz (no modelada).

## Efecto en la física

Al regenerar los datos (`research/p51/p51-05/derive_physics.py`) con la nueva geometría: el morro largo adelanta motor, baterías y depósito, de modo que el inventario equilibra en el 27 % MAC con **0,21 kg** de lastre virtual (antes 1,66 kg), coherente con lo que reportan los constructores de P-51 de 1/4 con DA-120; masa de vuelo 18,2 kg; el brazo de cola más corto baja el margen estático de 15,1 a **12,2 % MAC**; pérdida 13,6 m/s, arranque 22 m/s. `tests/test_p51_handling.gd` 15/15, `tests/test_aircraft_catalog.gd` 34/34, `aircraft/verify_p51.gd` 126/126.

## Comparación con la foto oblicua del usuario

El propietario aportó un recorte con alpha de un P-51D real («Val-Halla», cola roja) en oblicua baja frontal con tren abajo. Es el caso de las fotos del Avanti: seis puntos marcados (ápice del cono, puntas alares, cima de la deriva, apoyo de las dos ruedas), cámara en perspectiva ajustada con el campo de visión libre (teleobjetivo: queda en el límite de 4°, distancia y FOV no se separan), render transparente a 1579 × 996 y superposición. Herramientas en [`silhouette/photo/`](../../research/p51/p51-02/silhouette/photo/): `picks.json`, `fit.py`, `review_photo.py`; el original y las composiciones quedan en `references/p51-mustang/user-photos/` (foto de tercero, fuera de Git); en el repositorio van los puntos, la cámara, el render cian del modelo y [metrics-2026-10-06.json](../../research/p51/p51-02/silhouette/photo/metrics-2026-10-06.json).

| | Valor |
| --- | --- |
| Ajuste de cámara (6 puntos) | RMS **8,6 px**; puntos reservados (cima de cabina, labio de la toma) 14,3 px |
| Contorno foto → modelo | **8,6 px** de media, p90 18,4 px; modelo → foto 8,9 px |
| IoU (palas borrosas excluidas por alpha < 200 y cajas) | **0,80** |

Lo que enseñó: la boca de la toma real es un escalón casi vertical, no una rampa (el labio quedaba 48 px alto): se corrigió la regla de `apply_metrology.py` y el labio baja a −1,11 m desde z 1,23. La cima de la cabina del modelo queda ~10 px alta y el parabrisas algo adelantado desde este ángulo (ambiguo entre altura y profundidad; no se cambió). Diedro, vía, altura del tren, posición de deriva y estabilizador y la cuerda de las puntas coinciden dentro del ruido de los picks. El fuselaje real lleva puertas de tren, antena y piloto; el modelo no.

Dos trampas registradas: primero asigné las alas al revés (el avión muestra su lado **derecho**: la escarapela visible en el intradós va en el ala derecha; con el morro a la derecha de la imagen, el lado visible es el derecho), lo que daba 27 px de RMS y una cámara reflejada, como ya pasó en el Avanti; y marqué el vértice del cono en el borde de la silueta en vez del ápice (centro del casquete visto).

## Límites

- Píxeles, no milímetros: la métrica no identifica piezas y el borde más cercano puede ser de otra; tampoco valida aerodinámica.
- El perfil del dibujo es un 3 % anisótropo; solo se calibra la escala horizontal para la cámara, así que las alturas del perfil arrastran ese error (≈ 5 mm sobre el modelo en la deriva).
- La extensión del borde de ataque de raíz, el carenado de salida, las puertas del patín y los depósitos no se modelan; los flaps y alerones conservan sus fracciones estimadas (no se distinguen en la silueta).
- La frontal del dibujo es cualitativa (palas no separables). En la foto, las palas se excluyen por alpha y cajas; la cámara de teleobjetivo deja FOV y distancia correlacionados (fiarse de la superposición, no de la distancia). El eje de empuje real está 1°45' inclinado respecto a la línea de referencia; el modelo lo mantiene paralelo (P51-06).

## Lección

Empezar por extraer cotas con rellenos fue el camino largo: la superposición con cámaras ancladas mostró de un vistazo los tres errores grandes (ala adelantada y alta, cabina atrás) que luego cuantificó la metrología. Orden correcto: superponer, mirar, corregir, medir.
