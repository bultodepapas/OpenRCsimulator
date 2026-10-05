# 08 — Accesibilidad y legibilidad

**Investigado:** 2026-10-05. **Pregunta:** ¿qué objetivos de texto, contraste, foco y movimiento podemos adoptar para el menú de escritorio sin confundir una guía con una certificación? **Evidencia:** Xbox Accessibility Guidelines (XAG), W3C WCAG 2.2 y cálculo reproducible de una paleta candidata; no existe UI nueva que evaluar.

## Hallazgos

Las [XAG 101 sobre texto](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/101) publican para PC/VR referencias de tamaño mínimo de 18 px a 1080p y 36 px a 4K, y recomiendan que el jugador pueda escalar el texto hasta 200 % sin perder contenido, funcionalidad o significado. También piden una opción sans serif y fuentes con juegos de caracteres completos para todos los idiomas soportados. Son recomendaciones de experiencia de juego. Su medida en píxeles de pantalla no equivale automáticamente al `font_size` lógico de Godot, así que el valor útil para OpenRC es la altura renderizada en la captura/exportación.

La [XAG 102 sobre contraste](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/102) usa 4.5:1 para texto estándar y 3:1 para texto grande y elementos inactivos; además anima a permitir fondo sólido, colores configurables o modo de alto contraste. La [XAG 117 sobre distracciones y movimiento](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/117) recomienda pausar u ocultar contenido que se mueve, parpadea o se actualiza solo y dar opciones para movimiento de cámara y pantalla. Eso apoya la propuesta de un fondo estático en Inicio y evita texto sobre una vista 3D en movimiento.

[WCAG 2.2](https://www.w3.org/TR/wcag/) es un estándar para contenido web. Su 1.4.3 fija 4.5:1 para texto normal y 3:1 para texto grande; 2.4.7 pide foco de teclado visible; 2.4.13 define un indicador con área y contraste específicos como nivel AAA; 2.5.8 da 24×24 píxeles CSS como tamaño mínimo de puntero con excepciones. Estos criterios no certifican una app Godot nativa: los píxeles CSS no son unidades de Godot, y la conformidad web no se deduce de una captura del juego. Los tomo como referencias para fijar metas internas y revisar con personas.

## Aplicación a OpenRC

El cálculo local de `contrast-check.json` usa colores planos opacos y luminancia sRGB. Para el panel `#17252A`, texto crema `#F5F2E9` da 14.058:1 y texto secundario `#BBC8C6`, 9.135:1. Texto crema sobre rojo `#B6322E` da 5.384:1. En cambio, rojo sobre el panel da 2.611:1 y no alcanza el objetivo adoptado de 3:1 para elementos no textuales. El foco ámbar `#F5C65D` sobre panel da 9.830:1; sobre rojo, 3.765:1. **Propuesta:** botón rojo solo con etiqueta clara; el rojo nunca será texto pequeño ni la única diferencia para indicar foco, radio conectada, calibración o armado. Poner un contorno ámbar visible alrededor del control enfocado y un mensaje de estado con palabras e icono/forma.

Para UI-01, mantener texto sobre un PanelContainer opaco incluso si detrás hay foto; el contraste del texto sobre imagen cambia por píxel y no queda validado por este cálculo. El foco inicial debe caer en Volar; Tab, flechas, Enter y Esc deben mostrar en todo momento dónde está el foco. Reservar animación o cámara móvil para el vuelo y permitir pausarla o reducirla si la escena de inicio llegara a ser animada. La radio no debe comunicar “listo” solo mediante color.

## Política y validación propuestas

Adoptar como objetivos de diseño de esta UI 4.5:1 para texto normal, 3:1 para bordes/foco y etiquetas grandes, foco visible sin límite de tiempo y texto ampliable hasta 200 % con scroll/reflujo cuando haga falta. La referencia Xbox de 18 px a 1080p puede guiar el tamaño mínimo renderizado de cuerpo; primero hay que capturar el export a resolución conocida y medir los glifos, no asignar 18 directamente en Theme. Esto es una política interna propuesta, no una declaración de conformidad con WCAG o XAG.

Cuando exista la primera pantalla, calcular todas las parejas de texto/fondo y foco/borde usadas, revisar la captura sobre fondos claros y oscuros, verificar lectura a 100 % y 200 %, y recorrer cada pantalla solo con teclado. Hacer una prueba humana a distancia normal de vuelo para encontrar textos que exijan acercarse a la pantalla. Esta ronda calcula seis parejas planas; no mide antialiasing, foco dibujado, daltonismo, visión de bajo contraste, reflejos ni comprensión. Se necesita revisión con captura y piloto antes de declarar que el menú es legible.
