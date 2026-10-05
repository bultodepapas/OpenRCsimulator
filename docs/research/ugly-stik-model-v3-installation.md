# US-04 y US-07: holguras de mandos y entrega de instalación

2026-10-05 · Modelo visual `jensen-60-nitro-61-v3`. Esta nota acompaña la geometría renderizada y entrega coordenadas para integrar el tren en una etapa posterior. No certifica un avión físico, una instalación comercial ni dinámica de taxi.

## US-04: holguras de superficies móviles

El verificador [model_clearance.gd](../../app/aircraft/model_clearance.gd) examina los triángulos de las mallas que construye el avión, en su pose transformada. `verify_model.gd` lo ejecuta dentro del contrato de modelo y `app/test.sh` lo mantiene en la suite normal. No se limita a comparar posiciones de bisagra.

Se comprobaron nueve combinaciones de elevador (−20°, 0°, +20°) y timón (−25°, 0°, +25°). En cada una se contrastaron las superficies móviles con fuselaje, estabilizador y deriva fijos, las superficies móviles entre sí y, cuando existen, ventral y patín. También se probaron ambos alerones en −20°, 0° y +20° contra los cinco paneles fijos de su lado. El umbral de holgura para superficies móviles es 0,25 mm.

| Comprobación | Resultado |
| --- | --- |
| Pares móviles de cola | 99 poses de pares; 0 fallos en las 9 combinaciones elevador/timón |
| Alerones contra ala fija | 30 poses de pares; 0 fallos en las 6 combinaciones lado/deflexión |
| Menor cota conservadora de holgura en cola | 1,748 mm, fuselaje/timón; separación inferior calculada desde los AABB completos |
| Menor cota conservadora de holgura en ala | 0,681 mm, alerón izquierdo/panel `wing_left_0` a +20°; separación inferior calculada desde AABB |
| Pares de cola que requirieron distancia entre triángulos | Elevador/timón a elevador +20°: 8,519 mm con timón neutro y 8,827 mm con timón ±25° |
| Fixture de contención | Un cubo cerrado de 1 mm dentro del fuselaje se detectó como contenido aunque las superficies estén separadas 42,520 mm |

Las dos cotas mínimas de la tabla son **límites inferiores garantizados por las cajas envolventes**: la distancia real entre mallas es igual o mayor; no son distancias mínimas exactas. Para las tres poses cercanas elevador/timón se calculó la distancia entre triángulos. Cuando las cajas están próximas, el verificador usa distancia triángulo a triángulo y pruebas de interior; una cuadrícula de 1 mm busca puntos que estén dentro de ambos sólidos. El límite de detección por muestreo se estima en 1,8 mm. Si hay contacto/intersección y la cuadrícula no puede resolverlo, la pose falla como no resuelta. El fixture de cubo prueba el caso de un sólido enteramente contenido dentro de otro, donde la distancia a las superficies por sí sola no bastaría.

Los contactos fijos intencionales se informan aparte y no participan en el resultado móvil: fuselaje/estabilizador tiene 27,900 cm³ de solape muestreado; fuselaje/deriva, 0,0255 cm³. El par estabilizador/deriva queda separado por una cota AABB de 10,978 mm. Fuselaje/ventral tiene una separación de superficies calculada de 0,060 mm, y fuselaje/patín una cota AABB de 17,448 mm. El volumen se estima con muestras y no mide profundidad ni resistencia estructural.

La prueba de mutación puso la holgura de bisagra de cola de 4 mm a cero **solo en una copia temporal de `app/`**. El informe detallado detectó 24 fallos de pose/par (18 con penetración muestreada o contacto no resuelto), y el contrato integrado terminó con 510 comprobaciones y 1 fallo. La geometría compartida no se alteró. La prueba de 1 mm para el ancho del recorte central no generó colisión en esta malla y no se usa como evidencia. Se puede repetir con `python3 research/ugly-stik/model-v3/check_clearance_mutation.py`.

El informe completo, poses y regiones están en [clearance-current.json](../../research/ugly-stik/model-v3/clearance-current.json); la mutación está en [clearance-mutation-hinge-gap.json](../../research/ugly-stik/model-v3/clearance-mutation-hinge-gap.json). El registro de la línea base v2 se conserva por separado en [clearance-v2-baseline.json](../../research/ugly-stik/model-v3/clearance-v2-baseline.json). Los resultados corresponden a las mallas actuales y a las poses enumeradas; no comprueban autocruces de una misma malla, herrajes, fuerzas ni deformación.

## US-07: puntos de rueda, ejes y equipos

El intercambio usa metros. El marco visual local es +X derecha, +Y arriba, morro −Z; su origen cerca del cuarto de cuerda no es el CG. El marco físico LE usa `[x_aft, y_right, z_up]`, con el borde de ataque del ala en el centro del fuselaje como origen y `z_up=0` sobre el empuje. El marco físico del cuerpo usa FRD `[x_forward, y_right, z_down]` en el CG de plano.

Con `leading_z = −0,115 m`, `shaft_y = −0,005 m` y `cg_le = [0,1209, 0,0] m`, las conversiones son:

```text
visual → LE:       [z_model − leading_z, x_model, y_model − shaft_y]
LE → body-CG FRD:  [cg_x − x_aft, y_right − cg_y, cg_z − z_up]
LE → visual:       [y_right, shaft_y + z_up, leading_z + x_aft]
```

El CG de plano corresponde a `[0, −0,005, 0,0059] m` en el modelo visual. `app/render/frames.gd` coloca la raíz para que ese punto caiga en el CG simulado. Las posiciones siguientes son puntos locales antes de aplicar la transformación de actitud y raíz. El contacto nominal es el punto inferior de una rueda circular no deformada, no una colisión de física.

| Rueda | Radio | Eje en modelo visual | Contacto en modelo visual | Eje en LE `[x_aft,y_right,z_up]` | Contacto en LE |
| --- | ---: | --- | --- | --- | --- |
| Principal izquierda | 0,03810 m | `[−0,18, −0,22, 0,10]` | `[−0,18, −0,2581, 0,10]` | `[0,215, −0,18, −0,215]` | `[0,215, −0,18, −0,2531]` |
| Principal derecha | 0,03810 m | `[+0,18, −0,22, 0,10]` | `[+0,18, −0,2581, 0,10]` | `[0,215, +0,18, −0,215]` | `[0,215, +0,18, −0,2531]` |
| Morro | 0,034925 m | `[0, −0,22, −0,251276]` | `[0, −0,254925, −0,251276]` | `[−0,136276, 0, −0,215]` | `[−0,136276, 0, −0,249925]` |

Las coordenadas body-CG FRD de los ejes son `[−0,0941, ±0,18, +0,215] m` para el tren principal y `[+0,257176, 0, +0,215] m` para el delantero. Las coordenadas de contacto en ese marco, junto con todos los puntos, radios y fuentes, están en [equipment-handoff.json](../../research/ugly-stik/model-v3/equipment-handoff.json). El ancho de vía visual es 0,36 m, igual al alcance lateral guardado en el tamaño del elemento de tren principal en física.

Los ejes de giro de las ruedas son paralelos a X; el pivote de dirección pasa por el eje de la rueda delantera y usa +Y. `build()` devuelve `gear.left`, `gear.right`, `gear.nose` y `gear.steering`. `AirplaneBuilder.apply_gear(airplane, wheel_angles, steering_rad)` coloca los ángulos recibidos directamente en rotación local X de rueda y rotación local Y de dirección, en radianes. No genera velocidad, fuerza de contacto ni integración automática con física. Si física define giro positivo como rodar hacia delante por −Z, el adaptador de intercambio debe pasar el ángulo con signo negativo; si define dirección positiva como guiñada a la derecha, también debe invertir el signo antes de la rotación +Y, que orienta el morro hacia −X.

Las posiciones físicas de los elementos de tren son centroides de masa, no ejes visuales: el centroide delantero `[-0,17, 0, −0,12] m` menos el eje visual `[-0,136276, 0, −0,215] m` difiere `[-0,033724, 0, +0,095] m`. El centroide del tren principal `[0,137, 0, −0,1] m` difiere del punto medio de ejes visuales `[0,215, 0, −0,215] m` en `[-0,078, 0, +0,115] m`. No se deben mover las ruedas para igualar esos centroides. La coherencia de ancho de vía no convierte las posiciones en puntos de anclaje físicos.

El motor visual es una envolvente genérica .61 de un cilindro, provisional y sin marca elegida; el manual O.S. MAX-61FX informó su escala, no una selección. El inventario físico guarda un O.S. MAX-61FX de 0,55 kg como hipótesis de masa, no como identidad del modelo visual. El centro visual aproximado del cárter es `[-0,234776, 0, 0] m` en LE frente a `[-0,226, 0, 0] m` en inventario. Soporte y escape son simplificados; no se han cotejado con planos de un motor, montaje, tanque o carenado seleccionados. La línea de cortafuegos al plano de hélice mide 117 mm en el modelo visual.

El centro visual de la hélice está en `[-0,293276, 0, 0] m` LE; el inventario físico coloca su centro de masa en `[-0,286, 0, 0] m`, una diferencia visual menos física de `[-0,007276, 0, 0] m`. Ambos diámetros nominales son 0,3048 m. El disco barre un plano normal a Z y el empuje apunta por −Z.

Para igualar los contactos de las tres ruedas circulares rígidas, el cálculo de pose requiere rotación X de `−0,0090386 rad` (`−0,5179°`). La diferencia residual del contacto delantero es cero y el borde inferior del disco de hélice queda 96,10 mm sobre el suelo calculado. Esto supone neumáticos indeformables, ejes paralelos y ninguna suspensión o dinámica de contacto; es una comprobación geométrica estimada, no validación de despegue, aterrizaje o taxi.

## Reproducción y procedencia

Desde la raíz del repositorio:

```bash
app/test.sh
"$(app/get-godot.sh)" --headless --path app --script ../research/ugly-stik/model-v3/verify_clearance.gd \
  -- --output="$PWD/research/ugly-stik/model-v3/clearance-current.json"
python3 research/ugly-stik/model-v3/equipment_handoff.py
python3 research/ugly-stik/model-v3/check_clearance_mutation.py
```

La corrida registrada de `app/test.sh` pasó la protección float64, parseo de todos los scripts, pruebas de aplicación y contrato de modelo: 510 comprobaciones del modelo, 0 fallos; suite completa con salida 0. El informe de holguras registra estos SHA-256: geometría JSON `89c7bb667dbee4022cb5041d23a524ce80ae04a882ad5508437e999f13a2d108`, constructor `7c24196b2174aeb2443ea47c9dd746b1f46b6329907b1f6491acd456c06e93c1`, verificador `f648b9124e5accea16e7a678591d12917dd9bf3dc431683d86af35400b3e59cc`. El JSON de entrega añade hashes del dato físico, del adaptador de render y del constructor. Reejecutar los generadores actualiza la procedencia cuando cambien sus fuentes.
