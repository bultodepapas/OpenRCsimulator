# Extra 300: auditoría de integración con el Ugly Stik

2026-10-05 · Inspección de código, sin cambios de aplicación ni ensayos nuevos. [Plan](../EXTRA-300-PLAN.md).

El árbol tiene trabajo concurrente de paisaje/menú; estas observaciones describen los archivos leídos, no un commit limpio. Base HEAD al registrar: `a78cda31d63a48e2c7b64397a96b40a916649d9a`. Revisar de nuevo los puntos afectados al implementar.

## Lo que se puede aprovechar

- [Geometría y compiladores](../../assets/aircraft/ugly-stik-60/README.md): fuente declarativa, procedencia y generación comprobable. El patrón sirve; la forma rectangular y sus constantes no representan el Extra.
- [Constructor nativo](../../app/aircraft/ugly_stik_model.gd): estaciones, extrusión de contornos, materiales y jerarquía estable. Extraer únicamente helpers que ambos aviones usen realmente.
- [Transformación de marcos](../../app/render/frames.gd): separa origen visual de posición del CG. Recibe `leading_z` y `thrust_y`; la nueva variante debe suministrar sus propios anclajes.
- [FlightSession](../../app/sim/flight_session.gd): `setup(path)` ya carga otro JSON. [Simulation](../../app/sim/simulation.gd) integra masa/inercia/cargas suministradas; no necesita otro integrador.
- [AircraftData](../../app/physics/aircraft_data.gd): validación, unidades, procedencia e inventario de masa. Las pruebas genéricas pueden ejercitarse con ambos modelos.
- [Pruebas](../../app/tests/test_aircraft_data.gd), [handling](../../app/tests/test_handling.gd), [pilot aids](../../app/tests/test_pilot_aids.gd): conservar las expectativas Stik y añadir las específicas Extra; no reemplazarlas por una misma banda laxa.

## Acoplamientos observados y consecuencia

| Archivo / símbolo | Estado observado | Cambio mínimo propuesto |
| --- | --- | --- |
| [render/airplane.gd](../../app/render/airplane.gd) `build`, `_mat` | Preloads y delegación directa a UglyStik; también Controls del Stik | Constructor/funciones por definición; preservar entrada sin argumento como Stik |
| `apply_surfaces` en ese archivo | Asigna Euler `(r.x, r.y, 0)` a cada bisagra | Deflexión sobre eje o marco específico del avión; comprobar alerón oblicuo Extra |
| `apply_gear`, `set_maintenance` | Ruedas `left/right/nose` y mecanismo Controls concreto | Ruedas opcionales por ID y delegado de mantenimiento; cola para Extra |
| [main.gd](../../app/main.gd) `_update_cg_model`, `_build_scene` | Geometry Stik fija; builder sin identidad | Resolver juntos geometría, constructor y datos antes de crear la sesión |
| [scenarios.gd](../../app/sim/scenarios.gd) `AIRCRAFT`, escenarios | Ruta Stik por defecto, velocidad 15 m/s | Conservar default y permitir inicio validado por avión |
| [flight_session.gd](../../app/sim/flight_session.gd) `trace_meta`, `reload` | Metadatos citan Scenarios.AIRCRAFT y vuelo fijo; texto reload menciona 15 m/s | Ruta/ID/revisión/condición efectivos; recarga coherente con avión activo |
| [inspect_model.gd](../../app/aircraft/inspect_model.gd) | Geometría, cámaras de detalle, rutas y manifests específicos Stik | Presets de inspección por avión; impedir sobrescribir evidencia anterior |
| [shadow.gd](../../app/render/shadow.gd) | Extensión obtenida de mallas; máscara y centro alar fijos | Parámetros/silueta propios por avión; tamaño correcto no basta |
| [test_aircraft_data.gd](../../app/tests/test_aircraft_data.gd) | Compara span/cuerda del JSON con Geometry Stik | Mantener prueba Stik; Extra compara su planta y referencia de cuerda declarada |
| [aircraft_data.gd](../../app/physics/aircraft_data.gd) `COEFFICIENTS` | Signos exigidos para estabilidad estática | Diseñar primer perfil Extra estable; justificar cualquier relajación con caso independiente |
| `validate_and_derive` / `_envelope` en ese archivo | Exige `span × mean_chord = area` ±1 % y una región lineal de ±8° | Normalizar primero con `S/b`, declarar MAC aparte; no forzar datos de pérdida para satisfacer una hipótesis incompatible |
| [aero.gd](../../app/physics/aero.gd) estaciones/envolvente | Ala equivalente, sin propwash; respuesta no identificada para Extra | Etiquetar límites; geometría de estaciones/cola mediante Gate F, no escalar arbitrariamente eficacia |
| [propulsion.gd](../../app/physics/propulsion.gd) `loads` | Fuerza sobre +X; offset añade brazo, no inclinación; torque sobre X | Dirección de eje y transformaciones de par/momento angular coherentes; compatibilidad axial |

La cámara usa `_extent.x` del modelo construido, por lo que su autozoom ya parte de una magnitud útil. Revisar el encuadre de inspección y el datum cuando cambie la longitud/cabina; no afirmar que toda la cámara necesita reescritura.

## Detalles físicos que impiden una simple copia del JSON

El esquema requiere superficie, envergadura, cuerda de referencia y punto aerodinámico. La nueva planta trapezoidal necesita definir cómo se obtienen esos valores. Los derivados y los coeficientes de momentos deben usar las mismas referencias. Las estaciones de pérdida y los brazos no se heredan del Stik.

En v1 la comprobación `span × mean_chord` impone cuerda media geométrica. Eso es utilizable como referencia de coeficientes si se normalizan consistentemente, pero no autoriza llamar MAC a ese valor ni calcular el porcentaje de CG respecto a él como si lo fuera. El primer Extra mantiene esa normalización; una separación de campos requiere cambio explícito de contrato.

El loader convierte `crash_hull` desde coordenadas LE a cuerpo relativo al CG. Su topología es flexible, pero sus puntos deben representar el Extra, incluyendo rueda de cola y carenado. Eso detecta accidentes; todavía no implementa aterrizaje.

`Propulsion.loads()` usa velocidad axial y reacción de par alineadas con el cuerpo. `FlightSession.rotor_momentum()` también debe revisarse al orientar el motor: inclinar solo su dibujo no cambia las fuerzas ni la precesión. Un ensayo conocido del caso axial debe permanecer inalterado.

No hay modelo de consumo de combustible en esta primera instalación. La condición de masa usada en simulación debe documentarse; un CG de montaje con depósito vacío no determina automáticamente el CG de una salida con combustible.

## Contrato de cambio de sesión propuesto

Resolver ID → definición → datos válidos/trim → constructor, preparar la nueva sesión detenida y entonces sustituir la anterior. Al fallar preparación, no mezclar recursos; conservar una sesión anterior válida o mostrar el error en selección. Desconectar señales y cerrar la grabación previa, liberar nodos antiguos y restablecer servo/rpm/trims al iniciar. Compartir recursos de material inmutables; no conservar estado de mandos entre instancias.

Probar como mínimo Stik → Extra → Stik, ID desconocido, datos inválidos, trim imposible, reinicio, recarga, radio conectada/desconectada y traza. El menú proyectado en [UI-05](../MENU-PLAN.md) es el propietario de la selección de producto; esta definición no crea otro sistema de preferencias.

## Evidencia y límites

Se leyeron los módulos anteriores y el research dimensional/visual del Stik. No se midió rendimiento, no se construyó un Extra y no se ejecutó una prueba de vuelo. Las pruebas de este documento son propuestas para implementación. La infraestructura actual demuestra una vía de integración, no que las derivadas actuales representen otro avión.
