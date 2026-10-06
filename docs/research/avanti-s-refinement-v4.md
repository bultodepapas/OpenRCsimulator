# Avanti AV-02 · revisión 4: siete superposiciones y detalles

Fecha: 2026-10-06. Revisión `a200-av02-contours-details-04`. Continúa la maqueta aislada de SebArt Avanti S A200 en `research/avanti-s/av02/`; todavía no está integrada ni vuela en la aplicación.

[Comparador local de siete vistas](../../references/avanti-s/refinement-v4/index.html) · [Modelo con materiales](../../references/avanti-s/refinement-v4/final/inspector/oblique-flap0.png) · [Comprobaciones](avanti-s-refinement-v4-checks.json) · [Métricas](avanti-s-refinement-v4-metrics.json) · [Reproducción](avanti-s-refinement-v4-validation.json).

## Cambios construidos

- Cabina: máximo de altura estimada de 0,251 a 0,275 m, estación desplazada 50 mm hacia atrás y transición contigua ligeramente elevada. Dos bandas blancas siguen la superficie a z = −0,63 y −0,29 m. Pertenecen al nodo de cabina y se ocultan con ella en el inspector interior.
- Deriva: desplazamiento gradual hacia atrás de la parte alta, máximo 60 mm, con ajuste del extremo superior del eje del timón. Se mantiene la transición inferior, altura y longitud total nominal.
- Dos placas verticales del ala, situadas a ±0,68 m del plano central. Espesor visual de 2 mm, extremo anterior redondeado mediante un polígono y borde posterior separado 18 mm de la bisagra neutra. Son aproximaciones de las placas visibles en las fotografías; terminan antes del alerón y no pretenden copiar su mecanismo real ni acreditar efecto aerodinámico.
- Salida de turbina: borde anular gris y cavidad oscura de 40 mm de profundidad, radio interior visual de 30 mm. Se elimina la tapa trasera del fuselaje para que no bloquee la abertura. No es un conducto térmico validado ni el diámetro de salida del motor. La envolvente nominal del P100-RX permanece independiente.

Las cotas anteriores son decisiones de modelado **estimadas**, registradas en `geometry.json`; no se han obtenido medidas físicas de las fotos. No cambia la escala nominal 2,00 × 2,22 m. Las tomas permanecen en su aproximación anterior. El acabado de colores identifica partes y mandos; no reproduce todavía la librea de las fotos.

## Evidencia usada y comparación

Se reutilizan las fotos ya archivadas de las [tres vistas iniciales](avanti-s-transparency-comparison.md), los [tres ángulos adicionales](avanti-s-new-angles.md) y el [perfil recortado del usuario](avanti-s-user-profile.md). Para los detalles se consultan CIMG7323 (frente), CIMG7345/7346 (placas) y CIMG7314 (cola). Procedencia y hashes en los manifiestos de recursos previos. La variante exacta del perfil del usuario sigue sin confirmarse.

Se vuelven a renderizar los siete encuadres con las cámaras y los puntos de calibración anteriores **sin reajustarlos**. Se preservan dimensiones nativas: 650 × 488, 650 × 489 y 1818 × 865. Cada par verifica hash de cámara, foto y captura. El comparador ofrece opacidad, fotografía visible/oculta y borde por filtro SVG; no modifica los archivos raster originales. Se conserva la v3 como antes y nueve vistas coloreadas de v4, incluidos flaps 0°/20°/50° e interior.

En el perfil del usuario se compara el borde superior de la componente alfa principal, a columnas fijas cada 5 px. Son distancias de pantalla bajo una alineación aproximada, no medidas físicas ni error global del avión:

| Tramo (x en píxeles nativos) | Error vertical medio absoluto v3 | v4 |
| --- | ---: | ---: |
| Deriva, 280–495 | 29,7 px | 15,1 px |
| Lomo, 500–795 | 79,4 px | 80,0 px |
| Cabina, 800–1545 | 49,3 px | 40,0 px |

El tramo medido de deriva **excluye la punta de x≈110–280**, que sigue sin coincidir. La silueta no mejora de forma uniforme. El lomo continúa demasiado bajo en ese perfil; no se ha elevado todo el fuselaje para perseguir una fotografía de variante y perspectiva desconocidas.

Las muestras de borde anteriores, a 650 × 488, también conservan sus puntos: frontal alta sin cambios apreciables; posterior alta empeora en cola 11,6→12,3 px y cuerpo 7,9→8,2 px; lateral mejora deriva 5,0→4,6 px y cuerpo 6,4→6,1 px. La muestra etiquetada «ala» lateral pasa 13,1→11,4 px, pero las placas nuevas añaden bordes: esto **no acredita una planta alar mejor**, que no se ha modificado. La métrica busca el borde más cercano y puede cambiar de componente.

Revisión visual de los otros encuadres: las placas añaden la estructura que faltaba en frontal baja y oblicua; la cabina más alta deja también más exceso en la frontal baja. La cola y el vientre siguen mostrando diferencias en intradós. Se acepta el ajuste moderado como paso parcial, conservando estas discrepancias visibles para la siguiente revisión; no se declara una mejora global en las siete vistas.

## Verificación y alcance

`verify.gd` comprueba escala, normales, interpolación, siete bisagras, signos de mando, reinicio e independencia de instancias. Añade ocultación de marcos, sección de triángulos reales del alerón en las dos caras de cada placa para cinco órdenes de alabeo, y salida sin tapa trasera. La separación comprobada es local y muestreada, no una certificación continua de todos los volúmenes barridos. El margen radial del test de salida admite 0,05 mm por la cuantización observada de ArrayMesh (hasta 0,019 mm en esta malla).

Resultado: 18.071 comprobaciones y cero fallos. Un clon local nuevo, con los archivos fuente actuales superpuestos y sin `references/`, reproduce las siete transparencias y nueve capturas. Las mutaciones deliberadas se ejecutan únicamente en esa copia: placa invadiendo alerón y tapa cerrando salida deben fallar. Véase el informe JSON de reproducción para el resultado y hashes.

El comparador se prueba en Chromium: siete opciones, imágenes cargadas, controles de opacidad/fondo/borde y vista móvil sin desbordamiento. No se ejecuta `app/test.sh`: este paso sólo cambia el estudio aislado y sus herramientas; no valida vuelo ni integración con el simulador. Las fotos, PNG, HTML generado y copia v3 permanecen en `references/`, ignorados por Git. No se ha hecho commit ni push.

## Repetir

Desde la raíz, con el Godot fijado disponible en `.tools/`, `xvfb-run`, las dependencias de `alignment/requirements.txt` y Pillow 11.3.0:

```bash
python3 research/avanti-s/refinement-v4/capture.py --output /tmp/avanti-v4-new --inspector
python3 research/avanti-s/refinement-v4/review.py --captures /tmp/avanti-v4-new --output references/avanti-s/refinement-v4
python3 research/avanti-s/refinement-v4/verify_repro.py --captures /tmp/avanti-v4-new --report /tmp/avanti-v4-validation.json
```

El directorio de capturas debe ser nuevo. El comparador necesita las referencias locales y capturas v3 archivadas; la construcción y las capturas de la maqueta no las necesitan.

Siguiente ajuste recomendado: contrastar lomo/raíz de deriva y sección de las tomas usando conjuntamente perfil y frontal baja. Después, precisar forma de placas y librea. Tren, perfiles aerodinámicos, datos de turbina e integración siguen pendientes.
