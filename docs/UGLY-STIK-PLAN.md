# Ugly Stik .61: plan de modelado en paralelo

Revisión 6 · 2026-10-05 · **V3 implementada e integrada; aceptación humana y rendimiento en hardware pendientes.** Variante: Jensen Ugly Stik 60 in / nitro .61. [Entrega y pruebas v3](research/ugly-stik-model-v3.md) · [Plan revisado antes de ejecutar](UGLY-STIK-PLAN-v5.md) · [Entrega v2](research/ugly-stik-model-v2.md).

El objetivo es un avión reconocible, articulado y legible para el primer playtest. La ejecución ha completado el trabajo de código, medición y preparación que podía comprobarse en este entorno. No convierte las medidas del escaneo en certificación de un avión real ni sustituye la evaluación del piloto. Mini y gigante siguen para después.

## Estado de cada entrega

| ID / relación | Resultado implementado | Prueba y aceptación restante |
| --- | --- | --- |
| US-01 · D1 | Inspector con destino explícito, protección de v1/v2, cámaras, poses, hashes y versión del modelo | 9 vistas de inspección y 36 de orientación sin recorte; repetición independiente de 36/36 PNG idénticos. **Implementación cerrada** |
| US-02 · D1 | Metrología Jensen por vista, coordenadas fuente, escala, controles e incertidumbres | [Ficha y auditoría](research/ugly-stik-model-v3-metrology.md). Sesión inicial **cerrada**, con discrepancias entre vistas y datum vertical provisional explícitos |
| US-03 · D1 | Estaciones posteriores y unión de cola corregidas; comparación de perfil/planta; asiento alar conservado | Cota reservada fuera del ajuste: residuos absolutos 0,032 mm techo, 0,020 mm vientre, 1,266 mm ancho, dentro de 3/3/6 mm declarados. **Implementación cerrada**, no precisión física certificada |
| US-04 · D1/B5 | Empenaje trazado, bisagras reubicadas, alivios, recorte del elevador y piezas ventrales | 99 pares/poses de cola sin fallo; prueba de penetración y contención, mutación detectada. **Implementación cerrada** para poses muestreadas |
| US-05 · D1/B5 | Puntas y alerones según planta, sección normalizada desde costilla, sombreado suave | 30 pares/poses alares sin fallo; signos y cotas del contrato conservados. [Límites del ala](research/ugly-stik-model-v3-wing.md). **Implementación cerrada**; incidencia y diedro continúan estimados |
| US-06 · D7/Gate 2 | Ensayo de orientación 20/50/100 m, seis actitudes y dos fondos; formulario local y clave oculta | [36 casos listos](../research/ugly-stik/model-v3/captures/review.html). **Preparación completa; respuestas del piloto pendientes**. La nueva decoración roja con cruces fue elegida después por el propietario; estos datos servirán para ajustar su lectura |
| US-07 · E1/E2 | Motor .61 genérico, escape, anclajes, pivotes de rueda/dirección, contactos y conversión de marcos | [Entrega a física](research/ugly-stik-model-v3-installation.md). **Preparación completa**; contacto/taxi pertenecen a E1/E2 y la marca del motor sigue abierta |
| US-08 · Gate 2/M5 | Sujeción del ala, accesorios visibles y materiales; presupuesto geométrico registrado | 54 mallas, 4.816 triángulos, 5 materiales. **Detalle inicial completo; medición en hardware pendiente**. No se justifica LOD con llvmpipe |

El contrato integrado pasa **510 comprobaciones**, y `app/test.sh` pasa en el árbol compartido. La prueba desde clon limpio también pasa: suite completa, contrato y nueve capturas con la geometría final. [Evidencia reproducible](../research/ugly-stik/model-v3/validation.json).

## Siguiente entrega visual

El propietario ha elegido rojo clásico con cruces y mayor detalle de motor, servos y herrajes. El [plan visual específico](UGLY-STIK-VISUAL-PLAN.md) organiza US-V01–08 y continúa US-06/07/08. La revisión 2 del plan visual incorpora las [dos fotografías aportadas](research/ugly-stik-visual-photo-brief.md): campos blancos exteriores con cruces negras, puntas rojas, filetes oscuros y cola vertical blanca. Esta elección autoriza avanzar en el acabado; el ensayo humano pendiente servirá para ajustar su legibilidad. La implementación visual todavía está pendiente.

## Siguiente ciclo de aceptación

1. Abrir el [ensayo de lectura](../research/ugly-stik/model-v3/captures/review.html), registrar las respuestas antes de desplegar cada clave y descargar el JSON. Revisar errores y dudas por distancia/fondo. Priorizar los que impidan reconocer la orientación; comparar cualquier cambio de acabado con idéntica cámara y geometría.
2. Probar la aplicación en el equipo del propietario y registrar dispositivo, resolución, cámara y coste de CPU/GPU. Optimizar únicamente donde esa medición lo justifique; guardar otra captura y repetir el contrato tras cambiar mallas.
3. Entregar los contactos y convenciones de giro a E1/E2. La API visual ya está lista; la simulación debe proporcionar ángulos y fuerzas. Una elección de motor comercial abre una tarea dimensional concreta, no una sustitución automática del Jensen por otro Stick.
4. Si se necesita fidelidad de réplica, resolver datum de empuje, zonas ocultas del fuselaje y escalas contradictorias con una fuente adicional o medidas de una construcción. Mantener las estimaciones actuales identificadas hasta entonces.

Estos pasos requieren observaciones que aún no existen; no se declara su aceptación por haber generado imágenes. El modelo actual puede acompañar M1/PT1 sin esperar una réplica dimensional completa.

## Criterios de aceptación conservados

Para PT1: interfaz y signos correctos, ensamblaje coherente y orientación evaluable desde tierra. Para afirmar ajuste al plano: variante, vista, datum, escala, incertidumbre y medida independiente reservada. Para rendimiento y lectura: prueba humana y equipo real. El número de tests no mide parecido ni pilotabilidad.

## Protocolo dimensional de US-02

1. Usar como fuente principal el [Jensen firmado](../references/ugly-stik/downloads/jensen/Das_Ugly_Stik_Jensen_oz1253.pdf); separar planta, perfil, costilla y detalles. Registrar hash, página, resolución y puntos antes de convertirlos a metros.
2. Adoptar el borde de ataque y la línea de empuje como referencias de intercambio con física. Describir también el origen de cada detalle; no trasladar la escala de una vista ampliada a la vista montada.
3. Comprobar escala en ambos ejes cuando haya controles válidos. Tratar el tamaño PDF como candidato, la rueda como dibujo posiblemente esquemático y la cuerda como control local. No forzar concordancia mediante escalas independientes por pieza.
4. Para fuselaje, identificar extremo delantero/trasero, techo, vientre y anchos de estaciones comunes. Para cola, separar estructura fija, superficie móvil y líneas de varillaje. Marcar los tramos ocultos por el ala; no completarlos como si estuvieran medidos.
5. Declarar la tolerancia de cada cota antes del ajuste, a partir de la lectura y la incertidumbre de escala. Guardar una medida fuera del ajuste y reportar su residuo. Los 2 mm del morro no se copian a toda la cola.
6. Entregar una tabla breve de «documentado / medido / estimado / sin resolver». Áreas y brazos calculados desde contornos aceptados se pueden ofrecer al otro desarrollador como candidatos, con procedencia; no sustituyen automáticamente datos aerodinámicos.

## Contrato y trabajo en paralelo

| Frente | Responsabilidad |
| --- | --- |
| Modelado | `assets/aircraft/`, `app/aircraft/`, `app/render/airplane.gd`, este plan, investigación y capturas del modelo |
| Física/simulación | `app/physics/`, `app/sim/`, `app/data/aircraft/`, pruebas de simulación, escena principal y roadmap |
| Intercambio | Avisar mediante documentación de cambios que afecten envergadura, cuerda, borde de ataque o línea de empuje; entregar evidencia y comprobar integración. No editar silenciosamente parámetros del otro frente |

La fuente única de geometría visual es [geometry.json](../assets/aircraft/ugly-stik-60/geometry.json), compilada a [ugly_stik_geometry.gd](../app/aircraft/ugly_stik_geometry.gd). La física coteja envergadura/cuerda y el render usa borde de ataque/línea de empuje para transformar el CG; por eso un cambio de datum tiene efectos fuera del constructor. CG físico y origen visual son distintos.

Conservar `build()` → `{root, propeller, hinges}`, raíz `airplane`, hélice `propeller` y bisagras `aileron_left`, `aileron_right`, `elevator`, `rudder`. Ejes: metros, +X derecha, +Y arriba, −Z morro. Los marcos alares contienen el diedro estático y sus bisagras solo la deflexión. Las órdenes positivas mantienen roll derecho, pitch arriba y yaw derecho según las pruebas existentes.

No añadir arquitectura de familias, Blender o una ruta GLB para completar estas tareas. El ensayo GLB queda disponible como investigación. No derivar masa/inercia de la malla exterior ni polares de su perfil visual.

## Prueba proporcional al cambio

- Cambios de datos: compilador `--check`, cotas independientes y procedencia. Validar las restricciones del dato que se cambie; no construir un sistema de esquemas general por adelantado.
- Cambios de malla o bisagras: contrato actual, prueba específica sobre geometría construida y captura comparable; `app/test.sh` antes de entregar código integrado. No usar el número total de comprobaciones como medida de fidelidad.
- Cambios de color: comparación visual con cámara, luz y geometría fijas; sin pruebas unitarias que repitan el color escogido.
- Cambios solo documentales: enlaces, coherencia de estados y evidencia citada; no hace falta ejecutar física.
- Borradores GDScript fuera de `app/` hasta que parseen; las pruebas de mutación se hacen en copias temporales. Cada entrega registra su prueba y una lección práctica.

Preservar v1/v2 como evidencia histórica. Las próximas capturas deben guardar solo referencias deliberadas o resultados útiles; las series transitorias no necesitan convertirse en un archivo permanente. Los planos, fotos y CAD originales siguen locales bajo `references/`.

## Decisiones conservadas y trabajo aplazado

Las [diez investigaciones](research/ugly-stik-investigations/README.md) y el [índice de referencias](research/aircraft-reference-index.md) siguen disponibles. Los 31 archivos aportados conservan sus hashes y están separados por avión. Jensen es la fuente principal; Ultra Stick 120, Great Big Stik, REFLEX y MoJo no aportan dimensiones intercambiables.

Se conserva el dato nominal de 60 in / 720 in² / .45–.61. La sección visual v3 proviene de una lectura normalizada de costilla; no es una polar ni un perfil NACA identificado. Las posiciones ocultas, incidencia, diedro, equipo genérico, materiales y simplificaciones del festoneado siguen etiquetados como aproximaciones. La longitud de otra miniatura no certifica la de este plano.

Quedan aplazados: mini/gigante, estructura interna, conversión completa de CAD, instalación comercial exacta sin equipo elegido, acabado fotorrealista y LOD sin medición. Vuelo, contacto con suelo, sonido y entrada de radio avanzan por el roadmap del desarrollador principal. Esta entrega no modifica su simulación ni sus datos físicos.
