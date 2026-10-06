> Archivo histórico de la revisión 4. El plan vigente está en [UGLY-STIK-PLAN.md](../UGLY-STIK-PLAN.md).

# Ugly Stik: plan de modelado en paralelo

Revisión 4 · 2026-10-05 · Basada en [diez investigaciones](../research/ugly-stik-investigations/README.md). **Modelo .61 v2 conectado: morro corregido con la lectura local del plano Jensen.** [Informe y pruebas v2](../research/ugly-stik-model-v2.md). La calibración de las demás vistas sigue pendiente; la geometría estimada se identifica como tal.

> **Actualización 2026-10-05 (desarrollo principal):** Gate 1 eligió **Godot**. El constructor del avión vive ahora en [`app/render/airplane.gd`](../../app/render/airplane.gd), con las mismas interfaces (`airplane`, `propeller`, `*_hinge`). Las pruebas de `app/test.sh` comprueban signos de superficies sobre los nodos reales. Por decisión del propietario, los planos y CAD se movieron a `references/` (ignorado por git, solo local); las rutas de este documento ya apuntan allí. `assets/aircraft/ugly-stik-60/` contiene ahora el modelo v1.

> **Revisión de integración 2026-10-05 (desarrollo principal / física):**
> - El modelo v1 funciona en el simulador sin cambios de interfaz. Mis 106 comprobaciones (97 unitarias + 9 e2e: controles, física, traza) y la prueba de independencia de FPS pasan con él. `verify_model.gd` pasó 439/0 sobre la versión confirmada.
> - `app/test.sh` ejecuta ahora `aircraft/verify_model.gd` (como pedía la nota del ensayo), y CI ejecuta `compile_geometry.py --check` para que `geometry.json` y `ugly_stik_geometry.gd` no diverjan. Con su borrador actual (nueva comprobación de unión ala/fuselaje en `x=0`), `test.sh` falla 446/1. Es esperado; no confirmar hasta que pase.
> - Hallazgo visual: en el perfil ortográfico el ala parece separada del fuselaje por una franja fina. La nueva comprobación de la sección en `x=0` parece atacar justo eso.
> - `spec.gd`: las tablas BOXES/WINGS/WHEELS/SURFACES del bloque inicial ya no se usan. Mi `test_controls.gd` dejó de depender de `SURFACES`, así que se pueden borrar.
> - Área alar: `geometry.json` usa 720 in²; `DECISIONS.md` registra 723 in², leídos en el cartucho del plano Jensen (imagen JEN-01). La diferencia es 0,4 %. Para física (D1) registraré ambos con su fuente.
> - Para D1: el origen visual del modelo está "cerca del cuarto de cuerda; NO es un CG medido". La física usa el CG como origen del cuerpo, así que D1 definirá la posición del CG en el marco del modelo y el render desplazará la malla. Su geometría sigue siendo la única fuente de cotas: la física la leerá de `ugly_stik_geometry.gd` en lugar de copiarla.
> - **D1 hecho (física), 2026-10-05: medición del plano Jensen oz1253 a escala 1:1** (`research/d1/jensen_plan_cg.py`, lectura ±0,03 in). Cuerda 12,07 in (el cartucho dice 720 in² / 60 in = 12,00 in: verificación de escala 0,6 %). **Cara delantera del cortafuegos F1 a borde de ataque: 6,94 in (0,176 m)**. **CG del plano: 4,76 in detrás del borde de ataque (39 % de la cuerda).**
> - **Para el modelo visual:** `geometry.json` tiene el cortafuegos en `z = -0,44` y el borde de ataque en `-0,115`, es decir 0,325 m (≈12,8 in): el morro mide ≈1,85 veces el del plano. La física no depende de ello (usa borde de ataque y línea de empuje de su archivo, y el CG del plano), pero el morro se verá largo. El área 720 in² de su archivo coincide con el cartucho medido.

**Resolución de las notas anteriores, modelo v2:** la unión ala/fuselaje quedó corregida en v1 (449 comprobaciones); v2 corrige F1–borde de ataque a 176,276 mm y pasa 453 comprobaciones, además de la suite completa. Las tablas sin consumidores de `app/spec.gd` se eliminaron. D1 físico fue completado por el desarrollador principal; las mejoras dimensionales de la malla continúan en este frente. Las notas citadas arriba se conservan como historial.

La primera entrega es un **Jensen Ugly Stik .61 sencillo y articulado para Godot**, con fuente editable en `assets/aircraft/ugly-stik-60/` y constructor nativo en `app/aircraft/`. El propietario fijó primero el motor nitro de clase .61; **mini y gigante quedan para después**. La marca y el modelo concreto del motor siguen abiertos. Primero calibrar la geometría y conservar los mandos; después mejorar la silueta y añadir detalle visible. El [catálogo de recursos](../research/ugly-stik-resources.md) permite abrir aquí los planos, notas, manual y referencias descargados.

## Decisiones que cambian el plan inicial

| Investigación | Hallazgo y decisión |
| --- | --- |
| 01 · Fuente principal | El plano Jensen firmado y su escaneo anterior rotulan 60 in, **720 in²** y motor **.45–.61**. Usar esa fuente; conservar las discrepancias con la miniatura local por separado |
| 02 · Ala | La nota Jensen describe sección semisimétrica y el dibujo incluye diedro. Trazar la sección de esa variante; no elegir un NACA por apariencia ni copiar el ala plana Grid Leaks |
| 03 · Datos físicos | El CG es una referencia gráfica; masa y recorridos Jensen siguen sin establecer. El origen de la malla y sus límites visuales no sustituyen estos datos |
| 04 · Instalación | El objetivo es clase .61. El manual oficial del O.S. 61FX aporta una referencia dimensional provisional; no selecciona la marca. El 65AX queda como comparación histórica. Definir conjunto motor/escape/hélice antes de cerrar morro y altura del tren |
| 05 · Reutilización | Hay un modelo REFLEX del Ugly Stik y documentación de su autor. Su ejecutable no se ejecutó ni se validó como malla importable; usar el documento como referencia comparativa |
| 06 · Apariencia | Las fotos corresponden a construcciones concretas, algunas modificadas. Identificar configuración y vista; una decoración no define geometría ni prueba superioridad visual |
| 07 · CAD | El Great Big Stik tiene estructura interna y mallas de renderizado almacenadas muy detalladas. Consultarlo por piezas; construir una superficie exterior ligera propia |
| 08 · Medición | El tamaño de página y una rueda rotulada dieron escalas distintas. Validar escala por hoja/vista con más de una dimensión independiente |
| 09 · Entrega | Un recurso GLB con bisagra pasó importación y comprobación de movimiento en Godot. Declarar los ejes y aplicar la conversión una sola vez |
| 10 · Distancia | A 100 m y 720p, la envergadura proyectada ronda 12 px en orientación favorable. Priorizar silueta y grandes áreas de color; detalle interno y LOD vienen después de medir |

Fuentes, límites y pruebas de cada conclusión: [índice de investigaciones](../research/ugly-stik-investigations/README.md). Las cifras documentales candidatas están en [jensen-geometry-candidates.json](../research/ugly-stik-investigations/evidence/jensen-geometry-candidates.json): es un registro de investigación, no datos que `app/` ya esté cargando. La longitud de 52 in de la miniatura no se promueve a medida confirmada del plano firmado.

## Reparto de trabajo

| Frente | Archivos y responsabilidad |
| --- | --- |
| Desarrollador principal | Física/simulación, controles, escena principal, capturas oficiales y documentos principales del proyecto |
| Investigación/modelado | Este plan, `docs/research/ugly-stik-*`, `app/aircraft/`, adaptador `app/render/airplane.gd`, fuente en `assets/aircraft/`, experimentos en `research/ugly-stik/` y referencias locales |
| Modelo actual | `assets/aircraft/ugly-stik-60/geometry.json` y compilador reproducible de la copia Godot |
| Integración | Cambio pequeño sobre una revisión estable del constructor Godot; comparar las pruebas existentes antes y después |

El otro desarrollador trasladó las referencias antiguas a `references/ugly-stick/` (con `ck`); las descargas nuevas están en `references/ugly-stik/`. Ambas permanecen locales por la exclusión de `references/` del repo. La integración v1 modifica únicamente el frente de modelado asignado en AGENTS: `app/aircraft/`, `app/render/airplane.gd` y aclaraciones de las tablas visuales antiguas en `app/spec.gd`. Las capturas actuales se guardan en `research/ugly-stik/model-v2/`, con v1 conservado como historial; no se editan la física ni las capturas oficiales. Las herramientas auxiliares se probaron en entornos temporales aislados.

## Secuencia de entregas

Son subtareas de **D1**, conservación de **B5**, integración tras **B7** y legibilidad de **D7/Gate 2** del [roadmap](../../ROADMAP.md); no añaden una fase ni reabren la selección de plataforma.

| Orden | Entrega pequeña | Prueba |
| --- | --- | --- |
| 1 · D1 | **Investigación realizada:** fuentes, variantes, recursos, incertidumbres y experimentos | Diez estudios, archivos descargados con hashes, informes de CAD, escala, proyección e importación |
| 2 · D1 | Calibrar las vistas Jensen y fijar datum/extremos; trazar contorno lateral y superior del fuselaje | Dos controles de escala por vista y una cota reservada fuera del ajuste; tabla de residuos y errores de lectura |
| 3 · B5/D1 | Extender el ensayo de bisagra a alerones con diedro, elevador, timón y hélice | Nombres únicos, jerarquía, escala y posiciones finales en neutro y ambos sentidos; los pivotes permanecen unidos |
| 4 · D1 | Fuselaje de pocas secciones, afinado hacia la cola, con morro provisional | Vistas ortográficas y cotas comparables al contorno; distinguir fuselaje de longitud total instalada |
| 5 · D1 | Ala basada en la sección Jensen; puntas y alerones separados; diedro con referencia identificada | Planta, sección y vista frontal; comprobar envergadura y límites móviles; toda simplificación etiquetada |
| 6 · D1 | Contornos del estabilizador y conjunto vertical redondeado | Vistas superior/lateral y recorrido libre de elevador/timón; respetar la separación fija/móvil del plano |
| 7 · D1/E1 | Equipo visible de una instalación .61 explícita: motor, escape, hélice, ruedas y patas | Vista lateral con cotas y holgura hélice/suelo; sin atribuir masa, empuje o rigidez a la malla |
| 8 · D7/Gate 2 | Decoración y lectura desde tierra sobre la misma geometría | Serie a 20/50/100 m, misma cámara, ambas caras y virajes; identificar orientación con el usuario |
| 9 · D1, después de B7 | Conectar el recurso terminado al constructor Godot | Pruebas existentes de superficies/ejes y nuevas capturas neutra/deflectada; comprobar importación y escala |

**Estado v2:** fuente de geometría editable, fuselaje afinado, sección alar con diedro y marcos de mando separados, cola redondeada, equipo .61 simplificado y tren triciclo. Las pruebas de articulación y las capturas son parte de esta entrega. El morro ya usa la lectura Jensen de 6,94 in, con control local por cuerda. **Próxima comprobación dimensional:** identificar y calibrar el contorno de cola y las estaciones restantes con referencias independientes; las trazas actuales no cierran ese control. Si una cota secundaria no se resuelve, se estima con un rango explícito; masa, inercia y polares desconocidas no bloquean la primera silueta. La incertidumbre de longitud sí impide presentarla como reproducción dimensional exacta.

La integración conserva las interfaces de [el constructor](../../app/render/airplane.gd) y los mandos existentes. [app/spec.gd](../../app/spec.gd) conserva constantes de escena y controles; la geometría actual viene del registro visual. La prueba de cada paso debe acompañar su futuro commit. D1 físico está completado en el frente principal: esta malla no define masa, inercia ni derivadas aerodinámicas.

## Modelo y contrato de entrega

La fuente editable será pequeña y paramétrica: secciones del fuselaje, contorno alar extruido y contornos de cola con espesor. Los datos de geometría llevarán variante, fuente, unidad original, conversión SI, método, evidencia e incertidumbre. Empezar por superficies externas; los detalles de construcción quedan como referencias o una futura vista educativa.

La primera configuración es **Jensen 60 in / nitro .61**: `60` en la carpeta propuesta describe envergadura, no cilindrada. Una vez validada, mini y gigante podrán reutilizar el generador geométrico, la jerarquía de mandos y la escena de inspección. Cada variante necesitará sus propios datos de equipo, masa, inercia y aerodinámica; cambiar la escala de la malla no valida su vuelo. No se implementan esas variantes ni una arquitectura de familias en esta entrega.

La salida para Godot conserva raíz, hélice y mapa de bisagras de la interfaz existente. **Ruta elegida para v1:** malla procedural nativa (`SurfaceTool` y primitivas), con constantes generadas desde JSON; sin importación GLB en la aplicación. El experimento GLB anterior queda como opción de intercambio, no como dependencia adicional. GLB es una ruta comprobada para un recurso mínimo; si se adopta para el avión, acompañarlo de su fuente editable y del procedimiento de exportación. La prueba no obliga a introducir Blender ni una nueva dependencia en la aplicación.

- Nombres: `airplane`, `propeller`, `aileron_left`, `aileron_right`, `elevator`, `rudder` y sus `*_hinge`, únicos dentro del recurso.
- Frontera del simulador: metros, morro `−Z`, derecha `+X`, arriba `+Y`. Datum geométrico explícito; CG físico almacenado aparte.
- Jerarquía: pieza bajo su pivote, posición neutra conservada y rotación aplicada alrededor de la bisagra. Con diedro, el eje del alerón debe acompañar la semiala.
- Signos observables: roll positivo sube el borde de salida derecho y baja el izquierdo; pitch positivo sube elevador; yaw positivo lleva el timón a la derecha del avión.
- Exportación futura: declarar la orientación del recurso y ensayar la conversión una sola vez. El modelo nativo v1 ya usa los ejes del simulador y no aplica ese giro. El frente canónico glTF y el del simulador difieren; no añadir giros implícitos en varias capas. [Contrato y experimento](../research/ugly-stik-investigations/09-export.md).
- Geometría visual, parámetros físicos y configuración de equipo siguen separados. No derivar masa/inercia de una malla maciza ni coeficientes aerodinámicos de su perfil visual.

## Validación visual y rendimiento

Preparar una escena de inspección aislada, con fondo uniforme, vistas ortográficas superior/lateral/frontal y una vista tres cuartos. Guardar dimensiones, encuadre y pose. Eso distingue defectos de forma de errores de cámara.

Para lectura de vuelo, las distancias 20/50/100 m son muestras de prueba elegidas, no límites operacionales. Fijar FOV vertical de 50°, resolución y `KEEP_HEIGHT` en la escena Godot. El estudio de proyección ya cuantifica la pérdida de detalle; las capturas del nuevo avión ya permiten inspección a esas distancias; falta el ensayo de percepción con pilotos. El intradós oscuro sigue siendo una alternativa visual a comparar.

Registrar triángulos, materiales, tamaño de archivo y tiempo de render de la primera malla. No fijar un presupuesto arbitrario ni optimizar el CAD completo de antemano. El LOD automático de Godot se evalúa si la medición lo justifica. El rendimiento en software de esta VM no representa la GPU del usuario.

## Pendientes que la investigación no resolvió

- Longitud y posiciones de superficies calibradas sobre una referencia Jensen consistente.
- Coordenadas de perfil, incidencia y ángulo de diedro instalado; la elevación dibujada no es un ángulo publicado.
- Marca/modelo e instalación final del motor .61, escape/hélice y equipo; masa, inercia y recorridos de una construcción real. El CG gráfico Jensen ya fue leído para D1; no equivale a medir un ejemplar construido.
- Reutilización de recursos REFLEX y equivalencia dimensional del Great Big Stik con Jensen.
- Revisión perceptual con pilotos y rendimiento en hardware real; las capturas locales no sustituyen esas pruebas.

Los [estudios](../research/ugly-stik-investigations/README.md) dejan la evidencia y los pendientes. El [informe v1](../research/ugly-stik-model-v1.md) conserva la primera implementación; el [informe v2](../research/ugly-stik-model-v2.md) registra la corrección dimensional y sus pruebas.

## Nuevos recursos aportados por el propietario

[Ultra Stick V3 y MoJo Parts 60: análisis](../research/ugly-stik-new-files.md). El paquete principal identifica Ultra Stick 120 Light/Lite y trae planos/DXF/patrones con registro de 1 in. Se conserva para una posible variante grande y para mejorar la extracción de contornos nominales; no reemplaza la referencia Jensen .61 ni cierra su calibración. El manual incluido y el redibujo difieren en dimensiones, así que sus datos permanecen separados.

**Organización completada:** 31 originales conservados byte a byte bajo `references/ultra-stick-120/` y `references/mojo-60/`, con enlaces y manifiestos actualizados. El [índice por avión](../research/aircraft-reference-index.md) mantiene estas fuentes separadas del Jensen .61.
