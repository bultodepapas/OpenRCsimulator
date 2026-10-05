# Alcance del problema del rudder y robustez del modelo de vuelo

2026-10-05 · Continuación de [la auditoría del rudder](ugly-stik-rudder-audit.md).

**Conclusión:** el síntoma extremo del rudder no se reproduce en los pulsos equivalentes de elevator y alerones, pero la debilidad que permitió conservarlo sí es transversal: validar signos, continuidad a velocidades angulares cero y reproducción de trayectorias no establece realismo. Además, aparecen defectos concretos en la envolvente con rotación y en el rechazo de una configuración sin trim. Reducir el rudder aisladamente cambia coordinación y recuperación de barrena.

La física de producción permanece intacta. Se ejecutaron 26 vuelos de 3 s, dos maniobras de barrena de 8 s, un barrido estático de 925 estados y casos aislados de datos. [Resultados, estados finales y hashes](flight-robustness/results.json). El HEAD avanzó de `90374d2` a `83f2035` durante el trabajo compartido; los hashes de la física usada en la auditoría anterior permanecen iguales. [Plan de mejoras](../FLIGHT-MODEL-ROBUSTNESS-PLAN.md).

## 1. Qué se extiende a los otros mandos

Cada vuelo parte de trim, aire en calma y 100 m de altura para estudiar la respuesta sin el reinicio por impacto. Aplica un único pulso de 0,5 s entre t=0,5 y 1 s; después vuelve a los trims. El motor mantiene el gas de trim. Los máximos se observan durante los 3 s completos. `p/q/r` son velocidades angulares del cuerpo, no derivadas de ángulos Euler.

| Mando a 15 m/s | Pico α absoluto | Pico β absoluto | Velocidad del eje mandado | Resultado observado |
| --- | ---: | ---: | ---: | --- |
| Alerón +25% | 3,73° | 3,39° | p 31,83°/s | Respuesta moderada, sin régimen extremo |
| Alerón +100% | 3,73° | 11,91° | p 122,98°/s | Alabeo con guiñada adversa |
| Elevator +25% | 5,93° | 0,59° | q 21,21°/s | Respuesta moderada |
| Elevator +100% | 10,32° | 1,54° | q 63,31°/s | Pull-up, sin autorrotación extrema |
| Elevator −100% | 5,74° | 2,62° | q 85,16°/s | Respuesta distinta a pull-up; no implica signo erróneo |
| Rudder +25% | 4,91° | 17,27° | r 56,72°/s | Mucho acoplamiento: p llega a 64,25°/s |
| Rudder +100% | 68,07° | 42,41° | r 462,14°/s | Autorrotación; p llega a 576,18°/s |

Los casos de alerón/elevator a 12 y 20 m/s tampoco reproducen el fallo extremo del rudder. Esto **no certifica su realismo**: solo acota el fallo para esos pulsos. Mantener elevator o entrar voluntariamente en pérdida es otra maniobra.

El trim de elevator a 15 m/s es +0,2353 de mando. Como se suma trim y se limita a ±1, la excursión adicional disponible desde neutral no es simétrica. La aerodinámica positiva/negativa tampoco lo es. Antes de tratar diferencias push/pull como bug, comparar los grados reales de superficie, no solo ±100% del stick.

El modo corto recalculado a 13,8 m/s es **1,882 Hz, ζ 0,780**, y la constante de alabeo **0,05555 s**. Reproduce los resultados previos en `research/sensitivity/results.md`. Esa investigación comparó con un Ultra Stick 120 escalado y obtuvo pitch 1,45× y roll ~2,09× más rápidos. Es una **alerta de validación con otro avión**, no evidencia de que el Ugly deba tener exactamente sus números. El PDF primario de UMN enlazado en RESEARCH devolvió 403 en esta sesión; no se presenta esa comparación como una nueva validación independiente.

## 2. Corregir el rudder sí cambia otras maniobras

Se repitieron dos comportamientos con `Cndr ×0,3`, sin otros cambios de datos:

| Prueba | Base | Con Cndr ×0,3 |
| --- | ---: | ---: |
| Alabeo coordinado: pico p | 142,77°/s | 122,62°/s |
| Alabeo coordinado: pico β absoluto | 1,48° | 3,48° |
| Barrena: máximo de p/r absolutos entre 6 y 8 s, tras la secuencia de recuperación existente | 0,221 rad/s | **6,488 rad/s** |

La coordinación usa el mismo controlador de prueba `yaw = clamp(10 β)`. Parte de la diferencia es que su ganancia deja de corresponder a la planta modificada. No concluir de aquí que el alerón perdió su autoridad física.

La recuperación es exactamente la de `Maneuvers.spin_right`: pitch + yaw, motor a idle; entre 4 y 4,9 s, timón opuesto y stick adelante; después neutro. Con el nuevo dato cambian tanto entrada como recuperación. La prueba demuestra que **esa secuencia completa deja de recuperar**; no demuestra que cualquier técnica de recuperación sea imposible. El umbral del test actual exige p y r menores de 1 rad/s después de 6 s; la variante no lo cumple.

Aunque los comentarios de esa maniobra hablan de «power-off», el código inicia `mode=level` y manda throttle=0: el motor permanece encendido al ralentí. No confundirlo con `mode=glide`, que sí lo detiene; conviene corregir esa descripción al ampliar los tests.

Consecuencia: el candidato que mejoró el doblete no está listo para producción. La aceptación debe incluir maniobras laterales y barrena, y la recuperación deberá contrastarse con respuesta física y técnica de piloto, sin ajustar el test arbitrariamente para hacerlo pasar.

## 3. Defecto confirmado: discontinuidad en vuelo hacia atrás con alabeo

En `Aero.coefficients`, el `CL` de base se calcula con el α global y luego se añaden déficits de franjas calculados con sus α locales. Cuando todas las franjas comparten α, los términos lineales se cancelan al entrar en la placa plana. Con rotación, α global y local pueden ocupar lados diferentes del corte de `atan2` en ±π; esa cancelación deja de funcionar.

Caso mínimo comprobado: V=15 m/s, β=0, p=5 rad/s, q=r=0, mandos aerodinámicos neutros, sin propulsión. Los dos estados solo cambian una diminuta componente vertical de velocidad:

| α | Fz del cuerpo |
| --- | ---: |
| −179,999° | −921,090 N |
| +179,999° | +921,091 N |

La diferencia de velocidad vertical entre ellos es ~0,000524 m/s; el salto de Fz es **1.842,181 N**. Repetir con separaciones angulares cada vez menores no lo elimina:

| ε a cada lado de ±180° | Salto de Fz |
| --- | ---: |
| 0,1° | 1.841,606 N |
| 0,01° | 1.842,129 N |
| 0,001° | 1.842,181 N |

Con p=0 las fuerzas cerca de ese corte son pequeñas y continuas. La magnitud del salto con p≠0 concuerda con el término global no cancelado `qbar S CLa 2π`. Es un defecto algebraico de la mezcla, no una elección discutible de coeficiente o un problema de precisión de Godot.

Impacto potencial: tailslides, tumbles y maniobras con flujo invertido. No se reprodujo este cruce concreto en los vuelos normales de la sección 1. Los tests existentes recorren α con rates=0 y sin `v_air`, por lo que no ejercitan esta discontinuidad local/global.

## 4. Defecto de consistencia energética en ciertos estados rotatorios

La misma mezcla calcula drag global y le resta drag lineal local de las franjas. Esas cantidades no son la misma base cuando hay rotación. El resultado puede ser `CD < 0`.

Se midió además la potencia mecánica total de las cargas aerodinámicas respecto al CG:

```text
P_aero = F_aero · v_air + M_aero · ω
```

No se incluye propulsión ni gravedad. En estos casos no hay viento ni movimiento de servos. **Drag negativo por sí solo no basta** para declarar creación neta de energía en un cuerpo rotatorio: puede existir transferencia desde su rotación. Por eso se suma también `M·ω`.

Barrido: α de −180 a +180° cada 10°, β=0, p/r en {−10,−5,0,5,10} rad/s, q=0, V=15 m/s; 925 muestras. Se encontraron **30 con CD negativo y 46 con potencia total positiva**.

- α=150°, p=−10, r=0: CD=−0,05492, P=+462,68 W. No requiere guiñada; sin alabeo, el mismo α da P=−329,75 W.
- Máximo del barrido: α=150°, p=−10, r=−5 → **+540,41 W**.
- También a α=10°, p=r=10 rad/s: CD=−0,01369 y P=+13,66 W. Por tanto no está restringido exclusivamente a vuelo hacia atrás, aunque exige rotaciones grandes en este ejemplo.

Esto señala generación artificial de energía en el modelo aerodinámico algebraico usado aquí. No se modela una reserva aerodinámica no estacionaria que justifique liberarla. **En los 26 vuelos de pulsos medidos no apareció CD negativo ni potencia aerodinámica total positiva.** No atribuirles la autorrotación normal del rudder sin más evidencia: son defectos adicionales del mismo subsistema.

No se recomienda resolverlo con `max(CD,0)` como solución definitiva. Eso escondería una señal y dejaría los momentos y la discontinuidad intactos. Fuerzas y momentos deben construirse con el mismo flujo local, geometría y referencias.

## 5. Robustez del cargador y de la sesión

Caso aislado en memoria: recorrido de elevator de 1°. El dato está dentro del rango aceptado por el loader, pero no permite el trim inicial:

```text
data.ok = true
start.ok = false
message = needs 4.7° of elevator, more than the 1.0° throw
sim.paused = false
```

`FlightSession.reset()` usa un lanzamiento de respaldo cuando `start.ok` es falso y solo pausa por `not aircraft.ok`. `_apply()` aplica datos y resuelve trim, pero no hace del éxito del trim una condición de vuelo. La prueba llama `_apply` y `reset`, el mismo final que usa hot reload; no prueba un clic de F5. Es un **defecto de contrato de la sesión**: para el inicio prometido como vuelo trimado, una configuración no trimable debería rechazarse o quedar pausada con explicación, no iniciar el respaldo silenciosamente.

Además, `Cndr ×10` sigue pasando la validación de datos. Los límites genéricos [−100,100] y el signo correcto no establecen plausibilidad de manejo. Un coeficiente extremo válido en el esquema no tiene por qué ser válido para el Ugly.

El código mantiene una separación conocida entre CG del inventario (x=0,04127 m) y CG usado para vuelo (x=0,1209 m); la inercia se calcula alrededor del primero. Es una representación provisional de una distribución trasladada/balanceada, no evidencia de un avión construido con esa distribución. Para calibrar respuestas, hace falta reconciliar masa, posiciones y CG de una configuración física concreta. Aplicar simplemente el teorema de ejes paralelos a un punto que no es su CG no arregla ese problema.

## 6. Integración y herramientas de validación

Con el mismo pulso y duración, aumentar ticks de física mantiene el síntoma. Diferencias del estado a 3 s:

| Eje | 240→480 Hz: posición / actitud | 480→960 Hz: posición / actitud |
| --- | --- | --- |
| Roll | 0,01483 m / 0,02232° | 0,00742 m / 0,01117° |
| Pitch | 0,00519 m / 0,01479° | 0,00261 m / 0,00743° |
| Yaw | 0,01647 m / 0,50274° | 0,00832 m / 0,25311° |

El pico de yaw permanece ~462,14°/s. No aparece evidencia de que 240 Hz cause el exceso. El error de la sesión completa cae aproximadamente a la mitad, compatible con auxiliares avanzados una vez por tick y retenidos durante RK4; usar RK4 para el cuerpo **no convierte todo el sistema acoplado en orden cuatro**. No cambiar la frecuencia por intuición: fijar tolerancias por régimen y medir coste.

Hallazgo por lectura: `flight_modes.gd` llama a `RB.derivative` sin `h_rotor`, mientras el vuelo sí incluye momento giroscópico. Además separa longitudinal/lateral en matrices de 4×4; un acoplamiento q↔r no queda representado al separarlas. Es una aproximación útil, pero no debe presentarse como análisis completo idéntico al runtime. La magnitud de su efecto modal no se cuantificó aquí. Incluir servos en los modos naturales con mandos congelados tampoco es obligatorio; sí lo es modelarlos al comparar respuesta stick→movimiento.

## 7. Otras limitaciones de realismo y futuros aviones

Estas son **lectura del código**, no nuevos fallos reproducidos:

- Elevator y alerones conservan derivadas de control lineales a grandes ángulos. La pérdida por franjas usa un término de lift de mandos compartido, no la deflexión independiente de cada alerón en su franja. Con alerones antisymétricos su suma de lift se cancela; no representa completamente su efecto local sobre la pérdida.
- Las franjas cambian α con p/r, pero usan la presión dinámica global; no son aún superficies completas con fuerza local y momento `r×F` coherentes. `station_kappa` calibra los momentos, no las fuerzas de igual forma.
- Sin propwash: al cesar velocidad del avión, el control de cola desaparece aunque haya motor. E0b debe llegar después de corregir autoridad y superficies.
- RPM objetivo depende del throttle, no de la carga aerodinámica del eje. `peak_power` se valida pero no impone un balance dinámico de potencia. Motor parado devuelve cargas de hélice cero; no representa su drag/windmilling. Son simplificaciones D5/G2 conocidas, relevantes para despegue, idle y planeo.
- Solo hay un JSON físico de avión: el Ugly. No se puede afirmar que Extra 300 o Avanti ya reproduzcan estos fallos en vuelo. Sí heredarían defectos del solver si se conectan a él.
- El loader exige `span × mean_chord ≈ area`, adecuado al ala rectangular actual si esa cuerda representa la media geométrica. En un ala afilada, la cuerda aerodinámica media usada para momentos no es generalmente S/b. Generalizar el avión exige distinguir ambas y no rechazar geometrías válidas ni copiar las derivadas del Stik.

## Reproducción y verificación

```bash
# Código 1 intencional: estados con potencia positiva detectados.
FLIGHT_AUDIT_OUT=/tmp/openrc-flight-audit $(app/get-godot.sh) \
  --headless --path app --script "$PWD/docs/research/flight-robustness/probe.gd"

# Código 0: recolector de mediciones, no aceptación de realismo.
FLIGHT_AUDIT_OUT=/tmp/openrc-flight-audit $(app/get-godot.sh) \
  --headless --path app --script "$PWD/docs/research/flight-robustness/flights.gd"

# Código 1 intencional: trim inválido pero sesión no pausada.
FLIGHT_AUDIT_OUT=/tmp/openrc-flight-audit $(app/get-godot.sh) \
  --headless --path app --script "$PWD/docs/research/flight-robustness/data_guards.gd"
```

Se ejecutaron los tres comandos. `test_envelope.gd`: **15 checks, 0 failed**. `test_spin.gd`: **9 checks, 0 failed** con el avión original. Estos tests pasan pese a las lagunas descritas. La suite completa ya pasó en la auditoría anterior con la misma física; no se repitió para cambios de documentación. Las mutaciones se limitan a diccionarios de investigación en memoria.

## Fuentes y criterio de realismo

La ecuación de drag exige conservar explícitamente área de referencia, coeficiente y condiciones del flujo; cambiar referencia cambia el coeficiente numérico. Esto respalda revisar la consistencia de las franjas, no aporta un `CD` calibrado para el Ugly. [NASA Glenn, Drag Equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/drag-equation/).

La identificación de modelos a partir de ensayos y vuelo es una vía documentada para aeronaves pequeñas de hélice. Se consultó el resumen de la tesis, no se reprodujo su método ni se obtuvo un dataset del Ugly. [Simmons, NASA NTRS, 2023](https://ntrs.nasa.gov/citations/20230004001).

UIUC ofrece mediciones de hélices para modelos/UAV y explica referencias y Reynolds. Es una fuente para el futuro balance propulsivo; no prueba que los datos de una 11×6 describan exactamente la 12×6 instalada. [UIUC Propeller Database](https://m-selig.ae.illinois.edu/props/propDB.html).
