# VQ-01a — capturas verificables y atmósfera separada del campo

2026-10-06. Primer paso de implementación del [plan visual](../../../VISUAL-QUALITY-PLAN.md). No añade vegetación ni cambia física, materiales, cámara o presets.

## Cambio

- `app/capture.sh` ejecuta cada captura mediante `tests/capture_runner.py`. Borra PNG/JSON anteriores de ese caso, exige salida cero, rechaza errores de motor/shader, decodifica el PNG completo a 1280 × 720 y verifica nombre/hash/escena del manifiesto. En timeout termina el grupo del proceso (Godot y Xvfb); ante fallo conserva el log y retira los artefactos parciales.
- Un bloqueo impide dos ejecuciones del harness sobre la misma carpeta. `run-manifest.json` se retira al comenzar y solo se publica al terminar capturas, controles de imagen y traza. Enumera exclusivamente los casos ejecutados; no recoge archivos antiguos mediante un glob.
- Las capturas de vuelo conservan el manifiesto del motor y añaden formato, renderer y `capture_scene`. Una escritura fallida del JSON hace salir a Godot con error. La UI recibe un sidecar del harness, identificado como tal; no se inventan contadores GPU de UI.
- `main.gd::_build_field()` contiene la construcción actual del suelo/pista. El fixture `tests/fixtures/atmosphere_field.tscn` hereda el flujo de captura y sustituye solo esa construcción por las dos mallas de referencia. Sigue consumiendo los materiales/atmósfera que deben probarse; no es una copia congelada de los shaders.
- **Vacío significa sin decoración del campo**, no sin suelo: L2 necesita terreno cercano/lejano, bruma y borde del plano; los casos L3 necesitan avión/sombra. Las 29 referencias conservan sus nombres. Las nueve vistas nuevas del campo real están en `app/captures/field/`, cuatro azimuts × dos elevaciones más cenital, sin avión.
- El checker exige los 29 contadores y manifiestos del fixture. Mantiene las fórmulas y umbrales L1–L4; un PNG antiguo extra no sustituye un caso ausente. Las pantallas Home/Pause/Help/Hint en inglés/español usan las mismas guardas de proceso e imagen.

Se preservó el trabajo concurrente: catálogo/selección de aviones en `main.gd` y las nuevas capturas Help/Hint. Ningún fichero del modelo, física o UI fue reemplazado por una versión anterior.

## Pruebas

| Evidencia | Resultado |
| --- | --- |
| [Suite headless integrada](app-tests.log) | `app/test.sh` finaliza con código 0: parseo, modelos, física, goldens, radio/entrada, UI y estado idéntico a 30/60/144 fps |
| [Pruebas del runner](runner-tests.log) | 15 casos pasan: archivos viejos válidos, exit 42 incluso tras guardar archivos válidos, timeout, salida cero sin artefactos, PNG roto/tamaño incorrecto, JSON ausente/roto/hash/nombre/escena incorrectos, error shader y éxito de vuelo/UI |
| [Mutaciones de las guardas](guard-mutations.json) | Quitar la limpieza inicial o ignorar el código de salida hace fallar sus respectivas pruebas |
| [Comparación con el baseline](baseline-comparison.json) | **29/29 PNG idénticos**. Datos CSV de la traza idénticos; el encabezado `created_utc` cambia por diseño, por lo que no se afirma igualdad del CSV completo |
| [Separación y fallos reales](mutations/results.json) | Siete pruebas pasan: obstáculo nuevo modifica el campo, no el fixture; error real al escribir JSON devuelve código 12; falta de counter se detecta con el PNG presente; cielo plano, borde artificial y nubes congeladas siguen rechazándose |

La prueba del obstáculo cambia únicamente una copia temporal de `main.gd`. [Campo con obstáculo](mutations/field/capture-land-az0-el0.png) y [fixture intacto](mutations/atmosphere/capture-land-az0-el0.png) son evidencia de esa mutación, **no capturas del producto entregado**. Las mutaciones de imagen actualizan su hash deliberadamente: deben fallar por las métricas visuales, no por integridad del archivo.

**La ejecución integrada final en clon limpio terminó con código 0: 46 PNG y sidecars nuevos** (29 referencias, nueve vistas del campo, ocho de UI), además de la traza validada. [Log completo](capture-tests.log), [inventario](run-manifest.json) y [hashes del código probado](validation.json). Las 29 referencias y los datos de la traza siguen idénticos tras integrar el catálogo de aviones. Solo se reutilizaron las herramientas fijadas en `.tools`; no se copiaron capturas ni caché `.godot` al clon.

## Reproducción

Desde la raíz:

```bash
app/test.sh
app/capture.sh
```

El harness usa el Godot fijado y el entorno visual ya existente; no añade dependencias Python ni cambia sus versiones. Requiere el entorno Linux de captura habitual (Xvfb, OpenGL software y `flock` de util-linux). Cada PNG tiene `.json` y `.log`; el marcador de conjunto completo es `app/captures/run-manifest.json`. Un fallo devuelve código no cero y deja ese marcador ausente. Los logs identifican el caso que falló.

Las mutaciones de aceptación se pueden repetir después de una ejecución completa:

```bash
"$(app/tests/visual-env.sh)" docs/research/visual-quality-implementation/VQ-01a/verify_mutations.py \
  --app app --godot "$(app/get-godot.sh)" --captures app/captures \
  --out /tmp/openrc-vq01a-mutations
```

Las comparaciones se hicieron en Godot 4.7.2 Compatibility, Mesa/llvmpipe, `LP_NUM_THREADS=1`, 1280 × 720. No son benchmarks GPU ni prometen igualdad de bytes entre drivers. Las capturas UI que esperan un segundo de vuelo sirven para comprobar layout y guardado; este paso no las convierte en replays deterministas.

## Límites y siguiente paso

El manifiesto actual acredita los archivos producidos, la escena y sus contadores; **VQ-01b** todavía debe añadir la matriz ampliada, metadatos completos de casos y muestras crudas del logger. **L5** sigue pendiente: esta separación para pruebas no implementa el loader de campo ni comparte su construcción con Home. L6 y los perfiles de calidad tampoco se declaran completados.
