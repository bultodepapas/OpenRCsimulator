# Diez investigaciones para la entrada y los menús de OpenRC

**Fecha:** 2026-10-05. Investigación en internet y contraste con el repositorio para mejorar [MENU-PLAN.md](../../MENU-PLAN.md). Los informes separan documentación, código observado, inferencias de diseño y pruebas todavía pendientes.

**Resultado:** diez informes completados e incorporados a la revisión 2 del plan. [sources.json](sources.json) indexa sus fuentes por página y por informe; los enlaces explicativos permanecen junto a cada afirmación, no solo en el inventario.

## Las diez preguntas

| # | Investigación | Pregunta de decisión |
| --- | --- | --- |
| 01 | [Escenas, ciclo de vida y pausa](01-godot-shell-lifecycle.md) | ¿Cómo añadir Inicio sin arrancar el vuelo ni bloquear la calibración? |
| 02 | [Input, foco y aislamiento de radios](02-input-focus-radio-isolation.md) | ¿Cómo impedir que navegar mueva el avión o que una radio navegue el menú? |
| 03 | [Preferencias, contenido y versiones](03-settings-content-versioning.md) | ¿Qué guardar y cómo recuperar ajustes inválidos sin perder calibraciones? |
| 04 | [Navegación en simuladores RC](04-rc-simulator-navigation.md) | ¿Qué patrones de selección y acceso al vuelo merecen adaptarse? |
| 05 | [Primera conexión de radio](05-radio-onboarding.md) | ¿Cómo explicar detección, canales, calibración y armado sin exigir un tutorial? |
| 06 | [Entrenamiento y modos](06-training-modes-progression.md) | ¿Qué experiencia educativa cabe antes de aterrizajes, viento o puntuaciones? |
| 07 | [Estilo visual y recursos](07-visual-direction-assets.md) | ¿Qué aspecto propio puede tener OpenRC con los recursos que ya existen? |
| 08 | [Accesibilidad y lectura](08-accessibility-legibility.md) | ¿Cómo hacer legibles los estados, textos y controles y comprobarlo? |
| 09 | [Resoluciones e idiomas](09-responsive-localization.md) | ¿Cómo evitar que la UI se rompa al escalar o traducir? |
| 10 | [Pruebas, rendimiento y exportación](10-testing-performance-export.md) | ¿Cómo demostrar que el menú funciona en el binario que recibe el piloto? |

## Cómo leer la evidencia

- **Documentado:** la fuente primaria explica la capacidad o el flujo; las afirmaciones llevan enlaces junto al texto.
- **Observado en código:** se inspeccionó el archivo del repositorio indicado. El trabajo paralelo puede cambiarlo después de esta fecha.
- **Calculado:** existe una operación reproducible, con entradas y límites explícitos.
- **Propuesto:** recomendación para OpenRC; no implica que la app o un producto consultado ya la implemente.
- **Pendiente:** prueba con el Godot fijado, screenshot, experimento o evaluación con piloto que aún no se realizó.

Los manuales comerciales sirven de referencia funcional, no de permiso para redistribuir sus imágenes ni de prueba independiente de calidad. Las guías WCAG/Xbox aportan criterios que podemos adoptar; no convierten este plan en certificación de accesibilidad. Las páginas de Godot `stable` pueden cambiar: verificar APIs y comportamiento en el binario fijado antes de implementar.

## Decisiones que cambian la implementación

- UI-01 retira navegación joypad implícita antes de mostrar botones: el tag exacto del motor ya asocia ejes a `ui_*`.
- Inicio adopta **Campo tranquilo**, con captura propia y panel opaco; «Club» y «Banco de trabajo» quedan como direcciones acotadas para paisaje y fichas.
- Se mantienen Volar y la combinación activa visibles. Se posponen filtros, categorías vacías, talleres 3D y lecciones puntuadas sin objetivos detectables.
- UI-09 se divide en **UI-09a** (escala, reflujo y pseudolocalización) y **UI-09b** (pantalla con confirmación/reversión). El temporizador de reversión funciona mientras la simulación está pausada.
- La pantalla de radio comunica conexión, perfil, movimiento observado y armado por separado; Classic/Advanced se comparan con hardware antes de cambiar la recomendación del repo.
- UI-11 comprueba tanto el Inicio exportado como el vuelo técnico; un smoke test de traza no acredita que el menú empaquetado funcione.

## Evidencia propia complementaria

[contrast-check.json](contrast-check.json) contiene la comparación de seis pares de una paleta candidata. Se reproduce con:

```sh
python3 docs/research/menu-investigations/check_contrast.py
```

El script usa solo la biblioteca estándar y guarda el resultado junto a sí mismo. Cinco pares cumplen su objetivo declarado; **rojo sobre panel oscuro da 2,61:1 y no llega al objetivo 3:1**. La recomendación es añadir etiqueta y borde adecuados, no confiar en rojo como único indicador. Es cálculo sobre colores planos, no lectura de una captura ni ensayo con usuarios.

Esta ronda no ejecuta `app/test.sh`: no modifica la app y hay trabajo paralelo en el paisaje. La validación de la entrega documental comprueba enlaces locales, estructura, diez informes y reproducción del cálculo. Las pruebas de UI descritas en los informes pertenecen a su futura implementación.
