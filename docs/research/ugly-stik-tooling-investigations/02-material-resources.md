# 02 · Recursos de material, caché y datos

Fecha: 2026-10-05. **Pregunta:** ¿cómo compartir materiales de forma segura entre piezas, y hace falta pasar la configuración visual de JSON a un `Resource` tipado?

## Alcance y código observado

Esta investigación complementa la decisión de acabado de [09 · Atlas UV](../ugly-stik-visual-investigations/09-materials-atlas.md): concreta el ciclo de vida de los materiales y el límite de formato. En [`ugly_stik_model.gd`](../../../app/aircraft/ugly_stik_model.gd), `material(color)` guarda `StandardMaterial3D` en un diccionario estático cuya clave es `Color.to_html()`. El builder asigna ese material desde `SurfaceTool.set_material()` y desde primitivas como `BoxMesh.material`. No se revisó ni propuso un cambio de código.

El proyecto guarda datos de avión validados en JSON `openrc-aircraft v1`; cada valor incluye unidad, clase y procedencia. Se mantiene esa función de evidencia separada del modelo visual. Las notas previas ya proponen distinguir materiales por acabado además del color; este informe añade el comportamiento de recursos compartidos y las consecuencias de usar un override.

## Hallazgos

`StandardMaterial3D` hereda de `Resource`. Godot carga y conserva recursos por referencia; volver a cargar el mismo recurso devuelve la instancia en caché. Por ello, modificar un material recuperado del diccionario estático puede cambiar todas las mallas que lo comparten. Es útil para una paleta pequeña e inmutable, pero riesgoso para retoques por pieza o por ejemplar. `Resource.duplicate(false)` no duplica recursos anidados; `duplicate(true)` duplica datos anidados y sólo duplica recursos locales, mientras `duplicate_deep()` ofrece control explícito sobre subrecursos. [`StandardMaterial3D` 4.7](https://docs.godotengine.org/en/4.7/classes/class_standardmaterial3d.html) · [`Resource` 4.7](https://docs.godotengine.org/en/4.7/classes/class_resource.html) · [Recursos 4.7](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html)

Hay tres ámbitos de asignación. El material de una superficie vive en la malla; `set_surface_override_material()` asocia el override con esa instancia; el `material_override` de `GeometryInstance3D` se aplica a todas las superficies de ese nodo. Si un `ArrayMesh` combina arriba, abajo y tapas con materiales distintos, el override global oculta esa selección. [`MeshInstance3D` 4.7](https://docs.godotengine.org/en/4.7/classes/class_meshinstance3d.html)

Un `Resource` personalizado aporta propiedades declaradas, serialización `.tres` y edición en Inspector. JSON se parsea como `Variant`/`Dictionary`; el llamador valida las claves y los tipos esperados. JSON es más fácil de inspeccionar y consumir fuera de Godot, mientras que `.tres` facilita edición guiada dentro del editor. Los archivos `.tres` de recursos personalizados guardan la ruta del script, así que la clase y su ubicación pasan a formar parte del formato del proyecto. [`JSON` 4.7](https://docs.godotengine.org/en/4.7/classes/class_json.html) · [Recursos 4.7](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html)

## Decisión y prueba propuesta

Adoptar una caché por nombre de perfil visual —por ejemplo, piel, metal mate o goma— y tratar los recursos cacheados como compartidos e inmutables tras su construcción. Usar material por superficie para conservar varios acabados en una malla; reservar el override global para inspecciones que quieran reemplazar deliberadamente todo el aspecto. Duplicar un material sólo cuando una pieza necesite una variación propia.

Conservar JSON para las cotas con unidades/procedencia y para la primera ficha visual versionable; no migrar el cargador ni introducir clases de datos nuevas en esta etapa. Diferir un `.tres` tipado hasta que haya una necesidad concreta de editar muchos perfiles desde Inspector. Una prueba pequeña debe instanciar dos modelos con perfiles compartidos, cambiar una copia duplicada y comparar asignación por superficie con override global. No se propone dependencia externa ni cambio de formato; el motor del proyecto es 4.7.2-stable y la consulta de API usó documentación 4.7.
