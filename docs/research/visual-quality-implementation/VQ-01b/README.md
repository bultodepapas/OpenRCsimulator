# VQ-01b — referencias, casos fijos y tiempos de frame

2026-10-06 · Godot 4.7.2 · Compatibility · 1280 × 720 · Linux/Mesa llvmpipe. **Infraestructura de comparación; no aprobación de rendimiento de la RTX 3090.**

## Entrega

`app/capture.sh` conserva las 46 capturas anteriores y ejecuta el nuevo inventario de 66 mediante `tests/visual_quality_cases.py`, reutilizando `capture_runner.run_capture`. El manifiesto de conjunto solo se publica al terminar todas las comprobaciones; enlaza por SHA-256 el manifiesto ampliado. La ejecución independiente también bloquea su directorio de salida para evitar dos productores simultáneos.

| Familia añadida | PNG | Contrato |
| --- | ---: | --- |
| Piloto | 8 | Altura inicial 30/3 m, t=1,5 s, autozoom activado/desactivado, con/sin avión; sombra desactivada; cuatro mediciones de legibilidad |
| Campo | 18 | Azimut 0/90/180/270°, elevación 0/10° y cenital a 30 m; dos procesos por vista; hashes y contadores idénticos |
| Inspección sintética | 36 | Stik/Extra × 20/50/100 m de distancia al ojo × seis actitudes; FOV, exposición y luz iguales |
| Inicio → Volar | 4 | Inicio y vuelo en EN/ES; botón real de Volar; vuelo detenido en tick 360, sin cámaras ni entornos duplicados |

El Extra ya está en el catálogo de la app. Se usa su constructor real en el mismo fixture de inspección que el Stik, en vez de mantener dos inspectores con cámaras distintas. **Esta matriz es visual y sintética**; no amplía la validación física del Extra. La inspección cercana ya disponible sigue siendo útil para detalles de materiales.

Cada captura de vuelo conserva el formato anterior y añade `visual_evidence`: pose efectiva, distancias al piloto/cámara, proyección/FOV/autozoom, exposición, luz, controles/superficies/hélice, tick, reloj, backend y configuración. Los hashes incluyen las fuentes renderizadas, shaders, geometría generada y datos físicos. La semilla se declara no aplicable donde no se usa RNG; no se inventa una semilla de vuelo. La revisión Git puede venir del harness; los hashes identifican los archivos incluso en un árbol sucio.

Las capturas UI producen un sidecar nativo `openrc-ui-capture v2`. En Inicio → Volar se desactiva el avance automático antes de ceder un frame, se integra exactamente hasta 1,5 s y se dibuja la pose resultante. El contador y la cámara activa se comprueban después de liberar Inicio. El tiempo hasta el primer frame de vuelo se registra aparte, con caché **desconocida** y sin afirmación de rendimiento. Ayuda/pausa/hint conservan su función de inspección de interfaz; los snapshots de vuelo variable se etiquetan como tales.

[Hoja de referencias y licencias](REFERENCES.md): campo RC, acabado de avión y tres encuadres propios de aceptación. Las fotografías permanecen en documentación, fuera del runtime.

## Registro de tiempos

Se amplía `_log_frame_time()`; `render/frame_samples.gd` solo recoge/valida intervalos y construye sus agregados. No crea otra simulación ni otra configuración de usuario.

- `--frametimes=archivo.json --warmup=10 --t=60` solicita calentamiento y muestra; por compatibilidad los valores por defecto siguen siendo 1 y 20 segundos.
- `openrc-frametimes v2` conserva `frames`, `seconds`, `fps_mean`, `frame_ms`, `physics_us_per_tick`, dispositivo/API/Godot/SO, ventana, VSync y nota. **Los agregados usan ahora reloj monotónico real**; `engine_*` conserva por separado el `delta` de Godot, que puede estar recortado bajo carga.
- Guarda todos los intervalos crudos, marcas monotónicas y métricas por frame, incluidos tiempo/tick de simulación. Los percentiles se pueden recalcular. El dato de coste físico sigue siendo el monitor suavizado existente, no una medida GPU.
- El primer `_process` establece el origen; un frame que cruza el calentamiento se excluye completo. Desde el siguiente intervalo se mide la duración solicitada. El último frame se conserva íntegro, por lo que puede haber sobrepaso. Quedan guardados el calentamiento y los extremos reales.
- `--scripted` identifica `scripted-fixed`: entrada desactivada y trayectoria, reloj visual y hélice ligados al tiempo monotónico. Sin ese argumento se identifica `live-input`, incluso si nadie toca los mandos. Una radio conectada no convierte un vuelo en replay fijo.
- `preset=current-default` describe la configuración actual; todavía no existen perfiles Bajo/Alto/Ultra. Se registran MSAA, escalado, cámara y backend efectivos.
- Números inválidos, combinaciones con `--capture`/`--trace` y fallos de escritura devuelven error. Límites del registrador: calentamiento ≤ 3600 s; muestra > 0 y ≤ 300 s. Son límites de diagnóstico/memoria, no límites de vuelo.

En un pack exportado no se prometen hashes de fuentes que Godot haya omitido: `source_tree_available=false` lo declara, y `BuildInfo` aporta la identidad del build. El smoke del binario Linux comprueba esa ruta.

## Reproducción

```bash
app/test.sh
app/capture.sh

# Solo la matriz nueva, reutilizando las guardas existentes:
"$(app/tests/visual-env.sh)" app/tests/visual_quality_cases.py \
  --app app --godot "$(app/get-godot.sh)" --out app/captures/vq01b

# Tres procesos nuevos: 10 s de calentamiento + 60 s de muestra cada uno.
# Este runner usa Xvfb/OpenGL: valida el protocolo, no la GPU del propietario.
"$(app/tests/visual-env.sh)" app/tests/visual_quality_cases.py \
  --app app --godot "$(app/get-godot.sh)" --out app/captures/vq01b --performance-only

app/export.sh
```

Para medir en la máquina del propietario, ejecutar el **export** en pantalla normal con `-- --scripted --frametimes=run-1.json --warmup=10 --t=60 --case=scripted-60s`; repetir en tres procesos y guardar cada JSON. Comparar con misma resolución, VSync, refresco del monitor y configuración. Para una ronda sin VSync, añadir `--disable-vsync` antes de `--`. Registrar SO/driver/refresco del monitor; realizar profiling CPU/GPU en otra sesión y no borrar cachés del usuario. Un proceso nuevo no acredita caché de shaders fría.

## Prueba y límites

Los logs, manifiestos, datos de medición y selección de imágenes de esta entrega se guardan junto a este archivo. Las 112 imágenes completas y su archivo comprimido se conservan localmente en `app/captures/vq01b-validation/`; el repo versiona la selección visual y los datos del ensayo. [validation.json](validation.json) identifica los archivos validados y el resultado de cada comprobación. La [galería](gallery.html) permite revisar los casos; los PNG completos temporales se regeneran bajo `app/captures/`.

Resultados: **112 capturas válidas**, nueve pares de campo idénticos, 38 PNG anteriores idénticos y datos de traza intactos. Pasan 18 pruebas del productor, 14 del inventario, 43 del muestreador y 65 de poses/procedencia, además de las suites completas. Los tres exports pasan; el binario Linux valida vuelo y logger. Windows/macOS se comprueban como paquetes, no se ejecutan nativamente en esta máquina.

La revisión está aislada en un clon limpio del snapshot de trabajo, sin copiar `.godot` ni capturas previas. Se comprueban suite del juego, inventario y repetición, paridad con el baseline, los tres exports y smoke Linux. Los goldens físicos y umbrales L1–L4 no se regeneran ni se relajan. El manifiesto registra código sucio del repo compartido por hashes; el commit privado del clon es solo identidad del ensayo, no un commit en la rama del usuario.

La incorporación concurrente del P-51 se verificó después mediante otra ejecución completa de la suite y ocho capturas con el catálogo de cuatro aviones. Seis imágenes de vuelo/campo/inspección coincidieron byte a byte con la matriz completa; Inicio cambia su contador a cuatro aviones. Se actualizó en la copia de validación la prueba de navegación que el autor del P-51 había terminado mientras corría el primer intento. El [log final de integración](integration-tests.log) es la ejecución aprobada.

**Pendiente de hardware:** rendimiento/pacing en export con RTX 3090 y equipo modesto, cachés fría/caliente controladas y lectura humana. Ninguno se deduce de llvmpipe. Las tres muestras locales coinciden con otros procesos de QA: acreditan duración, datos crudos y rutas, y no se usan para comparar velocidad ni establecer presupuestos. VQ-01b no añade vegetación ni presets. **Siguiente paso: L5**, loader y constructor de campo compartido entre Inicio y vuelo, conservando estas referencias.
