# Ugly Stik .61 — plan visual: rojo clásico, cruces y mecánica

2026-10-05 · Revisión 1 · **Plan pendiente de implementación.** Continúa [US-06/07/08 del plan general](UGLY-STIK-PLAN.md), sobre el [modelo v3](research/ugly-stik-model-v3.md). Dirección solicitada por el propietario: rojo con cruces, mayor detalle del motor, servos y equipamiento.

## Resultado buscado

Un Ugly Stik .61 rojo reconocible desde tierra, con cruces negras sobre campos blancos y una instalación mecánica convincente al acercarse. La presentación debe transmitir un aeromodelo de madera recubierto: superficies ligeras, motor glow expuesto, fijaciones, neumáticos y mandos visibles. El acabado inicial será cuidado, con uso leve localizado.

La elección roja con cruces ya está definida por el propietario. Se puede avanzar con ella sin esperar el ensayo humano pendiente de v3; ese ensayo servirá para ajustar su lectura. Se conserva el Jensen de 60 pulgadas con tren triciclo. Este documento planifica la siguiente entrega visual; no modifica todavía la malla.

## Punto de partida comprobado

Se revisaron el constructor, el adaptador, la captura neutra v3, la hoja 2 del Jensen y la fotografía local 013. El estado actual contiene:

| Área | V3 existente | Mejora que aporta más |
| --- | --- | --- |
| Decoración | Rojo `#c8102e`, bandas crema, franja lateral e intradós oscuro; sin cruces | Composición roja/blanca/negra completa y coherente entre superficies |
| Materiales | Cinco materiales; caché identificada solo por color | Diferenciar recubrimiento, aluminio, acero, goma y plástico por respuesta a la luz |
| Motor | Cárter cilíndrico, cilindro, seis aletas, bujía, carburador y escape simplificados | Silueta de fundición, culata, montaje, tornillería, admisión, salida de escape y tubos |
| Mandos | Bisagras articuladas; sin servos, cuernos ni transmisiones modelados | Mostrar cómo se conectan los mandos y mantener sus uniones durante la deflexión |
| Montaje | Dos retenedores cruzados, espigas, tren y ruedas básicos | Bandas planas, anclajes, collarines, llantas y uniones creíbles |
| Presentación | Nueve vistas generales y 36 casos a distancia | Primeros planos comparables y una vista de mantenimiento para los componentes internos |

Referencia cuantitativa v3: **54 mallas, 4.816 triángulos y cinco materiales**. Es una línea base de coste, no una restricción artística ni un benchmark. [Captura inicial](../research/ugly-stik/model-v3/inspection/three-quarter-neutral.png) · [Manifiesto](../research/ugly-stik/model-v3/inspection/manifest.json).

## Dirección artística y referencias

**Decoración.** Adoptar fondo rojo, cruces de brazos ensanchados negras sobre campos blancos, y detalles blancos suficientes para ordenar la silueta. Dibujar las cruces como vectores propios a partir del contorno de referencia. Sustituir las bandas actuales donde compitan con las insignias. Empezar con el rojo existente y un blanco cálido; ajustar bajo iluminación neutra y después bajo la luz de la aplicación. La captura v3 se percibe rosada en sus reflejos: revisar conjuntamente luz y material antes de cambiar el color base.

**Distribución propuesta, todavía artística:** una cruz en cada semiala superior e inferior y una marca lateral en cada cara de la deriva/timón. Contrastar un campo blanco amplio arriba con un marco blanco más estrecho abajo, conservando el rojo como base. Registrar esta diferencia como ayuda visual propuesta; no atribuirla al plano. Revisar primero la deriva para decidir si la marca cabe en la pieza fija o debe dividirse entre fija y móvil. Los distintivos no deben atravesar una bisagra como una sola superficie rígida. El fuselaje mantiene una franja blanca sencilla; cualquier rótulo «Das Ugly Stik» será discreto y secundario.

**Materiales.** Recubrimiento rojo/blanco satinado con reflejo amplio; aluminio del cárter más mate que arandelas y eje; caucho oscuro rugoso; plástico de servos y cuernos con brillo moderado. Pliegues y juntas solo donde la construcción los justifique. El entelado puede insinuar costillas en zonas abiertas sin convertir cada costilla en una ondulación exagerada. Añadir suciedad mínima junto al escape después de conseguir una buena versión limpia.

| Referencia disponible | Uso en esta entrega | Límite |
| --- | --- | --- |
| [Jensen firmado, hojas 1–2](../references/ugly-stik/downloads/jensen/Das_Ugly_Stik_Jensen_oz1253.pdf) | Cruces, campos gráficos, servos, reenvíos, cuernos y montaje | La hoja 2 rotula **ambas** alas como vistas inferiores; cruz y escarapela son opciones gráficas. No deducir extradós/intradós de izquierda/derecha |
| [Notas del kit](../references/ugly-stik/downloads/jensen/Das_Ugly_Stik_Jensen_oz1253_insert_notes.pdf) | Interpretar montaje de ala y mando de alerones | Conservar el contexto de cada detalle |
| [Manual O.S. MAX-61FX](../references/ugly-stik/downloads/components/os-max-61fx-40-91fx-manual.pdf) | Proporciones y piezas identificables de un .61 glow | Referencia provisional; el motor sigue genérico y sin marca elegida. Separar cotas del 61FX de otros motores del manual |
| [Foto 013](../references/ugly-stik/downloads/components/outerzone-1253-photo-013-thumb.jpg) y [catálogo de fotos](research/ugly-stik-resources.md) | Recubrimiento, festoneado, juntas y apariencia de construcción | La 013 es azul/blanca y tiene tren de cola; no demuestra el acabado rojo ni cambia nuestro tren |
| [Investigación de decoración y componentes](research/ugly-stik-investigations/04-06-components.md) | Procedencia y diferencias entre variantes | Las fotografías pequeñas no aportan cotas finas |

Antes de añadir un detalle sin suficiente referencia, hacer una consulta concreta —por ejemplo, salida del silenciador o brazo del carburador— y guardar fuente y conclusión en `docs/research/`. No hace falta repetir la investigación general del avión. Las posiciones y tamaños elegidos por apariencia se etiquetan como estimados.

## Entregas pequeñas y orden de ejecución

Todos los pasos siguientes están pendientes. Los IDs US-V continúan el frente de modelado y se vinculan a D1/D7, US-07/08 y Gate 2; no crean nuevos hitos de física.

| Paso | Trabajo concreto | Entrega y comprobación |
| --- | --- | --- |
| **US-V01 · Composición** | Preparar una lámina propia de planta, intradós y laterales: ubicación de cruces, campos blancos y franja. Registrar fuente y decisión artística por superficie | Lámina y ficha de acabado; verificar simetría, orientación de vistas y separación de bisagras. Primer resultado visible: avión rojo con cruces en las capturas generales |
| **US-V02 · Recubrimiento y marcas** | Aplicar composición, ajustar rojo/blanco/negro, separar materiales por función, mejorar continuidad del sombreado y juntas del recubrimiento | Comparativa v3/nuevo acabado con cámara y luz fijas; capturas con luz neutra y luz de aplicación. Sin parpadeo de marcas, reflejos quemados ni costuras de UV visibles |
| **US-V03 · Motor .61** | Refinar cárter, base y orejas de montaje, cilindro/culata, aletas, bujía con hexágono, carburador con garganta y brazo, aguja, silenciador con juntas y salida hueca visual; arandela y tuerca de hélice | Primeros planos de ambos costados, frontal y superior; comprobar apoyos, conexiones, eje de hélice y holgura con el morro. Sin motor flotante ni tubos que terminen en el aire |
| **US-V04 · Mandos exteriores** | Cuernos de elevador, timón y alerones; clevis, varillas, salidas de guía y reenvíos identificados en el plano. Actualizar extremos según las bisagras existentes | Capturas y secuencia neutro/extremos/combinaciones; uniones continuas, sin varillas que atraviesen fuselaje o superficies. Documentar contactos intencionales |
| **US-V05 · Servos e instalación interna** | Servos de alerones según el montaje documentado y servos de fuselaje para elevador/timón/gas: carcasa, tapa, orejas, gomas, tornillos, brazo y cable corto. Bandeja y conducciones suficientes para explicar el montaje | Vista de mantenimiento con ala/tapa ocultables y mandos animados. Los componentes interiores conservan su posición real; no se sacan al exterior para hacerlos visibles |
| **US-V06 · Herrajes y terminación** | Bandas de sujeción planas, espigas, asiento alar, collarines del tren, fijaciones, llantas, flancos de rueda, tornillos seleccionados, mangueras de combustible/presión y cableado visible | Macro de raíz alar, tren y motor. Cada pieza tiene soporte o conexión; ausencia de solapes accidentales. Las cantidades y rutas no confirmadas quedan estimadas |
| **US-V07 · Acabado fino y presentación** | Insinuar estructura bajo recubrimiento, pequeñas juntas, festoneado documentado y desgaste leve del escape. Mejorar sección visual de pala y borde sin alterar diámetro/eje | Galería final con avión montado, detalle mecánico y mantenimiento. Evaluar silueta del festoneado y holguras después de cualquier cambio de contorno |
| **US-V08 · Lectura y coste** | Repetir inspección y 36 casos 20/50/100 m; comparar antes/después; medir mallas, triángulos, materiales y llamadas de dibujo. Perfilar CPU/GPU en equipo disponible | Manifiestos y reporte de diferencias; pruebas de contrato pasan. Respuestas del piloto y rendimiento en hardware identificados por separado, pendientes si todavía no se dispone de ellos |

Orden: **V01 → V02 → V03 → V04 → V05 → V06 → V07 → V08**. Revisar lectura y coste tras cada entrega, no únicamente al final. Si un microdetalle degrada la imagen a distancia o consume coste desproporcionado, simplificar su representación conservando la apariencia importante.

## Servos y movimiento: alcance concreto

La primera implementación del mecanismo seguirá el esquema visible del Jensen: leer soportes, servos, reenvíos y cuernos antes de elegir su ubicación. No sustituirlo automáticamente por servos modernos en cada punta. El aspecto comercial de las carcasas será genérico mientras no exista una selección documentada.

Las bisagras actuales son la fuente de pose. Los cuernos se fijan a la superficie correspondiente; las varillas se dibujan entre puntos de unión transformados. Los brazos de servo acompañan el recorrido mediante una relación visual documentada. Comprobar variación de longitud: no representar una varilla rígida que se estira de forma perceptible para cerrar un mecanismo mal colocado. Si el esquema exige un reenvío, modelarlo. Este movimiento visual no introduce torque, holgura ni consumo en física.

La vista de mantenimiento pertenece al inspector del modelo: permite ocultar temporalmente ala/tapa para mostrar bandeja y servos. Debe restaurar el avión completo al cambiar de vista o volver a la aplicación. No requiere desmontaje interactivo, inventario ni una nueva interfaz de juego. Construir solo la estructura interior necesaria para sostener lo mostrado.

La manguera de combustible debe llegar al carburador y la de presión a su conexión correspondiente. Las rutas ocultas se pueden simplificar; las conexiones visibles deben resultar coherentes. La animación del gas se añade únicamente si el adaptador recibe esa señal; el mecanismo no modifica el control del motor del otro desarrollador.

## Implementación propuesta

Mantener el constructor nativo Godot. Separar el acabado y los detalles visuales de las cotas compartidas: una ficha de apariencia junto a `geometry.json` puede guardar paleta, distribución gráfica, materiales y procedencia; el dato geométrico mantiene dimensiones y pivotes. No abrir una arquitectura de variantes para esta entrega.

Para las cruces, crear un SVG propio como fuente editable y añadir UV a las mallas que lo necesiten. Evaluar un atlas opaco pequeño para marcas/recubrimiento, con márgenes entre islas y filtrado que no produzca halos. Empezar con una resolución de ensayo de 1.024 px, etiquetada como decisión artística; aumentar solo si falla la inspección cercana. El resultado debe ser reproducible desde los archivos fuente. Evitar depender de planos superpuestos casi coplanares que puedan parpadear. Cualquier técnica elegida debe funcionar en el renderizador Compatibility usado por la aplicación.

El material actualmente se cachea solo por color. Cambiar esa clave para incluir función/acabado cuando dos piezas compartan color pero necesiten rugosidad distinta; revisar los usos de `material()` y conservar la interfaz del adaptador. Agrupar geometría fija por material cuando sea útil; mantener separados únicamente los conjuntos que se articulan, se ocultan para inspección o requieren tratamiento distinto. No crear un nodo y un material por tornillo.

Los detalles de motor, mandos y tren pueden extraerse a funciones o archivos específicos si el constructor pierde claridad. `build()`, `root`, `propeller`, `hinges` y `gear` conservan sus contratos. No tocar masas, aerodinámica, posiciones de contacto ni simulación por razones cosméticas. Las posibles correcciones de silueta se documentan y vuelven a pasar las pruebas geométricas.

## Evidencia de aceptación

Guardar la siguiente revisión bajo `research/ugly-stik/model-v4/`, con ID de geometría/acabado y hashes del atlas, materiales, constructor, cámaras y poses. El inspector y el wrapper actuales tienen rutas de v3: adaptar su destino explícitamente antes de generar v4 y comprobar que las series v1/v2/v3 quedan preservadas.

La galería debe incluir las nueve vistas generales, macros del motor por ambos lados, raíz alar, tren, cuernos de cola y servos con acceso abierto. Repetir las 36 vistas a distancia para el acabado elegido. Añadir una secuencia breve de mandos que permita ver continuidad entre brazo, varilla y cuerno; una imagen neutra sola no prueba el montaje animado.

Criterios de cierre del trabajo local:

- Rojo y cruces coherentes en el avión completo; marcas legibles y sin errores al reflejar islas de UV o separar superficies móviles.
- Materiales distinguibles por iluminación y acabado; malla sin normales invertidas ni piezas sin apoyo.
- Mandos conectados en las poses comprobadas; los nuevos herrajes relevantes se incluyen en la revisión de interferencias, sin ampliar indiscriminadamente la lista de solapes permitidos.
- `compile_geometry.py --check` y `app/test.sh` pasan tras cambios integrados. Añadir pruebas solo para nuevos contratos de movimiento o defectos concretos; el color se comprueba visualmente.
- Clon limpio reproduce las capturas cuando se añadan texturas, importaciones o rutas. Registrar dependencias exactas si hicieran falta.
- Documentar incremento de coste frente a v3. La VM con llvmpipe permite comparar imágenes, pero el rendimiento objetivo sigue requiriendo medición en hardware real.

No se declara validada la orientación humana por generar las capturas. Las respuestas del ensayo se registran separadamente. Tampoco se exige que servos o tornillos sean visibles a 100 m: su criterio es la inspección cercana.

## Límites y colaboración

Este frente trabaja en `app/aircraft/`, `app/render/airplane.gd`, `assets/aircraft/`, investigación y documentación del modelo. El otro desarrollador conserva escena principal, cámaras de juego, física, datos de vuelo y contacto con suelo. La vista de mantenimiento se desarrolla en el inspector; cualquier conexión nueva a la aplicación se entrega mediante el adaptador y documentación.

Quedan fuera de esta pasada: mini/gigante, réplica certificada de un motor comercial, estructura interior completa, simulación mecánica de servos, humo/partículas, sonido y LOD automático sin una necesidad medida. Desenfoque de hélice y efectos de motor pueden evaluarse después de cerrar la apariencia estática y conocer la señal de RPM disponible.

**Primer paso ejecutable:** lámina de decoración y aplicación de rojo/cruces al modelo actual, con captura comparable de planta, intradós y tres cuartos. Después, primer plano del motor; luego transmisión y servos.
