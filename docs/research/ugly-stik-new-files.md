# Nuevos archivos: Ultra Stick V3 y MoJo Parts 60

Inspección: 2026-10-05. Archivos entregados por el propietario en la raíz. [Inventario de 31 archivos con SHA-256](../../research/ugly-stik/new-files/inventory.json) · [análisis CAD](ugly-stik-new-files-cad.md) · [inspección de fotografías](ugly-stik-new-files-visual.md).

**Resultado:** el conjunto principal documenta **Ultra Stick 120 Light/Lite**, de mayor tamaño que el Jensen .61 que estamos construyendo. Aporta planos vectoriales, patrones y detalles de construcción útiles para una futura variante grande y para mejorar el procedimiento de medición. No resuelve por sí mismo las cotas pendientes del Jensen. El nombre `MoJo Parts 60.dwg` tampoco demuestra que sea un Ugly Stik .61.

Los originales siguen donde el propietario los dejó; no se editaron ni convirtieron en el sitio. Se añadieron exclusiones específicas a `.gitignore`, coherentes con el tratamiento de los demás originales de terceros. Los recortes y renders de lectura están en `references/ugly-stik/new-files-previews/`; la documentación e inventarios sí quedan en el repositorio.

## Qué hay y qué usar primero

| Grupo | Contenido comprobado | Uso |
| --- | --- | --- |
| [PDF de fuselaje](../../Ultrastick%20V3/PDF%20Plans/Ultr%20Stick%20Lite_fuse3.pdf) y [ala](../../Ultrastick%20V3/PDF%20Plans/Ultra%20Stick%20Lite%20Wing3.pdf) | Dos hojas de planos completos; cartucho RHB Designs, Ultra Stick 120 Light, motor O.S. 1.08 dibujado, tren de cola; ala y cola convencionales con opciones de mandos | Fuente de forma y montaje de esta variante; contiene un cuadrado rotulado de 1 in |
| [DXF Plans](../../Ultrastick%20V3/DXF%20Plans/) | Planos vectoriales de fuselaje y ala, vistas JPG y README | Preferibles al raster para extraer curvas y comprobar unidades; [resultados CAD](ugly-stik-new-files-cad.md) |
| [DXF Laser cutting files](../../Ultrastick%20V3/DXF%20Laser%20cutting%20files/) | Anidado de piezas, capas y compensación de corte documentada | Elegir geometría nominal para medir; no confundir piezas desplegadas con el avión ensamblado |
| [PDF de patrones](../../Ultrastick%20V3/pdf%20parts%20patterns/) | Tres hojas y README que pide comprobar el cuadrado de registro de 1 in, sin offsets | Una vía concreta para comprobar escala al imprimir y cotejar piezas del DXF |
| [Manual Horizon](../../Ultrastick%20V3/pics/Original%20Horizon%20manual.pdf) | 84 páginas, portada Hangar 9 Ultra Stick Lite; montaje, mandos, CG y programación quad-flap | Manual de otra configuración; conservar separado del redibujo RHB |
| [Fotografías](../../Ultrastick%20V3/pics/) | Once fotos de construcción/modelos; tres previews CAD adicionales en las otras carpetas | Piezas, costillas, servos, varillas, montajes y decoración; no regla de escala |
| [DWG](../../Ultrastick%20V3/DWG/) y [MoJo Parts 60.dwg](../../MoJo%20Parts%2060.dwg) | Cinco archivos binarios CAD en total | Inventariados y examinados con los límites documentados en el informe CAD |

El inventario completo registra **5 DWG, 3 DXF, 14 JPG, 6 PDF y 3 TXT**, 14,083,239 bytes en total. La inspección del manual se centró en portada/especificaciones, índice, recomendaciones de equipo y página 43; se extrajo su texto completo para búsqueda. No se revisaron visualmente sus 84 páginas.

## Dos configuraciones que no deben mezclarse

El cartucho del **redibujo RHB** imprime envergadura **78 in**, longitud **61 in**, área **1210–1230** según el tipo de alerón, peso **9–12 lb**, motores dos tiempos **1.08–1.50 in³** y cuatro tiempos **1.00–1.80 in³**; también enumera gasolina de 25 cc y eléctrico de 1500–2000 W. El cartucho no imprime unidad junto al área; el contexto del manual usa in². Conversiones directas de las cotas de longitud: **1.9812 m** y **1.5494 m**. Se leyó el cartucho en el PDF de fuselaje, no se dedujo del nombre del directorio.

La portada del **manual Horizon/Hangar 9** imprime **76 in** y **55 in**, peso **9–11 lb**. Además contiene equivalencias métricas incoherentes, visibles en la página original, no solo en la extracción de texto:

| Dato impreso | Equivalencia también impresa | Conversión aritmética del dato imperial |
| --- | --- | --- |
| 76 in | 1676 mm | 1930.4 mm |
| 1210 in² | 5934.5 “sq dm” | 78.06436 dm² |
| 9–11 lb | 2.7–3.15 kg | 4.082–4.990 kg |

Estas discrepancias impiden tratar la tabla como una ficha dimensional consistente. La aritmética identifica un conflicto; no prueba cuál de las cotas describe un avión real. El manual y el redibujo se mantienen con IDs separados. La página 3 del manual confirma el intervalo de motor dos tiempos 1.08–1.50; no se interpreta el `1.08–.150` de la portada como un intervalo válido.

## Datos de mandos y CG que sí aporta el manual

La página 43 recomienda CG a **4⅛ in detrás del borde de ataque** (104.775 mm). Da recorridos lineales, no grados: alerón ±¾ in en bajo / ±1¼ in en alto; elevador ±1 in / ±1½ in; timón ±2½ in / ±4 in; flaps 1½ in hacia abajo. Son recomendaciones del **Ultra Stick Lite del manual**, no del Jensen ni automáticamente del redibujo RHB. Convertir esos desplazamientos a ángulos requiere identificar la posición de medición y la distancia a la bisagra.

## El hallazgo más útil para medir

Los README distinguen dos contornos en los archivos de corte: rojo con compensación **0.004 in** (0.1016 mm), verde de tamaño nominal sin compensación, inicialmente apagado según el autor. Esto cambia la selección de curvas: para geometría del simulador se necesita el contorno nominal, no el de fabricación. El texto explotado también puede aparecer como líneas/polilíneas; contar entidades no equivale a contar piezas del avión.

La inspección CAD encontró `$INSUNITS=1` y cuadrados vectoriales de **1 × 1** en los tres DXF; el detalle por archivo está en [el informe CAD](ugly-stik-new-files-cad.md). El README de los PDF de patrones pide comprobar el cuadrado de **1 in**. Es una referencia explícita más clara que la rueda esquemática usada en el diagnóstico Jensen. Antes de extraer un contorno hay que contrastar ese cuadrado con una segunda dimensión y reservar otra comprobación; ni el tamaño de página ni `$INSUNITS` por sí solos bastan.

## Efecto en el plan .61

1. Conservar Jensen como geometría principal del .61. No sustituir su cola redondeada, tren triciclo, CG ni masas por los del Ultra Stick 120.
2. Usar las fotos como referencias de construcción y articulación, con variante identificada.
3. Guardar el paquete Ultra Stick como candidato documental para la futura variante grande, con sus propias medidas, montaje y datos físicos. No es automáticamente una ampliación exacta del Jensen.
4. Aplicar al flujo de trabajo la distinción entre contorno nominal y compensación de fabricación, y la verificación de escala con registros explícitos.
5. Mantener MoJo como conjunto separado hasta identificar su geometría y procedencia; “60” en el nombre no selecciona nuestra variante .61.

La malla v1 del Jensen continúa con estimaciones identificadas donde faltan medidas; este paquete nuevo mejora nuestras referencias y abre la variante grande sin cambiar el objetivo actual.
