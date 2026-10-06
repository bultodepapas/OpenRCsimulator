# Perfil aportado por el usuario

El PNG original permanece local, con SHA-256 fijado en `prepare.py` y su registro de procedencia. El script lee dimensiones y calcula una alineación uniforme de perfil; no modifica imágenes. La variante exacta de la foto está pendiente de confirmar.

Desde la raíz:

```sh
python3 research/avanti-s/user-profile/prepare.py
xvfb-run -a $(app/get-godot.sh) --path research/avanti-s/av02 \
  --audio-driver Dummy --rendering-driver opengl3 --script ../alignment/render.gd \
  -- --fit=res://../user-profile/camera-fit.json \
  --picks=res://../user-profile/picks.json \
  --output-dir="$PWD/references/avanti-s/user-profile/renders-profile"
python3 research/avanti-s/user-profile/build_page.py
```

El directorio de renders debe ser nuevo. Si ya existe, usar otro nombre para una prueba aislada y conservar la evidencia. Dependencias Python: `../refinement/requirements.txt`. Renderizar con la cámara guardada no necesita el original; recalcular la alineación o generar el visor sí.

La escala por nariz/extremo posterior **es una alineación visual aproximada**, no una calibración: el extremo posterior del cuerpo está inferido y no es el centro visible del escape. El perfil ortográfico del modelo no elimina la perspectiva de la foto. [Observaciones y límites](../../../docs/research/avanti-s-user-profile.md).
