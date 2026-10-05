# 10 · Lectura distante, coste y LOD

Fecha: 2026-10-05. **Pregunta:** ¿qué se conserva de las marcas a distancia y qué conviene medir antes de simplificar el modelo?

## Alcance y fuentes

Consulté docs oficiales **4.7**, no específicas del parche; el repo fija `4.7.2-stable`, que requiere verificación local. `project.godot` usa Compatibility y `msaa_3d=2`, enum **MSAA 4×**. El builder crea mallas; [`airplane.gd`](../../../app/render/airplane.gd) actualiza rotaciones.

## Hallazgos

Godot advierte que el aliasing 3D puede hacer parpadear superficies y borrar líneas finas. Compatibility admite MSAA 3D, pero no TAA, FXAA ni SMAA. MSAA suaviza bordes geométricos, no alias de textura ni especular; 4× ayuda a la silueta con más coste que 2×. [Antialiasing 3D 4.7](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html) · [Viewport 4.7](https://docs.godotengine.org/en/4.7/classes/class_viewport.html) · [Renderizadores 4.7](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html)

Con FOV 50° y salida 1280×720, el estudio previo proyecta una junta de 2 mm a 0,031 px a 50 m y 0,015 px a 100 m; es cálculo, no prueba humana. [Proyección previa](../ugly-stik-investigations/10-screen-readability.md). Dejar filetes finos para primeros planos y decidir su lectura distante con capturas.

El manifiesto cuenta mallas, triángulos y materiales, no draw calls. Godot expone primitivas y llamadas por fotograma en `RenderingServer`/`Performance`, y cambian con cámara u objetos ocultos. Perfilar antes de fijar presupuesto o agrupar superficies. [RenderingServer 4.7](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html) · [Performance 4.7](https://docs.godotengine.org/en/4.7/classes/class_performance.html)

El LOD automático se genera al importar escenas, no en el builder GDScript. `ArrayMesh` admite índices LOD explícitos; `SurfaceTool.generate_lod()` está obsoleto y pierde normales/UV, por lo que no debe reducir la piel texturizada. `Visibility Range` permite HLOD manual por `GeometryInstance3D`. Sin coste medido, no imponer LOD ahora. [LOD 4.7](https://docs.godotengine.org/en/4.7/tutorials/3d/mesh_lod.html) · [ArrayMesh 4.7](https://docs.godotengine.org/en/4.7/classes/class_arraymesh.html) · [SurfaceTool 4.7](https://docs.godotengine.org/en/4.7/classes/class_surfacetool.html) · [Visibility Range 4.7](https://docs.godotengine.org/en/4.7/tutorials/3d/visibility_ranges.html)

## Cambio sugerido en US-V y validación

En **US-V02**, comparar cruces/filetes con MSAA 4×, mipmaps y vistas rasantes. En **V04/V05**, crear una vez los nodos móviles y animar transformaciones como hace el adaptador. En **V08**, medir draw calls/primitivas por fotograma además de conteos estáticos; posponer LOD hasta que lo justifique el perfil.

Validar 36 vistas a 20/50/100 m, 1280×720 y FOV 50°, macros y mandos animados. Registrar renderer, GPU y tiempos con cámara/luz idénticas. No se ejecutó benchmark ni se fija límite de polígonos.
