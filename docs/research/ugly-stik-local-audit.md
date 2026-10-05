# Ugly Stik: auditoría de referencias locales

Inspección: 2026-10-05. Relacionada con **ROADMAP D1**, preparación de geometría y **B5**, superficies articuladas. [Plan de trabajo](../UGLY-STIK-PLAN.md) · [Fuentes por variante](ugly-stik-sources.md) · [Inventario con hashes](ugly-stik-local-inventory.json).

> **Alcance histórico:** esta es la inspección inicial. La ronda posterior de [diez investigaciones](ugly-stik-investigations/README.md) consiguió el plano Jensen legible (60 in, 720 in², .45–.61) y [leyó los dos 3DM](ugly-stik-investigations/07-cad.md), incluyendo las mallas almacenadas. Esos resultados actualizan los pendientes descritos abajo. El directorio original `ugly stick ` se trasladó posteriormente a `references/ugly-stick/`; las descripciones de la primera inspección se conservan como registro. El objetivo del propietario es .61 primero; mini y gigante después.

## Método y alcance

Se abrieron las **14 imágenes** PNG/JPG de `ugly stick ` y se renderizó la página completa del PDF Grid Leaks con `pdftoppm`. Se leyeron encabezados y tipos de entidades de los seis DXF, y el encabezado binario de los dos `.3dm`. No se cargó la geometría 3DM/DWG en un programa CAD, no se validó su escala y no se midió un avión físico.

El directorio se llama literalmente `ugly stick `, con un espacio al final. El inventario registra 38 archivos allí y la copia adicional del PDF en `references/from-prototypes/`: **39 entradas**. Se conservaron las rutas. Los hashes identifican los bytes inspeccionados; no establecen autoría ni permiso de reutilización.

## Qué muestra cada imagen

Todas las descripciones siguientes son observaciones visuales de los archivos del usuario; la identidad de una variante no se deduce solo de su color.

| ID | Archivo local | Contenido observado | Uso propuesto / límite |
| --- | --- | --- | --- |
| JEN-01 | [image.png](../../references/ugly-stick/image.png), 720×566 | Plano titulado Das Ugly Stick 60, cartucho Jensen; planta/perfil de fuselaje, empenaje, motor y tren triciclo | Referencia principal coherente con DECISIONS; resolución insuficiente para todas las cotas. Verificar el área impresa frente a 723 in² en la spec |
| CAD-01 | [image2.png](../../references/ugly-stick/image2.png), 566×353 | Redibujo Classic Ugly Stick; atribución CAD Guy Fuller 1997, hoja 1 de 2; fuselaje y tren triciclo | Identificación y organización de vistas; no se verificó que el DWG homónimo corresponda exactamente a esta captura |
| GL-IMG | [image copy.png](../../references/ugly-stick/image%20copy.png), 640×480 | Plano Grid Leaks/BNPS con cartucho V133, ala, fuselaje y cola | Es la misma composición general que el PDF; usar el PDF para leer detalles, no esta miniatura |
| RCM-01 | [image copy 2.png](../../references/ugly-stick/image%20copy%202.png), 800×534 | Collage con cartuchos RCM plan 939 y fotos del avión rojo/blanco | Apariencia y comparación de variantes; no medir sobre el collage ni asumir que sus piezas son Jensen |
| KIT-01 | [image copy 3.png](../../references/ugly-stick/image%20copy%203.png), 328×214 | Componentes separados: ala roja/blanca, fuselaje, cola redondeada, hélice y tren | Reconocimiento de piezas y decoración; fabricante/configuración exactos sin verificar |
| KIT-01-DUP | [image copy 4.png](../../references/ugly-stick/image%20copy%204.png), 328×214 | Duplicado byte por byte de KIT-01 | No aporta evidencia independiente |
| GBS-01 | [great big stik 3d.jpg](../../references/ugly-stick/great%20big%20styk%20full/great%20big%20stik%203d.jpg) | Perspectiva de estructura abierta, costillas, largueros y tren principal | Construcción y forma general; no se identifica la configuración completa del tren por esta vista aislada |
| GBS-02 | [great big stik triciclo.jpg](../../references/ugly-stick/great%20big%20styk%20full/great%20big%20stik%20triciclo.jpg) | Perspectiva con tren triciclo y hélice | Relación entre patas y fuselaje; dimensiones no transferidas al Jensen |
| GBS-03 | [ala sup.jpg](../../references/ugly-stick/great%20big%20styk%20full/ala%20sup.jpg) | Semiala superior, costillas, largueros, punta y borde de salida | Comprender planta y separación de piezas |
| GBS-04 | [ala inf.jpg](../../references/ugly-stick/great%20big%20styk%20full/ala%20inf.jpg) | Vista inferior de semiala y zona de servo/mando | Referencia de montaje, no dato de aerodinámica |
| GBS-05 | [ala enc.jpg](../../references/ugly-stick/great%20big%20styk%20full/ala%20enc.jpg) | Sección alar con borde de ataque redondeado y afilamiento posterior | Justifica una sección visual con espesor; no identifica una familia NACA ni una polar |
| GBS-06 | [ala marg.jpg](../../references/ugly-stick/great%20big%20styk%20full/ala%20marg.jpg) | Otra sección alar y montaje del mando | Comparar estructura y contorno; no asumir misma escala de pantalla que GBS-05 |
| GBS-07 | [porta serb aler.jpg](../../references/ugly-stick/great%20big%20styk%20full/porta%20serb%20aler.jpg) | Detalle del soporte de servo de alerón entre costillas | Detalle opcional para inspección futura, innecesario para primera silueta |
| GBS-08 | [registro.jpg](../../references/ugly-stick/great%20big%20styk%20full/registro.jpg) | Acceso delantero y motor con dos cilindros opuestos visibles | Evidencia de que la instalación de esta referencia difiere de una representación nitro monocilíndrica provisional |

Los ocho JPG de Great Big Stik son de 1533×673 píxeles. Las imágenes de estructura no establecen que el CAD esté listo para el simulador.

## PDF: qué sí pudimos leer

[Ugly_Stik_Grid_Leaks_oz5175.pdf](../../references/from-prototypes/Ugly_Stik_Grid_Leaks_oz5175.pdf) es una página rasterizada: `pdftotext` produjo únicamente un salto de página. Su cartucho identifica Das Ugly Stick, Phil Kraft, dibujo Geo. Walker, Grid Leaks Plan Service y BNPS V133. La página muestra ala, perfil de costilla, estabilizador, fuselaje en planta/perfil y componentes del tren. Se distinguen las etiquetas VECO 45, JENSEN NOSEGEAR y una escala gráfica 0–6.

La regla y las cotas de piezas ofrecen una vía para calibrar futuras mediciones. El tamaño físico de página del PDF no debe usarse directamente como tamaño del avión: primero contrastar la escala gráfica y una segunda dimensión legible. Para medir contornos hay que guardar los puntos elegidos, la escala de cada vista y el error de lectura. Una captura en perspectiva no sirve como plano métrico.

La copia en `references/ugly-stick/` es idéntica a la de `references/from-prototypes/`:

```text
SHA-256 78a869d91fe15d961e691a549f4c53a28d9461458e0592de4959c6be2f865353
```

Las dos fotografías KIT-01 comparten:

```text
SHA-256 26af8770365e55a4a6a8089976a1e8fde9ac5d81ac08b6cdf3b726ba5c0954de
```

## CAD: oportunidades concretas y límites

Los seis DXF declaran `$ACADVER=AC1018`, `$INSUNITS=4`, `$MEASUREMENT=0`, `$LUNITS=2`. Autodesk documenta AC1018 como AutoCAD 2004, INSUNITS 4 como milímetros para inserción y MEASUREMENT 0 como sistema inglés. Son metadatos con funciones distintas; no constituyen una comprobación geométrica de la escala. Verificar contra una cota conocida antes de convertir a metros. [Referencia oficial de encabezados DXF](https://help.autodesk.com/cloudhelp/2024/ENU/AutoCAD-DXF/files/GUID-A85E8E67-27CD-4C59-BE61-4DC9FADBE74A.htm).

| Archivo DXF dentro de `great big styk full/` | Entidades seleccionadas contadas en `ENTITIES` | Posible utilidad |
| --- | --- | --- |
| `aleron.dxf` | 3 LINE, 10 SPLINE | Contorno sencillo para probar extracción sin abrir el conjunto |
| `gbs empenaje 2d.dxf` | 159 LINE, 32 SPLINE, 2 ARC, 3 CIRCLE | Contornos de cola para comparación |
| `plano ala full escala 2d.dxf` | 526 LINE, 100 SPLINE, 1 ARC, 5 CIRCLE | Examinar distribución del ala de esa variante |
| `plano fuce full escala 2d.dxf` | 1670 LINE, 278 SPLINE, 68 ARC, 25 CIRCLE | Examinar vistas y secciones del fuselaje de esa variante |
| `corte de ala final 2d.dxf` | 2741 LINE, 2126 SPLINE, 104 POLYLINE, 512 ARC, 88 CIRCLE, 5 DIMENSION | Piezas de construcción; mayor coste de limpieza |
| `corte final fuse 2d.dxf` | 2293 LINE, 1159 SPLINE, 33 POLYLINE, 534 ARC, 70 CIRCLE, 1 DIMENSION, 1 MTEXT | Piezas de construcción; mayor coste de limpieza |

El inventario JSON conserva también VERTEX y SEQEND. Estos recuentos son de registros DXF, no de triángulos, objetos 3D ni coste de renderizado. No se interpretaron las cotas ni se extrajeron superficies.

Los encabezados de `great big stik 3d final.3dm` y `gbs patin.3dm` indican formato 50 y Rhinoceros 5.0. El archivo grande ocupa aproximadamente 51 MiB, además de su respaldo y del ZIP. **No se ha comprobado** si tiene mallas utilizables, materiales, unidades consistentes o pivotes. La biblioteca del autor [rhino3dm](https://github.com/mcneel/rhino3dm) permite explorar archivos 3DM desde código; sería una prueba aislada posterior. No se instaló en esta revisión. La documentación de [openNURBS sobre mallas de renderizado](https://developer.rhino3d.com/en/guides/opennurbs/reading-render-meshes/) explica que pueden existir mallas asociadas a BReps/extrusiones; no demuestra que estén presentes en nuestros archivos.

El `.dwg` Classic Ugly Stick solo se inventarió, sin extraer su geometría. Los `.ai`, `.dwg`, `.3dmbak` y ZIP tampoco se convirtieron ni se descomprimieron. Mantenerlos como fuentes de consulta evita convertir una investigación de silueta en una migración CAD completa.

## Comparación con el modelo existente

Las capturas cercanas y los constructores muestran un fuselaje de sección constante, ala de cajas, cola rectangular y ruedas sin patas. Es una base de pruebas válida; los cambios más visibles serán estrechar el fuselaje, redondear la cola y unir el tren. No hace falta reproducir las costillas para lograr ese avance.

La tabla de SPEC aporta una comprobación útil de la separación entre geometría visual y física. Su ala fija tiene planta de `1.524 × 0.226 m` y sus dos alerones de `0.62 × 0.08 m`. Sumando esas superficies sin solapamiento se obtiene **0.443624 m²** de planta visual, mientras que el valor nominal de 723 in² equivale a **0.46645068 m²**: aproximadamente **4.9 % menos**. Es un cálculo sobre cajas de la especificación, no una medición del ala real ni un error aerodinámico demostrado. La envolvente de cuerda de 0.306 m no implica que toda la envergadura esté rellena con esa cuerda.

Esto refuerza la necesidad de un registro físico separado: no deducir área, CG o inercia de la malla actual. Además, 723 in² necesita contraste con el cartucho Jensen antes de convertirse en dato definitivo; véase [la revisión de fuentes](ugly-stik-sources.md).

La vista de piloto inspeccionada muestra un avión muy pequeño y la cercana permite distinguir piezas. Las lecciones existentes registran ~15 píxeles a ~87 m; no repetimos esa medición durante esta auditoría. La captura three.js ya tenía panel de B5 durante la lectura, mientras la de Godot aún no; el desarrollador estaba trabajando, por lo que no se usa esa diferencia para puntuar plataformas.

## Registro mínimo propuesto para cada medida

`variant`, `configuration`, `quantity`, `original_value`, `original_unit`, `si_value`, `source_id`, `source_location`, `evidence_kind`, `method`, `uncertainty`, `status`.

Conservar las categorías del roadmap: `manual`, `borrowed`, `estimated`, `measured`. Una conversión de unidades conserva la categoría de su fuente y añade la fórmula en `method`. Digitalizar un plano mide su representación, no un avión construido: registrar ese límite. Una dimensión tomada del Great Big Stik para un Jensen sería `borrowed`, aunque el CAD tenga muchas cifras decimales. Lo ilegible queda pendiente; no rellenarlo con precisión aparente.

## Lecciones obtenidas en esta inspección

Para incorporar posteriormente a `LEARNINGS.md`, sin editar el archivo mientras lo usa el otro desarrollador:

- **Abrir la imagen cambia la interpretación.** La colección contiene distintos planos y variantes, además de fotos; no es un único expediente homogéneo del Jensen. Usar IDs de fuente por dato.
- **Dos archivos no siempre son dos pruebas.** El PDF está repetido byte por byte y dos fotos también. Deduplicar lógicamente por hash antes de citar corroboración.
- **PDF no significa texto extraíble.** La extracción del plano devolvió solo un salto de página; hubo que renderizarlo y leerlo visualmente.
- **Un archivo CAD no demuestra escala ni facilidad de importación.** Los DXF contienen encabezados que requieren interpretación y muchos splines; se debe probar primero una pieza pequeña.
- **La envolvente de la malla no es el área aerodinámica.** El cálculo de planta del modelo de cajas difiere del valor nominal, incluso conservando su envergadura y cuerda máxima.
- **El trabajo paralelo necesita evidencias separadas.** Las capturas oficiales cambiaron durante la revisión por la implementación de B5. Las futuras pruebas de modelado deben escribir en su propio directorio.

## Reproducción de comprobaciones

Desde la raíz del repo, estos comandos son de lectura excepto por la imagen temporal:

```bash
sha256sum 'references/ugly-stick/Ugly_Stik_Grid_Leaks_oz5175.pdf' references/from-prototypes/Ugly_Stik_Grid_Leaks_oz5175.pdf
sha256sum 'references/ugly-stick/image copy 3.png' 'references/ugly-stick/image copy 4.png'
pdfinfo references/from-prototypes/Ugly_Stik_Grid_Leaks_oz5175.pdf
pdftotext references/from-prototypes/Ugly_Stik_Grid_Leaks_oz5175.pdf -
review_dir=$(mktemp -d /tmp/openrc-ugly-review-XXXXXX)
pdftoppm -scale-to 2600 -png -singlefile references/from-prototypes/Ugly_Stik_Grid_Leaks_oz5175.pdf "$review_dir/grid-leaks"
```

El manifiesto usa SHA-256 sobre los bytes, dimensiones de imagen y pares código/valor del encabezado DXF. La comprobación de entidades recorre exclusivamente la sección `ENTITIES`; no suma definiciones de `BLOCKS`. No se añadieron copias de planos ni imágenes de terceros a esta entrega documental.
