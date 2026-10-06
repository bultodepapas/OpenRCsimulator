# Reparación de vuelo y autoridad del Ugly Stik

2026-10-06. Implementación de D9-R1/R2, D4-R1, D1-R1, D8a-R1 y D10-R. Continúa las auditorías [rudder](ugly-stik-rudder-audit.md) y [robustez](flight-model-robustness-audit.md). **Candidato de ingeniería reproducible; no validación contra telemetría de un avión real.**

## Causas reparadas

1. El momento prestado del rudder no correspondía a su fuerza y brazo: `|Cndr/CYdr| b = 1,443 m`. Se enlazan `CYdr`, `Cndr`, `Cldr` y `Cnb` con un mismo modelo explícito de deriva, respecto al ARP. No se cambian recorrido (25°), expo ni velocidad de servo para disimularlo.
2. La resta de déficits por franjas mezclaba una referencia global con ángulos locales y ramas distintas de `atan2`. Producía un salto de aproximadamente 1.842 N cerca de ±180° y potencia positiva en 46 de 925 estados. Se reemplaza por cargas completas de superficies locales fuera del régimen válido del modelo empírico.
3. El CG de vuelo no era el centro de la distribución usada para las inercias. Se declara una configuración virtual balanceada y se rechaza una configuración incompatible. No se aplica el teorema de ejes paralelos a un punto que no sea su centro de masa para llamarlo «inercia del avión».
4. La aceptación del avión comprobaba datos pero permitía despegar sin trim. Ahora prepara datos, trim, estado y cargas antes de aceptar; un reload fallido conserva la sesión válida. NaN, cargas malformadas y cuaterniones degenerados pausan conservando el último tick válido, incluidas fallas solo en RK k2/k3/k4.
5. Las herramientas de trim/modos y el vuelo componían la dinámica por rutas distintas. `physics/dynamics.gd` centraliza cargas, momento angular del rotor y derivada; los modos exponen el Jacobiano completo de 8×8 y etiquetan sus estimaciones 4×4 como proyecciones.

## Superficies y procedencia

La velocidad en cada superficie es `v_i = v_aire + ω × r_i`. La sustentación es perpendicular a esa velocidad en el plano horizontal/vertical correspondiente; el arrastre se opone a la velocidad completa. Su momento es exactamente `r_i × F_i`. Así, para superficies fijas sin propulsión, `F_i·v + (r_i×F_i)·ω = F_i·v_i ≤ 0`. La autorrotación puede tomar energía de la traslación; no se obliga artificialmente a que cada momento frene su rate.

Se conservan seis elementos de ala de igual área para el ala rectangular actual. La cola horizontal y la vertical usan sus propios ángulos locales, curva de sustentación y arrastre. El modelo local **reemplaza**, no suma, las derivadas globales. Se elimina `station_kappa`: escalar solo momentos de pérdida era incompatible con la misma fuerza/brazo.

Dentro de una región pequeña se conserva exactamente el modelo empírico corregido. La mezcla de cargas completas depende de los ángulos efectivos locales de ala y colas, incluidos rates, incidencia y mandos. Comienza en 8°; termina al empezar la pérdida del ala o a 12° efectivos de cola. La cola transita de pendiente lineal a placa plana entre 12° y 24°. Estos límites son estimaciones explícitas. `Aero.coefficients()` representa la curva empírica de referencia, no la suma de elementos ni una medida de potencia del modelo final. Para diagnosticar potencia hay que usar `Aero.loads()`.

La pasividad de los elementos locales se obtiene por construcción; la mezcla que retiene derivadas empíricas se verifica mediante barridos, no se presenta como demostrada para cualquier estado y cualquier conjunto de datos futuro.

Todos los parámetros nuevos están en `aero.surfaces`, con unidad, evidencia y fuente:

| Parámetro | Valor | Base / limitación |
|---|---:|---|
| Área horizontal fija+móvil | 0,0956 m² | Suma redondeada de polígonos de `assets/aircraft/ugly-stik-60/geometry.json`; geometría modelada, no medición aerodinámica |
| Área vertical fija+móvil | 0,0484 m² | Mismo procedimiento |
| Centro horizontal en datum LE | [0,8409; 0; −0,04564] m | Centro de presión estimado dentro de la cola; brazo x nominal −0,72 m |
| Centro vertical en datum LE | [0,8609; 0; 0,075] m | Estimado; brazo x nominal −0,74 m |
| Pendientes horizontal / vertical | 1,75 / 2,4 rad⁻¹ | Estimaciones efectivas de superficies finitas; falta identificación experimental |
| Efectividad rudder | 0,55 | Calibración provisional de manejo y recuperación, no dato de fabricante |
| Efectividad elevator | 1,174 | Cociente efectivo heredado `Cmde/Cma`; representa también efectos omitidos como downwash, no una efectividad pura de flap medida |
| Incidencia horizontal | 0,03845 rad | `Cm0/Cma`, redondeado; incidencia efectiva de la calibración global |
| Efectividad alerón | 0,144 | `abs(Clda_right)/(0,125 CLa)`, redondeado |
| Cola CD0 / k / CD90 | 0,012 / 0,08 / 1,2 | Estimados; CD90 comparte aproximación de placa plana del ala |

Con `a_v=2,4`, `S_v=0,0484`, `τ=0,55`, `l=x_v−x_ARP=0,74`, se usan:

```
CYdr = a_v S_v τ / S
Cndr = −CYdr l / b
Cldr = CYdr (z_v−z_ARP) / b
Cnb  = a_v S_v l / (S b)
```

El momento global se transfiere después del ARP al CG; usar altura respecto al CG en `Cldr` habría contado dos veces la transferencia. El loader comprueba estas relaciones y rechaza, por ejemplo, multiplicar solo `Cndr` por diez. Los valores globales restantes continúan siendo prestados; el modelo no se anuncia como identificación completa del Ugly. No hay intervalo estadístico justificable para los valores estimados: su incertidumbre física sigue sin cuantificar y Gate 2 permanece abierto.

## Configuración de masa explícita

Se conserva el inventario histórico como estimación y se añade una **masa virtual de balance**, identificada por nombre y fuente, para tener un único centro de masa compatible con el CG de plano. No es una afirmación de que un Ugly real necesite ese lastre ni una recomendación de construcción.

- Masa histórica: 2,601 kg; CG x ≈0,041274 m; objetivo de plano x=0,1209 m.
- Se elige x del balance=0,85 m, posición estimada en la parte posterior del fuselaje.
- `m_balance = (M x_CG − Σ m_i x_i)/(x_balance − x_CG) = 0,284058291 kg`.
- y=−0,031683638 m, z=−0,070584104 m cancelan los primeros momentos laterales y verticales.
- Masa total: **2,885058291 kg**. CG e inercias proceden de esta misma distribución; caja de balance de 25 mm estimada.
- El loader rechaza diferencias superiores a la tolerancia declarada de 1 mm en cualquiera de los tres ejes. La inercia de pitch queda en torno a 0,3871 kg·m²; se conserva la advertencia de que es 2,11 veces la referencia Ultra Stick escalada.

Este cambio explica parte de la variación de trim, planeo y modos. Para validar un avión construido hay que sustituir inventario y posición de balance por datos de esa construcción. No se ajustó el tensor para recuperar los resultados anteriores.

## Verificación y expectativas que cambian

| Caso | Modelo anterior | Candidato reparado |
|---|---:|---:|
| Doblete rudder original a 15 m/s: pico de β | 42,413° | 19,918° |
| Mismo caso: pico de r de cuerpo | 462,145°/s | 87,832°/s |
| Mismo caso: pico de roll | 178,605° | 20,497° |
| Barrido original pasivo | 46/925 con potencia positiva | 0/925 |
| Corte de flujo invertido | salto ~1.842 N | salto tiende a cero al reducir ε |
| Recuperación de barrena desde 6 s | pasa; falla con parche aislado Cndr×0,3 | conserva el criterio original de α<10°, |p|/|r|<1 rad/s |
| Trim a 15 m/s | α≈3,71° | α≈4,26° con la masa reconciliada |
| Planeo sin motor a 15 m/s | L/D≈8,46 | L/D≈9,11 con la masa reconciliada |
| Pérdida en vuelo lento | configuración de 2,601 kg | 9,49 m/s; predicción de 1g y CLmax: 9,51 m/s |

`test_physical_envelope.gd` conserva el caso rojo original y añade 5.000 estados deterministas con q, β, controles asimétricos, V=0 y rates. Comprueba finitud y potencia total, además de aislar la contribución del rudder y verificar sus brazos de momento. El barrido ampliado queda en [repair-fuzz.gd](flight-robustness/repair-fuzz.gd) y su JSON asociado.

Cambios deliberados de expectativas, no validaciones nuevas de realismo:

- V_COM=0 con ω≠0 ya no tiene fuerzas nulas: las superficies sí se mueven respecto al aire. El test exige disipación; solo traslación **y** rotación nulas dan cargas cero.
- El oráculo aleatorio ahora limita también cola y deflexiones; el test anterior declaraba «flujo adherido» con colas fuera de ese régimen.
- La reducción de roll con pies quietos ya no exige el antiguo 10–20% deducido de las mismas derivadas. Exige el sentido físico y que coordinar reduzca el deslizamiento; mantiene la banda de roll coordinado.
- Se conserva autorrotación direccional sostenida y descenso, y el criterio original de recuperación. Se retiran «3–10 rad/s» y «6–14 m/s» de barrena, sin medición independiente que los justificara. El nuevo mínimo de 1 rad/s es un filtro provisional de ingeniería, no un objetivo para el avión real.
- No se exige que una pequeña asimetría de inercia cause necesariamente una caída de ala de 20°; se exige respuesta mayor que en el avión simétrico, que sigue sin alabear en pérdida simétrica.
- Los goldens y bandas modales se regeneran por el cambio deliberado de fuerzas, autoridad y distribución de masa, después de las pruebas de integridad y manejo. Son regresiones numéricas, no datos de vuelo.

**Estabilidad pendiente de validación:** el modelo proyectado presenta raíz espiral positiva a 10 y 15 m/s (~0,3447 y 0,03422 s⁻¹) y casi neutra a 25 m/s (~−0,000201 s⁻¹). Se conservan esas raíces con signo en el test; no se ocultan forzando «todos los modos estables». Los modos oscilatorios y la amortiguamiento del roll permanecen amortiguados. Cerca de 10 m/s el modelo está próximo a la pérdida y la proyección por ejes pierde fiabilidad; hace falta contrastar el Jacobiano completo y el vuelo perturbado. La matriz completa de producción, con giroscópico, da raíces espirales positivas aproximadamente +0,34818 / +0,04372 / +0,01535 s⁻¹ a 10/15/25 m/s: a 25 m/s la proyección incluso cambia el signo. Es un límite concreto del análisis separado por ejes. La calibración real de estabilidad sigue abierta.

## Robustez transversal

Las secciones JSON se comprueban por tipo antes de indexarlas. Se rechazan tablas CT/CP con strings numéricos, fuentes vacías, hull con NaN, colas malformadas y CG incompatible. Un error de script no debe convertirse en `ok=true`. La sesión acepta candidatos transaccionalmente; resume no elude un arranque inválido. Un cambio válido de inercia actualiza su inversa cacheada. Se mantienen float64 y paso fijo.

Las trazas incorporan hash SHA-256 de los datos aceptados, configuración y nombre de modelo aerodinámico. No cambian las columnas del CSV. `Dynamics.evaluate` expone aire, cargas aero/propulsión y derivada para herramientas sin recomponer la física por otra ruta.

## Alcance pendiente

La reparación entrega superficies locales y sus guards; **propwash, equilibrio de eje motor/hélice, downwash explícito y pérdida dinámica siguen siendo ampliaciones separadas E0b/G2**, como requería el plan. No se añaden durante esta reparación para compensar la autoridad. Tampoco convierte los modelos visuales Extra/Avanti en modelos de vuelo validados. El ala local actual sigue discretizada para la planta rectangular del Ugly; una nueva planta necesita su propia distribución de área y cuerda.

No se cierra Gate 2 sin prueba del usuario con radio real/teclado, ni se declara realismo validado por disponer de tests verdes. Las pruebas de dispositivos simulados verifican sus rutas y servos, no la sensación del piloto.
