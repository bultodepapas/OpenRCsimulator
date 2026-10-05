# Ugly Stik modelo v1: protocolo y revisión visual

**Alcance.** Escena de inspección independiente del simulador, que instancia el constructor procedural disponible en `app/render/airplane.gd`. Esta revisión comprueba silueta, ensamblaje y legibilidad visual del mismo modelo en varias cámaras; no modifica la física, no calibra las cotas del plano y no certifica que el .61 concreto quepa en el morro.

La primera configuración pedida es el Jensen Ugly Stik de 60 pulgadas con motor nitro clase .61. La marca del motor sigue abierta y las variantes mini y gigante se dejan para después. El constructor puede cambiar durante el trabajo en paralelo; el visor consume el contrato existente `{ root, propeller, hinges }` y no escribe en `app/captures/`.

## Capturas comparables

`research/ugly-stik/model-v1/capture.sh` abre el Godot fijado por `app/get-godot.sh`, crea una ventana virtual 1280×720 y guarda sus resultados en `research/ugly-stik/model-v1/captures/`.

La serie incluye planta e intradós ortográficos, perfil y frente ortográficos, perspectiva de tres cuartos neutra y con una pose fija de mandos, y tres imágenes de vuelo a 20, 50 y 100 m. Las tres distancias usan FOV vertical de 50°, `KEEP_HEIGHT`, el mismo avión, la misma orientación y 1280×720. Un rótulo breve identifica la vista y sus condiciones. `manifest.json` registra los límites de la geometría que renderizó Godot, materiales, triángulos, distancia y proyección vertical calculada.

La pose desviada es una demostración visual estática; no representa una orden de piloto ni afirma los signos de mando. Para las vistas ortográficas se usan encuadres distintos por orientación, así que son útiles para inspección, no para comparar tamaño relativo entre vistas. El fondo es uniforme y no se añade suelo para mantener la silueta clara.

## Resultado observado

Primera inspección del constructor v1, 2026-10-05, Godot 4.7.2 con llvmpipe. El render produjo 9 PNG; el manifiesto inicial midió una caja de 1.5228 × 0.5011 × 1.3245 m, 45 `MeshInstance3D`, 2,460 triángulos y 73 materiales instanciados. La envergadura coincide con el objetivo documentado de 1.524 m dentro del margen de 1.2 mm. Estos conteos son del constructor inicial, antes del ajuste del asiento del ala y de la revisión geométrica en curso.

La primera serie descubrió un error del visor: la función de pose neutra enviaba un diccionario vacío y no devolvía a neutro los mandos después de la toma desviada. Los PNG de vuelo de esa primera corrida quedaron desviados aunque se rotularon `neutral`; no deben usarse como prueba de lectura en vuelo. El visor ya usa `Commands.neutral_commands()` y `Commands.hinge_rotations()` para restablecer y aplicar la pose. También se acercó la cámara de tres cuartos y se añadió un relleno suave inferior tras comprobar que el intradós perdía demasiado detalle. Se regenerará toda la serie después de que termine el ajuste de geometría; los PNG actuales son diagnósticos preliminares.

| Vista | Resultado que se debe comprobar | Hallazgo de esta revisión |
| --- | --- | --- |
| Planta | El contorno rojo/crema y la alineación general se distinguen. Revalidar tras el trazado de medidas. | Diagnóstico preliminar; `top.png` sí es neutra. |
| Intradós | La cara oscura diferencia orientación, pero la primera iluminación oculta detalles. Se añadió luz de relleno desde abajo. | Comparar en la serie regenerada. |
| Perfil | Se ve ala suspendida sobre el fuselaje con `root_y = 0.065 m`; el constructor ya se está corrigiendo a ~0.048 m. | Defecto geométrico observado, pendiente de confirmar tras el ajuste. |
| Frente | La simetría y el diedro leve se ven; comprobar altura del ala con el nuevo asiento. | Diagnóstico preliminar. |
| Tres cuartos neutro | El avión se entiende, pero ocupaba solo ~400×220 px. Se acercó la cámara para apuntar a ~650×360 px sin recorte. | Verificar encuadre con geometría final. |
| Tres cuartos desviado | La pose se distingue poco a esa escala. El visor aplica ahora mandos normalizados por el módulo de controles. | Revisar bisagras en el encuadre cercano. |
| Vuelo 20/50/100 m | El ancho proyectado calculado es 58.8/23.5/11.8 px. A 100 m queda solo una marca corta; no cabe esperar detalle. | Primera serie tenía mandos desviados por error del visor; repetir antes de valorar lectura. |

El manifiesto numérico ayuda a detectar una geometría fuera de escala y a reproducir encuadres. La lectura humana sigue siendo una inspección visual; el cálculo de píxeles no sustituye una prueba de percepción con usuarios.

## Ejecución

Desde cualquier directorio del repositorio:

```sh
bash research/ugly-stik/model-v1/capture.sh
```

El ejecutable de Godot se descarga y verifica por SHA-512 si aún no está en `.tools/`. Se requiere `xvfb-run` y el controlador OpenGL por software disponible en el entorno. El script escribe únicamente en la carpeta `captures/` de esta investigación y falla si Godot registra un error GDScript. La serie actual todavía es preliminar: falta volver a ejecutarla después de que se cierren los cambios geométricos en curso y revisar las nueve PNG resultantes.
