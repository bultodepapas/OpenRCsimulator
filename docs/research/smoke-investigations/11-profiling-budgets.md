# 11 · Medir el coste de humo denso

**Investigado:** 2026-10-05. **Pregunta:** ¿cómo separar coste de lógica, simulación de partículas y transparencias para decidir si hace falta otra herramienta o backend? **Evidencia:** documentación y código/repositorios primarios; no son benchmarks nuevos del simulador.

## Herramientas contrastadas

| Herramienta | Evidencia primaria | Uso recomendado |
| --- | --- | --- |
| Profiler y Visual Profiler de Godot 4.7 | [Panel de depuración](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/debugger_panel.html) | Profiler para scripts; Visual Profiler para render CPU/GPU. Este último no cubre scripts/física y no está disponible en Compatibility/macOS |
| API de tiempos por viewport | [RenderingServer 4.7](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html#class-renderingserver-method-viewport-set-measure-render-time) | Activar medición y registrar tiempos donde el backend los suministre; un cero no acredita coste cero |
| [RenderDoc](https://github.com/baldurk/renderdoc) | Repositorio del autor: MIT, soporte OpenGL core 3.2–4.6 en Linux/Windows | Inspeccionar un frame problemático: draw calls, blend/depth y recursos; herramienta manual opcional |
| [godot-benchmarks](https://github.com/godotengine/godot-benchmarks) | Proyecto oficial MIT; informa medias por frame durante una ventana de ejecución | Referencia metodológica y fixture aislado si hace falta; no reemplaza p95/p99 del vuelo real |

Se resolvió `godot-benchmarks/main` mediante `git ls-remote` a **`b059e38a81230a87293828bbf65ab247b6b2d2a8`** en esta investigación. Se leyó su README; no se ejecutó ni se instaló. RenderDoc se estudió como candidato, sin fijar o instalar una versión: hacerlo cuando un caso requiera su uso y registrar binario/versionado entonces. Godot «Compatibility» no significa el antiguo perfil OpenGL Compatibility que RenderDoc excluye; comprobar la API del contexto real.

## Hallazgo que cambia el presupuesto

Un número pequeño de draw calls no limita la cantidad de fragmentos dibujados. Dos emisores pueden seguir siendo caros si cientos de quads grandes se superponen al atravesar una nube. Además, reducir la tasa de emisión no equivale a reducir la capacidad del sistema. Por eso deben medirse al menos tres escenarios: estela lejana, estela superpuesta consigo misma y cámara dentro del humo.

La cifra previa de «≤ 1.50 ms extra» es una meta propuesta. No hay una medición que demuestre que 1024 partículas la cumplen en la máquina del propietario. Conservar esa honestidad evita elegir plugins o reescribir el render por una supuesta limitación no observada.

## Diseño del ensayo

Reutilizar el logger de [`main.gd`](../../../app/main.gd), ampliándolo únicamente para identificar escenario y estado de humo. Separar dos ejecuciones:

- **Correctitud:** inputs/ticks y render offline reproducibles. Produce imágenes; el tiempo de compresión o guardado no entra en un benchmark del juego.
- **Rendimiento:** vuelo normal en build de release, sin Movie Maker, sin lectura de imágenes GPU→CPU ni instrumentación pesada. Mismo recorrido, resolución, ajustes, cámara y GPU.

Ejecutar tres pares OFF/ON alternando orden para reducir sesgo por calentamiento. Separar primer uso/compilación de shaders de la ventana estable. Propuesta inicial: cinco segundos de calentamiento y treinta de medición, ampliables si el p99 fluctúa. Son decisiones del ensayo, no constantes del motor.

Registrar muestras y p50/p95/p99 de frame; tiempo del controlador; draw calls/primitivas; memoria contabilizada por Godot; GPU ms si está disponible. Si el hardware no permite tiempos GPU, reportar `unavailable` y conservar frame times de pared; no rellenar con cero. No sumar tiempos CPU y GPU como si todo se ejecutara secuencialmente.

**Diagnóstico por cambios controlados:** comparar 512/1024 partículas, dos anchos de sprite y dos resoluciones manteniendo el resto. Si el coste sigue principalmente a resolución/ancho, investigar fill rate/overdraw. Si sigue al número de partículas con quads pequeños, investigar simulación/sorting. Esa correlación orienta el trabajo; no es una prueba definitiva del cuello de botella sin inspección adicional.

Usar RenderDoc en un caso aislado para confirmar por qué hay pases o estados de material inesperados. No usar el tiempo de una captura instrumentada como la aceptación final ni exigir esta herramienta en macOS. Los resultados llvmpipe de CI demuestran render funcional y ayudan a detectar regresiones internas, no rendimiento de una GPU de juego.

## Cambios al plan y pruebas

**SM-07** separa arranque, estado estable y cámara dentro de la nube. A la tabla de presupuestos se añade resolución de prueba 1920×1080 cuando exista ese objetivo de pantalla, además de 720p. Se mantienen dos perfiles candidatos y se elige el menor que conserve continuidad/lectura.

La degradación no cambia vida/capacidad de partículas ya activas cada frame: aplicar calidad al iniciar vuelo o tras un cambio explícito que limpie el efecto. No inflar alpha para ocultar huecos. Una solución de niebla volumétrica o simulación externa solo entra si resuelve un fallo medido y supera la misma comparación.

**No medido:** coste real en iGPU/dGPU, ganancia de ordenación o consumo exacto de VRAM de los perfiles. Esos números siguen pendientes de SM-07.
