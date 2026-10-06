# AV-02: primera maqueta Godot aislada

Godot **4.7.2**, Compatibility. Usa únicamente geometría procedural propia y `geometry.json`; funciona sin las fotos y PDF locales. No se conecta al menú, catálogo ni física del simulador.

Desde la raíz del repositorio:

```sh
# Inspector con vistas, flaps, alerones, elevadores, timón e interior.
$(app/get-godot.sh) --path research/avanti-s/av02 --audio-driver Dummy --script res://inspect.gd

# Comprobación estructural y de signos, sin display.
$(app/get-godot.sh) --headless --path research/avanti-s/av02 --script res://verify.gd

# Nueve capturas reproducibles; el directorio de salida debe ser nuevo.
xvfb-run -a $(app/get-godot.sh) --path research/avanti-s/av02 \
  --audio-driver Dummy --rendering-driver opengl3 --script res://inspect.gd \
  -- --output-dir=/tmp/avanti-study-captures
```

El inspector permite elegir frente, perfil, planta, inferior y dos oblicuas. Los tres botones de flap aplican 0°/20°/50°. Los deslizadores aplican órdenes normalizadas de alabeo, cabeceo y dirección; Neutro restablece mando y deslizadores. Interior oculta fuselaje/cabina y muestra el volumen nominal de turbina. La posición de esa turbina está estimada: esta vista no prueba holguras ni diseño de conducto.

La longitud/envergadura y volumen nominal del motor son cotas documentadas. Todas las secciones, cuerdas, espesores, bisagras y posiciones de instalación tienen evidencia `estimated_visual_blockout` en `geometry.json`. Los paneles son sólidos delgados, no perfiles aerodinámicos. Rojo identifica superficies móviles; el acabado no reproduce todavía la librea.

El modelo ofrece siete bisagras, dos por grupo bilateral más timón. Guarda punto/eje/resto por bisagra y compone la deflexión respecto al reposo. El nodo `propeller` vacío es un marcador de compatibilidad; `has_propeller=false`. La maqueta no usa ni modifica el constructor del Ugly Stik o Extra.

`verify.gd` comprueba escala de la malla construida, vértices finitos, simetría de extremos, tamaño nominal de turbina, ausencia de hélice, sentidos de movimiento sobre puntos del borde de salida, invariancia del eje, reinicio e independencia entre dos instancias. No certifica semejanza, perfiles, volumen barrido libre de colisiones ni comportamiento de vuelo.

[Informe y límites](../../../docs/research/avanti-s-av02-preview.md) · [Capturas locales](../../../references/avanti-s/av02/index.html). Si el enlace a referencias no existe en un clon, el inspector y las verificaciones siguen funcionando.

Revisión actual `a200-av02-contours-02`: ala/estabilizador con puntas segmentadas, deriva con transición cóncava y tomas carenadas. [Antes/después y límites](../../../docs/research/avanti-s-contour-refinement.md). Las capturas iniciales anteriores se conservan como referencia histórica.
