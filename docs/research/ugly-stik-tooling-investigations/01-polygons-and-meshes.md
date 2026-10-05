# 01 · Contornos 2D y construcción de malla

Fecha: 2026-10-05. **Pregunta:** ¿qué parte del festoneado del borde de salida conviene resolver con `Geometry2D`, y qué parte debe seguir en el constructor `SurfaceTool`/`ArrayMesh`?

## Alcance y código observado

Esta nota amplía [09 · Atlas UV](../ugly-stik-visual-investigations/09-materials-atlas.md) con topología, índices y normales. Se revisó [`ugly_stik_model.gd`](../../../app/aircraft/ugly_stik_model.gd). El proyecto fija Godot **4.7.2-stable**; las referencias son de la documentación 4.7. No se ejecutó el binario fijado.

El constructor usa `Geometry2D.triangulate_polygon()` para tapar secciones de alas y prismas, y `clip_polygons()` para la entalladura del elevador. Convierte esos resultados 2D a vértices 3D y crea los lados. La piel de fuselaje y alas se construye con quads sobre estaciones; `_wing_quad()` y `_section_normal()` definen sus normales.

## Hallazgos y decisión

`triangulate_polygon()` devuelve tripletas de índices hacia el contorno de entrada, con salida antihoraria; si falla, devuelve vacío. Sirve para rellenar perfiles cóncavos y se debe conservar la comprobación que ya hace `_prism()`. No sustituye la piel alar: sólo triangula una región plana, sin espesor, lados ni normales. [`Geometry2D` 4.7](https://docs.godotengine.org/en/4.7/classes/class_geometry2d.html)

`clip_polygons()` calcula diferencia y puede devolver varios contornos. Un hueco cerrado produce borde exterior e interior, que la función no convierte en una tapa 3D. Hoy la entalladura llega al borde posterior y separa el elevador en piezas; `_elevator_mesh()` extruye cada contorno, adecuado para ese corte. **Inferencia del código:** repetirlo para un agujero cerrado taparía también el interior. Se debe tratar la orientación del hueco o dividir el contorno antes de extruir. [`Geometry2D` 4.7](https://docs.godotengine.org/en/4.7/classes/class_geometry2d.html)

Para el festoneado, conservar el loft y añadir estaciones explícitas que definan picos y valles del borde. `Geometry2D` puede recortar el contorno plano, pero no genera la piel. El loft conserva control de espesor y normales, a cambio de más quads según el muestreo.

`SurfaceTool` exige fijar atributos antes de cada `add_vertex()`. `index()` puede reducir vértices repetidos, pero costuras UV y aristas con distintas normales necesitan vértices separados. `generate_normals()` suaviza por grupo (0 por defecto); el constructor actual asigna normales a mano. Probar el indexado en un perfil plano repetido sin retirar esas normales. [`SurfaceTool` 4.7](https://docs.godotengine.org/en/4.7/classes/class_surfacetool.html) · [`ArrayMesh` 4.7](https://docs.godotengine.org/en/4.7/classes/class_arraymesh.html)

## Prueba propuesta para US-V02

Crear una pieza de prueba con perfil cóncavo y recortes abierto/cerrado; comparar tapas, normales y silueta. Añadir una tira festoneada de un vano, conservando bisagra y holgura. Registrar vértices, triángulos y captura oblicua. Todo lo citado es API nativa.

**Decisión nueva:** Geometry2D ya es una herramienta localizada para perfiles/cortes planos; el festón del ala debe integrarse en las estaciones del loft. El ensayo de costuras/indexado determina si `SurfaceTool.index()` aporta algo sin cambiar el sombreado.
