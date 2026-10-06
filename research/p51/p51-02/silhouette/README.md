# Siluetas del P-51D sobre la tres vistas AN 01-60-3

La técnica de las siluetas del Avanti (`research/avanti-s/user-profile`, `alignment`, `refinement`) aplicada al P-51D con una referencia mejor que fotos: la **tres vistas acotada oficial de North American (AN 01-60-3 p. 30, dominio público)**, ya ortográfica, descargada en `references/p51-mustang/drawings/` (hash en `references/p51-mustang/index.json`). El dibujo no se edita nunca.

1. `measure.py` rellena la silueta de cada vista (trazo cerrado 3 px, relleno del papel desde el borde, apertura 4 px que borra cotas y texto, mayor componente, retroceso 2 px al centro de la tinta), calibra cada eje con una cota impresa (longitud 387 5/16 in, envergadura 37 ft 5/16 in, deriva 69 9/16 in) y escribe `metrology.json` (metros a escala real; z desde el borde de ataque extrapolado a la línea central, y desde la línea de referencia del fuselaje). Comprobaciones reservadas: envergadura del estabilizador +0,5 %, área alar +0,6 %, MAC +0,7 %.
2. `apply_metrology.py` vuelca el perfil medido en `assets/aircraft/p51d-mustang-120/source.json` con reglas explícitas (máscaras del mástil, el patín extendido, la deriva y las zonas donde ala y estabilizador se funden con el fuselaje en planta; cono de cola interpolado; piloto desde una plantilla). Es idempotente.
3. `prepare.py` fija una cámara ortográfica por vista con dos anclas (perfil: punta del cono y timón sobre la línea de referencia; planta y frontal: puntas de ala), escala uniforme, sin rotación ni deformación → `camera-fit.json`.
4. `render.gd` renderiza el modelo con fondo transparente y material plano cian al tamaño exacto del recorte, sin hélice, y comprueba que las anclas proyectan donde se marcaron (< 1 px).
5. `review.py` superpone, mide y escribe `metrics.json`, `overlay_*.png` e `index.html` (visor SVG con opacidad, contorno y «antes»).

Desde la raíz (el directorio de renders debe ser nuevo):

```sh
python3 research/p51/p51-02/silhouette/measure.py --output /tmp/p51-sil      # metrology.json + diagnósticos
python3 research/p51/p51-02/silhouette/apply_metrology.py                    # source.json
python3 assets/aircraft/p51d-mustang-120/build_geometry.py && python3 assets/aircraft/p51d-mustang-120/compile_geometry.py
python3 research/p51/p51-02/silhouette/prepare.py                            # camera-fit.json (anclas del modelo actual)
xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy \
  --script res://../research/p51/p51-02/silhouette/render.gd -- --output-dir=/tmp/p51-renders
python3 research/p51/p51-02/silhouette/review.py --candidate /tmp/p51-renders \
  --baseline research/p51/p51-02/silhouette/renders-before --output /tmp/p51-review --label "prueba"
```

`renders-before/` es la primera maqueta (a ojo), `renders-after/` la revisión 1 y `review-2026-10-06/` su comparación con visor. Métrica: distancia euclídea de cada píxel del contorno del dibujo al borde más cercano del alpha del render (y a la inversa) e IoU de las máscaras; en píxeles (≈ 490 px por metro de modelo), no es precisión métrica por pieza. Las palas dibujadas se excluyen por cajas en perfil y planta; en la frontal no se pueden separar del cuerpo, así que esa vista es cualitativa. Dependencias: Python 3 con NumPy, SciPy y Pillow del sistema (las mismas que el Avanti).

[Informe](../../../../docs/research/p51-silhouette-review-v1.md) · [Plan](../../../../docs/P51-PLAN.md).
