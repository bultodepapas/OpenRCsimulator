# Ugly Stik: plan de modelado en paralelo

Revisión 2 · 2026-10-05 · Basada en [diez investigaciones](research/ugly-stik-investigations/README.md). **Todavía no hay un avión nuevo:** hay fuentes recuperadas, datos contrastados y experimentos que permiten construirlo con menos incertidumbre.

> **Actualización 2026-10-05 (desarrollo principal):** Gate 1 eligió **Godot**. El constructor del avión vive ahora en [`app/render/airplane.gd`](../app/render/airplane.gd), con las mismas interfaces (`airplane`, `propeller`, `*_hinge`). Las pruebas de `app/test.sh` comprueban signos de superficies sobre los nodos reales. Por decisión del propietario, los planos y CAD se movieron a `references/` (ignorado por git, solo local); las rutas de este documento ya apuntan allí. `assets/aircraft/ugly-stik-60/` sigue libre.

La siguiente entrega será un **Jensen Ugly Stik sencillo y articulado para Godot**, preparado fuera de `app/`. Primero calibrar la geometría y conservar los mandos; después mejorar la silueta y añadir detalle visible. El [catálogo de recursos](research/ugly-stik-resources.md) permite abrir aquí los planos, notas, manual y referencias descargados.

## Decisiones que cambian el plan inicial

| Investigación | Hallazgo y decisión |
| --- | --- |
| 01 · Fuente principal | El plano Jensen firmado y su escaneo anterior rotulan 60 in, **720 in²** y motor **.45–.61**. Usar esa fuente; conservar las discrepancias con la miniatura local por separado |
| 02 · Ala | La nota Jensen describe sección semisimétrica y el dibujo incluye diedro. Trazar la sección de esa variante; no elegir un NACA por apariencia ni copiar el ala plana Grid Leaks |
| 03 · Datos físicos | El CG es una referencia gráfica; masa y recorridos Jensen siguen sin establecer. El origen de la malla y sus límites visuales no sustituyen estos datos |
| 04 · Instalación | Las dimensiones del fabricante permiten representar el candidato 65AX, pero su selección sigue abierta y excede el rango histórico rotulado. Definir conjunto motor/escape/hélice antes de cerrar morro y altura del tren |
| 05 · Reutilización | Hay un modelo REFLEX del Ugly Stik y documentación de su autor. Su ejecutable no se ejecutó ni se validó como malla importable; usar el documento como referencia comparativa |
| 06 · Apariencia | Las fotos corresponden a construcciones concretas, algunas modificadas. Identificar configuración y vista; una decoración no define geometría ni prueba superioridad visual |
| 07 · CAD | El Great Big Stik tiene estructura interna y mallas de renderizado almacenadas muy detalladas. Consultarlo por piezas; construir una superficie exterior ligera propia |
| 08 · Medición | El tamaño de página y una rueda rotulada dieron escalas distintas. Validar escala por hoja/vista con más de una dimensión independiente |
| 09 · Entrega | Un recurso GLB con bisagra pasó importación y comprobación de movimiento en Godot. Declarar los ejes y aplicar la conversión una sola vez |
| 10 · Distancia | A 100 m y 720p, la envergadura proyectada ronda 12 px en orientación favorable. Priorizar silueta y grandes áreas de color; detalle interno y LOD vienen después de medir |

Fuentes, límites y pruebas de cada conclusión: [índice de investigaciones](research/ugly-stik-investigations/README.md). Las cifras documentales candidatas están en [jensen-geometry-candidates.json](research/ugly-stik-investigations/evidence/jensen-geometry-candidates.json): es un registro de investigación, no datos que `app/` ya esté cargando. La longitud de 52 in de la miniatura no se promueve a medida confirmada del plano firmado.

## Reparto de trabajo

| Frente | Archivos y responsabilidad |
| --- | --- |
| Desarrollador principal | `app/`, controles, física, capturas y documentos principales del proyecto |
| Investigación/modelado | Este plan, `docs/research/ugly-stik-*`, experimentos en `research/ugly-stik/`, descargas en `references/ugly-stik/` |
| Modelo siguiente | Carpeta aislada propuesta `assets/aircraft/ugly-stik-60/`, comprobando que siga libre al comenzar |
| Integración | Cambio pequeño sobre una revisión estable del constructor Godot; comparar las pruebas existentes antes y después |

El otro desarrollador trasladó las referencias antiguas a `references/ugly-stick/` (con `ck`); las descargas nuevas están en `references/ugly-stik/`. Ambas permanecen locales por la exclusión de `references/` del repo. Los experimentos no escriben en `app/`, sus dependencias, capturas oficiales o índice Git. Las herramientas auxiliares se probaron en entornos temporales aislados.

## Secuencia de entregas

Son subtareas de **D1**, conservación de **B5**, integración tras **B7** y legibilidad de **D7/Gate 2** del [roadmap](../ROADMAP.md); no añaden una fase ni reabren la selección de plataforma.

| Orden | Entrega pequeña | Prueba |
| --- | --- | --- |
| 1 · D1 | **Investigación realizada:** fuentes, variantes, recursos, incertidumbres y experimentos | Diez estudios, archivos descargados con hashes, informes de CAD, escala, proyección e importación |
| 2 · D1 | Calibrar las vistas Jensen y fijar datum/extremos; trazar contorno lateral y superior del fuselaje | Dos controles de escala por vista y una cota reservada fuera del ajuste; tabla de residuos y errores de lectura |
| 3 · B5/D1 | Extender el ensayo de bisagra a alerones con diedro, elevador, timón y hélice | Nombres únicos, jerarquía, escala y posiciones finales en neutro y ambos sentidos; los pivotes permanecen unidos |
| 4 · D1 | Fuselaje de pocas secciones, afinado hacia la cola, con morro provisional | Vistas ortográficas y cotas comparables al contorno; distinguir fuselaje de longitud total instalada |
| 5 · D1 | Ala basada en la sección Jensen; puntas y alerones separados; diedro con referencia identificada | Planta, sección y vista frontal; comprobar envergadura y límites móviles; toda simplificación etiquetada |
| 6 · D1 | Contornos del estabilizador y conjunto vertical redondeado | Vistas superior/lateral y recorrido libre de elevador/timón; respetar la separación fija/móvil del plano |
| 7 · D1/E1 | Equipo visible de una instalación explícita: motor, escape, hélice, ruedas y patas | Vista lateral con cotas y holgura hélice/suelo; sin atribuir masa, empuje o rigidez a la malla |
| 8 · D7/Gate 2 | Decoración y lectura desde tierra sobre la misma geometría | Serie a 20/50/100 m, misma cámara, ambas caras y virajes; identificar orientación con el usuario |
| 9 · D1, después de B7 | Conectar el recurso terminado al constructor Godot | Pruebas existentes de superficies/ejes y nuevas capturas neutra/deflectada; comprobar importación y escala |

**Siguiente acción concreta:** calibración y contornos del fuselaje en la carpeta aislada. En paralelo se puede ampliar el pequeño ensayo de mandos. Si una cota secundaria no se resuelve, se estima con un rango explícito; masa, inercia y polares desconocidas no bloquean la primera silueta. La incertidumbre de longitud sí impide presentarla como reproducción dimensional exacta.

Antes de integrar, releer [app/spec.gd](../app/spec.gd) y [el constructor](../app/render/airplane.gd). Esta entrega no cambia sus valores. La prueba de cada paso debe acompañar su futuro commit. D1 sigue pendiente como entrega completa.

## Modelo y contrato de entrega

La fuente editable será pequeña y paramétrica: secciones del fuselaje, contorno alar extruido y contornos de cola con espesor. Los datos de geometría llevarán variante, fuente, unidad original, conversión SI, método, evidencia e incertidumbre. Empezar por superficies externas; los detalles de construcción quedan como referencias o una futura vista educativa.

La salida para Godot debe conservar raíz, hélice y mapa de bisagras de la interfaz existente. GLB es una ruta comprobada para un recurso mínimo; si se adopta para el avión, acompañarlo de su fuente editable y del procedimiento de exportación. La prueba no obliga a introducir Blender ni una nueva dependencia en la aplicación.

- Nombres: `airplane`, `propeller`, `aileron_left`, `aileron_right`, `elevator`, `rudder` y sus `*_hinge`, únicos dentro del recurso.
- Frontera del simulador: metros, morro `−Z`, derecha `+X`, arriba `+Y`. Datum geométrico explícito; CG físico almacenado aparte.
- Jerarquía: pieza bajo su pivote, posición neutra conservada y rotación aplicada alrededor de la bisagra. Con diedro, el eje del alerón debe acompañar la semiala.
- Signos observables: roll positivo sube el borde de salida derecho y baja el izquierdo; pitch positivo sube elevador; yaw positivo lleva el timón a la derecha del avión.
- Exportación: declarar la orientación del recurso y ensayar la conversión una sola vez. El frente canónico glTF y el del simulador difieren; no añadir giros implícitos en varias capas. [Contrato y experimento](research/ugly-stik-investigations/09-export.md).
- Geometría visual, parámetros físicos y configuración de equipo siguen separados. No derivar masa/inercia de una malla maciza ni coeficientes aerodinámicos de su perfil visual.

## Validación visual y rendimiento

Preparar una escena de inspección aislada, con fondo uniforme, vistas ortográficas superior/lateral/frontal y una vista tres cuartos. Guardar dimensiones, encuadre y pose. Eso distingue defectos de forma de errores de cámara.

Para lectura de vuelo, las distancias 20/50/100 m son muestras de prueba elegidas, no límites operacionales. Fijar FOV vertical de 50°, resolución y `KEEP_HEIGHT` en la escena Godot. El estudio de proyección ya cuantifica la pérdida de detalle; falta el ensayo de percepción y el render del nuevo avión. El intradós oscuro sigue siendo una alternativa visual a comparar.

Registrar triángulos, materiales, tamaño de archivo y tiempo de render de la primera malla. No fijar un presupuesto arbitrario ni optimizar el CAD completo de antemano. El LOD automático de Godot se evalúa si la medición lo justifica. El rendimiento en software de esta VM no representa la GPU del usuario.

## Pendientes que la investigación no resolvió

- Longitud y posiciones de superficies calibradas sobre una referencia Jensen consistente.
- Coordenadas de perfil, incidencia y ángulo de diedro instalado; la elevación dibujada no es un ángulo publicado.
- Configuración final motor/escape/hélice y equipo instalado; masa, CG numérico, inercia y recorridos reales.
- Reutilización de recursos REFLEX y equivalencia dimensional del Great Big Stik con Jensen.
- Aspecto del avión completo importado, rendimiento y lectura con pilotos.

Los [estudios](research/ugly-stik-investigations/README.md) dejan la evidencia, las lecciones y la siguiente prueba para cada pendiente. No se ejecutaron las pruebas de la aplicación ni se modificó su modelo en esta revisión.
