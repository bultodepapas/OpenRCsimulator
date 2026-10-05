# 10 · Lectura distante, coste y LOD

Fecha: 2026-10-05. **Pregunta:** ¿qué se conserva de las marcas a distancia y qué conviene medir antes de simplificar el modelo?

## Alcance y fuentes

Consulté documentación oficial versionada Godot **4.7**. El repo fija `4.7.2-stable`; las páginas no nombran el parche, así que sus datos son de la serie 4.7 y se deben comprobar con ese binario. `project.godot` usa Compatibility y `msaa_3d=2`: el enum oficial identifica el valor 2 como **MSAA 4×**. El constructor actual crea mallas al montar el modelo; [`airplane.gd`](../../../app/render/airplane.gd) cambia rotaciones de bisagras y tren.

## Hallazgos

Godot documenta que el aliasing 3D puede hacer parpadear superficies y casi borrar líneas finas. Compatibility admite MSAA 3D, pero no TAA, FXAA ni SMAA; MSAA suaviza bordes geométricos, no el aliasing de texturas ni el especular. El 4× actual ayuda en bordes de la silueta y cuesta más que 2×; no garantiza que un filete UV se lea lejos. [Antialiasing 3D 4.7](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html) · [Viewport 4.7](https://docs.godotengine.org/en/4.7/classes/class_viewport.html) · [Renderizadores 4.7](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html)

La inspección previa, con FOV vertical de 50° y salida 1280×720, proyecta una junta de 2 mm a 0,031 px a 50 m y 0,015 px a 100 m; es cálculo de proyección, no prueba de percepción. [Cálculo previo de proyección](../ugly-stik-investigations/10-screen-readability.md). Mantener filetes finos como detalle cercano y decidir a distancia con las capturas; no hay un ancho correcto documentado por el motor.

Los triángulos, instancias y materiales del manifiesto describen la malla, pero no sustituyen el recuento de llamadas de dibujo. Godot expone primitivas y draw calls por fotograma en `RenderingServer`/monitores `Performance`; cambian con cámara y objetos ocultos. Perfilar vistas y hardware constantes antes de fijar un presupuesto o agrupar superficies. [RenderingServer 4.7](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html) · [Performance 4.7](https://docs.godotengine.org/en/4.7/classes/class_performance.html)

El LOD automático documentado se genera al importar escenas 3D; no se aplica al constructor GDScript actual. `ArrayMesh` acepta índices LOD explícitos por superficie. `SurfaceTool.generate_lod()` está obsoleto y la API advierte que pierde normales y UV, así que no sirve para reducir una piel ya texturizada. `Visibility Range` sí permite HLOD manual en `GeometryInstance3D`, con configuración y comprobación visual. No hay motivo medido para imponer LOD a la malla actual. [LOD de malla 4.7](https://docs.godotengine.org/en/4.7/tutorials/3d/mesh_lod.html) · [ArrayMesh 4.7](https://docs.godotengine.org/en/4.7/classes/class_arraymesh.html) · [SurfaceTool 4.7](https://docs.godotengine.org/en/4.7/classes/class_surfacetool.html) · [Visibility Range 4.7](https://docs.godotengine.org/en/4.7/tutorials/3d/visibility_ranges.html)

## Cambio sugerido en US-V y validación

En **US-V02**, comparar filetes y cruces con la configuración actual MSAA 4×, mipmaps y vistas rasantes. En **US-V04/V05**, mantener los nodos móviles creados una vez y animar transformaciones; el adaptador existente ya sigue ese patrón para bisagras y ruedas. En **US-V08**, agregar medición de draw calls y primitivas por fotograma, además de conteos estáticos; posponer LOD hasta que el perfil revele coste y solo simplificar detalles que no afecten silueta.

Validar las 36 vistas previstas a 20/50/100 m, 1280×720 y FOV 50°, más macros fijas y secuencia de mandos. Registrar renderer, GPU y tiempos; comparar antes/después con cámara y luz idénticas. Estas son propuestas: no se ha ejecutado un benchmark ni se fija un límite arbitrario de polígonos.
