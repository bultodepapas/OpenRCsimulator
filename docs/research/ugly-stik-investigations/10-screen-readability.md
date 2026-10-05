# 10 · Qué detalles sobreviven a la distancia del piloto

Fecha: 2026-10-05. Paso: D7/Gate 2 y prioridades de modelado. **Pregunta:** ¿conviene invertir primero en costillas, texturas y tornillos, o en silueta y manchas de color?

## Fuente y método

La cámara del proyecto usa FOV vertical de 50° y capturas de 1280×720. La documentación de [PerspectiveCamera](https://threejs.org/docs/pages/PerspectiveCamera.html) confirma que `fov` es vertical y se expresa en grados. Con píxeles cuadrados y zoom 1, la distancia focal en píxeles es `f = H / (2 tan(FOV/2))`. Un segmento paralelo al plano de imagen, de longitud `L` y profundidad `d`, ocupa `p = f L / d` píxeles.

Se implementó el cálculo y la proyección de los dos extremos a distinta profundidad en [screen_size.py](../../../research/ugly-stik/screen_size.py), independiente del código activo. Envergadura: 1.524 m, conversión del rótulo Jensen 60 in. Se eligieron una mancha de 200 mm y una junta de 2 mm como tamaños de ensayo **estimados**, no como mediciones de una decoración o construcción real.

## Resultado ejecutado

720 px de altura, 50° verticales; segmentos paralelos al plano de imagen:

| Profundidad | Envergadura 1.524 m | Mancha 200 mm | Junta 2 mm |
| --- | --- | --- | --- |
| 20 m | 58.83 px | 7.72 px | 0.077 px |
| 50 m | 23.53 px | 3.09 px | 0.031 px |
| 100 m | 11.77 px | 1.54 px | 0.015 px |

A 100 m y con la línea de envergadura inclinada 60° respecto al plano de imagen, su longitud proyectada baja a aproximadamente **5.88 px**. Aumentar la altura de captura de 720 a 1080, manteniendo FOV y proporción, multiplica las longitudes por 1.5. Estas son predicciones geométricas, no mediciones de legibilidad humana ni del rasterizador.

También se reprodujo la pose circular de SPEC a `t=3 s` con cálculo independiente: distancia al centro **87.204 m**, separación proyectada entre puntas **8.775 px**; colocada paralela a la imagen a la misma distancia, la envergadura daría **13.492 px**. El primer valor no es el ancho de todos los píxeles del avión: excluye cuerda, fuselaje, ruedas, antialiasing y cobertura del rasterizador. No contradice automáticamente la estimación anterior de ~15 px de la captura completa.

[Tabla completa CSV](evidence/screen-size.csv) · [Resultados y supuestos JSON](evidence/screen-size.json). Pasaron comprobaciones analíticas de escala con distancia, resolución y orientación; no se ejecutó un ensayo con pilotos.

## Qué cambia en el plan

Priorizar proporción global, cola, tren y bloques grandes de color. La geometría de inspección puede añadir detalle, pero no debe retrasar la lectura desde tierra. No se puede prometer que una junta o unas costillas mejoren la orientación a distancia: su proyección es muy inferior a un píxel en estos casos.

Mantener el tamaño físico del modelo. Comparar cualquier ayuda de zoom como opción explícita de cámara y registrar su FOV efectivo. El intradós oscuro es una variante visual de prueba, no decoración histórica confirmada.

Para una futura simplificación, elegir umbrales por tamaño proyectado y medir el coste real antes de hacer varias mallas. Three.js dispone de cambios de LOD por distancia e histéresis para evitar cambios repetidos en el límite, pero no resuelve por sí mismo la orientación perceptual. [Documentación de LOD](https://threejs.org/docs/pages/LOD.html).

**Prueba siguiente:** capturas con la misma cámara a 20/50/100 m, frente/costado/arriba/abajo y virajes, comparando decoraciones sobre la misma malla; registrar si el usuario distingue morro/cola y arriba/abajo. Añadir una vista a 1080p para separar limitaciones de resolución y de diseño. No fijar un presupuesto arbitrario de polígonos como sustituto de esa prueba.

## Reproducir

```bash
python3 research/ugly-stik/screen_size.py
```

Escribe solo sus propios CSV/JSON y no usa servidores, capturas ni dependencias del simulador.
