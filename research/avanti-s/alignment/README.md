# Comparación por transparencias

La herramienta ajusta únicamente la cámara del modelo AV-02 a tres fotos existentes y superpone un render RGBA sobre el original. No modifica la geometría, las fotos ni los recursos de la app.

Abrir [el comparador local](../../../references/avanti-s/alignment/index.html). Incluye opacidad, contorno, parpadeo, solo foto/modelo, desplazamiento arrastrando, escala uniforme, giro y exportación JSON del ajuste manual.

Reproducción desde la raíz:

```sh
# Recalcular cámaras: usa las fotografías locales para verificar sus hashes.
# Versiones utilizadas, ya presentes: Python 3, NumPy 1.26.4 y SciPy 1.11.4.
python3 research/avanti-s/alignment/fit.py

# El directorio de renders debe ser nuevo. Este paso funciona sin fotografías.
xvfb-run -a $(app/get-godot.sh) --path research/avanti-s/av02 \
  --audio-driver Dummy --rendering-driver opengl3 --script ../alignment/render.gd \
  -- --output-dir=/tmp/avanti-aligned-renders

# Para publicar el comparador usa references/avanti-s/alignment/renders-v1/
# como salida del render inicial; build_page.py enlaza esa carpeta.
python3 research/avanti-s/alignment/build_page.py
```

`picks.json` conserva puntos manuales, dimensiones de imagen, hashes y posiciones 3D del modelo. `camera-fit.json` registra cámara, FOV supuesto, puntos proyectados y residuos. Se ajustan seis parámetros de pose con FOV vertical fijo 45°, centro óptico centrado y sin distorsión de lente. Cuatro puntos por vista intervienen en el ajuste; los demás se reservan para contraste.

Los extremos del ala/cola son aproximaciones al punto medio del borde de punta visible. La tolerancia de selección indicada es orientativa, no una desviación estadística medida. La salida en el perfil está parcialmente oculta. El ajuste no convierte fotografías oblicuas en planos ni identifica dimensiones reales.

El renderer contrasta las proyecciones de SciPy con `Camera3D.unproject_position`; falla si difieren más de 0,05 px. La inversión entre ejes ópticos de imagen y ejes locales de cámara Godot se hace explícita. Genera tres imágenes con transparencia real y una máscara cian propia. La página usa SVG para superponerlas y extraer su contorno: no hay reconstrucción generativa de las fotografías.

[Resultados y límites](../../../docs/research/avanti-s-transparency-comparison.md). Las capturas de comparaciones contienen las fotos de terceros y permanecen locales, ignoradas por Git.
