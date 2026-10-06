# Segunda ronda: técnicas, materiales y herramientas de diagnóstico

2026-10-05 · America/Bogota. Investigación solicitada como continuación del [catálogo inicial](../visual-quality-tools-2026-10-05.md) y del [plan visual](../../VISUAL-QUALITY-PLAN.md). Objetivo: mejorar calidad desde equipos modestos hasta la RTX 3090 del propietario, con Godot 4.7.2 y Compatibility como base comprobada.

Se consultaron fuentes primarias de Godot y de los autores de herramientas; cada capítulo distingue documentación, lectura del repo, inferencias y pruebas propuestas. **Solo el ensayo enlazado abajo se ejecutó en esta ronda.** Los addons y herramientas externas no se instalaron ni se probaron en la aplicación.

| Investigación | Qué añade a la primera ronda | Evidencia |
| --- | --- | --- |
| [01 · Ocho técnicas nativas](01-native-rendering-tricks.md) | Parámetros por objeto; bounds de mallas deformadas; LOD de materiales y límites del fade; primera compilación; profundidad/transparencia; sombras; oclusión; filtrado procedural | Fuentes oficiales y dos comportamientos ensayados |
| [02 · Texturas e importación](02-textures-materials-import.md) | UV/tangentes antes del normal map, espacio de color, márgenes de atlas, roughness importado y compresión de memoria | Documentación/código; ensayos A/B propuestos |
| [03 · Diagnóstico y herramientas de assets](03-profiling-and-asset-tools.md) | Profiler, RenderDoc, Nsight y optimizadores GLB: qué mide cada uno y qué puede romper | Fuentes de los autores; sin instalación/benchmark |
| [Ensayo Godot reproducible](godot-probe/README.md) | Colores distintos sobre un material compartido y descarte/recuperación de geometría movida por shader | Dos ejecuciones, 5 estados, 8 comprobaciones de píxel por ejecución, 5 PNG idénticos |

## Recomendaciones que cambian el trabajo práctico

1. **Separar carga, primera presentación y vuelo calentado.** Un promedio de FPS durante el vuelo no descubre un tirón al activar por primera vez el humo o cambiar un preset. Compatibility necesita un protocolo distinto al de precompilación Forward+.
2. **Preparar la malla antes de mejorar sus materiales.** Verificar UV y tangentes antes de añadir normal maps; examinar los mipmaps del atlas antes de resolver defectos subiendo la resolución.
3. **Variar lo justo por objeto.** El ensayo confirma `instance uniform` para color por MeshInstance3D en el pin actual. La textura de librea, el árbol de bisagras y los ejemplares de MultiMesh requieren sus propias decisiones.
4. **Diseñar también el nivel de detalle del shader.** Una malla reducida puede seguir teniendo un material caro. El fade HLOD de Forward+ no debe trasladarse como si funcionara igual en Compatibility.
5. **Medir con una herramienta que soporte la API real.** Usar la RTX 3090 para ensayos altos, identificar backend/driver y seleccionar profiler por actividad. No interpretar una captura de frame como garantía de frame pacing.

## Qué está comprobado y qué sigue abierto

- Se vio el aislamiento de dos tintes con ShaderMaterial compartido. Modificar el uniform ordinario compartido cambió ambos objetos, como control del ensayo.
- Se reprodujo el descarte de una malla desplazada por shader y se recuperó ajustando solo su AABB. El tamaño exagerado del desplazamiento separa el caso correcto del incorrecto; no es una receta para los árboles.
- Las capturas del fixture son llvmpipe, 640 × 360. Acreditan comportamiento y repetibilidad en ese entorno, no velocidad en GPU real ni mejora visual de los aviones.
- Atlas con margen, normales, compresión, sombreado, primera compilación, profilers externos y herramientas GLB quedan pendientes de sus ensayos. No se atribuyen resultados de la ronda anterior a esta.

## Ensayos siguientes, por utilidad

| Prioridad propuesta | Caso acotado | Paso que informa |
| --- | --- | --- |
| 1 | Un acabado del avión y un suelo con mapa normal, UV/tangentes y lectura en movimiento | VQ-02 / EX-10 / L9 |
| 2 | Un árbol cercano y su versión lejana, con material simple y bounds que incluyan viento | L6 / L8 / L11 / L15 |
| 3 | Primera entrada al campo y primera aparición de humo, con caché fría/caliente documentadas | VQ-06 / UI / SM |
| 4 | Misma pasada en Compatibility y Forward+ sobre la 3090, sin cambiar assets | VQ-07 / Gate L |

Prioridades de diseño, no benchmark ni calendario comprometido. L5/L6 siguen siendo la primera entrega de paisaje del plan; estos ensayos preparan decisiones y evitan copiar configuraciones de tutoriales de otro backend.
