# 07 · Auditoría topológica de mallas con trimesh

2026-10-05 · **Pregunta:** ¿aporta una biblioteca Python una comprobación independiente y útil de la geometría del Ugly Stik?

## Evidencia local

El actual [`model_clearance.gd`](../../../app/aircraft/model_clearance.gd) ya revisa triángulos transformados, distancia de superficies y penetración mediante puntos interiores en una rejilla de 1 mm. [`verify_model.gd`](../../../app/aircraft/verify_model.gd) integra ese análisis con poses de elevador, timón y alerones. El informe v3 registra 99 pares/poses de cola y 30 de ala, además de un cubo contenido de control; sus límites reconocen resolución de muestreo y cobertura discreta de ángulos ([informe](../ugly-stik-model-v3-installation.md)).

## Hallazgos

`trimesh.Trimesh.is_watertight` verifica que cada arista pertenezca a dos caras; `is_winding_consistent` comprueba sentidos opuestos en aristas compartidas, e `is_volume` exige además normales dirigidas hacia fuera. `volume` no es fiable si la malla no es estanca. Estas propiedades ofrecen un auditor compacto para componentes que sí representan sólidos cerrados, pero no son un sustituto del barrido de holguras articuladas. [`trimesh 5.1.1: API`](https://trimesh.org/trimesh.html) · [`trimesh 5.1.1: instalación y dependencias opcionales`](https://trimesh.org/install.html)

La instalación mínima requiere NumPy. SciPy aporta, entre otras funciones, `cKDTree` y consultas cercanas rápidas; `rtree` acelera ciertas búsquedas espaciales y la fase amplia de rayos; `python-fcl` habilita las consultas de colisión entre mallas de `CollisionManager`. No hace falta añadirlas para solo preguntar si una malla está cerrada y orientada. `CollisionManager` calcula colisiones, contactos y distancias con FCL, pero no cubre el contrato actual de poses, uniones estructurales permitidas ni su fixture de contención. [`dependencias opcionales`](https://trimesh.org/install.html#dependency-overview) · [`API de colisiones`](https://trimesh.org/trimesh.collision.html)

La conversión es una condición de validez: el verificador actual lee `Mesh.get_faces()`, una lista de posiciones trianguladas; esa representación no conserva por sí sola las aristas indexadas. Godot también permite arrays de vértices e índices por superficie. Para auditar cierre topológico, exportar esos índices y transformaciones, o soldar vértices duplicados por UV/normales con una regla y tolerancia documentadas; validar por separado superficies intencionalmente abiertas. [Godot 4.7 `Mesh`](https://docs.godotengine.org/en/4.7/classes/class_mesh.html) · [implementación local](../../../app/aircraft/model_clearance.gd)

## Decisión y verificación pendiente

**Adoptar trimesh solo como auditor offline opcional** al cerrar US-V02/V04, sin cambiar el clearancer GDScript. La versión consultada y candidata es `trimesh==5.1.1` (PyPI: 2026-10-02), licencia MIT; requiere Python ≥3.10 y NumPy. El inventario local indica que trimesh no está instalado y el repositorio no fija dependencias Python. [`release 5.1.1`](https://pypi.org/project/trimesh/5.1.1/) · [`licencia MIT`](https://github.com/mikedh/trimesh/blob/5.1.1/LICENSE.md). Antes de incorporarlo, fijar también NumPy en un entorno de herramientas aislado. **No instalado ni verificado con las mallas actuales.**

**Comprobación propuesta, no ejecutada:** exportar un sólido cerrado conservando índices, comprobar `is_volume`, luego contrastar el fixture de cubo contenido y una pose con interferencia contra el JSON actual de clearance. Registrar unidades, ejes, transformación y nombres de cada componente para no confundir fallos de exportación con defectos geométricos. El volumen de la piel exterior no determina masa ni inercia de un avión hueco.
