# Revisión de contornos AV-02

Compara la maqueta actual con los renders iniciales, manteniendo las cámaras de `alignment/camera-fit.json`. El render exige `--compare-geometry` para aceptar una geometría distinta de la usada al ajustar las cámaras. Registra ambos hashes y no recalcula el encuadre. Los puntos usados por la comprobación de proyección son las anclas antiguas, no puntos medidos sobre la nueva malla.

Desde la raíz del repositorio, con directorios de salida nuevos:

```sh
$(app/get-godot.sh) --headless --path research/avanti-s/av02 --script res://verify.gd
xvfb-run -a $(app/get-godot.sh) --path research/avanti-s/av02 \
  --audio-driver Dummy --rendering-driver opengl3 --script ../alignment/render.gd \
  -- --compare-geometry --output-dir="$PWD/references/avanti-s/refinement-next/renders"
python3 research/avanti-s/refinement/review.py \
  --candidate references/avanti-s/refinement-next/renders \
  --output references/avanti-s/refinement-next
```

`review.py` necesita las tres fotos originales indicadas por las cámaras, los renders iniciales `references/avanti-s/alignment/renders-v1/` y los nuevos renders con manifiesto. Se instalan sus dependencias en un entorno virtual con `pip install -r research/avanti-s/refinement/requirements.txt`. Los originales se recuperan según `docs/research/avanti-s-resources.json`; no se distribuyen en Git. El inspector y `verify.gd` funcionan sin ellos.

La página usa SVG: referencias intactas, dos capas de render, opacidad, contornos, puntos de revisión y alternancia. No aplica transformaciones manuales. La comparación por píxeles lee únicamente el canal alpha de los renders; **no edita imágenes**. `contour-picks.json` documenta muestras manuales exploratorias, elegidas durante el afinado. La distancia al borde más cercano no identifica piezas ni demuestra precisión física; los cambios de oclusión pueden mover la métrica de una zona sin modificar esa pieza.

[Resultado de esta revisión](../../../docs/research/avanti-s-contour-refinement.md) · [Comparador local](../../../references/avanti-s/refinement-v2/index.html).

Para comparar revisiones consecutivas, `--baseline` selecciona el directorio de renders anterior (con manifiesto), `--before-label`/`--after-label` identifican ambas versiones y `--description`/`--report` indican el cambio y su informe. Se registra el hash de geometría y constructor de ambos lados. [Ejemplo v2 → v3](../../../docs/research/avanti-s-contour-refinement-v3.md). Los archivos históricos ya generados se conservan.
