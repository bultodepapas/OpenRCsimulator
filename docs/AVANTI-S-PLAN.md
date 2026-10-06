# Avanti S de turbina: plan del siguiente avión

2026-10-06 · Revisión 4 · **AV-00 completo; AV-01 provisional; AV-02 en la app (AV-03): vista previa en el menú, «Volar» desactivado hasta la rama de turbina (AV-05).**

La variante elegida es el **SebArt Avanti S A200 original**, documentado como «Avanti S Jet 2.2m»: **2,00 m de envergadura y 2,22 m de longitud**, con instalación inicial **JetCat P100-RX, ficha de referencia 2017, y tobera fija**. La documentación original permite identificarlo mejor que una mezcla de versiones comerciales actuales. El catálogo reciente usa también «2.3m»; esa etiqueta no autoriza a cambiar las dimensiones del manual elegido. [Manual SebArt](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf), [catálogo actual](https://www.sebart.it/download/sebart-pricelist.pdf).

Este plan atiende la petición actual de un jet como candidato al siguiente avión tras el Ugly Stik. El [plan Extra 300](EXTRA-300-PLAN.md) conserva su investigación; ambos deben compartir el futuro catálogo, sin duplicar la selección de aeronaves. **La primera entrega del Avanti será una vista previa sencilla; el primer vuelo físico necesita una propulsión nueva.**

[Familia y elección](research/avanti-s-family-research.md) · [Recursos locales y lectura visual](research/avanti-s-resources.md) · [Auditoría de integración](research/avanti-s-integration-audit.md) · [Turbina y límites físicos](research/avanti-s-turbine-research.md) · [Galería local](../references/avanti-s/index.html).

## 1. Identidad, popularidad y alcance

El Freewing Avanti S 80 mm EDF tiene señales públicas de difusión comercial, pero corresponde a otra construcción, tamaño y propulsión. No hay en esta investigación un censo verificable que ordene ventas de todos los Avanti de turbina. La elección del A200 se basa en documentación e identidad de turbina, no en atribuirle el título de más vendido. La [comparación de variantes](research/avanti-s-family-research.md) distingue A200, XS, Mini, XXL, composite y EDF.

ID de catálogo: `sebart-avanti-s-a200-p100rx`. Registrar por separado revisión geométrica, instalación de motor, condición de combustible y configuración de mandos. El P100-RX original y el P100-RX-BL actual tienen documentos con diferencias; no combinar dimensiones, RPM y comportamiento sin registrar la edición de origen.

La primera configuración volable comienza **ya en vuelo**, turbina estabilizada, flaps arriba, tren recogido y masa de una condición de combustible declarada. Se prueba vuelo nivelado, virajes, ascenso/descenso y respuesta al acelerador. Posteriormente se añaden flaps y retráctiles funcionales. Taxi, aterrizaje, frenos, arranque completo de ECU, fallos detallados, humo y empuje vectorial pertenecen a entregas posteriores.

La cámara sigue siendo la del piloto RC en tierra. La experiencia debe comunicar mayor inercia y respuesta del motor con retardo mediante dinámica y sonido coherentes; no aumentar arbitrariamente velocidad o sensibilidad para que «parezca jet». El avión mantiene las reglas de radio, armado, pausa, reinicio y grabación existentes.

## 2. Qué se conserva del Ugly Stik

| Evidencia o método aprendido | Aplicación concreta al Avanti |
| --- | --- |
| Geometría declarativa y compilación reproducible | Fuente original por estaciones/contornos; unidades y procedencia separadas de la malla |
| Medición por vista y cotas reservadas | Las fotografías son perspectivas; ninguna anchura oculta se presenta como medida |
| Datum visual diferente del CG | Transformación explícita del CG y línea de empuje de este avión |
| Root, pivotes y signos comprobados | Bisagras oblicuas, elevadores partidos y flaps con marcos propios |
| Contención además de distancia entre superficies | Revisar ala/fuselaje, flaps, timón, elevadores y recorrido del tren |
| Capturas con pose restablecida y manifiesto | Nuevas suites Avanti; conservar evidencia y goldens Stik |
| Librea evaluada desde tierra | Separar vistas superior/inferior, fondos y distancia; no confundir hashes con lectura humana |
| Cachés de materiales inmutables | Alternar Stik/Avanti sin contaminación de textura o estado |
| Loader estricto y física float64 | Añadir un tipo de propulsión sin burlar validaciones de la hélice |

Antecedentes: [plan Stik](UGLY-STIK-PLAN.md), [metrología](research/ugly-stik-model-v3-metrology.md), [mandos v4](research/ugly-stik-model-v4-controls.md), [doce investigaciones de herramientas](research/extra-aircraft-tooling/README.md) y [lecciones](../LEARNINGS.md). Los números de pruebas de esos informes son históricos, no resultados nuevos de esta entrega.

## 3. Fuentes, medición y límites

Se reunieron manual introductorio, 91 páginas de montaje, fotos oficiales de suelo/vuelo y dibujos acotados de motor/abrazadera. **No se encontró un plano constructivo completo ni CAD calibrado del A200.** Los planos del motor no fijan las secciones del fuselaje. Los manuales Mini y catálogo se archivan como comparación, nunca como geometría intercambiable.

Primera sesión de geometría AV-01:

1. Definir origen en la intersección del borde de ataque de referencia con el fuselaje, y registrar dónde está esa referencia sobre un ala en flecha. El montaje p.91 muestra el datum del CG; no lo sustituye un porcentaje de cuerda supuesto.
2. Medir planta, perfil, frente, empennaje, tomas laterales, raíz y puntas alares. Registrar imagen/página/hash, puntos, incertidumbre y transformación. Clasificar cada cota como nominal de manual, derivada o estimada.
3. Conservar una tabla de secciones de fuselaje y un conjunto reducido de cotas de control; reservar vistas y detalles que no intervengan en el ajuste. Una homografía sirve para una superficie aproximadamente plana, no para recuperar el volumen entero de una foto.
4. Obtener área de referencia y cuerda `S/b` de la planta declarada. Registrar MAC y su posición aparte. Mantener la convención de normalización del simulador o migrarla explícitamente; no introducir MAC en un campo que actualmente exige `b·c = S`.
5. Construir bloque visual a escala. Si faltan secciones, marcar el volumen como aproximación; no bloquear una vista previa por ausencia de metrología completa.

La masa publicada **10,5 kg RTF dry con P100** no es masa en vuelo con tanque lleno. La configuración necesita un inventario coherente y una cantidad de combustible identificada; el volumen del tanque no quedó establecido en las fuentes A200 consultadas. No sumar otra vez turbina/baterías a una cifra que ya las incluye. Las inercias de la piel exterior tampoco representan un fuselaje hueco y su equipo interno.

Faltan perfiles identificados, polares, derivadas, área alar calibrada, masa/inercia de una instalación concreta y curvas de respuesta de turbina. XFOIL/AVL pueden contrastar estimaciones de flujo adherido después de fijar geometría; no validan pérdida dinámica ni acrobacia por sí solos.

## 4. Construcción visual en Godot

Conservar **Godot 4.7.2, Compatibility y el constructor nativo**. Rutas (creadas en AV-02/AV-03): `assets/aircraft/avanti-s-a200/geometry.json`, `appearance.json`, compiladores y `app/aircraft/avanti_s_*`. Compartir únicamente helpers que ambos constructores necesiten; la geometría del ala rectangular Stik no se reutiliza como si fuera el ala Avanti.

Orden visual: fuselaje por estaciones → ala baja en flecha y uniones → cola → cabina → tomas y salida → superficies separadas → tren → acabado. Cerrar la boca de admisión con profundidad visual controlada y salida tubular; no detallar compresor oculto antes de lograr una silueta reconocible. Usar fotos de mantenimiento para ubicar masas y anclajes, sin afirmar qué turbina aparece en una foto si no se identifica.

La librea inicial propuesta es **blanco/azul/rojo clásica**, respaldada por galerías oficiales. Cabina inicialmente opaca estilizada; comparar transparencia más adelante bajo Compatibility. La foto en alabeo ayuda a distinguir decoración inferior; no espejar automáticamente la superior. [Galerías y observaciones](research/avanti-s-resources.md).

Las superficies móviles reciben deflexiones escalares sobre ejes locales, conservando su transformación neutra. Para un eje expresado en el padre, la orientación compone delta y reposo en ese orden; no se sustituye toda la orientación por una rotación aislada. Los dos elevadores pueden compartir orden física al principio y seguir como mallas/pivotes distintos. Flaps, puertas y patas tienen estado propio, no son alias del canal de cabeceo.

Conservar nombres/interfaz Stik. Como transición, el Avanti puede devolver un nodo `propeller` vacío e inmóvil para el contrato existente, con capacidad visual explícita `has_propeller=false`. El render no debe suponer que RPM implica una hélice exterior. Los helpers de giro, sonido y momento rotor se seleccionan por propulsión, no por el nombre del nodo vacío. Posteriormente un contrato versionado puede hacer opcional esa referencia sin romper los consumidores antiguos.

El inspector y la sombra reciben geometría, encuadres y datum Avanti. `shadow.gd` calcula extensión desde mallas pero su máscara sigue siendo Stik: sustituirla por contorno propio o una máscara generada una vez, no recalcular imágenes de GPU cada frame. Comparar lectura a 20/50/100 m y añadir mayores distancias si el régimen de vuelo lo requiere. Mantener autozoom y campo visual registrados.

## 5. Propulsión: cambio necesario antes de volar

El módulo actual calcula empuje y par mediante `Ct(J)`, `Cp(J)` y diámetro de hélice. El loader limita RPM con valores del motor de combustión y exige esa hélice. **Subir el límite de RPM y poner una hélice invisible no constituye un modelo de turbina.** Además de `Propulsion`, deben cambiar los consumidores de trim, sesión, HUD y sonido. [Auditoría](research/avanti-s-integration-audit.md).

Propuesta de datos: introducir `openrc-aircraft v2` con discriminador `propulsion.kind` (`glow_prop`/`turbine`) y conservar lectura de v1 con interpretación legacy explícita. Validar cada rama por separado, con `{value, unit, kind, source}` en cada magnitud. Rechazar campos incompatibles y tipos desconocidos. No migrar todos los JSON existentes para abrir la primera vista previa.

La frontera de propulsión debe ofrecer estado inicial/estacionario, evolución por tick, cargas y telemetría coherentes. Stik continúa llamando al comportamiento anterior mediante la rama `glow_prop`; el trim usa el mismo cálculo estacionario que las cargas de vuelo. La física conserva arrays y escalares de 64 bits a 240 Hz.

Primer modelo de turbina propuesto:

- Estado de funcionamiento y spool independiente del acelerador. Curva de empuje estacionario y tiempos de subida/bajada con procedencia; constantes desconocidas se etiquetan como estimadas y se barren en sensibilidad.
- Empuje residual de ralentí distinto de motor parado. No deducir `T ∝ RPM²` de dos puntos extremos ni usar la velocidad del chorro como velocidad del avión.
- Fuerza sobre eje de instalación y momento `r × F` respecto al CG. Tobera fija al inicio; sin copiar par de hélice ni propwash. La aproximación al momento giroscópico interno se declara aparte hasta conocer inercia/velocidad del rotor pertinente.
- Modelo inicial de envolvente limitada, con condiciones atmosféricas y de velocidad declaradas. Los datos estáticos de banco no prueban empuje instalado en vuelo: admisión, conducto, ram drag y condiciones de aire requieren contraste posterior.
- En pausa se congelan spool y relojes físicos; reset restablece estados. Un corte tiene su evolución declarada; no se presupone desaparición instantánea del empuje residual.

La [investigación JetCat](research/avanti-s-turbine-research.md) separa prestaciones históricas, dibujos posteriores y ficha RX-BL. Es documentación para modelar el simulador; la primera entrega no pretende emular toda la ECU ni su secuencia de arranque.

## 6. Aerodinámica, combustible y mandos

Definir un perfil estable con CG conservador dentro de la referencia del manual, y una velocidad inicial que resulte del trim de **este** avión. No heredar 15 m/s del Stik ni usar la velocidad máxima recomendada como condición de arranque. Antes de aceptar vuelo, comprobar empuje disponible, sustentación, mando de trim y margen respecto a pérdida. El solver actual protege una región lineal; si los datos nuevos la contradicen, revisar el contrato con una prueba independiente en lugar de falsificar CL máximo.

La primera masa puede permanecer fija durante vuelos cortos, pero representa combustible declarado y conserva su balance. El consumo dinámico se añade en una entrega propia: cambia masa, centro de gravedad e inercia de manera consistente. Mover solamente el CG dibujado o reducir únicamente masa total produciría un estado incoherente.

El manual describe alerones diferenciales y flaps con mezclas de elevador. Es una brecha real respecto a los recorridos simétricos actuales: separar subida/bajada y punto de medida. Guardar rates/expo/mixes como configuración de control, sin duplicar expo de la emisora ni tratar porcentaje de mezcla como coeficiente aerodinámico. Primero comprobar signos geométricos; después aplicar efectos físicos. [Referencia de mandos SebArt](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf).

Flaps necesitan deflexión real limitada por actuador y cambios de cargas/pérdida/trim identificados. Retráctiles necesitan fracción de extensión, tiempos, puertas y estados terminales; cuando sean funcionales, resistencia y hull deben corresponder al estado. Hasta ese paso, tren/flaps se mantienen en configuración fija y la interfaz lo indica. No mostrar un interruptor operativo cuyo único efecto sea mover una malla.

Conservar AETR como mínimo. Flaps/tren usan asignaciones opcionales de ejes o botones, estados seguros al conectar y teclado equivalente; no tomar canales empleados por calibración, bomba de humo o futuras funciones. Coordinar [menú](MENU-PLAN.md) y [humo](SMOKE-PLAN.md), que siguen siendo trabajos separados. En la desconexión, el sistema conserva su failsafe y pausa; reanudar no salta spool ni posición del tren.

## 7. Sonido, cámara y límites de producto

El sonido actual sintetiza un monocilíndrico de dos tiempos. Crear una voz procedural provisional de turbina, o integrar audio con licencia y procedencia comprobadas: componentes de tono/ruido gobernados por spool y carga, ganancias limitadas y congelación coherente con pausa. No descargar audio de vídeos y presentarlo como recurso del juego. El material recopilado aquí sigue siendo referencia local.

La sensación de jet exige revisar distancia útil de cámara, lectura de velocidad, orientación y trayectoria. Evaluar maniobras conservadoras con el piloto; mayor rapidez de traslación no debe hacer que el avión desaparezca constantemente del encuadre. Trazas y capturas registran ID, revisión y condición inicial efectivos.

El contacto con terreno actualmente es accidente. Entrenamiento de aterrizajes, rodaje, frenos y suspensión dependen del trabajo E1/E2, no de modelar unas ruedas retráctiles. Empuje vectorial/P180, hover, giros extremos, vibraciones y flutter se aplazan. La documentación comercial de maniobras no es validación del simulador.

## 8. Entregas y pruebas

**AV-00** está completo. **AV-02** está integrada en la app como vista previa (AV-03 ✅); sus contornos siguen en refinamiento (revisiones 2–4, más abajo). **AV-01** tiene preparación concreta: 30 datos trazables, cuatro proporciones, 42 recortes del montaje y un panel interactivo de tamaños/mandos. Falta cerrar contornos, secciones, área y ejes de bisagra. Véanse la [ficha AV-01](research/avanti-s-av01-metrology.md), la [mesa de referencias](../references/avanti-s/organized/index.html) y los [datos y herramienta](../research/avanti-s/av01/README.md). Los demás pasos siguen ligados a hitos existentes del [roadmap](../ROADMAP.md).

| Paso | Cambio acotado | Dependencia | Prueba requerida |
| --- | --- | --- | --- |
| AV-00 · preparación D1 | Elegir versión y archivar evidencia | — | Fuentes abiertas, archivos válidos, hashes y exclusión Git comprobados |
| AV-01 · D1 | Datum y geometría mínima | AV-00 | Cotas con procedencia, límites y controles reservados; discrepancias visibles |
| AV-02 · D1 visual | Jet sencillo en inspector | AV-01 | Frente/perfil/planta/oblicua, escala, uniones y Stik intacto |
| AV-03 · D1/UI-05 ✅ | Catálogo y adaptador sin hélice | AV-02 | Stik → Avanti preview → Stik; ID erróneo rechazado; materiales y nodos independientes |
| AV-04 · B5 | Rig y recorridos reales | AV-02 | Neutro/extremos/combinaciones; alerón diferencial, dos elevadores, holguras y defecto deliberado detectado en copia |
| AV-05 · D5 / propulsión nueva (sin equivalente en G1–G4) | Rama de turbina y datos v2 | AV-03 | Unidad de empuje, ejes, lag, idle/stop/reset/pausa; split de timestep; v1 y goldens Stik conservados |
| AV-06 · D1–D4 | Masa, referencias aero y trim | AV-01/05 | Loader, CG/inercia, condición de combustible y solución estacionaria propia |
| AV-07 · D8a/D10 | Primer vuelo experimental | AV-04/06 | 30 s sin mando, virajes y escalones de throttle; estados finitos; 30/60/144 fps; radio/failsafe/traza |
| AV-08 · D7/Gate 2 | Acabado y sonido de turbina | AV-02/05 | Capturas iguales por condición, pausa estable, lectura humana cielo/suelo y coste GPU identificado |
| AV-09 · controles/E0a–E0b | Flaps y tren funcionales en vuelo | AV-07 | Entradas opcionales, límites de actuador, trim/drag/hull por estado; no duplicar expo |
| AV-10 · G4 | Consumo y balance variables | AV-07 | Integración de flujo, depósito no negativo y masa/CG/inercia consistentes; reinicio reproducible |
| AV-11 · D8b/Gate 2 | Contraste independiente | AV-07/09 | Observaciones de configuración comparable, sensibilidad y límites de envolvente documentados |
| AV-12 · PT1/UI-05 | Entrega de dos aviones | AV-07/08; límites AV-09/10 explícitos | Clon limpio, import/export, smoke por ID, suite completa y captura con renderer; sin depender de `references/` |
| AV-13 · E1/E2 y futuro | Contacto, frenos, vectorial y ECU ampliada | Hitos físicos respectivos | Ensayos propios; no bloquear la vista previa ni prometerlos en el primer vuelo |

Las tolerancias físicas y presupuestos de rendimiento se fijan antes de ajustar, contra la evidencia disponible. Si falta contraste independiente, la ficha conserva **experimental**. El número de tests o un trim convergente no acreditan fidelidad a una turbina real.

## 9. Riesgos y siguiente acción

El mayor cambio respecto al Extra es separar propulsión de hélice y turbina en todos sus consumidores. La mayor carencia de referencia es geometría dimensionada del fuselaje/ala completos. Se controla con una primera forma aproximada declarada, datos físicos separados y pruebas de regresión Stik.

Ya existe una [maqueta Godot aislada AV-02](research/avanti-s-av02-preview.md), con siete superficies articuladas, controles de escala, nueve capturas y prueba en clon sin referencias. Todas las secciones no documentadas están identificadas como estimaciones. Falta refinarla e integrarla; AV-02 y AV-04 no se consideran completos.

La siguiente acción es **cerrar AV-01 y los contornos de AV-02** (la integración AV-03 ya está hecha): usar el datum longitudinal propuesto y las cotas documentadas para construir contornos y un volumen aproximado declarado, fijar los ejes de las superficies y mostrar un Avanti básico en el inspector. El archivo ya separa neumática, tanque de queroseno/humo y escape vectorial opcional. Ese trabajo no necesita integrar consumo, tren funcional o una ECU completa. Antes del primer vuelo se cierra AV-05 con una rama de turbina comprobable.

## Comparación de siluetas por transparencia — 2026-10-06

La maqueta AV-02 ya se compara con tres fotos mediante [superposiciones interactivas](../references/avanti-s/alignment/index.html). Se ajusta una cámara por foto conservando geometría, imágenes originales y puntos reservados. [Método, errores y diferencias detectadas](research/avanti-s-transparency-comparison.md). Es una ayuda para refinar contornos; no cierra la metrología ni acredita área/perfiles. La próxima edición debe contrastar los tres encuadres y guardar el efecto de cualquier reajuste de cámara.

## Afinado AV-02 con cámaras congeladas — 2026-10-06

La [segunda revisión de contornos](research/avanti-s-contour-refinement.md) reduce cuerda alar, perfila puntas/estabilizador, prolonga la transición de deriva e integra las tomas. Conserva escala nominal, siete bisagras y cámaras anteriores; incluye comparación antes/después, muestras de borde y clon limpio sin referencias. Las tres vistas mejoran en las muestras del ala, mientras fuselaje/cabina y cola posterior mantienen diferencias. Sigue siendo una geometría visual estimada; quedan metrología, detalle, comprobación de volúmenes barridos e integración.

## Continuidad de fuselaje y cabina — revisión 3

La [tercera revisión](research/avanti-s-contour-refinement-v3.md) estrecha moderadamente el cuerpo delantero, ajusta cabina e interpola secciones con normales suaves. Las muestras del fuselaje mejoran en frontal y posterior; el perfil y la cola siguen limitando el ajuste. Se conservan cámaras y siete bisagras. La comparación usa v2 como referencia; siguen pendientes metrología e integración AV-02.

## Referencias complementarias y tres ángulos nuevos — 2026-10-06

La [nueva selección](research/avanti-s-new-angles.md) añade 30 fotografías oficiales, lámina comercial de tres vistas y reportaje Aerotec. Compara frontal baja, oblicua frontal alta e intradós en vuelo con la geometría v3 intacta. La frontal prioriza revisar sección de vientre y tomas; el intradós es exploratorio por mandos desconocidos y mayor residuo. Las cámaras anteriores permanecen congeladas y los nuevos recursos son exclusivamente locales.

## Detalles y siete cámaras congeladas — revisión 4

La [cuarta revisión AV-02](research/avanti-s-refinement-v4.md) ajusta moderadamente cabina/deriva y añade marcos, placas alares y una salida con cavidad. Siete superposiciones v3→v4 muestran mejora parcial en perfil y diferencias persistentes en lomo, frontal baja y cola posterior. Las placas tienen holgura local comprobada frente al alerón en cinco órdenes de alabeo. La maqueta está integrada como vista previa (AV-03); no cierra integración, vuelo, tren ni volumen barrido completo.

## En la app como vista previa (AV-03) — 2026-10-06

La maqueta AV-02 (`a200-av02-contours-03`) vive ahora en la app: [`avanti_s_model.gd`](../app/aircraft/avanti_s_model.gd) con geometría compilada desde [`assets/aircraft/avanti-s-a200/`](../assets/aircraft/avanti-s-a200/README.md); vértices idénticos a AV-02 (mismo SHA-256 de mallas, normales, materiales y bisagras). El catálogo lo ofrece en Inicio como **vista previa**: se ve en el fondo y en la ficha, pero «Volar» está desactivado y explica que la turbina aún no se simula. La ruta directa lo rechaza salvo con `--scripted` (círculo visual, sin física). `render/airplane.gd` traduce las deflexiones comunes a sus siete bisagras (dos elevadores; flaps quietos, `set_flaps()` preparado) y no hace girar ningún disco de hélice.

Prueba: `verify_avanti.gd` (137 comprobaciones en `app/test.sh`, dos mutaciones de signo detectadas), `test_aircraft_catalog.gd`, `test_ui_aircraft.gd`. **Siguiente para volar:** AV-05 (rama de turbina y datos v2) y AV-06 (masa, referencias y trim); el catálogo solo necesitará la ruta de datos y cambiar el estado.
