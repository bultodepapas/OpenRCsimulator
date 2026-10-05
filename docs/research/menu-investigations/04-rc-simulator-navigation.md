# 04 — Navegación y acceso al vuelo en simuladores RC

**Investigado:** 2026-10-05. **Pregunta:** ¿cómo hacer que se entienda qué avión y campo están activos y que se pueda volar enseguida? **Evidencia:** manuales oficiales de simuladores RC y lectura de `docs/MENU-PLAN.md`; no se modificó ni ejecutó la app.

## Hallazgos verificables

1. **RealFlight deja elegir entre preparar y salir a volar.** El manual de avión RealFlight 9.5 describe un Welcome Screen con avión, campo, escenarios preseleccionados, lecciones y retos, además de un botón grande para entrar directamente al vuelo. Se puede ocultar al inicio y abrir después desde Help. La captura publicada en el manual (p. 28) muestra seis tarjetas de selección/aprendizaje y **FLY!** separado abajo: es un menú de producto maduro, con más contenido que OpenRC. La captura es de la versión 9.5; no la atribuyo a Evolution actual. ([manual RealFlight 9.5, pp. 28–29](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/dw6b391a4f/Manuals/RealFlight-9.5-Manual.pdf)).

2. **aerofly RC 10 separa selección del modelo y del lugar y mantiene visible “Fly”.** El manual de IKARUS sitúa al abrirse un menú inicial para cargar modelo o escenario, configurar control y cambiar opciones. La conexión/calibración puede abrirse desde Control; el manual también permite una prueba inicial con teclado y ratón cuando no hay radio. Los selectores de modelo y escenario también se abren durante el vuelo mediante accesos rápidos. Esto documenta rutas concretas, no una afirmación de que OpenRC deba copiar sus catálogos. ([manual RC10](https://www.ikarus.net/en/rc10-manual/)).

   Inspeccioné tres capturas enlazadas por ese manual: [inicio](https://www.ikarus.net/wp-content/uploads/rc10_manual_web_01.png), [selección de modelo](https://www.ikarus.net/wp-content/uploads/rca10_work15_02.png) y [selección de escenario](https://www.ikarus.net/wp-content/uploads/rca10_work17_03.png). En la primera, el fondo es un campo RC, una barra lateral enumera modelo, escenario, mando y ajustes, y **FLY** queda destacado bajo las imágenes de modelo/lugar. Los selectores usan categorías y miniaturas; la ficha del modelo añade texto técnico. Es una densidad apropiada para una biblioteca grande, pero innecesaria con un avión y un campo.

3. **SeligSIM usa una pantalla de sesión sin convertir cada ajuste en un paso obligatorio.** Su manual 2026 describe un vuelo libre con paneles para avión, campo, cielo, viento, grabación y salida; se puede filtrar avión/campo mediante una búsqueda rápida, y `Enter` activa Fly. Indica que desde un arranque frío se puede llegar al vuelo pulsando `Enter` dos veces. La cantidad de categorías corresponde a su catálogo y capacidades actuales. ([Getting Started: Part II, “Running SeligSIM”](https://www.seligsim.com/manual/getting_started_running.html)).

## Aplicación a OpenRC

La propuesta del plan encaja con estos flujos: **Volar** debe ser la acción más evidente y no exigir que la persona conecte o calibre una radio. Un resumen puede mostrar **Jensen Das Ugly Stik 60 · Campo de pruebas · vuelo libre en el aire**; Aviones y Escenarios llevan a fichas que permiten ver y confirmar el único contenido existente. Las pantallas de catálogo no necesitan filtros, búsqueda, categorías vacías ni una vitrina 3D para cumplir su función inicial. UI-01 abre el vuelo actual; UI-05 y UI-06 exponen el avión y el campo reales.

La identidad debe partir del punto de vista RC: el piloto está en tierra mirando un avión remoto. La captura de aerofly muestra precisamente un campo y el modelo; no es un cockpit de aeronave tripulada. Para OpenRC, un HUD útil o el monitor de sticks puede aparecer durante el vuelo, pero no conviene que la entrada se parezca a un panel de cabina con instrumentación que el piloto no necesita para reconocer orientación.

**Ahora:** conservar un botón Volar de acceso directo, mostrar el avión/campo elegidos y abrir las fichas sin empezar el vuelo accidentalmente. Radio y configuración avanzada quedan disponibles, pero opcionales. **Después:** añadir búsqueda/favoritos o elección rápida durante el vuelo solo cuando existan varias aeronaves o campos con datos probados.

## Validación propuesta y límites

Probar en una instalación limpia y sin joystick que Inicio permita llegar al vuelo de teclado en una acción; abrir y cerrar cada ficha debe devolver a la pantalla anterior, mantener la selección válida y no arrancar una sesión. Revisar capturas de la app con el avión y campo propios a tamaños de ventana acordados. En una prueba humana, observar si se reconoce dónde se está y cómo volar sin leer un tutorial.

Inspeccioné la captura de Welcome Screen de RealFlight 9.5 (página impresa 28 de su PDF oficial), además de las tres capturas indicadas del manual de aerofly RC 10. No inspeccioné capturas de SeligSIM. No medí tiempo de entrada ni hice un playtest de OpenRC; estas recomendaciones son inferencias de producto, no resultados de usabilidad.
