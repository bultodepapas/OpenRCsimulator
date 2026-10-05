# Reparación de la autoridad del rudder — Ugly Stik

2026-10-05 · Estado: **diagnosticado en simulación; reparación pendiente**.

**Ampliación posterior:** [auditoría del modelo completo](research/flight-model-robustness-audit.md) y [plan de robustez](FLIGHT-MODEL-ROBUSTNESS-PLAN.md). La variante `Cndr ×0,3` rompe la secuencia de recuperación de barrena existente (p/r residual máximo después de 6 s: 6,49 rad/s frente a 0,22); no adoptarla como parche aislado. Se localizaron además discontinuidades de la mezcla por franjas y estados con potencia aerodinámica positiva, que necesitan sus propias correcciones.

**Prioridad:** cerrar este problema de Gate 2 antes de ampliar propwash o takeoff. Un pulso de rudder de medio segundo a 15 m/s puede llevar el modelo a autorrotación; reducir únicamente el coeficiente de momento evita esa entrada en el escenario reproducido. La autoridad prestada y los 25° estimados necesitan validación conjunta con el comportamiento a grandes ángulos.

[Diagnóstico, evidencia, límites y comandos reproducibles](research/ugly-stik-rudder-audit.md) · [19 experimentos](research/rudder-audit/results.json).

Este plan continúa D8b/D10 y Gate 2. No reabre todo el simulador. Los IDs siguientes son subpasos propuestos de esas tareas; no están completados salvo el diagnóstico descrito.

## D10-R1 — Convertir el síntoma en contrato de manejo

**Trabajo:** conservar el escenario rojo, añadir a `app/tests/` una prueba de autoridad y recuperación usando la sesión real. Primero registrar la traza del usuario con T y el dispositivo, trim, velocidad y gas; si aún no está disponible, usar la reproducción archivada como caso de ingeniería provisional.

Matriz mínima: izquierda/derecha; 10/25/50/100% de mando; pulsos de 0,1/0,25/0,5 s y mantenido 2 s; 12/15/20 m/s; vuelo trimado y planeo. Para aislar efecto de potencia, añadir estados iniciales idénticos con idle/cruise/full y documentar que dejan de estar trimados. No confundir esa prueba con planeos retrimados. Ejecutar los casos seleccionados por entrada directa, teclas reales inyectadas, radio y gamepad simulados.

**Medir:** entrada cruda, mando con trim, posición de servo, δr en grados, β/α, p/r de cuerpo, actitud, velocidad, altitud, tiempo de vuelta a trim y rotación residual 0,5/1/2 s después de soltar. No usar solo rumbo Euler o «no hubo crash».

**Aceptación propuesta, marcada `estimated` hasta contrastarla:** en el doblete de referencia a 15 m/s, |β| pico ≤25°, |r| pico ≤120°/s y |r| a 1,5 s de soltar ≤15°/s; sin entrada en autorrotación. Estas bandas sirven para discutir y detectar la regresión; no se extrapolan automáticamente a full rudder sostenido, vuelo acrobático o proximidad a pérdida. Registrar el origen de cada banda y separar pruebas de implementación de validación física.

**Prueba de que el test sirve:** debe fallar con el dato actual y detectar una mutación que reinstale ese dato. El experimento `Cndr ×0,3` satisface solo parte de la evidencia preliminar; no basta para cerrar esta tarea.

## D10-R2 — Reconciliar recorrido y derivadas con el avión

**Trabajo:** revisar `Cndr`, `CYdr`, `Cldr`, `Cnb`, `Cnr`, CG/ARP y recorrido como conjunto. Usar plano/geometría del equipo de modelo para área de deriva/timón, brazo y fracción móvil, con incertidumbre explícita. Buscar recorrido en documentación específica del Jensen o medir una construcción; fuentes de Ultra Stick siguen siendo `borrowed`, nunca `measured` del Ugly.

Derivar un intervalo razonado para fuerza lateral y momento por grado, documentando la referencia de área/envergadura y sus signos. Contrastar la palanca equivalente de 1,443 m con la distribución real de superficies. Verificar que el plano visual y los datos físicos usan el mismo datum; no asumir que el origen del mesh es el CG.

**Archivos previstos:** `app/data/aircraft/jensen_ugly_stik_60.json` y evidencia en `docs/research/`. No alterar nodos ni bisagras del modelo. Cada número conserva `{value, unit, kind, source}`. Toda derivación nueva lleva fórmula, entradas e incertidumbre.

**Criterio de salida:** distinguir qué dato contradice geometría/medición y qué solo es una calibración de manejo. Si falta evidencia externa, el candidato se etiqueta provisional y queda pendiente Gate 2. No elegir `−0,05433` simplemente porque es el 30% que hizo pasar una prueba.

## D10-R3 — Aplicar la corrección más pequeña sustentada

**Orden recomendado:** corregir primero el dato de autoridad que R2 justifique, manteniendo constantes las otras variables; retrimar cada variante y repetir R1. Investigar con mayor resolución la transición entre 40 y 50% de `Cndr` observada en el diagnóstico. Solo modificar otros coeficientes si su evidencia y su efecto aislado lo justifican.

Si el recorrido físico de 25° se confirma, conservarlo y corregir el modelo aerodinámico. Si se demuestra que el recorrido es erróneo, corregirlo en los datos, de modo que física y bisagra sigan coincidiendo. Las variantes de 10° y `Cndr ×0,3` ya medidas son puntos del barrido, no decisiones tomadas.

**No usar como solución causal:** expo, deadzone o ralentizar el servo. Expo conserva full rudder; el problema se reproduce con entradas válidas. Tampoco duplicar amortiguamiento o estabilidad sin evidencia: los experimentos `Cnr ×2` y `Cnb ×2` no eliminan el comportamiento extremo y afectarían modos de vuelo.

**Pruebas:** autoridad, trim sostenido, coordinación de viraje, alabeo con pies quietos, resbalamiento intencional, pérdida/barrena y recuperación. El timón debe conservar utilidad; una reducción que solo impida maniobras no es una reparación suficiente.

**Riesgo:** cambia el trim de yaw y la combinación aileron/rudder necesaria para compensar el motor; también pueden cambiar la entrada/salida de barrena y los goldens. Registrar comparaciones antes/después, no solo un resultado verde.

## Gate F / E0a-R — Revisar el modelo de cola si el ajuste no basta

Esta rama se activa si datos coherentes en R2/R3 no permiten a la vez manejo normal y maniobras esperadas, o si la respuesta fuera del régimen lineal sigue siendo incoherente.

Revisar la asimetría actual: el restaurador usa sin(β), mientras la autoridad del timón permanece lineal a cualquier α/β. La solución física preferible es la deriva como superficie con flujo local, presión dinámica, deflexión y pérdida propios; generar fuerza y momento con el mismo brazo. Es la ampliación vertical de **E0a**, decidida en Gate F, no una reescritura de toda el ala.

Retirar la contribución de cola de las derivadas globales para no contar dos veces estabilidad, amortiguamiento o fuerza de control. Preservar el oráculo de pequeño ángulo **respecto al modelo corregido**, no congelar el dato defectuoso. Separar pruebas de equivalencia matemática y validación de autoridad.

**Aceptación:** curvas continuas en β y δr, signos correctos, fuerza/momento coherentes, amortiguamiento local comprobado, integración estable al comparar dt y dt/2, maniobras R1/R3 y coste de física medido. Mantener float64 en simulación.

Propwash sigue siendo **E0b**, una tarea posterior y separada. No explica el exceso actual: todavía no está implementado y el síntoma existe con motor parado. Añadirlo antes de controlar la autoridad podría agravar el manejo a baja velocidad.

## D6 / Gate 2-R — Ajustar sensación de entrada y validar volando

Una vez corregida la respuesta física, comprobar radio real calibrada y gamepad, y evaluar un perfil de teclado con rates por eje si sigue siendo difícil dosificar. Mostrar qué recorrido manda y qué superficie alcanza. Los rates/expo de usuario pertenecen a configuración de entrada; los grados físicos máximos y el servo pertenecen al avión.

**Sesión de aceptación:** mismo circuito, viraje coordinado, resbalamiento, rudder a ambos lados con liberación, pérdida y recuperación; comparar con un Ugly real cuando sea posible. Registrar valoración −2…+2 por eje según Gate 2, dispositivo, ajustes y trazas. Objetivo: yaw dentro de ±1 sin perder maniobras ni ocultar la entrada en pérdida. La validación con el propietario sigue pendiente; esta investigación headless no la sustituye.

## D8a-R — Cerrar la regresión y entregar

1. Ejecutar las nuevas pruebas de autoridad y la matriz seleccionada; documentar qué límites son medidos y cuáles siguen estimados.
2. Ejecutar `app/test.sh`: señales/unidades, entrada, servo, modos, trim, stall/spin, crash, contrato del modelo y frame-rate independence. Si cambian respuestas deliberadamente, explicar cada expectativa revisada; no relajar bandas para recuperar verde.
3. Comparar goldens antes/después. Regrabar con `tests/record_golden.gd` solo tras aceptar el cambio físico y conservar su justificación. Mantener separado el doblete pequeño de manejo normal del caso agresivo usado para explorar pérdida.
4. Verificar `bench_physics.gd` si cambia código aerodinámico; capturas si cambia recorrido visual; prueba de dt frente a dt/2 si cambia la dinámica. No ampliar checks irrelevantes a un cambio de documentación.
5. Actualizar ROADMAP, DECISIONS si cambia la arquitectura y LEARNINGS tras cada paso. Un commit por paso, con traza/test/medición como prueba. No publicar una release antes de cerrar la validación de manejo elegida.

**Entrega mínima aceptable:** el caso original deja de provocar la respuesta excesiva bajo el contrato acordado, el timón sigue coordinando y recuperando, queda una prueba que falla al restaurar la causa, y el ajuste tiene una procedencia explícita. La implementación permanece pendiente; este cambio entrega el diagnóstico y el plan.
