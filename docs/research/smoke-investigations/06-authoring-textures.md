# Autoría de texturas: máscara pequeña, flipbook o simulación

**Fecha:** 2026-10-05. **Pregunta:** ¿qué flujo produce una textura de humo reproducible para Godot 4.7.2 Compatibility sin añadir herramientas al runtime?

## Resultado y herramientas

Empezar con una máscara RGBA pequeña, gradiente radial nativo y parámetros/semilla versionados. Escalar a un flipbook solo si las capturas muestran discos repetidos; dejar la simulación de fluidos como experimento offline posterior. Los recursos se importan como imagen: el juego no necesita Material Maker, Krita ni Blender instalados.

| Herramienta | Evidencia y uso posible | Decisión |
| --- | --- | --- |
| Godot `GradientTexture2D` / `NoiseTexture2D` | Gradiente radial y ruido basados en recursos nativos. NoiseTexture2D genera en hilo y su imagen puede no estar lista de inmediato. | SM-02 empieza con el gradiente. Si añade ruido, fijar seed/configuración y esperar señal antes de leer la imagen. |
| Material Maker | MIT; nodos procedurales y export de PNGs o spritesheet con tamaño/cuadros configurables. | Opción para atlas si la máscara parece disco. Inspeccionar alfa exportado; sin dependencia runtime. |
| Krita | Capas transparentes y secuencia PNG; vídeo no conserva alfa. Blanco es color, no transparencia. | Alternativa para pintar 8–16 siluetas, guardando `.kra`. |
| Blender | Bake de fluidos con costo de cómputo y caché; Eevee permite Film Transparent y salida PNG RGBA. | Solo si el flipbook dibujado no funciona. Hornear/renderizar offline y reducir a atlas 2D, nunca cargar caché volumétrica durante el vuelo. |

## Importación y artefactos visibles

Godot recomienda mipmaps para reducir grano al ver una textura 3D oblicua o distante; cuestan cerca de un 33% más de memoria. En Compatibility, la compresión de alta calidad se trata como deshabilitada: la importación puede usar S3TC/DXT5 para alfa en desktop o ETC2 en mobile/web y producir artefactos. Línea base: PNG RGBA con importación lossless; comparar mipmaps y compresión con el renderer fijado antes de aceptar el preset. Para una máscara 64×64 RGBA8, el original ocupa 16 KiB y con mipmaps unos 21 KiB. La documentación estima 85 KiB para 128×128 lossless con mipmaps y unos 21 KiB en VRAM comprimida.

Con filtrado bilineal, RGB oscuro bajo píxeles transparentes puede formar halo. Mantener **Fix Alpha Border** y probar contra fondos claros/oscuros; usar premultiplicación solo si el material también usa blend premultiplicado. No habilitar Alpha Scissor/Hash en humo suave: recortaría cobertura continua. Usar RGB claro y alfa gradual hacia el borde; dejar tono y opacidad del perfil fuera de la imagen para compartir máscara entre escape y bomba.

Un atlas de 4×4 cuadros en 512×512 entrega celdas de 128×128. Reservar margen transparente y revisar bleeding del cuadro vecino al rotar y reducir partículas. Dieciséis cuadros y esas dimensiones son propuestas para medir, no requisitos de Godot ni garantía de calidad. Añadir ruido sutil de baja frecuencia solo si la prueba demuestra repetición: exceso de detalle puede producir banding o convertir una nube clara en mancha.

## Pipeline y decisión accionable

1. **SM-02:** crear máscara radial nativa en 64×64. Probar primero estática y en material blended. Si usa NoiseTexture2D, fijar `seed`, frecuencia y octavas en el recurso, y no depender de `get_image()` antes de su señal de finalización. Exportar a PNG solo si se necesita un activo precalculado estable.
2. Si la nube se percibe como discos, producir 16 cuadros en Material Maker o Krita, bucle cerrado y atlas 4×4. Guardar `.mmgraph` o `.kra`, versión y parámetros junto al PNG; revisar alfa, costura del bucle, gutters y filtrado en Godot.
3. Si el atlas pintado sigue sin volumen convincente, evaluar bake Blender de 16 muestras con Film Transparent y salida RGBA PNG. Conservar `.blend` y parámetros; quitar VDB/UNI temporales del paquete de juego.
4. En el manifiesto de SM-08 registrar fuente editable, herramienta/versión, seed o ajustes, formato y licencia. La licencia MIT/GPL de una aplicación describe su código, no la licencia de cada preset, pincel o textura importada. Verificar esos activos por separado; los renders originales pertenecen al proyecto conforme a los términos de la herramienta.

**Aceptación:** capturar la textura sola sobre fondos claros y oscuros; inspeccionar borde a escala 1:1, mipmaps, billboard en paisaje real, alfa, banding, halo y cuadros vecinos. Ver el atlas desde ambas cámaras durante el looping para asegurar que no tapa el avión ni parece una rueda mecánica. Repetir import desde checkout limpio y registrar memoria importada. El preview de una herramienta externa no sustituye Compatibility del ejecutable fijado.

La documentación cubre formatos y opciones, pero no determina si el humo de este avión requiere animación ni cuál será el atlas más legible. Eso queda para comparar en SM-02/06; 64×64 y 16 cuadros son estimaciones de lookdev.

## Fuentes primarias

- Godot 4.7: [importación de imágenes, alfa, compresión y mipmaps](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html), [NoiseTexture2D](https://docs.godotengine.org/en/4.7/classes/class_noisetexture2d.html), [GradientTexture2D](https://docs.godotengine.org/en/4.7/classes/class_gradienttexture2d.html).
- Material Maker: [repositorio/licencia](https://github.com/RodZill4/material-maker) y [exportación animada del panel 2D](https://rodzill4.github.io/material-maker/doc/user_interface_2d_preview_panel.html).
- Krita: [animación y transparencia de capas](https://docs.krita.org/en/user_manual/animation.html), [render de secuencias](https://docs.krita.org/en/reference_manual/render_animation.html), [licencia](https://krita.org/en/about/license/).
- Blender 4.5: [caché de fluidos](https://docs.blender.org/manual/en/4.5/physics/fluid/type/domain/cache.html), [Film Transparent](https://docs.blender.org/manual/en/4.5/render/eevee/render_settings/film.html), [formatos RGBA](https://docs.blender.org/manual/en/4.5/render/output/properties/output.html), [licencia](https://www.blender.org/about/license/).
