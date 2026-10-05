# Investigaciones 09–12: configuración, controles y representación del viento

**Consulta:** 2026-10-05. **Motor examinado y ejecutado:** Godot 4.7.2-stable, edición oficial del proyecto; fuentes del tag exacto cuando se indica. Las páginas `stable` son móviles. Base local leída durante esta ronda: `8fe4bad`, con trabajo paralelo. [Índice de la ronda](README.md) · [Plan de viento](../../WIND-PLAN.md).

## 09. JSON, ConfigFile y JSON Schema: preservar lo que se configuró

**Pregunta.** ¿Cómo guardar presets y checkpoints sin perder números, aceptar una configuración incoherente o confundir parseo con validación?

**Hallazgos documentados.** Godot JSON permite comas finales y algunas entradas que un parser JSON estricto rechazaría. `JSON.new().parse()` ofrece error y línea; `parse_string()` devuelve `null` sin ese diagnóstico. `JSON.stringify(..., full_precision=true)` conserva los dígitos necesarios para reconstruir floats; la opción predeterminada no tiene esa finalidad. Los números JSON no conservan un tipo entero separado. [Referencia JSON](https://docs.godotengine.org/en/stable/classes/class_json.html), [contrato del tag 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/JSON.xml).

`ConfigFile` conserva valores Variant y permite codificar/parsear texto, además de cargar/guardar archivos. La clase no proporciona por sí sola migración del dominio meteorológico. [ConfigFile](https://docs.godotengine.org/en/stable/classes/class_configfile.html).

Para herramientas externas, `jsonschema` **4.26.0**, versión de la documentación consultada, ofrece `Draft202012Validator`, `check_schema` e `iter_errors`. Su `format` no valida automáticamente sin un comprobador habilitado. Licencia MIT. JSON Schema permite condiciones `if/then/else`, útiles para exigir `tau_s` en OU y escalas en Dryden. [API jsonschema](https://python-jsonschema.readthedocs.io/en/stable/validate/), [licencia v4.26.0](https://raw.githubusercontent.com/python-jsonschema/jsonschema/v4.26.0/COPYING), [condicionales del estándar](https://json-schema.org/understanding-json-schema/reference/conditionals).

**Prueba ejecutada.** El [probe reproducible](probe_config_controls.gd) y su [resultado](config-controls-probe.json) comprueban:

- `1.2345678901234567` se serializa por defecto como `1.23456789012346`; la opción `full_precision` permite recuperarlo exactamente en este motor.
- El número JSON `9007199254740993` vuelve como `9007199254740992`; como cadena permanece exacto.
- `ConfigFile.encode_to_text/parse` conserva el entero `9223372036854775807` con tipo `int` en este ensayo.
- Godot acepta `{"speed":2,}`. No demuestra que el preset sea válido para viento ni que lo acepte un lector externo.

**Cambio concreto al plan.** W01a mantiene el loader nativo, siguiendo el patrón de [`aircraft_data.gd`](../../../app/physics/aircraft_data.gd), con errores de campo y comprobación explícita de tipos/unidades/valores finitos. Los presets distribuidos deben ser JSON estricto; una validación offline puede detectar extensiones aceptadas por Godot. W01d/W04a guardan seed y estado RNG como cadenas decimales comprobadas, y floats de checkpoint con `full_precision=true`. Definir un orden de claves y una representación versionada antes de hashear contenido; `sort_keys` no equivale a un estándar universal de JSON canónico entre lenguajes.

`jsonschema` es **candidato offline**, no dependencia del juego ni requisito del primer preset. Si se adopta, fijar versión exacta y hashes en entorno de investigación separado. El esquema verifica estructura; restricciones como `gap_min <= gap_max`, continuidad del perfil y estabilidad numérica siguen siendo validaciones de dominio. No confundir `type:number` con magnitud físicamente razonable.

**Pruebas pendientes.** Fixtures compartidos Godot/Python para tipos, campos desconocidos, OU/Dryden, unidades y rangos cruzados; checkpoint → carga → continuación idéntica. Antes de reemplazar archivos de usuario, guardar temporal, recargar/validar y comprobar errores de sustitución; no atribuir atomicidad universal al guardado nativo. El probe no ensayó corte eléctrico, migración, import/export de presets ni Python jsonschema.

## 10. SpinBox, Range y foco: un editor de viento que no modifique el vuelo al abrirse

**Pregunta.** ¿Qué comportamiento real tienen los controles numéricos y qué debe suceder al pulsar Aplicar?

**Hallazgos documentados.** `Range.value` emite `value_changed` al cambiar incluso por código. `set_value_no_signal()` evita esa señal; el `step` sigue cuantizando valores. `SpinBox` tiene texto pendiente separado del valor y un método `apply()`; también `update_on_text_changed`, inicialmente desactivado. [Range](https://docs.godotengine.org/en/stable/classes/class_range.html), [SpinBox](https://docs.godotengine.org/en/stable/classes/class_spinbox.html).

Hay un detalle de prueba relevante: el código de `Range::Shared::emit_value_changed` omite controles fuera del árbol. Un test que construye el widget sin insertarlo no reproduce las señales de un panel visible. `SpinBox.apply()` llama a su ruta de envío de texto. [Range 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/gui/range.cpp), [SpinBox 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/gui/spin_box.cpp).

**Prueba ejecutada.** Con control dentro del SceneTree y `step=0.1`, asignar `0.26` produce `0.3` y una señal. Cargar silenciosamente `0.37` produce `0.4` sin señal adicional. Escribir `1.3` deja el valor anterior hasta `apply()`. El primer ensayo fuera del árbol no emitió señales; se corrigió el arnés y se verificó el motivo contra la fuente. El resultado guardado corresponde al ensayo final **10/10**, incluyendo las comprobaciones de investigación 09.

**Cambio concreto al plan.** En W03b mantener tres conceptos: configuración activa, borrador preciso y representación del widget. Abrir/cancelar o cambiar unidad no copia de vuelta los números redondeados. Cargar controles sin señales y no aplicar clima desde `value_changed`. Al confirmar, consolidar texto pendiente, validar el borrador completo y crear un único evento para el próximo tick. Determinar los campos realmente editados evita que abrir un preset de investigación con más decimales destruya precisión al guardar.

El panel debe expresar m/s, km/h o kt como presentación; σ y τ conservan sus unidades propias. No vincular dos sliders de unidades distintas mediante `Range.share()`: compartirían valor sin conversión física. La dirección requiere tratamiento circular y marca «desde»; limitar el widget a 0–360 no implementa interpolación angular.

**Integración RC.** [`FlightSession`](../../../app/sim/flight_session.gd) sondea teclado/radio además de recibir eventos. Pausar la física no cancela ese sondeo. Reutilizar el aislamiento de navegación de [MENU-PLAN](../../MENU-PLAN.md) y su [investigación de foco](../menu-investigations/02-input-focus-radio-isolation.md); no crear otro lector de radio para la pantalla meteorológica.

**Pruebas pendientes.** Abrir/guardar sin edición conserva hash; m/s→kt→m/s sin edición conserva valores internos; texto pendiente + clic Aplicar usa el valor nuevo; entrada inválida no cambia clima; flechas y radio no vuelan mientras navegan; cerrar el panel no anula una pausa por failsafe. El probe verifica contratos de controles, no ese flujo de producto completo. API nativa incluida con el Godot fijado; no hace falta plugin de formularios.

## 11. ImmediateMesh y MultiMesh: visualizar el campo para descubrir errores

**Pregunta.** ¿Cómo inspeccionar dirección, coherencia espacial y diferencia entre alas sin construir un sistema visual costoso?

**Hallazgos documentados.** `ImmediateMesh` está pensado para geometría simple actualizada frecuentemente y expone construcción de superficies; el manual desaconseja usarlo para geometría compleja. Sirve de candidato para unas pocas flechas/líneas de diagnóstico. [ImmediateMesh](https://docs.godotengine.org/en/stable/classes/class_immediatemesh.html).

`MultiMesh` agrupa muchas instancias con menor sobrecarga de envío. Su culling es conjunto, por lo que repartir una población amplia en regiones puede evitar dibujarla entera. El buffer es float32; los cuatro valores de `custom_data` se empaquetan en 16 bits en Compatibility. Hay que habilitar formatos antes de dimensionar las instancias y definir bounds adecuados. [MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html), [guía de optimización](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html). La guía avisa que no está revisada para 4.7; tomar sus cifras como orientación, no benchmark de nuestro motor.

**Cambio concreto al plan.** W04b incorpora una vista de depuración opcional con muestras en CG, puntas, cola y manga, cada una etiquetada con posición/altura, tiempo y unidad. Una flecha dibuja el vector **hacia** donde viaja el aire; el texto puede seguir mostrando «desde». W05b añade una cuadrícula pequeña a dos alturas para visualizar el fixture espacial afín. Construir sus vectores a partir del servicio físico puro y convertir a `Vector3` únicamente en render.

Empezar con pocos segmentos nativos; promover a MultiMesh solo al medir una cantidad que lo justifique. Un slider de escala de flecha cambia longitud dibujada, nunca el viento. La resolución del mapa y el refresco gráfico no determinan el paso meteorológico. No usar datos empaquetados en `INSTANCE_CUSTOM` como copia autoritativa del campo físico ni hacer consultas aleatorias nuevas al dibujar.

**Prueba propuesta.** Tres fixtures: uniforme, gradiente vertical lateral `W_D=kE`, y dos capas de altura. Comparar valores exportados con solución analítica, verificar extremos/direcciones de flechas en cuatro cardinales y medir el momento de alabeo cuando exista integración distribuida. Activar/desactivar el diagnóstico debe conservar hash de avión y clima. Captura fija con vectores y etiquetas permite revisar conversión NED→render sin interpretar una estela artística. No se ejecutó aún captura de esta herramienta.

**Límites.** Interpolar flechas no demuestra continuidad del campo subyacente. Flechas densas pueden tapar el avión, por lo que este modo es de investigación y está apagado al volar normalmente. Es una propuesta con clases incluidas, sin librería extra ni rendimiento garantizado; medir coste CPU/GPU y bounds antes de integrarla.

## 12. Particle shaders: transportar humo sin duplicar el movimiento

**Pregunta.** ¿Cómo hará un viento cambiante que la nube ya emitida se mueva de forma coherente en Compatibility?

**Hallazgos documentados y de fuente.** El shader de partículas expone `DELTA`, `VELOCITY`, `TRANSFORM` y `EMISSION_TRANSFORM`; `render_mode disable_velocity` desactiva el movimiento automático por velocidad. `disable_force` desactiva fuerza de attractors, es otro control. [Referencia de particle shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/particle_shader.html).

En el shader GLES3 de **4.7.2**, el avance `xform[3].xyz += out_velocity_flags.xyz * local_delta` aparece **antes** de ejecutar el bloque `PROCESS` y se omite con `DISABLE_VELOCITY`. Por tanto, escribir nueva velocidad en `process()` no equivale a que esa nueva velocidad ya haya desplazado la partícula en el mismo paso. Mover también `TRANSFORM` sin elegir quién integra puede contar dos avances. [Código GLES3 fijado](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/drivers/gles3/shaders/particles.glsl).

El material predeterminado separa gravedad, velocidad inicial y herencia de velocidad del emisor; esta última se aplica al nacer. Ninguna de esas propiedades, por sí sola, representa un servicio `W(x,t)` que cambie sobre partículas antiguas. [ParticleProcessMaterial](https://docs.godotengine.org/en/stable/classes/class_particleprocessmaterial.html).

**Cambio concreto al plan.** W07 comienza con un spike de trazadores pasivos y una decisión escrita de propiedad del avance:

1. Integración nativa por `VELOCITY`, aceptando/verificando su orden temporal; o
2. Integración explícita de posición con `disable_velocity`, coherente con las muestras de viento del intervalo visual.

No mezclar ambas. Primero usar viento uniforme y solución exacta `x(t)=x₀+Wt`; después cambio de dirección a un tick conocido y referencia CPU que integre ambos tramos. Una nube mantiene su posición al cambiar W y su trayectoria futura cambia de dirección. Si hay relajación de velocidad de humo hacia aire, τ es parámetro de ese efecto, separado de la τ de turbulencia.

Para campo espacial, el shader no puede llamar al objeto GDScript: hará falta una representación compartida verificable (rejilla, parámetros analíticos o partículas CPU) y un presupuesto de error de muestreo. No duplicar en GPU un generador aleatorio distinto y denominarlo el mismo clima. El float32 visual puede ser suficiente; jamás vuelve al solver de vuelo.

**Relación con investigación anterior.** [SMOKE-PLAN](../../SMOKE-PLAN.md) y [research de humo](../rc-exhaust-smoke.md) ya cubren `local_coords=false`, avance explícito, historia de emisor y restricciones de Compatibility. Aquí se añade el orden concreto del avance GLSL y la propiedad de integración. Su controlador visual debe agrupar subpasos sin perder cambios de viento dentro del bloque; transmitir solo W al final de cuatro ticks no reproduce necesariamente ese historial.

**Pruebas y límites.** El spike necesita Xvfb/OpenGL para comprobar compilación y transporte real; headless sin render solo prueba referencia CPU. Validar mismo número de pasos visuales, seed y cámara antes de comparar capturas. No se ha compilado un nuevo shader ni medido GPU en esta ronda. Mantener el efecto de humo independiente y coordinar este cambio con su equipo, sin convertirlo en requisito de W01.

## Evidencia ejecutada y reproducción

```bash
timeout 30 .tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app \
  --script "$PWD/docs/research/wind-investigations/probe_config_controls.gd" \
  -- "$PWD/docs/research/wind-investigations/config-controls-probe.json"
```

Resultado final: **10 comprobaciones, 0 fallos**, salida 0, sin errores de motor. El script vive fuera de `app/` y no modifica la simulación ni preferencias del usuario; ConfigFile se prueba en memoria. No se instaló ninguna dependencia. Las investigaciones 11–12 conservan experimentos propuestos, claramente separados de este resultado.
