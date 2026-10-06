# Texturas, materiales e importación en Godot 4.7

**Investigación nueva · 2026-10-05 · America/Bogota.** Revisión documental y de código; no se editó `app/`, no se importaron assets y no se
hicieron benchmarks.

Esta ronda concreta la parte de materiales del [plan visual](../../VISUAL-QUALITY-PLAN.md) y evita repetir el catálogo general de herramientas de
la [ronda anterior](../visual-quality-tools-2026-10-05.md). El proyecto fija Godot 4.7.2 y Compatibility. El código consultado está etiquetado
[`4.7.2-stable`](https://github.com/godotengine/godot/commit/ed1daf0bf), commit de versión `ed1daf0bf`; las conclusiones describen esa versión, no la rama `master`.

## 1. Color sRGB para albedo; valores lineales para mapas de datos

Godot ilumina en espacio lineal. En un `sampler2D` personalizado, la marca `source_color` identifica una textura de color sRGB y permite su
conversión correcta al muestrear. Albedo/color suele usarla; normal, roughness, metallic y height normalmente no. En Compatibility es opcional,
pero la guía la recomienda para mantener el shader correcto al cambiar de renderer; Forward+ y Mobile la requieren. Esta marca pertenece al
shader, no a la importación del archivo.

**Aplicación local.** [`ground.gdshader`](../../../app/render/ground.gdshader#L8) ya declara el césped como `source_color` y lo lleva a `ALBEDO`.
El Stik usa `StandardMaterial3D.albedo_texture` para su librea en [`ugly_stik_finish.gd`](../../../app/aircraft/ugly_stik_finish.gd#L59); sus
acabados todavía definen color, metalicidad y roughness mediante valores, no mapas de datos.

**Ensayo propuesto.** En un proyecto temporal 4.7.2/Compatibility, muestrear una carta con parches sRGB conocidos como color con `source_color`,
y una carta gris/normal como datos sin esa marca. Mantener luz y exposición fijas; comparar la captura con valores esperados y repetir al migrar
cualquier shader a otro renderer.

**Decisión: adoptar la convención para shaders nuevos; probar en un scratch project antes de introducir mapas.** El césped actual ya sigue la
convención. No se hizo captura en esta ronda.

Fuentes: [Shading language 4.7:
`source_color`](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html#using-source-color),
[StandardMaterial3D y canales PBR](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html).

## 2. Mipmaps, atlas UV y fuga entre regiones

Godot recomienda mipmaps para 3D: suavizan el detalle distante, pueden reducir coste de muestreo/ancho de banda y aumentan el uso de memoria
aproximadamente 33%. Los mipmaps reducen la imagen por niveles y combinan texels vecinos. La documentación 4.7 consultada y el importador 4.7.2
no muestran *Preserve Alpha Test Coverage*; no se debe diseñar el foliage del repo contando con esa opción sin verificarla en el pin. Para
recortes alfa, evaluar offline silueta y cobertura en los mip levels disponibles.

**Aplicación local.** [`ground.gd`](../../../app/render/ground.gd#L11) genera una baldosa periódica de 256 px con mipmaps; el shader usa filtrado
lineal anisotrópico y repetición. [`ugly_stik_finish.gd`](../../../app/aircraft/ugly_stik_finish.gd#L42) rasteriza la librea SVG de 1024 px,
genera mipmaps y la aplica al modelo con filtrado anisotrópico. Sus regiones UV se calculan en el mismo archivo. La librea es mayormente opaca;
el asunto de cobertura alfa solo aplicaría a futuras texturas recortadas de árboles.

**Inferencia para este atlas:** al filtrar una región UV cerca de su borde, la huella de muestreo puede incluir colores de otra región; los
mipmaps amplían el vecindario que se combina al bajar resolución. Extender el color de cada isla hacia un margen (*dilation/gutter*) y separar
sus UV del borde son medidas a probar. Las páginas oficiales consultadas no dan un ancho de margen universal para este atlas 3D; no fijo un
número como regla.

**Ensayo propuesto.** Capturar el mismo avión en inspección y vuelo a varias distancias, priorizando los bordes de ala, deriva y fuselaje donde
cambia el color. Comparar el atlas actual con una copia temporal que dilate colores en los márgenes y ajuste UV; revisar la pasada en vídeo y los
mip levels lejanos. Para un futuro árbol alfa, probar la lectura de la silueta a distancia sin presuponer una función de preservación de
cobertura del importador.

**Decisión: probar márgenes de atlas en una variante; conservar mipmaps en los assets 3D.** No hay evidencia de fuga confirmada en la librea
actual, y la prueba aún no se ejecutó.

Fuentes: [importación de imágenes 4.7: mipmaps y
filtrado](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html#mipmaps-generate), [rutina local de la
librea](../../../app/aircraft/ugly_stik_finish.gd), [atlas de referencia](../../../app/aircraft/ugly_stik_appearance.gd).

## 3. Roughness limiter durante importación

El importador puede generar niveles de roughness guiándose por un mapa normal asociado: se elige el canal que contiene roughness (a menudo verde)
y la ruta de su normal en las opciones de importación. El filtrado aumenta rugosidad en zonas con detalle normal de alta frecuencia, para reducir
algo el aliasing especular. Se calcula al importar y la documentación declara que no tiene coste de renderizado; su efecto es limitado y no
arregla aliasing de bordes geométricos.

El limitador **en espacio de pantalla** es otro mecanismo: la guía 4.7 lo restringe a Forward+ y Mobile, no Compatibility. No conviene atribuirlo
a la configuración actual. El procesamiento de mapas durante la importación sí se describe por separado, mediante `roughness/mode` y
`roughness/src_normal`; el código 4.7.2 genera mipmaps de roughness desde la normal asociada.

**Aplicación local.** [`ugly_stik_finish.gd`](../../../app/aircraft/ugly_stik_finish.gd#L14) define roughness numérica por acabado; no hay par de
texturas roughness/normal al que aplicar esta operación. Podría interesar más adelante para pintura/film, asfalto o caucho con detalle de
superficie.

**Ensayo propuesto.** En una escena temporal, crear un par roughness + normal con detalle fino y especular visible; comparar el mapa original con
la variante importada bajo la misma luz y durante una pasada. Verificar el detalle cercano, aliasing a distancia y la lectura de la pintura. No
mezclar el resultado con la prueba de MSAA.

**Decisión: posponer en los materiales actuales; probar si VQ-02 adopta mapas PBR separados.** La mejora visual no se ha evaluado aquí.

Fuentes: [import options 4.7: Roughness](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html#roughness-mode),
[antialiasing 4.7: roughness importado y
Compatibility](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html#texture-roughness-limiter-on-import), [código Godot 4.7.2:
generación de mipmaps roughness](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/import/resource_importer_texture.cpp#L2807-L2811).

## 4. Normal maps en mallas creadas con SurfaceTool

Las normales de vértice no sustituyen a las tangentes. La documentación advierte que una superficie generada sin tangentes no muestra
correctamente el normal mapping; `generate_tangents()` requiere UV y normales definidos previamente. El orden práctico es completar
geometría/UV/normales, generar tangentes y después hacer `commit()`.

**Aplicación local.** [`ugly_stik_model.gd`](../../../app/aircraft/ugly_stik_model.gd#L23) asigna normales al crear triángulos y asigna UV solo
cuando la cara lleva una región de textura; las rutinas hacen `commit()` sin generar tangentes. Es válido para los materiales existentes, que
usan colores y albedo. Si se agrega normal map, habrá que asegurar UV en cada superficie objetivo, generar tangentes y revisar costuras antes de
juzgar el material.

**Ensayo propuesto.** En una copia temporal de una superficie curva y una plana, aplicar un normal map conocido. Comparar mesh con y sin
`generate_tangents()` tras fijar UV y normales; inspeccionar un giro bajo luz rasante para detectar orientaciones invertidas y discontinuidades
en alas, deriva y fuselaje. Mantener el normal map en convención Godot X+, Y+, Z+; convertir Y si la fuente es DirectX.

**Decisión: adoptar tangentes como requisito previo para cualquier normal map en `SurfaceTool`; probar antes de modificar el modelo del avión.**
No se asigna normal map ni se cambia geometría en esta investigación.

Fuentes: [SurfaceTool 4.7](https://docs.godotengine.org/en/4.7/tutorials/3d/procedural_geometry/surfacetool.html), [StandardMaterial3D: normal
maps y canales](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html#normal-map), [código de SurfaceTool en el tag usado
por el repo](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/surface_tool.cpp).

## 5. Compresión de VRAM y KTX/Basis Universal

La importación detecta texturas empleadas en 3D y, por omisión, activa mipmaps y compresión VRAM. Godot describe la compresión VRAM como formato
habitual para 3D: baja uso de memoria y ancho de banda, con pérdida de calidad moderada dependiente del formato. La tabla oficial estima una
textura RGBA8 de 1024² con mipmaps en 5,33 MiB sin compresión VRAM frente a 1,33 MiB comprimida; son cifras documentales, no mediciones de este
simulador. *High Quality* no se aplica en Compatibility; los formatos dependen de plataforma (S3TC en escritorio, ETC2 en móvil/web cuando está
disponible).

**Aplicación local.** [`project.godot`](../../../app/project.godot#L23) fija Compatibility y activa la importación ETC2/ASTC necesaria para su
export universal de macOS; el comentario señala que no hay una biblioteca de texturas importadas para afinar actualmente. En ejecución,
[`ground.gd`](../../../app/render/ground.gd#L62) crea un `ImageTexture` desde una imagen procedural y
[`ugly_stik_finish.gd`](../../../app/aircraft/ugly_stik_finish.gd#L46) rasteriza la librea embebida a `ImageTexture`. El importador no aplica
automáticamente sus opciones a esas texturas creadas por código. El sidecar [`livery.svg.import`](../../../app/aircraft/livery.svg.import) sirve
de referencia de configuración del archivo fuente, pero el modelo toma la imagen SVG embebida.

Godot ya ofrece **Basis Universal** como modo de compresión de imágenes importadas; `PortableCompressedTexture2D` también documenta Basis
Universal para texturas 3D portables, con tradeoff de compresión más lenta y una pequeña pérdida de calidad. El listado 4.7 acepta `.ktx` 2D y
explica sus límites; no encontré `.ktx2` en los formatos oficiales listados. Por eso la investigación no recomienda instalar otro convertidor ni
hacer que el build dependa de KTX2 sin un ensayo de carga en el pin 4.7.2.

**Ensayo propuesto.** Fuera de `app/`, importar una carta idéntica de césped, pintura y goma con Lossless, VRAM Compressed y Basis Universal;
probar Compatibility y exportes que interesen. Registrar artefactos en color/normal, memoria reportada por Godot, peso de build y tiempo de
import/carga en una GPU modesta además de la RTX 3090. Mantener la librea fina sin pérdida hasta que una comparación demuestre que la compresión
es aceptable.

**Decisión: probar VRAM Compressed para mapas 3D grandes; conservar la librea en alta calidad mientras no haya captura A/B; posponer una tubería
externa KTX2/BasisU.** No se importó una textura ni se midió memoria o calidad en esta ronda.

Fuentes: [importación de imágenes 4.7: modos, costes y
formatos](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html#compress-mode), [clase PortableCompressedTexture2D
4.7](https://docs.godotengine.org/en/4.7/classes/class_portablecompressedtexture2d.html), [código de importación Godot 4.7.2: modo 3D, mipmaps y
Basis Universal](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/import/resource_importer_texture.cpp#L2383-L2402).

## Síntesis de adopción

- **Adoptar:** `source_color` en muestras de color de shaders propios; generar tangentes antes de normal maps en geometría `SurfaceTool`.
- **Probar:** márgenes/dilatación del atlas y compresión VRAM en una carta comparativa aislada.
- **Posponer:** roughness limiter hasta que existan mapas roughness + normal; herramienta/pipeline KTX2 externo hasta que la lista oficial y el
  import real demuestren el caso.

Las cinco pruebas son propuestas futuras: no son resultados realizados ni comprometen el preset visual. Mantenerlas alineadas con VQ-02 y la
futura biblioteca de materiales, sin modificar la física ni la base Compatibility.
