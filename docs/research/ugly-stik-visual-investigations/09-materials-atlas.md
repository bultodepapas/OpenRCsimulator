# 09 · Atlas UV y materiales para Compatibility

Fecha: 2026-10-05. **Pregunta:** ¿cómo llevar la decoración roja/blanca/negra al constructor nativo sin depender de funciones ausentes en Compatibility?

## Alcance y fuentes

Consulté docs oficiales **4.7**, no específicas del parche. El repo fija `4.7.2-stable`; [`ugly_stik_model.gd`](../../../app/aircraft/ugly_stik_model.gd) usa `SurfaceTool`/`ArrayMesh`, cachea material por color y no asigna UV.

## Hallazgos

Godot rasteriza SVG al importar; ThorVG tiene soporte limitado y el texto debe ser un trazado. Conservar la cruz como SVG simple sin fuentes y tratar la textura como derivado reproducible. [Importación de imágenes 4.7](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html)

Los mipmaps reducen grano y ancho de banda a distancia, con ~33 % más memoria. El filtrado 3D se configura por material; trilineal interpola niveles y anisotrópico mejora ángulos rasantes, con algo más de coste. **Inferencia:** dejar margen de color entre islas y comprobar sangrado al reducirlas. [Importación de imágenes 4.7](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html) · [BaseMaterial3D 4.7](https://docs.godotengine.org/en/4.7/classes/class_basematerial3d.html)

`StandardMaterial3D` ofrece albedo, metallic, roughness y normal; textura y color del albedo se multiplican. En shaders, albedo sRGB usa `source_color` (opcional en Compatibility, recomendable para cambiar renderer); mapas roughness/metallic/normal son datos lineales. Godot normal usa coordenadas OpenGL y canales rojo/verde; invertir Y para DirectX. El atlas requiere UV, no tangentes; mapas normales sí: `generate_tangents()` requiere UV y normales. Asignar cada UV correspondiente antes de `add_vertex()`. Separar acabados sin tratar valores artísticos como mediciones. [Material estándar 3D 4.7](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html) · [Lenguaje de shaders 4.7](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html) · [SurfaceTool 4.7](https://docs.godotengine.org/en/4.7/classes/class_surfacetool.html) · [Importación de imágenes 4.7](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html)

Compatibility **no admite Decal3D**. `ArrayMesh` sí admite UV por superficie: pintar las cruces en la piel y evitar planos superpuestos. Compatibility desactiva VRAM de alta calidad; el modo normal usa S3TC en escritorio o ETC2 en móvil/web y puede degradar bordes nítidos. [Renderizadores 4.7](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) · [ArrayMesh 4.7](https://docs.godotengine.org/en/4.7/classes/class_arraymesh.html) · [Importación de imágenes 4.7](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html)

## Cambio sugerido en US-V y validación

En **US-V01/V02**, usar UV comunes en ala, cola y piezas móviles para alinear marcas en neutro. Mantener SVG fuente y ensayar atlas opaco de 1.024 px (**estimación artística**); hacer antes microfixture de UV, mipmap, margen y compresión. Cachear por función/acabado además de color.

Validar luz neutra/de aplicación, vistas rasantes, bisagras y 20/50/100 m; revisar halos, sangrado y continuidad. Reimportar desde un clon limpio. No se midió compresión en la GPU objetivo.
