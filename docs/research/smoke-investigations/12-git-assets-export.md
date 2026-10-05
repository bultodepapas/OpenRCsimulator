# 12 · Git, procedencia de recursos e importación reproducible

**Investigado:** 2026-10-05. **Pregunta:** ¿cómo investigar repositorios y producir texturas/escenas de humo sin crear dependencias ocultas, conflictos con otros desarrolladores o exportaciones incompletas? **Evidencia:** guías oficiales y lectura del repositorio; no se alteró su configuración de Git/CI.

## Hechos útiles de las guías

- [`git worktree`](https://git-scm.com/docs/git-worktree) permite directorios de trabajo separados que comparten repositorio. Sirve para experimentar con una rama/commit sin modificar los archivos del checkout de otros desarrolladores. Un worktree no contiene automáticamente sus cambios sin confirmar.
- [Atributos Git](https://git-scm.com/docs/gitattributes) permiten declarar archivos binarios y controlar el tratamiento de texto. No aportan un merge semántico de imágenes: regenerar una máscara desde su fuente es más fiable que intentar fusionar PNG.
- [Control de versiones en Godot](https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html) y [proceso de importación](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/import_process.html) distinguen fuentes/configuración de importación y caché generada. Versionar los `.import` junto a imágenes cuando existan; `.godot/` se reconstruye.
- [Git LFS](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-git-large-file-storage) guarda referencias en Git y contenido fuera. Añade una condición de descarga al clon/build. No hace falta para unas máscaras pequeñas; reconsiderarlo si se decide conservar bakes volumétricos grandes.
- [Exportación Godot](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html#resource-options) separa recursos y filtros de otros archivos. Un JSON consultado por ruta requiere comprobar inclusión; no asumir que se exporta por estar junto a una textura.

## Auditoría local

[`.gitignore`](../../../.gitignore) ya excluye `.godot/`, `.tools/` y `app/captures/`. [`export.sh`](../../../app/export.sh) ya importa antes de exportar. Los presets incluyen `data/*.json`; evitar añadir un perfil visual JSON fuera de esa convención sin comprobar el paquete. El plan actual con perfiles GDScript o recursos `.tres` referenciados evita una ruta de carga extra.

Hay varios frentes activos —modelo, paisaje, menú, viento y Extra— y `docs/SMOKE-PLAN.md` todavía no equivale a un commit de implementación. Una prueba en worktree de HEAD necesita aplicar los cambios concretos del efecto, o no estará probando ese trabajo. Registrar siempre commit base y diff/estado probado.

## Procedencia propuesta para humo

Cada recurso externo que se decida incorporar llevará un registro pequeño:

```text
id, upstream_url, upstream_commit_or_release, source_path,
license_identifier, license_path, copyright_notice,
download_sha256, local_output, modifications, generator_version
```

Este esquema es una propuesta del proyecto. Un README con licencia MIT del código no certifica automáticamente cada textura de ejemplo del repositorio. Revisar el archivo o pack exacto. Si no se puede establecer permiso del recurso, conservar el enlace como referencia visual y generar una máscara propia.

**Ruta simple:** parámetros semilla/tamaño de ruido en fuente versionada y máscara PNG pequeña si se decide precalcular. Mantener mismo alpha/canal de color y opciones de mipmaps entre editor y export; la [investigación de autoría](06-authoring-textures.md) define esas opciones. Si se usa Blender o Material Maker fuera del juego, registrar versión y fuente del generador; no convertirlos en dependencias del jugador ni hacer que el export dependa del editor instalado.

Los repositorios candidatos se consultan por licencia y capacidad primero. Antes de copiar código, fijar commit y revisar el subset necesario. No añadir un submódulo o gestor de addons para reutilizar una única textura o una idea de shader.

## Flujo Git recomendado

1. Mantener experimentos en `research/smoke/` o un worktree aislado; scripts incompletos nunca entran en `app/`, donde la suite parsea todo.
2. Un commit por paso SM; preparar solamente los paths del efecto y sus pruebas. Evitar staging global del trabajo de otros frentes.
3. Fuente, parámetros de importación y prueba en el mismo cambio; capturas grandes como artefactos y resumen de resultados en docs.
4. Para la prueba de distribución, usar un clon nuevo del commit que contiene el cambio, importar desde cero y abrir el paquete exportado con render real. Comprobar ambos perfiles y la parada de la bomba.
5. Si cambian rutas, buscar todas sus referencias; si cambian ignore/export/generados, repetir el clon limpio. No tomar `act` con carpetas locales presentes como sustituto.

## Cambio concreto al plan y evidencia pendiente

**SM-08** exige un manifest de procedencia y una prueba visual del paquete, además de la traza headless ya existente. Se conservan herramientas Git nativas; no se instala Git LFS ni un addon de gestión por anticipado. La configuración de CI actual queda intacta hasta que haya un efecto y una prueba que integrar.

**Pendiente:** recurso final, su licencia si es externo, reproductibilidad de su generador y funcionamiento real en exportaciones Windows/macOS. Esta investigación no afirma haber hecho un clon/export del humo, porque aún no está implementado.
