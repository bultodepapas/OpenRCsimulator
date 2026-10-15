# Análisis de choques y mecánica — Monster Truck Nitro 1:8 (diseño propio)

Unidades en mm y grados. Recorrido de rueda −44 / +36 mm (80 mm) y dirección ±0.42 (control).

## 1. Choques

- Poses analizadas: 31 (compresión, extensión, balanceo, cabeceo, cruce de ejes) × dirección −/0/+, cada una con un ángulo de giro distinto de ruedas, palieres, cardanes y cigüeñal.
- **Choques por movimiento: 0**
- Contactos intermitentes (se tocan en reposo y se separan): 0
- Contactos permanentes: 59, todos uniones de diseño (pasadores, rodamientos, kingpins, sellos, asientos de resorte).

### Holguras mínimas en movimiento (< 0.8 mm)

| Holgura | Pieza A | Pieza B | Peor pose | Tipo |
|---|---|---|---|---|
| 0.10 | Amort_Del_Der_Cuerpo_Malla | Amort_Del_Der_Tope | todas +36 mm, dirección -0.42 | pasa libre |
| 0.10 | Amort_Del_Izq_Cuerpo_Malla | Amort_Del_Izq_Tope | todas +36 mm, dirección -0.42 | pasa libre |
| 0.10 | Amort_Tras_Der_Cuerpo_Malla | Amort_Tras_Der_Tope | todas +36 mm, dirección -0.42 | pasa libre |
| 0.10 | Amort_Tras_Izq_Cuerpo_Malla | Amort_Tras_Izq_Tope | todas +36 mm, dirección -0.42 | pasa libre |
| 0.20 | Freno_Disco | Freno_Pastillas | todas +0 mm, dirección +0.42 | juego de articulación |
| 0.24 | Diferencial_Salida_Del_Der | Palier_Del_Der | cruce de ejes, dirección -0.42 | juego de articulación |
| 0.25 | Diferencial_Salida_Del_Izq | Palier_Del_Izq | cabeceo acelera, dirección +0.42 | juego de articulación |
| 0.30 | Amort_Del_Der_Tope | Amort_Del_Der_Vastago_Malla | todas -44 mm, dirección -0.42 | pasa libre |
| 0.30 | Amort_Del_Izq_Tope | Amort_Del_Izq_Vastago_Malla | todas -44 mm, dirección -0.42 | pasa libre |
| 0.30 | Amort_Tras_Der_Tope | Amort_Tras_Der_Vastago_Malla | todas +36 mm, dirección -0.42 | pasa libre |
| 0.30 | Amort_Tras_Izq_Tope | Amort_Tras_Izq_Vastago_Malla | todas +36 mm, dirección -0.42 | pasa libre |
| 0.42 | Eje_Copa_Del_Der | Palier_Del_Der | cabeceo frenada, dirección -0.42 | juego de articulación |
| 0.46 | Eje_Copa_Del_Der | Mangueta_Del_Der_Malla | reposo | pasa libre |
| 0.46 | Eje_Copa_Del_Izq | Mangueta_Del_Izq_Malla | reposo | pasa libre |
| 0.47 | Eje_Copa_Del_Izq | Palier_Del_Izq | cabeceo frenada, dirección +0.42 | juego de articulación |
| 0.50 | Campana_Embrague | Transmision | todas -44 mm, dirección -0.42 | pasa libre |
| 0.50 | Freno_Disco | Freno_Pinza | todas +36 mm, dirección -0.42 | pasa libre |
| 0.50 | Mangueta_Del_Der_Malla | Portamangueta_Del_Der | todas +36 mm, dirección +0.42 | juego de articulación |
| 0.50 | Mangueta_Del_Izq_Malla | Portamangueta_Del_Izq | todas +36 mm, dirección -0.42 | juego de articulación |
| 0.50 | Motor_Carter | Volante_Motor | todas +0 mm, dirección -0.42 | pasa libre |
| 0.59 | Bieleta_Rotulas_Der | Servo_Brazo_Direccion | todas -44 mm, dirección +0.00 | pasa libre |
| 0.60 | Direccion_Bellcrank | Varilla_Direccion | reposo | pasa libre |
| 0.63 | Amort_Tras_Der_Cuerpo_Malla | Soporte_Amort_Orejas_Tras | todas -44 mm, dirección -0.42 | pasa libre |
| 0.63 | Amort_Tras_Izq_Cuerpo_Malla | Soporte_Amort_Orejas_Tras | todas -44 mm, dirección -0.42 | pasa libre |
| 0.63 | Eje_Copa_Tras_Der | Palier_Tras_Der | balanceo der, dirección -0.42 | juego de articulación |
| 0.63 | Eje_Copa_Tras_Izq | Palier_Tras_Izq | balanceo izq, dirección +0.42 | juego de articulación |
| 0.64 | Amort_Del_Der_Cuerpo_Malla | Soporte_Amort_Orejas_Del | todas -44 mm, dirección -0.42 | pasa libre |
| 0.64 | Amort_Del_Izq_Cuerpo_Malla | Soporte_Amort_Orejas_Del | todas -44 mm, dirección -0.42 | pasa libre |
| 0.77 | Eje_Copa_Tras_Der | Mangueta_Tras_Der_Malla | cabeceo acelera, dirección -0.42 | pasa libre |
| 0.77 | Eje_Copa_Tras_Izq | Mangueta_Tras_Izq_Malla | cabeceo acelera, dirección -0.42 | pasa libre |

Las holguras < 0.5 mm son juegos internos de articulación (pasador del palier en su ranura, pastillas contra el disco, cara axial del kingpin). Todas las piezas que solo pasan cerca quedan a ≥ 0.5 mm.

## 2. Mecánica (medida en el rig)

| | Delantera | Trasera |
|---|---|---|
| Recorrido de rueda | [-44.0, 36.0] | [-44.0, 36.0] |
| Largo del amortiguador min/reposo/max | [85.19, 95.5, 107.31] | [82.69, 93.0, 104.81] |
| Carrera del amortiguador | 22.12 | 22.12 |
| Relación de movimiento (extensión/reposo/compresión) | [0.28, 0.273, 0.296] | [0.281, 0.273, 0.295] |
| Giro del balancín | [-35.9, 31.2] | [-35.9, 31.2] |
| Caída (extensión/reposo/compresión) | [3.52, 0.0, -4.02] | [3.53, 0.0, -4.01] |
| Cambio de vía (extensión/compresión) | [-6.0, -6.77] | [-6.0, -6.77] |
| Bump steer (extensión/compresión) | [0.048, 0.017] | [0.0, 0.0] |
| Ángulo del palier: lado diferencial / lado rueda | [22.7, 19.18] | [22.68, 19.16] |
| Ángulo del palier con dirección a tope | [22.73, 31.11] | — |
| Deslizamiento del palier en la copa | [-2.45, 1.42] | [-2.36, 1.36] |

**Amortiguadores**

| | Delantero | Trasero |
|---|---|---|
| Margen al fondo en compresión total | 5.28 | 4.03 |
| Vástago dentro del cuerpo en extensión total | 12.28 | 11.03 |
| Copa del resorte al sello (compresión total) | 1.5 | 1.5 |
| Margen antes de bloquear espiras | 7.33 | 4.83 |

**Dirección**

- Giro máximo: interior 26.97°, exterior 21.96° (Ackermann ideal: 18.63°) → **Ackermann 60.1 %**
- Radio de giro aprox.: 0.879 m · Brazo del servo: -28.9° / +33.8°
- Caster 8.0° (avance mecánico 12.2 mm) · inclinación del pivote 9.05° · scrub radius 26.4 mm

**Transmisión**: cardán delantero 79.4 mm a 15.48°, trasero 160.1 mm a 1.52°. Relación diferencial 3.308, 1.ª 2.6, total 8.6.

## 3. Masa, resortes y amortiguadores

- Masa total estimada 7.026 kg (suspendida 4.952 kg; no suspendida 0.5257 kg por rueda delantera y 0.5115 kg por trasera).
- Reparto 50.6 % adelante / 49.4 % atrás. Altura del CG 109.6 mm (suspendida 119.6 mm).

| Para frecuencia de marcha 2.2 Hz | Delantero | Trasero |
|---|---|---|
| Rigidez en rueda (N/m) | 239.0 | 234.1 |
| Resorte (N/mm) | 3.207 | 3.141 |
| Precarga con la rueda colgando (mm) | 2.21 | 2.21 |
| Largo libre del resorte (mm) | 49.5 | 47.0 |
| Fuerza del resorte en reposo (N) | 44.95 | 44.02 |
| Amortiguador compresión / extensión (N·s/m) | 162.4 / 255.2 | 159.0 / 249.9 |

Con estos valores el reposo queda en h = 0: 44 mm sobre la extensión total y 36 mm antes del tope.

## 4. Todo terreno

- Centro de balanceo: 19.7 mm (adelante y atrás). Brazo de balanceo 99.9 mm.
- **Gradiente de balanceo 4.16°/g** (sin barras 7.35°/g). Reparto de rigidez al balanceo 52.9 % adelante.
- Vuelco: factor de estabilidad estática 1.825; con el balanceo el límite queda en 1.743 g.
- Distancia al piso: 45.0 mm en reposo; 9.0 mm con las 4 ruedas a tope (aterrizaje): los topes de uretano frenan antes de que la placa llegue al piso.
- Ángulo de ataque 45.6° y de salida 45.6° (los limita el soporte del parachoques); ángulo ventral 27.0°.
- Antihundimiento / anticabeceo: 0 % (pivotes paralelos al eje del auto). Inclinar 3-5° los pivotes traseros daría ~20-35 % de antihundimiento al acelerar.

| Rigidez al balanceo (N·m/rad) | Delantero | Trasero |
|---|---|---|
| Resortes | 19.12 | 18.73 |
| Barra estabilizadora | 16.21 | 12.72 |
| Total | 35.33 | 31.45 |
| Barra: diámetro / brazo / bieleta (mm) | 3.4 / 57.3 / 22.3 | 3.2 / 57.3 / 22.3 |
| Barra: rigidez efectiva (torsión + flexión de brazos) | 9.06 | 7.11 |

Topes de compresión: uretano de 3.86 mm en el vástago; tocan el sello a +28.0 mm de recorrido y se aplastan 2.36 mm (≈80.8 N en el amortiguador al tope).

## 5. Carrocería "LOCURA" (v11)

Pickup monstruo de diseño propio. Todos los patrocinadores y marcas de las calcomanías son inventados.

- **Casco**: loft de 30 secciones con capó abombado (corona de 4 mm), costados con caída hacia adentro, nariz y cola redondeadas; espesor de lámina 2.2 mm. Pasos de rueda de 125.5 mm de radio centrados 5 mm sobre el eje de rueda (la misma holgura ya verificada para 80 mm de recorrido con dirección a tope).
- **Pintura** (atlas de 4096 px generado por `livery.py`, mapeado por vistas): verde esmeralda metalizado con laca, llamas caramelo (amarillo → naranja → rojo → carmesí) con filete neón rosa, banda inferior de camuflaje digital con filo neón verde, franjas negras de carrera en capó y techo, número 08 en puertas y techo, zarpazos, "LOCURA" en la caja y la compuerta, cuadros de bandera, franjas de peligro y 10 calcomanías de patrocinadores ficticios. Tres texturas: color, rugosidad/metálico (G/B, formato glTF) y emisión (filetes neón que brillan de noche).
- **Luces**: faros de proyector dobles con luz diurna en C (azul) y direccional ámbar, barra LED en el techo (16 LED) con 5 marcadores ámbar, barra LED frontal de 12 LED, antinieblas ámbar, 4 focos en la antivuelco, calaveras LED de 5 tiras, tercera luz de freno en el techo y neón bajo la carrocería (rosa a los lados, verde adelante y atrás).
- **Accesorios**: soplador rojo nervado con tapas pulidas, polea, correa y toma "atrapa insectos" cromada con malla; rejillas y pasadores del capó; parrilla de panal con emblema; defensa tubular, ganchos de remolque rojos; guardabarros atornillados (7 tornillos cada uno); estribos tubulares; espejos; manijas; tapón de combustible; red de ventana; escapes verticales con corte en bisel, protector ranurado y abrazaderas; barra antivuelco con tirantes a los rieles cromados de la caja; amarres; alerón de fibra de carbono (perfil NACA 4412 invertido, 70 mm de cuerda) con gurney neón, aletas pintadas y cuellos de cisne; parachoques trasero con enganche y placa "LOKO-08".
- **Masa de la carrocería**: 843 g en 66 piezas (los accesorios se pesan como plástico de pared delgada; el casco como lámina de 0.8 mm).
- **Verificación**: la carrocería entró al análisis de choques completo (31 poses × 3 direcciones, con giro de ruedas): 0 choques por movimiento con ruedas, brazos ni amortiguadores. Los solapes estáticos nuevos son montajes a propósito (antinieblas en el parachoques, soplador y correa entrando al capó, focos sobre la antivuelco, guardabarros atornillados al costado, defensa tubular sobre el parachoques).

## 6. Cambios de versiones anteriores (v10)

- Caster de 8° adelante: el eje de dirección pasa por el centro de la rueda con la rótula superior 8 mm atrás → 12 mm de avance mecánico (se autocentra y es estable en recta). La portamangueta ahora gira con un driver exacto sobre su pasador (un Damped Track la habría torcido con el eje inclinado). Dirección reoptimizada: bump steer 0.05°, Ackermann 60 %.
- Barras estabilizadoras adelante (3.4 mm) y atrás (3.2 mm): tramo transversal en dos bujes atornillados al mamparo exterior, brazos de 57 mm y bieletas de 22 mm con rótulas a una oreja nueva del balancín. El espárrago es horizontal para que la rótula trabaje perpendicular a la bieleta. Balanceo de 7.3 a 4.2°/g.
- Tirantes: uno central que une las dos torres por encima del motor y dos diagonales de cada torre al techo del diferencial. Cierran la caja torre-placa-torre que la placa angosta había perdido.
- Placas protectoras de UHMW (2 mm) bajo las rampas, por encima de la placa: no restan distancia al piso.
- Topes de compresión de uretano en los vástagos (se aplastan con un driver de escala en los últimos 8 mm).
- Copas de los palieres con boca avellanada: con caster el palier llega a 31° y su cuello rozaba la boca.
- Pasos de rueda de la carrocería más grandes (tocaba la llanta con giro y balanceo). Manguera de presión reubicada sobre el tirante central.
- Tornillos de la placa avellanados desde abajo: antes asomaban 6 mm hacia el piso. Placa y rampas unidas sin caras duplicadas (la resta booleana dejaba restos del cortador).
