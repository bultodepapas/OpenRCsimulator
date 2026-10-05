# 01 · Contornos 2D y construcción de malla

Fecha: 2026-10-05. **Pregunta:** ¿qué parte del festoneado del borde de salida conviene resolver con `Geometry2D`, y qué parte debe seguir en el constructor `SurfaceTool`/`ArrayMesh`?

## Alcance y código observado

Esta nota amplía la investigación [09 · Atlas UV](../ugly-stik-visual-investigations/09-materials-atlas.md): trata topología, índices y normales; no vuelve a evaluar atlas ni filtros. Se revisó [`ugly_stik_model.gd`](../../../app/aircraft/ugly_stik_model.gd). El proyecto fija Godot **4.7.2-stable**; las referencias de API son de la documentación 4.7. No se ejecutó un prototipo con el binario fijado.

El constructor ya usa `Geometry2D.triangulate_polygon()` para tapar las secciones de alas y prismas, y `clip_polygons()` para retirar la entalladura del elevador. Después convierte índices o contornos 2D a vértices 3D, orienta triángulos y crea caras laterales. La piel del fuselaje y los paneles alares se construye en cambio con quads propios sobre estaciones; `_wing_quad()` y `_section_normal()` mantienen normales elegidas por cara y sección. La llamada actual a `SurfaceTool` no crea una lista de índices compartidos.

## Hallazgos y decisión

`triangulate_polygon()` devuelve tripletas de índices hacia el contorno de entrada, siempre con salida antihoraria; si no puede triangularlo, devuelve una lista vacía. Sirve para rellenar perfiles cóncavos sencillos y se debe conservar la comprobación de fallo que ya hace `_prism()`. No sustituye la construcción de una piel alar: sólo entrega triángulos de una región plana, no el espesor, los lados ni sus normales. [`Geometry2D` 4.7](https://docs.godotengine.org/en/4.7/classes/class_geometry2d.html)

`clip_polygons()` calcula diferencia y puede devolver varios contornos. Si el recorte deja un hueco cerrado, devuelve borde exterior e interior; no los convierte en una tapa 3D. En el caso actual, la entalladura llega al borde posterior y separa el elevador en piezas. `_elevator_mesh()` extruye cada contorno por separado, solución adecuada a ese corte abierto. **Inferencia del código:** reutilizar ese bucle para un agujero cerrado taparía también el interior. Habría que conservar y tratar la orientación de los huecos o dividir el contorno antes de extruirlo. [`Geometry2D` 4.7](https://docs.godotengine.org/en/4.7/classes/class_geometry2d.html)

Para el festoneado, conviene conservar el loft de secciones y añadir estaciones spanwise explícitas que definan picos y valles del borde. `Geometry2D` puede ayudar con un contorno plano de panel o un recorte abierto, pero no es el generador de la piel. Esto mantiene control de espesor, cierre y normales; el coste será más quads y triángulos según el muestreo, a medir en una sola semiala.

`SurfaceTool` exige fijar UV, normal y demás atributos antes de cada `add_vertex()`. `index()` puede reducir vértices repetidos, pero sólo son intercambiables los que compartan sus atributos; una costura UV o una arista con normal distinta necesita vértices separados. `generate_normals()` suaviza por grupo —grupo 0 por defecto—, mientras el constructor actual asigna normales a mano. Por tanto, probar índices en un perfil plano repetido, sin reemplazar de entrada sus normales explícitas. [`SurfaceTool` 4.7](https://docs.godotengine.org/en/4.7/classes/class_surfacetool.html) · [`ArrayMesh` 4.7](https://docs.godotengine.org/en/4.7/classes/class_arraymesh.html)

## Prueba propuesta para US-V02

Crear una pieza aislada con perfil cóncavo, un recorte abierto y otro cerrado; comparar triangulación, capado, normales de borde y silueta antes de aplicarla al ala. Añadir una tira festoneada de un solo vano al modelo de prueba, conservando bisagra y holgura. Registrar vértices, triángulos y captura oblicua. El código no depende de bibliotecas externas; todo lo citado es API nativa de Godot.

**Decisión nueva:** Geometry2D ya es una herramienta localizada para perfiles/cortes planos; el festón del ala debe integrarse en las estaciones del loft. El ensayo de costuras/indexado determina si `SurfaceTool.index()` aporta algo sin cambiar el sombreado.
