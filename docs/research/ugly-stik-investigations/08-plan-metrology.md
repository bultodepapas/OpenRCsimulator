# 08 · Medir el plano sin convertir el escaneo en falsa precisión

Fecha: 2026-10-05. Paso: D1, preparación de geometría. **Pregunta:** ¿podemos obtener cotas del fuselaje directamente de los píxeles o del tamaño de página del PDF Jensen?

## Evidencia reunida

Se inspeccionaron las dos hojas del [plano Jensen oz1253](https://outerzone.co.uk/plan_details.asp?ID=1253), ahora descargado localmente (`references/ugly-stik/downloads/jensen/Das_Ugly_Stik_Jensen_oz1253.pdf`, local only). `pdfimages -list` identifica imágenes monocromas de 19316×14400 y 19144×14400 píxeles, declaradas a 400 ppp. El documento contiene imágenes, no contornos vectoriales que puedan importarse directamente como geometría.

La calibración espacial requiere una distancia conocida; también hay que comprobar por separado la escala horizontal y vertical. El manual de ImageJ describe ambas operaciones y el uso de una referencia de aspecto conocido. Es un método de medición, no prueba de que un dibujo esté a escala. [ImageJ: Set Scale](https://imagej.net/ij/docs/guide/146-30.html#sub:Set-Scale...). Para la conversión, una pulgada internacional equivale exactamente a 25.4 mm. [NIST](https://www.nist.gov/pml/owm/si-units-length).

## Experimento ejecutado

Se renderizó la hoja 1 a 2400×1790 píxeles y se leyó visualmente la rueda delantera rotulada **2¾ in**. Se seleccionaron extremos exteriores del dibujo, excluyendo el marco y la pata. Las coordenadas y el SHA-256 del PDF están en [plan-measurements.json](../../../research/ugly-stik/plan-measurements.json); [measure_plan.py](../../../research/ugly-stik/measure_plan.py) reproduce las conversiones usando solo la biblioteca estándar de Python.

| Comprobación | Resultado |
| --- | --- |
| Diámetro horizontal / vertical seleccionado | 131 / 131 px |
| Escala si esa rueda representa exactamente el diámetro rotulado | 0.5332 mm/px en ambos ejes |
| Escala inferida únicamente de la anchura física del PDF | 0.5111 mm/px |
| Diferencia entre ambos métodos | 4.33 % |
| Intervalo de escala con ±2 px por extremo | 0.5174–0.5500 mm/px |

El margen de ±2 px es una **estimación elegida para este ensayo**, no un intervalo estadístico. La rueda puede estar dibujada esquemáticamente. La discrepancia no identifica por sí sola si el problema está en el escaneo, el dibujo o el método de selección, y no justifica reescalar toda la hoja. El acuerdo X/Y solo afecta a esta pequeña región. [Resultados completos](evidence/plan-scale.json).

## Qué cambia en el plan

Antes de trazar el fuselaje se añade una entrega de **calibración por hoja y vista**. Una cota rotulada manda sobre el DPI. Elegir una referencia larga identificable —por ejemplo, la semienvergadura con su centro y extremo inequívocos— y verificarla con otra cota independiente. Registrar los extremos, el datum, unidades y residuo. Si no concuerdan dentro del error declarado, mantener coordenadas normalizadas y señalar el desacuerdo; no deformar silenciosamente el plano para satisfacer todas las cotas.

Para la geometría original guardar estaciones longitudinales normalizadas, anchura y altura, con vínculo al contorno de origen. Definir si la longitud incluye motor, hélice y timón: las líneas de extensión del plano no son el extremo de una pieza. Las fotos oblicuas sirven para apariencia y montaje, no como regla métrica.

**Prueba siguiente:** dos controles de escala por vista, incluidas direcciones X/Y, y una cota reservada que no participe en el ajuste. Publicar su error junto al contorno. Un objetivo inicial de error del 1 % sería un criterio de trabajo **propuesto**, pendiente de comprobar que la fuente lo permite; no una exactitud que esta revisión haya conseguido.

## Reproducir

```bash
python3 research/ugly-stik/measure_plan.py
```

El programa verifica el hash si está presente el PDF. Si falta la descarga, informa que solo está recalculando las selecciones guardadas. No modifica el plano ni el simulador.
