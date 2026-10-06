# Avanti S · segundo contorno a partir de las transparencias

2026-10-06 UTC · **AV-02, revisión `a200-av02-contours-02`.** Se afinó la maqueta Godot aislada utilizando las tres cámaras de la comparación anterior, sin volver a ajustarlas. Sigue siendo un estudio visual aproximado, no volable.

[Comparador local antes/después](../../references/avanti-s/refinement-v2/index.html) · [vista oblicua actual](../../references/avanti-s/refinement-v2/inspector-final/oblique-flap0.png) · [planta](../../references/avanti-s/refinement-v2/inspector-final/top-flap0.png) · [flaps 50°](../../references/avanti-s/refinement-v2/inspector-final/rear-flap50.png) · [reproducción](../../research/avanti-s/refinement/README.md).

## Cambios de forma

| Zona | Problema observado en la superposición | Ajuste aplicado |
| --- | --- | --- |
| Ala | Exceso de cuerda, especialmente cerca del fuselaje; punta rectangular | Cuerda de raíz estimada de 0,56 a 0,43 m; borde de salida con más estaciones y punta redondeada por segmentos; alerón termina en x=0,95 m, antes de la punta fija |
| Estabilizador | Superficie demasiado ancha hacia delante y extremos rectangulares | Menor cuerda estimada, cuatro estaciones y extremos redondeados; elevador conserva eje recto |
| Deriva | Unión angular y demasiado corta con el lomo | Nueve puntos en el borde delantero describen el arranque extendido y la transición curva hacia la punta |
| Tomas | Dos cilindros externos sobresalían como apéndices | Carenados elípticos espejados, boca más próxima a la raíz y cola que se oculta dentro de la piel; plano oscuro representa la boca |

Todas las nuevas posiciones, cuerdas y radios son **estimaciones visuales**, identificadas en [geometry.json](../../research/avanti-s/av02/geometry.json). Las tomas no modelan un conducto interno ni acreditan flujo/holgura. Se mantienen los 2,00 m de envergadura, 2,22 m de longitud y envolvente nominal P100-RX de 241 × 97 mm. Las secciones de fuselaje y cabina no se modificaron en esta revisión: no hay evidencia suficiente para resolver sus diferencias entre cámaras.

El constructor admite centros laterales por sección para crear las tomas. Los paneles cóncavos usan triangulación del polígono; el abanico desde el centro empleado inicialmente no es válido para cualquier transición de deriva. Los bordes de salida de las superficies móviles incluyen estaciones intermedias, pero su borde delantero y eje permanecen rectos. Las siete bisagras conservan sentidos y límites de mando.

## Comparación con cámaras congeladas

Se conserva `alignment/camera-fit.json` byte a byte. `render.gd` exige `--compare-geometry` cuando la geometría difiere de la usada para ajustar la cámara y registra los hashes de ambas. Su comprobación de proyección verifica las **anclas originales**, no afirma que los puntos de la nueva geometría coincidan con ellas.

El nuevo visor SVG permite ver antes/después juntos, cambiar vista, variar opacidad, mostrar contornos y muestras, y alternar foto/modelo. No desplaza ni deforma ninguna capa. Las fotos originales se validan por SHA-256; los renders también deben coincidir con sus manifiestos.

Se marcaron muestras exploratorias del borde visible en las fotos originales de 650 × 488. Se mide su distancia al borde más cercano del alpha de cada render. Los puntos se escogieron **durante el afinado**, no son un conjunto independiente de validación. Se excluyen tren y fences no representados. El borde más cercano puede pertenecer a otra pieza: esta métrica detecta diferencias en la imagen, no mide precisión geométrica por componente.

| Vista | Ala antes → después | Estabilizador antes → después | Fuselaje antes → después |
| --- | --- | --- | --- |
| Frontal alta | 7,3 → **3,6 px** | 5,3 → **2,4 px** | 5,4 → 5,5 px |
| Posterior alta | 9,4 → **4,0 px** | 14,0 → **11,6 px** | 9,6 → 9,7 px |
| Perfil oblicuo | 18,9 → **13,7 px** | 9,7 → **8,8 px** | 6,4 → 6,4 px |

Las muestras de deriva en perfil bajan de **8,0 a 5,0 px**. No todo mejora: el fuselaje permanece prácticamente igual y pequeñas diferencias de su métrica proceden de las oclusiones/tomas y del borde más cercano. La cola posterior conserva un desajuste apreciable. La cámara de perfil ya tenía incertidumbre elevada y un punto parcialmente oculto; no se utilizó para corregir por sí sola el avión.

[Mediciones completas](avanti-s-contour-metrics.json) · [muestras manuales](../../research/avanti-s/refinement/contour-picks.json) · [método de las cámaras](avanti-s-transparency-comparison.md). Los errores están en píxeles, no en milímetros; no son una calibración métrica ni una validación de aerodinámica.

## Pruebas y archivos locales

- [Verificación de geometría y mandos](avanti-s-contour-checks.json): escala, vértices finitos, siete bisagras, signos, reset, independencia de instancias y motor nominal. Añade ejes rectos en estaciones intermedias y volumen orientado de dos extrusiones cóncavas. Sin fallos; el contador incluye comprobaciones por vértice.
- [Clon local limpio](avanti-s-contour-validation.json): código de estudio superpuesto al clon, sin `references/` ni caché inicial. Verificación, tres renders transparentes y nueve capturas del inspector correctos con el motor fijado suministrado externamente. El rechazo de geometría cambiada sin flag devuelve 2. Invertir el orden de las caras laterales solo en el clon hace fallar las comprobaciones cóncavas.
- Se inspeccionaron visualmente las tres comparaciones, planta, oblicua y flaps a 50°. Chromium verificó cambio de vistas, opacidad, contornos, muestras, alternancia, imágenes cargadas y página de 390 px sin desbordamiento. Se corrigió el desbordamiento inicial del hash en móvil.
- Los originales, versiones de prueba, capturas y composiciones quedan en `references/avanti-s/refinement-v2/`, excluido de Git por la regla existente. El código, las muestras y los resultados numéricos permanecen en el repositorio. No se cambió `.gitignore` ni se ejecutó push.

No se modificó la aplicación como parte de este trabajo ni se ejecutó su suite durante las ediciones concurrentes. Las pruebas pertenecen al proyecto aislado. AV-02 sigue pendiente de integración; no se da por cerrado AV-04 ni se usan estas cuerdas para física.

## Próxima revisión

Contrastar fuselaje y cabina con nuevas cámaras independientes sobre las fotos grandes; conservar estas tres como comparación histórica. Resolver el estabilizador posterior antes de añadir detalle fino. Después: espesor y continuidad de superficies, fences, tren/puertas, librea y barrido de mandos para detectar intersecciones. El fuselaje aún muestra facetas y las alas siguen siendo sólidos de espesor constante, no perfiles aerodinámicos.

Continuación: [revisión 3, fuselaje y cabina](avanti-s-contour-refinement-v3.md), con comparación contra esta revisión y cámaras conservadas.
