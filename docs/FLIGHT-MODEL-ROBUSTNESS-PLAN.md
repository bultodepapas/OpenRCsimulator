# Plan de robustez y realismo del modelo de vuelo

> Actualización 2026-10-06: reparación implementada en el árbol de trabajo. Ver [cambios, pruebas y límites](research/flight-repair-implementation.md). D9-R1/R2, D4-R1, D1-R1 y D8a-R1 tienen implementación y regresiones; el rudder usa superficies/derivadas enlazadas. Gate 2 (validación con piloto), propwash y equilibrio de eje siguen abiertos. El texto fechado 2026-10-05 se conserva como plan original.

2026-10-05 · Propuesta de continuación de D8b, D9, D10, Gate F y E0. **Implementado el 2026-10-06 (nota superior); pendientes Gate 2-R (piloto), E0b, G2 y D8b-R1 (matriz de manejo multi-eje).**

[Evidencia y límites](research/flight-model-robustness-audit.md) · [Mediciones reproducibles](research/flight-robustness/results.json) · [Plan específico del rudder](RUDDER-REPAIR-PLAN.md).

**Decisión recomendada:** conservar el núcleo float64, el paso fijo, la separación de datos y las pruebas existentes. Corregir primero los defectos matemáticos y las condiciones de aceptación de vuelo; luego calibrar respuestas y ampliar superficies. No intentar obtener realismo reduciendo todos los mandos ni aumentando ticks de física.

## Orden de trabajo

| Paso propuesto | Prioridad | Cambio acotado | Prueba necesaria para cerrarlo |
| --- | --- | --- | --- |
| D9-R1 | P0 | Reparar la mezcla global/local al cruzar flujo invertido | El salto de ~1.842 N tiende a cero al reducir ε; cubre p/q/r no nulos, ambas ramas y mandos |
| D9-R2 | P0 | Construcción coherente de fuerzas y momentos de las franjas; eliminar generación artificial de energía | Casos de potencia positiva dejan de generarla bajo supuestos pasivos; no basta clamping de CD; trim, stall y recuperación siguen correctos |
| D4-R1 | P0 | Rechazo transaccional de aeronave/condición inicial sin trim | La variante elevator 1° conserva sesión previa al recargar, o queda pausada si no existe sesión válida; nunca lanza un respaldo silencioso |
| D8b-R1 | P1 | Matriz de manejo multieje y maniobras cruzadas | Límites documentados para autoridad, respuesta y recuperación; restaurar el defecto debe hacer fallar el test |
| D10-R1…R3 | P1 | Calibrar rudder junto con estabilidad y geometría | Mejora de manejo sin romper coordinación ni recuperación; el candidato ×0,3 actual no cumple |
| D1-R1 | P1 | Reconciliar masa, CG, inercias, recorridos y referencias | Una configuración física coherente, con incertidumbres y trazabilidad; no mezclar CG objetivo con inventario incompatible sin declarar el supuesto |
| D8a-R1 | P1 | Alinear el evaluador de dinámica usado por vuelo y herramientas | Jacobianos contrastados contra derivadas del runtime; separar modos naturales de transferencia stick→movimiento |
| Gate F / E0a | P2 | Cola horizontal y vertical como superficies; después completar franjas del ala | Fuerza y momento con el mismo flujo/brazo, sin contar dos veces derivadas; equivalencia local y validación de maniobras |
| E0b / G2 | P2 | Propwash y balance de eje motor/hélice en pasos separados | Respuesta a potencia y velocidad sustentada en datos; torque, empuje, RPM y energía coherentes |
| Gate 2 | En cada candidato | Playtest comparativo, trazas y valoración por eje | Piloto confirma control dosificable y maniobras; evidencia externa separada de coherencia interna |

Los IDs con sufijo R son subpasos propuestos, no nuevas tareas completadas del ROADMAP. Cada uno se entrega en un cambio pequeño con su prueba y su entrada en LEARNINGS.

## 1. Definir tres clases de pruebas

**Integridad física y numérica:** continuidad respecto a velocidades reales (incluido el corte ±π), finitud, signos con explicación física, balance de fuerzas/momentos y de energía bajo supuestos explícitos, inercia físicamente válida, y convergencia temporal. Estas pruebas pueden rechazar un modelo sin tener telemetría de un Ugly.

No exigir que cada momento se oponga siempre a su velocidad angular: una autorrotación puede transformar energía de traslación/descenso en rotación. Comprobar la potencia total en el marco adecuado. Con viento, hélice, superficies móviles o un modelo aerodinámico con memoria, incluir sus aportes; no trasladar indiscriminadamente el criterio pasivo del probe a todos los estados.

**Regresión funcional:** golden flights, rutas de teclado/radio/gamepad, servo, trim, pausa, reinicio, crash y export. Garantizan que el comportamiento no cambie accidentalmente; un golden no demuestra que ese comportamiento represente al avión real.

**Validación de manejo:** amplitud y tiempo de respuesta por eje, coordinación, resbalamiento, pérdida/recuperación y efecto de potencia, contra mediciones o bandas con incertidumbre. Si solo existe juicio de piloto, etiquetarlo como tal. Reservar parte de los vuelos para validar después de ajustar, en vez de calibrar y evaluar con la misma maniobra.

## 2. Reparar las fuerzas antes de retocar sensaciones

En D9-R1 aislar primero la discontinuidad: sustituir/restar términos definidos sobre la misma base, sin mezclar un α global discontinuo con déficits locales de otras ramas. Probar que la solución no agrega otra discontinuidad al empezar la pérdida ni cambia el régimen lineal intencionalmente conservado.

En D9-R2 usar como objetivo una fuerza por elemento construida a partir de su velocidad local `v + ω×r`, presión dinámica local y orientación. Sumar su fuerza y su momento `r×F` en el mismo punto de referencia. El viento se resta en el marco correcto; propwash entra posteriormente como otro flujo local.

Si se conserva temporalmente el método de déficits, definir exactamente qué contribución se reemplaza y cómo se conserva su consistencia energética. No restar una media de drag local a una base global distinta. No escalar únicamente momentos para que un coeficiente coincida sin revisar el balance total resultante.

Preservar la equivalencia del régimen válido y las derivadas pequeñas **que sigan justificadas**. El oráculo sirve para detectar cambios involuntarios, no para impedir corregir un dato erróneo. Actualizar DECISIONS si cambia la arquitectura de mezcla; mantener nodos/bisagras del equipo visual.

## 3. Calibrar el avión como conjunto

El orden evita compensar un error con otro:

1. Masa, CG e inercia de una configuración: pesar, localizar componentes/CG y medir inercias si es posible; recalcular al mover batería o lastre. No corregir inercia trasladándola a un punto que no es el CG real.
2. Recorridos físicos y posición neutral; medir tiempo y excursión del servo. Distinguir grados totales, incremento sobre trim y mando normalizado.
3. Trim, resistencia y planeo a varias velocidades.
4. Respuestas pequeñas por eje y acoplamientos laterales; estudiar conjuntamente `Cndr/CYdr/Cldr`, estabilidad y amortiguamiento con rangos de evidencia.
5. Pérdida, recuperación y maniobras grandes, incluyendo ambos sentidos y potencia.

No declarar el avión «2× demasiado rápido» solo por compararlo con otro Stik escalado. Usar esa diferencia para priorizar mediciones. Los modos de avión con controles congelados no miden el retraso total de radio+servo; añadir pruebas de transitorio para conocerlo.

El rudder ×0,3 debe permanecer como contrafactual. Su mejora del pulso viene acompañada de fallo de la recuperación existente. Revisar toda la secuencia y su física; no reducir simplemente el objetivo del test ni alargar un pulso hasta producir verde sin justificación.

## 4. Endurecer carga, estado y procedencia

La preparación de una aeronave debe ser una operación completa: parsear → validar esquema/unidades → derivar masa/geométrica → comprobar plausibilidad → resolver condición inicial → aceptar conjuntamente. La sesión activa solo cambia después de esa aceptación. Un hot reload fallido conserva avión, estado y trims anteriores; un primer arranque fallido muestra el motivo y no inicia vuelo.

Añadir reglas de plausibilidad relacionadas entre sí: autoridad por grado frente a estabilidad, relación fuerza/momento con brazos geométricos, capacidad de trim y márgenes de superficie. Las bandas de plausibilidad se definen por modelo y evidencia; no bloquear todos los aviones futuros con los números del Stik.

Mantener `{value, unit, kind, source}` y añadir de forma acotada metadatos de validez donde falten: configuración/versión, rango de α/β/velocidad/deflexión/Reynolds, incertidumbre y procedimiento de derivación. Datos fuera de rango deben poder diagnosticarse; no inventar precisión añadiendo decimales.

En runtime, proponer detección explícita de estados/cargas no finitos, cuaternión degenerado y preparación inválida. Pausar y conservar la última traza válida con causa legible. **No pausar por α alto, invertir el avión o un rate grande por sí solos**: son estados legítimos de un simulador acrobático. Un guard no debe ocultar la física defectuosa con clamps arbitrarios.

## 5. Una dinámica compartida por vuelo y análisis

Extraer, cuando se implemente D8a-R1, una evaluación pura y pequeña de cargas/derivadas con contexto explícito: avión derivado, estado, superficies reales, RPM, viento y densidad. `FlightSession` conserva el ciclo de vida y los dispositivos; esa función representa la física y se usa desde runtime, trim y herramientas cuando corresponda.

Incluir el término giroscópico en análisis que se anuncien como equivalentes al vuelo. Si se usa la separación longitudinal/lateral, declarar qué acoplamientos descarta y cuantificar su error frente a la matriz completa. Revisar la fiabilidad del cálculo de autovalores al ampliar matrices; no asumir que el solver casero probado en 4×4 se generaliza sin validación.

Separar estado de cuerpo y actuadores de forma explícita en las herramientas. Mantener determinismo y float64. Las mediciones 240/480/960 Hz no justifican hoy cambiar el tick de producción; definir tolerancias y repetir en condiciones nuevas si cambia la integración o el acoplamiento.

## 6. Instrumentación que ayude a ajustar sin esconder el problema

Añadir al modo de diagnóstico: entrada cruda → mando con trim → grados reales, β/α, p/q/r, presión dinámica, y contribuciones de fuerza/momento de ala, cola y propulsión cuando existan. Guardar también versión/hash del avión, perfil de entrada, escenario, dt y condiciones ambientales.

En pruebas de desarrollo, registrar potencia aerodinámica y propulsiva, energía cinética/potencial y motivo de salida de envolvente. El CSV actual tiene estado/cargas/servos, pero para investigar contribuciones habría que ampliarlo con versión de formato. Los campos técnicos pertenecen al panel de diagnóstico y a las trazas; el vuelo normal debe seguir siendo sencillo.

## 7. Aplicación a Extra 300, Avanti y próximas aeronaves

El solver común debe aprobar las pruebas de integridad antes de validar aviones nuevos. Cada avión necesita sus propios datos, límites de validez y vuelos de aceptación. Compartir algoritmos no autoriza compartir sin validación los coeficientes del Ugly.

Separar área de ala, cuerda media geométrica y cuerda aerodinámica media antes de introducir alas afiladas. Definir capacidades de propulsión/control que cada avión realmente tenga; evitar requisitos de hélice de pistón para un EDF/turbina. Estas son condiciones de futura integración, no una afirmación de que esos aviones ya estén implementados.

## Entrega y criterio de cierre

Primera entrega: pruebas rojas reproducibles de discontinuidad/energía/trim y sus correcciones pequeñas. Segunda: autoridad del rudder calibrada sin romper maniobras cruzadas. Tercera: superficies y propulsión ampliadas con evidencia. En cada entrega, conservar comparación antes/después y actualizar goldens solo por cambios deliberados aceptados.

Ejecutar checks dirigidos tras cada cambio y `app/test.sh` antes de integrar scripts en `app/`. Medir coste por tick si cambia aerodinámica. Evaluar con el piloto después de cada cambio de manejo. Las modificaciones están en producción desde el 2026-10-06; este texto conserva el plan original.
