# D1 / B5 — Primera malla Jensen Ugly Stik .61

Fecha: 2026-10-05. [Plan vigente](../UGLY-STIK-PLAN.md) · [Fuente editable](../../assets/aircraft/ugly-stik-60/geometry.json).

El constructor de la aplicación ya entrega un avión con fuselaje afinado, ala con sección y diedro, mandos separados, cola de contorno redondeado, motor monocilíndrico .61 simplificado, escape, hélice y tren triciclo con patas. Sustituye la representación de cajas manteniendo `build()`, `apply_surfaces()`, `airplane`, `propeller` y el mapa de bisagras. Mini y gigante siguen fuera de esta entrega.

## Qué representa y qué falta

Esta es una **primera representación visual**, no una reproducción dimensional certificada. La referencia Jensen aporta envergadura nominal de 60 in, área de 720 in² y ruedas de 2¾ in delante / 3 o 3¼ in principales; se eligió la opción de 3 in para la malla. La documentación .61 consultada es O.S. MAX-61FX, sin seleccionar esa marca como configuración definitiva. [Estudios de geometría](ugly-stik-investigations/01-03-geometry.md) · [equipo](ugly-stik-investigations/04-06-components.md).

La escala de la hoja no ha superado controles independientes suficientes. [El registro de calibración](ugly-stik-model-v1-calibration.md) conserva coordenadas del raster, referencias y discrepancias. Los contornos y posiciones sin calibración se identifican como estimados. El perfil alar es una aproximación visual semisimétrica con intradós posterior plano, no un perfil NACA ni una fuente de coeficientes aerodinámicos. El ángulo de diedro de 2.86° es provisional: no es un valor publicado por Jensen.

No se modificaron masa, inercia, fuerzas, empuje ni integración física. El datum geométrico sigue cerca del ala y no se afirma que coincida con el CG real. El siguiente hito físico D1 requiere su propio registro y validación.

## Implementación pequeña y reproducible

- [geometry.json](../../assets/aircraft/ugly-stik-60/geometry.json): dimensiones, contornos, ejes, variante y evidencia por grupo.
- [compile_geometry.py](../../assets/aircraft/ugly-stik-60/compile_geometry.py): genera [la constante Godot](../../app/aircraft/ugly_stik_geometry.gd); `--check` detecta una copia desactualizada.
- [ugly_stik_model.gd](../../app/aircraft/ugly_stik_model.gd): loft de secciones biseladas para el fuselaje, sección extruida del ala, prismas de cola y primitivas para el equipo.
- [airplane.gd](../../app/render/airplane.gd): adaptador que conserva la interfaz de la escena y los controles existentes.

La ruta v1 es **geometría nativa de Godot**. Permite ajustar los contornos sin introducir Blender ni un paso de importación; los metros y ejes ya son los del simulador. El [ensayo GLB anterior](ugly-stik-investigations/09-export.md) sigue disponible para intercambio futuro; su conversión de ejes no pertenece a este constructor nativo.

Los alerones cuelgan de marcos fijos que conservan el diedro. Sus bisagras solo reciben el giro del mando, evitando que una actualización de comandos borre la orientación de la semiala. La hélice gira bajo su propio nodo, con el cubo centrado en el eje. Los materiales se comparten por color.

## Pruebas y entregas del plan

| Paso del plan | Entrega v1 | Límite o continuación |
| --- | --- | --- |
| 2 · Calibración/contornos | Registro de puntos y escalas candidatas | No se acepta calibración absoluta; faltan controles independientes por vista |
| 3 · Articulaciones | [Ensayo sobre la malla y sus bisagras reales](ugly-stik-model-v1-rig.md), mandos positivos/negativos, retorno a neutro y poses del avión | No demuestra recorridos de un avión físico |
| 4 · Fuselaje | Secciones afinadas y franja que sigue la superficie | Ajustar cotas cuando se cierre la escala |
| 5 · Ala | Sección visual, alerones separados, diedro y colores superior/inferior | Incidencia y coordenadas aerodinámicas siguen pendientes |
| 6 · Cola | Estabilizador, elevador, deriva y timón independientes | Contorno simplificado, sin varillaje interno |
| 7 · Equipo | Motor .61 visual, escape, eje/hélice, ruedas y patas | Instalación estimada, sin masa/empuxe derivados de la malla |
| 8 · Lectura | [Capturas ortográficas y a 20/50/100 m](ugly-stik-model-v1-visual.md), misma cámara | Falta observación con el propietario/pilotos; no se declara Gate 2 superado |
| 9 · Integración | Constructor conectado a la aplicación, interfaz estable | D1 físico completo sigue pendiente |

El [cálculo de montaje](ugly-stik-investigations/evidence/model-v1-assembly.json) pone los tres neumáticos ideales sobre un plano y comprueba la separación del disco de hélice. Es una comprobación geométrica del montaje elegido, sin deformación de ruedas ni dinámica de aterrizaje; la hélice de 12 in y posiciones de equipo siguen siendo estimadas.

Comandos desde la raíz:

```bash
python3 assets/aircraft/ugly-stik-60/compile_geometry.py --check
python3 research/ugly-stik/model-v1/measure_assembly.py
app/test.sh
research/ugly-stik/model-v1/capture.sh
```

Las capturas y manifiestos están separados en `research/ugly-stik/model-v1/`. Los escaneos y recortes de terceros permanecen bajo `references/`, ignorado por Git.

## Lecciones prácticas

1. Una vista lateral detectó separación entre el ala y el fuselaje que no era evidente en tres cuartos; se ajustó el asiento alar y se añadió una comprobación geométrica.
2. Mantener el diedro en el padre de la bisagra conserva el eje de mando al volver a neutro y al cambiar la actitud del avión.
3. Una serie de capturas necesita restablecer todos los mandos antes de cada toma; dejar un diccionario vacío conservaba las deflexiones de la imagen anterior.
4. La malla puede avanzar con estimaciones explícitas sin convertir la escala del PDF o una rueda dibujada en una medida física confirmada.
5. El primer recuento encontró materiales idénticos repetidos; compartirlos por color reduce recursos sin modificar la silueta.
