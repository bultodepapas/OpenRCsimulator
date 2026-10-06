# Avanti S A200: mandos, tren y depósitos

2026-10-05 · Lectura del manual oficial de introducción y revisión visual del fotomanual. Aplica al **SebArt Avanti S Jet 2.2 m ARF original (A200, envergadura 2,00 m, largo 2,22 m)**; la turbina de referencia del plan es la JetCat P100-RX del catálogo 2017. No mezcla el A200 con el Avanti XS, Mini, FC/Krill ni el actual Avanti S anunciado como 2,3 m.

## Referencias que sí da el fabricante

La página PDF 1 de la introducción fija 200 cm de envergadura, 222 cm de longitud y 10,5 kg de peso RTF seco con P100. Describe fuselaje compuesto y alas/estabilizadores de madera. Son cotas generales de identidad; el documento no publica área alar, cuerda, MAC, perfiles, incidencias ni una planta dimensionada. [SebArt, ficha de producto](https://www.sebart.it/jets-L.html) · [Introducción oficial A200 (PDF)](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf) · [copia local](../../references/avanti-s/manuals/avanti-s-200-intro.pdf).

La PDF p. 2 enumera 9 canales mínimos y 8 servos digitales estándar: cinco DS8411 para alerones, elevadores y dirección de rueda; tres DS8911 para flaps y timón. Esto corresponde a dos alerones, dos mitades de elevador, dirección de rueda de morro, dos flaps y timón. Es una lectura de la lista de equipos, no una asignación oficial de canales del transmisor. Dos DS8915 y el tubo vectorial aparecen como **opcionales**. La selección de este plan usa P100 y tubo fijo; el fabricante asocia su opción vectorial al conjunto P180/vector A200-15. [Introducción, PDF p. 2](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf#page=2) · [página oficial de accesorios y fotos del tubo vectorial](https://www.sebart.it/img-jets/Avanti/VES/vector%20thrust.html).

La PDF p. 4 da estos recorridos máximos recomendados y modos de emisora:

| Superficie / ajuste | Dato del manual | Lectura para el rig |
| --- | --- | --- |
| Flaps, normal/pattern | 0° arriba | Posición FLIGHT del fotomanual, step 42 (step 41 presenta eje y palanca). |
| Flaps, START | 20° abajo; mezcla de elevador abajo 8% | Posición START, step 43. El porcentaje es una mezcla de emisora, no un ángulo publicado. |
| Flaps, LANDING | 50° abajo; mezcla de elevador abajo 20% | Posición LANDING, step 44. La secuencia y velocidad de despliegue no están documentadas. |
| Alerones | Hasta 30° arriba y 25° abajo, diferencial | Conservar lados independientes; no reducirlo a una bisagra común ni a recorridos simétricos. |
| Elevador | Hasta 30° arriba y abajo | Son dos servos de elevador según la lista de equipo. La sincronía entre mitades se representa como acoplamiento explícito. |
| Timón | Hasta 30° a izquierda y derecha | Servo propio. En p. 5 el fabricante añade mezcla lineal timón → elevador abajo de 1% a timón completo. |

Los `D/R` y `Expo` también impresos en p. 4 son ajustes de radio, no geometría: alerón 50/20 en normal, 100/60 en START/landing y 100/40 en 3D; elevador 50/40, 100/80 y 100/60; timón 80/60, 100/80 y 100/60. El manual advierte que el signo de expo cambia entre JR y Futaba. No convierto esos porcentajes a coeficientes de mando ni duplico el expo en Godot si la emisora ya lo aplica. [Introducción, PDF p. 4–5](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf#page=4).

## Mapa verificable del fotomanual

La [fotoinstrucción oficial de 91 páginas](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Photoinstriction.pdf) organiza dos fotos por página y rotula los pasos. Para seleccionar recortes locales, conserva juntas ambas cosas: imagen del componente y rótulo `step`; en las páginas con una cota, no recortes la cota ni sus flechas. La [copia local](../../references/avanti-s/manuals/avanti-s-200-assembly.pdf) sirve como origen estable de página y paso.

| Parte | Página PDF y pasos útiles | Qué muestra y qué no demuestra |
| --- | --- | --- |
| Alerones: bisagras, horns y varillaje | pp. 1–13, steps 01–26; cota de 60 mm en p. 8, step 16 | Montaje del mando y una longitud de varillaje. Los 60 mm no son cuerda ni recorrido del alerón. |
| Flaps: horn, brazos, extensión y servo | pp. 14–20, steps 27–40; brazo marcado 13 mm en p. 14, step 28; ajuste marcado 52 mm en p. 15, step 29; instalación/extension en p. 20, steps 39–40 | Ubica servo, palanca, anillo/link y prolongación. Las cotas son de armado del mando, no de la superficie aerodinámica. |
| Posiciones de flaps | pp. 21–22, steps 41–44 | El fotomanual presenta eje/palanca en step 41 y rotula FLIGHT, START y LANDING en steps 42–44. Para sus ángulos mandan los valores explícitos de la introducción (0/20/50°); las fotos oblicuas no sirven para medir ángulos por píxeles. |
| Tren principal y frenos | pp. 25–29, steps 49–58 | p. 25 nombra `Main L. Gear Installation`; p. 27 marca `Brake`; p. 28 incluye fittings/tubos. Las fotos no aportan cotas completas, presión neumática ni tiempos de extensión. |
| Tren delantero y puerta | pp. 30–36, steps 59–72 | Conjunto delantero, montaje y puerta retráctil; step 68 incluye 13 mm para el detalle de montaje de la puerta. La dirección de morro tiene servo separado en la lista de equipo. |
| Elevadores | pp. 37–45, steps 73–90; varilla 34 mm en p. 44, step 87 | Servo/varillaje y elevador; la cota de 34 mm es local al enlace, no cuerda o deflexión. |
| Timón | pp. 46–55, steps 91–110; varilla 39 mm en p. 50, step 99 | Servo y enlace de timón. La cota de 39 mm pertenece al varillaje fotografiado. |
| Línea neumática y ramales | p. 60, steps 119–120; pp. 71–72, steps 141–144 | p. 60 marca tubo de aire de 4 mm; p. 72 nombra `IN AIR`, `DOUBLE GEAR VALVE` y `SINGLE BREAK VALVE` (freno). Confirma funciones neumáticas, no el tiempo ni la presión de actuación. |
| Turbina / tubo | p. 66, steps 131–132 | Se ve el conjunto naranja de tubo y una turbina. La foto no identifica por sí sola la revisión JetCat ni el número de pieza A200. La introducción enumera tubo A200-13 como opcional para P100. |

## Aclaración de depósitos: neumática frente a keroseno/humo

La secuencia de la fotoinstrucción separa dos instalaciones que en una foto pequeña se pueden confundir:

1. **Neumática del tren/freno:** p. 69, steps 137–138, muestra dos cilindros blancos con líneas y válvulas. El paso siguiente, p. 70, step 139, aplica `Silicon` al montaje; step 140 cierra el acceso. Las líneas y cilindros reaparecen instalados en p. 71, steps 141–142, y conectan con las referencias explícitas de aire, doble válvula del tren y válvula sencilla del freno en p. 72, steps 143–144. La continuidad visual y los rótulos clasifican esos dos cilindros como depósitos de aire del sistema neumático. **No son los depósitos de combustible.** El manual no indica su volumen, presión, masa ni autonomía.
2. **Combustible y humo:** p. 73, steps 145–146, muestra otra instalación y rotula las conexiones `SUPPLY SMOKE`, `ONE ... SMOKE`, `TWO ... KERO`, `PUMP Smoke` y `PUMP Turbine`. La introducción p. 2 lista el tanque opcional A200-16 para keroseno + UAT + humo. Esto permite distinguir circuitos, pero no recuperar capacidad en litros, masa vacía/llena, volumen de la UAT ni curva de consumo de humo. Las [fotos oficiales del accesorio A200](https://www.sebart.it/img-jets/Avanti/Tank/tank-foto.html) amplían la referencia visual y de conexiones, no sustituyen una ficha dimensional.

Por tanto, no se debe estimar combustible tomando el diámetro de los cilindros de p. 69, ni deducir litros por el tamaño aparente de la foto p. 73. El valor de 10,5 kg está declarado como peso RTF **seco** con P100; no resuelve masa de combustible, posición del centro de gravedad al consumirlo ni masas separadas de turbina, baterías, depósito o accesorios.

## Proporciones: datos admitidos y límites

| Magnitud | Evidencia | Uso permitido |
| --- | --- | --- |
| Envergadura 2,00 m; largo 2,22 m | Introducción A200, PDF p. 1; también página del fabricante | Control de escala general. |
| Peso RTF seco 10,5 kg con P100 | Introducción A200, PDF p. 1 | Masa de referencia del avión configurado y seco; no masa en vuelo con combustible. |
| CG nominal 250 mm detrás del borde de ataque del ala, junto al fuselaje; 240 mm para jet beginner y 260 mm para 3D ilimitado | Introducción A200, PDF p. 5; foto de montaje p. 91, step 181 destaca 24/26 cm | Conservar datum, referencia y variante. 240 mm es el punto de partida indicado para principiante, no una coordenada corporal hasta construir el datum del ala. |
| 60, 52, 34 y 39 mm; 13 mm local | Fotomanual: p. 8 step 16 (alerón), pp. 14–15 steps 28–29 (flap), p. 44 step 87 (elevador), p. 50 step 99 (timón) | Medidas de enlaces/brazos dibujados. Mantenerlas en fichas de montaje con el recorte y sus extremos visibles; no usarlas para escalar el avión. |

Aunque SebArt dice que el diseño se basa en el Hawk, eso solo describe inspiración de diseño. Las fotos son de perspectiva; el fotomanual no es un plano de fabricación. Siguen sin fuente verificable: área y cuerda alar, MAC, perfiles, flecha, diedro, incidencias, estaciones de bisagra, tamaño de superficies, dimensiones de tomas/tubo instalado, coordenadas de tren respecto al CG, inercia y capacidades de depósitos. No fijar esas magnitudes midiendo píxeles en una vista oblicua o escalando el motor de una foto.

## Contrato visual y de mando propuesto para Godot

La jerarquía debe reflejar partes reales y conservar articulaciones de izquierda/derecha. Para una interfaz compatible con el estilo `build() → {root, hinges, ...}` del Ugly Stik, propongo nombres estables como:

```text
root
├── wing_left / wing_right
│   ├── aileron_left / aileron_right
│   └── flap_left / flap_right
├── elevator_left / elevator_right
├── rudder
├── gear { main_left, main_right, nose, doors... }
└── propulsion { turbine_mount, exhaust_axis, vector_nozzle? }
```

`vector_nozzle` solo existe si el perfil elige el accesorio vectorial; el Avanti P100 de referencia tiene salida y eje de empuje fijos. El adaptador temporal del [plan](../AVANTI-S-PLAN.md) puede conservar un nodo `propeller` vacío por compatibilidad, pero no dibuja una hélice ni reutiliza el giro de disco del Stik para representar la turbina. El transformador de entrada separa `roll`, `pitch`, `yaw`, `flap_setting`, `gear_command`, dirección de morro, freno y `throttle`. Aplica mezcla de flaps/elevador donde se decida, una sola vez y con sus unidades declaradas.

En una primera vista previa, basta con que todas las bisagras existan y acepten ángulo en radianes, y que el tren/puertas se muestren en una pose declarada. Para el primer vuelo, dejar explícita la configuración fija de flaps/tren si aún no existen sus estados. La entrada actual del simulador solo aporta roll/pitch/yaw/throttle; flaps y tren retráctil requieren estado de sesión separado antes de simularlos. El modelo visual no prueba que el avión vuele trimado: la aerodinámica debe conocer el estado de flap, y el tren visual requiere contacto/actuación para simular despegue o aterrizaje.

## Pendientes para cerrar con evidencia

- Confirmar el marco local de coordenadas, pivotes y signos de todas las bisagras al crear la maqueta nativa; medir o documentar qué cota del A200 fija la escala de cada panel.
- Identificar las superficies físicas de cada servo del elevador y del nose steering, y escoger el mapeo de canales para una emisora concreta. El manual solo da cantidad/modelo y grupos, no canales.
- Saber si las mezclas de elevador del flap (8%/20%) se definen respecto al recorrido del canal, del servo o a otra configuración de emisora antes de mapearlas a grados.
- Conseguir planta/vistas calibradas, cuerda/MAC, incidencias, coordenadas y volúmenes del A200. Las fotos del tanque opcional documentan conexiones, no capacidad.
- Medir presión y tiempo de retracción del tren, tiempo de flap/servo, recorrido de puertas, ruedas/frenos y masa/ubicación de los sistemas. No aparecen en los documentos consultados.
- Verificar en el ejemplar de referencia el montaje P100, salida del tubo, eje y línea de empuje relativa al CG; el manual muestra fotos, no una cota de instalación. El dato de catálogo de la turbina no determina esos anclajes.
- Tratar por separado el accesorio vectorial: límites angulares, orientación, servos y ley de mando no están acotados en los materiales consultados.

Fuentes primarias consultadas: [página SebArt Avanti S](https://www.sebart.it/jets-L.html), [manual de introducción A200](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf), [fotoinstrucción A200](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Photoinstriction.pdf), [galería del tanque](https://www.sebart.it/img-jets/Avanti/Tank/tank-foto.html) y [galería del tubo vectorial](https://www.sebart.it/img-jets/Avanti/VES/vector%20thrust.html). Todas las cantidades y límites anteriores se asocian a página PDF y step para que puedan revisarse junto al recorte original.
