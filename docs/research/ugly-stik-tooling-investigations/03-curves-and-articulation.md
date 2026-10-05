# 03 · Curvas, pivotes y geometría articulada

Fecha: 2026-10-05. **Pregunta:** ¿qué geometría visual conviene mover con `Node3D`, qué se beneficia de `Curve3D`, y cuándo tendría sentido una malla dinámica o un esqueleto?

## Alcance y código observado

Esta nota complementa [07 · Transmisiones](../ugly-stik-visual-investigations/07-control-linkages.md) y [10 · Lectura y coste](../ugly-stik-visual-investigations/10-readability-performance.md). El modelo crea pivotes `*_hinge` locales; el adaptador aplica ángulos. Las varillas rectas son cilindros orientados entre extremos. No se usa `Curve3D`, `Skeleton3D` ni plugin IK. El repo fija Godot 4.7.2-stable; no se ejecutó prototipo.

## Hallazgos y decisión

`position`, `rotation` y `scale` de `Node3D` son relativos al padre. Los puntos de bisagra del alerón pertenecen al marco local de ala, mientras que medidas de escena pueden estar en mundo. Convertir ambos extremos al mismo espacio antes de hallar centro, longitud y orientación evita desplazamientos al girar el ala. Los pivotes existentes bastan para superficies rígidas controladas por el adaptador. [`Node3D` 4.7](https://docs.godotengine.org/en/4.7/classes/class_node3d.html)

`Curve3D` almacena puntos en su espacio local y ofrece `sample_baked()` por distancia; `bake_interval` controla densidad y memoria. `sample_baked_with_rotation()` usa X lateral, Y arriba y Z adelante. Una curva de longitud cero no tiene orientación válida; sin vectores arriba, el método informa error y devuelve Y global. `PathFollow3D` advierte que pocos puntos cacheados pueden perder giros cerrados. Esto importa para mangueras, cables y bandas curvas. [`Curve3D` 4.7](https://docs.godotengine.org/en/4.7/classes/class_curve3d.html) · [`PathFollow3D` 4.7](https://docs.godotengine.org/en/4.7/classes/class_pathfollow3d.html)

`Curve3D` describe la trayectoria, pero no genera un tubo visible. Una banda o tubo barre una sección 2D por los puntos y asigna normales. Si cambia la ruta y se conserva el número/orden de vértices, `ArrayMesh` acepta `ARRAY_FLAG_USE_DYNAMIC_UPDATE` y `surface_update_vertex_region()`. Se deben respetar stride y offsets en bytes y recalcular normales si cambia la curvatura; cambios de topología requieren reconstrucción. [`ArrayMesh` 4.7](https://docs.godotengine.org/en/4.7/classes/class_arraymesh.html)

Para varillas rígidas, usar nodos/mallas creados una vez y actualizados desde sus extremos. Mantener mangueras y bandas estáticas al inicio; introducir `Curve3D` si simplifica su edición o movimiento. Diferir buffers dinámicos hasta que el barrido de poses lo justifique. No incorporar `Skeleton3D`/IK: es una jerarquía de huesos para animar una malla, innecesaria para pivotes y varillas rígidas. [`Skeleton3D` 4.7](https://docs.godotengine.org/en/4.7/classes/class_skeleton3d.html)

## Prueba propuesta para US-V04/V06

En una pieza de prueba, barrer una bisagra y verificar que la varilla conserve longitud usando puntos locales y globales. Añadir manguera y banda en curva cerrada; inspeccionar torsión, unión final y resolución en giros. Si una curva animada necesita malla variable, medir actualización de superficie fija frente a reconstrucción. Sólo se usan API nativas.
