# Avanti S · revisión 3: fuselaje y cabina

2026-10-06 · AV-02 sigue como maqueta visual aislada. Esta revisión continúa directamente desde `a200-av02-contours-02`; las cámaras, fotografías y muestras de contorno son las mismas. La geometría actual es `a200-av02-contours-03`.

Antes/después v2 → v3 (`references/avanti-s/refinement-v3/index.html`, local only) · captura oblicua actual (`references/avanti-s/refinement-v3/inspector-final/oblique-flap0.png`, local only) · oblicua anterior (`references/avanti-s/refinement-v2/inspector-final/oblique-flap0.png`, local only) · planta actual (`references/avanti-s/refinement-v3/inspector-final/top-flap0.png`, local only).

## Cambios conservados

- **Fuselaje delantero más estrecho y vientre menos profundo.** Las semianchuras estimadas en z = −0,65/−0,40/−0,15 m pasan de 109/153/178 a 95/129/151 mm. En la raíz se pasa de 177 a 162 mm. Son decisiones de modelado apoyadas en las tres perspectivas; no cotas medidas.
- **Cabina algo más estrecha:** semianchura máxima de 120 a 108 mm, conservando sus estaciones longitudinales y altura máxima. Todavía no se han medido cristales, marcos ni sección transversal real.
- **Secciones continuas:** interpolación cúbica Hermite monotónica, cuatro subdivisiones por tramo, pendientes interiores armónicas ponderadas y extremos con pendiente secante. Se conservan las estaciones originales y se limita cada componente a los extremos del tramo para evitar abultamientos artificiales.
- **Sombreado continuo:** normales calculadas a partir de las tangentes circunferencial y longitudinal. Las tapas mantienen normales de cara. Las pruebas comprueban que activar este sombreado no mueve los vértices.

Se revisó también la foto oficial de alta resolución `a200-hq-01-perfil-izquierdo-atardecer.jpg` para contrastar continuidad de lomo/cabina; no se ajustó una nueva cámara ni se extrajeron cotas de ella. La cabina y el cuerpo dejan de mostrar las grandes facetas del bloque inicial, aunque permanecen aproximaciones: perfil alar, librea, fences, tren y detalle de conductos están pendientes.

La cola conserva la revisión anterior. Su discrepancia en la perspectiva posterior no se corrige desplazándola para una sola foto. Ala, bisagras, tomas y turbina mantienen sus datos anteriores. Se mantienen envergadura 2,00 m, longitud 2,22 m y envolvente nominal P100-RX.

## Resultado con las mismas muestras

Distancia media en píxeles al borde visible más cercano del render, comparando **v2 contra v3**, no contra la primera maqueta:

| Vista | Fuselaje v2 → v3 | Ala v2 → v3 | Estabilizador v2 → v3 |
| --- | --- | --- | --- |
| Frontal elevada | **5,5 → 3,3** | 3,6 → 3,6 | 2,4 → 2,4 |
| Posterior elevada | **9,7 → 7,9** | 4,0 → 4,0 | 11,6 → 11,6 |
| Perfil oblicuo | 6,4 → 6,4 | 13,7 → 13,1 | 8,8 → 8,8 |

El ala no cambió: su pequeña variación de perfil procede de qué borde queda visible al reducir el cuerpo. La métrica no separa piezas. Las muestras fueron escogidas durante la revisión anterior y siguen siendo exploratorias; no son una prueba independiente ni una conversión píxel/metro. No se retocaron para favorecer este resultado.

[Mediciones y hashes](avanti-s-contour-v3-metrics.json). Se corrigió la descripción de la erosión: SciPy usa por defecto una cruz de **cuatro vecinos**, no ocho. El algoritmo y los cálculos anteriores no cambian; solo se corrige su etiqueta en los nuevos informes.

## Evidencia y límites

[Comprobaciones de la maqueta](avanti-s-contour-v3-checks.json): escala, siete bisagras, mandos, reinicio e independencia de instancias; además, interpolación sin sobrepasar extremos, estaciones preservadas, normales finitas/unitarias orientadas según las caras y vértices idénticos con sombreado plano/suave. El contador incluye verificaciones por vértice, no miles de pruebas independientes.

[Validación en clon limpio](avanti-s-contour-v3-validation.json): el código de estudio se copió sobre un clon local sin referencias ni caché inicial. Godot fijado proporcionado externamente; tres renders transparentes, nueve vistas del inspector y comprobaciones correctos. Anular deliberadamente las normales solo en ese clon hace fallar la verificación de orientación. La primera prueba de fallo mostró que longitud unitaria por sí sola no detectaba la mutación tras codificar la malla; se añadió la comprobación contra las caras y se repitió. La protección de cámaras sigue rechazando geometría distinta si falta `--compare-geometry`.

El visor conserva la revisión 2, muestra etiquetas v2/v3 y permite opacidad, contornos, muestras y alternancia. Se comprueba en Chromium a tamaño de escritorio y 390 px. Las fotos se mantienen intactas, con SHA-256 verificado. Todos los PNG, composiciones y copias de referencia continúan bajo `references/`, excluido de Git.

El refinamiento aumenta los triángulos de los dos cuerpos interpolados. No se ha medido rendimiento en GPU real ni se ha integrado el modelo en la aplicación. No se ejecutó la suite de `app/`: este cambio pertenece al proyecto aislado. La mejora de apariencia no valida masa, aerodinámica ni instalación interna; AV-01, integración AV-02 y vuelo permanecen abiertos.

## Reproducir esta comparación

Con los originales y renders v2 locales disponibles, generar un nuevo directorio de renders mediante el comando del [README de revisión](../../research/avanti-s/refinement/README.md), y después:

```sh
python3 research/avanti-s/refinement/review.py \
  --baseline references/avanti-s/refinement-v2/renders-final \
  --candidate references/avanti-s/refinement-v3/renders-final \
  --output references/avanti-s/refinement-v3 \
  --before-label 'Antes · revisión 2' --after-label 'Después · revisión 3' \
  --description 'Fuselaje más estrecho, cabina ajustada y superficies continuas.' \
  --report avanti-s-contour-refinement-v3.md
```

Siguiente paso: contrastar cabina y fuselaje con una cámara independiente sobre la fotografía grande y resolver la posición de la cola antes de añadir acabado o modificar física.
