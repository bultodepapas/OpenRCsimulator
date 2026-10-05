# Diez investigaciones: Godot y herramientas para el Ugly Stik .61

2026-10-05 · Nueva ronda para la **revisión 4 del [plan visual](../../UGLY-STIK-VISUAL-PLAN.md)**. Complementa las [investigaciones de apariencia y montaje](../ugly-stik-visual-investigations/README.md); no las sustituye.

Se investigaron documentación oficial, repositorios de los autores y especificaciones, contrastándolos con el constructor y los flujos de validación locales. Cada informe contiene pregunta, hallazgos con fuentes, decisión, límites y prueba propuesta. **Investigación completada; implementación y ensayos nuevos pendientes.** No se instalaron dependencias ni se modificó la aplicación en esta ronda.

| # | Pregunta / informe | Decisión que mejora el resultado | Paso |
| --- | --- | --- | --- |
| 01 | [Geometry2D, SurfaceTool y ArrayMesh](01-polygons-and-meshes.md): ¿cómo mejorar contornos y UV sin rehacer el avión? | Mantener herramientas existentes; tratar huecos, normales y costuras de atributos explícitamente | V02 |
| 02 | [Resource y StandardMaterial3D](02-material-resources.md): ¿cómo compartir materiales sin contaminar instancias? | Recetas de material inmutables; aislar variaciones y ampliar la clave de caché | V02 |
| 03 | [Node3D y Curve3D](03-curves-and-articulation.md): ¿cómo dibujar conexiones y tubos estables? | Pivotes locales y transformaciones para piezas rígidas; curvas para rutas flexibles | V04–06 |
| 04 | [SVG, Inkscape y resvg](04-svg-toolchain.md): ¿cómo producir cruces y atlas reproducibles? | SVG simple y rasterización de Godot primero; herramientas externas condicionadas a un defecto real | V01–02 |
| 05 | [Blender y exportación glTF](05-blender-gltf.md): ¿cuándo aportan valor al constructor actual? | Autoría externa opcional; GLB explícito y contrato de pivotes si se incorpora una pieza | Opcional |
| 06 | [glTF Validator, glTF Transform y meshoptimizer](06-gltf-validation.md): ¿qué garantiza optimizar un GLB? | Validación estructural separada del roundtrip; aplazar compresión y cambios automáticos del grafo | Opcional |
| 07 | [trimesh y dependencias geométricas](07-mesh-audit-libraries.md): ¿qué puede auditarse además de las holguras actuales? | Contraste offline de cierre y orientación cuando sea útil; conservar comprobaciones del modelo construido | V02/V06 |
| 08 | [Pillow, SSIM y pixelmatch](08-image-regression.md): ¿cómo detectar regresiones visuales relevantes? | Diferencias por región con Pillow; calibrar tolerancias con defectos conocidos y revisar capturas | V02/V08 |
| 09 | [Importación, CI, GUT y gdUnit4](09-import-ci-tests.md): ¿cómo reproducir el nuevo acabado desde cero? | Esperar importación antes de pruebas; mantener suite actual y aplazar frameworks adicionales | V02/V08 |
| 10 | [Performance, RenderingServer, RenderDoc y MultiMesh](10-gpu-profiling.md): ¿dónde medir antes de optimizar? | Instrumentación nativa primero; hardware identificado y agrupación solo tras medir | V08 |

## Ruta de adopción

El primer resultado sigue siendo el avión rojo con cruces. Preparar la lámina SVG y una pieza pequeña que pruebe colores, filetes, bisagra, UV y acabado. Importarla desde una copia limpia antes de extenderla al avión. Después desarrollar motor y mandos con anclajes locales, manteniendo la interfaz del adaptador. Comparar imágenes y coste durante las entregas, además del cierre V08.

Las herramientas aplazadas no se convierten en requisitos del modelo: Blender, resvg, glTF Transform, trimesh, SSIM, GUT/gdUnit4 y RenderDoc necesitan un motivo concreto y una prueba acotada antes de entrar al flujo. Para cualquier adopción externa, fijar versión exacta y revisar licencia del artefacto elegido. El inventario local encuentra Pillow **11.3.0**, pero eso no equivale a una dependencia reproducible del proyecto.

## Alcance de la evidencia

El repositorio fija **Godot 4.7.2** y Compatibility; las páginas Godot consultadas corresponden a **4.7**. La documentación de una API no demuestra su resultado en nuestras mallas. Las pruebas propuestas no se ejecutaron en esta ronda, ni se midió rendimiento. Las cifras y pruebas v3 citadas son antecedentes registrados, no una nueva validación del árbol compartido.

Los enlaces primarios están junto a cada hallazgo. [sources.json](sources.json) recoge URLs, informes y hashes para recuperar esta revisión; no copia los sitios ni concede derechos de redistribución. La documentación del otro desarrollador sobre simulación y cámaras queda fuera del alcance.

Comprobación documental de esta entrega: diez informes numerados, 64 URLs citadas, 115 enlaces locales revisados entre informes/índice/planes/lecciones sin destinos ausentes, diez hashes verificados y `git diff --check` sin errores en el alcance documental. No se ejecutó la suite de simulación por este cambio de documentación.
