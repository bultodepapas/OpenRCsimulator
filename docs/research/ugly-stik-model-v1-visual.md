# Ugly Stik modelo v1: protocolo y revisión visual

**Alcance.** Escena de inspección independiente del simulador, que instancia el constructor procedural disponible en `app/render/airplane.gd`. Esta revisión comprueba silueta, ensamblaje y legibilidad visual del mismo modelo en varias cámaras; no modifica la física, no calibra las cotas del plano y no certifica que el .61 concreto quepa en el morro.

La primera configuración pedida es el Jensen Ugly Stik de 60 pulgadas con motor nitro clase .61. La marca del motor sigue abierta y las variantes mini y gigante se dejan para después. El constructor puede cambiar durante el trabajo en paralelo; el visor consume el contrato existente `{ root, propeller, hinges }` y no escribe en `app/captures/`.

## Capturas comparables

`research/ugly-stik/model-v1/capture.sh` abre el Godot fijado por `app/get-godot.sh`, crea una ventana virtual 1280×720 y guarda sus resultados en `research/ugly-stik/model-v1/captures/`.

La serie incluye planta e intradós ortográficos, perfil y frente ortográficos, perspectiva de tres cuartos neutra y con una pose fija de mandos, y tres imágenes de vuelo a 20, 50 y 100 m. Las tres distancias usan FOV vertical de 50°, `KEEP_HEIGHT`, el mismo avión, la misma orientación y 1280×720. Un rótulo breve identifica la vista y sus condiciones. `manifest.json` registra los límites de la geometría que renderizó Godot, materiales, triángulos, distancia y proyección vertical calculada.

La pose desviada es una demostración visual estática; no representa una orden de piloto ni afirma los signos de mando. Para las vistas ortográficas se usan encuadres distintos por orientación, así que son útiles para inspección, no para comparar tamaño relativo entre vistas. El fondo es uniforme y no se añade suelo para mantener la silueta clara.

## Resultado observado

Serie final de inspección, 2026-10-05, Godot 4.7.2 con llvmpipe, 1280×720. El script completó las nueve tomas sin errores GDScript. El manifiesto mide una caja de **1.52283 × 0.48510 × 1.34750 m**, con 46 `MeshInstance3D`, **2,568 triángulos y 5 materiales únicos** compartidos por el constructor. La extensión X queda 1.17 mm por debajo del objetivo de 1.524 m del plano; la geometría visible sigue siendo una aproximación, no una comprobación dimensional completa.

La primera pasada había revelado dos defectos del propio visor: la pose neutra no restablecía las bisagras y la cámara tres cuartos quedaba lejos. Se corrigieron antes de generar esta serie: cada pose ahora se deriva de `Commands.neutral_commands()` y `Commands.hinge_rotations()`, y la cámara cercana encuadra el avión completo. Se añadió relleno inferior para mostrar el intradós sin cambiar el material oscuro elegido para distinguir las caras.

| Vista | Hallazgo de la serie final |
| --- | --- |
| [Planta](../../research/ugly-stik/model-v1/captures/top.png) | La franja alar, el fuselaje estrecho y la cola se separan bien. El cuerpo y la cola conservan continuidad aparente. |
| [Intradós](../../research/ugly-stik/model-v1/captures/bottom.png) | El relleno ayuda a distinguir ala, varillas del tren y cola; los colores oscuros siguen señalando la cara inferior. |
| [Perfil](../../research/ugly-stik/model-v1/captures/side.png) | El ala ya apoya visualmente sobre el fuselaje con `root_y = 0.048 m`; no se aprecia el hueco de la toma anterior. |
| [Frente](../../research/ugly-stik/model-v1/captures/front.png) | Se distinguen el diedro leve y el tren triciclo. No se ve recorte de puntas ni de ruedas. |
| [Tres cuartos neutro](../../research/ugly-stik/model-v1/captures/three-quarter-neutral.png) | El avión ocupa cerca de 700×320 px y entra completo; motor, hélice, cola y bandas se pueden inspeccionar juntos. No observé agujeros abiertos en el encastre del ala o la cola. |
| [Tres cuartos desviado](../../research/ugly-stik/model-v1/captures/three-quarter-deflected.png) | Alerones, elevador y timón cambian respecto a neutro y conservan una unión visible en sus bisagras. La pose se fija con roll/pitch/yaw = 0.75 y solo demuestra la articulación. |
| [20 m](../../research/ugly-stik/model-v1/captures/flight-20m.png) / [50 m](../../research/ugly-stik/model-v1/captures/flight-50m.png) / [100 m](../../research/ugly-stik/model-v1/captures/flight-100m.png) | La proyección del ancho X es 58.78 / 23.51 / 11.76 px. A 20 m se lee el ala y los colores; a 50 m queda una silueta pequeña; a 100 m es apenas una marca de envergadura, sin detalle identificable. |

El manifiesto numérico ayuda a detectar una geometría fuera de escala y a reproducir encuadres. La lectura humana sigue siendo una inspección visual; el cálculo de píxeles no sustituye una prueba de percepción con usuarios.

## Ejecución

Desde cualquier directorio del repositorio:

```sh
bash research/ugly-stik/model-v1/capture.sh
```

El ejecutable de Godot se descarga y verifica por SHA-512 si aún no está en `.tools/`. Se requiere `xvfb-run` y el controlador OpenGL por software disponible en el entorno. El script escribe únicamente en la carpeta `captures/` de esta investigación y falla si Godot registra un error GDScript. Para repetir la serie tras otro cambio geométrico, usa el mismo comando; el manifiesto registra límites, triángulos, materiales, distancia y tiempos.
