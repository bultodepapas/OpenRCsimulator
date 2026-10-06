# Avanti: alineación y comparación por transparencias

2026-10-06 · Comparación de la maqueta AV-02 con tres fotografías oficiales ya archivadas. **Se ajustó la cámara; la geometría y las fotos permanecen intactas.**

Abrir el comparador interactivo (`references/avanti-s/alignment/index.html`, local only). También quedan imágenes listas para revisar: frontal con transparencia (`references/avanti-s/alignment/front_high-overlay.png`, local only), posterior con contorno (`references/avanti-s/alignment/rear_high-contour.png`, local only) y perfil superpuesto (`references/avanti-s/alignment/side-overlay.png`, local only).

## Uso

1. Elegir una de las tres vistas. Cada foto carga su propia cámara ajustada; no se compara una captura genérica con todas las imágenes.
2. Mover **Opacidad del modelo**, alternar **Contorno** o **Parpadear**. **Solo foto** y **Solo modelo** separan las capas.
3. Para afinar la presentación, arrastrar el modelo o ajustar X/Y, escala uniforme y rotación. **Restablecer ajuste** vuelve a la cámara calculada y elimina la corrección manual.
4. Activar puntos: círculos naranjas son referencias usadas para ajustar, verdes son puntos reservados y cruces cian son proyecciones del modelo. **Guardar ajuste JSON** descarga la corrección de presentación, sin sobrescribir los datos de geometría.

La cámara inicial se ajusta a morro, punta de deriva y dos extremos de ala en las vistas frontal/posterior. En el perfil se usa morro, punta de deriva, ala próxima y salida del fuselaje; este último punto es parcialmente oculto y menos fiable. Los puntos de cola reservados no participan en la optimización.

## Método y evidencia

Los originales son `CIMG7321` (frontal elevada), `CIMG7313` (posterior oblicua) y `CIMG7310` (perfil oblicuo), todos de 650 × 488 px, procedentes de la [galería oficial SebArt](https://www.sebart.it/img-photogallery/2012-Avanti-jet/index.htm). Los [puntos manuales](../../research/avanti-s/alignment/picks.json) incluyen hash de cada foto y de la geometría.

Se ajustan orientación y posición de una cámara perspectiva de **FOV vertical supuesto 45°**, centro óptico centrado y sin distorsión de lente. Se minimizan residuos de cuatro referencias, con varios puntos iniciales deterministas. No se optimizan las secciones del modelo, una homografía, escalas diferentes por eje ni una deformación de imagen. El ajuste de cámara queda en [camera-fit.json](../../research/avanti-s/alignment/camera-fit.json).

Godot renderiza directamente el modelo en RGBA transparente, sin interfaz ni fondo. Se compara la proyección de sus puntos con la del cálculo numérico para detectar errores de ejes, aspecto o conversión de cámara. El SVG superpone este render cian a la fotografía y calcula un contorno a partir de su alfa. Los controles manuales son una transformación 2D de presentación adicional, visible y reversible.

| Vista | RMS de ajuste, 4 puntos | RMS de puntos reservados | Lectura |
| --- | ---: | ---: | --- |
| Frontal elevada | 8,5 px | 5,8 px, 2 puntos | Útil para inspeccionar ancho y contornos de ala/cola |
| Posterior oblicua | 7,7 px | 26,1 px, 3 puntos | Coincidir en las anclas no hace coincidir la cola/salida; revisar forma y cámara |
| Perfil oblicuo | 16,6 px | 20,2 px, 1 punto | Menor confianza: perspectiva, oclusión y contornos aproximados |

Todos los errores son en la imagen nativa 650 × 488, no en el tamaño ampliado del navegador. Son errores conjuntos del modelo aproximado, cámara supuesta y selección manual; **no son tolerancias dimensionales del avión**. Los puntos medios de punta no son referencias topográficas exactas. Tampoco se conoce el FOV real de las fotos. Las cifras describen la cámara inicial; mover la capa manualmente no recalcula ese ajuste y la interfaz lo indica.

## Diferencias que permite revisar

En la frontal, los extremos generales quedan próximos, pero aparecen diferencias en anchura del fuselaje, silueta del ala y cuerda aparente de la cola. Las tomas cilíndricas esquemáticas sobresalen donde la referencia tiene una transición integrada. Las placas verticales del ala aparecen en la foto y siguen ausentes del modelo.

En el perfil, la transición de la deriva es demasiado angular en la maqueta y el contorno de la semiala próxima no sigue el fotografiado. La superposición posterior también muestra diferencias en cola/salida y morro. Estas observaciones identifican zonas de trabajo, pero no justifican corregirlas todas a partir de una sola vista: parte del residuo puede deberse a la cámara o a la correspondencia aproximada de puntos.

La siguiente iteración debe modificar un grupo de geometría cada vez y comparar las tres vistas con sus cámaras registradas. Si se vuelven a ajustar cámaras, guardar ambos resultados para distinguir mejora de forma de cambio de encuadre. Esta ronda deja el modelo anterior sin cambios como referencia de partida.

## Comprobación y reproducción

[Código y comandos](../../research/avanti-s/alignment/README.md) · [validación](avanti-s-alignment-validation.json) · manifiesto de renders (`references/avanti-s/alignment/renders-v1/render-manifest.json`, local only).

Se verificaron la transparencia real de los PNG, la conversión de proyecciones, los hashes de originales y geometría, y los controles de opacidad, modos, corrección manual, reinicio y exportación JSON en navegador. La página se revisó también a 390 px de ancho. Una copia sobre clon limpio puede volver a renderizar la geometría con las cámaras guardadas sin disponer de las fotos; el comparador sí necesita esos originales locales.

Las fotos, renders y comparaciones quedan en `references/avanti-s/alignment/` o en sus rutas originales, ignorados por Git. Solo código, puntos, cámaras y documentación propia se preparan para versionado. No se modificó la app ni se probó vuelo.

Continuación: [afinamiento de la geometría con estas mismas cámaras](avanti-s-contour-refinement.md). La comparación inicial y sus renders se conservan intactos como referencia.
