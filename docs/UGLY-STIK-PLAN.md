# Ugly Stik: plan de modelado en paralelo

Fecha: 2026-10-05. Estado: **propuesta basada en inspección del repo y referencias; todavía no se ha construido un modelo nuevo**.

La siguiente entrega útil es un Ugly Stik sencillo y reconocible, con superficies articuladas y dimensiones trazables. Se puede preparar fuera del simulador mientras el otro desarrollador completa los controles y la comparación de motores. Primero corregir la silueta; después añadir los detalles que realmente se vean.

Este documento desarrolla el trabajo de referencias de **D1**, el contrato visual necesario para **B5**, la futura integración de **B7** y la legibilidad de **D7/Gate 2** de [ROADMAP.md](../ROADMAP.md). No cambia sus prioridades ni decide Gate 1.

## Punto de partida

- Hay dos modelos procedurales equivalentes, construidos con cajas y cilindros, en [three.js](../prototypes/stage0/three/src/render/airplane.ts) y [Godot](../prototypes/stage0/godot/render/airplane.gd). Ya separan las superficies mediante pivotes. Conviene conservar esa inversión.
- La geometría del modelo inicial vive en un archivo de especificación por motor. Las medidas de cola, fuselaje y superficies son aproximaciones visuales declaradas en [SPEC.md](../prototypes/stage0/SPEC.md).
- Al comenzar esta revisión, el roadmap llegaba a B4. Durante la revisión aparecieron código y capturas de B5 del otro desarrollador. Esto es una lectura de un espacio de trabajo activo, no una certificación de su estado final.
- [DECISIONS.md](../DECISIONS.md) usa provisionalmente **Jensen Das Ugly Stik 60**, con tren triciclo. Las referencias locales incluyen también Grid Leaks/BNPS, RCM, un redibujo CAD y Great Big Stik: su parentesco no hace intercambiables sus medidas.
- La revisión de las imágenes y los archivos está en [el catálogo local](research/ugly-stik-local-audit.md). El contraste documental está en [las fuentes por variante](research/ugly-stik-sources.md).

## Reparto para no interferir

| Frente | Trabajo | Entrega / frontera |
| --- | --- | --- |
| Desarrollo activo | Controles B5, panel, capturas oficiales, comparación, selección de plataforma | Sigue en los archivos actuales del simulador |
| Este frente, ahora | Catalogar referencias, contrastar medidas y planear el modelo | Archivos nuevos `docs/UGLY-STIK-PLAN.md` y `docs/research/ugly-stik-*` |
| Este frente, siguiente implementación propuesta | Preparar geometría original y evidencias fuera de la escena activa | Carpeta nueva propuesta `assets/aircraft/ugly-stik-60/`; confirmar que no esté ocupada al comenzar |
| Integración posterior | Conectar el recurso terminado con el constructor del motor elegido | Una entrega coordinada sobre una revisión estable del trabajo del desarrollador |

En esta revisión no se ejecutan capturas que sobrescriban las suyas, ni instalaciones, cambios de rama, commits o modificaciones del índice. Las referencias originales conservan sus rutas. Las lecciones de esta inspección quedan al final del catálogo; el desarrollador puede incorporarlas a `LEARNINGS.md` cuando termine su edición.

## Secuencia pequeña y comprobable

Las etiquetas siguientes son subtareas de los pasos existentes, no fases nuevas del roadmap. Cada fila es una entrega separada.

| Orden / paso relacionado | Trabajo concreto | Prueba de terminación |
| --- | --- | --- |
| 1 · D1, referencias | **Realizado en esta revisión:** inventariar imágenes, planos y CAD; identificar variantes y duplicados | Catálogo con las 14 imágenes inspeccionadas, PDF renderizado y manifiesto de 39 archivos con SHA-256 |
| 2 · D1, medidas | Resolver qué plano gobierna cada medida Jensen; aclarar el área 720/723 in²; registrar envergadura, longitud y puntos de referencia. Lo no demostrado queda provisional | Tabla con valor original, unidad, conversión SI, variante, fuente, método e incertidumbre; ninguna mezcla silenciosa |
| 3 · B5, contrato del modelo | Escribir el inventario de piezas, ejes y pivotes compatible con los nombres actuales; conservar las posiciones existentes como estimaciones hasta sustituirlas | Diagrama de jerarquía y tabla de puntos/ejes; neutro y comandos positivos con sentido inequívoco |
| 4 · D1, silueta del fuselaje | Construir un fuselaje ligero a partir de unas pocas secciones, afinado hacia la cola; morro y zona del motor como volúmenes simples | Vistas superior y lateral ortográficas con cotas y referencia identificada; envolvente longitudinal comprobada |
| 5 · D1/B5, ala | Añadir ala con borde de ataque redondeado, espesor y borde de salida; alerones separados. Un perfil visual aproximado lleva etiqueta `estimated` | Vista frontal y sección; envergadura comprobada; alerones giran desde sus bisagras sin desprenderse |
| 6 · D1/B5, cola | Modelar contorno del estabilizador y conjunto de deriva/timón redondeado; elevador separado | Vistas lateral y superior; comprobar contorno y bisagras en neutro y ambos extremos de recorrido |
| 7 · D1, equipo visible | Añadir patas del tren triciclo, ruedas, hélice y representación sencilla del motor instalado provisional | Vista tres cuartos y lateral: ruedas unidas, plano de hélice y piezas bien situados; sin atribuirles masa real |
| 8 · D7/Gate 2, apariencia | Probar rojo/blanco y contraste entre intradós y extradós con la misma geometría | Capturas equivalentes de frente, costado, arriba, abajo y virajes; comparación a distancias conocidas |
| 9 · B7, integración | Después de Gate 1 y del cierre del cambio concurrente, sustituir el modelo en el motor ganador manteniendo su interfaz | Pruebas de ejes y superficies existentes, nueva captura neutra/deflectada y escala del recurso importado |

**Primer paso de implementación recomendado:** tabla de medidas y contorno lateral/superior del fuselaje en la carpeta aislada. Da una base revisable para modelar sin modificar los controles. Si una cota secundaria sigue sin fuente, se estima explícitamente y se continúa; no hace falta resolver todavía masa, inercia o aerodinámica.

Antes de cada integración se relee la revisión vigente de `SPEC.md` y la interfaz del constructor. La prueba de una fila acompaña su futuro commit. Nada de esta tabla marca B5, B7 o D1 como completados.

## Cómo modelaría

Empezaría con geometría paramétrica pequeña y editable: secciones para el fuselaje, un contorno de perfil extruido para el ala y contornos planos con espesor para la cola. Es una continuación natural del modelo de cajas actual. Las costillas y largueros de los CAD ayudan a entender la forma, pero no necesitan convertirse en miles de piezas visibles durante el vuelo.

El script y sus medidas serían la fuente editable. Se decidiría el formato de entrega al comprobar el primer modelo. Si aporta portabilidad, se exportaría una copia GLB; Blender puede entrar después para revisar formas y materiales. No hace falta introducir ahora un generador universal de aeronaves ni una dependencia nueva en los prototipos.

| Pieza | Qué tomar de las referencias | Qué conservar como desconocido |
| --- | --- | --- |
| Fuselaje | Caja delantera, transición superior y estrechamiento hacia la cola | Estaciones métricas no calibradas, densidad y distribución de masa |
| Ala | Planta casi rectangular, perfil grueso visible, puntas y alerones articulados | Perfil aerodinámico exacto, incidencia, diedro y efectividad de alerones hasta medirlos |
| Cola | Contorno redondeado vertical, estabilizador y elevador separados | Área y brazo de cola, reparto exacto fijo/móvil hasta digitalizar la variante correcta |
| Tren | Configuración triciclo del Jensen y ubicación visual aproximada | Rigidez, amortiguación, fricción y puntos físicos de contacto de fase E |
| Motor/hélice | Volúmenes reconocibles y giro alrededor del eje longitudinal | Instalación definitiva y rendimiento nitro de fase G |
| Decoración | Rojo/blanco visible en las referencias | Efecto sobre la legibilidad hasta comparar capturas; el intradós oscuro actual es una decisión visual |

No usaría el Great Big Stik escalado como sustituto automático del Jensen: las imágenes muestran una instalación de motor diferente y un CAD de construcción, cuya correspondencia geométrica no está validada.

## Contrato para entregar al desarrollador

- Mantener `airplane`, `propeller`, `aileron_left`, `aileron_right`, `elevator`, `rudder` y sus nodos `*_hinge`. La interfaz existente devuelve raíz, hélice y mapa de bisagras; el recurso deberá poder conectarse a ella.
- En la frontera con el simulador: metros; morro hacia `−z`, ala derecha hacia `+x`, arriba `+y`, según `SPEC.md`. Documentar también el origen geométrico: hoy está **aproximadamente** en el CG, no constituye una medición del CG.
- Distinguir la posición neutra de cada pieza del pivote que recibe la deflexión. El morro y las ruedas no cambian de orientación al mover mandos.
- A `roll=+1`, borde de salida derecho arriba e izquierdo abajo; a `pitch=+1`, elevador arriba; a `yaw=+1`, timón hacia la derecha del avión. Validar posiciones finales, no solo signos de ángulos internos.
- Guardar junto a la geometría las dimensiones visuales y su procedencia. Los parámetros físicos de D1 siguen siendo datos independientes.
- Si se usa GLB, documentar explícitamente la conversión: glTF define el frente hacia `+Z`, distinto del morro `−z` actual. Verificar orientación, escala y jerarquía después de importar; los nombres tampoco son únicos por obligación del formato. [Especificación glTF 2.0](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#coordinate-system-and-units).

## Evidencia visual que conviene preparar

Una pequeña escena de inspección separada de la trayectoria de vuelo, con fondo uniforme, vistas ortográficas superior/lateral/frontal y una vista tres cuartos. Así se puede distinguir un error de geometría de uno de cámara. Añadir después las capturas desde el piloto usando el FOV y resolución ya fijados.

Para legibilidad propongo muestras a **20, 50 y 100 m**, en neutro y virajes a izquierda/derecha; son distancias de prueba elegidas para cubrir cercano/medio/lejano, no límites operacionales medidos. Registrar distancia, actitud, FOV, resolución y tamaño del avión en píxeles. El usuario valorará si reconoce morro/cola y arriba/abajo. No prometer una mejora solo por añadir polígonos.

Cada entrega del recurso incluiría una tabla de dimensiones y origen, capturas comparables y un recuento de triángulos/materiales/tamaño de archivo. Fijar un presupuesto de rendimiento después de la primera medición; la VM con renderizado por software no representa la GPU del usuario.

## Otros avances útiles, por prioridad

1. **Orden lógico antes de mover archivos:** usar los identificadores del catálogo para citar fuentes. El directorio actual tiene un espacio final y varios nombres genéricos; un traslado físico deberá ser una tarea coordinada posterior.
2. **Auditoría CAD acotada:** abrir el Classic Ugly Stick y el `.3dm` solo para verificar unidades, vistas y contornos. Interrumpir esa exploración si se convierte en reconstrucción del CAD: ya hay suficiente información visual para un modelo original simple.
3. **Preparar D1 sin programar física:** lista de componentes y posiciones aproximadas de motor, depósito, batería y servos. Dejar masa/CG/inercia pendientes donde no haya evidencia; no inferirlos de una malla maciza.
4. **Vista de estructura como opción futura:** los dibujos de costillas podrían inspirar un modo educativo de inspección. Su valor se evalúa después de tener un avión reconocible y controlable.

## Comprobaciones de esta entrega documental

Se leyeron las decisiones, el roadmap, el stack, las lecciones, SPEC, COMPARISON, las secciones pertinentes del cuaderno de investigación y ambos constructores del avión. Se inspeccionaron las 14 imágenes locales y el PDF completo. Se verificaron duplicados por SHA-256 y metadatos DXF/3DM en lectura. La auditoría explica sus límites. Esta entrega no ejecutó pruebas del simulador ni modificó su modelo.
