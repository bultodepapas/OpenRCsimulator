# Viento en Godot: auditoría de integración de OpenRC

**Fecha:** 2026-10-05. **Base:** commit `0f002aa` y árbol con trabajo paralelo. **Evidencia:** lectura de código local, documentación oficial y fuentes del motor; una prueba existente ejecutada. Propuesta completa: [WIND-PLAN.md](../WIND-PLAN.md).

## Motor y APIs comprobadas

El pin local es **4.7.2-stable**, no solamente «Godot 4». `app/project.godot` usa Compatibility y 240 ticks/s, con máximo de 12 pasos por fotograma. La simulación integra su propio estado de 13 escalares; no depende de `RigidBody3D`.

| Fuente primaria consultada | Hecho documentado | Aplicación propuesta |
| --- | --- | --- |
| [Area3D, XML de 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Area3D.xml) | Sus propiedades `wind_*` afectan a `SoftBody3D`; no a otros cuerpos | Implementar velocidad del aire en nuestra física; `Area3D.wind_force_magnitude` no integra este avión |
| [Interpolación física](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html) | Frecuencia física y fotogramas son relojes diferentes | Viento en el tick; la imagen consume muestras e interpola |
| [float](https://docs.godotengine.org/en/stable/classes/class_float.html) | El escalar GDScript es de doble precisión | Mantener `float`/`PackedFloat64Array`, como exige el repositorio |
| [FastNoiseLite, interfaz 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/modules/noise/fastnoise_lite.h), [real_t](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/math_defs.h) | Las consultas de ruido usan `real_t`; es `float` salvo compilación de doble precisión | Una firma GDScript que acepta escalares no demuestra cálculo interno float64. Reservar FastNoiseLite para apariencia; no introducirlo silenciosamente en el viento físico |
| [RandomNumberGenerator](https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html) | Ofrece `seed`, `state`, normales y secuencias repetibles; el algoritmo subyacente es detalle de implementación | RNG privado por subsistema, sin `randomize()` en replay; guardar versión y estado. La semilla sola no garantiza continuidad entre versiones |
| [Global uniforms](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html#global-uniforms) | Se pueden registrar y actualizar mediante RenderingServer; el shader usa precisión propia de GPU | Reutilizar `ShaderClock.register/update`; GPU solo para representación |
| [ConfigFile](https://docs.godotengine.org/en/stable/classes/class_configfile.html) | Guarda/carga secciones y valores Variant y devuelve códigos de error | Persistencia en el sistema previsto por el menú, con validación, esquema y recuperación propios |

Las páginas `stable` pueden cambiar; los enlaces a `4.7.2-stable` fijan las observaciones de código. No se propone actualizar el motor ni añadir una dependencia. No se ha medido una nueva implementación de viento o shader.

## Hallazgos concretos del repositorio

| Archivo y símbolo | Estado leído | Trabajo necesario |
| --- | --- | --- |
| [`air_data.gd: compute`](../../app/physics/air_data.gd) | Resta viento NED rotado a cuerpo; produce `v_air`, V, α, β y presión dinámica | Reutilizarlo, mantener pruebas de cero y signos |
| [`rigid_body.gd`](../../app/physics/rigid_body.gd) | Velocidad inercial expresada en ejes de cuerpo; posición NED | Conservar esa semántica; no añadir viento otra vez al avanzar posición |
| [`flight_session.gd: _loads`](../../app/sim/flight_session.gd) | Pasa siempre `[0,0,0]`; ignora `_t` | Inyectar una muestra del servicio de viento para estado/tiempo solicitados |
| [`propulsion.gd: loads`](../../app/physics/propulsion.gd) | Ya recibe `air.v_air`; usa componente axial para J | El viento debe llegar por el mismo AirData; inflow oblicuo y rpm dependientes de carga siguen fuera del modelo actual |
| [`simulation.gd: step`](../../app/sim/simulation.gd) | Una evaluación para registrar cargas y cuatro RK4, todas con el mismo t | No consumir RNG dentro de `loads`; soportar tiempos de etapa antes del viento temporal |
| [`integrator.gd: rk4_step`](../../app/physics/integrator.gd) | Callback `f(state)` | Añadir una vía explícita `f(state,time)` conservando clientes autónomos |
| [`aero.gd: coefficients`](../../app/physics/aero.gd) | Tres estaciones por semiala; corrigen déficit de pérdida, con α local por p y r | No confundirlas con un solver distribuido de ala y cola; viento espacial necesita nueva contribución comprobada |
| [`scenarios.gd`](../../app/sim/scenarios.gd) | Estado inicial obtenido con trim en calma | Convertir velocidad inicial relativa al aire en velocidad respecto al suelo al iniciar con viento |
| [`main.gd: _update_hud`](../../app/main.gd) | Calcula AirData con viento cero | Leer telemetría física de la sesión; separar TAS y GS |
| [`trace.gd`](../../app/sim/trace.gd) | Formato real **v3**; `speed_mps` es norma de velocidad inercial, no TAS | Nueva revisión de traza con semántica explícita; el AGENTS todavía menciona v2 |
| [`simulation.gd: stepped`](../../app/sim/simulation.gd) | Emite estado al final del paso y cargas del comienzo | Registrar los dos tiempos; no atribuir unas cargas a otra muestra de viento |
| [`recorder.gd: start`](../../app/sim/recorder.gd) | Puede comenzar en medio del vuelo | Guardar checkpoint de vuelo y meteorología, no solo semilla inicial |
| [`shader_clock.gd`](../../app/render/shader_clock.gd) | `wind_vec` reservado en cero; reloj de simulación envuelto a 1024 s | Publicar viento convertido a render; no usar ese reloj envuelto para procesos físicos |
| [`atmosphere.gd: cloud_offset`](../../app/render/atmosphere.gd) | Deriva configurada en celdas/s multiplicada por tiempo | No equivale a viento físico m/s. Un viento cambiante exige desplazamiento integrado y altura/escala de nubes definidas |
| [`frames.gd`](../../app/render/frames.gd) | NED → render `(E,-D,-N)` | Única frontera hacia `Vector3`; `ned_to_render` recibe `Array`, adaptar el `PackedFloat64Array` explícitamente |

La pausa es `sim.paused`, no una pausa automática de todos los nodos Godot. Los caminos de traza y captura llaman directamente a `sim.step()`; el generador debe avanzar también ahí, sin depender de `_process`, de que exista una cámara o del lector de radio.

## Research anterior que conserva valor

- [RESEARCH: viento y térmicas](../../RESEARCH.md#wind-thermals-and-inexpensive-validation): distingue el campo de aire de las fuerzas, remite a JSBSim y al modelo de térmicas NASA. Útil como mapa, no como parámetros calibrados del campo RC.
- [Ambiente y viento](landscape-investigations/11-wind-animation-ambience.md): manga, vegetación, reloj y unidades. Su propuesta `wind_clock` quedó implementada como **`sim_clock`**. Su duda sobre registrar globals en runtime ya está resuelta por `ShaderClock.register`. No duplicar ese trabajo.
- [Ajustes y versiones](menu-investigations/03-settings-content-versioning.md), [alma del menú](../MENU-PLAN.md): entrada rápida al vuelo y una sola física; preferencias separadas de calibración de radio.
- [Auditoría Extra 300](extra-300-integration-audit.md), [plan Extra](../EXTRA-300-PLAN.md): futura geometría, datos y propulsión por avión. El clima debe ser común y su efecto depender de cada modelo.
- [Plan de humo](../SMOKE-PLAN.md): pausa, historial de emisiones y advección compartida. Es una propuesta paralela, no una dependencia implementada.
- [Pruebas de paisaje](../../app/tests/check_landscape_captures.py): reutilizar el protocolo de capturas; no atribuirle pruebas de viento que todavía no contiene.

La investigación anterior de mangas mezcla hechos y bocetos. La [FAA AC 150/5345-27E, §§3.2.2 y 3.5](https://www.faa.gov/documentlibrary/media/advisory_circular/150_5345_27e.pdf) respalda extensión completa a 15 kt y alineación desde 3 kt; corregimos aquí el número de sección de alineación que figuraba como 3.4 en la nota anterior. No demuestra una relación universal de velocidad por franja, ni la constante temporal sugerida. Ese parámetro sigue siendo una estimación visual, no un dato meteorológico.

## Comprobación realizada

```bash
timeout 30 .tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app --script res://tests/test_air_data.gd
```

Salida: `Godot Engine v4.7.2.stable.official.ed1daf0bf`; **11 checks, 0 failed**, salida 0 y sin errores del motor. Incluye viento de frente, cruzado, rotación a cuerpo y velocidad relativa cero. Esto verifica la función existente, no un sistema meteorológico integrado. No se ejecutó `app/test.sh` completo para esta entrega documental.
