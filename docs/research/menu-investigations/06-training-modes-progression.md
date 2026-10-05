# 06 — Entrenamiento breve y progresión basada en capacidades

**Investigado:** 2026-10-05. **Pregunta:** ¿qué aprendizaje inicial ayuda a orientarse sin convertir una alfa pequeña en un curso, competición o sistema de logros? **Evidencia:** manuales oficiales de SeligSIM, aerofly RC 10 y RealFlight Drone, contrastados con las capacidades descritas en el repositorio.

## Hallazgos verificables

1. **SeligSIM distingue aprender mirando de salir a volar libre.** Su manual 2026 ofrece lecciones Basic y Advanced como rutas separadas del vuelo libre. Las básicas incluyen despegue, giros y aterrizaje; durante una lección se ven el avión y las posiciones de sticks grabadas, con voz, pausa, cámara lenta y repetición. El manual también documenta una ayuda graduable para aprender estacionario 3D, que pierde efecto en vuelo de crucero. Esto describe el producto actual y sus modelos; no implica que OpenRC tenga esos objetivos, grabaciones ni ayudas. ([Flight Training, SeligSIM 2026](https://www.seligsim.com/manual/flight_training.html)).

2. **aerofly RC 10 ofrece ayudas visuales configurables y competiciones separadas.** Su manual dice que prismáticos ayudan a leer actitud, el radar muestra el campo y la orientación de pista, y el rastro de vuelo sirve para practicar trayectorias. El capítulo separado “Competitions and training modes” describe entrenador de estacionario, aterrizaje a objetivo con suma de puntos y carreras por pilones con ruta y control de inicio. Estos ejemplos dependen de simulación, escenarios y objetivos implementados; no son simples etiquetas que se puedan mostrar sobre un modo libre. ([manual RC10, overlays y capítulos 15–17](https://www.ikarus.net/en/rc10-manual/)).

3. **RealFlight documenta lecciones y retos ligados a tareas medibles, pero la referencia disponible es histórica y de drones.** Su manual de Drone explica retos con ruta de obstáculos o búsqueda de objetos, temporizador, instrucciones y puntuación; también registra progreso y niveles. Sirve para precisar por qué un reto requiere objetivo detectable y condición de éxito. No debe usarse como evidencia del estado actual de RealFlight Evolution ni como patrón directo para vuelo de ala fija. ([manual RealFlight Drone, pp. 85–92](https://forums.realflight.com/downloads/RealFlight%20Drone%20Manual.pdf)).

## Aplicación a OpenRC

La app de hoy ofrece un Ugly Stik, un campo, vuelo nivelado en el aire y teclas/radio. Aún no hay despegue ni aterrizaje desde pista; tocar suelo provoca accidente y reinicio. Por eso una pantalla “Entrenamiento” no debe ofrecer aterrizaje, viento variable o puntuación sin una condición inicial, objetivo, detección y reinicio validados para esa actividad. El plan acierta al dejar Entrenamiento y Retos fuera de la primera navegación y al considerar orientación solo más adelante.

**Ahora:** tratar el primer vuelo libre como práctica con ayudas opcionales que ya funcionan, como autozoom, vista de inspección y monitor de mandos. Mostrar una tarjeta de ayuda concisa: qué hacen alerón, elevador, timón y throttle, en qué lado está el piloto y qué hacer si se pierde orientación: pausar, resetear o probar una orden pequeña. No imponer pasos, medallas ni un puntaje. Una ayuda no debe cambiar fuerzas, trims, tasas ni modelo de vuelo.

**Después:** si pruebas con pilotos confirman una necesidad, crear una lección breve de orientación solo cuando el juego pueda dar feedback honesto: identificar rumbo relativo del avión, demostrar que una entrada pequeña produce la respuesta esperada y permitir reiniciar. Un ejercicio de circuito aéreo desde el inicio actual no necesita M2; un circuito completo que evalúe despegue y aterrizaje sí depende de esa entrega y de marcadores/estado comprobables. Antes de cualquier reto, declarar objetivo, criterio de éxito, fallo, pausa y reinicio. Las ayudas y lecciones deben ser optativas y volver a Vuelo libre con el mismo avión y física.

## Validación propuesta y límites

En UI-B, pedir al piloto completar el recorrido de teclado y radio del plan y registrar qué nombres, ejes o ayudas no entiende; aún no evaluar “habilidad de vuelo” con puntuación. Para una futura lección, definir antes una condición objetiva reproducible y revisar falsos éxitos/fallos con trazas y observación humana; comparar la física con Vuelo libre para confirmar que solo cambia la instrucción o la ayuda declarada.

Los manuales describen funciones de simuladores con más contenido y no prueban que una clase de orientación baste pedagógicamente para OpenRC. RealFlight Drone es multirrotor y la fuente es antigua. No inspeccioné capturas de estos modos; las conclusiones proceden del texto de sus manuales. No se hicieron pruebas de aprendizaje ni se propusieron métricas de aprobación.
