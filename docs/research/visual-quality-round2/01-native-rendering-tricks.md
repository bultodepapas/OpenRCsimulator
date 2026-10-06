# Ocho técnicas de Godot para subir calidad sin perder control

2026-10-05 · Investigación web contra documentación oficial **4.7**, lectura del proyecto y [ensayo aislado 4.7.2](godot-probe/README.md). Complementa el [plan visual](../../VISUAL-QUALITY-PLAN.md). Los apartados 1 y 2 tienen evidencia nueva ejecutada; el resto contiene mecanismos documentados y pruebas propuestas. Ninguno está integrado en `app/` por esta entrega.

## 1. Variar el acabado por objeto sin modificar a los demás

**Problema concreto:** [Extra.material()](../../../app/aircraft/extra_300s_model.gd) cachea recursos y el Stik también comparte acabados. Cambiar un recurso compartido para seleccionar, oscurecer o resaltar una pieza puede afectar otros objetos.

Godot ofrece `instance uniform` para valores por GeometryInstance3D; el uniform ordinario pertenece al ShaderMaterial. La documentación actual también explica restricciones de samplers/arrays y el límite práctico de parámetros por instancia. No deducir soporte 4.7 de un tutorial 4.2 que los declare incompatibles con OpenGL. [Lenguaje de shaders 4.7](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html#per-instance-uniforms).

**Probado:** dos quads comparten un ShaderMaterial, conservan rojo/verde, y cambiar el rojo a azul deja el verde intacto. Cambiar el uniform común vuelve ambos amarillos. Cinco capturas del ensayo completo se repitieron; solo este caso valida parámetros vec4 sencillos.

**Aplicación:** tinte o máscara escalar de selección por mesh en VQ-02/EX-10. Compartir recursos inmutables sigue siendo correcto. Una textura de librea por avión necesita su material/atlas, no un supuesto sampler por instancia. Para árboles MultiMesh, estudiar `INSTANCE_CUSTOM` por ejemplar: el parámetro por GeometryInstance3D no identifica cada árbol.

**Decisión:** adoptar el patrón cuando se introduzca un ShaderMaterial que lo necesite; no convertir todos los StandardMaterial3D solo para tenerlo. La ganancia de draw calls no fue medida.

## 2. Vegetación que no desaparece al moverse en el shader

El movimiento de vértices ocurre después de decidir qué objetos están dentro de cámara. Godot permite ajustar `custom_aabb` o ampliar `extra_cull_margin`; `ignore_occlusion_culling` no desactiva el descarte por frustum. [GeometryInstance3D](https://docs.godotengine.org/en/4.7/classes/class_geometryinstance3d.html).

**Probado:** un quad fuera de cuadro se desplaza al centro desde el vertex shader pero no se dibuja. Ajustando únicamente los bounds locales aparece. [Imágenes 04 y 05](godot-probe/README.md). Es la demostración mínima de por qué un arbusto que se inclina al viento podría desaparecer antes de tiempo.

**Aplicación propuesta:** en L11/L15, calcular límites del mesh más la amplitud máxima de viento; en MultiMesh cubrir transformaciones y deformación de todo el sector. Una caja del tamaño de todo el mundo evita el síntoma, pero elimina la utilidad del descarte.

**Prueba de integración pendiente:** cámara barriendo cada borde de un sector, viento mínimo/máximo, distintas orientaciones; registrar continuidad de silueta y coste. También comprobar sombras/reflejos, porque el arnés solo mira color sin iluminación.

## 3. LOD de geometría y de materiales; transición con histéresis

Reducir polígonos conserva el coste del shader por píxel. El HLOD puede sustituir conjuntos distantes por una malla y materiales más simples; la histéresis evita saltar repetidamente de nivel en el umbral. Los rangos se evalúan respecto al centro de AABB y no son el mismo mecanismo que mesh LOD por tamaño en pantalla. [Guía HLOD](https://docs.godotengine.org/en/4.7/tutorials/3d/visibility_ranges.html).

**Limitación relevante:** `VISIBILITY_RANGE_FADE_SELF` y `DEPENDENCIES` solo desvanecen en Forward+; en Compatibility se comportan como salto sin histéresis. Elegir «fade» puede empeorar la transición que se quería arreglar. [Enums de GeometryInstance3D](https://docs.godotengine.org/en/4.7/classes/class_geometryinstance3d.html#enum-geometryinstance3d-visibilityrangefademode).

**Aplicación propuesta:** árboles próximos con normal map; grupos distantes con material sencillo y silueta equivalente. En la cámara fija del piloto, conservar representación estable según su posición. Para cámaras móviles, usar histéresis y comprobar límites de AABB; para avión, considerar además FOV/autozoom y píxeles ocupados.

**Ensayo:** dos niveles de un árbol, ida/vuelta por el umbral y zoom sin traslación; vídeo a 30/60/144 fps y contadores. Mantener coste de normales/reflejos solo donde cambien la lectura. **Decisión:** probar antes que un addon genérico de LOD.

## 4. Preparar shaders durante la carga, según el backend

La guía oficial separa dos rutas: Compatibility debe dibujar materiales/partículas al menos un frame dentro del frustum; Forward+/Mobile tienen mecanismos de precompilación y ubershaders. `preload()` o carga en hilo no equivalen a la primera presentación. El Shader Baker de export no afecta Compatibility y no elimina por sí solo la compilación dependiente del driver. [Compilación de pipelines](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html).

**Aplicación propuesta:** una escena de preparación detrás de la pantalla de carga, con variantes realmente usadas de cabina, humo y suelo. No basta hacerlas invisibles en Compatibility. Instanciar el avión procedural y crear texturas también tiene coste propio: medir esas etapas aparte.

**Ensayo pendiente:** primera entrada al vuelo y primera activación de cada efecto, caché fría/caliente claramente diferenciadas; registrar máximos y p99, no solo media. Cambios de MSAA/backend se aplican con pantalla de ajustes/carga si producen tirones. No borrar cachés globales de drivers automáticamente.

**Decisión:** añadir esta comprobación a VQ-06/07 y UI de carga; evitar una dependencia nueva de «shader warmup» antes de medir el problema. La prueba de colores de esta ronda no mide stutter.

## 5. Humo suave y cristal: revisar qué contiene la imagen de pantalla

En 3D, `hint_screen_texture` captura tras opacos y antes de transparentes. Otro cristal o el humo no necesariamente estará en esa imagen; un efecto de refracción puede producir un resultado incoherente aunque compile. [Shaders que leen pantalla](https://docs.godotengine.org/en/4.7/tutorials/shaders/screen-reading_shaders.html).

La reconstrucción de posición desde profundidad también cambia: Compatibility usa Z de NDC en [−1,1]; Forward+/Mobile, [0,1]. Usar `CURRENT_RENDERER` y la inversa de proyección, siguiendo la guía, en vez de copiar la fórmula Vulkan al shader OpenGL. [Postproceso avanzado](https://docs.godotengine.org/en/4.7/tutorials/shaders/advanced_postprocessing.html).

**Aplicación propuesta:** proximity fade de humo contra el suelo y evaluación de cabina Extra. Empezar con reflejo de entorno y transparencia sencilla; refracción solo si sobrevive a humo detrás/delante, hélice y cielo. Un viewport adicional puede resolver casos concretos, a coste de volver a dibujar una escena.

**Ensayo:** cubo opaco a distancia conocida, cristal delante y partículas cruzándolo; comprobar distancia reconstruida en ambos backends, cámara ortográfica/perspectiva, near/far y MSAA. **Decisión:** mantener como paso del plan SM/VQ-02/07; no añadir «soft particles» por nombre sin probar su intersección real.

## 6. Sombras: concentrar resolución donde aporta

La luz direccional distribuye resolución entre distancia cubierta y cascadas; el atlas no arregla por sí solo sesgos o recortes. `directional_shadow_pancake_size` afecta precisión y puede generar artefactos cerca de límites con geometría grande. [Luces y sombras](https://docs.godotengine.org/en/4.7/tutorials/3d/lights_and_shadows.html), [DirectionalLight3D](https://docs.godotengine.org/en/4.7/classes/class_directionallight3d.html).

**Aplicación propuesta:** conservar horizonte lejano simplificado sin sombras de cada hoja; gastar la resolución en avión y campo próximo. Desactivar emisión de sombra de microdetalle que no sea perceptible. Para el avión, una malla proxy de sombra solo es aceptable si conserva silueta y la articulación necesaria; no asumir que sirve una caja.

**Ensayo:** comparar distancias cubiertas y 2/4 cascadas con mismo atlas; revisar contacto de ruedas, alas finas, alabeo y autozoom, además de tiempo GPU. Ajustar bias con captura rasante para detectar sombras separadas de su objeto. La compensación de color existente en [atmosphere.gd](../../../app/render/atmosphere.gd) sigue siendo un problema independiente.

**Decisión:** priorizar en el ensayo Forward+ de la RTX 3090 y mantener la silueta planar del perfil básico. Valores concretos dependen del campo y del tamaño en pantalla; no se midieron sombras nuevas aquí.

## 7. Occlusion culling solo donde haya oclusores útiles

Godot utiliza oclusores simplificados para evitar dibujar objetos tapados. Mover oclusores complejos puede requerir reconstrucción costosa, y un entorno abierto solo se beneficia si su geometría realmente oculta parte de la escena. [Guía de occlusion culling](https://docs.godotengine.org/en/4.7/tutorials/3d/occlusion_culling.html).

**Aplicación propuesta:** hangar cerrado o colina pueden servir; una copa con huecos no debería convertirse en una pared opaca que oculte aviones incorrectamente. Para el campo abierto actual, frustum + sectores MultiMesh + LOD son un punto de partida más ajustado.

**Ensayo:** dos posiciones, detrás del hangar y mirando cielo/campo; comparar CPU/GPU con oclusión on/off y verificar un avión cruzando un hueco. Medir también cámara de inspección. **Decisión:** posponer oclusores hasta que el escenario los justifique, no activarlos como supuesto aumento gratuito de FPS.

## 8. Filtrar los patrones procedurales, no solo sus bordes geométricos

Godot ofrece `fwidth()` para estimar variación local en pantalla; sus variantes Fine/Coarse no están disponibles en Compatibility. Un patrón procedural de líneas finas puede parpadear aunque la malla tenga MSAA. [Funciones de shader](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shader_functions.html#derivative-functions).

**Propuesta propia, no ensayada:** calcular la distancia firmada al borde de la marca y suavizar su cobertura en una anchura proporcional a `fwidth(distancia)`, en el fragment shader. Aplicar la derivada a coordenadas continuas antes de operaciones discontinuas como `fract`; cuando muchas bandas caben en un píxel, converger al color medio o usar una textura con mipmaps. Suavizar un único borde no integra mágicamente un patrón repetido subpíxel.

**Aplicación:** bandas de siega y bordes de pintura de L9c; para texturas importadas usar el protocolo de [texturas/materiales](02-textures-materials-import.md). Comparar cámara cenital con pasada rasante y pequeños movimientos subpíxel; conservar contraste del borde de pista.

**Decisión:** ensayo pequeño sobre el shader de suelo antes de subir MSAA o introducir TAA para esconder un patrón mal filtrado. La estética de la pista no cambia la fricción ni su contorno físico.

## Qué incorporar al plan

| Paso existente | Nueva condición concreta |
| --- | --- |
| VQ-02 / EX-10 | Parámetros por objeto con aislamiento comprobado; atlas/libreas como recursos separados |
| L11 / L15 | Bounds que incluyan deformación, revisados desde bordes de cámara |
| L6 / L8 | LOD de material y geometría; no confiar en fade HLOD de Compatibility |
| VQ-06 / UI de carga | Medir primera presentación y cambios de opciones, no solo vuelo ya calentado |
| SM / VQ-07 | Ensayo de profundidad y transparencias por backend |
| L9c | Filtrado espacial/temporal de las bandas, conservando referencia de pista |

No se cambió el integrador, las fuerzas ni los modelos. El siguiente paso de campo sigue siendo L5/L6; estas técnicas afinan cómo implementarlo y verificarlo.
