# Skills de Godot seleccionadas

Fecha de revisión: 2026-10-05 (America/Bogota). Instalación solicitada por el usuario a partir de su lista de candidatos. Es una tarea de herramientas de desarrollo, sin avance de un paso funcional del ROADMAP.

Instaladas a nivel de usuario en `~/.codex/skills/`; estarán disponibles desde el siguiente turno. No forman parte del juego ni de sus dependencias de ejecución. Los paquetes se conservaron sin modificaciones, fijados a los commits del [registro de instalación](godot-skills-installation.json).

| Skill | Utilidad en OpenRC | Fuente fijada |
| --- | --- | --- |
| `godot` | Inspección de escenas, consulta de API del motor instalado, herramientas de diagnóstico y edición de recursos | [haxqer/godot-skill](https://github.com/haxqer/godot-skill/tree/037c03e9858ae748bf66c010aeb9942dbe9b93d6/skill/godot) |
| `godot-3d-lighting` | Sol, sombras, ambiente y alternativas de iluminación para Compatibility | [GD-Agentic-Skills](https://github.com/thedivergentai/gd-agentic-skills/tree/4c4d0ff5c4597938cc9257d99d9e35f7692c9c06/skills/godot-3d-lighting) |
| `godot-3d-materials` | Superficies del avión, transparencia de cabinas, texturas PBR y materiales compartidos | [GD-Agentic-Skills](https://github.com/thedivergentai/gd-agentic-skills/tree/4c4d0ff5c4597938cc9257d99d9e35f7692c9c06/skills/godot-3d-materials) |
| `godot-debugging-profiling` | Diagnóstico de objetos huérfanos, memoria, tiempos y errores de ejecución | [GD-Agentic-Skills](https://github.com/thedivergentai/gd-agentic-skills/tree/4c4d0ff5c4597938cc9257d99d9e35f7692c9c06/skills/godot-debugging-profiling) |
| `godot-gdscript-headless-testing` | Runners SceneTree, códigos de salida, importación inicial y prevención de bloqueos en CI | [gamedev-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/tree/d4b0e35550c55ae70bdfcab4ef5a0e94610438a9/skills/godot/godot-gdscript-headless-testing) |
| `godot-shaders` | Shaders spatial/canvas, uniforms y migración de sintaxis | [gamedev-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/tree/d4b0e35550c55ae70bdfcab4ef5a0e94610438a9/skills/godot/godot-shaders) |

## Encaje y límites observados

- Las reglas de `AGENTS.md` y el stack del proyecto prevalecen: motor de `app/get-godot.sh`, renderizador Compatibility y dinámica propia con floats de 64 bits. Las recetas de RigidBody3D o Vector3 no sustituyen el núcleo de vuelo.
- Los datos aerodinámicos continúan en JSON con unidades y procedencia. Los ejemplos de Resources no justifican migrar ese contrato.
- Las referencias de iluminación y materiales también incluyen técnicas de Forward+. Su instalación no demuestra que todas sus recetas funcionen en Compatibility; comprobar las capacidades con el motor fijado antes de aplicar cada efecto.
- La skill base incluye plantillas y un runner de pruebas propio. El proyecto ya tiene arquitectura, estilo visual y `app/test.sh`: conservarlos, sin inicializar otra estructura ni otro framework por defecto.
- Los ejemplos y afirmaciones de los autores son orientación, no evidencia de aerodinámica ni validación local de cada API. En particular, la guía de profiling menciona `--release`: comprobar los flags reales del binario antes de usarlo; las medidas de rendimiento deben identificar el tipo de build.
- Los scripts auxiliares permanecen fuera de `app/`. Cualquier fragmento que se incorpore al juego requiere revisión y las comprobaciones del proyecto.

## Opciones aplazadas

- `godot-input-handling`: su instrucción de no usar ejes crudos sin zona muerta radial encaja con sticks de gamepad, pero contradice la lectura de canales independientes de la emisora RC. No se instaló.
- Skills de física general: no aportan un modelo aerodinámico validado y se centran en los cuerpos físicos del motor.
- `godot-3d-world-building`: el contenido revisado se centra en GridMap, CSG y navegación. Menor prioridad que materiales e iluminación para el campo actual.
- `godot-performance-optimization`: solapa parte del diagnóstico elegido; se puede añadir cuando una medida concreta justifique sus patrones.
- `godot-master` y routers completos: ampliarían innecesariamente la selección a géneros y especialidades ajenos al simulador.
- Las alternativas de alexmeckes y shihabshahrier quedaron fuera de esta instalación por solapamiento con la base seleccionada; no se auditó su contenido en esta pasada.
- `gda` quedó pendiente de evaluación separada. No se instaló CLI, MCP ni puente al editor; la petición era instalar skills y el repo ya dispone de capturas, trazas y pruebas.

## Comprobación y reproducción

El instalador oficial `skill-installer/scripts/install-skill-from-github.py` instaló seis directorios con `--ref` fijado al commit completo. Se verificaron los 238 archivos contra los hashes de blobs del árbol Git de cada origen, los seis nombres del frontmatter y la existencia de todos los enlaces Markdown relativos en sus `SKILL.md`. Los 17 archivos Python de la skill base pasaron análisis sintáctico con `ast.parse`.

Esta comprobación valida la integridad de la instalación, no la ejecución de todos sus ejemplos. No se modificó `app/` ni se ejecutó la suite del simulador para esta instalación.

Para reproducir cada entrada del registro:

```bash
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo OWNER/REPO --ref COMMIT_COMPLETO --path RUTA_DE_SKILL
```

El instalador rechaza destinos ya existentes. El registro incluye commit, ruta, SHA-256 de `SKILL.md` y huella del conjunto: SHA-256 del JSON de un mapa ordenado de ruta relativa a SHA-256 de archivo, serializado con `json.dumps(checks, sort_keys=True)` de Python.
