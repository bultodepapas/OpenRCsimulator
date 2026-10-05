# 07 — Dirección visual y recursos

**Investigado:** 2026-10-05. **Pregunta:** ¿qué lenguaje visual puede hacer reconocible a OpenRC con el Ugly Stik y el campo actuales, sin inventar contenido ni depender de arte externo? **Evidencia:** lectura de `docs/MENU-PLAN.md` y revisión de imágenes oficiales enlazadas abajo; no se copiaron imágenes al repositorio ni se ejecutó la app.

## Referencias observadas

La página oficial de [RealFlight Evolution](https://www.horizonhobby.com/realflight/) presenta el producto mediante aeronaves sobre un campo abierto, cielo azul y vegetación. Inspeccioné su imagen: varios modelos vuelan sobre un paisaje verde, con el cielo como fondo principal. Sirve de referencia de género, no de composición de menú, ya que no muestra interfaz.

El [manual oficial de RealFlight 9](https://www.horizonhobby.com/on/demandware.static/Sites-horizon-us-Site/Sites-horizon-master/default/Manuals/RFL1100_RFL1101-Manual-EN.pdf), creado en 2019, sí muestra una pantalla de selección. Inspeccioné la página impresa 50: un panel oscuro cubre parte de la escena de vuelo, con categorías a la izquierda, dos tarjetas grandes con imagen y descripción en el centro y un botón FLY! separado abajo. Es un ejemplo histórico de “preparar y volar”; la captura no describe la UI actual de Evolution y no se debe copiar su arte o estilo literal.

La [nota de la AMA Foundation sobre un evento de club](https://amafoundation.modelaircraft.org/posts/ama-district-vi-club-celebrates-national-model-aviation-day-1) muestra aviones en césped, personas trabajando alrededor de ellos y toldos de sombra. Da soporte a una lectura social de “día de campo”, pero no implica que el escenario actual de OpenRC tenga club, espectadores o toldos.

## Tres direcciones posibles

**Campo tranquilo — recomendada para Inicio.** Usar una captura estática propia del Ugly Stik sobre el campo que ya existe, con cielo y vegetación reales del simulador, una superficie opaca para lectura y el botón Volar como foco. Mantiene la identidad en el avión y no requiere escenario de hangar, animación en segundo plano ni contenido que aún no está implementado. El panel con un avión y campo activos puede tomar la jerarquía de “imagen y descripción + acción de volar” del manual de RealFlight, pero usando nuestros componentes y datos.

**Club y línea de vuelo — guardar para una expansión.** La foto de AMA respalda el césped, los modelos en tierra y la convivencia. Puede funcionar cuando exista un campo de club representado; ahora prometería una instalación que no tenemos. Una tarjeta de estado de radio puede evocar el equipo personal sin inventar una escena social.

**Banco de trabajo — útil dentro de Configurar vuelo, no como mundo de fondo.** La selección por categorías, imagen, ficha y acción principal que muestra el manual ayuda a organizar avión, escenario y control. Es funcional cuando crezca el catálogo. Para un solo avión y un solo campo, replicar categorías o construir un taller 3D añade ruido y mantenimiento. “Banco de trabajo” puede ser una metáfora para tarjetas de preparación; el piloto RC sigue siendo una persona en tierra, no dentro de una cabina.

## Aplicación y recursos

Propongo que UI-01 pruebe Campo tranquilo con una captura propia y Theme compartido de Godot para color, foco, tamaños y espaciado; usar Container para distribuir controles. No incrustar texto en la imagen, para conservar ajustes de idioma y tamaño. Reutilizar en Aviones y Escenarios tarjetas con imagen, título, descripción y acción. No importar fotos ni logotipos de las referencias.

Para prototipar antes del Theme propio, el [UI Pack de Kenney](https://kenney.nl/assets/ui-pack) declara licencia CC0. Es opcional: revisar cada archivo y conservar su metadata, pues el permiso no garantiza encaje visual. Para el producto final, usar StyleBox nativo y capturas propias. La paleta candidata reserva el rojo como acento; el reporte 08 muestra que rojo sobre panel oscuro no alcanza el objetivo calculado.

**Validación propuesta:** capturar Inicio a 1280×720, 1920×1080 y en ventana pequeña. Revisar visibilidad de Volar, resumen y estado de control, y que el panel no oculte el avión. Confirmar que la captura representa el producto real. No hice prueba de usabilidad ni medí rendimiento. La pantalla de RealFlight 9 es de 2019 y las fotos de AMA describen otro evento: inspiran, pero no predicen qué entenderán los pilotos de OpenRC.
