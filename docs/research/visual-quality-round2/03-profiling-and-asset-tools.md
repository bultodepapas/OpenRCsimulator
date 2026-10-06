# Perfilado del render y herramientas de assets

2026-10-05 · America/Bogota · **Investigación; no ensayada en el simulador.** No instalé herramientas ni modifiqué `app/`. Versiones/licencias son datos de upstream verificados al investigar; no son pins del proyecto. Este complemento acota el [plan visual](../../VISUAL-QUALITY-PLAN.md) y el [catálogo inicial](../visual-quality-tools-2026-10-05.md). Configuración local: [proyecto Godot](../../../app/project.godot) y [pin del motor](../../../app/get-godot.sh).

## Contexto y recomendación

El proyecto fija Godot **4.7.2-stable** y `gl_compatibility`; resolución final, SO de prueba y PC modesto siguen sin definirse. La RTX 3090 del propietario sirve para caracterizar el extremo alto y probar Forward+, pero no representa PCs modestos. Compatibility usa OpenGL en escritorio; Forward+ usa RenderingDevice y Vulkan, Direct3D 12 o Metal según plataforma/controlador. Compatibility continúa como referencia amplia/web; comparar Forward+ en un gate separado. [Matriz Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) · [requisitos 4.7](https://docs.godotengine.org/en/4.7/about/system_requirements.html).

| Herramienta | Mejor pregunta que responde | Decisión inicial |
| --- | --- | --- |
| Profiler, Visual Profiler y monitores nativos | ¿La lógica, el render CPU/GPU o los objetos/draws/primitivas causan tiempo/spikes? | Adoptar como línea base; disponible en ambos renderers salvo excepción macOS indicada |
| MangoHud | ¿Cómo se distribuyen los frametimes durante una ruta real en Linux? | Probar en Linux si ese es el SO; externo y opcional |
| RenderDoc | ¿Qué recursos, estado y evento generan un draw/píxel incorrecto o caro? | Probar captura puntual en Compatibility y Forward+ |
| NVIDIA Nsight Graphics | ¿Qué carga/pases/shaders limitan la GPU NVIDIA? | Probar en la RTX 3090; no extrapolar al extremo bajo |
| gltfpack / glTF Transform | ¿Un asset estático puede bajar peso, superficies/draws o triángulos sin cambiar su lectura? | Spike offline cuando aparezcan GLB de campo; no tocar el avión sin gate de jerarquía |

## Qué medir: CPU, GPU, draw calls y frame pacing

El profiler de Godot presenta frame time, idle, física y funciones GDScript. Su `Frame Time` engloba el recorrido del frame y renderizado; no es un cronómetro exclusivo de GPU. El profiler tiene coste y está desactivado por defecto. [Profiler 4.7](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/the_profiler.html) · [medición y límites](https://docs.godotengine.org/en/4.7/tutorials/performance/general_optimization.html).

Los monitores `TIME_FPS`, `TIME_PROCESS` y `TIME_PHYSICS_PROCESS` ayudan a orientar. FPS se actualiza una vez por segundo: no descubre bien microtirones. `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` y `RENDER_TOTAL_PRIMITIVES_IN_FRAME` son contadores, no tiempo de GPU. Godot define las primitivas como vértices o índices renderizados; pases de profundidad/sombra pueden contarlas varias veces. Los monitores no incluyen objetos culled; varios tienen demora de hasta un segundo y algunos solo sirven en debug. [API Performance 4.7](https://docs.godotengine.org/en/4.7/classes/class_performance.html).

**No confundir métricas:** draw call es una emisión de dibujo/estado desde CPU/driver; la cantidad de triángulos/índices aproxima trabajo geométrico de GPU. Un MultiMesh puede reducir draws manteniendo casi todos los triángulos; simplificar una malla puede reducir triángulos sin cambiar superficies/materiales ni el número de draws. Overdraw, resolución y shaders pueden limitar la GPU aunque ambas cifras sean bajas. No hay un umbral universal.

El baseline del plan visual registra 101 draw calls y 46.842 primitivas visibles en una captura del avión, con el campo vacío; fue hecho en llvmpipe, no es FPS ni presupuesto de GPU para la RTX 3090. [Plan visual y protocolo](../../VISUAL-QUALITY-PLAN.md).

| Señal | Hipótesis inicial | Confirmación |
| --- | --- | --- |
| Mucho tiempo en funciones/idle de Godot; bajar resolución no cambia el frame | CPU/GDScript, árbol, draw submission o sincronización | Profiler nativo y captura de llamadas; comparar carga de escena controlada |
| Menor resolución mejora claramente frametime/GPU trace | Límite de píxel/ancho de banda/shader en GPU | Nsight; aislar efectos, transparencia y resolución |
| Spike repetible al pasar por el mismo sector | Carga/importación, streaming, composición de escena u otra tarea por frame | Repetir recorrido/cámara y revisar línea temporal; no atribuirlo a triángulos sin evidencia |
| FPS medio correcto pero stutter visible | Pacing irregular, compilación, espera/VSync o spike breve | Serie de frametimes y p95/p99/1% low, no solo promedio de FPS |

## Matriz de compatibilidad y estado

| Candidato | Compatibility: OpenGL 3.x escritorio | Forward+: Vulkan | Pin 4.7.2 / estado |
| --- | --- | --- | --- |
| Godot Profiler / Visual Profiler / Performance | Visual Profiler y contadores compatibles | Visual Profiler y contadores compatibles | Docs consultadas de 4.7; captura del nivel no realizada; Compat Visual Profiler no disponible en macOS |
| MangoHud | El upstream incluye OpenGL | El upstream incluye Vulkan | Solo Linux; no instalado ni probado en este proyecto |
| RenderDoc v1.46 | El upstream cubre GL 3.2–4.6 Core | El upstream cubre Vulkan | Compatibilidad de API declarada; captura de app no probada |
| Nsight Graphics (release 2026.2 consultada) | GPU Trace + OpenGL Frame Debugger; no Shader Profiling | GPU Trace + Shader Profiling/Debugger | RTX 3090 incluida; no probado. macOS/Metal fuera de cobertura declarada |
| gltfpack / glTF Transform | Asset pipeline no depende del renderer | Asset pipeline no depende del renderer | Importar salida/extension de glTF en Godot sigue sin comprobar |

La selección de API debe basarse en el log de ejecución: Godot puede cambiar de driver según SO, hardware y fallback. No suponer que la etiqueta “Forward+” equivale siempre a Vulkan ni que una captura OpenGL en Compatibility predice diferencias de color o rendimiento entre backends. [Fallbacks documentados por Godot](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html#switching-between-renderers).

## Herramientas y ejercicios aplicados

### 1. Godot: Profiler + Performance monitors — adoptar

Para esta versión el panel Profiler es la primera herramienta; `Performance.get_monitor()` también permite registrar contadores en una escena diagnóstica. La API documenta draws, primitivas, memoria de video, `TIME_PROCESS` y física. La lista de Performance no trae tiempo GPU: los contadores de escena tampoco son GPU ms.

**Visual Profiler, dentro del mismo grupo:** Godot separa render CPU y GPU en gráficos por frame. El componente CPU mide tareas de render (p. ej. draw calls), no script ni física; para esas usa el Profiler estándar. Está soportado con los tres métodos de render excepto Compatibility en macOS. La resolución del viewport influye y debe mantenerse fija. [Debugger panel, sección Visual Profiler](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/debugger_panel.html#visual-profiler).

**Ejercicio:** en una escena de prueba con cámara fija, capturar 30 s sin vegetación, luego un anillo de árboles y por último el vuelo normal. Usar el Visual Profiler para comparar costo de render CPU y GPU en la misma resolución; el Profiler estándar ayuda a separar scripts/física. Guardar frame-time/physics, draws, primitivas y memoria. Marcar ruta/estado, preset, resolución, renderer y motor. Repetir en export release para pacing; los profilers del editor añaden coste.

**Compatibilidad:** Godot 4.7 docs y pin app 4.7.2; renderer-agnóstico para contadores. Uso real de estos monitores en el nivel de vuelo: no ensayado en esta investigación.

### 2. MangoHud — probar solo para Linux

El upstream describe un overlay para OpenGL y Vulkan con frametime, lectura de FPS y registros locales; la versión upstream más reciente consultada es **0.8.4**, licencia **MIT**. [README/configuración y logging](https://github.com/flightlessmango/MangoHud) · [releases](https://github.com/flightlessmango/MangoHud/releases) · [licencia](https://github.com/flightlessmango/MangoHud/blob/master/LICENSE).

**Ejercicio:** si la prueba se hace en Linux, registrar en local el mismo vuelo/60–90 s en Compatibility (OpenGL) y Forward+ (Vulkan), con HUD apagado durante capturas visuales. Conservar log crudo y anotar VSync, refresco, driver, resolución y preset; comparar p95/p99 y lows a partir de los frametimes. No subir logs a servicios públicos. El overlay no sustituye al trace de GPU.

**Estado:** el soporte de API está declarado por el proyecto; sistema, instalación, driver y app Godot 4.7.2 no probados. No sirve como solución común si el equipo objetivo usa Windows/macOS.

### 3. RenderDoc — probar capturas puntuales

RenderDoc es un depurador basado en captura/replay de frames; release upstream verificada **v1.46**, licencia **MIT**. La tabla del proyecto declara Windows/Linux para OpenGL **3.2–4.6 Core** y Vulkan. La cobertura coincide en API con Compatibility de escritorio (OpenGL 3.x) y Forward+ cuando corre con Vulkan; no demuestra que la captura ya funcione con esta app/driver. [README y APIs](https://github.com/baldurk/renderdoc/blob/v1.x/README.md) · [release](https://github.com/baldurk/renderdoc/releases) · [guía Vulkan](https://github.com/baldurk/renderdoc/blob/v1.x/docs/behind_scenes/vulkan_support.rst).

**Ejercicio:** capturar un único frame en aproximación baja y otro en cámara de seguimiento. En Event Browser revisar pases y draws de pista/avión; inspeccionar shader, texturas, estado de profundidad y el recurso que pinta un píxel anómalo. Repetir en ambas APIs con el mismo contenido.

**Decisión:** usar para depurar “qué se dibujó y con qué estado”, no para declarar FPS o latencia: captura/replay añade trabajo y puede guardar copias de recursos. Evitar conclusiones de rendimiento en sesiones capturadas.

### 4. NVIDIA Nsight Graphics — probar en RTX 3090

NVIDIA incluye la **GeForce RTX 3090** en la lista vigente, sin la nota que restringe algunos modelos antiguos a Frame Debugging. La release **2026.2** está consultada, pero no fijada al repo. La matriz de actividades distingue las APIs: **GPU Trace** está disponible en OpenGL, Vulkan y D3D12; **Shader Profiling** en Vulkan/D3D12, no OpenGL; **Shader Debugger** solo Vulkan. OpenGL dispone de OpenGL Frame Debugger, pero no de Graphics Capture en la matriz. [Matriz oficial de actividades](https://docs.nvidia.com/nsight-graphics/UserGuide/appendix.html#feature-support-matrix) · [GPU list](https://developer.nvidia.com/nsight-graphics-gpus-full-list) · [release notes 2026.2](https://developer.nvidia.com/nsight-graphics/getting-started/release-note-v2026.2).

**Ejercicio:** en la 3090 recolectar pocos frames de GPU Trace para ambos backends; comparar actividad/pases, primero a la resolución fija y luego bajándola o apagando un efecto. Para Compatibility/OpenGL limitarse a GPU Trace y OpenGL Frame Debugger: la tabla no declara Shader Profiling ni Shader Debugger para GL. Para Forward+/Vulkan se pueden probar GPU Trace, Shader Profiling y Shader Debugger. El Frame Debugger OpenGL indica el subconjunto de operaciones de OpenGL 4.5 core, así que hay que comprobarlo con el contexto de Compatibility usado. No instalar; app 4.7.2 no ensayada.

**Límite:** datos de GPU NVIDIA de alta gama no dimensionan PCs modestos ni CPU frame pacing. Nsight no declara soporte Metal; en macOS Forward+ puede usar Metal, por lo que esta herramienta no cubre esa ruta. Términos de coste/licencia de NVIDIA no verificados aquí.

### 5. gltfpack / glTF Transform (meshoptimizer) — spike offline, no dependencia

`gltfpack` forma parte de meshoptimizer; el README declara licencia **MIT**, versión del ejecutable **1.2** en upstream y optimizaciones de caché/orden, cuantización, merge de mallas y simplificación opcional (`-si`). `-kn` conserva nodos nombrados y las mallas conectadas a ellos para transformación externa; no garantiza que el avión conserve pivotes/articulación funcionales. [README gltfpack](https://github.com/zeux/meshoptimizer/blob/master/gltf/README.md) · [releases](https://github.com/zeux/meshoptimizer/releases) · [licencia](https://github.com/zeux/meshoptimizer/blob/master/LICENSE.md).

Por defecto `gltfpack` puede añadir `KHR_mesh_quantization` y `KHR_texture_transform`; `-noq` desactiva cuantización, pero no garantiza una salida sin extensiones. Inspeccionar el JSON y validar el GLB, incluidas extensiones heredadas del input. `-cc`/`-c`, Basis/KTX2 y WebP piden otras extensiones de compresión. El [manual de Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html) admite glTF/GLB, pero el soporte de cada salida/extensión optimizada no se ha verificado para el pin **4.7.2**. El primer ensayo debe usar input base, `-noq`, sin pedir compresión y comprobar el resultado con [Khronos glTF Validator](https://github.com/KhronosGroup/glTF-Validator) e importación en un scratch project.

**Ejercicio:** cuando exista un prop estático real (cono, mesa o árbol), guardar GLB fuente, ejecutar salida gltfpack con parámetros registrados, importar fuente y salida con Godot 4.7.2 y comparar jerarquía, superficies/materiales, textura checker UV, normals, draw calls, primitivas, tamaño y frame time. Probar `-si` en una copia; descartar si cambia silueta de vuelo/colisión visual o crea costura de UV. El [importador de Godot ya genera LOD con meshoptimizer](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html#automatic-mesh-lod); gltfpack resuelve otro tramo (archivo/contenido de origen).

**Contrato del avión:** por ahora solo props estáticos. No optimizar el generador actual ni el modelo articulado como “batch”. Si un futuro gate evalúa un GLB del avión, exportar y comparar árbol exacto `airplane`, `propeller`, todos los `*_hinge`, paths, transform local/global y posición del pivote; accionar superficies bajo el script existente. `-kn` ayuda a conservar nombres, pero cada resultado requiere prueba. No usar `prune` sobre bisagras. Conserva y revisa atlas UV, tiling, normales y material albedo en Godot.

`glTF Transform` es alternativa JS/Node MIT con CLI/API para `prune`, `dedup`, `meshopt` y transformaciones repetibles; upstream no fija versión aquí y esa ruta no está probada. [README/licencia y comandos](https://github.com/donmccurdy/glTF-Transform). Elegirlo solo si hace falta un pipeline scriptable por lotes; no sumar dos optimizadores. Su modo `meshopt` puede codificar extensión: confirmar compatibilidad del importador antes de producir assets del juego.

## Protocolo de comparación por perfil

1. Congelar escena, ruta de cámara/mandos, clima, tiempo, resolución, VSync, renderer, driver y distancia de dibujado; cada preset Bajo/Equilibrado/Alto reutiliza exactamente los mismos assets y vuelo.
2. Medir en el export nativo, sin RenderDoc/Nsight capturando; hacer tres pasadas tras calentar la escena. Guardar frametimes, p50/p95/p99 o 1% low, y anotaciones de spikes; FPS medio por sí solo no aprueba el gate.
3. En Godot, sumar frame/physics time, draw calls, primitivas y memoria para explicar causas; repetir con Profiler al buscar funciones CPU, aceptando su coste de medición.
4. Abrir RenderDoc para explicar un evento/píxel; usar Nsight solo para aislar si la GPU NVIDIA y qué pase/shader consume trabajo. Después repetir pacing sin el capturador.
5. La 3090 valida el extremo Alto/Ultra; añadir una PC modesta real para calibrar Bajo/Equilibrado. No simular soporte de hardware bajo en 3090 ni prometer FPS antes de conocer objetivo y resolución.
6. Comparar calidad/lectura del avión durante movimiento además de números: hélice, árboles en pasada baja, aliasing en cables/alas, profundidad y textura del terreno.
7. Anotar: SO, CPU/GPU, RAM/VRAM, driver, Godot 4.7.2, backend efectivo, API, resolución/Hz/VSync, preset, configuración y versión/herramienta. Conservar capturas/CSV locales y distinguir “fuente consultada” de “ejercicio ejecutado”.

## Fuentes primarias consultadas

- Godot 4.7: [renderers](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html), [requisitos](https://docs.godotengine.org/en/4.7/about/system_requirements.html), [Profiler](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/the_profiler.html), [Visual Profiler](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/debugger_panel.html#visual-profiler), [Performance monitors](https://docs.godotengine.org/en/4.7/classes/class_performance.html), [optimización](https://docs.godotengine.org/en/4.7/tutorials/performance/general_optimization.html).
- RenderDoc: [APIs/licencia](https://github.com/baldurk/renderdoc/blob/v1.x/README.md), [v1.46](https://github.com/baldurk/renderdoc/releases), [Vulkan capture support](https://github.com/baldurk/renderdoc/blob/v1.x/docs/behind_scenes/vulkan_support.rst).
- NVIDIA: [Nsight Graphics](https://developer.nvidia.com/nsight-graphics), [feature support matrix](https://docs.nvidia.com/nsight-graphics/UserGuide/appendix.html#feature-support-matrix), [release 2026.2](https://developer.nvidia.com/nsight-graphics/getting-started/release-note-v2026.2), [GPU support list](https://developer.nvidia.com/nsight-graphics-gpus-full-list).
- MangoHud: [README, frametime/logging](https://github.com/flightlessmango/MangoHud), [release](https://github.com/flightlessmango/MangoHud/releases), [MIT](https://github.com/flightlessmango/MangoHud/blob/master/LICENSE).
- Assets: [meshoptimizer/gltfpack](https://github.com/zeux/meshoptimizer/blob/master/gltf/README.md), [releases](https://github.com/zeux/meshoptimizer/releases), [glTF Transform](https://github.com/donmccurdy/glTF-Transform).
