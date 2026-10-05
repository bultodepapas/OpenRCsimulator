# Godot: ciclo de vida del shell y carga de escenas

**Consulta:** 2026-10-05. **Pregunta:** ¿Cómo organizar Inicio → vuelo → regreso y pausa en Godot, y cuándo merece la pena cargar contenido en segundo plano?

## Hallazgos verificados

Godot permite cambiar la escena activa y también preparar un nodo antes de convertirlo en escena actual. `SceneTree.change_scene_to_node()` retira la escena saliente enseguida, elimina esa instancia al final del frame y agrega la nueva; `scene_changed` avisa cuando la nueva ya entró y se inicializó. El árbol conserva una escena activa y no deja ambas ejecutándose durante el cambio. Esto ayuda a limpiar el mundo de vuelo al regresar, pero implica que el estado que deba sobrevivir al cambio tiene que vivir fuera de esa escena o guardarse antes de salir. [Referencia `SceneTree` de Godot 4.7](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html).

La pausa global de Godot detiene física y callbacks según `Node.process_mode`; una rama `When Paused` puede seguir atendiendo el menú. Los temporizadores de `SceneTree.create_timer()` procesan durante una pausa por defecto: hay que pedir `process_always = false` cuando una espera deba congelarse. El proyecto tiene hoy otra pausa: `Simulation.set_paused()` detiene los ticks físicos, pero `FlightSession._physics_process()` sigue sondeando entradas y bajando el contador del accidente, y `main.gd._process()` mantiene la presentación. Por ello, la pausa de Godot no se puede aplicar como detalle visual sin decidir qué pasa con radio, calibración, audio y el reinicio por choque. [Pausa y modos de proceso](https://docs.godotengine.org/en/4.7/tutorials/scripting/pausing_games.html) y [temporizadores de `SceneTree`](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html).

`ResourceLoader` ofrece solicitudes de carga en hilos, consulta de progreso y estado por frames. Llamar `load_threaded_get()` antes de que termine puede bloquear el hilo principal; el manual recomienda esperar comprobando estado en frames distintos. Los subhilos pueden aliviar carga, aunque el propio manual advierte que pueden causar lentitud en el hilo principal. Esto describe carga de recursos: construir nodos, activar física y conectar el lector de radio siguen siendo responsabilidades de la escena/app. [Referencia `ResourceLoader` de Godot 4.7](https://docs.godotengine.org/en/4.7/classes/class_resourceloader.html).

## Aplicación al repositorio y recomendación

`project.godot` arranca directamente en `main.tscn`; `main.gd._ready()` construye el mundo, crea `FlightSession`, conecta el grabador, llama `reset()` y crea audio antes de que haya un botón de inicio. Las pruebas y rutas técnicas también instancian `main.tscn` directamente. Esto coincide con el riesgo que señala `docs/MENU-PLAN.md` en «Ciclo de vida»: el arranque interactivo requiere un shell pequeño y una ruta técnica directa compatible.

**Ahora:** UI-01 puede mantener un `app_root` liviano con Inicio y un contenedor de vuelo. Instanciar `main.tscn` únicamente al elegir Volar y liberarlo al terminar deja intacto su punto de entrada para CLI/tests. Preparar y validar los datos antes de habilitar ticks; el primer frame del vuelo no debe ser un efecto colateral de `add_child()`. Conservar el estado de pausa de simulación existente y agregar el menú sin activar simultáneamente `SceneTree.paused`, hasta que haya una política explícita para las causas que bloquean el vuelo.

**Después:** si un segundo campo, texturas o catálogo hacen visible una espera al entrar, iniciar `load_threaded_request()` desde el shell y consultar estado/progreso cada frame; obtener la escena solo cuando esté cargada. Si Inicio usa una captura estática y la selección actual no tarda, diferir esta complejidad. Mantener identificadores y selección en el shell; no mantener una instancia del mundo de vuelo bajo una capa de menú oculta.

## Prueba o spike aún propuesto

En una rama de trabajo, medir y comprobar Inicio sin sesión/audio activos; Volar con una sola sesión válida; Terminar con grabación; y cinco retornos sin duplicar sesiones, sonidos ni señales. Verificar que un error de datos vuelve a Inicio sin volar y que la pausa durante el retardo de choque detiene ese retardo. Si se evalúa `change_scene_to_node()`, esperar `scene_changed` antes de usar referencias a la nueva escena. La documentación respalda estas pruebas, pero no se ejecutó ninguna aquí.

**Límite:** las páginas consultadas documentan Godot 4.7; el proyecto fija Godot 4.7.2. No se verificó que cada detalle coincida con ese ejecutable, ni se midió carga o rendimiento. La recomendación sobre un shell persistente es una inferencia de la estructura actual, no una exigencia del motor.
