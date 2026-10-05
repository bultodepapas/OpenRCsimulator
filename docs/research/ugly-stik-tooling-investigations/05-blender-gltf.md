# 05 · Blender como autoría opcional y GLB de intercambio

2026-10-05 · Investigación documental; no se exportó ni importó un modelo nuevo. Aplica como opción futura de US-V.

## Pregunta y estado local

¿Cuándo conviene sumar Blender sin desplazar innecesariamente el constructor? Hoy [el modelo](../../../app/aircraft/ugly_stik_model.gd) se crea en GDScript con primitivas y `SurfaceTool`; [el adaptador](../../../app/render/airplane.gd) expone `airplane`, `propeller` y nodos de bisagra para la simulación. El estudio previo ya importó un GLB sintético y verificó jerarquía, medidas y giro de pivote en Godot 4.7.2; ese resultado prueba el contrato mínimo, no fidelidad de una malla real. [Roundtrip GLB previo](../ugly-stik-investigations/09-export.md).

## Hallazgos para el contrato

Godot puede importar `.blend` llamando al exportador glTF de Blender, pero requiere que Blender esté instalado; la misma documentación prefiere exportar glTF/GLB si el flujo directo da problemas. GLB reúne malla y texturas en un archivo binario portable y permite inspeccionar y validar el artefacto entregado. Blender se distribuye bajo GPL; Godot está bajo MIT. La licencia del programa autor no determina por sí sola la licencia de los modelos creados con él. [Formatos 3D Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html) · [licencias Blender](https://www.blender.org/about/license/) · [licencia Godot](https://docs.godotengine.org/en/4.7/about/complying_with_licenses.html).

El exportador glTF de Blender documenta +Y arriba, normales, UV y tangentes como atributos exportables. También permite aplanar la jerarquía: esa opción deja solo mallas skinned como hijas del armature, así que sería incompatible con nodos de control rígidos si se activa. Los orígenes de objeto definen el punto de rotación; para elevador y timón deben colocarse en la bisagra y permanecer como transformaciones del nodo, con la malla hija desplazada hacia el borde de salida. Godot documenta activos con morro +Z y derecha −X; la conversión `Rᵧ(π)` del fixture actual a ejes de simulación debe seguir aplicándose una sola vez en la raíz, no hornearse en cada panel. [Exportador glTF Blender 5.0](https://docs.blender.org/manual/en/5.0/addons/import_export/scene_gltf2.html) · [convenciones Godot](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/model_export_considerations.html).

## Decisión y prueba propuesta

**Conservar el constructor nativo como producción.** Si una pieza resulta más fácil de modelar en DCC, mantener `.blend` como fuente humana y producir un GLB explícito como entrada revisable; no usar la importación transparente `.blend` como requisito para todos los colaboradores. La versión de Blender/exportador queda pendiente de pin mientras esta ruta siga aplazada.

Comando de exportación propuesto, no ejecutado:

```sh
blender --background source.blend --python export_glb.py -- build/hinge.glb
```

El script llamaría `bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_yup=True, export_hierarchy_flatten_objs=False, export_normals=True, export_tangents=False)`. Mantener triangulación y escala coherentes, no aplanar ni unir `airplane → elevator_hinge → elevator`, y dejar tangentes apagadas mientras no haya mapa normal. Microfixture: ala corta y elevador separado, pivote en el borde de ataque y probes de morro/derecha; verificar en Godot nombres únicos, parentesco, AABB, escala, normales/sombreado y giro ±30° tras conversión de raíz. El resultado sintético ya existente puede ampliarse para esta comprobación, sin afirmar que valida las alas CAD reales.
