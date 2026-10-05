# US-V04/V05 — servos, cuernos y varillaje

## Implementación

`app/aircraft/ugly_stik_controls.gd` expone `build(root, hinges)`, `update(controls)`, `set_maintenance(controls, visible)` y `audit(controls)`. El builder del modelo ya construye `controls`; `render/airplane.gd` actualiza las transmisiones después de aplicar las bisagras. El verificador usa ese avión y sus controles existentes, sin construir una segunda instalación.

El ala tiene un servo genérico y un bellcrank por semiala, en la raíz. La hoja 2 de Jensen representa ambas semialas en vistas inferiores y dibuja un servo y un reenvío para cada una. La disposición general está respaldada por el esquema; estaciones y dimensiones son aproximadas. Los dos servos de cola se colocan juntos cerca del ala dentro del fuselaje, con varillas largas y salidas cortas guiadas hacia elevador y timón. La posición de cola y esos recorridos son una aproximación visual, no una cota Jensen.

Cada servo es una silueta estándar genérica de 40 × 22 × 20 mm; no se presenta como un HS-311 ni se selecciona una marca. La instalación incluye carcasa, tapa, pestañas, gomas, ojales, fijaciones, bancada/raíles, brazo y cable corto. Los componentes estáticos se fusionan por material dentro de cada grupo. Brazos, varillas, clevises y sus extremos conservan sus transforms independientes. La geometría fija se crea una sola vez; la actualización solo cambia posición y orientación, sin escalar varillas ni crear nodos.

Los extremos de varilla usan un clevis metálico de doble oreja, pin transversal y casquillo; los extremos de las varillas de acero llevan bandas cortas que sugieren rosca. Cada cuerno lleva una arandela circular y alma de latón. Las salidas de elevador/timón añaden un tubo guía corto y una placa con fijaciones, inspirados por la descripción de la foto C aportada en la conversación. Esa foto no tiene una ruta local inspeccionable; estos detalles son una interpretación visual, sin atribución de marca o cota.

Elevador y timón usan el mismo cierre geométrico de manivela directa: una intersección de círculos resuelve el brazo de servo manteniendo la longitud de la varilla. Los alerones resuelven dos uniones rígidas por semiala: brazo servo a bellcrank y bellcrank a cuerno. En cada pose se escoge la solución más cercana al ángulo anterior para conservar la rama continua. Los componentes móviles se expresan en coordenadas locales de la raíz, así que el cierre también funciona con la raíz trasladada y rotada.

El servo y la varilla de gas son una instalación estática estimada porque la interfaz visual de esta entrega solo recibe bisagras. El extremo visual se conecta al punto de carburador publicado por el helper de equipo: `(0.019, shaft_y + 0.031, engine_z - 0.030)`, que da `(0.019, 0.026, -0.379776) m` en la geometría actual. No se modifica la entrada de gas ni se afirma movimiento de throttle.

## Evidencia

Fuentes de montaje: [plan visual](../UGLY-STIK-VISUAL-PLAN.md), [06 · instalación de servos](ugly-stik-visual-investigations/06-servo-installation.md) y [07 · cuernos y varillas](ugly-stik-visual-investigations/07-control-linkages.md). La hoja Jensen inspeccionada es `references/ugly-stik/calibration-v1/renders/jensen-2.png` (dos vistas inferiores). Los manuales de otros fabricantes respaldan solo la anatomía genérica de montaje, no una instalación concreta Jensen.

Prueba con el Godot 4.7.2 fijado: `verify_controls.gd` pasa **289 checks, 0 fallos**. Recorre 21 poses de ±20° para cada alerón/elevador y ±25° para timón, comprueba cierre y longitudes, transformación de raíz, extremos de cuerno, ausencia de asignaciones de nodos durante el barrido, y restauración de la pose neutral y de la rama del solver. Máximos observados: cierre `0.000000060 m`, error de longitud `0.000000060 m`; tolerancia de auditoría `0.25 mm`.

`verify_model.gd` integrado pasa **807 comprobaciones, 0 fallos**. Su barrido usa las órdenes reales de vuelo en 21 posiciones por eje más ocho extremos combinados: **71 poses**. Mide los extremos transformados de las mallas de varilla, además del cierre calculado: separación máxima `0.000000089 m`, error de longitud `0.000000119 m`. La tolerancia es 0,25 mm de implementación, no precisión física de construcción.

El contrato geométrico anterior mantiene sus pruebas de holgura de superficies. No equivale a una prueba exhaustiva de colisión entre todos los accesorios: guías, apoyos y contactos intencionales se revisaron en las macros y poses guardadas. La varilla de gas es estática y no forma parte de los seis eslabones articulados del barrido.
