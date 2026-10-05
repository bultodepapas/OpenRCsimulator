# Avanti S turbina: auditoría de integración con el Ugly Stik

2026-10-05 · Inspección del árbol actual y de los planes existentes. **Sin cambios en `app/` y sin ejecutar tests o vuelos.** Esta nota evalúa la costura técnica para un segundo avión; no valida todavía datos ni comportamiento de una variante Avanti concreta.

## Conclusión

El simulador ya tiene piezas reutilizables para cargar datos propios, calcular un trim, simular en paso fijo y representar una geometría nativa. Todavía no tiene catálogo ni contrato multiavión: `main.gd`, el constructor visual, el datum del CG y la propulsión se resuelven alrededor del Jensen Ugly Stik. Para el Avanti S hay que separar primero **definición del avión**, **geometría y transformación visual**, **modelo de motor**, y **configuración de inicio**. No conviene disfrazar la turbina como una hélice ni cambiar los parámetros del Stik para hacer caber al nuevo avión.

La continuidad más útil con el trabajo actual es conservar el flujo del modelo: fuente geométrica declarativa con procedencia → generador verificable → constructor nativo → inspector y capturas. Ese flujo está descrito en el [README del modelo Ugly Stik](../../assets/aircraft/ugly-stik-60/README.md); su jerarquía `build() → {root, propeller, hinges}` es hoy un contrato activo, aunque sea específico a un avión con hélice.

## Qué existe ahora

| Área | Comportamiento observado |
| --- | --- |
| Runtime | [get-godot.sh](../../app/get-godot.sh) fija Godot **4.7.2-stable**; [project.godot](../../app/project.godot) usa renderer **Compatibility**. La simulación conserva `float64` en `sim/` y `physics/`, con guard en [test.sh](../../app/test.sh). El Avanti comparte este contrato, sin convertir vectores de simulación a tipos 3D de 32 bits. |
| Avión visual | [airplane.gd](../../app/render/airplane.gd) precarga `ugly_stik_model.gd`; su `build()` no recibe ID ni definición. El constructor devuelve `root`, `propeller`, `hinges`, además de pivotes `gear` y mecanismos visuales `controls`. |
| Escena | [main.gd](../../app/main.gd) construye el avión antes de crear la sesión física, y luego `FlightSession.setup()` carga el JSON por defecto de [scenarios.gd](../../app/sim/scenarios.gd). No existe una resolución común ID → constructor + geometría + datos. |
| Datos físicos | `openrc-aircraft v1` valida unidades, procedencia, inventario, aerodinámica, propulsión, superficies y `crash_hull` en [aircraft_data.gd](../../app/physics/aircraft_data.gd). El formato de masas y geometría se ancla al marco LE del avión. |
| Propulsión | [propulsion.gd](../../app/physics/propulsion.gd) implementa RPM objetivo lineal desde throttle, un lag de primer orden y cargas de hélice calculadas con `Ct(J)` / `Cp(J)`. La fuerza es axial en el cuerpo; el offset produce brazo y el par de reacción se aplica sobre X. |
| Sesión y trim | [flight_session.gd](../../app/sim/flight_session.gd) recibe una ruta de JSON y utiliza masa, inercia, fuerzas, trims, comandos y estado de motor de ese modelo. [trim.gd](../../app/physics/trim.gd) admite una velocidad de trim explícita; las funciones de [scenarios.gd](../../app/sim/scenarios.gd) usan 15 m/s como valor por defecto. |
| Controles | El canal de vuelo es roll, pitch, yaw y throttle. El JSON admite recorridos de alerón, elevador y timón, y una velocidad común de servo; no hay orden de flaps ni de tren retráctil en [commands.gd](../../app/input/commands.gd) o el cargador de datos. |
| Suelo | [flight_session.gd](../../app/sim/flight_session.gd) declara accidente si cualquier punto de `crash_hull` toca el terreno. No hay contacto, rueda, taxi ni aterrizaje; esos pasos siguen en M2. |
| Traza | [trace.gd](../../app/sim/trace.gd) escribe `openrc-trace v3`, con comandos, RPM de motor y posiciones de tres servos. `FlightSession.trace_meta()` todavía describe nivelado a 15 m/s y nombra la ruta fija del Stik. |

## Bloqueos y decisiones para el Avanti

### Selector y propiedad de datos

`main.gd` usa `AirplaneBuilder.build()` sin argumento y calcula el CG visual desde `Geometry.DATA` del Stik. `FlightSession.setup(path)` permite otra ruta JSON, pero esa flexibilidad no selecciona constructor, geometría, anclajes o condiciones iniciales junto con el archivo físico. La nueva definición debe resolverlos atómicamente antes de crear el modelo y la sesión; un ID desconocido o dato inválido no debe dejar un modelo de un avión volando con la física del otro.

La [auditoría de integración Extra 300](extra-300-integration-audit.md) ya propone un registro pequeño de definiciones y sustitución de sesión entre vuelos. Reutilizar esa dirección y preservar el default del Ugly Stik para CLI, pruebas y capturas existentes. No editar ni retirar [EXTRA-300-PLAN.md](../EXTRA-300-PLAN.md): es un plan separado, con sus propios datos y estado.

### Compatibilidad temporal del nodo `propeller`

`main.gd::_render_pose()` asigna `rotation.z` directamente a `_airplane.propeller` en cada actualización, y el contrato de `airplane.gd::build()` lo marca como salida requerida. Por eso el Avanti no puede devolver simplemente una definición sin `propeller` mientras siga vivo ese consumidor.

Para una primera integración se puede conservar la clave con un `Node3D` vacío, no visible y sin disco animado. Es un adaptador de compatibilidad, no una hélice falsa ni un modelo de turbina. La evolución limpia es hacer que el constructor exponga un nodo o adaptador visual de propulsión opcional (`propeller` solo para hélices) y que el render no acceda a él cuando no existe. Un rotor de turbina o una tobera no debe girar con el ángulo de disco de hélice.

### Turbina: empuje, lag, par, giro y sonido

El cargador actual exige `propulsion.propeller.diameter`, `thrust_line_offset`, `rotating_inertia`, tablas positivas de `ct_table` y tablas `cp_table`; `Propulsion.loads()` calcula empuje, potencia, torque y brazo con esa hipótesis. El avance D5 usa un lag e idle genéricos, pero las magnitudes y la salida siguen siendo RPM de motor + hélice, no un estado de turbina calibrado.

El perfil del Avanti debe representar empuje neto de turbina en función del mando (y de la velocidad/condición que respalden las fuentes), spool/lag e idle/parada con datos trazables. El vector de empuje debe usar el eje real de instalación y trasladar el momento desde la tobera o montaje hasta el CG. No aplicar `Ct/Cp`, torque de hélice ni momento giroscópico del disco de hélice al motor a reacción. Mantener intacto el perfil glow del Stik; si se extiende `openrc-aircraft`, hacerlo con un tipo de propulsión explícito y validación separada, no con campos de hélice ficticios.

Hay además dos acoplamientos visuales que requieren adaptación. El ángulo de `propeller` se integra desde RPM en [main.gd](../../app/main.gd), y [engine_sound.gd](../../app/render/engine_sound.gd) sintetiza el zumbido de un monocilíndrico dos tiempos con frecuencia `rpm / 60`. Un spool de turbina no puede conectarse a esa frecuencia como si fuese la nota acústica: separar velocidad de disco, estado de spool y parámetro de sonido. La fase G3 del [roadmap](../../ROADMAP.md) reemplaza el sonido provisional del Stik; no resuelve por sí sola el perfil específico de turbina.

### Propwash no equivale al chorro de una turbina

[aero.gd](../../app/physics/aero.gd) no modela propwash; el roadmap mueve el acoplamiento de cola para hélice a M2/E0b. El Avanti no debe heredar artificialmente ese incremento de velocidad detrás de una hélice. Si se decide simular el efecto de escape o chorro sobre una superficie, debe tener geometría, alcance e intensidad propios y evidencia; puede quedar fuera del primer vuelo trimado.

### Alas en flecha, cuerda y datum

En `openrc-aircraft v1`, `mean_chord` tiene que satisfacer `wing_span × mean_chord ≈ wing_area` con 1 % de tolerancia. [aero.gd](../../app/physics/aero.gd) usa `reference.c` al dimensionalizar amortiguamiento de cabeceo y momento de cabeceo, mientras usa `b` para los términos laterales. En un ala en flecha, `S / b` es una convención de referencia compatible con el contrato actual, pero no es la cuerda aerodinámica media geométrica (MAC). Guardar la MAC en `mean_chord` produciría rechazo del loader o referencias de momento incoherentes.

Antes del JSON definitivo, fijar la planta y los ejes desde recursos del modelo RC seleccionado. Documentar aparte `S/b`, MAC, borde de ataque de MAC, punto aerodinámico, CG, montaje de motor y origen visual; normalizar cada coeficiente respecto a las referencias declaradas. El datum importa también al render: `main.gd::_update_cg_model()` combina `cg_le` con el leading edge y la altura de eje específicos del Ugly Stik. El Avanti necesita anclajes propios y una prueba de que su punto CG visual cae en la posición CG de la simulación.

### Flaps, actuadores y tren retráctil

El sistema actual solo convierte roll/pitch/yaw en las tres superficies primarias. Las bisagras del adaptador son `aileron_left`, `aileron_right`, `elevator` y `rudder`; la función `apply_gear()` solo recibe ángulos de ruedas y dirección y asume `left/right/nose`. No hay estado desplegado/retraído, mando de flaps ni actuadores independientes. El mecanismo visual de Ugly Stik resuelve sus propios varillajes y no es un mecanismo genérico para las superficies del Avanti.

No mapear flaps a pitch ni al actuador de elevador, ni usar las rotaciones de rueda como estado de tren. Cada grupo necesita su propia orden, estado real del actuador y articulación visual; la aerodinámica debe conocer la configuración de flaps antes de que se ofrezca como opción volable. Para la primera versión volable, fijar y declarar una sola configuración (flaps arriba y tren en la posición que corresponda al escenario elegido); después añadir mandos separados y una velocidad/recorrido por actuador. El canal de entrada actual no ofrece esos mandos.

### Masa, combustible e inercia

La masa e inercia se derivan una vez del inventario al cargar el JSON y se guardan en `Simulation`; no cambian durante el vuelo. El propio inventario del Stik representa combustible como una masa estimada de medio depósito, no como consumo. El roadmap deja combustible dinámico para G4 (opcional). Para el Avanti hay que declarar qué carga de combustible representa su masa trimada y ubicarla respecto al CG. No variar solo el peso o solo el CG durante el vuelo: una simulación parcial necesita que masa, centro de gravedad e inercia evolucionen de forma coherente.

### Condición de vuelo inicial

El resolvedor de trim ya permite resolver a una velocidad solicitada, pero la configuración predeterminada es 15 m/s y `FlightSession.trace_meta()` afirma esa misma condición aunque se cambie velocidad o modo. No iniciar un Avanti con el valor heredado sin demostrar que cabe en su envolvente. La definición del avión debe aportar una velocidad de vuelo nivelado inicial sustentada por sus datos, y la creación de sesión usarla para resolver el trim. Actualizar metadatos de la traza para describir ID, archivo y condición efectivamente volada; conservar `openrc-trace v3` mientras no cambien columnas o semántica.

### Aterrizaje y exportación

El `crash_hull` es solo un detector de choque. Tener tren animado o retráctil no crea contacto de ruedas. La [hoja de ruta M2](../../ROADMAP.md) aún propone contacto de tren, taxi, despegue y circuito; la primera aceptación del Avanti debe limitarse a una modalidad en vuelo o mostrar explícitamente el estado de aterrizaje como no implementado.

El [plan de menú](../MENU-PLAN.md) mantiene UI-05 como trabajo futuro de catálogo con el Ugly Stik; hoy no es un selector multiavión implementado. Al añadir el Avanti, extender ese catálogo e IDs estables en un solo lugar, sin duplicar geometría ni parámetros físicos en una tarjeta. Los [presets de exportación](../../app/export_presets.cfg) incluyen JSON con `data/*.json`, y [export.sh](../../app/export.sh) prueba actualmente el vuelo del binario exportado. La entrega del segundo avión debe comprobar explícitamente que el JSON de Avanti viaja en los tres builds y que el binario logra cargarlo y trimarlo; compilar en el editor no prueba el paquete final.

## Secuencia de integración recomendada

1. **Definir la identidad y sus fuentes.** Fijar exactamente el modelo Avanti RC, motor/turbina y configuración inicial. Seguir el patrón del Stik: recursos locales separados por avión, medidas con vista, escala, datum, hash, incertidumbre y cota reservada; mantener geometría, apariencia y física como fuentes separadas.
2. **Añadir una definición mínima multiavión.** Mantener el Ugly Stik como predeterminado cuando no se proporciona ID y hacer que constructor, geometría, datos y configuración de trim provengan del mismo ID. No implementar un sistema extensible de plugins para dos aviones.
3. **Entregar vista previa visual.** Constructor nativo o importación controlada, nodos nombrados, bisagras y puntos de CG/propulsión propios. Mantener puente no visible para `propeller` mientras el renderer lo requiera. Comparar planta, perfil, frente, orientación, sombra y encuadre; no habilitar vuelo porque la malla sea reconocible.
4. **Abrir la ruta de turbina.** Diseñar un perfil de datos con procedencia, ley de empuje, eje, brazo, spool y stop/idle. Probar la nueva ruta contra casos calculables y confirmar que el caso glow axial del Stik sigue igual.
5. **Cargar y trimar el Avanti en aire.** Usar su masa/inercia, datos aerodinámicos normalizados y configuración fija de flaps/tren; elegir velocidad inicial del avión. Validar trim, estabilidad, mandos y pérdidas con trazas propias antes de marcarlo seleccionable.
6. **Añadir mandos de configuración y suelo después.** Tratar flaps y tren como estados separados con servo/actuador; activar simulación de contacto solo al implementar los pasos M2 que permiten probar despegue y aterrizaje.
7. **Cerrar producto y distribución.** Integrar la ficha de avión en UI-05, actualizar metadatos y aceptación de trazas y añadir a la prueba de humo de exportación una carga/trim real de cada ID disponible.

## Comprobaciones propuestas para la implementación

- Conservación del caso actual: build por defecto, trazas doradas y capturas del Ugly Stik permanecen en la misma ruta y con los mismos resultados dentro de sus tolerancias.
- Resolución de ID: Ugly Stik → Avanti → Ugly Stik, ID desconocido, JSON inválido, constructor ausente y trim imposible; ningún cruce entre geometría, datos o audio.
- Validación física: unidades/procedencia completas, concordancia de superficie/envergadura/referencia, MAC declarada por separado, CG/datum, inventario, inercia, `crash_hull` y origen de la línea de empuje.
- Turbina: empuje en los puntos de la curva de fuente, vector y momento al cambiar brazo/eje, aceleración y desaceleración de spool, idle y apagado; ausencia de torque y giro de hélice falsos.
- Trim/entrada: inicio Avanti a la velocidad definida, vuelo manos libres dentro de tolerancia, signos de ejes y pruebas de independencia de frame rate con entradas reales.
- Configuración: flaps y elevador conservan órdenes independientes; cualquier mezcla explícita se prueba por separado; tren no confunde rueda/steering con retraído; articulación visual coincide con el estado físico. La prueba de contacto se añade cuando M2 la implemente.
- Trazas y paquete: ID/ruta/velocidad correctos en metadata, columnas con semántica explícita y binarios Linux/Windows/macOS capaces de cargar y trimar el JSON Avanti.
- Modelo: compiladores `--check`, contrato de nodos, signos y holguras, capturas comparables de vistas/actitudes, lectura humana y medición en hardware objetivo. Los planos o fotos descargados no sustituyen esas verificaciones.

## Límites de esta auditoría

La lectura confirma dónde se acopla el Stik y qué infraestructura es reutilizable; no determina la variante RC Avanti, sus dimensiones, peso, motor, combustible, coeficientes o velocidad de trim. Tampoco se construyó una malla, se cargó un segundo JSON o se ejecutó el simulador. Las pruebas enumeradas son criterios propuestos, no resultados.

Referencias internas principales: [plan de integración Extra 300](extra-300-integration-audit.md), [método del Ugly Stik](../UGLY-STIK-PLAN.md), [plan de menú](../MENU-PLAN.md), [roadmap](../../ROADMAP.md), [fuente geométrica Ugly Stik](../../assets/aircraft/ugly-stik-60/README.md), [pin de Godot](../../app/get-godot.sh), [renderer Compatibility](../../app/project.godot) y [guard de `float64`](../../app/test.sh).
