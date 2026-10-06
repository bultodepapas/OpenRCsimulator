# Avanti · perfil transparente aportado por el usuario

2026-10-06 · PNG original local (`references/avanti-s/user-profile/avanti-s-perfil-recortado-usuario.png`, local only) · comparador de perfil (`references/avanti-s/user-profile/index.html`, local only) · [registro de procedencia](avanti-s-user-profile-resource.json).

El adjunto se guardó **sin recortar, remuestrear, regenerar ni modificar sus bytes**: PNG RGBA, **1818 × 865**, 785.323 bytes, con alpha entre 0 y 255. Su SHA-256 es `4ab4d1ba032756c4c0877a00db53162c38cf4ecdfa79d8dedf83d74dbb8977e3`. Se conservan los restos del recorte en el borde. El fondo cuadriculado del visor no forma parte de la imagen.

La procedencia registrada es el adjunto del usuario. No se conoce el autor original ni se ha confirmado la versión exacta del Avanti de la fotografía. Se conserva como referencia visual de la familia, sin trasladar sus dimensiones a la física ni tratarlo como plano del A200.

## Uso inmediato

Se generó una superposición del perfil del modelo v3 sobre este recorte, con escala uniforme y sin estirar ejes. La escala de presentación se obtiene de nariz y extremo posterior aproximado del cuerpo; se centra verticalmente entre ambos. **El escape no está visible de forma fiable:** el punto posterior es una aproximación sobre el cuerpo fotografiado, no una medida de la tobera. Las anclas pueden mostrarse en el visor.

La cámara del modelo es ortográfica lateral para facilitar la lectura del perfil. Eso no convierte la fotografía en una vista ortográfica: alas, estabilizador y tren muestran perspectiva. No se deforma la foto para encajar el modelo. Los datos de alineación están en [picks.json](../../research/avanti-s/user-profile/picks.json) y [camera-fit.json](../../research/avanti-s/user-profile/camera-fit.json).

La referencia permite contrastar:

- **Cabina:** altura de la cúpula, posición longitudinal y transición hacia nariz/lomo. Bajo esta alineación, la cabina de la maqueta queda más baja y algo adelantada.
- **Deriva y lomo:** la parte alta de la deriva queda adelantada en el modelo respecto al recorte; revisar también la curva de unión, sin atribuir todo el desplazamiento a geometría antes de confirmar variante y alineación.
- **Vientre y toma:** continuidad inferior y relación de la entrada lateral con el ala; la toma fotografiada es una abertura integrada y la aproximación actual todavía necesita detalle.
- **Tren y placas alares:** referencia para trabajo posterior. No deben considerarse fallos de contorno del fuselaje porque aún no existen en esta maqueta.

No se cambió la geometría en esta tarea. Los residuos de puntos de cabina/deriva se guardan para hacer explícita la discrepancia, no como una medición física: depende de un extremo posterior inferido y de la perspectiva. Esta foto complementa las [otras vistas](avanti-s-new-angles.md).

## Verificación

[Informe](avanti-s-user-profile-validation.json): hash del original intacto, dimensiones/transparencia, generación de perfil en clon sin referencias, proyección numérica contrastada con Godot y regresión de los tres renders de perspectiva existentes. El visor comprueba foto/modelo/superposición, opacidad, contorno, anclas y móvil a 390 px.

El original y las capturas están bajo `references/avanti-s/user-profile/`, cubierto por la exclusión existente de Git. Se registra en el manifiesto general con origen `user-attachment:`, no como descarga web. No se ejecutó la suite del simulador: no se modificó `app/`.
