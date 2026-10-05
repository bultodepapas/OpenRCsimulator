# Ajustes locales, catálogo instalado y versión visible

**Consulta:** 2026-10-05. **Pregunta:** ¿Cómo guardar opciones de usuario con recuperación simple, cambiar pantalla de forma segura y mantener versiones de producto/contenido claras?

## Hallazgos verificados

`ConfigFile` parsea un archivo y devuelve `Error` al cargar; al guardar emite una estructura estilo INI y también devuelve `Error`. Ofrece lecturas con valores por defecto, pero la clase no promete migraciones, validación de dominio ni copias de recuperación. Esas reglas deben ser del juego. [Referencia `ConfigFile` de Godot 4.7](https://docs.godotengine.org/en/4.7/classes/class_configfile.html).

`Window` expone el modo y el tamaño físicos de ventana. Pantalla completa ajusta el tamaño a la resolución del monitor, por lo que la UI debe tolerar tamaños distintos; el modo exclusivo tiene diferencias de comportamiento por plataforma. No existe en la referencia una función de «probar y revertir» para el usuario: la confirmación temporal es una política de producto que el proyecto tendría que implementar. [Referencia `Window` de Godot 4.7](https://docs.godotengine.org/en/4.7/classes/class_window.html).

`Engine.get_version_info()` describe la versión de Godot: versión mayor/menor/parche, estado, build y hash del motor. No equivale a la versión de OpenRC. [Referencia `Engine`](https://docs.godotengine.org/en/4.7/classes/class_engine.html). En este repositorio, `project.godot` declara nombre y escena inicial; `export.sh` usa `git describe` para los nombres de paquetes, y `export_presets.cfg` todavía tiene `0.1.0` para macOS. La calibración ya vive aparte en `user://rc_calibration.cfg`; `RcCalibration` guarda perfiles por clave de dispositivo, valida los canales al leer y devuelve vacío para archivo ilegible o perfil inválido. Su guardado actual no conserva una copia si `ConfigFile.load()` falla.

## Recomendación para el plan

**Ahora, UI-07/UI-09b:** crear un `user://settings.cfg` chico con una clave de versión de esquema, valores por defecto en código y lectura/validación explícita por campo. Mantener calibración en su archivo existente: no mezclar identidad del dispositivo, canales ni perfil con preferencias generales. Para un esquema antiguo, migrar versión por versión; ante un archivo corrupto, conservar una copia antes de escribir defaults; ante una versión futura o fallo de guardado, no sobrescribir en silencio. Esta política es inferida: Godot aporta carga/guardado con errores, no su semántica de recuperación.

Para resolución o pantalla completa, guardar modo/tamaño anterior en memoria, aplicar la alternativa temporalmente y mostrar Confirmar/Revertir con cuenta atrás. Persistir solo tras confirmar; el timeout debe restaurar el modo anterior. Un valor de 15 s puede ser punto de partida del spike, no un dato medido. Priorizar ventana y pantalla completa al comienzo; no añadir selector de frecuencia del monitor mientras no exista un requisito.

El catálogo inicial puede ser una lista instalada en código con `id` estable, título, imagen y ruta a datos existentes. La tarjeta debe derivar masa y geometría de `app/data/aircraft/jensen_ugly_stik_60.json`, no replicarlas. El avión ya declara `openrc-aircraft v1`; los campos siguen siendo trabajo futuro, así que una entrada para el campo actual puede referenciar el constructor vigente sin fabricar un formato ni un instalador de paquetes.

Para «Acerca de», generar al exportar un recurso pequeño de build con versión de producto y revisión/estado de fuente derivados del mismo `git describe` usado por `export.sh`. El ejecutable no necesita Git. La app muestra ese dato y `Engine.get_version_info()` por separado; revisión del avión y esquema de preferencias también son dimensiones separadas. No versionar como app cada dato de vuelo.

## Prueba o spike aún propuesto

Probar instalación limpia (defaults), migración conocida, archivo corrupto conservado, esquema futuro intacto y error de escritura visible. En los tres exports, entrar en pantalla completa y volver por rechazo/timeout sin perder acceso a la ventana; la documentación no garantiza todas las transiciones de escritorio. Comparar la versión de Acerca de, metadata de diagnóstico y ZIP con el recurso generado, y verificar que el binario arranca sin Git. Validar una tarjeta del Ugly Stik contra el JSON fuente. Ninguna de estas pruebas se ejecutó aquí.

**Límite:** las páginas abiertas son documentación Godot 4.7, no ejecución con el motor 4.7.2 fijado. ConfigFile no documenta atomicidad, política de recuperación ni migraciones; la reversión de display, el catálogo y el recurso de build son propuestas que aún requieren spike/export real.
