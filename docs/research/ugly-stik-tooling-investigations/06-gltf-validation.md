# 06 · Validación glTF y límites de optimización

2026-10-05 · Investigación documental; sin instalar herramientas ni transformar assets. Aplica solo si US-V incorpora GLB.

## Pregunta y estado local

¿Qué cubre un validador y qué riesgos agregan las transformaciones automáticas al avión? La ruta activa sigue siendo malla nativa de Godot; el roundtrip sintético previo cubrió importación, nombres, escala, probes y una bisagra, por lo que no se debe presentar otra inspección estática como nueva evidencia. [Constructor actual](../../../app/aircraft/ugly_stik_model.gd) · [prueba GLB anterior](../ugly-stik-investigations/09-export.md).

## Evidencia y límites

El [Khronos glTF Validator](https://github.com/KhronosGroup/glTF-Validator) compara con la especificación glTF 2.0 y revisa sintaxis JSON, estructura GLB, referencias internas, buffers/accessors, valores inválidos, animación, imágenes y extensiones conocidas. La CLI `gltf_validator model.glb` escribe un informe JSON y retorna código no cero ante errores; valida también recursos referenciados por defecto. Su licencia Apache-2.0 es permisiva y la herramienta puede mantenerse fuera del runtime. **Límite:** pasar la especificación no prueba que Godot interprete igual el modelo, que las cruces se vean bien ni que el elevador rote desde la bisagra correcta; estas son inferencias de alcance que requieren importar y observar en la aplicación, aparte. [README, uso, comprobaciones y licencia](https://github.com/KhronosGroup/glTF-Validator).

glTF Transform aporta una CLI de inspección (`gltf-transform inspect model.glb`) y transformaciones separadas. `prune` elimina propiedades no referenciadas; `flatten` aplana el grafo; `join` une mallas y busca reducir draw calls. Meshopt codifica geometría, morph targets y animación mediante `EXT_meshopt_compression`, y su función combina reordenamiento, cuantización y extensión de compresión. Estas son operaciones distintas: una inspección no modifica el archivo, pero una optimización compuesta sí puede cambiar atributos o estructura, así que hay que evaluar cada salida en copia. glTF Transform usa MIT; meshoptimizer también es MIT. [CLI y comandos](https://gltf-transform.dev/cli) · [join](https://gltf-transform.dev/modules/functions/functions/join) · [meshopt](https://gltf-transform.dev/modules/functions/functions/meshopt) · [licencias meshoptimizer](https://github.com/zeux/meshoptimizer).

En Godot 4.7.2, el registro de extensiones glTF integrado no incluye `EXT_meshopt_compression`; una extensión requerida desconocida se rechaza salvo que un complemento la registre. No hay complemento glTF en `app/`. Por tanto, incluso una salida estructuralmente válida podría no importarse en este proyecto. [Lista soportada en código Godot 4.7.2](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/gltf/gltf_document.cpp#L6619-L6647) · [manejo de extensiones requeridas](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/gltf/gltf_document.cpp#L7013-L7020).

## Decisión y fixture

**Aplazar glTF Transform y meshopt.** Si se acepta un asset Blender, ejecutar el Validator sobre GLB plano antes de Godot; fijar versiones y licencia al incorporar una herramienta. No lanzar optimización por defecto ni fusionar nodos nombrados que sostienen bisagras.

Prueba mínima futura: conservar e inspeccionar el GLB sintético original con `inspect`; generar copias separadas con `prune`, `flatten`, `join` y meshopt. Para cada salida, pasar el validador y el importador de Godot, comparar nombres, aristas del árbol, TRS, AABB, posición del pivote, normales y giro de elevador; anotar tamaños antes/después. El informe Validator solo acredita reglas que implementa; capturas en Compatibility y prueba dinámica siguen siendo el control visual y funcional. No se ejecutó ninguna de estas transformaciones en esta investigación.
