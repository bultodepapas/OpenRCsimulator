# P-51D 1/4 · revisión visual 1: siluetas y comparación con fotografías

2026-10-06 · Geometría `p51d-mustang-120-v1` tras la revisión por siluetas ([informe](p51-silhouette-review-v1.md)). Este documento ordena **todo lo que todavía no se parece a un P-51D**, de lo más grave a los detalles, con la evidencia que lo muestra y la corrección propuesta. El plan de ejecución está en [P51-VISUAL-PLAN](../P51-VISUAL-PLAN.md).

Material: tres fotografías de la USAF de dominio público (`references/p51-mustang/photos/`), la foto oblicua aportada por el propietario (local), la tres vistas AN 01-60-3, 36 órbitas del inspector a tres elevaciones y primeros planos. Comparativas lado a lado en [`research/p51/p51-02/visual-review-2026-10-06/`](../../research/p51/p51-02/visual-review-2026-10-06/): [aire-aire desde la izquierda y arriba](../../research/p51/p51-02/visual-review-2026-10-06/usaf-air-to-air-left-above.png), [en tierra, baja izquierda](../../research/p51/p51-02/visual-review-2026-10-06/usaf-ground-left-low.png), [en tierra, izquierda trasera](../../research/p51/p51-02/visual-review-2026-10-06/usaf-ground-left-rear.png), [órbita el +10°](../../research/p51/p51-02/visual-review-2026-10-06/model-orbit-el+10.png), [el −25°](../../research/p51/p51-02/visual-review-2026-10-06/model-orbit-el-25.png), [el +40°](../../research/p51/p51-02/visual-review-2026-10-06/model-orbit-el+40.png), [detalles](../../research/p51/p51-02/visual-review-2026-10-06/model-detail-sheet.png), [cola](../../research/p51/p51-02/visual-review-2026-10-06/model-tail-closeup.png), [vientre](../../research/p51/p51-02/visual-review-2026-10-06/model-belly-closeup.png).

## 1. Dónde estamos (siluetas)

| Vista | Contorno real → modelo | IoU | Residuo que queda |
| --- | --- | --- | --- |
| Perfil (tres vistas) | 7,7 px (≈16 mm sobre el modelo) | 0,87 | patín extendido del dibujo (tramo 6: 20 px), cono de cola |
| Planta (tres vistas) | 15,0 px | 0,83 | raíz alar: extensión del borde de ataque y carenado de salida no modelados (15-19 px); cono (37 px, palas) |
| Foto oblicua del propietario | 8,6 px | 0,80 | cabina ~10 px alta/adelantada; puertas de tren, antena y piloto reales |

Las proporciones generales, posiciones de ala, cabina, toma, cola, cono y tren ya coinciden con el avión real dentro de 1-3 cm de modelo. Lo que sigue son **formas y detalles**, no dimensiones.

## 2. Hallazgos, de grave a detalle

Gravedad: **A** se nota a distancia de vuelo y rompe la identidad; **B** se nota en la vista cercana y en Inicio; **C** detalle de primer plano.

| # | Grav. | Zona | Qué se ve en el modelo | Qué muestra la referencia | Evidencia | Corrección |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | A | Deriva y timón | Trapecio de borde de ataque recto, tope plano, timón-placa amarilla con esquina inferior cuadrada que cuelga bajo el cono; la dorsal es una losa del grosor de la deriva | Borde de ataque curvo que se continúa en el tope redondeado, timón con cabeza redondeada y borde de salida casi recto, tapa inferior que remata el cono con la luz de cola; la dorsal se funde en el lomo | [cola](../../research/p51/p51-02/visual-review-2026-10-06/model-tail-closeup.png), foto 44-74880, tres vistas | Contorno de deriva/timón por puntos leídos de la tres vistas (perfil), sección de perfil aerodinámico en vez de placa, dorsal como loft que se ensancha hasta el lomo |
| 2 | A | Raíz alar | El ala entra recta en el fuselaje: sin extensión del borde de ataque ni carenado de salida | Extensión del BA en la raíz (medida: 0,21 m en el costado bajando a 0,05 m a 0,85 m del eje, escala real) y carenado de salida que sube por el costado del fuselaje | planta de la tres vistas (tramos 5-6), foto aire-aire | Añadir `root_extension` a la geometría (ya medida en `metrology.json`) y un carenado de salida como loft entre el ala y la estación del fuselaje |
| 3 | A | Toma ventral | Bulbo liso pegado al fuselaje; boca redondeada; salida que se cierra en punta | Conducto de lados casi verticales, boca ovalada aplanada separada del fuselaje por el canal de capa límite, cuerpo largo y recto, compuerta de salida rectangular | [vientre](../../research/p51/p51-02/visual-review-2026-10-06/model-belly-closeup.png), foto 44-74880, foto del propietario | Secciones del conducto con exponente alto (lados rectos), canal de 2-3 cm entre labio y fuselaje, compuerta de salida y garganta oscura más profunda |
| 4 | A | Estabilizador y elevadores | Trapecio de puntas cuadradas; de perfil se ve como una línea | Puntas redondeadas, compensación aerodinámica en las puntas de los elevadores, perfil con espesor y unión carenada al fuselaje | planta de la tres vistas, foto aire-aire | Planta por puntos (ya separada la del timón), sección con espesor real, redondeo de puntas |
| 5 | B | Cabina | Burbuja de una pieza con una banda oscura como «marco»; el parabrisas no se distingue | Parabrisas de paneles planos con marco visible y cristal frontal blindado, luego la capota corredera; raíles sobre el umbral y escalón hacia el lomo rebajado | [detalles](../../research/p51/p51-02/visual-review-2026-10-06/model-detail-sheet.png), foto del propietario | Parabrisas como prisma con marcos, capota desde `frame_z`, umbral con raíl, respaldo blindado y colimador |
| 6 | B | Escapes | Seis cilindros negros que sobresalen como un peine (muy visible en planta) | Tubos cortos, poco salientes, altos en el costado del capó, a menudo carenados | planta del inspector, fotos | Acortar a ~1/3, subir al panel superior del costado, opción de carenado |
| 7 | B | Tren principal | Patas cilíndricas verticales, puertas-placa, cubos planos | Amortiguador inclinado hacia delante con tijera, puerta interior grande solidaria con la pata, tapas en el fuselaje, llantas con radios | foto del propietario, 44-74880 | Pata con inclinación y tijera, puerta interior con forma, tapas de pozo, llanta con radios |
| 8 | B | Hélice | Palas finas y apuntadas desde algunos ángulos | Hamilton Standard de pala ancha tipo remo con **cuffs** en la raíz y punta redondeada | órbita el +40, fotos | Planform de pala ancha con cuff, punta redonda |
| 9 | B | Puntas alares | Esquinas vivas con un degradado de espesor | Punta recortada con redondeo en planta | planta, foto del propietario | Redondeo en planta en los últimos 0,1 m |
| 10 | B | Materiales | El «aluminio» lee como plástico gris sin reflejos; sin líneas de panel | Metal natural con reflejos del cielo, paneles y remaches visibles incluso a 1/4 | todas las fotos | Material metálico con mapa de entorno y rugosidad baja; líneas de panel en el acabado (como `appearance.json` del Extra) |
| 11 | B | Esquema | Cono rojo, banda roja, antirreflejo oliva, timón y puntas amarillas (provisional) | El propietario decide; Val-Halla: cola roja, bordes de ataque rojos, cono rojo, metal natural | foto del propietario | Esquema en JSON (colores, bandas, escarapelas genéricas) y sombreador procedimental |
| 12 | C | Cono de cola | Termina en esquina bajo el timón | Remate redondeado con la luz de cola; pozo del patín con puertas | [cola](../../research/p51/p51-02/visual-review-2026-10-06/model-tail-closeup.png) | Tapa redondeada; puertas del patín |
| 13 | C | Toma de carburador | Resalte plano casi invisible | Toma sobre el capó justo tras el cono, boca rectangular redondeada con labio | fotos del morro | Loft propio con boca y garganta (sin salirse de la silueta medida) |
| 14 | C | Alerones y flaps | Línea fina en planta; flaps fijos | Bisagras visibles, flaps que bajan 47° en tierra | tres vistas | Hueco de bisagra marcado; flaps animables cuando la simulación los soporte |
| 15 | C | Piloto | Cabeza y casco grandes, sin asiento ni respaldo | Piloto con casco, gafas, respaldo blindado y colimador | [detalles](../../research/p51/p51-02/visual-review-2026-10-06/model-detail-sheet.png) | Proporción 1/4 (cabeza ~0,06 m), asiento, respaldo, colimador |
| 16 | C | Detalles del ala | Sin cañones, pitot, luces de formación ni tapas de combustible | Tres cañones por ala en el BA, pitot bajo el ala izquierda, luces | fotos | Tres bocas por ala, pitot, luces |
| 17 | C | Fuselaje | Sin antena, sin registro de radiador, sin tapas de pozo | Mástil de antena tras la cabina, puertas del radiador, registros | fotos | Mástil, puertas, líneas de panel |
| 18 | C | Eje de empuje | Hélice paralela al datum | 1°45' de empuje hacia abajo (tres vistas) | tres vistas | Girar el `thrust_frame` visual y el dato físico juntos (P51-06) |

## 3. Qué no cambia

Envergadura, longitud, posiciones del ala, cabina, toma, cola, cono y tren, diedro, vía y cuerdas están medidos sobre la tres vistas con comprobaciones reservadas dentro del 0,7 %, y confirmados por la foto oblicua. Ninguna corrección de este informe debería moverlos; cada paso del plan vuelve a pasar las siluetas para demostrarlo.

## 4. Límites de este análisis

Las fotos de la USAF no tienen cámara ajustada (comparación cualitativa en el ángulo más parecido de la órbita); solo la foto del propietario tiene cámara ajustada y métrica. Las fotos en tierra muestran el avión en tres puntos, el modelo vuela nivelado. No se evalúa aún el acabado real del kit de 1/4 (el propietario no ha elegido esquema). Nada de esto toca la física.
