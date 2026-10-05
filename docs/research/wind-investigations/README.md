# Doce investigaciones para mejorar el plan de viento

**Fecha:** 2026-10-05. **Estado:** investigación aplicada al [WIND-PLAN](../../WIND-PLAN.md), sin meteorología implementada en la app. Doce preguntas independientes, agrupadas en tres notas para facilitar su lectura. Cada investigación conserva fuentes primarias, aplicación al código, cambio de plan y prueba propuesta; la evidencia ejecutada se distingue de propuestas.

## Índice y consecuencias

| # | Investigación | Mejora concreta al plan | Paso |
| --- | --- | --- | --- |
| 01 | [Ciclo físico, prioridades y pausa en Godot](01-04-godot-runtime.md) | Avance desde `sim.step()` también en captura/traza; clima y avión comparten ralentización del tick | W01b, W02a |
| 02 | [RNG, precisión efectiva y checkpoints](01-04-godot-runtime.md) | Seed/state más filtros y agenda; escalado float64, restauración ordenada y evaluación de cuantización | W02c, W04a |
| 03 | [Profiler, Performance y benchmark](01-04-godot-runtime.md) | Medición por ventanas/percentiles y contadores puros; separar coste instrumentado y presupuesto | W01b, W04a, W05c |
| 04 | [CLI headless, fps fijo, export, GUT y GdUnit4](01-04-godot-runtime.md) | Ampliar arnés existente y smoke exportado; render y simulación se comprueban por rutas apropiadas | W01d, W04b |
| 05 | [SciPy Welch, CSD y coherencia](05-08-analysis-tools.md) | PSD/RMS/correlación con unidades, resolución y normalización explícitas | W04a, W06a |
| 06 | [Discretización de filtros y ruido](05-08-analysis-tools.md) | Distinguir discretización determinista de covarianza de innovaciones e inicialización estacionaria | W04a, W06a |
| 07 | [JSBSim como referencia independiente offline](05-08-analysis-tools.md) | Comparación aislada de clima/ráfagas con versión, ejes, unidades y parámetros fijados | W02b, W06a |
| 08 | [TurbSim/OpenFAST y campos espaciales](05-08-analysis-tools.md) | Evaluar coherencia e importación de fixtures sin trasladar presets eólicos a aviones RC | W05b, W06a |
| 09 | [JSON, ConfigFile y JSON Schema](09-12-config-render.md) | Preservar floats e int64; validación nativa de dominio y esquema offline opcional | W01a, W01d |
| 10 | [SpinBox, Range y foco](09-12-config-render.md) | Abrir o convertir unidades no redondea configuración activa; Aplicar consolida texto pendiente | W03b |
| 11 | [ImmediateMesh/MultiMesh para diagnóstico](09-12-config-render.md) | Flechas de muestras por posición/altura; buffers visuales nunca gobiernan el viento | W04b, W05b |
| 12 | [Particle shaders y propiedad de la integración](09-12-config-render.md) | Evitar advección doble y desfase de velocidad; comparar transporte con solución CPU | W07 |

Los IDs son los del plan M5 (`M5-Wxx`). No se han abierto doce frentes de implementación: estas investigaciones afinan la misma secuencia pequeña de entregas.

## Selección de herramientas

| Herramienta | Uso recomendado | Decisión de esta ronda |
| --- | --- | --- |
| Godot 4.7.2 nativo | Runtime, controles, serialización, diagnóstico y pruebas actuales | Mantener el pin; no añadir framework |
| SciPy | Análisis de señales y oráculos numéricos offline | Candidato para scripts reproducibles; fijar versión/entorno cuando se adopte |
| JSBSim | Referencia externa de componentes meteorológicos | Ensayo aislado, sin reemplazar física de OpenRC |
| TurbSim/OpenFAST | Estudiar/generar fixtures espaciales para comparación | Posterior y fuera de runtime; parámetros de energía eólica no son datos RC |
| pyTurbSim | Referencia alternativa de dominio acuático | No adoptar como dependencia; revisar alcance y licencia antes de reutilización |
| python-jsonschema | Validar catálogo de datos offline | Opcional; no reemplaza reglas físicas del loader |
| GUT / GdUnit4 | Marcos de pruebas Godot | Mantener harness actual; reconsiderar ante una carencia concreta |
| ImmediateMesh / MultiMesh | Diagnóstico y visualización de muchas muestras | Pocas líneas primero, instancing tras medición |
| Shader de partículas | Transporte visual coherente con W | Spike de advección antes de conectarlo al humo |

Las versiones consultadas, licencias y límites constan en las notas. Mencionar una librería no la instala ni demuestra compatibilidad del sistema completo. No se añadieron dependencias de ejecución.

## Evidencia de esta ronda

**Ensayo ejecutado:** [probe de configuración y controles](probe_config_controls.gd), [resultado estructurado](config-controls-probe.json), reproducción al final de [investigaciones 09–12](09-12-config-render.md). Godot 4.7.2-stable: **10 comprobaciones, 0 fallos**, salida 0 sin errores del motor. Prueba serialización/round-trip y comportamiento de widgets dentro del árbol; no es una prueba de viento integrado.

Se comprobó pérdida de precisión con JSON predeterminado, conservación con `full_precision`, redondeo de enteros grandes como número JSON, conservación como cadena, comas finales aceptadas, int64 en ConfigFile y cuantización/señales/texto pendiente de SpinBox. La primera versión del arnés omitía insertar el control en SceneTree y por ello no recibía señales; se corrigió contra código fuente, sin modificar `app/`.

**Experimentos SciPy ejecutados:** la [nota 05–08](05-08-analysis-tools.md) conserva un ensayo OU de 900 s y un cálculo de covarianza discreta. En la misma serie, el RMS temporal fue 0.502766 m/s y el espectral bajó a 0.426056 m/s con segmentos cortos y detrend local: la configuración del análisis puede ocultar energía lenta. La exponencial de bloque recuperó la covarianza OU exacta dentro del error numérico. Se usaron SciPy 1.11.4 y NumPy 1.26.4 ya instalados; son pruebas del análisis, no del viento en Godot.

La validación estadística de una implementación de viento, integración con JSBSim/TurbSim, visualización espacial y nuevos shaders permanecen propuestas. No se ejecutó la suite completa `app/test.sh` ni se midió nuevo rendimiento del simulador en esta entrega de investigación.

## Continuidad con la investigación anterior

- [Física y fuentes primarias](../wind-physics-primary-sources.md): convenciones, perfiles, Dryden/von Kármán, alcance RC.
- [Auditoría inicial Godot](../wind-godot-integration.md): puntos de integración ya identificados.
- [Plan revisado](../../WIND-PLAN.md): decisiones de estas doce investigaciones y pruebas por entrega.
- [Investigaciones de humo](../smoke-investigations/README.md): compartir contrato visual y reloj; no duplicar el controlador del otro frente.
- [Foco y radio en menús](../menu-investigations/02-input-focus-radio-isolation.md): aplicar al editor de condiciones.

La siguiente implementación sigue siendo **M5-W01a**, ahora con reglas más precisas de formato, validación y conservación de valores. Las herramientas estadísticas y espaciales entran cuando el paso correspondiente las necesita.
