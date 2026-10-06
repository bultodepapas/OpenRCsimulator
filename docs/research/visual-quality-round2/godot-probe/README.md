# Ensayo reproducible: parámetros por objeto y culling

2026-10-05, fecha de sesión en America/Bogota. Proyecto sintético separado de `app/`, usando el binario fijado Godot 4.7.2, Compatibility/OpenGL 3 y llvmpipe. Código original bajo la licencia MIT del repositorio.

Se ejecutaron **dos procesos**, cinco estados capturados y ocho comprobaciones de color por proceso. Las cinco imágenes se repitieron byte a byte. No hubo errores de motor, script o shader; sí el aviso esperado de VSync no soportado por el driver software. [Resultado](evidence/result.json), [repetición](evidence/repeat-result.json), [validación](evidence/validation.json), [log](evidence/run.log), [log repetición](evidence/repeat-run.log).

| Estado | Resultado observado | Captura |
| --- | --- | --- |
| Un material compartido, dos `instance uniform tint` | Izquierda roja, derecha verde | [01](evidence/01-instance-red-green.png) |
| Cambiar únicamente el parámetro de la izquierda | Izquierda azul; derecha conserva verde | [02](evidence/02-instance-blue-green.png) |
| Cambiar un uniform ordinario del recurso compartido | Ambas pasan a amarillo | [03](evidence/03-shared-yellow.png) |
| Mesh en x=100 desplazado −100 por shader; bounds automáticos | El objeto queda descartado: centro negro | [04](evidence/04-displaced-culled.png) |
| Mismo mesh/shader, bounds locales ajustados al desplazamiento | Se dibuja rojo en el centro | [05](evidence/05-displaced-bounds.png) |

La comparación de bounds modifica **solo** `custom_aabb` entre 04 y 05. El desplazamiento exagerado de 100 unidades hace inequívoco el experimento; no es una configuración de vegetación recomendada. El margen real debe cubrir la máxima deformación de cada efecto.

Los colores se muestrean en el centro de los quads, tolerancia por canal 0,03 (estimación del arnés). Esta prueba acredita el aislamiento de colores y el cambio de visibilidad, no comportamiento de texturas por instancia, materiales iluminados, MultiMesh, rendimiento, drivers de la RTX 3090 o integración con aviones. El estado 04 reproduce un descarte esperado, no un shader roto.

Para repetir desde la raíz del repo sin generar `.godot/` en los documentos:

```bash
probe_dir=$(mktemp -d /tmp/openrc-vq-probe.XXXXXX)
probe_output=$(mktemp -d /tmp/openrc-vq-output.XXXXXX)
cp docs/research/visual-quality-round2/godot-probe/project.godot "$probe_dir/"
cp docs/research/visual-quality-round2/godot-probe/probe.gd "$probe_dir/"
LP_NUM_THREADS=1 timeout 55 xvfb-run -a -s '-screen 0 640x360x24' \
  "$(app/get-godot.sh)" --path "$probe_dir" \
  --rendering-driver opengl3 --audio-driver Dummy --script res://probe.gd \
  -- --out="$probe_output"
```

Se necesita un renderer real, aunque sea software: `--headless` no valida píxeles ni compilación del shader en GPU. La repetición usa el mismo proyecto temporal y caché, por lo que no es un ensayo de primera carga ni de clon limpio. No se añaden recursos, dependencias o pruebas a la aplicación.
