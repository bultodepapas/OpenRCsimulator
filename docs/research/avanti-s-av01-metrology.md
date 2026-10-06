# Avanti S AV-01: cotas, recortes y preparación del modelo

2026-10-05 · **AV-01 parcialmente preparado.** Referencia A200 original de 2000 × 2220 mm y P100-RX 2017. Hay archivo organizado, cotas trazables y un panel de mandos; todavía no hay planta calibrada ni avión implementado.

Abrir la [mesa de referencias local](../../references/avanti-s/organized/index.html) o el [panel interactivo de dimensiones y flaps](../../references/avanti-s/organized/study-board.html). El panel compara longitudes a una misma escala y permite seleccionar flap 0°/20°/50° y recorrer el diferencial de alerones. Es un esquema geométrico: no simula sustentación, trim ni tiempo de servo.

## Archivo ordenado

Se conservan las rutas originales para no romper documentos anteriores. La carpeta `organized/` añade copias con nombres descriptivos y separa:

| Carpeta | Contenido |
| --- | --- |
| `documents/baseline/` | Manuales A200, planos del motor/abrazadera y catálogo elegido; manual RX histórico rotulado como comparación |
| `documents/comparison/` | Mini, XS y catálogo SebArt actual |
| `documents/text/` | Texto extraído de los 11 PDF para buscar; las cotas se comprueban en la página visual |
| `images/01-airframe/`, `02-canopy/` | Vistas generales, silueta y cabina, con nombres que reconocen la perspectiva |
| `images/04-gear/`, `05-propulsion/`, `06-installation/` | Tren, motor, electrónica y secuencia adicional del tanque |
| `images/08-livery/`, `09-optional-vector/` | Decoración superior/inferior y accesorio vectorial separado de la configuración elegida |
| `assembly-pages/` | Las 91 páginas completas, numeradas, como contexto de los recortes |
| `details/03-controls/` y otras carpetas por componente | 42 recortes de pasos seleccionados, con página y número de paso en el nombre; conservan las anotaciones del PDF |

También se extraen cuatro láminas completas: recorridos, datum de CG, dimensiones P100 y tabla del catálogo 2017. El [catálogo de organización](avanti-s-organized-catalog.json) registra archivo de origen, URL, hash, página, paso, resolución, caja del recorte y hash del resultado. No confundir las 91 páginas navegables con una auditoría dimensional completa de las 91.

Se descargaron **23 fotos adicionales y 2 páginas HTML oficiales**: 13 fotos de montaje del [depósito de queroseno/humo](https://www.sebart.it/img-jets/Avanti/Tank/tank-foto.html) y 10 del [escape vectorial opcional](https://www.sebart.it/img-jets/Avanti/VES/vector%20thrust.html). Las imágenes pequeñas de la secuencia de tanque son de 330 × 246 px: se conserva esa resolución, sin inventar detalle. Dos incluyen una regla, pero la lectura de extremos y perspectiva no queda resuelta; no se incorporan como cotas. El total al cierre de esta ronda AV-01 fue de **67 originales descargados**; las copias, recortes y páginas renderizadas no cuentan como descargas nuevas.

## Tamaño y proporciones documentadas

| Magnitud | Valor | Evidencia / interpretación |
| --- | --- | --- |
| Envergadura | 2000 mm | Nominal A200, introducción PDF p.1 |
| Longitud | 2220 mm | Nominal A200, introducción PDF p.1 |
| Longitud/envergadura | 1,11 | Cociente de las dos cotas anteriores; no aproxima cuerda ni área |
| Masa seca RTF con P100 | 10,5 kg | Incluye motor; falta combustible y balance de una instalación concreta |
| Longitud P100-RX elegida | 241 mm | Plano dimensional; coincide con catálogo 2017 |
| Diámetro del cuerpo P100-RX | 97 mm | Plano; no diámetro exterior del fuselaje |
| Diámetro de salida del motor | 60 mm | Plano; no diámetro de salida del tubo instalado en Avanti |
| Longitud motor / avión | 10,86% | Solo proporción de escala; no ubicación de bancada |
| Diámetro motor / envergadura | 4,85% | Cociente geométrico, sin significado aerodinámico |
| Masa del motor | 1,080 kg | Catálogo 2017, incluye válvulas según nota 2; no inventario completo de instalación |
| Empuje nominal ralentí / máximo | 2 / 100 N | Catálogo 2017: condiciones de banco, no empuje instalado en vuelo |
| Régimen ralentí / máximo | 44.000 / 154.000 rpm | Misma edición; no mezclar ralentí del manual RX histórico |
| Consumo nominal ralentí / máximo | 80 / 390 ml/min | No permite calcular autonomía sin combustible utilizable y perfil de potencia |
| Empuje máximo / peso seco | 0,971 | `100 / (10,5 × 9,80665)`; disminuye con combustible o pérdidas de instalación |

Fuentes: [introducción A200](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf#page=1), [plano P100-RX](https://www.jetcat.de/jetcat/produkte/hobby/p100_rx/JetCat%20P100%20RX%20Size.PDF), [catálogo JetCat 2017, página PDF 15](https://www.jetcat.de/jetcat/Kataloge/JetCat%20Lieferprogramm%202017_web.pdf#page=15). La página PDF 15 contiene una tabla a doble página; la columna escogida es **P100-RX**, no otra turbina. Condiciones de catálogo: 15 °C, 1013 mbar, ±3%.

Los datos numéricos, fuentes con hash y fórmulas quedan en [measurements.json](../../research/avanti-s/av01/measurements.json). Se distinguen nominales del fabricante, fotos acotadas y cocientes derivados. No es un JSON de vuelo `openrc-aircraft`; deliberadamente no entra en `app/data/aircraft/`.

## Flaps, cotas locales y montaje

La secuencia exacta para estudiar el flap es:

1. [Eje de palanca, p.21 paso 41](../../references/avanti-s/organized/details/03-controls/flap-eje-palanca-p021-s041.png).
2. [Neutro, p.21 paso 42](../../references/avanti-s/organized/details/03-controls/flap-posicion-vuelo-p021-s042.png): 0° según introducción.
3. [Despegue, p.22 paso 43](../../references/avanti-s/organized/details/03-controls/flap-posicion-despegue-p022-s043.png): 20° abajo; mezcla recomendada de elevador abajo 8%.
4. [Aterrizaje, p.22 paso 44](../../references/avanti-s/organized/details/03-controls/flap-posicion-aterrizaje-p022-s044.png): 50° abajo; mezcla recomendada de elevador abajo 20%.

Los ángulos proceden del [manual de introducción, p.4](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf#page=4), no de medir las fotos oblicuas. El alerón sube 30° y baja 25° a recorrido alto; elevadores y timón tienen 30° por sentido. Las mezclas en porcentaje necesitan una definición de canal/rate antes de convertirse a una deflexión; no son coeficientes físicos.

Las cotas de varillaje merecen conservar sus extremos: **60 mm** de alerón (p.8/16), **52 mm** de flap (p.15/29), **34 mm** de elevador (p.44/87), **39 mm** de timón (p.50/99). Las flechas no miden necesariamente entre centros de ambas articulaciones: alerón/elevador acotan el tramo entre extremos internos de terminales; la cota de flap parte del pasador de la horquilla y termina al comenzar el terminal negro. Copiar esos números como longitud total del enlace deformaría el rig. [Fotomanual](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Photoinstriction.pdf).

La continuidad visual p.69–72 y los rótulos de válvulas de aire permiten clasificar los dos cilindros blancos como **depósitos neumáticos de tren/freno**. El tanque de queroseno/humo es otro conjunto, visible en p.73 y en la nueva secuencia del accesorio. No se ha acreditado capacidad de ninguno. Véase la [investigación de mandos e instalación](avanti-s-controls-and-installation.md) y sus citas de página/paso.

## Datum y siguiente avance

Para compartir la convención visual del Stik se propone nariz `−Z`, derecha `+X`, arriba `+Y`, metros. El datum longitudinal se toma en el borde de ataque junto al fuselaje, proyectado sobre el plano de simetría. Entonces las referencias de CG corresponden a `z = +0,240 / +0,250 / +0,260 m`, **solo una vez construido ese datum**. La altura del origen, altura del CG y distancia nariz–datum no están medidas. La [foto p.91/181](../../references/avanti-s/organized/details/07-datum/cg-desde-borde-ataque-raiz-p091-s181.png) y la [introducción p.5](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf#page=5) definen la referencia longitudinal.

Antes de cerrar AV-01 faltan planta calibrada o contorno aproximado explícito, secciones, cuerdas, área, incidencias y extremos de bisagra. El panel actual permite revisar tamaños y movimientos, pero no sustituye esa geometría. AV-02 podrá mostrar un volumen aproximado declarado; AV-05 sigue siendo necesario para volar con propulsión de turbina.

## Reproducción y prueba

[Herramienta y uso](../../research/avanti-s/av01/README.md) · [selección de fotos/pasos](../../research/avanti-s/av01/selection.json). La extracción usa Poppler: recortar una región del PDF conserva texto, flechas y dibujo; `pdfimages` por sí solo pierde anotaciones vectoriales. Los originales se verifican por SHA-256 antes y después. No se mueven ni renombran archivos anteriores.

La validación de archivo y enlaces queda en [avanti-s-validation.json](avanti-s-validation.json); la del panel y clon limpio, en [avanti-s-av01-validation.json](avanti-s-av01-validation.json). Los originales y derivados permanecen bajo `references/`, ignorados por Git. Esta entrega no modifica la app ni ejecuta pruebas de vuelo.

Avance posterior: [AV-02, maqueta aislada y fotos de alta resolución](avanti-s-av02-preview.md).
