# 02 · Recursos de material, caché y datos

Fecha: 2026-10-05. **Pregunta:** ¿cómo compartir materiales de forma segura entre piezas, y hace falta pasar la configuración visual de JSON a un `Resource` tipado?

## Alcance y código observado

Esta nota amplía [09 · Atlas UV](../ugly-stik-visual-investigations/09-materials-atlas.md) con el ciclo de vida de materiales y el límite de formato. En [`ugly_stik_model.gd`](../../../app/aircraft/ugly_stik_model.gd), `material(color)` guarda `StandardMaterial3D` en una caché estática con clave `Color.to_html()`. Se asigna desde `SurfaceTool` y primitivas `BoxMesh`; no se propuso código.

La geometría visual procede de [`geometry.json`](../../../assets/aircraft/ugly-stik-60/geometry.json), compilado a GDScript. Por separado, la física usa JSON `openrc-aircraft v1` con unidad, clase y procedencia; esta propuesta no cambia su formato. Las notas previas ya proponen distinguir materiales por acabado; aquí se documenta el uso compartido y los overrides.

## Hallazgos

`StandardMaterial3D` hereda de `Resource`. Godot conserva recursos cargados por referencia, de modo que editar un material cacheado puede cambiar todas las mallas que lo usan. `duplicate(false)` comparte recursos anidados; `duplicate(true)` copia datos anidados y sólo copia recursos locales. `duplicate_deep()` permite elegir el tratamiento de subrecursos. [`StandardMaterial3D` 4.7](https://docs.godotengine.org/en/4.7/classes/class_standardmaterial3d.html) · [`Resource` 4.7](https://docs.godotengine.org/en/4.7/classes/class_resource.html) · [Recursos 4.7](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html)

`resource_local_to_scene` actúa al instanciar `PackedScene`; no debe asumirse como aislamiento automático de materiales que este builder construye y cachea directamente. [`Resource` 4.7](https://docs.godotengine.org/en/4.7/classes/class_resource.html).

El material de superficie vive en la malla; `set_surface_override_material()` asigna uno para esa instancia. El `material_override` de `GeometryInstance3D` se aplica a todas las superficies y puede ocultar la selección de un `ArrayMesh` con acabados distintos. [`MeshInstance3D` 4.7](https://docs.godotengine.org/en/4.7/classes/class_meshinstance3d.html)

Un `Resource` personalizado ofrece propiedades declaradas, serialización `.tres` y edición en Inspector. JSON se convierte en `Variant`/`Dictionary`; el llamador valida claves y tipos. JSON es accesible fuera de Godot; `.tres` facilita edición guiada, pero guarda la ruta del script y ata el dato a esa clase. [`JSON` 4.7](https://docs.godotengine.org/en/4.7/classes/class_json.html) · [Recursos 4.7](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html)

## Decisión y prueba propuesta

Adoptar una caché por perfil visual y tratar los materiales cacheados como inmutables. Usar materiales por superficie; reservar el override global para reemplazar todo el aspecto de una instancia. Duplicar sólo si una pieza necesita una variación propia.

Conservar JSON para cotas con unidades/procedencia y la primera ficha visual; diferir `.tres` tipado hasta que sea necesario editar perfiles desde Inspector. Probar dos modelos con perfiles compartidos, modificar una copia y comparar asignación por superficie con override global. No se propone dependencia externa; API consultada en docs 4.7 para el motor fijado en 4.7.2-stable.
