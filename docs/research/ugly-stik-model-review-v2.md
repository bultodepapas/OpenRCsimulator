# Revisión del modelo y del plan después de v2

2026-10-05 · Pausa solicitada por el propietario. Revisión documental, de código y de imágenes; no se modifica la malla ni la simulación. Resultado incorporado al [plan revisión 5](../UGLY-STIK-PLAN.md).

## Propuesta y su mejor versión

El objetivo sigue siendo un Jensen Ugly Stik de 60 in con motor clase .61, reconocible y articulado, que acompañe el primer vuelo del simulador. La mejor continuación aprovecha el constructor nativo, corrige unas pocas dimensiones que cambian mucho la silueta y valida la lectura desde tierra. No necesita una reconstrucción de estructura interna ni una malla fotorrealista para el primer playtest.

## Evidencia revisada

- [Fuente geométrica](../../assets/aircraft/ugly-stik-60/geometry.json), [constructor](../../app/aircraft/ugly_stik_model.gd), [pruebas del modelo](../../app/aircraft/verify_model.gd), [visor](../../app/aircraft/inspect_model.gd) y [adaptador](../../app/render/airplane.gd).
- Ambas hojas Jensen renderizadas localmente: hoja 1 (`references/ugly-stik/calibration-v1/renders/jensen-1.png`, local only) y hoja 2 (`references/ugly-stik/calibration-v1/renders/jensen-2.png`, local only). Comparación visual con planta, frente e intradós v2; perfil y tres cuartos revisados en la entrega v2.
- [Calibración provisional](ugly-stik-model-v1-calibration.md), [medición del morro](ugly-stik-investigations/evidence/model-v2-nose.json), [validación v2](ugly-stik-investigations/evidence/model-v2-validation.json), [manifiesto de capturas](../../research/ugly-stik/model-v2/captures/manifest.json) y [roadmap](../../ROADMAP.md).
- Los cinco hashes de fuente/captura registrados en la validación v2 coinciden al revisar. Las 453 comprobaciones y la suite verde pertenecen a esa ejecución anterior; esta revisión no vuelve a ejecutar pruebas de una simulación que está cambiando en paralelo.

## Supuestos que hay que limitar

| Supuesto | Qué muestra el repositorio | Consecuencia |
| --- | --- | --- |
| «El modelo ya sigue el plano porque pasa 453 comprobaciones» | Se comprueban nodos, datos finitos, signos, pivotes, asiento del ala, envergadura y morro. No hay comparación completa de contornos | Separar funcionamiento del modelo de fidelidad dimensional |
| «Corregir F1 calibra el fuselaje» | v2 transformó solo tres estaciones delanteras; las restantes conservan Z/alturas estimadas y anchuras de una escala condicional | Medir estaciones posteriores antes de retocar su aspecto |
| «La cola redondeada representa Jensen» | `evidence.tail` declara una aproximación; el estabilizador del plano muestra un contorno distinto del polígono actual. La traza anterior fue descartada por ambigua | Identificar cada vista, sus límites y bisagras antes de adoptar puntos |
| «Hay que terminar toda la calibración antes del primer vuelo» | El modelo ya cumple su interfaz y tiene pruebas/capturas; M1 necesita vuelo y lectura desde tierra | La metrología completa no debe bloquear PT1 |
| «Las imágenes a 100 m prueban legibilidad» | Hay una sola orientación por distancia, fondo uniforme y unos 12 px de ancho proyectado | Falta un ensayo de orientación sobre cielo/suelo y en la cámara del simulador |

## Riesgos y mejoras por componente

| Componente | Estado comprobado | Falta y mejora propuesta | Prioridad |
| --- | --- | --- | --- |
| Fuselaje | Morro F1–ala 176,276 mm con control local; unión alar comprobada | Longitud posterior, alturas y anchos coherentes entre planta/perfil; tabla de estaciones y superposición a escala. La cara inferior del modelo sube hacia la cola; contrastarla con la línea casi recta visible en el perfil Jensen, sin inventar una corrección numérica | Alta dimensional |
| Cola | Piezas fijas y móviles, signos y pivotes funcionales | Planta del estabilizador, perfil deriva/timón, brazo desde ala y huecos para mandos. La cola actual mide 0,56 m de ancho nominal, pero es una elección visual | Alta dimensional |
| Ala | 1,524 m nominales, sección y diedro visibles; alerones en marcos fijos | Trazar sección, puntas y límites de alerones. `tip_start` cambia la banda de color, no redondea la punta; `_wing_panel` mantiene sección constante hasta el extremo. Diedro 2,86° y perfil siguen estimados | Media, después de cotas principales |
| Mandos | Pruebas con ±1 por eje y retorno a neutro | Holgura en elevador/timón combinados y junto al fuselaje. La captura usa +0,75 en tres ejes; no cubre todo el recorrido. Añadir solo comprobaciones de las zonas donde pueda haber contacto | Alta antes de aceptar la nueva cola |
| Motor/hélice/tren | Conjunto provisional .61, diámetros de ruedas documentados, hélice de 12 in estimada; holgura calculada 96,1 mm | Ajustar soporte, escape y posición del tren a una instalación declarada. Ruedas aún no giran ni orientan dirección en el constructor; sincronizarlo cuando exista E1/E2 | Después de forma; coordinación antes de M2 |
| Apariencia | Bandas claras arriba e intradós oscuro; cinco materiales | Ensayo de orientación con geometría fija; luego bandas de sujeción del ala, cuernos/varillas o tapa si aportan lectura cercana | Lectura alta; microdetalle baja |
| Evidencia | Capturas y medidas v1/v2 separadas, hashes v2 guardados | El visor sin argumentos y el script v1 aún escriben en v1; la metadata del constructor dice «visual v1». El manifiesto no guarda todos los parámetros de cámara ni el hash geométrico. Corregir esto al retomar para evitar evidencia mal rotulada | Primera tarea pequeña |

No se ha demostrado una colisión de mandos: falta comprobarla. Tampoco hay evidencia de que 46 instancias y 2.568 triángulos causen un problema de rendimiento. No se propone una optimización ni LOD antes de medir en el equipo del propietario.

## Preguntas que cambian decisiones

La marca concreta del .61 y la fidelidad cosmética final siguen abiertas. Se puede continuar con un motor genérico etiquetado; solo la reproducción de una instalación comercial concreta depende de esa elección. La decoración actual sirve para comparar lectura, sin atribuirle autenticidad histórica. Una foto aislada o un plano Ultra Stick 120 no resuelve dimensiones Jensen.

Para cada medida futura hay que responder: ¿qué pieza y vista estamos leyendo?, ¿qué punto fija su datum?, ¿qué control independiente permite detectar una escala incorrecta? Si no se puede responder, el dato permanece estimado y se documenta qué evidencia lo resolvería.

## Contraste de las objeciones

- Se descartó tratar la integración como pendiente: `airplane.gd` ya delega al modelo y las pruebas anteriores pasan. Tampoco hace falta reabrir Godot/GLB.
- Se descartó decir que la escala no tiene ningún apoyo: la cuerda respalda localmente la lectura del morro. Ese apoyo no se extiende automáticamente a detalles o a la segunda hoja.
- Se confirmó que hay cámaras fijas por vista; no hace falta sustituir un supuesto autoencuadre. Sí falta registrar su configuración completa en el manifiesto y conservarla entre comparaciones.
- Se confirmó el límite de las pruebas de mandos revisando `_check_control_direction` y `_set_pose`: signos y pivotes están cubiertos; intersecciones y combinaciones extremas no.
- La separación de física no es absoluta: `main.gd` usa `leading_z` y `shaft_y` para colocar el CG visual, y `test_aircraft_data.gd` coteja envergadura/cuerda. Cambiar esos cuatro parámetros requiere integración coordinada, aunque la edición sea «visual».

## Veredicto

**Buena idea, pero necesita límites.** Mantener v2 como base funcional para M1. Antes de aumentar detalle, cerrar una ficha dimensional útil de fuselaje/cola y comprobar sus mandos. La aceptación visual para PT1 se decide por lectura y funcionamiento; la fidelidad de plano se acepta por medidas y residuos. Ninguna de las dos sustituye la validación de vuelo del otro desarrollador.

## Acciones siguientes

1. Asegurar identidad y destino de las próximas evidencias sin sobrescribir v1/v2.
2. Una sesión de medición de fuselaje y cola: puntos, escalas por vista, cotas de control y dudas. Si la escala sigue abierta, terminar con una tabla de incertidumbres útil; no repetir investigación indefinida.
3. Aplicar una corrección de fuselaje por entrega; después cola y recorrido combinado, con pruebas sobre la malla construida.
4. Ensayar orientación a distancia en paralelo con D7/PT1; dejar incidencia/perfil exactos y equipo comercial como trabajo acotado posterior si siguen sin evidencia.

Las tareas, dependencias, pruebas y criterios de cierre están en el [plan vigente](../UGLY-STIK-PLAN.md). Esta pausa termina con documentación actualizada, sin iniciar la siguiente modificación del modelo.
