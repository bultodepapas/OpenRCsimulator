# Ugly Stik modelo v1: protocolo y revisión visual

**Alcance.** Escena de inspección independiente del simulador, que instancia el constructor procedural disponible en `app/render/airplane.gd`. Esta revisión comprueba silueta, ensamblaje y legibilidad visual del mismo modelo en varias cámaras; no modifica la física, no calibra las cotas del plano y no certifica que el .61 concreto quepa en el morro.

La primera configuración pedida es el Jensen Ugly Stik de 60 pulgadas con motor nitro clase .61. La marca del motor sigue abierta y las variantes mini y gigante se dejan para después. El constructor puede cambiar durante el trabajo en paralelo; el visor consume el contrato existente `{ root, propeller, hinges }` y no escribe en `app/captures/`.

## Capturas comparables

`research/ugly-stik/model-v1/capture.sh` abre el Godot fijado por `app/get-godot.sh`, crea una ventana virtual 1280×720 y guarda sus resultados en `research/ugly-stik/model-v1/captures/`.

La serie incluye planta e intradós ortográficos, perfil y frente ortográficos, perspectiva de tres cuartos neutra y con una pose fija de mandos, y tres imágenes de vuelo a 20, 50 y 100 m. Las tres distancias usan FOV vertical de 50°, `KEEP_HEIGHT`, el mismo avión, la misma orientación y 1280×720. Un rótulo breve identifica la vista y sus condiciones. `manifest.json` registra los límites de la geometría que renderizó Godot, materiales, triángulos, distancia y proyección vertical calculada.

La pose desviada es una demostración visual estática; no representa una orden de piloto ni afirma los signos de mando. Para las vistas ortográficas se usan encuadres distintos por orientación, así que son útiles para inspección, no para comparar tamaño relativo entre vistas. El fondo es uniforme y no se añade suelo para mantener la silueta clara.

## Resultado observado

Pendiente de ejecutar cuando el constructor del modelo v1 esté disponible. Registrar aquí defectos visibles concretos por vista, archivo y cambio pequeño siguiente. Una captura vacía o con el bloque anterior no cuenta como revisión del nuevo modelo.

| Vista | Resultado que se debe comprobar | Hallazgo de esta revisión |
| --- | --- | --- |
| Planta | Contorno del ala, alineación del fuselaje y cola, simetría y alerones | Pendiente |
| Intradós | Diferencia visible entre cara superior e inferior, continuidad y articulaciones | Pendiente |
| Perfil | Contorno del fuselaje, posición relativa de ala/cola, ruedas y hélice | Pendiente |
| Frente | Envergadura, simetría, diedro y altura del tren | Pendiente |
| Tres cuartos neutro | Lectura tridimensional y continuidad entre piezas | Pendiente |
| Tres cuartos desviado | Desplazamiento de cada superficie desde su bisagra | Pendiente |
| Vuelo 20/50/100 m | Lectura de silueta y grandes áreas; detalle fino solo si los píxeles lo permiten | Pendiente |

El manifiesto numérico ayuda a detectar una geometría fuera de escala y a reproducir encuadres. La lectura humana sigue siendo una inspección visual; el cálculo de píxeles no sustituye una prueba de percepción con usuarios.

## Ejecución

Desde cualquier directorio del repositorio:

```sh
bash research/ugly-stik/model-v1/capture.sh
```

El ejecutable de Godot se descarga y verifica por SHA-512 si aún no está en `.tools/`. Se requiere `xvfb-run` y el controlador OpenGL por software disponible en el entorno. El script escribe únicamente en la carpeta `captures/` de esta investigación. La inspección de cada PNG se registra en la tabla antes de considerar terminada la revisión visual.
