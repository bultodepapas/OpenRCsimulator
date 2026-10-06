# Extra 300S .60: recursos locales y lectura inicial

2026-10-05 · Revisión 2 · [Plan](../EXTRA-300-PLAN.md) · [Comparación de familia](extra-300-family-research.md) · [Manifiesto de descargas](extra-300-resources.json) · [Segunda ronda](extra-300-round2.md).

**34 archivos descargados**, más la foto del propietario y vistas de inspección generadas localmente. La primera ronda reunió 13 archivos (13.257.936 bytes); la [segunda añadió 21](extra-300-round2.md), con planos/manual/despiece del .40 asociado a la foto, más fotos y un artículo de construcción del .60. Están en `references/extra-300/`, cubierto por la regla existente `references/` de `.gitignore`. Esta tarea no cambió esa regla ni añadió originales al índice de Git; tampoco ejecutó commit/push. Investigación, procedencia y plan sí se conservan como documentación del repositorio.

Abrir la galería local (`references/extra-300/index.html`, local only) para consultar fotos, planos y manuales. Los enlaces a `references/` funcionarán en esta máquina; en un clon limpio se recuperan los originales desde sus fuentes. El runtime y sus futuras exportaciones no deben depender de esa carpeta.

## Paquete elegido: GPMA0236 / EXT6

Fuente de archivo: [Outerzone oz10977](https://outerzone.co.uk/plan_details.asp?ID=10977). La documentación Great Planes es fuente primaria por autoría aunque esté preservada en un archivo de terceros. Las conversiones de plano/CAD son derivados; no equivalen a un original certificado.

| Archivo local | Inspección y uso |
| --- | --- |
| Manual (`references/extra-300/gp-extra-300s-60/Extra_300S_60_oz10977_manual.pdf`, local only) | 50 páginas, EXT6P03 V1.2, ©2004 Great Planes. Instalación, mandos y CG; p.47 contiene dos vistas para decoración |
| Plano de dos hojas (`references/extra-300/gp-extra-300s-60/Extra_300S_60_oz10977.pdf`, local only) | Cartuchos ©1998, N. Liptak / M. Cross; EXT6P02 fuselaje y EXT6P01 ala. Vistas abiertas; escala pendiente de calibrar |
| Extracción vectorial (`references/extra-300/gp-extra-300s-60/Extra_300S_60_oz10977_vector.pdf`, local only) | 2 páginas; la ficha advierte que está sin escalar. Conservar para comparar contornos, sin medir desde el tamaño de página |
| CAD ZIP (`references/extra-300/gp-extra-300s-60/Extra_300S_60_oz10977_CAD.zip`, local only) | Un DXF de 19.555.878 bytes; CRC verificado. Alan Sinclair declara extracción y redibujo de costillas/cuadernas. Cabecera/entidades leídas en ronda 2; no importado ni calibrado |
| Ficha de procedencia (`references/extra-300/provenance/outerzone-oz10977.html`, local only) | Snapshot HTML con enlaces y atribución; no replica el sitio completo |

No confundir con GPMA0235 (.40), ARF GPMA1240, variantes 1.20/1.60 ni versiones eléctricas.

## Datos nominales transcritos

Lectura de los cartuchos del plano y p.43 del manual; **no son mediciones de una construcción real**. Los valores SI se calculan con 1 in = 0,0254 m y 1 lb = 0,45359237 kg. La envergadura y el área coinciden con los rótulos observados, no validan la escala de todas las vistas.

| Magnitud | Publicado | Conversión / límite |
| --- | --- | --- |
| Envergadura | 64 in | 1,6256 m |
| Superficie alar | 744 in² | 0,47999904 m² |
| Longitud | 54¼ in | 1,37795 m; comprobar extremos incluidos al calibrar |
| Masa nominal | 7–7,5 lb | 3,175–3,402 kg; configuración y condición de combustible por cerrar |
| CG inicial | 4⅛ in detrás del borde de ataque | 0,104775 m; resolver estación 2D / raíz antes de transferir a física |
| Ajuste de CG | ±⅜ in | Intervalo local 0,09525–0,11430 m |

De span/área se derivan `S/b = 0,295275 m` y alargamiento `b²/S = 5,5054`. El primero es cuerda media geométrica; **no afirmar que sea MAC**. La distribución de cuerda del ala importa para la referencia de momentos.

P.43: alerón bajo/alto ±¼ / ±⅝ in; elevador ±¾ / ±1¼ in; timón ±1½ / ±2½ in. Son desplazamientos en la parte más ancha, no ángulos. El CG se comprueba con depósito vacío. P.3 documenta una instalación de prototipo .61FX con escape Pitts Slimline #3217. No importar automáticamente el escape externo del Stik.

La hoja de fuselaje anota **2° hacia la derecha** en planta y **−½°** en perfil. La ampliación visual permite distinguir −½ de 1½; el datum y su transformación física todavía deben fijarse. Detalle local de perfil (`references/extra-300/inspection/downthrust-note.png`, local only). Una primera versión axial tendría que identificarse como simplificación.

## Fotografías: qué aportan realmente

Las seis imágenes se descargaron de los enlaces públicos de la ficha. Son miniaturas de 640 píxeles de ancho, suficientes para masas de color y montaje; no para metrología. La ficha acredita el aporte del conjunto a **William Trujillo Melo**. La foto 003 muestra otra decoración en blanco y negro; no se atribuye su captura original ni se la trata como la misma construcción.

| Foto | Lectura visual realizada |
| --- | --- |
| Principal (`references/extra-300/photos/gp-extra-300s-60-main.jpg`, local only) | Vista general del modelo rojo/blanco, cabina oscura y proporciones |
| 003 (`references/extra-300/photos/gp-extra-300s-60-003.jpg`, local only) | Otra decoración; carenado, cabina y carenas de ruedas visibles |
| 004 (`references/extra-300/photos/gp-extra-300s-60-004.jpg`, local only) | Oblicua delantera/superior; carenado a cuadros, ala y cola |
| 005 (`references/extra-300/photos/gp-extra-300s-60-005.jpg`, local only) | Lateral oblicua; lomo de fuselaje, posición de cabina y asiento alar |
| 006 (`references/extra-300/photos/gp-extra-300s-60-006.jpg`, local only) | Superficie superior: campos blancos, bordes rojos y filetes oscuros |
| 007 (`references/extra-300/photos/gp-extra-300s-60-007.jpg`, local only) | Superficie inferior: franjas azules/claras distintas del extradós; referencia útil de orientación |

La hoja de contacto local (`references/extra-300/inspection/photos-contact-sheet.jpg`, local only) reúne las seis. No permite demostrar perfil exacto, peso, motor, velocidad ni cumplimiento del plano. Los colores se interpretan bajo iluminación y cámara desconocidas.

Para el juego, producir geometría y atlas propios. Una descarga pública no convierte planos, logos, fotos ni un DXF ajeno en recursos MIT del proyecto. Los originales y rasterizados quedan locales como solicitó el propietario.

## Comparativas separadas

| Recurso | Uso y exclusión |
| --- | --- |
| Manual oficial EF 60 Extra 300 EXP con addendum V2 (`references/extra-300/comparison/ef-60-extra-300-exp-v2-manual.pdf`, local only) | Comparación de RC acrobático eléctrico; no aporta dimensiones, CG ni mandos al GPMA0236. [Fuente del fabricante](https://extremeflightrc.com/cdn/shop/files/EF-60extra-V2_manual_b58079bb-afb0-434a-a4da-930f2d508ced.pdf?v=13810129977580418015) |
| Historia Extra 1993 (`references/extra-300/provenance/extra-1993.html`, local only) | Evidencia de familia/producción del avión tripulado; ninguna equivalencia automática de dinámica RC. [Fuente del fabricante](https://extraaircraft.com/milestones/1993/) |

El manual O.S. .61FX ya existe en referencias del Stik (`references/ugly-stik/downloads/components/os-max-61fx-40-91fx-manual.pdf`, local only), con procedencia en su [catálogo](ugly-stik-resources.md). Reutilizar esa documentación del motor evita otra copia; su instalación y sus resultados no se trasladan sin revisión.

## Verificación inicial y ampliación

En la primera ronda se comprobaron firmas PDF/JPEG/ZIP al descargar, tamaños y SHA-256 de 13 archivos. `pdfinfo`/`pdftotext` abrieron los PDF, Pillow abrió las seis fotos y `zipfile.testzip()` verificó CRC sin ejecutar ni extraer el CAD. Se inspeccionaron visualmente las dos hojas del plano, p.47 del manual, la anotación ampliada de incidencia y la hoja de fotos; p.43 se contrastó en texto y raster. La segunda ronda verifica las descargas añadidas y registra comparación de la foto, lectura estática de ambos CAD y artículo RCM en su [evidencia](extra-300-round2-evidence.json).

La primera hoja del plano informa 3324,78 × 2592 puntos PDF (aprox. 46,18 × 36 in). **Eso describe el soporte PDF, no valida su escala.** Las plantillas, secciones y vistas deben contrastarse con cotas independientes antes de exportar metros al modelo.

Próximo experimento: identificar referencias de escala por vista, medir el ala y una estación de fuselaje, guardar incertidumbres y una cota de control que no participe del ajuste. La cabecera del DXF declara pulgadas, pero todavía falta validar sus contornos; no hay malla Extra, medición aerodinámica ni validación de vuelo.

Para recuperar los archivos, abrir la ficha Outerzone y usar sus descargas; el sitio rechaza enlaces externos directos. El manifiesto guarda las URLs solicitadas/finales, pero la ficha es el enlace público de procedencia. Ninguna recuperación necesita credenciales ni ejecución de archivos descargados.
