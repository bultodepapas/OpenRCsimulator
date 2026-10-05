# Ensayo del modelo Ugly Stik v1

Este ensayo convierte el contrato del avión en comprobaciones repetibles sobre el constructor de Godot. Comprueba la geometría construida y los nodos que moverán los controles; no certifica aerodinámica ni validez de vuelo.

## Ejecución

```sh
cd app
godot --headless --path . --script res://aircraft/verify_model.gd
```

El proceso termina con código distinto de cero si falla una condición y señala cada comprobación fallida. Se añadió como ensayo aislado para poder repetirlo durante los cambios del modelo. Todavía no se ha corrido contra el nuevo constructor; el resultado de la primera ejecución se debe registrar aquí cuando la geometría esté lista.

## Qué comprueba

- La interfaz contiene `airplane`, `propeller` y un pivote `*_hinge` por cada superficie. Cada superficie tiene una sola malla con su nombre, bajo el pivote correspondiente y con geometría detrás de la bisagra, hacia `+Z`.
- Los nombres de nodos son únicos. Cada `MeshInstance3D` contiene triángulos, límites con área y vértices finitos; los vértices también siguen siendo finitos al recorrer toda la jerarquía.
- La extensión total de la geometría en el eje local `X` es **1.524 m ± 0.006 m**. El valor central convierte las 60 in de envergadura impresas en el plano Jensen oz1253. La tolerancia de 6 mm es un umbral práctico de aceptación para esta malla, no una incertidumbre publicada por el plano. La elevación de punta de 1½ in está incluida en la tolerancia al medir la proyección horizontal del modelo.
- Los alerones cuelgan de marcos de ala distintos del avión y sus marcos llevan diedro en sentidos opuestos. Cada mando se prueba con entrada `−1` y `+1`, mediante `Commands.hinge_rotations()` y `AirplaneBuilder.apply_surfaces()`. El borde de salida medido en el espacio global debe moverse con el signo esperado, incluso con el avión rotado y trasladado.
- El origen de cada bisagra y el marco fijo que la sostiene permanecen inmóviles al mover las superficies. Al volver a mando neutro, pivotes y puntos de borde de salida regresan a su posición inicial.
- Girar `propeller` alrededor de su eje local mantiene el origen del cubo en la misma posición global.

Los puntos de prueba están expresados en el marco local de cada pivote: `Vector3(0, 0, 0.04)` para alerones y elevador, y `Vector3(0, 0.04, 0.04)` para timón. Son sondas de signo y recorrido; no reemplazan el contorno medido de los mandos. Las entradas `±1` prueban los límites definidos actualmente en `app/spec.gd`, no recorridos tomados del plano Jensen.

## Condiciones del constructor

El constructor debe devolver el diccionario documentado por `app/render/airplane.gd`: raíz `airplane`, nodo `propeller` y diccionario `hinges` con `aileron_left`, `aileron_right`, `elevator` y `rudder`. Cada `*_hinge` es una bisagra dinámica bajo el marco fijo de su ala o cola. La geometría fija de cada marco conserva su diedro; los comandos solo rotan el pivote. La malla de una superficie se llama igual que la clave y vive bajo su bisagra.

La orientación del simulador es `+X` derecha, `+Y` arriba y `−Z` morro. Las superficies se prolongan hacia atrás por `+Z`. Por eso una rotación alrededor de `+X` lleva el borde de salida hacia abajo con ángulo positivo, y la función de mandos traduce elevador/alerones positivos a una rotación local negativa. El timón usa el eje `+Y` para llevar su borde de salida a la derecha.

## Lectura del resultado

Un fallo de extensión o signo es una incompatibilidad entre el modelo y el contrato utilizable por los mandos, aunque la silueta se vea bien. Un fallo de los marcos de ala indica que el diedro se horneó en una bisagra que los comandos sobrescriben, o que la jerarquía no conserva el eje local del alerón. Un fallo de extensión de malla puede revelar un origen de pivote incorrecto o una superficie modelada hacia el morro.

Después de validar esta primera geometría, conectar la ejecución al conjunto habitual de verificaciones de `app/test.sh` y conservar el primer resultado en esta nota. La tarea paralela de física y el `LEARNINGS.md` principal permanecen bajo su responsable; la lección que debe transferirse es que comprobar puntos bajo marcos con diedro detecta errores que un ensayo plano de B5 no puede descubrir.
