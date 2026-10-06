# Nuevos ángulos del A200

Tres cámaras adicionales sobre el modelo `a200-av02-contours-03`. Los originales locales se identifican mediante `docs/research/avanti-s-new-angle-resources.json`; sin ellos se puede renderizar la maqueta, pero no volver a ajustar cámaras ni construir el visor fotográfico. Dependencias Python: las fijadas en `../refinement/requirements.txt`.

Desde la raíz, conservando un directorio de render nuevo:

```sh
python3 research/avanti-s/alignment/fit.py \
  --picks research/avanti-s/new-angles/picks.json \
  --output research/avanti-s/new-angles/camera-fit.json
xvfb-run -a $(app/get-godot.sh) --path research/avanti-s/av02 \
  --audio-driver Dummy --rendering-driver opengl3 --script ../alignment/render.gd \
  -- --fit=res://../new-angles/camera-fit.json \
  --picks=res://../new-angles/picks.json \
  --output-dir="$PWD/references/avanti-s/new-angles/renders-final"
python3 research/avanti-s/new-angles/build_page.py
```

Si `renders-final` ya existe, conservarlo y elegir otro directorio para una comprobación aislada. `build_page.py` publica el conjunto final indicado, comprueba hashes de originales/renders y respeta la dimensión nativa de cada vista. Las imágenes se referencian mediante SVG/HTML, sin deformaciones ni edición de píxeles.

`initial_camera_roll_deg` ayuda a iniciar el ajuste de una foto con fuerte alabeo; `camera_hemisphere: below` descarta soluciones vistas desde arriba para una foto del intradós. No son grados de mando ni mediciones de actitud de vuelo. Los puntos son manuales y exploratorios, no referencias topográficas.

El ajuste se niega a usar otra geometría que la identificada por las muestras. Al refinar el modelo, congelar estas cámaras y renderizar con `--compare-geometry`; no volver a encuadrar silenciosamente. El render exige también que el hash de las muestras coincida con el registrado en la cámara.

[Informe y límites](../../../docs/research/avanti-s-new-angles.md) · [Galería local](../../../references/avanti-s/new-angles/index.html).
