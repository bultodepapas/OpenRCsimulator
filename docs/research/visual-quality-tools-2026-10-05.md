# Herramientas y recursos para la calidad visual

Revisión: **2026-10-05** (fecha de la sesión en America/Bogota), incluyendo el equipo de referencia informado por el propietario.

Este documento complementa el plan de calidad visual de [`docs/VISUAL-QUALITY-PLAN.md`](../VISUAL-QUALITY-PLAN.md). Compara herramientas, addons, bibliotecas de recursos y material de aprendizaje para el simulador Godot. No modifica el proyecto ni prueba addons dentro de `app/`.

## Criterio y contexto comprobado

- La app fija Godot **4.7.2-stable** en [`app/get-godot.sh`](../../app/get-godot.sh) y configura `gl_compatibility` en [`app/project.godot`](../../app/project.godot). El renderer Compatibility es el camino compatible con el objetivo web futuro y el de mayor alcance de hardware según la [guía oficial de renderers Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html).
- La publicación actual apunta a Windows, Linux y macOS; web se mantiene como posibilidad futura en [`STACK.md`](../../STACK.md). La prueba de captura se ejecuta en software GL; eso comprueba render y repetibilidad, pero no da un presupuesto de FPS para la GPU del usuario ([`LEARNINGS.md`](../../LEARNINGS.md)).
- El equipo de referencia disponible es Ryzen 9 5900X, RTX 3090 y 64 GB RAM. No se conoce aún el equipo mínimo ni la resolución final; las cifras de calidad y rendimiento deben salir de mediciones y capturas, no de esta ficha.
- Para niveles Bajo, Equilibrado y Alto, mantener Compatibility y cambiar parámetros de calidad. Forward+ puede ser un experimento Ultra separado: Godot advierte que pasar de Compatibility a Forward+ puede pedir reajustar iluminación, materiales y escena; web solo admite Compatibility ([guía 4.7](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html)).
- En Compatibility 4.7 hay cielo procedural y shaders de cielo, fog, tonemapping, glow, SSAO simplificado desde 4.6, MSAA 3D y postproceso con quad. No hay decals, TAA, FSR2, volumetric fog, SSR ni CompositorEffects ([matriz 4.7](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html), [clase Decal](https://docs.godotengine.org/en/4.7/classes/class_decal.html)). Las marcas de pista deben salir de geometría o textura; el plan de paisaje ya las trata así.
- Los modelos GLB, texturas y datos de campo pueden compartirse entre niveles y perfiles. Las opciones del renderer y los efectos deben quedarse en recursos/perfiles de calidad, sin crear copias de cada asset por preset.
- El repositorio ya tiene investigación y decisiones profundas para cielo, horizonte, terreno, vegetación, texturizado, luces y capturas en [`docs/LANDSCAPE-PLAN.md`](../LANDSCAPE-PLAN.md) y [`docs/research/landscape-investigations/`](landscape-investigations/). Este informe se concentra en escoger y probar herramientas, no en reescribir sus pasos L1–L11.

## Decisión recomendada

| Área | Recomendación | Compatibilidad real para este proyecto | Coste/licencia | Motivo |
| --- | --- | --- | --- | --- |
| Cielo, luz, haze y postproceso | **Adoptar primero Godot nativo** | Confirmado en 4.7 Compatibility por documentación; medir aspecto/coste en capturas de `app/` | Incluido en Godot MIT | No añade dependencia ni contenido por nivel. Sky, fog, glow, SSAO simple y MSAA dan las señales visuales principales. |
| Materiales y texturas | **Probar Material Maker offline; seleccionar recursos CC0** | El export `.tres` de Material Maker debe verse en 4.7.2 Compatibility; los mapas de imagen son reutilizables | Material Maker: MIT salvo archivos marcados; Poly Haven y ambientCG: CC0 | Permite un lenguaje visual común: hierba, tierra, grava, asfalto y hangares sin casarse con un terrain addon. |
| Props y aeronaves en Blender | **Adoptar GLB como salida revisable** | glTF/GLB importado ya tuvo una prueba sintética en 4.7.2 según la investigación local; los assets finales aún requieren captura | Blender es GPL; la obra que se crea con Blender es del autor; GLB no trae coste por formato | Útil para manga de viento, edificios, árboles optimizados y, si el equipo de modelo lo acepta, un asset de avión. Conservar nodos/pivotes del avión. |
| Dispersar vegetación/objetos | **Probar ProtonScatter en escena aparte** | Hay actividad y notas de compatibilidad 4.7 en la investigación del repo; no está integrado ni medido con esta app | Addon MIT; no redistribuir sus texturas de muestra sueltas porque proceden de Textures.com | Sirve para componer cinturones de árboles o postes de forma editable. Generar y guardar instancias; no recalcularlas como parte del vuelo.
| Sistema de terreno editable | **Posponer Terrain3D; conservar como Gate** | Compatibility está soportado por el plugin, pero la versión estable no certifica expresamente Godot 4.7.2; web sigue experimental | MIT, C++ GDExtension | Aporta sculpt, pintura, LOD y foliage; cuesta añadir binarios por plataforma y hay que proteger la coincidencia terreno visual/física.
| Alternativa heightmap | **No adoptar HTerrain aún; evaluar si Terrain3D no encaja** | Su rama actual dice Godot 4.6+, pero la documentación mezcla instrucciones actuales con avisos históricos; Compatibility 4.7.2 no probado | MIT | Implementa terrain en GDScript y tiene sculpt, texturas, LOD y grass. Puede ser alternativa ligera, con incertidumbre de versión/render y muestreo de altura.
| Validación de modelos | **Añadir al flujo solo al entrar GLB real** | Khronos valida el formato, no el aspecto ni la jerarquía que espera el simulador | Apache-2.0 | El Validator detecta GLB malformado y extensiones inválidas antes de importarlo; no reemplaza una captura ni verificación de bisagras.

## Evaluación de herramientas

### Blender y glTF/GLB

Godot recomienda glTF 2.0 y acepta `.glb` y `.gltf`; la importación `.blend` llama al exportador glTF de Blender y exige que Blender esté instalado. GLB permite empaquetar mallas y texturas en un archivo; verificar que el export elegido no conserve referencias externas; usar `.gltf` separado si el control de versiones necesita revisar el JSON o si las texturas se deben editar fuera ([formatos 3D Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)).

La salida práctica es conservar `.blend` como archivo de autoría local y entregar `.glb` explícito. Eso hace revisable el asset de build y evita que CI o cada desarrollador dependa de una instalación de Blender. Blender 3.5+ es la recomendación mínima de Godot para sus correcciones al exporter; verificar la versión concreta si se automatiza el export ([Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html), [manual del exporter Blender 5.0](https://docs.blender.org/manual/en/5.0/addons/import_export/scene_gltf2.html)).

Para superficies articuladas del avión, mantener un árbol estable: raíz, `airplane`, `propeller`, y nodos `*_hinge` con el origen en la bisagra. No activar “Flatten Object Hierarchy” si destruye nodos de control rígidos. El informe local de Blender/glTF explica los ejes y pivotes que deben mantenerse ([auditoría de exportación](ugly-stik-tooling-investigations/05-blender-gltf.md)).

Blender está bajo GPL, pero el titular de Blender aclara que el arte y archivos creados con el programa pertenecen a quien los crea y se pueden usar comercialmente ([licencia oficial Blender](https://www.blender.org/about/license/)). La licencia del programa autor no cambia la licencia de un árbol, textura o modelo descargado: conservar la procedencia individual de cada pieza.

**Recomendación de uso:** crear props de campo modulares y de silueta legible desde la posición del piloto; probar primero un cono de viento o una caseta simple. Para assets del avión, coordinar con el equipo que mantiene [`app/aircraft/`](../../app/aircraft/) y conservar su interfaz antes de cambiar el generador existente.

### Material Maker

[Material Maker 1.7](https://github.com/RodZill4/material-maker/releases/tag/1.7) es la versión publicada que reporta actualización a Godot 4.7. Es una herramienta separada para sintetizar texturas y pintar modelos. Su código declara MIT salvo archivos con licencia explícita distinta ([README](https://github.com/RodZill4/material-maker#license)).

El manual describe exportación de PNGs y un `.tres`, pero todavía llama `SpatialMaterial` al recurso (terminología antigua); esa página por sí sola no acredita un material Godot 4 listo para usar. También indica conversión del formato del mapa normal según destino ([exportador Material Maker](https://rodzill4.github.io/material-maker/doc/export.html)). Es una ruta rápida para construir material tileable de hierba/asfalto/grava y reutilizar el mismo recurso en varios niveles.

El `.tres` generado no se ha importado ni comparado en Compatibility 4.7.2. Revisar escala UV, orientación del normal, roughness y repetición a la altura real de la cámara. Exportar mapas básicos (albedo, normal y roughness) conserva más control que depender de un shader generado con una función exclusiva de otro renderer.

El manual ofrece primeros pasos, editor de nodos, biblioteca, mapas de ruido y exportación específica a Godot ([manual oficial](https://rodzill4.github.io/material-maker/doc/)). Como tutorial de autor, usar “Exporting Materials” y producir una baldosa de grava para comparar junto a la pista; la pregunta de aceptación es si el detalle sigue legible al alejar el avión.

### Poly Haven y ambientCG

[Poly Haven](https://polyhaven.com/license) publica sus HDRI, texturas y modelos bajo CC0: uso comercial y redistribución permitidos, sin crédito obligatorio; el sitio pide no reclamar autoría ni relicenciar el original. Para la simulación, su mejor uso inicial es textura de suelo, HDRI opcional de referencia y props, adaptados a una paleta consistente ([licencia y FAQ](https://docs.polyhaven.com/en/faq)).

[ambientCG](https://docs.ambientcg.com/license/) ofrece mapas PBR, HDRI y modelos bajo CC0; confirma expresamente que los archivos pueden ir crudos dentro de un videojuego y usarse comercialmente. El crédito es opcional ([licencia oficial](https://docs.ambientcg.com/license/)).

Ambas bibliotecas son **adoptables** para prototipos sin coste de licencia de asset. Guardar por recurso: ID y URL directa, autor/fuente, licencia, fecha, resolución descargada y SHA-256. CC0 elimina atribución obligatoria, pero esa ficha permite volver a encontrar el original y detectar errores de importación. El plan de paisaje ya establece procedencia por archivo ([L9 y regla de assets](../LANDSCAPE-PLAN.md)).

Empezar con 1K o 2K por textura y subir solo donde se vea una mejora en captura. No cargar un HDRI enorme como solución automática: Compatibility dibuja en LDR RGBA8 y una textura HDR puede ocupar mucha VRAM; el sky procedural existente ya resuelve el horizonte y reduce peso de descarga ([características renderer](https://docs.godotengine.org/en/4.7/about/list_of_features.html), [baseline del paisaje](landscape-research.md)).

### Kenney y Quaternius

El [Car Kit de Kenney](https://kenney.nl/assets/car-kit) declara CC0 y ofrece vehículos sencillos para dar escala al aparcamiento. [Ultimate Nature Pack de Quaternius](https://quaternius.com/packs/ultimatenature.html) declara CC0 y formatos FBX, OBJ y Blend: exportar una selección pequeña a GLB si se adopta, sin asumir que ya incluye ese formato. Son candidatos para L10/L11, no assets descargados o probados en esta ronda. Mantener una paleta común y revisar silueta, tamaño, normales y coste antes de poblar el campo. La licencia verificada corresponde a esos packs concretos, no a todo producto presente o futuro de sus autores.

### ProtonScatter

El repositorio de [ProtonScatter](https://github.com/HungryProton/scatter) es un addon Godot 4 MIT que compone reglas no destructivas con modificadores, áreas y escenas; su documentación vive dentro del Inspector. El README limita el ejemplo de release 4.0 a Godot 4.0–4.2 en el momento de escribirlo, mientras la actividad más reciente del repo y la investigación local registran actualización/fix posterior para 4.7. Esa evidencia de upstream no sustituye una prueba con el pin de esta app ([releases](https://github.com/HungryProton/scatter/releases), [registro local del paisaje](landscape-investigations/05-grass-rendering.md)).

El código actual contempla MultiMesh, copias o partículas, chunks y caché. Para Compatibility probar solo instancing/MultiMesh, semilla fija, salida guardada y áreas por sector; evitar que miles de nodos editables se queden visibles en el árbol. La guía de MultiMesh de Godot advierte que no hay culling por instancia individual, por eso conviene dividir en chunks ([fuente del addon](https://github.com/HungryProton/scatter/blob/main/addons/proton_scatter/src/scatter.gd), [guía MultiMesh 4.7](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html)).

Usar un scratch project con una pista, un anillo de árboles y una mezcla de arbustos; exportar, abrir y capturar bajo Compatibility en Win/Linux/macOS antes de aprobarlo. Guardar semilla y salida generada; medir carga inicial, draws, memoria y estabilidad del editor. Desactivar las actualizaciones en juego. No incluir por separado las texturas de `demo/`: el README señala restricciones de Textures.com.

### Terrain3D

[Terrain3D 1.0.2](https://github.com/TokisanGames/Terrain3D/releases/tag/v1.0.2-stable) es MIT y C++ GDExtension. Su release atiende Godot 4.6 y declara Compatibility corregido; el README dice 4.4–4.6+. La nota del release candidate anterior indica explícitamente que el autor no sabía si funcionaría con Godot 4.7. La documentación llama Compatibility totalmente soportado con Godot 4.4, y web experimental ([release](https://github.com/TokisanGames/Terrain3D/releases), [matriz de plataformas/renderers](https://terrain3d.readthedocs.io/en/stable/docs/platforms.html)). **Resultado para este proyecto:** el renderer coincide, pero no hay certificación primaria clara de 4.7.2 ni prueba en `app/`; clasificar como pendiente de spike.

Resuelve sculpt, heightmaps, hasta 32 sets de textura, LOD y foliage instancing; el sistema usa regiones y mesh clipmaps ([API Terrain3D](https://terrain3d.readthedocs.io/en/stable/api/class_terrain3d.html)). Sirve si el arte de futuros campos requiere edición manual grande, no para reemplazar ya la pista de vuelo actual.

El gate importante es física: `get_height(global_position: Vector3)` devuelve un `float`: interpola alturas de 4 vértices y devuelve `NAN` en huecos o fuera de las regiones; el render además usa LOD y geomorphing. Esto no demuestra igualdad con el muestreador float64 triangular del simulador ([API de datos](https://terrain3d.readthedocs.io/en/stable/api/class_terrain3ddata.html), [revisión de física/terreno del proyecto](landscape-research.md)). Mantener la malla exacta de colisión/simulación generada desde los datos canónicos aunque Terrain3D se use solo para lo visual, o aplazar su adopción.

Las librerías nativas y las exportaciones web requieren pruebas por plataforma. El mantenedor marca web como muy experimental y menciona dependencias del backend/hardware WebGL; macOS puede bloquear binarios no firmados ([matriz oficial](https://terrain3d.readthedocs.io/en/stable/docs/platforms.html)). Aplazarlo mientras el terreno DIY por chunks satisfaga detalle y tamaño del campo ([Gate L18](../LANDSCAPE-PLAN.md)).

### HTerrain / Zylann Heightmap Plugin

El repositorio actual se declara heightmap terrain para Godot 4.1 y la documentación de `master` ahora pide Godot 4.6 o posterior; changelog visible presenta 1.8 en desarrollo. El autor describe el addon como MIT ([README](https://github.com/Zylann/godot_heightmap_plugin), [changelog](https://github.com/Zylann/godot_heightmap_plugin/blob/master/CHANGELOG.md), [nota del autor](https://github.com/sponsors/Zylann)).

Incluye sculpt, texture sets/splatmaps, LOD, agujeros, colisión, generación procedural y detail grass. La página de documentación dice que se apoya en VisualServer y espera que funcione sobre GLES3, pero contiene también un mensaje de troubleshooting histórico que dice que Godot 4 no está soportado. Sus videos enlazados son de 2020–2021; por tanto hay que seguir el texto reciente y probar la versión actual en 4.7.2 ([docs del autor](https://github.com/Zylann/godot_heightmap_plugin/blob/master/addons/zylann.hterrain/doc/docs/index.md)).

La aceleración nativa es opcional y la misma doc todavía habla de GDNative con binarios precompilados solo para Windows/Linux; eso requiere comprobar si aplica a la versión de desarrollo actual antes de usarla en tres plataformas ([sección nativa](https://github.com/Zylann/godot_heightmap_plugin/blob/master/addons/zylann.hterrain/doc/docs/index.md)). Evaluar solo como alternativa de taller para esculpir/exportar heightmap, no introducirlo como dependencia de cada nivel hasta que resuelva renderer, altura física y export.

### Khronos glTF Validator

[glTF Validator](https://github.com/KhronosGroup/glTF-Validator) es la herramienta oficial del grupo Khronos para validar glTF 2.0: formato JSON/GLB, buffers, referencias, imágenes, animaciones y extensiones; la CLI genera un reporte JSON y falla con errores. El repo distribuye la herramienta bajo Apache-2.0 ([README y licencia](https://github.com/KhronosGroup/glTF-Validator)).

Usarlo cuando llegue el primer `.glb` real. Después importar con el Godot fijado, revisar el árbol/pivotes y hacer captura de Compatibility; superar el validador no prueba el sombreado, el tamaño en pantalla ni la articulación. El repo ya documenta por qué no optimizar/flatten/meshopt sin probar cada salida ([auditoría glTF local](ugly-stik-tooling-investigations/06-gltf-validation.md)).

## Guías y tutoriales, con un ejercicio útil para el simulador

| Recurso primario | Qué enseña | Ejercicio aplicado | Límite que revisar |
| --- | --- | --- | --- |
| [Godot 4.7 — Environment and post-processing](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html) | WorldEnvironment, cielo, ambiente, tonemapping, fog, glow y ajustes | Crear variante de cielo de día con gradiente, nube/haze y color coherente en el horizonte; comparar vuelo pilotado e inspección | Compatibility usa implementación simplificada de glow/SSAO; decidir con captura, no solo viewport del editor. |
| [Godot 4.7 — Sky shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/sky_shader.html) | Shader de fondo y mapa de radiancia | Reforzar el horizonte y orientación con gradiente suave; mantener una sola fuente para cielo y color de niebla | Evitar `TIME` si no hace falta: el manual dice que puede forzar actualización de radiancia cada frame. Considerar LDR y banding de Compatibility. |
| [Godot 4.7 — MultiMeshes](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html) | Instanciar muchos meshes con pocas operaciones de dibujo | Prueba de cinturón de árboles dividido en chunks y 2–3 especies con densidad reducida por preset | Sin culling por ejemplar: chunkear y medir geometría visible, no perseguir conteo de instancias aislado. |
| [Blender glTF 2.0 manual](https://docs.blender.org/manual/en/5.0/addons/import_export/scene_gltf2.html) + [formatos Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html) | Jerarquía, GLB, UV, materiales y exportación de la escena | Modelar manga de viento y caseta con un pivote animable; exportar GLB, pasar Khronos Validator e importar en el proyecto | Usar GLB explícito y conservar jerarquía/nombres requeridos; render Blender puede diferir del renderer Compatibility. |
| [Material Maker: manual](https://rodzill4.github.io/material-maker/doc/) + [exportación para Godot](https://rodzill4.github.io/material-maker/doc/export.html) | Grafo de texturas, mapas PBR y exportación `.tres` | Hacer material repetible de tierra o asfalto con normal y roughness; comprobar mosaico desde cámara alta y baja | El `.tres` se debe validar en Godot 4.7.2; comenzar con mapas simples y pocas texturas. |
| [ProtonScatter README](https://github.com/HungryProton/scatter#readme) + documentación dentro del nodo `ProtonScatter` | Áreas, modificadores, seeds, salida de instancing y caché | Pintar una franja forestal detrás del campo; guardar salida y luego capturar la misma semilla | Tutorial/documentación del addon no certifica por sí sola la build desktop/web del simulador; probar export y renderer. |

La documentación oficial de Terrain3D incluye [videos del autor para instalación, texturas, pintura, autoshader e instancing](https://terrain3d.readthedocs.io/en/stable/docs/tutorial_videos.html). El propio autor advierte que parte de las instrucciones de esos videos quedó desactualizada. Ver el video 1 para comprender el flujo, pero seguir la página 1.0.2 para almacenamiento e instalación; usar ese estudio solo en el spike del gate.

## Protocolo de prueba y criterios de adopción

Mantener la prueba como una escena/proyecto temporal hasta que el addon demuestre valor. La norma del repo pide que todo script dentro de `app/` compile; no copiar prototipos incompletos ahí ([AGENTS.md](../../AGENTS.md)).

1. **Hacer primero el recorrido nativo:** capturar el nivel vacío en la cámara de piloto, una maniobra a media altura y una toma de campo a baja altura. El plan visual principal decide el orden de trabajo y evita repetir los gates de horizonte, terreno y materiales.
2. **Crear una biblioteca compartida pequeña:** material base de hierba, tierra, grava/asfalto, sky/HDRI opcional, árboles y 3–5 props. Guardar recursos reusables y su manifiesto CC0; mantener nombres y pivotes de los GLB.
3. **Comparar perfiles en la misma captura:** Bajo/Equilibrado/Alto dentro de Compatibility; anotar hardware, sistema, versión de Godot, resolución, MSAA, sombras, SSAO, cantidad de vegetación, draws/primitives, memoria observada y tiempo de carga. Sin resolución final, usar 1280×720 como captura de referencia del proyecto, no como promesa de entrega.
4. **Usar hardware conocido correctamente:** la RTX 3090 sirve para probar el límite alto y una configuración Forward+ Ultra. No permite estimar el rendimiento de PCs modestos. Aceptar niveles de FPS y densidad de escena después de una medición en hardware bajo objetivo; llvmpipe solo certifica captura y errores visuales.
5. **Gate de addon de terreno:** importar y esculpir una isla/campo pequeño; exportar Win/Linux/macOS; comprobar logs del engine, tamaño de build, tiempo de carga y captura en Compatibility. Comparar cada sample de altura física contra los triángulos dibujados y todos los puntos volables; descartar si la malla sim no coincide.
6. **Gate de ProtonScatter:** fijar versión/commit y semilla en el propio spike; generar y guardar instancias; medir regeneración, rendimiento de editor y export; reabrir en otro SO/limpieza de `.godot` para comprobar assets/caché. No agregarlo como dependencia de producción si niveles reproducibles pueden almacenarse como escenas/MultiMesh nativo.
7. **Gate de Forward+:** abrir una copia del proyecto con el renderer experimental, reutilizar los mismos assets y capturas y registrar diferencias de iluminación, colores, niebla, AA, tiempos y errores. Mantener la experiencia Compatibility equivalente mientras no haya hardware mínimo decidido.

Regla de decisión: adoptar una herramienta cuando mejore una evidencia visible del vuelo, sus salidas sigan compartibles entre niveles/perfiles y pase el gate de plataformas objetivo. Si solo acelera la autoría de arte, preferir herramienta offline con salida plana (`GLB`, PNG, EXR) a dependencia runtime.

## Fuentes primarias consultadas

- [Godot 4.7 — renderers](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html), [Environment](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html), [Sky shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/sky_shader.html), [MultiMeshes](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html), [formatos 3D](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html).
- [Terrain3D releases](https://github.com/TokisanGames/Terrain3D/releases), [plataformas/renderers](https://terrain3d.readthedocs.io/en/stable/docs/platforms.html), [API de terreno](https://terrain3d.readthedocs.io/en/stable/api/class_terrain3ddata.html), [texturas](https://terrain3d.readthedocs.io/en/stable/docs/texture_prep.html), [tutorial videos](https://terrain3d.readthedocs.io/en/stable/docs/tutorial_videos.html).
- [ProtonScatter README](https://github.com/HungryProton/scatter), [releases](https://github.com/HungryProton/scatter/releases), [script del nodo](https://github.com/HungryProton/scatter/blob/main/addons/proton_scatter/src/scatter.gd).
- [HTerrain README](https://github.com/Zylann/godot_heightmap_plugin), [changelog](https://github.com/Zylann/godot_heightmap_plugin/blob/master/CHANGELOG.md), [manual](https://github.com/Zylann/godot_heightmap_plugin/blob/master/addons/zylann.hterrain/doc/docs/index.md).
- [Material Maker 1.7 release](https://github.com/RodZill4/material-maker/releases/tag/1.7), [README/licencia](https://github.com/RodZill4/material-maker#license), [manual](https://rodzill4.github.io/material-maker/doc/), [exportación Godot](https://rodzill4.github.io/material-maker/doc/export.html).
- [Poly Haven license](https://polyhaven.com/license), [Poly Haven FAQ](https://docs.polyhaven.com/en/faq), [ambientCG license](https://docs.ambientcg.com/license/).
- [Blender license](https://www.blender.org/about/license/), [Blender 5.0 glTF manual](https://docs.blender.org/manual/en/5.0/addons/import_export/scene_gltf2.html), [Khronos glTF Validator](https://github.com/KhronosGroup/glTF-Validator).
- Evidencia y decisiones existentes: [`LANDSCAPE-PLAN.md`](../LANDSCAPE-PLAN.md), [`landscape-research.md`](landscape-research.md), [`05-grass-rendering.md`](landscape-investigations/05-grass-rendering.md), [`05-blender-gltf.md`](ugly-stik-tooling-investigations/05-blender-gltf.md), [`06-gltf-validation.md`](ugly-stik-tooling-investigations/06-gltf-validation.md).
