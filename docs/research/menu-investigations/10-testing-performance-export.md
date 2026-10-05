# 10 — Pruebas, rendimiento y distribución del menú

**Investigado:** 2026-10-05. **Pregunta:** ¿cómo demostrar que una entrada nueva funciona sin alterar el vuelo ni depender del entorno del desarrollador? **Evidencia:** documentación primaria consultada en internet e inspección de scripts existentes; no se ejecutó el menú, que aún es una propuesta.

## Hallazgos verificables

1. **Simular una acción no equivale a enviar un evento.** `Input.action_press()` cambia el estado de una acción, pero no llama a `_input()`; `parse_input_event()` sí introduce eventos en el juego. Tampoco simula la interacción con el sistema operativo: un Alt-Tab inyectado no cambia de ventana. Por eso una prueba que llame directamente a `button.pressed.emit()` no acredita navegación, foco ni aislamiento de mandos. [Godot Input](https://docs.godotengine.org/en/stable/classes/class_input.html).
2. **Los contadores tienen condiciones de lectura.** `Performance` ofrece nodos, recursos y nodos huérfanos; algunos monitores solo funcionan en debug y pueden actualizarse con demora. Un cero en release no demuestra ausencia de fugas. Proponemos comparar recuentos tras estabilizar cada retorno al Inicio y observar las instancias que posee la raíz. [Godot Performance](https://docs.godotengine.org/en/stable/classes/class_performance.html).
3. **La captura debe esperar a que termine el render.** `RenderingServer.frame_post_draw` se emite tras actualizar los viewports. Es un punto de sincronización para capturas, distinto de esperar un número arbitrario de milisegundos. No certifica por sí solo que una fuente o recurso asíncrono esté listo. [RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#signals).
4. **Importación y exportación son pasos comprobables.** La CLI permite scripts `SceneTree`, ejecución headless, importación y exportación. `--import` espera a que termine la importación antes de salir. Son capacidades suficientes para conservar la infraestructura propia; esta investigación no justifica introducir un framework nuevo. [Command line tutorial](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html).
5. **Los archivos ajenos al sistema de recursos necesitan atención al empaquetado.** La guía de exportación distingue recursos y filtros para archivos como JSON, CSV o TXT. Una imagen o fuente importada y un manifiesto JSON no deben tratarse como si tuvieran idéntica ruta de inclusión. [Exporting projects](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html#resource-options).

## Aplicación al código actual

[`app/test.sh`](../../../app/test.sh) ya ejecuta scripts headless, rechaza errores del motor y compara el estado físico a 30/60/144 fps. [`test_e2e_radio.gd`](../../../app/tests/test_e2e_radio.gd) inyecta eventos de radio, sustituye identidad del dispositivo falso y utiliza otro archivo de calibración. Extender este enfoque a la raíz nueva da evidencia más relevante que contar botones.

[`capture.sh`](../../../app/capture.sh) utiliza Xvfb/OpenGL; las capturas de la UI deben ser un grupo separado de las vistas de vuelo existentes. [`export.sh`](../../../app/export.sh) ya importa y comprueba vuelo headless del binario exportado: ese resultado puede seguir verde aunque el nuevo Inicio esté roto. Necesita una comprobación adicional de la entrada interactiva, con render cuando se evalúan imágenes o textos.

## Recomendación y pruebas propuestas

| Nivel | Caso que aporta evidencia | Qué no demuestra |
| --- | --- | --- |
| Headless | Abrir raíz, Tab/Enter/Esc mediante eventos completos de pulsar/soltar, observar pantalla y foco | Distribución visual correcta |
| Headless | Menú abierto + tecla de vuelo sostenida + radio movida: no cambian tick ni mandos aplicados | Compatibilidad de un transmisor físico |
| Headless | Desconectar durante calibración y cerrar modal: no reanuda ni pierde causa de bloqueo | Comportamiento del foco del sistema operativo |
| Xvfb/OpenGL | Inicio, Ajustes con scroll, calibración, error y foco; capturas a escala y tamaño fijados | Rendimiento GPU del propietario |
| Export limpio | Importar desde clon limpio; entrar al menú del binario y cargar sus recursos | Usabilidad humana |
| Equipo del piloto | Alt-Tab real, radio real, pantalla completa, lectura, tiempos y sonido | Determinismo entre todos los equipos |

**Ahora:** mantener fixtures propios pequeños; tomar la primera vuelta como calentamiento, después repetir cinco ciclos Inicio → Volar → Inicio (cantidad propuesta, no umbral científico). Medir picos de carga por separado del vuelo estable; registrar resolución, renderer, equipo, versión y escala. No exigir que toda memoria de caché vuelva al primer byte: buscar crecimiento continuado e instancias retenidas.

**Después:** automatizar nuevas resoluciones/casos cuando existan esas pantallas. No adoptar un sistema de diferencias perceptuales adicional hasta que las capturas y aserciones geométricas revelen una necesidad.

**Resultado para el plan:** UI-00 registra baseline e inventario de CLI; UI-03 comprueba liberación tras ciclos; UI-11 exige prueba de raíz exportada además de la traza. Las rutas técnicas deben ignorar preferencias personales. Guardar evidencias por build y mantener golden flights físicos sin regrabarlos por un cambio de interfaz.

**Límite:** páginas `stable` consultadas, no auditoría del tag del motor. No se publican números de arranque, fps o memoria porque no se midieron aquí. La suite de vuelo no se ejecutó durante esta investigación documental.
