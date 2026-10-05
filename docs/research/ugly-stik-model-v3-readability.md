# Captura y lectura desde tierra: Ugly Stik v3

2026-10-05 · Evidencia para US-01 y US-06 del [plan de modelado](../UGLY-STIK-PLAN.md). El visor conserva dos series: `inspection` para comparar geometría con las nueve vistas históricas, y `readability36` para la prueba de orientación desde tierra.

## Estado

La captura completa se generó el 2026-10-05 con el modelo `jensen-60-nitro-61-v3`. La serie `readability36` contiene 36 PNG; una segunda ejecución independiente produjo los mismos 36 hashes SHA-256. La inspección contiene las nueve vistas y todas las comprobaciones de vértices proyectados quedaron dentro del viewport. La revisión humana sigue **pendiente**: no se han registrado respuestas, dudas ni porcentajes.

## Reproducción y protección de la evidencia

Desde la raíz del repositorio:

```bash
bash research/ugly-stik/model-v3/capture.sh
```

El destino predeterminado es `research/ugly-stik/model-v3/captures/`. En un clon limpio no existe todavía; en este árbol ya está ocupado por la evidencia descrita abajo. El script rehúsa directorios externos a `model-v3`; si el destino existe, se detiene. Con `--overwrite`, mueve el directorio anterior a un nombre de respaldo fechado antes de instalar la nueva captura. El script y el visor rechazan además cualquier destino dentro de `model-v1` o `model-v2`. Las carpetas, imágenes y scripts v1/v2 se conservan como historia.

El wrapper usa Godot 4.7.2 fijado por `app/get-godot.sh`, `xvfb-run`, OpenGL 3, audio dummy y una ventana de 1280×720. Hace dos ejecuciones en directorios temporales distintos. Antes de publicar la primera, compara por SHA-256 los bytes de cada PNG y exige los mismos nombres. No compara manifiestos ni tiempos de ejecución. Si alguna imagen difiere, falla sin sustituir el destino. El manifiesto final lleva cada hash PNG y el resultado de esta comparación.

El visor acepta explícitamente `--suite=inspection` (predeterminada) y `--suite=readability36`. La primera conserva `top.png`, `bottom.png`, `side.png`, `front.png`, ambas vistas de tres cuartos y las tres distancias de vuelo con sus cámaras fijas originales. La segunda crea el conjunto que usa US-06. Para inspección manual fuera del wrapper:

```bash
$(app/get-godot.sh) --path app --script res://aircraft/inspect_model.gd \
  --rendering-driver opengl3 --audio-driver Dummy -- \
  --suite=inspection --output-dir="$PWD/research/ugly-stik/model-v3/inspection-captures"
```

## Procedencia por captura

`manifest.json` obtiene el ID de geometría de `ugly_stik_geometry.gd`, que es el dato cargado por el constructor. También registra SHA-256 de la geometría compilada y, cuando está presente, de `assets/aircraft/ugly-stik-60/geometry.json`, junto con el ID JSON y si coincide con el ID compilado. Guarda hashes del constructor, adaptador, visor, wrapper y generador HTML.

Cada imagen conserva su pose del modelo, órdenes roll/pitch/yaw/throttle, posición/destino/eje arriba de cámara, FOV vertical o tamaño ortográfico, encuadre, resolución, distancia real en línea de mira y datos del renderizador. Los metadatos globales incluyen luces, fondo, adaptador gráfico, método de render y versión de Godot. Los tiempos de render se informan solo como diagnóstico; no son una prueba de repetibilidad.

## Serie de orientación `readability36`

La matriz contiene 3 distancias × 2 fondos × 6 actitudes. El origen visual del modelo se mantiene en `(0, 5, 0)` m. La cámara de piloto está en `(0, 1.6, distancia)` m, mira al origen visual y usa arriba mundial `(0, 1, 0)`. Las etiquetas 20/50/100 m indican separación horizontal sobre Z; el manifiesto registra además la distancia oblicua real. La lente vertical es 50°, `KEEP_HEIGHT`, a 1280×720. Cuerda, escala, luz y acabado permanecen fijos; las cuatro bisagras siguen neutras.

| Caso interno | Actitud dibujada | Referencia que se guarda en el manifiesto |
| --- | --- | --- |
| P01 | Sin rotación del cuerpo | Intradós, alabeo nivelado, cola hacia el observador |
| P02 | Giro del cuerpo de 180° en Z | Extradós, nivelado, cola hacia el observador |
| P03 | Giro del cuerpo de +35° en Z | Intradós, alabeo a la izquierda, cola hacia el observador |
| P04 | Giro del cuerpo de −35° en Z | Intradós, alabeo a la derecha, cola hacia el observador |
| P05 | Giro del cuerpo de 180° en Y | Intradós, nivelado, morro hacia el observador |
| P06 | Giros de 180° en Y y Z | Extradós, nivelado, morro hacia el observador |

Las etiquetas visibles de la página son códigos opacos permutados (por ejemplo, `K7`, `M2`, `R5`); no muestran la actitud ni la respuesta correcta. La página HTML sirve imágenes PNG a tamaño nativo 1280×720 CSS px y cada imagen se puede abrir en otra pestaña. El formulario empieza en blanco, la clave está cerrada en un desplegable por caso y las respuestas se descargan solo cuando la persona lo solicita. No hay escritura automática ni envío externo. Se debe abrir la respuesta después de registrar la lectura piloto. Esta nota contiene la clave de construcción y es para quien conduce la prueba; no debe compartirse con el piloto antes de registrar sus respuestas.

La pregunta de viene/se aleja usa el sentido del morro en una imagen fija. Evalúa reconocimiento de orientación como indicio estático; no mide percepción del movimiento real. Las imágenes `sky` usan un fondo azul liso. Las imágenes `ground` añaden un plano verde gris liso en Y=0 para marcar horizonte y suelo; no son un escenario de campo detallado.

Las nueve cámaras fijas de la serie `inspection` conservan posición, objetivo y vistas del modelo-v2. Para contener el mayor alcance del empenaje, el tamaño ortográfico superior e inferior cambia de 1.58 m a 1.90 m; el tamaño lateral cambia de 0.92 m a 1.05 m. Esta revisión de encuadre queda registrada en el manifiesto y no promete píxeles idénticos a las capturas v2.

## Resultados de captura

| Evidencia | Resultado |
| --- | --- |
| ID de geometría | `jensen-60-nitro-61-v3`; el ID JSON coincide con el ID compilado |
| SHA-256 de `geometry.json` | `b3a2c3588b05cd85f5a593c723a66e7a9cc3f6dac573971d751224977bd5594a` |
| SHA-256 de `ugly_stik_geometry.gd` | `764faf699b997628de7e54bca769dc49b34ffaef55f57c7a6aad2cbac5907f88` |
| Límites locales de la malla | X: −0.7612 a +0.7612 m; Y: −0.2581 a +0.1781 m; Z: −0.4178 a +0.8977 m |
| Serie `readability36` | 36 PNG de 1280×720; cada hash está guardado en `captures/manifest.json` |
| Repetición independiente | 36 de 36 hashes PNG coinciden; el manifiesto registra `identical_png_sha256: true` |
| Comprobación de encuadre readability | 36 de 36 imágenes tienen todos los vértices de malla proyectados dentro del viewport; margen mínimo 339.57 px |
| Serie `inspection` | 9 vistas; 9 de 9 comprobaciones de vértices dentro del viewport |
| Margen mínimo de inspection | Superior/inferior: 19.82 px; lateral: 24.44 px; frontal: 44.40 px |
| Respuestas humanas del propietario | Pendientes; todavía no hay sesión de lectura |

La aceptación visual se decide con las respuestas y dudas de una sesión, comparadas por distancia y fondo. Esta nota y el manifiesto describen el protocolo y la clave de referencia; no afirman éxito humano hasta que se registre una sesión. La igualdad comprobada es de bytes PNG por nombre de archivo; manifiestos y tiempos no se compararon.
