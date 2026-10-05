# 08 · Comparación de capturas con Pillow, SSIM y pixelmatch

2026-10-05 · **Pregunta:** ¿cómo detectar cambios gráficos sin confundir ruido del renderizador con regresiones visibles?

## Línea base local

El wrapper v3 ejecuta dos capturas independientes en 1280×720 y compara SHA-256 de cada PNG antes de publicar el conjunto; [`make_review_kit.py`](../../../research/ugly-stik/model-v3/make_review_kit.py) falla si difieren bytes o nombres. La galería fija 36 poses, fondos, distancia, cámara y luces en su manifiesto ([captura](../../../research/ugly-stik/model-v3/capture.sh) · [lectura y coste](../ugly-stik-model-v3-readability.md)). El hash prueba repetibilidad byte a byte en ese entorno; no explica dónde cambió una imagen ni prueba equivalencia entre GPU distintos.

## Opciones y límites

Pillow `ImageChops.difference` devuelve la diferencia absoluta por píxel; con `ImageStat` o una máscara puede resumirse o excluir cielo, suelo y áreas de interfaz. Es adecuado para producir una imagen diff sencilla tras fijar cámara, resolución, fondo, materiales, luz y pose. No alinea imágenes ni entiende qué píxeles son cruces, silueta o texto: una diferencia de iluminación puede dominar el recuento. [API `ImageChops`](https://pillow.readthedocs.io/en/stable/reference/ImageChops.html) · [API `ImageStat`](https://pillow.readthedocs.io/en/stable/reference/ImageStat.html)

`scikit-image 0.26.0` ofrece `metrics.structural_similarity`, que calcula SSIM y puede entregar un mapa local, pero exige elegir parámetros y conviene pasar `data_range=255` para capturas uint8. SSIM es una métrica, no una garantía de lectura visual: no existe un umbral universal que asegure que una cruz desplazada o un filete fino siga siendo legible. El paquete añade NumPy, SciPy, NetworkX, Pillow, imageio, tifffile y otras dependencias; es mucho para una comparación básica. [API SSIM](https://scikit-image.org/docs/stable/api/skimage.metrics.html) · [dependencias y licencia BSD-3-Clause](https://github.com/scikit-image/scikit-image/blob/main/pyproject.toml) · [licencias](https://github.com/scikit-image/scikit-image/blob/main/LICENSE.txt)

Mapbox `pixelmatch` aplica un umbral perceptual de color y puede identificar/ignorar bordes antialias; el paquete JS 7.2.0 requiere `pngjs` y usa licencia ISC. Añadirlo para un pipeline Python incorporaría Node como ruta paralela sin resolver máscaras geométricas o iluminación por sí solo. [API y opciones](https://github.com/mapbox/pixelmatch) · [versión, dependencia y licencia](https://github.com/mapbox/pixelmatch/blob/main/package.json)

## Decisión y verificación pendiente

**Mantener el hash exacto para repeticiones en la misma máquina; usar Pillow como único complemento diagnóstico** si V02 necesita un diff visual. El entorno local ya tiene Pillow 11.3.0 (no fijado en el repositorio); la documentación oficial consultada es 12.3.0, MIT-CMU. Si se vuelve paso obligatorio, declarar una versión exacta en el entorno de herramientas en vez de depender de la instalación global. No adoptar SSIM ni pixelmatch ahora. [versiones Pillow](https://pillow.readthedocs.io/en/stable/about.html) · [licencia](https://pillow.readthedocs.io/en/stable/about.html#license)

Las comparaciones entre máquinas deben tolerar pequeñas variaciones del driver y separar máscaras: geometría/silueta, decoración, etiquetas y fondo/iluminación. La cámara y la luz permanecen fijas dentro de cada comparación. La documentación de Pillow no promete invariancia entre GPU; por tanto, el hash idéntico entre drivers distintos sería un requisito inventado. **Verificación propuesta, no ejecutada:** diffs idénticos, de un píxel y de una cruz desplazada bajo máscara; cambiar solo el fondo debe alterar el diff completo pero no el de geometría. El ensayo humano de orientación sigue siendo evidencia separada.
