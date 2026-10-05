# Investigaciones Godot para mejorar el plan de viento (01–04)

**Fecha:** 2026-10-05. **Motor fijado:** Godot 4.7.2-stable.  
**Alcance:** ampliación de [la auditoría de integración existente](../wind-godot-integration.md) sobre ciclo de ejecución, aleatoriedad, coste y pruebas. La documentación de clase consultada corresponde a Godot 4.7; donde importa, se coteja el código fuente del tag exacto 4.7.2-stable.  
**Proyecto local:** [plan de viento](../../WIND-PLAN.md) y [ROADMAP](../../../ROADMAP.md). Esta nota no cambia ninguno de ellos ni modifica la app.

## 01. ¿En qué reloj y callback debe evolucionar el viento, y qué pausa lo congela?

### Hallazgos citados

- Godot llama a `_physics_process()` a una tasa fija controlada por `Engine.physics_ticks_per_second`. El orden de esos callbacks usa `process_physics_priority`: prioridad menor primero, árbol como desempate. [Node 4.7](https://docs.godotengine.org/en/4.7/classes/class_node.html#class-node) [Engine 4.7](https://docs.godotengine.org/en/4.7/classes/class_engine.html#class-engine)
- `SceneTree.paused = true` para física/collisions nativas; puede suprimir callbacks según `Node.process_mode`. `PROCESS_MODE_ALWAYS` sigue procesando. Esta pausa global es distinta de la bandera de pausa propia del juego. [SceneTree 4.7](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html#class-scenetree) [Node process modes 4.7](https://docs.godotengine.org/en/4.7/classes/class_node.html#enum-node-processmode)
- Este proyecto fija 240 ticks/s y 12 pasos como máximo por fotograma: bajo 20 fps de render, Godot puede limitar la recuperación y la sesión se percibe en cámara lenta. El manual describe este límite y ralentización aparente. [Engine 4.7: máximo de pasos y tasa física](https://docs.godotengine.org/en/4.7/classes/class_engine.html#class-engine)
- El reloj útil para el modelo ya es `Simulation.tick / Simulation.time()`, con `dt() = 1 / Engine.physics_ticks_per_second`. `Simulation._physics_process()` no usa `delta` y no avanza cuando `sim.paused`. Además, `main.gd` deshabilita ese callback para la traza y llama `sim.step()` directamente. La captura física también avanza con llamadas directas a `step()`. Un nodo viento que dependa solo de su callback, un `Timer`, `_process()`, hora real o lectura del HUD se desincronizaría.
- La prioridad de nodos solo ordena callbacks ejecutados por SceneTree. El camino síncrono de traza/captura no ejecuta el callback del clima, por lo que el orden explícito dentro de `Simulation.step()` es la frontera robusta.

### Correspondencia local y cambio concreto al plan

[simulation.gd](../../../app/sim/simulation.gd) posee tick y pausa; [flight_session.gd](../../../app/sim/flight_session.gd) compone cargas; [main.gd](../../../app/main.gd) tiene los caminos síncronos de traza/captura. [project.godot](../../../app/project.godot) fija 240/12. La nota de integración previa ya indica que el clima ha de avanzar por el camino de simulación.

Afinar **M5-W01b/W01c**: el viento vive como datos/objeto de sesión y solo avanza desde `Simulation.step()`; no añadir reloj meteorológico autónomo en `_physics_process()`. Afinar **M5-W02a/W04a**: preparar una transición por tick antes del RK4; las cuatro evaluaciones de carga consultan el clima para el tiempo de etapa sin gastar aleatoriedad.

### Prueba propuesta

En la ruta viva, activar `sim.paused`, invocar el callback físico y demostrar que no cambian avión, tick, seed/state, filtro, agenda ni viento de traza. Reanudar y verificar que la transición siguiente coincide con la que habría ocurrido sin tiempo meteorológico durante la pausa. En una prueba de sesión, ejecutar N llamadas directas a `sim.step()` con el callback del nodo desactivado, igual que en `--trace`, y comprobar N avances del clima. Repetir la entrada de vuelo a 30/60/144 fps y comparar hash del avión y checkpoint meteorológico.

### Límites y riesgo concreto

Con 240 Hz y 12 pasos por fotograma, el reloj de pared puede adelantarse al de sesión cuando hay menos de 20 fps. El viento sigue al tick simulado; ponerse al día según reloj real haría que el campo cambie sin que avance la aerodinámica. Si después se activa pausa global del árbol, un nodo de viento configurado como `PROCESS_MODE_ALWAYS` podría seguir mientras el avión no, así que el clima no debe depender de esa política. No cambiar el límite de pasos ni las prioridades como parte del viento básico.

## 02. ¿Qué determinismo, checkpoint y precisión ofrece el RNG de Godot?

### Hallazgos citados

- `RandomNumberGenerator.seed` inicia una secuencia repetible; `state` permite continuar desde un estado antes observado. Se fija seed antes de restaurar state y no se asigna un state arbitrario. `randfn(mean, deviation)` produce una normal mediante Box–Muller. [RandomNumberGenerator 4.7](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html#class-randomnumbergenerator)
- La API dice que actualmente usa PCG32, pero que el algoritmo es detalle de implementación y no se debe depender de él. El constructor fuente de 4.7.2 aleatoriza inicialmente, así que la sesión debe asignar seed explícita inmediatamente. El método normal consume dos muestras uniformes. [RNG C++ 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/random_number_generator.h) [PCG 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/random_pcg.h) [inicialización PCG 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/random_pcg.cpp)
- En el binario oficial estándar, `real_t` es `float`; solo es `double` si se compila con `REAL_T_IS_DOUBLE`. Los métodos RNG usan `real_t`. Así, la resolución de una salida `randfn` puede estar cuantizada a float32 aunque el estado y el filtrado GDScript se mantengan en doble precisión. Es una precisión de entrada que se debe medir; por sí sola no obliga a reimplementar PRNG ni contradice el estado float64. [random_number_generator.h 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/random_number_generator.h) [math_defs.h 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/math_defs.h)
- Una seed solo repite una secuencia si se conserva el orden y cantidad de llamadas. Una lectura aleatoria adicional desde HUD/instrumentación desplaza todo el flujo. El state del PRNG no captura filtros, parámetros meteorológicos, agenda ni estado de vuelo.

La implementación `randfn` además aumenta el uniforme pequeño por `CMP_EPSILON` antes de aplicar logaritmo. Esa protección modifica la cola extrema respecto a una normal matemática ideal; no usar la API como evidencia de probabilidades de ráfagas raras. El número de llamadas a la API se puede fijar, pero no asumir que equivale a un número constante de palabras PCG: el generador uniforme contiene ramas. Para el primer OU, comprobar estadística útil y conservar estado observado; no escribir un RNG nuevo únicamente por este hallazgo. [Fuente PCG fijada](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/random_pcg.h).

### Correspondencia local y cambio concreto al plan

El plan propone RNG privado, `prepare_tick()`, `snapshot()/restore()` y W04a para OU. [simulation.gd](../../../app/sim/simulation.gd) hace cuatro evaluaciones RK4 por tick y [recorder.gd](../../../app/sim/recorder.gd) puede comenzar durante un vuelo. Por eso el sorteo aleatorio no debe ocurrir al consultar fuerzas.

Refinar **M5-W02c**: agenda de ráfagas en orden fijo y presupuesto fijo de draws por transición; consulta repetida, posición, HUD e indicador no consumen RNG. Refinar **M5-W04a**: obtener `randfn(0, 1)` y escalar/filtrar el resultado en GDScript float64; medir cuantización, varianza y autocorrelación antes de fijar tolerancias. Esto distingue precisión de muestra aleatoria del estado/cálculo float64. Para checkpoint, guardar seed y state como texto decimal, con tick, versión exacta de Godot, versión/config hash del clima, estado float64 del filtro y agenda/evento activo. En reset, sembrar antes de `sim.reset()`, porque reset evalúa las cargas iniciales.

### Prueba propuesta

Con seed fija, registrar muestras, guardar state y verificar que restaurarlo reproduce la continuación. Repetir dos vuelos y comparar checkpoint/traza. Insertar consultas extra a `sample_ned`, HUD e indicador: el hash no cambia. Probar `σ=0` y la recurrencia OU; con una muestra grande comprobar media/varianza/autocorrelación en banda estadística. Incluir una prueba de resolución de `randfn(0,1)` para el binario fijado como evidencia diagnóstica, sin congelar sus valores exactos entre versiones.

### Límites de versión

La garantía razonable es continuidad bajo el motor/runtime fijado y la misma secuencia de llamadas; la API no garantiza replay bit a bit entre versiones. Si se exige reanudar una grabación en un motor futuro, conservar muestras/eventos ya generados o, con evidencia de necesidad, evaluar un PRNG versionado propio. El límite `real_t` afecta la muestra aleatoria, no obliga a cambiar los estados, filtros e integración float64. Ninguna de estas fuentes calibra turbulencia de campo RC.

## 03. ¿Cómo medir el coste sin inventar una promesa de rendimiento?

### Hallazgos citados

- El profiler de Godot está apagado por defecto porque su medición tiene coste; identifica tiempo por función y por fotograma/física. Es útil para localizar cuellos de botella, pero los valores instrumentados no sustituyen al benchmark normal. [Profiler Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/the_profiler.html)
- `Performance.add_custom_monitor()` registra un `Callable` que devuelve un valor numérico, con categorías y tipos para cantidad, bytes, segundos o fracción porcentual. Es adecuado para contadores/snapshots, como consultas por tick o coste agregado; no es un hook de cada fase del RK4. El callback no debe consultar ni avanzar viento, ni consumir RNG. [Performance 4.7](https://docs.godotengine.org/en/4.7/classes/class_performance.html#class-performance) [API Performance 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Performance.xml)
- La documentación del profiler consultada describe medición temporal de funciones, no un contador por llamada de asignaciones float64 de GDScript. Crear/copiar arrays y diccionarios repetidamente es algo que hay que medir, no una razón para asumir un coste inaceptable.

- Los monitores custom solo admiten valores no negativos; la documentación avisa de que recorta los negativos a cero. Sirven para coste y recuentos, pero falsearían las componentes firmadas N/E/D del viento. Esas series van en la traza o un gráfico propio, no directamente en un monitor custom. [Contrato Performance del tag fijado](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Performance.xml).
- El benchmark local integra 2400 ticks de vuelo y reporta µs/tick, pero [bench_physics.gd](../../../app/tests/bench_physics.gd) solo conserva el mejor de tres runs. Para cambios pequeños se necesitan ventanas múltiples y percentiles. El propio [test.sh](../../../app/test.sh) dice que su medición de frame y física es instrumentación, no un presupuesto universal.

### Correspondencia local y cambio concreto al plan

[simulation.gd](../../../app/sim/simulation.gd) registra `step_usec` sin alimentarlo a física. [bench_physics.gd](../../../app/tests/bench_physics.gd) y el presupuesto existente del ROADMAP permiten comparar el coste antes/después. Campo distribuido en W05c puede multiplicar las muestras por las estaciones.

Añadir a **M5-W01b** una línea base con campo cero/uniforme. Extender aceptación de **M5-W04a/W05c** para medir por separado ráfagas, OU y estaciones; informar coste añadido por tick y percentiles. Usar primero el profiler para localizar gasto y después benchmark normal sin profiler. Los monitores custom son opcionales para contadores ya calculados; no son criterio de aceptación ni lógica meteorológica.

### Prueba propuesta y límite

Benchmark futuro: calentamiento de 2400 ticks y 10 ventanas de 2400 ticks por condición, reiniciando seed; informar distribución de promedios de µs/tick por ventana, junto con motor, SO/CPU, build y parámetros. Los percentiles de diez promedios no describen las colas de coste de ticks individuales: si se exige p95/p99 por tick, registrar esas duraciones y cuantificar el coste de instrumentarlas. Comparar campo cero, constante, ráfagas, OU y estaciones con mismo estado/mandos. Funcionalidad se prueba con hashes y finitud; rendimiento se mide aparte en el equipo mínimo objetivo. El profiler no permite afirmar que no hay asignaciones ni fijar presupuesto antes de medir; una prueba de memoria prolongada detecta crecimiento, no atribuye por sí sola una asignación a una consulta.

## 04. ¿Qué vías headless, fps fijo y exportación dan evidencia fiel?

### Hallazgos citados

- El CLI de Godot 4.7 incluye `--headless`, `--fixed-fps`, `--disable-render-loop` y `--profiling`. Los argumentos propios de la app van después de `--`. [CLI 4.7](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
- `Engine.get_frames_drawn()` siempre retorna 0 en headless o con render loop deshabilitado; no sirve como reloj del viento ni contador de física. [Engine.xml 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Engine.xml)
- `--fixed-fps` permite probar el app real a distintas frecuencias visuales. No hace reproducible por sí solo el PRNG: siguen siendo necesarios seed y orden de ticks. `--disable-render-loop` es útil para rendimiento/trazas sin dibujo, pero no prueba HUD, manga, `frame_post_draw` ni capturas. Terminar por tick exacto; `--quit-after` cuenta iteraciones, no segundos de viento ni pasos del modelo.
- El arnés ya tiene parser, pruebas headless, traza real, hashes 30/60/144 fps, benchmark y smoke test del ejecutable exportado. [run_fixed_step.gd](../../../app/tests/run_fixed_step.gd) inyecta entradas en ticks definidos. La exportación empaquetada importa recursos distintos al editor, por eso conviene ampliar su prueba meteorológica.
- Herramientas: GUT ofrece 9.7.1 para Godot 4.7.x y licencia MIT. GdUnit4 ofrece licencia MIT, pero su tabla actual v6.2.1 documenta compatibilidad hasta Godot 4.7.1, sin listar 4.7.2. [GUT oficial](https://github.com/bitwes/Gut) [GdUnit4 oficial/compatibilidad](https://github.com/godot-gdunit-labs/gdUnit4) [licencia GdUnit4](https://github.com/godot-gdunit-labs/gdUnit4/blob/master/LICENSE)

### Correspondencia local y cambio concreto al plan

[app/test.sh](../../../app/test.sh) recorre scripts, ejecuta unitarias, traza real y fps fijo. [main.gd](../../../app/main.gd) pasa argumentos luego de `--`; [export.sh](../../../app/export.sh) ya arranca el binario exportado con una traza. El smoke debe confirmar que el preset de viento está empaquetado y se valida.

Ajustar **M5-W01a/W01d** para probar carga/configuración meteorológica tanto en test headless como en binario exportado. Ajustar **M5-W02c/W04a** para que el test de hashes del app real incluya snapshot del viento a 30/60/144 fps. Mantener prueba aparte con display/captura para manga y HUD; loop de dibujo deshabilitado solo en pruebas de simulación sin render.

### Prueba propuesta y decisión de herramientas

1. Unitarias: Godot fijado, headless, script de viento que llama un número exacto de `sim.step()`.
2. Integración por fps: extender `run_fixed_step.gd` / `test.sh` para comparar estado meteorológico y hash a 30/60/144 fps.
3. Integración sin render: traza/replay headless con `--disable-render-loop` opcional; verificar tick exacto y ausencia de consultas al reloj de pared.
4. Empaquetado: ampliar smoke test de `app/export.sh` para cargar un preset de viento en el binario exportado y comprobar la traza.
5. Visual: capturar con display/Xvfb sin `--disable-render-loop` y comprobar HUD/manga por separado.

No instalar GUT ni GdUnit4: podrían aportar descubrimiento o JUnit si otro CI lo exige, pero hoy el harness controla orden, hashes, replay, headless y smoke exportado. GUT 9.7.1 es la única con compatibilidad explícita consultada para 4.7.x; sería una dependencia MIT que habría que fijar. GdUnit4 v6.2.1 no declara aún 4.7.2 en su tabla. Reabrir la decisión si aparece una brecha concreta; no reemplazar pruebas existentes solo por adoptar un plugin.

## Fuentes consultadas

1. [Node 4.7](https://docs.godotengine.org/en/4.7/classes/class_node.html), [SceneTree 4.7](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html), [Engine 4.7](https://docs.godotengine.org/en/4.7/classes/class_engine.html).
2. [RandomNumberGenerator 4.7](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html), [RNG fuente 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/random_number_generator.h), [PCG 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/random_pcg.h), [tipos matemáticos 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/math_defs.h).
3. [Profiler 4.7](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/the_profiler.html), [Performance API 4.7](https://docs.godotengine.org/en/4.7/classes/class_performance.html), [Performance.xml 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Performance.xml).
4. [CLI 4.7](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html), [Engine.xml 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Engine.xml), [GUT](https://github.com/bitwes/Gut), [GdUnit4](https://github.com/godot-gdunit-labs/gdUnit4).
