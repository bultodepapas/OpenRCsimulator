# Ugly Stik: diagnóstico del rudder

2026-10-05 · D8b / D10 / Gate 2 · Base `90374d2` · Godot 4.7.2.

**Resultado:** se reproduce una autoridad de guiñada extrema y una entrada en autorrotación con un pulso corto de timón, sin elevator. La causa principal identificada es la combinación de autoridad aerodinámica prestada (`Cndr`), recorrido estimado de 25° y extrapolación fuera del régimen lineal. La pérdida asimétrica amplifica la respuesta y permite que continúe después de centrar el timón. El control funciona en el sentido correcto; el exceso también existe sin radio y sin motor.

Esto identifica el mecanismo en el simulador; **no determina todavía el coeficiente correcto del Ugly Stik real**. El usuario no había precisado dispositivo, velocidad ni maniobra al realizar esta auditoría. No se dispone de su traza: el escenario reproducido es una explicación fuerte del síntoma, no una reproducción certificada de su vuelo particular.

Solo se añaden investigación y plan. Ningún parámetro de producción, golden ni script de `app/` se modifica. [Plan de reparación](../RUDDER-REPAIR-PLAN.md).

## Reproducción y límites

La sesión real de vuelo (`FlightSession`) carga el avión, resuelve trim a 15 m/s, comienza a 30 m y avanza a 240 Hz. Desde 0,5 hasta 1 s recibe timón derecho completo; de 1 a 1,5 s, izquierdo; después, neutro. El motor mantiene el gas de trim. No hay viento, elevator ni aileron de piloto. Se incluyen sus trims. Se registran comandos, servos y los seis grados de libertad.

```bash
$(app/get-godot.sh) --headless --path app \
  --script "$PWD/docs/research/rudder-audit/probe.gd"
```

Ejecutado dos veces, con resultado idéntico y aproximadamente 0,7 s de coste:

```text
RUDDER_SCREEN FAIL beta_peak=42.413 deg roll_peak=178.605 deg r_peak=462.145 deg/s
```

El código de salida 1 es **intencional**: el criterio de diagnóstico es pico de |β| ≤25°, el extremo de la transición lateral que ya define el modelo. Es un límite provisional de ingeniería para detectar este comportamiento, **no una medición del avión real ni un contrato definitivo de manejo**. No se incorpora a CI como aceptación física independiente.

El caso mínimo comprobado elimina la segunda mitad del doblete: un único pulso derecho de 0,5 s reproduce los mismos máximos, ya alcanzados antes de invertir el mando. Dos casos idénticos del barrido coinciden numéricamente. No se buscó el pulso mínimo en milisegundos.

El contrafactual que cambia solo `Cndr` al 30%, en memoria y con nuevo trim, cambia el veredicto:

```bash
RUDDER_CNDR_SCALE=0.3 $(app/get-godot.sh) --headless --path app \
  --script "$PWD/docs/research/rudder-audit/probe.gd"
```

```text
RUDDER_SCREEN PASS beta_peak=21.728 deg roll_peak=30.092 deg r_peak=88.239 deg/s
```

Pasar este filtro **no valida** ese ajuste ni asegura recuperación, maniobras acrobáticas o fidelidad en otras velocidades.

## Matriz experimental

[Barrido reproducible](rudder-audit/sweep.gd), [resultados completos, muestras y hashes](rudder-audit/results.json). Cada variante parte de datos frescos; se modifica una variable y se vuelve a resolver trim. Se ejecutaron 19 casos (~8 s).

```bash
RUDDER_AUDIT_OUT=/tmp/openrc-rudder-audit \
  $(app/get-godot.sh) --headless --path app \
  --script "$PWD/docs/research/rudder-audit/sweep.gd"
```

Produce un CSV por caso y `results.json` en la carpeta indicada. Sin la variable solo imprime resultados. El JSON archivado añade procedencia y muestras de la traza base. Los CSV completos son regenerables.

| Cambio respecto al doblete base | Pico absoluto β, ° | Pico absoluto r, °/s | Pico absoluto roll Euler, ° | Altitud perdida a 3 s, m |
| --- | ---: | ---: | ---: | ---: |
| Base | 42,41 | 462,14 | 178,61 | 15,94 |
| Un solo pulso derecho de 0,5 s | 42,41 | 462,14 | 178,61 | 15,78 |
| Primero izquierda | 40,13 | 437,64 | 179,05 | 15,54 |
| 25% de mando | 20,69 | 81,72 | 28,22 | −1,02 |
| 50% de mando | 33,27 | 440,13 | 179,26 | 14,36 |
| Teclas A/D a través de `Input` | 42,08 | 450,35 | 179,46 | 15,13 |
| Radio AETR simulada | 42,41 | 462,14 | 178,61 | 15,94 |
| Sin envolvente no lineal | 56,16 | 262,75 | 126,67 | 11,20 |
| Inercia giroscópica = 0 | 41,35 | 451,90 | 177,03 | 15,54 |
| Planeo trimado, motor parado | 41,64 | 449,88 | 166,39 | 17,66 |
| `Cndr × 0,5` | 33,33 | 437,53 | 179,06 | 13,08 |
| `Cndr × 0,4` | 28,74 | 119,48 | 42,92 | −1,33 |
| `Cndr × 0,3` | 21,73 | 88,24 | 30,09 | −0,88 |
| `Cnb × 2` | 38,12 | 402,03 | 179,96 | 16,36 |
| `Cnr × 2` | 38,96 | 297,67 | 178,77 | 16,44 |
| Recorrido 10° | 29,05 | 124,45 | 47,74 | −1,07 |
| Velocidad inicial 12 m/s | 36,14 | 393,77 | 179,47 | 16,32 |
| Velocidad inicial 20 m/s | 46,79 | 672,71 | 179,96 | 16,89 |

`r` es velocidad angular de cuerpo, no derivada del rumbo Euler. El roll Euler envuelve en ±180°: sirve como indicio de actitud extrema, no para contar vueltas. El pico de `p` del caso base es 576,18°/s. Pérdida de altitud negativa significa ascenso.

El caso sin envolvente es un contrafactual diagnóstico: elimina también la pérdida por franjas y no representa física válida a gran ángulo. Planeo cambia además la condición de trim; demuestra que el motor no es necesario, pero no es una comparación a fuerzas idénticas. La radio es inyectada, no una prueba de hardware USB. El camino directo omite eventos/UI y detección de impacto; las variantes de dispositivo sí pasan por `_physics_process`. Ningún escenario llega al suelo en los 3 s observados.

## Localización de la causa

### 1. Autoridad de timón frente a estabilidad direccional

En `app/data/aircraft/jensen_ugly_stik_60.json`:

- Recorrido máximo de rudder: 25°, marcado `estimated`.
- `Cndr = −0,1811 /rad`, momento de guiñada por deflexión.
- `Cnb = +0,0723 /rad`, estabilidad direccional por resbalamiento.
- `Cnr = −0,1833 /rad`, amortiguamiento de guiñada.
- `CYdr = +0,1913 /rad`, fuerza lateral por rudder.

La conversión piloto → superficies → aerodinámica es correcta: +1 → +25° TE derecha → −0,43633 rad bajo la convención del dataset. La fuerza empuja la cola a la izquierda y el momento gira el morro a la derecha. No aparece un factor accidental de 57,3 ni una doble aplicación del mando en esta ruta.

En `aero.gd:150–157`, el término de control es lineal y no depende de α/β; el restaurador lateral pasa de β a sin(β). A 15 m/s, 25° producen aproximadamente **7,71 N·m** de momento aerodinámico directo sobre el punto de referencia, antes de los otros términos.

Balance estático simplificado, con velocidades angulares y otros mandos cero:

```text
Cn = Cnb × β + Cndr × δr
|β_balance| = |Cndr| × 25° / Cnb = 62,62°
```

Este cálculo es una **señal de desproporción**, no un trim real de seis ejes: ignora aceleraciones, gravedad, fuerzas y acoplamientos. No debe volver a publicarse como «resbalamiento estacionario medido».

Con el término sin(β), la inconsistencia es aún más visible: `|Cndr δr| = 0,07902`, mayor que el máximo `Cnb × |sin β| = 0,0723`. Esos dos términos solos no pueden equilibrarse a full rudder. El control conserva toda su eficacia mientras se limita la restauración. Esto no demuestra que el modelo completo carezca de cualquier equilibrio dinámico; identifica qué formulación empuja el vuelo a grandes ángulos.

El XML original contiene esos mismos valores y multiplica la deflexión en radianes: **no se encontró error de transcripción de `Cndr`**. Se trasplantó un modelo de otro avión; no hay validación de estos coeficientes para el Jensen .60. [Fuente primaria fijada: OpenFlightSim `AeroOpenFlight.xml`, commit b020511](https://github.com/UASLab/OpenFlightSim/blob/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/AeroOpenFlight.xml).

Comprobación adicional de plausibilidad, derivada de los datos locales: el brazo equivalente `−b Cndr / CYdr` vale 1,443 m; la bisagra del timón está aproximadamente a 0,786 m detrás del CG, y su borde posterior llega a ~0,892 m. La pareja fuerza/momento exige revisión geométrica. **No es una demostración de error por sí sola**: son derivadas de avión completo, que incluyen interferencias, y la geometría visual no identifica el centro de presión.

### 2. La pérdida asimétrica amplifica una entrada ya excesiva

En el caso base, la secuencia medida es:

| t, s | β, ° | α, ° | r, °/s | Servo yaw normalizado |
| --- | ---: | ---: | ---: | ---: |
| 0,50 | −0,06 | 3,71 | 0,00 | 0,0066 |
| 0,65 | −5,52 | 3,70 | 95,21 | 1,0000 |
| 0,75 | −18,60 | 4,35 | 175,20 | 1,0000 |
| 1,00 | −25,76 | 61,21 | 428,40 | 1,0000 |
| 1,65 | 1,29 | 39,50 | 189,26 | 0,0066 |
| 3,00 | −7,98 | 52,05 | 379,01 | 0,0066 |

La primera muestra tiene el mando previo al pulso; el bucle aplica la orden al siguiente tick. El servo vuelve al trim, pero la rotación persiste: el problema de «sigue girando» no exige un mando pegado.

La guiñada cambia la velocidad local de las franjas (`u − r·y`); resbalamiento y acoplamientos generan roll y cambios de α. El modelo entra en pérdida asimétrica y autorrotación. Desactivar toda la envolvente reduce esa amplificación, pero conserva 56° de resbalamiento: **la pérdida no crea por sí sola el exceso inicial**. Reducir solo `Cndr` suficientemente evita alcanzarla en este escenario. El salto entre factores 0,5 y 0,4 muestra un umbral no lineal, no una mejora proporcional de «sensibilidad».

No se auditó aquí la fidelidad de una barrena real. La persistencia de la autorrotación y su recuperación requieren validación adicional; D9b ya documenta que neutro no basta para recuperar su barrena desarrollada.

### 3. Entrada y render no explican la causa común

Ruta: `keyboard.gd` / `rc_input.gd` → `FlightSession._physics_process` → `flown_commands` (trim y clamp) → servo → `surface_deflections_deg` → `deflections_from_surfaces` → `Aero.loads` → RK4.

- Teclado: llega a full en 0,25 s. Radio: posición directa. Gamepad: deadzone/expo propios; no probado en este barrido.
- Servo: centro a full en 0,14 s. La entrada está limitada a ±1.
- La radio simulada reproduce exactamente el caso directo. El teclado suaviza el arranque pero alcanza el mismo régimen extremo.
- `main.gd` dibuja `session.surfaces()` con los mismos recorridos. No se encontró una ruta que haga girar la física desde la animación de la bisagra. No se hicieron capturas de percepción de cámara en esta auditoría.
- El efecto se mantiene a izquierda y derecha, en 12/15/20 m/s y con motor detenido. Giroscopio, cámara y potencia no son condiciones necesarias.

Una calibración real defectuosa podría agravar el problema en un dispositivo concreto; los resultados no la descartan para el hardware del usuario.

## Por qué los tests y versiones lo conservaron

`test_aero.gd` comprueba signo y un mínimo de momento, sin máximo de autoridad. `test_handling.gd` solo exige que el primer rudder derecho produzca guiñada derecha. El golden conserva la trayectoria, incluida una trayectoria físicamente cuestionable. El barrido D10 estudió `Cnb` y `Cnr`, pero no incluyó `Cndr` ni el recorrido de rudder entre sus 13 incógnitas.

ROADMAP D9a y LEARNINGS ya documentaban ~62° en el balance lineal. Por tanto, hay una **deuda de validación conocida**, ahora respaldada por un síntoma de uso. D10 completado significaba que se hizo el barrido, no que se corrigiera la autoridad.

`git diff v0.1.0-rc1 HEAD -- app/physics app/sim app/input app/data/aircraft/jensen_ugly_stik_60.json` está vacío. El historial inspeccionado sitúa el crecimiento del modelo de pérdida en `4645213` y `dbe0cb2`, anteriores a las releases. No hay evidencia aquí de una regresión física específica introducida por rc2. No se ejecutó un bisect ni se compararon los binarios descargados del usuario.

## Qué queda por validar

Recorrido y respuesta reales del Jensen; dispositivos y maniobra del usuario; respuesta en gamepad; pulsos pequeños y sostenidos; gas alto a baja velocidad; recuperación tras soltar a distintos estados; métricas de coordinación y acrobacia con el coeficiente candidato. No adoptar «15–25° de resbalamiento típico» como dato medido: la mención histórica del roadmap no aporta aquí una fuente experimental independiente.

La reparación necesita un criterio de manejo explícito y una comprobación independiente. Las variantes `×0,3` y 10° son experimentos para localizar el problema, no valores listos para producción.

## Verificación de esta investigación

`app/test.sh` termina con código 0 en la base auditada: pruebas existentes, goldens, contrato del modelo, vuelo trimado y estados idénticos a 30/60/144 fps. Esto confirma que los checks actuales no rechazan la respuesta excesiva. El probe diagnóstico permanece rojo con los datos actuales y verde con el contrafactual explícito; no se está declarando reparada la física. Los scripts de investigación están fuera de `app/` y se ejecutaron por separado.
