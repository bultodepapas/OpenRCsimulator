# Ugly Stik · revisión detallada del motor glow .61

2026-10-05 · US-V03/V06/V07 · Revisión mecánica `glow-61-detail-v5`, sobre geometría v3 y apariencia v4.

Se inspeccionaron las fotos D/F del propietario y las macros del modelo construido. El resultado conserva la instalación y mejora su anatomía visible. Las fotos muestran una culata dorada, cilindro con aletas, cárter alargado, carburador inclinado y silenciador lateral. Su inscripción no permite confirmar una variante comercial exacta. [Referencias, identidad y hashes](ugly-stik-visual-photo-brief.md) · [Procedencia de la instalación](ugly-stik-model-v4-equipment.md).

## Análisis y cambios aplicados

| Zona | Problema observado en v4 | Cambio v5 |
| --- | --- | --- |
| Cárter | Volumen ovoide y transiciones poco legibles en macro | Cuerpo longitudinal continuo con alojamiento frontal escalonado, junta, tapa posterior y apoyos redondeados para tornillos |
| Cilindro | Pila compacta, cantos y reflejos muy facetados | Fundición expuesta bajo nueve aletas con bordes biselados y normales radiales suaves |
| Culata | Marcas oscuras simulaban ranuras sobre un borde sólido | Doce cortes abiertos de 3,5 mm en el borde dorado y cuatro fijaciones con hueco interior |
| Bujía glow | Terminal ancho y bajo respecto a la nueva culata | Hexágono y terminal pequeño por encima de la culata, sin cable permanente |
| Carburador | El cilindro exterior tapaba la entrada aunque existiera un disco negro | Labio anular, pared interior y fondo profundo; la boca queda abierta |
| Bancada | Taladros simulados y fijaciones poco apoyadas | Orejas con perforaciones, pernos atravesando apoyos y arandelas delante de F1 |
| Escape | Cuello rígidamente rectangular, facetas y unión abierta entre ejes distintos | Fundición con esquinas redondeadas, nervaduras, cono con anillos orientados y boquilla con interior profundo |
| Acabado | Respuesta similar en piezas fundidas y mecanizadas | Perfiles separados de aluminio fundido, aluminio mecanizado y dorado anodizado |

El constructor agrupa el motor en `engine_assembly`; las superficies circulares usan perfiles de revolución con 48 segmentos y las cabezas hexagonales conservan caras planas. El cono del escape conecta un anillo normal al eje del silenciador con otro normal al eje de la boquilla. Esto elimina la abertura que aparecía al unir dos conos inclinados por su centro solamente.

Las nuevas proporciones son **estimaciones visuales**, no medidas del fabricante: nueve aletas, doce ranuras, sus espesores, radios y posiciones de tornillos. El terminal pasa de `shaft_y + 0,054 m` a `shaft_y + 0,072 m`; la corona mantiene radio exterior de 20 mm. Esta corrección de altura de 18 mm sirve a la anatomía fotografiada y no constituye calibración dimensional. El acabado limpio y el dorado también son decisiones artísticas.

Se conservan `shaft_y`, `firewall_z`, `prop_z`, diámetro/pivote de hélice, nodos y bisagras públicas, extremos de la transmisión del acelerador y punto de salida del escape. La modificación afecta a la representación; masa, inercia, potencia y aerodinámica siguen en sus datos existentes.

## Imágenes reproducibles

Se generaron once pares **antes/después a 2560 × 1440**, con cámaras, iluminación, poses, comandos y reglas de visibilidad iguales. El comparador rechaza diferencias en esos campos y valida dimensiones y SHA-256 de los PNG. Son renders reales del modelo Godot.

- [Comparación local de once ángulos](../../app/captures/ugly-stik-engine-v5/comparison.html).
- [Galería local de la revisión final](../../app/captures/ugly-stik-engine-v5/release/review.html).
- [Detalle del cárter, cilindro y montaje](../../app/captures/ugly-stik-engine-v5/release/engine-three-quarter-left.png).
- [Escape y unión de boquilla](../../app/captures/ugly-stik-engine-v5/release/engine-exhaust.png).

Los enlaces anteriores apuntan a artefactos locales ignorados por git. Para producir una nueva galería del modelo actual, desde la raíz:

```bash
research/ugly-stik/model-v4/capture-detail.sh --engine
```

Cada ejecución crea su propia carpeta y entrega su ruta. Admite `--output-dir PATH` para una carpeta nueva; necesita `xvfb-run`, Godot fijado por el proyecto y Python estándar. El recorrido completo de 28 imágenes sigue disponible sin `--engine`.

Para comparar dos suites guardadas:

```bash
python3 research/ugly-stik/model-v4/compare_engine.py \
  ANTES/manifest.json DESPUES/manifest.json --output comparacion.html
```

La base de esta comparación procede del commit `baeae36`, con el inspector actual copiado a un clon temporal para igualar cámaras y luces. No se sobrescribió la geometría antigua en el árbol compartido.

## Verificación

**`app/test.sh` pasó**: guardia de float64, parseo, pruebas unitarias/integración, contrato de 807 comprobaciones sin fallos, vuelo trimado y estado idéntico a 30/60/144 fps. [Log completo](ugly-stik-engine-v5-evidence/app-test.txt). Las once imágenes se reprodujeron por SHA-256 desde un clon limpio; la comparación carga sus 22 imágenes en navegador y cabe en pantalla de 390 px sin desbordamiento horizontal.

La evidencia numérica y los hashes se conservan en [el registro de validación](ugly-stik-engine-v5-validation.json). Las pruebas de `visual_checks.gd` lanzan rayos contra los triángulos construidos: cinco muestras de admisión, doce pares de ranura/diente y el fondo de la boquilla. También miden separación del motor respecto al plano de hélice; el contrato existente comprueba normales, winding, articulaciones y mandos.

La admisión medida ofrece 15,35–15,55 mm hasta la primera obstrucción, las doce ranuras tienen 3,50 mm de desnivel y la boquilla alcanza un fondo a 9,00 mm. La muestra de boquilla se desplaza radialmente 0,4 mm para evitar la coincidencia numérica con el vértice central compartido por sus triángulos.

Dos mutaciones aisladas comprueban que los tests detectan el defecto: tapar la admisión provoca cinco fallos y cerrar las ranuras provoca doce. [Log de mutaciones](ugly-stik-engine-v5-evidence/mutations.txt) · [Contrato y medidas](ugly-stik-engine-v5-evidence/model-contract.txt). Se ejecutan sobre mallas temporales en memoria:

```bash
$(app/get-godot.sh) --headless --path app \
  --script "$PWD/research/ugly-stik/model-v4/check_engine_mutations.gd"
```

Las pruebas de abertura complementan la inspección de imágenes: una superficie oscura puede parecer un agujero y seguir tapada. Los rayos convierten metros a milímetros para evitar que la tolerancia absoluta de intersección descarte triángulos pequeños; su segundo argumento es una dirección normalizada y se limita el alcance del resultado.

El avión completo pasa de **27.040 a 46.840 triángulos** (+19.800), conserva **74 mallas** y pasa de **23 a 25 materiales únicos**. En la captura `engine-left`, el contador del fotograma conserva **75 draw calls**. Es un aumento de detalle geométrico que deberá medirse en hardware objetivo.

La comparación visual revisa macros de culata, carburador, ambos costados, frente, montaje, escape y salida. Los contadores de render corresponden al fotograma completo; llvmpipe no es una medida de rendimiento en la GPU del piloto. Las piezas internas del motor y la identificación dimensional del modelo comercial quedan fuera de esta representación visual.
