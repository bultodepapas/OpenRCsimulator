# Avanti S: primera maqueta Godot y nuevas referencias

2026-10-06 · **AV-02 iniciado como inspector aislado.** Ya existe un modelo procedural visible y articulado; falta refinar su forma e integrarlo en el inspector de la app. No es un avión volable y no se declara cerrada la metrología AV-01.

Galería de capturas y fotos nuevas (`references/avanti-s/av02/index.html`, local only) · maqueta oblicua (`references/avanti-s/av02/captures-v2/oblique-flap0.png`, local only) · planta (`references/avanti-s/av02/captures-v2/top-flap0.png`, local only) · flaps a 50° (`references/avanti-s/av02/captures-v2/rear-flap50.png`, local only) · [código e instrucciones](../../research/avanti-s/av02/README.md).

## Qué se construyó

El proyecto de estudio vive en `research/avanti-s/av02/`, separado del trabajo concurrente de menú, Extra y física. Corre con el Godot 4.7.2 ya fijado por el repositorio y Compatibility. No instala plugins, importa modelos ni depende de `references/`.

La geometría incluye fuselaje por 12 secciones elípticas, cabina por seis secciones, semialas en flecha, estabilizadores, deriva, tomas laterales esquemáticas, salida fija y un volumen nominal del P100-RX. Las superficies móviles son mallas distintas: dos flaps, dos alerones, dos elevadores y timón. La vista interior oculta piel/cabina para enseñar la escala del motor; no pretende representar todos los componentes internos.

Los controles visuales reproducen los límites del manual: flap 0/20/50°, alerón 30° arriba y 25° abajo, elevadores y timón 30° por sentido. Positivo de alabeo baja el alerón izquierdo y sube el derecho; positivo de cabeceo sube ambos elevadores. Cada deflexión se aplica sobre su eje de bisagra conservando el reposo. No se activan mezclas de emisora ni efectos aerodinámicos a partir de estos movimientos. [Manual SebArt, p.4](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf#page=4).

Se reutilizó el método del Stik/Extra —datos separados, superficies independientes, pruebas sobre la malla construida y capturas con pose restablecida— sin copiar sus dimensiones, física ni archivos en edición. `SurfaceTool` permite generar los triángulos y normales; se verifica su orientación conforme al orden de caras de Godot. La rotación se compone con `Basis` en el espacio del padre y no acumula incrementos entre capturas. Referencias: [SurfaceTool](https://docs.godotengine.org/en/stable/classes/class_surfacetool.html), [Node3D](https://docs.godotengine.org/en/stable/classes/class_node3d.html).

## Medido, nominal y estimado

| Elemento | Estado de evidencia |
| --- | --- |
| Envergadura 2,00 m y longitud 2,22 m | Nominal del A200 original; la maqueta mantiene esos extremos |
| Motor 241 mm × 97 mm | Envolvente nominal P100-RX elegida; no un CAD detallado del motor |
| Recorridos de mando | Nominales de manual; signos comprobados sobre puntos transformados |
| Datum longitudinal | Convención de modelo en LE de raíz; posición nariz–LE **estimada en 1,05 m** |
| CG 240/250/260 mm detrás del datum | Referencia de manual conservada en datos; no se resuelve CG/masa física de esta maqueta |
| Secciones de fuselaje/cabina | Estimaciones visuales; incertidumbre no cuantificada |
| Cuerdas, flecha, diedro, cola, bisagras | Estimaciones explícitas; no proceden de un plano calibrado |
| Alas y superficies | Sólidos delgados con espesor constante; no perfiles identificados |
| Tomas, salida y colocación del motor | Marcadores visuales estimados; no cotas de instalación A200-13 |
| Acabado blanco/azul/rojo | Identificación de piezas para inspección; librea detallada pendiente |

La fuente del modelo es [geometry.json](../../research/avanti-s/av02/geometry.json): unidades, ejes y evidencia por grupo. No se calcula una ficha de vuelo desde esa forma. La precisión numérica de una comprobación de escala no equivale a precisión de réplica.

## Qué añadió esta investigación

Se conservaron **cinco fotos oficiales de 4320 × 3240**, dos fotos de la familia de tubos y dos páginas HTML de procedencia. Son nueve descargas adicionales; el archivo acumulado alcanza **76 originales, 105.598.835 bytes**. Los originales nuevos están en `high-resolution/` (`references/avanti-s/high-resolution/`, local only), con nombres por vista. [Manifiesto](avanti-s-resources.json).

Las fotos de alta resolución permiten estudiar mejor los bordes de cabina, las tomas, las uniones y las placas verticales del ala. Siguen siendo perspectivas. Se inspeccionaron las cinco y no se utilizó una regla píxel/metro global para reconstruir el avión. [Descargas oficiales](https://www.sebart.it/download/).

La página de accesorios confirma A200-13 como opción original P100 de doble pared, coherente con la introducción del A200. No se encontró plano acotado del tubo ni un plano ortográfico oficial del avión. La lista de precios reciente usa otra combinación de referencias; no permite identificar la pieza fotografiada como A200-13 ni cambiar el tamaño del modelo. [Investigación complementaria](avanti-s-geometry-followup.md), [accesorios SebArt](https://www.sebart.it/accessories.html), [manual original p.2](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf#page=2).

## Comprobación realizada

- [Verificación headless](avanti-s-av02-checks.json): escala sobre la malla, siete bisagras, geometría finita, dimensiones de turbina, signos de mandos, reinicio e independencia de dos instancias; sin fallos. El contador incluye comprobaciones por vértice y no representa miles de casos de vuelo.
- [Clon limpio y fallo deliberado](avanti-s-av02-clone-check.json): copia del código nuevo sobre un clon local sin referencias ni caché Godot; verificación correcta. Invertir el signo del flap derecho **solo en ese clon temporal** produjo el fallo esperado. No se dejó código roto en el árbol compartido.
- Nueve capturas con renderer Compatibility mediante Mesa/llvmpipe: frente, perfil, planta, inferior, dos oblicuas, flaps 20°/50° e interior. Manifiesto de capturas (`references/avanti-s/av02/captures-v2/manifest.json`, local only) con motor, cámaras, hashes y estado. No es medición de rendimiento en GPU real.
- La primera captura reveló que la nariz en planta quedaba bajo los controles del inspector: se amplió el encuadre y se repitió la serie final. El audio se desactiva mediante driver Dummy; este estudio no genera sonido.

Los resultados de esta ronda se resumen en [avanti-s-av02-validation.json](avanti-s-av02-validation.json). No se modificó `app/` en esta tarea ni se ejecutó su suite durante las ediciones concurrentes; las comprobaciones pertenecen al proyecto aislado.

## Siguiente paso concreto

Comparar los contornos de la maqueta con las vistas nuevas, revisando cabina, transición de deriva, tomas y puntas. Las placas verticales del ala, perfiles y holguras de recorrido aún no están modelados. Faltan puertas/tren, continuidad fina de superficies, contraste inferior/superior y librea.

Antes de incorporar el constructor a `app/`, verificar volúmenes barridos y uniones, acordar el contrato de catálogo con el Extra y ejecutar regresión del Stik. AV-02 sigue pendiente de integración; AV-04 no se declara completo por tener siete pivotes. El primer vuelo continúa dependiendo de la rama de turbina AV-05 y de datos de masa, área y trim propios.

Comparación posterior: [transparencias y contornos sobre tres fotos](avanti-s-transparency-comparison.md), con cámaras ajustadas y geometría sin cambios.

Afinado posterior: [segunda revisión de contornos](avanti-s-contour-refinement.md), con cambios de geometría y las mismas cámaras. Los informes y capturas descritos arriba corresponden a la primera maqueta.
