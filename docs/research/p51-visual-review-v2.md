# P-51D Mustang 1/4 · revisión visual 2 (cierre de V01-V10)

**Fecha:** 2026-10-06 · **Modelo:** `app/aircraft/p51d_model.gd` (`p51d-mustang-120-v1`, 132 mallas, 52.693 triángulos) · **Plan:** [P51-VISUAL-PLAN](../P51-VISUAL-PLAN.md) · **Revisión anterior:** [v1](p51-visual-review-v1.md)

Cierra la revisión visual 1 (18 hallazgos) tras ejecutar los pasos V01-V08 y V10 del plan. V09 (esquema de colores) sigue bloqueado por la decisión del propietario; V11 es este informe.

## 1. Método

Igual que en v1, con la cámara congelada en cada paso: tres vistas ortográficas del dibujo AN 01-60-3 (`research/p51/p51-02/silhouette/`: `prepare.py` → `render.gd` → `review.py`), la foto oblicua del propietario con cámara en perspectiva ajustada (`photo/fit.py` → `render.gd --fit` → `review_photo.py`), las suites `inspection` y `orbit` del inspector (`inspect_p51.gd`) y recortes ampliados de cada detalle. Cada paso dejó su evidencia en `research/p51/p51-02/silhouette/review-2026-10-06-<paso>/` (visor `index.html`, `metrics.json`, superposiciones) y en `research/p51/p51-02/review-2026-10-06-<paso>/` (capturas, recortes, `manifest.json` con los hashes de geometría y modelo).

La métrica es la de siempre: distancia media (px) de cada píxel del contorno real al borde alfa del render más cercano, la inversa, la IoU de las máscaras rellenas y ocho tramos longitudinales. No es precisión métrica por componente; mide cuánto se parece la silueta.

## 2. Antes/después por paso

Siluetas del dibujo (real → modelo, px / IoU) y foto del propietario. «Inicio» es la geometría medida de la revisión 1 (`review-2026-10-06`).

| Paso | Qué cambió | Lado | Frente | Planta | Foto (px / IoU) | `verify_p51` | Triángulos |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Inicio | geometría medida v7 | 7,7 / 0,871 | 13,6 / 0,450 | 10,7 / 0,907 | 8,6 / 0,801 | 100 | 50.011 |
| V01 | deriva, timón, estabilizador por contornos medidos; cono de cola; holguras | 7,2 / 0,871 | 13,6 / 0,450 | 10,8 / 0,906 | 8,6 / 0,803 | 124 (+ `verify_p51_clearance.gd` 12) | 50.067 |
| V02 | extensión del BA en la raíz, carenado, puntas redondeadas | 7,2 / 0,871 | 13,8 / 0,448 | 10,7 / 0,910 | 8,5 / 0,805 | 135 | 50.095 |
| V03 | conducto ventral con canal y compuerta, toma de carburador con labio | 7,1 / 0,872 | 13,6 / 0,456 | 10,7 / 0,910 | 8,3 / 0,813 | 141 | 50.127 |
| V05 + V07 | escapes cortos; pala ancha con cuff; eje de empuje visual −1°45' | 7,1 / 0,872 | 13,8 / 0,451 | 10,7 / 0,914 | 8,3 / 0,813 | 147 | 50.127 |
| V04 | parabrisas de tres paneles con marcos, raíles, mira, placa de blindaje | 7,1 / 0,872 | 13,7 / 0,453 | 10,7 / 0,914 | 8,3 / 0,813 | 162 | 50.277 |
| V06 | pata inclinada con tijera, puerta con forma, tapas del pozo, llantas con radios, puertas del patín | 6,9 / 0,876 | 13,7 / 0,455 | 10,7 / 0,914 | 8,4 / 0,813 | 208 | 51.493 |
| V10 | cañones, pitot, mástil y cable de antena, luces, tapas, trim tabs | **5,9 / 0,874** | 13,7 / 0,455 | **10,6 / 0,914** | 8,4 / 0,813 | 240 | 52.693 |
| V08 | acabado metal natural con líneas de panel y remaches (sin geometría) | = | = | = | = | 248 | 52.693 |

Umbrales del plan: lado ≤ 7,7 px ✔ (5,9), planta ≤ 15 px ✔ (10,6), foto IoU ≥ 0,80 ✔ (0,813). El frente (13,7 px, IoU 0,455) no tenía umbral: su silueta está dominada por la hélice y el tren del dibujo (tramos 5-7), que el modelo excluye o posa distinto; sirve de vigilancia, no de aceptación.

Tramos finales (real → modelo, px): lado `3,1 2,1 7,6 5,2 3,5 13,1 6,5 4,5`; planta `11,2 7,3 2,2 5,6 6,1 4,7 0,9 41,6`; frente `3,7 4,8 6,1 7,0 22,7 13,8 28,9 7,6`.

## 3. Estado de los 18 hallazgos de la revisión 1

| # | Hallazgo | Estado | Paso | Evidencia |
| --- | --- | --- | --- | --- |
| 1 | Deriva y timón | **Resuelto** | V01 | [cola](../../research/p51/p51-02/review-2026-10-06-v10/detail-tail-tabs-light.png) |
| 2 | Raíz alar | **Resuelto** (carenado discreto; su sombreado plano se ve en V08 como panel distinto) | V02 | [planta](../../research/p51/p51-02/silhouette/review-2026-10-06-v10/overlay_top.png) |
| 3 | Toma ventral | **Resuelto** | V03 | [vientre](../../research/p51/p51-02/review-2026-10-06-v03/belly-closeup.png) |
| 4 | Estabilizador y elevadores | **Resuelto** | V01 | [planta](../../research/p51/p51-02/silhouette/review-2026-10-06-v10/overlay_top.png) |
| 5 | Cabina | **Resuelto** (vidrio del parabrisas oscuro: muestra la bañera) | V04 | [cabina](../../research/p51/p51-02/review-2026-10-06-v04/inspection_cockpit_front_right.png) |
| 6 | Escapes | **Resuelto** | V05 | [morro](../../research/p51/p51-02/review-2026-10-06-v05/nose-closeup.png) |
| 7 | Tren principal | **Resuelto** | V06 | [tren](../../research/p51/p51-02/review-2026-10-06-v06/gear-closeup-oblique.png) |
| 8 | Hélice | **Resuelto** | V07 | [hélice](../../research/p51/p51-02/review-2026-10-06-v05/prop-closeup.png) |
| 9 | Puntas alares | **Resuelto** | V02 | planta |
| 10 | Materiales | **Resuelto** (coste de GPU pendiente de medir en equipo con GPU) | V08 | [A/B](../../research/p51/p51-02/review-2026-10-06-v08/ab-oblique-front-left-before-after.png) |
| 11 | Esquema | **Abierto**: espera la elección del propietario (V09) | — | — |
| 12 | Cono de cola | **Resuelto** (remate, luz de cola, puertas del patín) | V01, V06, V10 | cola |
| 13 | Toma de carburador | **Resuelto** | V03 | morro |
| 14 | Alerones y flaps | **Parcial**: huecos de bisagra marcados; flaps animables cuando la simulación los soporte | — | — |
| 15 | Piloto | **Parcial**: placa de blindaje y mira añadidas (V04); el piloto conserva su proporción y no tiene asiento | V04 | cabina |
| 16 | Detalles del ala | **Resuelto** (pitot bajo el ala derecha, corrige el plan) | V10 | [ala](../../research/p51/p51-02/review-2026-10-06-v10/detail-gun-ports-nav-light.png) |
| 17 | Fuselaje | **Resuelto** (mástil, cable, líneas de panel; sin puertas del radiador animadas) | V10, V08 | [lomo](../../research/p51/p51-02/review-2026-10-06-v08/detail-side-spine-rivets.png) |
| 18 | Eje de empuje | **Parcial**: visual −1°45' (V07); el dato físico sigue axial hasta P51-06 | V07 | — |

## 4. Órbita final

[Hoja el +10°](../../research/p51/p51-02/visual-review-2026-10-06-v2/orbit-el+10-sheet.png) · [el −25°](../../research/p51/p51-02/visual-review-2026-10-06-v2/orbit-el-25-sheet.png) · [el +40°](../../research/p51/p51-02/visual-review-2026-10-06-v2/orbit-el+40-sheet.png) (36 vistas, `inspect_p51.gd --suite=orbit`, manifiesto junto a las hojas). Desde cualquier azimut se reconoce un P-51D: morro largo con el antirreflejo, burbuja tras el parabrisas, toma ventral, deriva de cabeza redondeada, tren ancho.

## 5. Hallazgos abiertos (para una revisión 3)

De mayor a menor efecto:

1. **Esquema de colores (V09).** Hoy: cono rojo, antirreflejo oliva, timón y puntas amarillas, metal natural. Requiere la decisión del propietario; el `appearance.json` ya separa colores de patrones.
2. **Vista frontal.** 13,7 px de media, con el tramo 7 (ruedas) en 28,9 px: el dibujo muestra el tren comprimido en tierra y la hélice; el modelo posa el tren extendido. Si se quiere una métrica frontal útil, añadir una pose «en tierra» al render de siluetas (compresión del amortiguador) y excluir las palas.
3. **Planta, tramo 8 (41,6 px).** Cola del dibujo con el patín extendido y la cota del estabilizador; el modelo coincide en la cola, el residuo es del dibujo. Candidato a caja de exclusión, no a geometría.
4. **Parabrisas oscuro.** Los paneles planos muestran la bañera negra; en las fotos el parabrisas es más claro que la capota por el reflejo del cielo. Probar vidrio con más reflejo (metallic bajo, roughness 0,05) o un tinte menos denso solo en el parabrisas.
5. **Carenado de raíz.** Lee como panel aparte bajo el acabado V08 (es un `_strip` plano con `PLAIN`): darle normales suaves y la parte `FUSELAGE` o `WING` del sombreador.
6. **Piloto.** Proporción y asiento (hallazgo 15); barato pero sin efecto en siluetas.
7. **Flaps animables y puertas del radiador** cuando la simulación exponga esos estados.
8. **Cámaras a fotos de la USAF en tierra.** Opcional en V11; no se hicieron porque no se marcaron los seis hitos necesarios en esas fotos (`references/p51-mustang/`). Con ellas se tendrían dos vistas métricas más (frontal baja y tres cuartos trasera).
9. **Coste del sombreador V08 en GPU real.** Este equipo no tiene GPU: queda la medición con `--frametimes` en el equipo del propietario.

## 6. Qué no cambia

Las decisiones de la revisión 1 siguen: geometría a escala exacta 1/4 del P-51D, datos medidos en el dibujo con sus fuentes, la hélice visual y la física comparten el planform (V07 bajó el régimen estático de 5.967 a 5.751 rpm), y nada se edita a mano en los ficheros generados.

## 7. Límites

Mismos que en v1: la silueta mide parecido global, no exactitud por pieza; el dibujo es una reproducción escaneada con cotas y detalles que no están en el modelo; la foto del propietario es una pose en perspectiva con hélice en movimiento y FOV en el límite del ajuste. Las fotos de referencia de terceros no se redistribuyen (quedan en `references/`, ignorado por git).
