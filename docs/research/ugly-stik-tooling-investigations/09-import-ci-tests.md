# 09 · Importación reproducible y herramientas de pruebas

2026-10-05 · Investigación web y lectura del repositorio; propuestas todavía sin ejecutar. Aplica a US-V02 y US-V08.

## Pregunta y situación local

¿Cómo evitar que el nuevo atlas funcione únicamente en la máquina donde se creó, y aporta algo incorporar un framework de pruebas? `app/test.sh` ya comprueba parseo, pruebas `SceneTree`, errores del motor y contrato del avión. No contiene una fase explícita de importación: el modelo nativo actual no necesita una ruta GLB. La primera textura introduce una dependencia nueva de la caché de recursos. Godot está fijado a 4.7.2; la documentación consultada corresponde a 4.7, no certifica por sí sola ese parche.

## Hallazgos con fuentes primarias

- **Importar antes de probar.** `--import` arranca el editor, espera las importaciones y termina; implica `--editor` y `--quit`. `--headless` permite realizarlo sin pantalla. `--check-only --script` comprueba parseo, pero no reemplaza importar recursos ni renderizar. Godot además advierte que ignora argumentos desconocidos: registrar la versión evita confiar en una opción inexistente. [CLI oficial 4.7](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html).
- **Separar fuentes de caché.** `.godot/` se excluye del control de versiones. Los UID de recursos importados viven en sus archivos `.import`; desde 4.4, scripts y shaders tienen archivos `.uid` que deben acompañar al original y entrar en Git. No confundir esos archivos vecinos con el contenido regenerable de `.godot/`. [Control de versiones](https://docs.godotengine.org/en/4.7/tutorials/best_practices/version_control_systems.html), [explicación oficial de UID](https://godotengine.org/article/uid-changes-coming-to-godot-4-4/).
- **GUT:** su matriz declara **9.7.1 para Godot 4.7.x**, con pruebas parametrizadas, dobles y ejecución CLI; licencia MIT. La release existe, pero los enlaces de documentación consultados muestran etiquetas 9.6.x incluso al abrir `/en/v9.7.1/`. Antes de adoptarlo habría que contrastar API y ejemplos con el tag, no copiar instrucciones de `latest`. [Repositorio y matriz](https://github.com/bitwes/Gut), [release 9.7.1](https://github.com/bitwes/Gut/releases/tag/v9.7.1), [documentación consultada](https://gut.readthedocs.io/en/v9.7.1/).
- **gdUnit4:** ofrece pruebas de escenas, parametrización y dobles, con licencia MIT. La matriz de **v6.2.0** enumera Godot 4.7 y 4.7.1, sin enumerar 4.7.2. Eso deja nuestro parche sin comprobación local; no demuestra incompatibilidad. [Repositorio y matriz](https://github.com/godot-gdunit-labs/gdUnit4), [licencia](https://github.com/godot-gdunit-labs/gdUnit4/blob/master/LICENSE).

## Decisión para el plan

**Adoptar en V02:** integrar importación con tiempo límite antes del parseo cuando entre el primer atlas, conservar fuentes y ajustes `.import`, y verificar desde un clon limpio. Mantener las pruebas existentes. **Aplazar GUT/gdUnit4:** hoy no hay un problema de pruebas que justifique migrar la suite; reevaluar ante una necesidad concreta de fixtures o interacción de escenas. No se instaló ninguno.

Secuencia propuesta desde la raíz, todavía no ejecutada para el atlas:

```sh
timeout 60 "$(app/get-godot.sh)" --headless --path app --import
app/test.sh
app/capture.sh
```

## Prueba de utilidad

En una copia limpia: importar el atlas, cargarlo y capturar la pieza UV de V02; registrar versión, ajustes y hash fuente. En otra copia temporal, retirar la textura y comprobar que la validación falla, sin dejar el árbol compartido roto. El wrapper debe tratar errores del motor como fallos incluso si el proceso devuelve cero. La captura visual necesita el renderizador Compatibility y Xvfb/display del flujo existente: `--headless` por sí solo no certifica apariencia. La integración de CI se coordina con su propietario; esta investigación solo entrega el requisito.
