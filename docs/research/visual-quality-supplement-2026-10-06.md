# Integración de la selección de recursos aportada por el propietario

2026-10-06. Entrada conservada sin cambios: [texto aportado](visual-quality-user-input-2026-10-06.txt). Decisiones aplicadas al [plan visual](../VISUAL-QUALITY-PLAN.md), sin instalar addons ni modificar el juego. Es una revisión documental y de fuentes upstream, no una prueba de compatibilidad en Godot 4.7.2.

El aporte refuerza la reutilización de assets y herramientas de autoría. La primera entrega sigue siendo VQ-01 → L5 → L6: paisaje legible. Reemplazar a la vez terreno, cielo, vegetación y física impediría atribuir el coste o un defecto a un cambio. Las puntuaciones 8/10–10/10 y el tamaño máximo de una herramienta no se convierten en requisitos ni benchmarks.

Integridad de la entrada: copia byte a byte del adjunto; SHA-256 `56493f2b12142e41653616582e32cf7e9d13864275000974b363dfc99483b8c8`. La copia conserva recomendaciones originales; las decisiones vigentes están en este informe y en el plan.

## Resultado por recurso ya investigado

| Recurso | Evidencia contrastada | Integración concreta |
| --- | --- | --- |
| ambientCG | La [licencia oficial](https://docs.ambientcg.com/license/) permite CC0 e incluir archivos crudos en el proyecto | L9/VQ-02: inventario pequeño de hierba, tierra y grava; albedo/normal/roughness a 1K–2K, escala física documentada |
| Poly Haven | [Assets CC0](https://polyhaven.com/license); la licencia de assets no convierte toda la web, logos o renders de usuarios en CC0 | L6/L10: priorizar un asset simple o fuente de bake, no árboles fotogramétricos íntegros; L16: HDRI si el gate pide otro cielo |
| Kenney | [Car Kit](https://kenney.nl/assets/car-kit), ya contrastado en el catálogo inicial | Familia base para props L10 y alternativa acotada de L6a; conservar estilo y dimensiones coherentes |
| Material Maker | [Herramienta de materiales](https://www.materialmaker.org/) y [catálogo previo](visual-quality-tools-2026-10-05.md#material-maker) | Autoría offline cuando falte una superficie; exportar mapas y conservar receta, versión y hashes |
| Terrain3D | La [matriz oficial](https://terrain3d.readthedocs.io/en/stable/docs/platforms.html) declara Compatibility; esto no prueba nuestra app/pin, export ni igualdad de alturas con física | Mantener L18, con criterio explícito de necesidad de esculpir/pintar. Un campo visible a kilómetros no exige por sí solo cambiar de terrain |
| ProtonScatter | El [README](https://github.com/HungryProton/scatter) separa código MIT de texturas demo derivadas de Textures.com; GitHub se identifica como espejo de Codeberg | Candidato de autoría para L6b/L11: exportar posiciones/semilla y probar recarga sin addon. No recalcular árboles durante vuelo ni copiar texturas demo al repo |
| Tree3D/gdTree3D | [Upstream](https://github.com/JekSun97/gdTree3D) documenta GDExtension, Godot 4.5+ desktop y colisiones generadas. [Asset Library](https://godotengine.org/asset-library/asset/3141) enumera 1.0; no confundir ficha con última release | Alternativa futura de generador offline si ez-tree/Kenney no bastan; exigir salida sin clases del addon. Sus colisiones no sustituyen los obstáculos float64 de L14 |
| PhysicalSkyMaterial | [Godot 4.7](https://docs.godotengine.org/en/4.7/classes/class_physicalskymaterial.html) ofrece un material de cielo físico nativo | Referencia A/B de atmósfera bajo la misma luz y exposición; no acredita por sí solo mayor legibilidad ni reemplaza las pruebas L1–L4 |
| Sky3D | [v2.1.0](https://github.com/TokisanGames/Sky3D/blob/v2.1.0/README.md) sí declara Compatibility, con ajustes. Su [shader](https://github.com/TokisanGames/Sky3D/blob/v2.1.0/addons/sky_3d/shaders/SkyMaterial.gdshader) lee `TIME` | Estudio/ensayo de L19, no reemplazo de L1–L4. Adaptar reloj, pausa, sol, exposición y bruma; medir coste y lectura con la misma escena |

ProtonScatter/Tree3D no se añaden ambos para resolver el mismo primer horizonte. El tiempo de autoría también cuenta: registrar minutos para crear, regenerar y exportar un campo frente a nuestro archivo de posiciones. Una salida guardada debe conservar escala, semilla, huecos de pista y límites de sectores.

## Correcciones de licencia y alcance

**Quaternius:** la [QAL v1.0](https://quaternius.com/license.html), fechada 2026-08-28, restringe redistribuir assets por separado; también distingue futuras versiones de archivos obtenidos anteriormente. La página de [Ultimate Nature Pack](https://quaternius.com/packs/ultimatenature.html) todavía muestra CC0. Esa coexistencia obliga a comprobar paquete/versión/archivo, no a declarar todo el catálogo CC0 ni a revocar retroactivamente licencias demostradas. Política del repo: no incorporar paquetes ambiguos; aceptar un archivo CC0 solo con evidencia conservada de esa distribución. Kenney/KayKit son alternativas para la entrega. No se ha descargado ni admitido ningún paquete Quaternius en esta integración.

**Sky3D:** MIT corresponde al código; sus [mapas estelares](https://github.com/TokisanGames/Sky3D/blob/v2.1.0/addons/sky_3d/assets/thirdparty/textures/milkyway/LICENSE.md) llevan atribución CC BY 4.0 de ESO/S. Brunier. El conjunto de recursos del aporte no es universalmente MIT/CC0. Antes de incorporar contenido, guardar licencia por archivo, autor, URL, fecha, revisión/hash y modificaciones, además de llevar el crédito requerido al build.

**Soporte declarado frente a integración:** Sky3D admite Compatibility según su autor; no se descarta por una supuesta ausencia de ese backend. Se pospone porque ya hay cielo comprobado y porque reloj/entorno requieren adaptación. Del mismo modo, tamaño máximo de Terrain3D o generadores con colliders no acredita la física ni el rendimiento del simulador.

## Recursos nuevos y asignación

La [verificación de plugins nuevos](visual-quality-supplement-plugins-2026-10-06.md) detalla Simple Grass Textured, Boujie Water, WaterBox, Road Generator, Procedural Forest Demo, KayKit y Godot Aerodynamic Physics, con sus fuentes y límites.

- L10/L11: KayKit amplía props; Simple Grass Textured se compara contra hierba opaca propia en una escena aislada.
- L6/L8/VQ-07: Procedural Forest Demo sirve de referencia de scattering/LOD; separar sus efectos exclusivos de un backend antes de reutilizar nada.
- L10/L18: Road Generator solo cuando el campo pida una carretera curva o acceso que justifique autoría; exportar geometría estática y excluir carriles IA/colisiones ajenos.
- Campo con agua futuro: Boujie Water es candidato visual; WaterBox es una investigación distinta de flotación. Un shader de lago no implementa hidroaviones.
- Física: Godot Aerodynamic Physics queda como referencia comparativa de conceptos y validación. Su arquitectura no autoriza sustituir nuestro integrador ni mezclar dos fuentes de fuerzas.

## Paquetes de trabajo añadidos a los IDs existentes

1. **L9/VQ-02, selección de superficies:** elegir hasta cuatro familias (hierba, tierra, grava y asfalto solo si un área del campo lo necesita); comparar una a la vez. La pista actual sigue siendo de hierba. Height/displacement no modifica el terreno físico. Registrar tamaño/escala, repetición y aspecto rasante antes de aumentar resolución.
2. **L6/L10, reutilización de assets:** inventario corto de árboles y props; GLB y texturas finales bajo `app/assets/landscape/`, fuentes/procedencia en `assets/landscape/`. Validar una muestra desde clon limpio y export antes de ampliar el lote. Si ya hay un recurso con silueta adecuada, no modelar un sustituto sin necesidad.
3. **Ensayos de herramientas:** elegir una herramienta por problema de autoría y una jornada estimada por ensayo; entregar fuente, versión, salida, coste de edición, capturas y decisión. El resultado del ensayo decide si incorporar la herramienta; no es un requisito adicional para cerrar L6c.
4. **Licencias al incorporar:** aplicar los campos de procedencia también a recursos internos de demos/addons. Quaternius deja de ser fuente CC0 por defecto. Código MIT y assets terceros se revisan por separado.

No se descargaron packs ni se ejecutaron proyectos externos. Los datos de versión son consultas de upstream, no dependencias fijadas del juego. La selección exacta y su checksum se fijan en el paso que incorpore cada archivo.
