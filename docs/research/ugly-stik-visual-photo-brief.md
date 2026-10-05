# Referencias visuales aportadas: acabado rojo con cruces

2026-10-05 · Lectura directa de dos imágenes adjuntas por el propietario. Complementa el [plan visual](../UGLY-STIK-VISUAL-PLAN.md). Las fotos fijan la apariencia deseada; el plano Jensen y la geometría v3 siguen fijando la variante y escala del modelo .61.

## Identificación de las imágenes

- **Foto A:** avión sostenido por una persona, sobre césped, vista oblicua superior; imagen presentada de 600 × 377 px. Alas y fuselaje rojos, grandes campos blancos con cruces negras, cola vertical blanca. No se identifica a la persona, fabricante ni tamaño del avión.
- **Foto B:** avión en vuelo sobre cielo azul, morro a la izquierda, imagen presentada de 565 × 414 px; marca de agua «DURAFLY» en la esquina inferior derecha. Se usa para leer distribución gráfica, silueta y acabado; la marca de agua no demuestra por sí sola cilindrada, escala o correspondencia con Jensen.

Los originales se recibieron como adjuntos de la conversación. Esta revisión conserva aquí las observaciones; no se ha verificado una ruta local ni creado una copia de los originales. Las referencias A/B identifican esos adjuntos, no los archivos de la galería Outerzone ya existente. No se asigna un hash o URL supuesto.

## Observaciones y decisiones

| Zona | Lectura de las fotos | Consecuencia para el modelo |
| --- | --- | --- |
| Ala central | Amplia superficie roja continua | Eliminar la alternancia de bandas crema de v3; mantener limpio el centro |
| Extremos del ala | Campo blanco ancho en cada semiala, con una punta roja más allá del blanco | La marca queda hacia la zona exterior, pero no pegada al extremo; respetar el remate rojo |
| Separación rojo/blanco | Filetes oscuros visibles, especialmente en B | Dibujar líneas finas negras en los límites transversales del campo; no añadir un marco grueso uniforme alrededor de todo el ala |
| Cruces alares | Negras, cuatro brazos ensanchados y cintura estrecha; margen blanco alrededor | Crear un vector propio de ese contorno, simétrico. Evitar sustituirlo por una cruz de barras rectangulares o por una cruz diagonal |
| Deriva/timón | Superficie vertical redondeada predominantemente blanca con cruz negra centrada | Sustituir la deriva roja/timón blanco de v3 por un conjunto blanco, manteniendo la separación física de bisagra |
| Cola horizontal | Roja, sin grandes paneles blancos visibles | Dejar estabilizador y elevador rojos en la primera composición |
| Fuselaje | Rojo continuo en las zonas visibles | Retirar la franja lateral crema de v3 de la propuesta base |
| Pequeña marca dorsal | Campo blanco con cruz negra inmediatamente detrás de la zona central del ala, visible en ambas imágenes | Añadir una marca secundaria sobre el lomo; confirmar su encaje con el ala montada y en vista superior |
| Borde de salida | Festoneado visible, especialmente en B | Elevar su prioridad como rasgo de silueta; usar el plano para posición y forma de los recortes |
| Acabado | Reflejos amplios sobre rojo, pequeñas variaciones de superficie y juntas | Recubrimiento satinado a brillante moderado; mantener volumen y rojo legibles sin convertirlo en espejo |
| Morro | Conjunto mecánico expuesto y metalizado; hélice de apariencia clara en las fotos | Refinar el motor .61 y sus conexiones según documentación propia. El color de hélice puede ensayarse, sin afirmar material, marca o motorización a partir de estos píxeles |

## Lo que estas imágenes no resuelven

No hay una vista inferior completa y ortogonal que documente el intradós. Tampoco hay un primer plano suficiente de los servos, el circuito de combustible, el montaje del motor o todos los puntos de contacto del tren. Las diferencias de escala y perspectiva impiden extraer cotas de construcción o comparar directamente el tamaño de ambos aviones.

No se confirma si ambas caras de cada superficie llevan idénticas marcas. Adoptar simetría gráfica cuando haga falta completar una zona oculta es una decisión artística explícita. Para el intradós, comenzar con una extensión coherente del esquema rojo/blanco/negro y etiquetarla como propuesta; no inventar que las fotos muestran un fondo oscuro o campos más estrechos.

Servos, reenvíos y tren se construyen desde el Jensen y la documentación mecánica disponible. Las imágenes aportan la referencia de apariencia del morro, pero no prueban que el equipo fotografiado sea un glow .61.

## Comparación visual que debe acompañar la entrega

Preparar una vista del modelo en una orientación aproximada a A para comprobar masas de rojo/blanco y colocación de cruces; otra con cielo azul y orientación aproximada a B para comprobar lectura y festoneado. Usar además planta, intradós y laterales ortográficos. Las fotos no aportan lente ni distancia conocidas: la comparación será de composición, no una superposición dimensional ni una prueba de escala.

Antes de pasar a microdetalle, deben verse: centro alar rojo continuo, dos campos blancos exteriores, puntas rojas, filetes finos, cruces proporcionadas, conjunto vertical blanco, cola horizontal roja y marca dorsal pequeña. La legibilidad desde tierra se evalúa después sobre esa composición mediante el protocolo de 20/50/100 m.

## Contraste posterior con el catálogo Durafly

La [investigación 01](ugly-stik-visual-investigations/01-decoration-identity.md) consultó el catálogo oficial: Durafly describe una variante EPO eléctrica de 1100 mm con motor nitro simulado. Esto refuerza el uso de las fotos como referencia de acabado, manteniendo documentación glow independiente para la mecánica. No identifica por sí solo el SKU de la foto B. [Ficha oficial del producto](https://hobbyking.com/duraflytm-retro-series-das-uglystik-electric-sports-model-epo-1100mm-pnf.html).

## Fotos C/D recibidas durante la implementación v4

**C · Transmisión bajo recubrimiento rojo.** Primer plano presentado de 1000 × 763 px. Se distinguen una varilla metálica, un tramo roscado, una horquilla con pasador transversal y un apoyo de color latón con base circular. La salida opuesta tiene una cubierta oscura con dibujo semejante a tejido de carbono. El film rojo deja ver costillas y largueros. La imagen aporta referencias de material, uniones y escala relativa; no demuestra que esa instalación pertenezca al Jensen .61 ni permite medir sus cotas.

Aplicación: horquillas metálicas con dos orejas y pasador, bases circulares de latón y guías de salida. El tejido aparente no basta para imponer carbono en una construcción histórica. Se conserva la piel opaca roja elegida con A/B; reproducir transparencia requeriría estructura interior suficiente y una variante de acabado explícita. Las líneas sutiles de costilla del atlas actual son una interpretación gráfica, no una estructura transparente modelada.

**D · Motor sobre fondo blanco.** Primer plano presentado de 607 × 506 px. Se leen «O.S. MAX» y «SPECIAL EDITION». Presenta corona dorada con ranuras axiales, aletas plateadas finas separadas por huecos oscuros, cárter de aspecto fundido, orejas perforadas, eje frontal y carburador inclinado hacia delante y arriba. No hay evidencia suficiente en la foto para identificar su modelo exacto, cilindrada o dimensiones.

Aplicación: adoptar esos rasgos para el motor visual de clase .61, conservando el eje y los puntos de instalación existentes. La corona dorada y el carburador inclinado pasan a ser referencias de apariencia; no se copia el texto ni se afirma una réplica comercial. Silenciador, alimentación y bancada siguen apoyándose en la investigación documental y llevan sus estimaciones explícitas.

La foto D también quedó verificada como archivo local [`references/.61 ENGINE NITRO OS.png`](<../../references/.61 ENGINE NITRO OS.png>), SHA-256 `33552dca9dc62f3a4a9b8c732b0ac3714245b4a60cbc6bd6beb8fdbab2e7de33`. A/B/C siguen identificadas mediante los adjuntos, sin ruta o hash supuesto. [Entrega visual v4](ugly-stik-model-v4.md).

## Fotos E/F: silenciador montado y separado

**E · Motor plateado montado.** Imagen adjunta de 500 × 500 px. Permite distinguir el silenciador alargado, su nariz redondeada, nervaduras exteriores longitudinales, unión central y reducción hacia la salida. También se ve el cuello de unión al cilindro, tornillería y un racor. La culata de este motor es diferente de D; se usa como referencia de montaje, conservando la dirección artística dorada ya elegida.

**F · Motor dorado y silenciador separado.** Archivo del propietario [`references/.61 AND EXHAUST.png`](<../../references/.61 AND EXHAUST.png>), 1080 × 1080 px, SHA-256 `5e3b9e50c7b9e8f957cdf09aba5e67e4b4749ede6ef38df11e69ee53d1f437c1`. Es un conjunto con el escape desmontado, no un despiece interno del motor. Muestra con más claridad el cuello ancho de fundición y su brida, los resaltes paralelos sobre el cuerpo, la costura circunferencial, el cono posterior, la boquilla y el racor pequeño.

Aplicación: sustituir el silenciador ovoide y el tubo curvo provisional por un cuerpo alargado con cuello ancho, nervaduras y salida cónica. Mantener las rutas visibles de combustible y presión conectadas, y comprobar separación de hélice, bancada y fuselaje en el montaje. La foto carece de escala: longitudes, radios y tornillería del modelo continúan siendo estimaciones visuales. El nombre del archivo no identifica por sí solo la variante comercial.

Los dos PNG locales permanecen en `references/`, excluidos de Git por el acuerdo del repositorio. Se versionan sus observaciones y hashes, no los originales de terceros.
