# 10 · Perfilado GPU/CPU para Godot Compatibility

2026-10-05 · **Pregunta:** ¿qué medición ayuda a decidir si agrupar mallas repetidas o perfilar una captura?

## Configuración comprobada

La app fija Godot `4.7.2-stable` en [`get-godot.sh`](../../../app/get-godot.sh), declara Compatibility en [`project.godot`](../../../app/project.godot) y las capturas v3 piden OpenGL 3. El manifiesto actual identifica el adaptador como `llvmpipe (LLVM 20.1.2, 256 bits)`, vendor Mesa; el informe lo clasifica como render de verificación y no benchmark GPU ([manifiesto](../../../research/ugly-stik/model-v3/captures/manifest.json) · [nota v3](../ugly-stik-model-v3.md)). Los documentos de API consultados corresponden a Godot 4.7; no se ejecutó la 4.7.2 en esta investigación.

## Herramientas

Godot 4.7 ofrece `RenderingServer.get_rendering_info()` para objetos, primitivas y llamadas de dibujo; las estadísticas requieren al menos dos fotogramas renderizados y varían con cámara/rotación. Bajo OpenGL, `RenderingServer.get_rendering_device()` devuelve `null`, pero la documentación no impone esa limitación a `get_rendering_info()`. El Visual Profiler informa tiempos CPU/GPU de etapas de render y soporta Compatibility salvo en macOS; sus resultados dependen de resolución. La app objetivo corre en Linux, usa 1280×720 y MSAA 4×, así que esta es la primera opción. [API RenderingServer](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html) · [Debugger y Visual Profiler](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/debugger_panel.html)

RenderDoc captura y permite inspeccionar un fotograma y sus llamadas/recursos. Su matriz oficial lista Linux OpenGL Core 3.2–4.6; Godot Compatibility en escritorio usa OpenGL Core 3.3. RenderDoc 1.46, licencia MIT, encaja por API, pero la matriz no certifica esta combinación concreta con llvmpipe; la captura exacta queda sin confirmar. No usar tiempos de llvmpipe para fijar presupuesto de GPU: las capturas guardadas proceden de un renderizador software. [RenderDoc: API y SO](https://github.com/baldurk/renderdoc) · [versión](https://github.com/baldurk/renderdoc/releases) · [licencia MIT](https://github.com/baldurk/renderdoc/blob/v1.x/LICENSE.md) · [backend OpenGL Godot](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html)

Tracy sirve para trazas de CPU/GPU más profundas, pero Godot pide compilar el motor desde fuente con soporte Tracy. La guía 4.7 fija Tracy 0.13.0 y exige usar la misma versión en cliente/servidor; upstream ya publica 0.14.1 (BSD-3-Clause), por lo que no se debe mezclar sin revisar compatibilidad. [integración Godot 4.7](https://docs.godotengine.org/en/4.7/engine_details/development/profiling/tracy.html) · [releases](https://github.com/wolfpld/tracy/releases) · [licencia](https://github.com/wolfpld/tracy/blob/master/LICENSE)

`MultiMesh` puede reducir miles de instancias a una llamada, pero trata el grupo como un solo objeto para visibilidad: instancias lejanas entre sí pueden seguir dibujándose y la caja AABB queda a cargo del usuario. Godot no prescribe un umbral numérico. Los conteos v3 de 54 mallas y 4.816 triángulos son baseline estático, no draw calls medidos. [API MultiMesh 4.7](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html) · [costes de batching](https://docs.godotengine.org/en/4.7/tutorials/performance/gpu_optimization.html)

## Decisión y verificación pendiente

**Empezar con estadísticas RenderingServer y Visual Profiler en hardware objetivo.** RenderDoc queda como diagnóstico puntual si hace falta inspeccionar un draw; Tracy se aplaza hasta hallar un problema CPU que justifique recompilar Godot. MultiMesh solo se evalúa para grupos repetidos cuando los conteos reales lo ameriten, preservando unidades de culling y soportes articulados. **Comprobación propuesta, no ejecutada:** comparar base y variante con tornillos/bandas agrupados en las mismas vistas montada y de mantenimiento, fijar cámara, resolución, MSAA y hardware, y registrar llamadas, primitivas y distribuciones de tiempo. La compatibilidad de RenderDoc con llvmpipe y los tiempos GPU del equipo objetivo no están confirmados.
