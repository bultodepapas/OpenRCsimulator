# Ugly Stik .61: plan de modelado en paralelo

Revisión 5 · 2026-10-05 · **Pausa de implementación solicitada por el propietario; revisión y planificación completadas.** Base actual: Jensen Ugly Stik 60 in / nitro .61, modelo v2. [Revisión crítica y evidencia](research/ugly-stik-model-review-v2.md) · [Entrega v2](research/ugly-stik-model-v2.md) · [Plan anterior y notas de integración](UGLY-STIK-PLAN-v4.md).

El objetivo es un avión reconocible, articulado y legible para el primer playtest del simulador. Después se aumenta su fidelidad con medidas identificables del Jensen. **La calibración completa no bloquea M1/PT1.** Mini y gigante quedan para después; el paquete Ultra Stick 120 se conserva como referencia de otra configuración.

## Estado real al hacer la pausa

| Frente | Estado | Evidencia y límite |
| --- | --- | --- |
| Investigación y organización | Hecho | [Diez investigaciones](research/ugly-stik-investigations/README.md), [índice por avión](research/aircraft-reference-index.md), 31 archivos nuevos con hashes conservados |
| Constructor e integración | Hecho | Fuente JSON → constantes Godot → constructor nativo → adaptador `airplane.gd`; no falta una importación GLB |
| Articulación y ensamblaje | Base comprobada | 453 comprobaciones en la ejecución v2; signos, pivotes, asiento alar, envergadura y morro. No certifican todos los contornos ni ausencia de intersecciones |
| Morro | Corrección v2 realizada | F1–borde de ataque: 176,276 mm, tolerancia visual 2 mm; apoyo local por cuerda, no calibración de todo el escaneo |
| Fuselaje posterior y cola | Aproximados | Estaciones posteriores estimadas, anchuras de escala condicional, cola dibujada como aproximación; falta contraste dimensional |
| Ala | Aproximada salvo referencia de envergadura | Cuerda representativa 12 in; perfil, puntas, alerones, incidencia y diedro necesitan evidencia más precisa |
| Motor, escape y tren | Instalación visual provisional | Clase .61 genérica; marca abierta. Ruedas documentadas, hélice de 12 in y posiciones estimadas |
| Lectura desde tierra | Capturas disponibles, aceptación pendiente | Serie 20/50/100 m; falta probar orientaciones y fondos con el propietario |
| Física | Otro frente | D1 completado según el roadmap; M1 sigue su propio desarrollo. No inferir vuelo validado de una captura en modo scripted |

Los resultados de pruebas son los del [registro v2](research/ugly-stik-investigations/evidence/model-v2-validation.json), cuyos cinco hashes revisados siguen coincidiendo. No se ejecutó una suite nueva durante esta revisión documental. El total de pruebas de física puede variar con el trabajo paralelo.

## Criterios de aceptación separados

**Para acompañar PT1:** mantener la interfaz y los signos de mando, no presentar partes visiblemente separadas ni penetraciones evidentes en las poses comprobadas, conservar escala coherente y permitir evaluar la orientación desde la cámara del piloto. Registrar con el propietario los fallos de lectura y resolver primero los que impidan pilotar. No exigir una réplica dimensional completa ni microdetalle.

**Para declarar una pieza ajustada al plano:** identificar variante, hoja/vista, datum y bordes; guardar coordenadas fuente, transformación, incertidumbre y una cota reservada fuera del ajuste. Comparar malla y contorno en la misma escala, sin estirar cada pieza hasta hacerla coincidir. Los controles deben ser independientes: `720/60` no cuenta como tres medidas. Si el plano no permite cerrar la escala, la pieza sigue marcada como estimada.

**Para mejorar apariencia:** mantener geometría y cámara al comparar colores o acabados. Evaluar la diferencia en el uso previsto: vuelo desde tierra primero, inspección cercana después. La lectura perceptual y el rendimiento requieren prueba humana y equipo real.

## Próximas entregas pequeñas

Los IDs US son tareas del frente de modelado vinculadas al [roadmap](../ROADMAP.md), no nuevos hitos del simulador. Cada fila se entrega por separado y conserva el avión funcionando. Todas están **pendientes** al cerrar esta pausa.

| ID / relación | Objetivo y dependencia | Resultado y prueba de cierre |
| --- | --- | --- |
| US-01 · D1 | Proteger la evidencia antes de otro cambio de malla | Destino actual explícito que no sobrescriba v1/v2, metadata sin «v1» fijo, manifiesto con ID/hash de geometría, cámara completa y pose. Repetir una captura con los mismos parámetros y comprobar su procedencia |
| US-02 · D1 | Medir fuselaje y ubicar la cola; usa US-01 para la comparación posterior | Ficha con F1, bordes del ala, estaciones identificadas, extremos de fuselaje, bisagras y contornos de cola; puntos por vista, escalas, controles, residuos e incertidumbres. **Una sesión inicial**; cerrar con medidas aprovechables o incertidumbres explícitas |
| US-03 · D1 | Corregir fuselaje posterior y su altura/anchura con los datos aceptados de US-02 | Una modificación geométrica pequeña; perfil/planta superpuestos a escala, cota reservada dentro de la tolerancia declarada y asiento del ala conservado. No desplazar ala/CG para esconder una discrepancia |
| US-04 · D1/B5 | Corregir contornos y ubicación de la cola después de fijar su unión con US-03 | Estabilizador, elevador, deriva y timón identificados por separado; pivotes sobre sus líneas de bisagra. Comprobar neutro, ambos extremos y combinaciones de pitch/yaw, con capturas cercanas y holguras de las zonas críticas |
| US-05 · D1/B5 | Mejorar una característica del ala por entrega, tras US-02 | Primero límites de puntas/alerones; después sección y diedro si hay evidencia. Mantener marcos de reposo y signos; comprobar cada nueva cota. Incidencia desconocida sigue explícita, sin elegir un NACA por apariencia |
| US-06 · D7/Gate 2 | Ensayar orientación desde tierra; puede hacerse en paralelo a US-02–05 con v2 fijo | Serie acotada a 20/50/100 m: cara superior/inferior, viraje a ambos lados y acercamiento/alejamiento, sobre cielo y suelo. Registrar cámara y respuestas del propietario: arriba/abajo, izquierda/derecha, viene/se aleja. Comparar errores y dudas entre decoraciones, sin declarar un porcentaje de éxito inventado |
| US-07 · E1/E2 | Preparar instalación y tren para M2, coordinado con física | Declarar equipo provisional o comercial; revisar soporte/escape/hélice, contactos de rueda y ejes de giro/dirección. Entregar puntos en marco visual y transformación al marco físico; comprobar coherencia antes de integrar contacto/taxi |
| US-08 · Gate 2/M5 | Detalle cercano y rendimiento según el playtest | Priorizar sujeción del ala y accesorios visibles si aportan reconocimiento. Medir en hardware del propietario antes de consolidar mallas o introducir LOD. Cada detalle conserva pruebas y lectura de vuelo |

**Siguiente acción al retomar:** US-01, después la ficha US-02. El resultado de US-02 decide qué corrección se puede justificar; no presupone que todas las cotas se resolverán. Si solo una medida queda clara, se corrige esa pieza y se mantiene etiquetado el resto. US-06 no espera a una cola perfecta.

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

El [índice de investigaciones](research/ugly-stik-investigations/README.md) conserva fuentes y experimentos: Jensen firmado 60 in / 720 in² / .45–.61; perfil cualitativo semisimétrico; morro y CG leídos localmente; masa/recorridos reales y coordenadas de perfil aún sin validar para una construcción concreta. La longitud de 52 in de otra miniatura no se convierte en longitud confirmada de este plano.

O.S. 61FX sirve de referencia provisional, sin elegir marca. REFLEX, Great Big Stik y Ultra Stick 120 aportan comparaciones, no geometría Jensen intercambiable. MoJo sigue sin identidad geométrica confirmada. [Catálogo y clasificación](research/aircraft-reference-index.md).

Quedan aplazados: mini/gigante, estructura interna, conversión completa de CAD, instalación comercial exacta mientras falte elección, acabado fotorrealista y LOD sin medición. El vuelo realista, contacto con suelo, sonido y entrada de radio avanzan según el roadmap del desarrollador principal.
