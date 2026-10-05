# Inspección, carga y contraste aerodinámico para dos aviones

2026-10-05 · Investigación documental y lectura del código. Godot fijado **4.7.2**, renderer **Compatibility**. Las recomendaciones y umbrales siguientes son propuestas; no se ejecutaron nuevos ensayos de GPU, exportación ni solvers. [Índice de las doce investigaciones](README.md).

<a id="investigacion-10"></a>

## Investigación 10 — SubViewport para inspección, miniaturas y silueta propia

**Pregunta.** ¿Cómo reutilizar el modelo construido para inspeccionarlo y producir una sombra reconocible, sin mantener otra geometría aproximada del Extra?

**Situación comprobada.** [inspect_model.gd](../../../app/aircraft/inspect_model.gd) ya captura después de `RenderingServer.frame_post_draw`, restablece visibilidad entre vistas y registra cámaras y hashes. Conviene conservar ese trabajo. Sin embargo, fija geometría, metadatos y cámaras del Stik. [shadow.gd](../../../app/render/shadow.gd) calcula extensión desde las mallas, pero dibuja una máscara rectangular con `WING_V`, `STAB` y `WING_CENTER_V` constantes. Cambiar solo la envergadura mantendría una sombra de Stik bajo un Extra.

**Hallazgos.** `SubViewport` ofrece un render target separado y modos de actualización: `UPDATE_ONCE` dibuja una vez y luego se desactiva; el predeterminado depende de que la textura sea visible. Una captura fuera de pantalla no debería depender de ese predeterminado. Debe tener tamaño válido y pertenecer al árbol. [API SubViewport](https://docs.godotengine.org/en/4.7/classes/class_subviewport.html). Un mundo propio permite separar avión, iluminación y fondo del paisaje; hay que proporcionar cámara y entorno de inspección explícitos. [API Viewport](https://docs.godotengine.org/en/4.7/classes/class_viewport.html).

Leer la textura antes del dibujo puede obtener contenido vacío; se espera `frame_post_draw`. `get_image()` implica recuperar datos de la GPU y no es apropiado para recalcular la sombra cada frame. [ViewportTexture](https://docs.godotengine.org/en/4.7/classes/class_viewporttexture.html), [Texture2D](https://docs.godotengine.org/en/4.7/classes/class_texture2d.html). La cámara ortográfica es útil para una máscara sin perspectiva; para legibilidad en vuelo se mantienen las cámaras perspectivas reales. [Camera3D](https://docs.godotengine.org/en/4.7/classes/class_camera3d.html).

**Aplicación propuesta.** Primero parametrizar el inspector por definición de avión, conservando sus suites existentes. Después, si el menú necesita una miniatura interactiva, reutilizar la receta de captura en un SubViewport. Para la sombra, comparar dos soluciones acotadas: rasterizar los contornos declarativos del ala/fuselaje/cola en CPU, o capturar una vez el modelo original desde arriba con material de máscara. La segunda refleja cambios del modelo; la primera puede ser más simple y reproducible. En ambos casos guardar el rectángulo de proyección y la posición del datum/CG en él: la imagen sola no corrige el desplazamiento fijo de `footprint()`.

En el Extra esto recupera la planta trapezoidal y el fuselaje ancho; en el Stik elimina otra fuente de proporciones duplicadas. La máscara cenital sigue siendo una ayuda planar: no reproduce una sombra física exacta de todas las actitudes. Para una máscara opaca se tratarán cabina y hélice con una política expresa, independiente de su transparencia de belleza.

**Decisión y prueba pendiente.** Adoptar el inspector por avión en EX-02/03; evaluar máscara propia en EX-10; aplazar una vista 3D permanentemente activa en el selector. Comparar máscara CPU y SubViewport a 128/256 px con una vista cenital reservada, marcar CG y medir desplazamiento en metros. Aceptación propuesta: contorno y datum dentro de un texel respecto de la referencia rasterizada elegida; ningún borde recortado; captura no vacía; reabrir selector no crea mundos ni cámaras acumulados. Registrar GPU/driver y coste de generación. Las capturas necesitan un renderer real, como el flujo actual con Xvfb/OpenGL: `--headless` utiliza el renderer dummy. [Línea de comandos](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html).

Herramienta nativa, sin dependencia nueva; conservar el pin del motor y sus avisos de licencia MIT existentes. No hay mejora de rendimiento demostrada todavía.

<a id="investigacion-11"></a>

## Investigación 11 — ResourceLoader y exportación de un catálogo de dos aviones

**Pregunta.** ¿Cómo evitar pausas y recursos ausentes al seleccionar Extra → Stik, sin introducir un cargador complejo antes de medirlo?

**Situación comprobada.** [airplane.gd](../../../app/render/airplane.gd) precarga el constructor Stik y ejecuta `build()`; [FlightSession.setup](../../../app/sim/flight_session.gd) ya recibe una ruta de datos. [ugly_stik_finish.gd](../../../app/aircraft/ugly_stik_finish.gd) rasteriza el SVG embebido una vez y conserva atlas/materiales estáticos. Cargar un script no ejecuta anticipadamente toda esa construcción. Los [presets](../../../app/export_presets.cfg) exportan recursos y filtran JSON; [export.sh](../../../app/export.sh) importa desde cero y prueba un vuelo del binario Linux, actualmente con el avión predeterminado.

**Hallazgos.** `ResourceLoader` carga recursos del motor y mantiene una caché por ruta. `load_threaded_request()` permite solicitar una carga, pero llamar a `load_threaded_get()` antes de que termine vuelve a bloquear. Consultar estado y errores es parte del protocolo, no basta cambiar el nombre de `load()`. [API ResourceLoader](https://docs.godotengine.org/en/4.7/classes/class_resourceloader.html), [carga en segundo plano](https://docs.godotengine.org/en/4.7/tutorials/io/background_loading.html).

El árbol activo no es seguro para mutaciones desde otro hilo. Además, crear instancias visuales o tocar recursos compartidos introduce restricciones que una carga de archivo no resuelve. [APIs e hilos](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html). Por tanto, envolver el `build()` actual en `WorkerThreadPool` sin auditar sus materiales, texturas y nodos sería una mala primera integración.

Los JSON y otros archivos que no son recursos requieren inclusión de exportación. Las rutas válidas en el árbol de trabajo no prueban su presencia en el paquete; los recursos seleccionados y sus dependencias siguen las reglas del preset. [Exportación](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html). El conjunto de fuentes de autoría fuera de `app/` y los originales bajo `references/` no debe convertirse en dependencia del ejecutable.

**Aplicación propuesta.** Un catálogo pequeño resuelve ID → constructor/geometría/datos/inspección. Preparar el cambio con la sesión detenida, validar datos y trim, construir el modelo y solo entonces reemplazar juntos sesión y vista. Mantener el anterior si falla la preparación. Empezar con construcción síncrona durante la selección y medir por separado lectura JSON, compilación/carga de recursos, construcción de mallas, raster SVG y primer frame. Eso distingue un problema de disco de uno de creación o shaders.

Si una pieza GLB demuestra necesidad de carga asíncrona, usar `ResourceLoader` para ese recurso y reservar instanciación/inserción para el hilo principal. El Stik se beneficia de conservar su caché inmutable, y el Extra de no mostrar la física del Stik durante una carga parcial. No exigir que toda memoria vuelva a cero: cachés compartidas retenidas deliberadamente son distintas de sesiones o señales que se acumulan.

**Decisión y prueba pendiente.** Adoptar catálogo y sustitución coherente en EX-03/11; aplazar hilos hasta tener una pausa medida. Ensayo: veinte ciclos Stik → Extra → Stik, ID desconocido, JSON inválido y recurso visual ausente. Registrar tiempos fríos/calientes, nodos, objetos y memoria estabilizada; debe existir exactamente una sesión activa, ningún callback duplicado y trazas con identidad correcta. Elegir presupuesto temporal contra hardware objetivo antes de optimizar, sin inventar una mejora porcentual.

En EX-12 exportar desde clon limpio y ejecutar un smoke explícito por ID; además una captura raster de cada binario/plataforma accesible, porque el vuelo headless no acredita sus texturas. Mantener la suite Stik como regresión. No se ha ejecutado esa matriz en esta investigación. La solución inicial usa APIs del pin 4.7.2, sin addon ni cambio de licencia.

<a id="investigacion-12"></a>

## Investigación 12 — XFOIL y AVL como herramientas offline para los datos de Godot

**Pregunta.** ¿Qué herramienta externa puede ayudar a estimar diferencias entre ala rectangular Stik y ala trapezoidal Extra sin confundir una predicción con un avión validado?

**Situación comprobada.** [aero.gd](../../../app/physics/aero.gd) aplica coeficientes globales y correcciones de pérdida por estaciones; no calcula automáticamente aerodinámica desde las mallas de Godot. [aircraft_data.gd](../../../app/physics/aircraft_data.gd) exige procedencia y verifica `span × mean_chord ≈ wing_area`, además de una región lineal protegida. La [auditoría Extra](../extra-300-integration-audit.md) documenta que esa cuerda representa `S/b`, mientras MAC debe registrarse aparte. Copiar coeficientes del Stik conservaría supuestos que la forma nueva no justifica.

**Hallazgos.** XFOIL analiza perfiles bidimensionales subsónicos, permite variar Reynolds, transición y deflexión. Puede servir para explorar sensibilidad si se dispone del contorno del perfil. [Sitio del autor](https://web.mit.edu/drela/Public/web/xfoil/). Su documentación describe problemas con separación masiva, flujo inherentemente no estacionario, Reynolds demasiado bajo y resolución insuficiente de burbujas de separación. Una curva que convergió no es una medición del kit; una que no convergió tampoco aporta un punto fiable de pérdida. [Manual XFOIL](https://web.mit.edu/drela/Public/web/xfoil/xfoil_doc.txt).

AVL representa superficies sustentadoras y calcula cargas, trim y derivadas. Sus hipótesis favorecen superficies delgadas, pequeños ángulos y flujo cuasiestacionario; no es un validador de harrier, hover o snap. [Manual AVL](https://web.mit.edu/drela/Public/web/avl/avl_doc.txt). Hay que declarar referencias geométricas, ejes, puntos de momento y controles para interpretar sus resultados. [Guía de usuario](https://web.mit.edu/drela/Public/web/avl/AVL_User_Primer.pdf). Ambos son herramientas externas; no aportan por sí mismos propwash, contacto de ruedas ni la integración temporal de nuestro simulador.

**Aplicación propuesta.** Antes de elegir un solver, resolver EX-01: datum, planta, incidencias, perfil disponible y superficie de referencia. Exportar desde esos datos una configuración independiente de la malla decorativa. En XFOIL comparar perfiles solo donde haya evidencia; usar alternativas declaradas si el plano no determina el perfil. Registrar `Re = V·c/ν`, condición atmosférica y transición, en vez de adoptar una polar de avión real por compartir nombre.

Para AVL, reproducir primero un caso rectangular simétrico con signos y referencias conocidos; luego usar las geometrías Stik y Extra con una configuración común documentada. Convertir explícitamente ejes, unidades y normalización de momentos antes de comparar con Godot. En particular, una derivada de momento normalizada con MAC no se pega en un JSON normalizado con `S/b`. El beneficio para el Stik es revisar sensibilidad y supuestos existentes; para el Extra, contrastar tendencias de estabilidad y mandos antes de ajustar sensaciones de vuelo.

**Decisión y prueba pendiente.** Aplazar ejecución hasta disponer de geometría mínima; candidato para EX-05/09, no requisito de EX-02. Ensayo propuesto: α de −4° a +4°, controles pequeños y dos discretizaciones refinadas, manteniendo CG fijo. Comprobar signos, simetría, unidades y convergencia; propuesta de aceptación numérica: variación menor del 2 % en magnitudes no próximas a cero al refinar, con tolerancia absoluta declarada para las restantes. Esa convergencia solo valida estabilidad numérica del cálculo. Guardar entradas, logs, versión, hash del ejecutable y coeficientes como `derived`/`estimated` según su cadena de evidencia; discrepancias con Godot quedan registradas, no se fuerza acuerdo automático.

Los autores distribuyen [XFOIL](https://web.mit.edu/drela/Public/web/xfoil/) y [AVL](https://web.mit.edu/drela/Public/web/avl/) bajo GPL. Si se adoptan, fijar versión exacta del artefacto y conservar su licencia; no integrarlos ni redistribuir binarios como parte del juego en esta propuesta. No se descargaron, instalaron ni ejecutaron aquí. La validación física final sigue necesitando observación independiente del avión/configuración y pruebas de vuelo.
