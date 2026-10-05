# 10 · Pruebas de secuencias y regresión visual

**Investigado:** 2026-10-05. **Pregunta:** ¿qué herramientas permiten detectar humo discontinuo, una bomba que no se apaga y nubes que sobreviven a un reinicio? **Evidencia:** documentación primaria en internet e inspección local; no se ha ejecutado un efecto de humo.

## Herramientas y hechos verificados

| Herramienta/fuente primaria | Capacidad documentada | Decisión para OpenRC |
| --- | --- | --- |
| [Movie Maker de Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/animation/creating_movies.html) | Grabación offline, secuencias PNG, `--fixed-fps` y salida por número de frames | Adoptar para clips deterministas de revisión; conservar PNG como evidencia |
| [NVlabs/FLIP](https://github.com/NVlabs/flip), [licencia](https://github.com/NVlabs/flip/blob/main/LICENSE) | Comparación perceptual de imágenes; BSD-3-Clause | Reutilizar `flip-evaluator==1.7` ya fijado y con hash en el proyecto |
| [FFmpeg: opciones de vídeo](https://ffmpeg.org/ffmpeg.html) | `-framerate` interpreta la cadencia de una secuencia de entrada; `-r` de salida puede duplicar o descartar frames | Opcional, solamente para vídeos de revisión; registrar versión/build si se usa |
| [RenderingServer 4.7](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html) | `frame_post_draw` permite esperar la actualización de viewports; headless devuelve valores ficticios para funciones gráficas | Render real bajo Xvfb/OpenGL para las pruebas del efecto |

La captura offline puede tardar más que el clip resultante: su cadencia no demuestra rendimiento en tiempo real. Tampoco hace determinista una fuente de aleatoriedad global o una trayectoria omitida. El harness debe fijar los inputs, el tiempo y las poses, según [investigación del reloj](02-clock-captures.md).

## Auditoría del harness existente

[`compare_captures.py`](../../../app/tests/compare_captures.py) ya tiene dos niveles: hash con adaptador/API iguales y FLIP cuando cambian. Usa un límite de píxeles distintos, más útil que una media global para defectos pequeños. Sin embargo, no valida por sí mismo todo el contexto de captura: el harness de humo debe registrar versión de Godot, configuración, semilla, tick, escena y recursos además del renderer. Una diferencia autorizada de material se revisa como cambio de baseline; no se oculta modificando la tolerancia.

Su función de legibilidad obtiene una máscara comparando avión visible/oculto. Si el humo desaparece junto con el avión, esa diferencia incluye ambos y deja de medir la silueta del avión. **Mejora concreta:** obtener máscara del avión en una pasada de referencia sin humo y reutilizarla en el par OFF/ON. Para estudiar la nube, usar un ROI independiente de trayectoria/estela. Las nubes del paisaje y la cámara deben representar el mismo instante en ambas imágenes.

El entorno local ya fija NumPy 2.5.3, Pillow 12.3.0 y FLIP 1.7 en [`requirements-visual.txt`](../../../app/tests/requirements-visual.txt). No se justifica añadir OpenCV, un framework de tests o un segundo comparador para esta entrega. Las versiones citadas son las del repositorio, no una recomendación de actualizar paquetes.

## Protocolo propuesto

1. Crear un programa de ensayo por tick: escape; bomba OFF→ON→OFF; pausa; reset; paso recto; giro que cruza la estela. Guardar esa programación en el manifiesto.
2. Capturar series a 30 y 60 fps con el mismo tiempo físico. Para 144 fps comparar estado funcional y continuidad; no exigir que sus píxeles coincidan con 60 fps.
3. Guardar contactos de frames y clips para revisión humana, más capturas exactas antes/después de cada transición. Esperar por render, no con sleeps de pared.
4. Medir desaparición residual tras OFF en una región fija: separar el corte de nacimientos de la muerte de partículas antiguas. Tras reset debe desaparecer el humo anterior de inmediato conforme al contrato.
5. Medir discontinuidades sobre un recorrido de referencia proyectado, con emisor y cámara controlados. El simple cambio de píxeles entre frames mezcla movimiento correcto y defectos; no sirve por sí solo como prueba de parpadeo.
6. Verificar dos ejecuciones iguales. Si un driver introduce variación, documentar su distribución antes de fijar umbral. Una semilla fija no demuestra igualdad entre fabricantes de GPU.

Una secuencia PNG 720p de 600 frames puede ocupar mucho más que un informe. Guardar logs/manifiestos pequeños en `docs/research/`, y capturas/clips en la carpeta ignorada `app/captures/smoke/`, como artefactos de CI. FFmpeg no debe regenerar los PNG usados como referencia a partir de un MP4 con pérdida.

## Cómo cambia el plan y cómo se prueba

**SM-05** pasa a exigir estados y secuencias, con máscaras independientes de avión/humo; **SM-06** revisa contactos además de clips. Se añaden controles negativos en una copia aislada: quitar la limpieza de reset, hacer locales las partículas o ignorar OFF debe hacer fallar el caso correspondiente. Ninguna mutación se realiza sobre el árbol compartido.

**No medido:** umbrales perceptuales específicos del humo, repetibilidad de Movie Maker con estos emisores y coste de generar la suite. El valor de 50 píxeles del comparador existente no se transfiere automáticamente a una nube translúcida grande.
