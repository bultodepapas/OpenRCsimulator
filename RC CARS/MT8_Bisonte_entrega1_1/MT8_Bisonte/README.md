# Bisonte MT8 — blockout articulado (entrega 1)

Monster truck RC eléctrico ~1/8 para OpenRC Simulator, inspirado en el T-Maxx 3.3.
Marco Godot: +X derecha, +Y arriba, −Z adelante. Unidades: metros.
Origen: plano de simetría, mitad de la batalla, cara inferior de las placas del chasis (0,125 m sobre el suelo en pose de diseño).

## Archivos

| Archivo | Qué es |
| --- | --- |
| `out/MT8_Bisonte.blend` | Escena editable (Blender 5.2.2 LTS), colecciones por pieza y esquina |
| `out/MT8_Bisonte.glb` | Exportación glTF binaria para Godot 4.7.2 (renderer Compatibility) |
| `out/mt8_spec.json` | Dimensiones, pivotes, límites, proxies de colisión y recuento de triángulos |
| `out/interference_report.json` | Resultado del chequeo de interferencias (27 poses extremas) |
| `out/gltf_export_settings.json` | Ajustes exactos del exportador glTF |
| `out/renders/*.png` | Capturas: vistas, bajos, extremos de suspensión y dirección, volcado, proxies |
| `godot/mt8_rig.gd` | Rig visual de referencia (GDScript, `@tool`): recorrido, dirección y giro por rueda |
| `godot/test_mt8.gd` | Verificación automática tras importar (24 comprobaciones) |
| `mt8_spec.py` | Fuente única de medidas y cinemática |
| `build_mt8.py`, `mt8_geo.py` | Construcción del modelo y exportación |
| `mt8_pose.py`, `check_mt8.py`, `render_mt8.py` | Pose en Blender, chequeo de interferencias y capturas |
| `gen_rig_gd.py` | Genera `godot/mt8_rig.gd` a partir de `mt8_spec.py` |

## Reproducir

```bash
pip install bpy==5.2.2          # Blender 5.2.2 LTS como módulo (Python 3.13)
python3 build_mt8.py            # .blend, .glb, mt8_spec.json
python3 check_mt8.py            # interferencias
python3 render_mt8.py           # capturas (Cycles CPU)
python3 gen_rig_gd.py           # godot/mt8_rig.gd
cp out/MT8_Bisonte.glb out/mt8_spec.json godot/
godot --headless --path godot --import
godot --headless --path godot -s test_mt8.gd
```

## Usar el rig en Godot

Crea un `Node3D` con `mt8_rig.gd`, instancia `MT8_Bisonte.glb` como hijo y ajusta `root_path` a `MT8_Bisonte/MT8_Root`.
Desde el simulador: `set_travel("FL", t)` (m, + = compresión, de −0,070 a +0,050), `set_steer(delta)` (rad, + = izquierda, ±30°), `set_spin("FL", a)` (rad sobre +X; avanzar = ángulo decreciente).

Aviso: `VehicleBody3D` de Godot avanza hacia +Z; este modelo mira hacia −Z.
Evita nombres de nodo terminados en `-wheel`/`_wheel`, `-col`, `-rigid`, `-vehicle`: Godot los convierte en otros tipos al importar.
