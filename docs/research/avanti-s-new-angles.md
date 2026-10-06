# Avanti A200 · más ángulos para contrastar la maqueta

2026-10-06 · **30 fotografías oficiales adicionales**, una ilustración comercial de tres vistas, un PDF de Aerotec y su ficha comercial de procedencia: **33 archivos nuevos inventariados, 7.399.303 bytes**. Los JPEG son 31, contando la ilustración. Las fotos pertenecen a los álbumes oficiales ya conocidos: son imágenes nuevas en el archivo local, no 30 fuentes independientes.

[Galería local y tres superposiciones](../../references/avanti-s/new-angles/index.html) · [inventario de esta ronda](avanti-s-new-angle-resources.json) · [fuentes externas complementarias](avanti-s-additional-angle-sources.md).

## Qué aporta cada grupo

| Referencias | Uso concreto |
| --- | --- |
| CIMG7322 / CIMG7323 | Frontal media y frontal baja centrada: comparar sección del vientre, anchura de morro/cabina, bocas de toma y simetría del ala. El avión grande del fondo no forma parte de las anclas. |
| CIMG7345 / CIMG7346 | Bajo el morro y bajo el ala: forma de la toma, vientre, tren delantero, patas y mecanismos. Son detalles en perspectiva, con partes recortadas. |
| CIMG7311 / CIMG7312 / CIMG7314 | Perfil posterior y cola cercana: continuidad del lomo, estabilizador, deriva y salida. CIMG7314 recorta parte del ala; no sirve para medir envergadura completa. |
| CIMG7308 / CIMG7309 | Diagonales altas: cabina y planta, relación ala/fuselaje y estabilizadores. |
| VOLO-9 / VOLO-13 / VOLO-19 / VOLO-21 | Perfil invertido y distintas vistas del intradós; VOLO-21 permite ver simultáneamente vientre, ala y cola. No se conocen todos los estados de mando. |
| VOLO-7 / VOLO-8 / VOLO-16 / VOLO-17 | Planta superior en viraje: contorno alar, transición de cola y distribución de color. |
| Otras fotografías descargadas | Interior sin cabina, aproximación, pasada, aterrizaje y contexto; menor prioridad para geometría. |

Los índices de fabricante contenían fotografías que no estaban incluidas en la descarga inicial. Se siguieron los enlaces públicos de sus páginas individuales y se conservaron los originales sin recorte ni remuestreo. Las resoluciones varían; muchas imágenes de vuelo tienen 650 píxeles de ancho y alturas distintas. El visor respeta la relación de aspecto de cada archivo. [Galería SebArt en tierra](https://www.sebart.it/img-photogallery/2012-Avanti-jet/ThumbnailFrame.htm), [galería SebArt en vuelo](https://www.sebart.it/img-photogallery/2012-Avanti-jet2/ThumbnailFrame.htm).

La [lámina de Intermodel](https://cdn2.intermodel.fr/34864-thickbox_default/avanti-s-avec-train-2200mm-jaune-noir-sebart.jpg) presenta planta superior, perfil e inferior en 800 × 800 px. Su [ficha](https://www.intermodel.fr/soldes/10624-avanti-s-avec-train-2200mm-jaune-noir-sebart-sebart-jet-jaune-noir-sebart-avanti-2200mm-avanti-s.html) identifica el A200 amarillo/negro con 2000/2220 mm y SKU `81-A200-YB+LG`. Es una ilustración sin cotas ni procedencia CAD: útil para proporciones y librea, aún no un plano métrico ni de fabricación.

[Aerotec 2013](https://www.sebart.it/download/Aerotec2013.pdf) añade fotografías del avión y su instalación durante Bellota. El ejemplar descrito usa Behotec 220 con empuje vectorial. Se mantiene separado del P100-RX con salida fija elegido: no trasladar esa tobera o sus accesorios a la maqueta por semejanza de fuselaje.

## Tres cámaras nuevas, geometría v3 intacta

| Vista / foto | Qué permite contrastar | RMS ajuste / puntos reservados |
| --- | --- | --- |
| Frontal baja · CIMG7323 | Vientre, morro, anchura y separación de las tomas | 8,7 / 13,3 px |
| Oblicua frontal alta · CIMG7308 | Cabina, unión alar y forma de ala/cola desde otra diagonal | 11,9 / 9,0 px |
| Inferior en vuelo · VOLO-21 | Intradós y disposición relativa de ala y empenaje | 19,4 / 23,1 px |

[Puntos elegidos](../../research/avanti-s/new-angles/picks.json) · [cámaras](../../research/avanti-s/new-angles/camera-fit.json). Cuatro anclas aproximadas ajustan cada cámara; los demás puntos se reservan. Se mantiene FOV supuesto de 45°, sin calibración de lente. Las puntas se relacionan con posiciones aproximadas del modelo v3; los números de píxel no expresan cotas ni tolerancias físicas. Las tres cámaras antiguas permanecen intactas.

Una primera asignación izquierda/derecha en la foto inferior produjo una solución vista desde arriba pese a mostrar la foto el intradós. Se corrigió la correspondencia y se exige cámara en el hemisferio inferior. La prueba descartada queda solo en referencias locales, marcada `initial-rejected`; no se usa como evidencia de ajuste válido. Las comprobaciones de puntos reservados siguen siendo importantes: un residuo bajo con una vista físicamente equivocada no valida la reconstrucción.

## Qué muestran las superposiciones

- **Frontal baja:** la maqueta produce una sección frontal de cuerpo/cabina más ancha que la fotografía en parte de su contorno. Las tomas y su unión con la piel merecen nueva revisión. Todavía intervienen posición de cámara, altura del datum y forma aproximada.
- **Oblicua alta:** aparece una discrepancia en vientre/unión alar y en las puntas. No basta con el buen ajuste de nariz y deriva para declarar correcto el conjunto.
- **Inferior:** añade la evidencia que faltaba del vientre y raíces, pero es el encuadre menos fiable de esta ronda. Los mandos pueden estar deflectados y el modelo no incluye tren, puertas ni fences; no usar esta foto sola para modificar cuerda, diedro o estabilizador.

Son observaciones visuales sobre los PNG inspeccionados, no conclusiones aerodinámicas. **No se cambió la geometría del Avanti en esta tarea.** La siguiente edición debe cruzar estas vistas con las seis comparaciones existentes/nuevas y conservar la distinción entre planos comerciales, fotos y cotas documentadas.

## Organización y comprobación

La galería filtra por frontal, perfil, cola, intradós, planta superior, detalles inferiores, interior, contexto y documentos. Cada tarjeta conserva nombre de archivo/identificador de foto, descripción, resolución, origen y limitaciones. Los archivos están bajo `references/avanti-s/new-angles/`, excluido de Git por la regla existente; código, muestras y manifiestos permanecen en el repositorio.

[Validación](avanti-s-new-angles-validation.json): hashes de los 33 recursos, ajuste de cámaras reproducido idénticamente, tres renders idénticos en un clon local sin referencias, correspondencia entre proyección numérica y Godot, rechazo de un par cámara/anclas incompatible, navegador de escritorio/móvil y carga de las 31 imágenes. El motor fijado se proporciona externamente al clon. No se ejecutó la suite de `app/`; los cambios están en herramientas de investigación y documentación.

[Cómo reproducir el visor](../../research/avanti-s/new-angles/README.md). No se editó `.gitignore`, no se añadieron imágenes al índice ni se publicó nada.
