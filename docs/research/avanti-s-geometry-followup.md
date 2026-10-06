# Avanti S A200: investigación geométrica complementaria

2026-10-06 · Fuentes primarias del fabricante y revisión de los recursos locales. Alcance: **SebArt Avanti S Jet 2.2m ARF original**, referencia de manual con envergadura nominal de 2000 mm y longitud de 2220 mm, con JetCat P100-RX y salida fija como configuración objetivo. No trasladar cotas de Mini, XS, FC/Krill ni de la ficha comercial A200 actual rotulada 2.3 m.

## Resultado

No encontré una planta constructiva, un juego ortográfico acotado ni un fichero CAD oficial del A200 original en las páginas y documentos oficiales revisados. SebArt publica las dos cotas generales, un manual de instalación fotográfica, una introducción con CG y recorridos de mando, fotos de producto y la identificación de opciones de tubo. Eso ayuda a fijar escala, componentes y apariencia, pero deja sin medir el ala y sus secciones.

La maqueta visual puede avanzar con los 2,00 m de envergadura y los 2,22 m de longitud como anclas nominales. Las cuerdas, área, flecha, diedro, perfiles, espesores, localización de bisagras y volumen del tubo deben continuar etiquetados como estimaciones hasta conseguir medición física o una vista acotada. No calcular superficie alar, MAC ni carga alar a partir de fotos oblicuas.

## Fuentes oficiales inspeccionadas

| Fuente | Qué ofrece | Resultado geométrico |
| --- | --- | --- |
| [Ficha oficial Avanti S Jet](https://www.sebart.it/jets-L.html) | Envergadura 200 cm, longitud 222 cm, masa RTF seca declarada, selección de turbinas y enlaces a manuales/galerías. | Dos cotas generales; no enumera área, cuerda ni perfiles. |
| [Manual de introducción A200, PDF](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf) | PDF de seis páginas: dimensiones generales p. 1, equipos/turbina p. 2, recorridos p. 4 y datum de CG p. 5. | No contiene plano en planta ni tabla de geometría alar. |
| [Fotomanual de montaje A200, PDF](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Photoinstriction.pdf) | Secuencia de 91 páginas con fotos de piezas, servos, mandos, instalación del tubo y tren. | Las cotas que aparecen son locales a enlaces o montaje. Las imágenes no son vistas ortográficas calibradas. |
| [Descargas oficiales SebArt](https://www.sebart.it/download/) | Lista las imágenes de alta resolución Avanti S-Jet 01–05 y otros manuales. | Son fotos comerciales, no láminas técnicas ni un modelo tridimensional. |
| [Accesorios oficiales SebArt](https://www.sebart.it/accessories.html) | Identifica las referencias de los tubos A200-13, -14 y -15. | Confirma la opción P100 de doble pared; no publica medidas. |
| [Lista de precios SebArt 2026, PDF](https://www.sebart.it/download/sebart-pricelist.pdf) | Muestra el producto A200 actual con etiqueta 2,3 m y opciones de la revisión vigente. | Su nomenclatura no debe combinarse automáticamente con el manual original de 2,2 m. |
| [Plano dimensional JetCat P100-RX](https://www.jetcat.de/jetcat/produkte/hobby/p100_rx/JetCat%20P100%20RX%20Size.PDF) | Cotas del motor, entre ellas 241 mm de largo, 97 mm de diámetro del cuerpo y 60 mm en la salida del motor. | Es el motor, no el conducto A200-13 ni la salida del tubo instalado. |

La revisión local del manual oficial de montaje está en [la copia original](../../references/avanti-s/manuals/avanti-s-200-assembly.pdf), con páginas renderizadas en [`organized/assembly-pages/`](../../references/avanti-s/organized/assembly-pages/). Las cotas generales, CG y mandos ya consolidados están en [AV-01 metrología](avanti-s-av01-metrology.md) y [mandos e instalación](avanti-s-controls-and-installation.md); este documento registra el hueco de geometría que esos datos todavía no cierran.

## Huecos por componente

| Elemento | Dato respaldado | Dato que no aparece en las fuentes consultadas |
| --- | --- | --- |
| Ala en planta | Envergadura total nominal: 2000 mm. El fotomanual muestra las semialas separadas y montadas. | Cuerda de raíz y punta, cuerda por estación, flecha, quiebros, diedro, washout, espesor, área, MAC y posición de MAC. |
| Perfil y secciones | SebArt describe alas de madera recubiertas; describe el diseño como inspirado en el Hawk real. | Coordenadas de perfiles, estaciones estructurales, espesores, largueros y sección del fuselaje. La referencia al Hawk no identifica una sección aerodinámica específica. |
| Cola | Las fotos de montaje muestran estabilizador, elevadores y timón por separado. | Envergadura y cuerda del estabilizador, áreas de elevador/timón, perfiles, incidencias y estaciones de las bisagras. |
| Superficies de mando | El manual recomienda flap 0°/20°/50°, alerón 30° arriba/25° abajo y elevador/timón ±30° (PDF p. 4). | Cuerda y longitud de cada superficie, coordenadas del eje de bisagra, holgura, balanza, relación brazo/superficie y cronometraje de servo. |
| Fuselaje y entradas | Longitud total nominal 2220 mm; la secuencia visual enseña estructura interna y montaje de la turbina. | Estaciones longitudinales, diámetros, contorno de tomas, línea de empuje respecto al datum y posiciones dimensionales del tren. |
| Tubo fijo A200-13 | El manual llama opcional al tubo de empuje A200-13 para P100 (PDF p. 2); la página de accesorios lo llama tubo de escape de doble pared P100. | Largo instalado, diámetros interior/exterior, taper, material/espesor, peso, soporte y desplazamiento del eje respecto al fuselaje. |

El manual fotográfico identifica operaciones de montaje, no una cota de bisagra respecto a borde de ataque o punta. Las longitudes visibles de enlaces —60 mm para alerón, 52 mm para flap, 34 mm para elevador y 39 mm para timón— son cotas del varillaje fotografiado, no la dimensión de esas superficies; ver recortes y extremos señalados en [la ficha de metrología](avanti-s-av01-metrology.md).

## Tubo P100: identificación y límites

Dos fuentes oficiales coinciden para la **referencia de la edición original**: el manual de introducción asocia P100 con el tubo opcional A200-13, y la página de accesorios asocia A200-13 con P100 y tubo de doble pared. La misma página distingue A200-15 para P180 y sistema vectorial. Es razonable modelar el A200-13 de esta configuración como conducto fijo sin vectorado; ninguna de esas fuentes publica su geometría.

El manual de 91 páginas muestra el conjunto de escape alrededor de los pasos 131–134 (PDF pp. 66–67), pero las fotos no rotulan el número A200-13, no identifican la revisión de la turbina ni incluyen una escala dimensional. No se puede asignar el producto de la foto a la pieza P100 con certeza. La galería oficial de tubos enlazada desde Accesorios está en [`3tubi-01.jpg`](https://www.sebart.it/img-jets/Avanti/3tubi-01.jpg) y [`3tubi-02.jpg`](https://www.sebart.it/img-jets/Avanti/3tubi-02.jpg): presenta tres conductos y un detalle de una unión, sin etiquetas por pieza ni escala. Sirve para construcción visual de doble pared, no para extraer longitud o diámetro.

Las cotas **97 mm** y **60 mm** de JetCat se refieren al cuerpo y a la salida de la turbina en el dibujo del P100-RX. No se debe tomar 60 mm como diámetro de salida del tubo A200-13: falta la transición entre turbina, conducto de doble pared y cola del fuselaje.

### Precaución de revisión

La documentación consultada conserva dos estados de catálogo distintos. El manual original de 2.2 m lista A200-13 para P100 y A200-14 para P140/P160. La página de accesorios actual aún enumera A200-13/P100, A200-14/P140 y A200-15/P180 vectorial; el PDF de precios 2026 anuncia A200 como 2.3 m y en su tabla muestra A200-14 para P160–180 y A200-15 vectorial, pero no enumera A200-13 en esa sección. El sitio no explica en esos documentos si es cambio de revisión, combinación comercial o pieza retirada. Por eso, conservar A200-13 como **opción documentada para la referencia original**, no como una dimensión verificada ni como afirmación de disponibilidad actual del kit.

## Fotos oficiales nuevas para futuras referencias

La página de descargas enlaza cinco JPEG de alta resolución, cada uno de 4320 × 3240 px. Están alojados por SebArt; la inspección visual confirma que sirven como referencia de silueta y acabado, no como plan. No son tomas cenitales ortográficas: las vistas elevadas tienen perspectiva y el perfil de suelo también presenta perspectiva de cámara.

| Nombre publicado | URL oficial | Lectura visual segura |
| --- | --- | --- |
| Avanti S-Jet 01 | [JPG](https://www.sebart.it/download/planes/Avanti%20S%20Jet/Avanti%20S_Jet-01.JPG) | Avión completo en plataforma, silueta lateral en perspectiva. |
| Avanti S-Jet 02 | [JPG](https://www.sebart.it/download/planes/Avanti%20S%20Jet/Avanti%20S_Jet-02.JPG) | Vista elevada frontal de tres cuartos. |
| Avanti S-Jet 03 | [JPG](https://www.sebart.it/download/planes/Avanti%20S%20Jet/Avanti%20S_Jet-03.JPG) | Vista elevada frontal del lado opuesto. |
| Avanti S-Jet 04 | [JPG](https://www.sebart.it/download/planes/Avanti%20S%20Jet/Avanti%20S_Jet-04.JPG) | Vista lateral oblicua con persona; escala humana aproximada, sin control de distancia. |
| Avanti S-Jet 05 | [JPG](https://www.sebart.it/download/planes/Avanti%20S%20Jet/Avanti%20S_Jet-05.JPG) | Detalle de cabina y morro. |

Estas cinco URL se comprobaron como recursos JPEG del dominio oficial. Se conservaron los originales en [high-resolution/](../../references/avanti-s/high-resolution/), con URL, fecha, hash y aviso de perspectiva en el [manifiesto](avanti-s-resources.json). La foto 03 es otra vista frontal oblicua, desde el lado contrario a la 02.

## Qué puede avanzar con rigor

1. Fijar la envolvente de la maqueta por las cotas nominales verificadas: 2000 mm de punta a punta y 2220 mm de nariz a cola. Registrar el punto inicial y final que se usen para interpretar la longitud, ya que la ficha no define un datum de nariz alternativo.
2. Dibujar un bloque visual de fuselaje, ala baja en flecha, cola, cabina e intakes guiado por las fotos. Cada estación no publicada debe llevar `visual_estimate`, la vista de referencia y una nota de incertidumbre.
3. Mantener la superficie aerodinámica y el `S`, MAC, incidencias y centro aerodinámico fuera de datos de vuelo hasta conseguir una fuente o calibración física. No convertir una malla a datos de vuelo por el solo hecho de que mida dos metros de punta a punta.
4. Modelar la forma general de un conducto fijo de doble pared para el encuadre visual; conservar diámetros y longitud como parámetros estimados. Una implementación de empuje deberá usar la línea/eje que se mida o declarar ese eje como estimación aparte.
5. Para cerrar metrología, solicitar al fabricante el plano A200 de la revisión elegida o medir un ejemplar desmontado con cuerda raíz/punta, estaciones de borde de ataque, secciones y bisagras. Para el tubo, solicitar plano de A200-13 con cotas de interfaz P100 y salida trasera.

**Conclusión de búsqueda:** no hay evidencia primaria publicada en las fuentes revisadas para asignar una superficie alar, cuerda, perfiles o dimensiones del A200-13. La búsqueda no demuestra que SebArt o un propietario no tengan planos internos; identifica el límite de los materiales públicos localizados al 2026-10-06.
