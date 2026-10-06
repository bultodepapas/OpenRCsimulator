# Calidad visual del simulador: dirección, herramientas y entregas

2026-10-05 · Revisado contra el código el **2026-10-06**, con **ensayos prácticos de herramientas y assets** añadidos en §6.2. **VQ-01a, VQ-01b y L5 implementados y verificados; siguiente paso L6a.** Preferencia del propietario: «una mezcla de todos, con opciones para subir calidad»: realismo RC, presentación limpia y buen rendimiento, con calidad escalable. Equipo disponible para probar: **Ryzen 9 5900X, RTX 3090 y 64 GB RAM**. Resolución, sistema operativo y equipo modesto de referencia todavía sin definir.

La recomendación es construir **un campo RC reconocible, un avión con materiales convincentes y una imagen estable en movimiento**, conservando Compatibility como base. Primero composición, escala, contraste y materiales; después efectos caros. Forward+ merece una comparación controlada, no una migración asumida.

Este documento coordina [ROADMAP](../ROADMAP.md), [paisaje](LANDSCAPE-PLAN.md), [Extra 300](EXTRA-300-PLAN.md), [acabado Stik](UGLY-STIK-VISUAL-PLAN.md), [menú](MENU-PLAN.md), [humo](SMOKE-PLAN.md) y [viento](WIND-PLAN.md). Los pasos existentes conservan sus IDs. Los IDs **VQ** identifican coordinación, verificación y presentación; L, EX y UI conservan la propiedad de sus entregas. La revisión original no implementó pasos; [VQ-01a ya está cerrado con evidencia](research/visual-quality-implementation/VQ-01a/README.md). La secuencia ejecutable está en §4, los contratos en §11 y la revisión con evidencia en §12. Estos apartados precisan las propuestas anteriores; no sustituyen Gate 2 ni los gates físicos.

## 1. Qué tenemos realmente

La investigación inicial revisó scripts, configuración, planes y fuentes oficiales, y produjo **tres capturas de referencia**: [piloto](research/visual-quality-baseline-2026-10-05/pilot.png), [inspección](research/visual-quality-baseline-2026-10-05/inspect.png) y [horizonte](research/visual-quality-baseline-2026-10-05/horizon.png). [Protocolo y límites](research/visual-quality-baseline-2026-10-05/README.md).

| Evidencia local | Consecuencia |
| --- | --- |
| [get-godot.sh](../app/get-godot.sh) y binario ejecutado: 4.7.2-stable; [project.godot](../app/project.godot): Compatibility | Evaluar herramientas contra esta combinación concreta |
| `msaa_3d=2` | Ya es **MSAA 4×**, no 2×. El valor es un enum: [Viewport](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#enum-viewport-msaa) |
| [atmosphere.gd](../app/render/atmosphere.gd): cielo propio, ACES, exposición, bruma, reflejo de cielo y nubes | L1–L4 ya existen; afinar con pruebas A/B, sin volver a implementarlos |
| [field.gd](../app/render/field.gd) y [field_loader.gd](../app/data/field_loader.gd), L5: campo desde JSON validado, compartido por Inicio y vuelo | Cada escena conserva su cámara, avión y reloj; datos inválidos impiden arrancar la sesión. [Evidencia L5](research/visual-quality-implementation/L5/README.md) |
| [ground.gdshader](../app/render/ground.gdshader): tile de hierba en coordenadas mundiales con mipmaps y muestreo anisotrópico | Conservar ese filtrado; falta romper repetición, introducir superficies y transiciones |
| [shadow.gd](../app/render/shadow.gd): máscara planar genérica, geometría/datum propios del Stik | Extra necesita su propia silueta; alabeo extremo y suelo irregular requieren otro tratamiento |
| [pilot_camera.gd](../app/render/pilot_camera.gd): seguimiento y autozoom; horizonte puede salir del cuadro | Calidad incluye encuadre y lectura del vuelo, además de materiales |
| [airplane.gd](../app/render/airplane.gd) sigue construyendo Stik; [extra_300s_model.gd](../app/aircraft/extra_300s_model.gd) se declara preview EX-02 | No presentar las capturas del Stik como validación del Extra; coordinar EX-03/04/10 |
| Captura piloto: 101 draw calls visibles, 46.842 primitivas; horizonte: 2 y 4 | El escenario está casi vacío. Medir avión y paisaje por separado; estos números no son FPS ni presupuesto universal |

El árbol contenía cambios concurrentes. El baseline es del 2026-10-05; no retrata el Inicio añadido después. Las capturas corresponden a `--scripted`, 1280 × 720, llvmpipe; no son un benchmark ni un ensayo de vuelo físico. No se modificó `app/` en esta entrega.

## 2. Dirección artística que une las tres prioridades

**Realismo en lo que informa al piloto:** proporciones, materiales, tamaño de pista y árboles, dirección del sol, altura percibida, orientación superior/inferior del avión y viento coherente. **Simplificación deliberada en lo que distrae:** microdetalle distante, ruido del terreno, HUD, vegetación de fondo y reflejos que borran la pintura.

[Hoja de referencia de VQ-01b](research/visual-quality-implementation/VQ-01b/REFERENCES.md): fotos licenciadas de campo RC/acabado y tres encuadres de aceptación —piloto, pasada baja e inspección—. Cada referencia debe responder una pregunta concreta. No usar una imagen promocional con lente, exposición o profundidad de campo distintas como objetivo del vuelo normal.

La misma identidad se conserva en todos los perfiles: paleta natural moderada, pista claramente diferenciada, árboles de tamaños variados, horizonte con huecos y blancos del avión sin saturación. Una base estilizada reduce ruido; el nivel alto añade respuesta de materiales, geometría cercana y sombras. No se mantienen tres estilos artísticos independientes.

## 3. Renderizadores y perfiles de calidad

La documentación **4.7** confirma que Compatibility dispone de SSAO simplificado y glow, con menos controles. No aplicar el consejo antiguo «Compatibility no tiene SSAO/bloom». [Entorno y postproceso](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html).

| Función | Compatibility actual | Ruta de calidad superior |
| --- | --- | --- |
| Materiales PBR, cielo, niebla tradicional, ReflectionProbe, MSAA | Aprovechables ya | Mantener los assets y volver a calibrar el resultado |
| SSAO / glow | Disponibles con implementación limitada | Ensayo A/B; no activarlos por defecto por su nombre |
| Decals, niebla volumétrica, SSR, SDFGI, TAA, FSR2 | No disponibles en este backend | Evaluar en Forward+ únicamente donde sean útiles |
| CompositorEffect / compute | Sin RenderingDevice | Ensayos Forward+; evitar que sean requisito del vuelo básico |
| Web | Ruta Compatibility | Forward+ no sustituye esta ruta |

Fuente de capacidades: [matriz de renderizadores Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html). Mobile es una tercera alternativa para otra matriz de hardware; no implica automáticamente más calidad que Compatibility y no se propone mantenerla ahora.

### Perfiles que se pueden implementar

Bajo, Equilibrado y Alto comparten **Compatibility**, contenido físico y referencias de vuelo. Equilibrado conserva MSAA 4× y es candidato por defecto solo tras VQ-06. Antes de ese gate se mantiene el comportamiento actual. **Ultra no se muestra como perfil soportado:** es el nombre de la comparación Forward+ de VQ-07.

| Ajuste inicial | Bajo | Equilibrado | Alto |
| --- | --- | --- | --- |
| MSAA | 2×; Off disponible como ajuste individual | 4× actual | 4×; 8× solo como opción medida |
| Resolución 3D | Nativa | Nativa | Nativa |
| Horizonte, pista, árboles de referencia y objetos con colisión | Mismas posiciones y siluetas esenciales | Iguales | Iguales |
| Hierba ornamental, tras L11a | Off | 50 % de las instancias cercanas | 100 % |
| Distancia de hierba | No aplica | Hasta 30 m; desvanecimiento geométrico 22–30 m | Igual; aumentar solo tras medición |
| Texturas y materiales de la primera entrega | Mismos recursos importados | Mismos recursos importados | Mismos recursos importados |
| Sombra del avión | Planar existente por defecto | Igual | Igual hasta aprobar VQ-04b |
| Glow, SSAO, GI y reflejos nuevos | Off | Off | Off hasta aprobar su A/B |
| Humo | No hay control hasta integrar SM | Definido en el plan SM | Definido en el plan SM |

Porcentajes y distancias son **decisiones de diseño provisionales**, no resultados de benchmark. La selección de hierba es un subconjunto determinista por instancia: no volver a sortear posiciones al cambiar calidad. Si un ajuste todavía no tiene consumidor, no se ofrece en UI. Al principio los perfiles solo difieren en MSAA; el control de vegetación se incorpora con L11a. No vender Alto como una mejora de materiales inexistente.

**Texturas:** se elimina la promesa de un límite global 1K/2K/4K que cambie al vuelo. Hoy hay texturas generadas por código y no existe un cargador de variantes. La primera entrega usa un atlas de árboles 1K y límites de paisaje de §8. Si VQ-02 demuestra necesidad, generar variantes offline, registrar qué material las consume y medir memoria tras liberar la anterior; aplicarlas al cargar la siguiente escena. Los 4K de primer plano del avión requieren un presupuesto separado. Escala 3D/reescalado queda fuera del primer panel; se añade solo con ensayo de lectura y UI a resolución nativa.

**Persistencia:** ampliar el único `app_state/preferences.gd` de UI-07; no crear otro archivo de ajustes. Versión, validación, migración, precedencia de CLI y errores se especifican en §11. Ajustes en vuelo se aplican desde pausa después de UI-02. Cambiar preset no puede alterar fuerzas, obstáculos, viento, reloj, entradas o trazas.

**Gate Forward+:** ejecutar escena, resolución y trayectoria iguales; separar un A/B sin recalibrar de otro con color recalibrado, registrando el delta de parámetros. Medir legibilidad, estabilidad temporal, CPU/GPU, memoria y primera presentación; probar export en cada plataforma que vaya a declararse soportada. El cambio de backend requiere arranque y recuperación a Compatibility: no se implementa como slider ni entra en VQ-06. Sin resultados favorables, VQ-07 cierra como «pospuesto» y los tres perfiles siguen funcionando.

## 4. Secuencia de implementación y cierre

**Primera entrega: un horizonte arbolado legible, con claros, en Inicio y vuelo.** No necesita Extra volable, hierba cercana, colinas, terreno físico ni plugins. Ruta: **VQ-01a → VQ-01b → L5 → L6a → L6b → L6c**. Cada ID se entrega por separado. VQ-01 es el paraguas de a/b; VQ-04 y VQ-06 también se dividen para no mezclar infraestructura con decisiones visuales.

| Paso | Cambio concreto y dueño | Depende de | Prueba que permite cerrar |
| --- | --- | --- | --- |
| VQ-01a ✅ · L0 | Render/tests: proteger el harness contra PNG viejos y separar la escena de atmósfera vacía de las vistas del campo completo | Ninguna nueva | Forzar fallo/timeout en copia con PNG viejo debe fallar; producir PNG/manifest nuevos debe pasar. Mantener controles L1–L4 en fixture vacío y añadir vistas del campo sin relajar sus límites. **Cerrado:** [15 pruebas, mutaciones, 46 capturas y suite](research/visual-quality-implementation/VQ-01a/README.md) |
| VQ-01b ✅ · L0/D7 | Render/tests: referencias visuales, casos fijos y extensión mínima del logger existente | VQ-01a | Manifiesto de casos de §8, capturas iniciales, datos crudos de frametime y calentamiento configurable. El reporte identifica ruta/backend/perfil; un vuelo con radio no se etiqueta como replay fijo. **Cerrado:** [66 casos nuevos, muestras crudas y prueba de integración](research/visual-quality-implementation/VQ-01b/README.md) |
| L5 — **completado** | Campo: loader `openrc-field v1`, archivo actual y constructor compartido entre Inicio y vuelo | VQ-01b | [Prueba L5](research/visual-quality-implementation/L5/README.md). Números actuales intactos; loader rechaza tipos/unidades/no finitos/rectángulos inválidos; paridad de capturas y traza; recurso incluido en export Linux/Windows/macOS |
| L6a | Assets: adaptar las tres muestras Kenney ensayadas (§6.2); alternativa ez-tree si falla su silueta. ≤ 1k triángulos por malla, atlas 1024²; corregir metalicidad, paleta y escala | L5 | Derivados GLB sin errores Khronos, procedencia/SHA y A/B tras conversión; importar desde clon limpio y exportar sin rutas externas; bake repetible, padding y mips inspeccionados. Los originales defectuosos no pasan al runtime |
| L6b | Campo: posiciones offline y ocho sectores MultiMesh con huecos; una superficie/material por grupo de cards, hasta tres especies | L6a | SHA de posiciones; cuatro azimuts × dos elevaciones; bounds completos; ≤ 24 draws reales del pase visible, anotando pases extra. Misma distribución en todos los presets, fuera de pista/calle de vuelo; sin colisiones nuevas |
| L6c | Render/playtest: lectura ante árboles y aceptación de la primera entrega | L6b | Protocolo de §8 y resultados humanos registrados. Si falla, reducir densidad/contraste o abrir huecos antes de añadir más detalle |
| L9a → L9b → L9c | Campo: probar paridad del shader ya existente; anti-tiling; superficies/pista desde L5, cada ID separado | L5; aterrizar después de L6c | L9a no reescribe L2: valida lo existente. L9b fija umbral de autocorrelación antes del cambio. L9c conserva contraste de borde y elimina el plano duplicado solo tras el A/B |
| VQ-02 · EX-10/Stik | Modelos: un acabado a la vez (pintura, caucho, metal, cabina), UV/tangentes antes de normales | VQ-01b; EX-04 solo para validación articulada del Extra | A/B de mismo modelo/luz a 20/50/100 m y primer plano; mejora identificada, sin clipping/parpadeo. Previews no se declaran vuelo validado |
| L8 | Campo: árboles 3D cercanos, coherentes con cards | L6c | LOD fijo desde estación del piloto; histéresis para cámaras móviles; silueta y ausencia de desaparición al borde del frustum. IoU objetivo del plan de paisaje, calibrado antes de ajustar assets |
| L11a → L10 → L11b | Campo: hierba cercana, objetos de escala y arbustos, por pasos | L9c; L10 también consume L5 | Presupuesto por componente; hierba excluida de pista, prueba de borde con/sin hierba; dimensiones/procedencia de props; mantener siluetas esenciales en Bajo |
| L7 | Campo: bosque y colinas distantes | L6c **y salida de colinas de L13a** | ≤ 3 draws extra, horizonte continuo con claros y sin colisiones implícitas. No bloquea la primera entrega; no adelantar todo L12/L13 para conseguirla |
| VQ-03 · D7 | Cámara: ensayo optativo de composición con horizonte | VQ-01b, L6c | Avión siempre dentro de margen definido; sin retardo de puntería; zoom continuo a 30/60/144 fps; volver al modo actual. Si no mejora lectura, cerrar como descartado |
| VQ-04a · EX-10 | Modelos/render: máscara y datum de sombra por avión | VQ-01b; EX-03/04 para Extra | Planta y offset correctos; pasada baja, invertido y cuchillo; Stik intacto; modo off sin doble sombra |
| VQ-04b · L3 | Render: ensayo separado de sombra nativa | VQ-04a | Comparar color/blancos, contacto y coste. Mantener planar si falla; no es requisito de Alto |
| VQ-05 · UI-02/EX-10 | Modelos/render: pala/barrido desde RPM y tiempo coherentes | **UI-02** y VQ-01b | Fuente `sim.aux[0]` en vivo; fixture sintético explícito. Pausa/crash/reset y captura coherentes; vídeo 30/60/144 fps; traza intacta |
| VQ-06a | Render: resolver/aplicar configuración con CLI diagnóstica y valores por defecto | VQ-01b | MSAA aplica realmente; repetir aplicación no duplica nodos/recursos; inválidos rechazados; ruta técnica independiente de preferencias; comparación de trazas |
| VQ-06b · UI-07/08 | UI: presets, Personalizado, restauración y guardado en esquema común | VQ-06a, **UI-02 y UI-07** | Casos de §11; pruebas de archivo roto/futuro/error; no perder idioma; aplicar/revertir desde pausa. Calibrar antes de declarar perfiles soportados |
| VQ-07 | Render: comparación Forward+ aislada | VQ-02, VQ-04b y GPU real disponible | Adoptar/posponer con informe; color y shaders propios revisados; release y recuperación probados antes de exponer Ultra |
| SM / L15 / M5 | Efectos y viento: integración desde sus planes | Sus contratos de estado/tiempo, UI-02 | Pausa/reinicio y coherencia con el viento simulado; no inventar viento físico desde el shader |

**Decisión de fuente L6a:** primero aplicar la búsqueda breve de §6.1. Si una familia existente cumple silueta, licencia y presupuesto, reutilizarla conservando las pruebas de atlas/import/export. Si no hay una adecuada, ensayar export offline de ez-tree, candidato ya investigado, fijando revisión exacta y licencia antes de incorporar archivos. Limitar el ensayo de export/import a una jornada estimada; si no produce assets reproducibles dentro del presupuesto, usar una familia CC0 de Kenney para cerrar el primer horizonte y registrar el cambio de estilo. No portar proctree ni añadir GDExtension en esta entrega. Conservar semilla, parámetros, versión y archivos fuente; reproducibilidad del bake se exige en el mismo renderer, no entre GPUs distintas.

Estimación de la primera entrega: **4–8 jornadas** de una persona familiarizada con el repo más el playtest; es una estimación de planificación. Si L6a excede su ensayo, activar su alternativa; si L6c falla, corregir lectura antes de extender el escenario. VQ-06a puede adelantarse tras VQ-01b para medir presets; su UI no bloquea el horizonte.

Los modelos son del frente de modelos; UI/pausa/preferencias del frente UI; `main.gd`, campo y medición se coordinan con línea principal. Antes de cada cambio comprobar modificaciones concurrentes en esos paths. Preservar `airplane`, `propeller`, `*_hinge` y los acabados Stik v4/v5 ya entregados. Los materiales de caché permanecen inmutables: variar valores admitidos por instancia; duplicar el recurso solo si hace falta una modificación no soportada por instancia.

## 5. Técnicas y trucos con aplicación concreta

Son propuestas de implementación, salvo donde se señala evidencia existente. Cada una debe demostrar una mejora en su escena de prueba.

| Técnica | Aplicación al simulador | Coste o precaución |
| --- | --- | --- |
| **Detalle según píxeles ocupados** | A distancia conservar silueta, colores superior/inferior y superficies; ocultar tornillos antes de simplificar el ala | El autozoom cambia el tamaño proyectado: una distancia fija no basta para el avión |
| **Macro + meso + micro en suelo** | Grandes variaciones suaves, zonas segadas y textura fina; evitar que cada nivel tenga la misma escala | Dos muestras adicionales ya cuestan fill rate; comparar contra el shader L2 actual antes de sumar capas |
| **Rugosidad antes que más polígonos** | Diferenciar film tenso, neumático, cabina y metal; variación sutil evita aspecto de plástico uniforme | Pintura y caucho no se vuelven metálicos por brillar; albedo de referencia y exposición común |
| **Biseles donde cambian el reflejo** | Borde del spinner, tren, capó y piezas cercanas; normales suaves en curvas y duras en cortes reales | Reservar geometría para contorno/reflejo perceptible; no inventar espesor o deformar cotas |
| **AO local moderado** | Uniones y cavidades en un atlas o mapa propio | No hornear una sombra direccional en piezas articuladas; no confundir AO con sombra del avión sobre el campo |
| **Un probe estático útil** | Zona de presentación/pits con suelo, mesa y entorno reflejados | `UPDATE_ONCE`, fijo al mundo; excluir avión móvil si generaría su reflejo fantasma. Mover el probe puede actualizarlo otra vez |
| **Hierba por sectores** | Grupos cercanos en MultiMesh, variación por instancia, reducir densidad fuera de zonas visibles | Un MultiMesh enorme se culla como conjunto; dividir espacialmente y ajustar AABB al balanceo |
| **Transparencia solo donde aporta** | Árboles con recorte alfa; césped cercano con geometría opaca; comparar cabina oscura opaca vs transparente | Ordenación, overdraw y bordes parpadeantes. No depender de alpha-to-coverage sin ensayo en nuestro pin |
| **Silueta de sombra por avión** | Máscara horneada de planta y datum propio para Extra/Stik | La proyección plana no reproduce una pose 3D arbitraria ni relieve; no extenderla fingiendo colisión correcta |
| **Hélice como exposición acumulada** | Pala a RPM bajo; disco/barrido según régimen y velocidad visual | Mantener spinner sólido y un solo efecto; el truco visual no modifica RPM físicas |
| **Luz y cielo con el mismo sol** | Si se prueba un HDRI, alinear dirección de luz, sombras y reflejos con su sol | Mezclar cielo soleado y luz de otra dirección produce incoherencia evidente |
| **Cámara estable y HUD selectivo** | Mantener datos de vuelo útiles; controles de diagnóstico accesibles aparte; suavizado de zoom opcional | No añadir retardo de seguimiento o cámara flotante al pilotaje RC |
| **Microvariación reproducible** | Rotación, tamaño y color de árboles desde semilla/posición; animación desde reloj de simulación | No `TIME` ni RNG dependiente del frame; pausa y captura deben reproducir el mismo estado |

Fundamento de materiales: [StandardMaterial3D y ORM](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html). Reflejos: [ReflectionProbe](https://docs.godotengine.org/en/4.7/classes/class_reflectionprobe.html). Instancias: [MultiMesh](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html), cuya página avisa que parte del contenido necesita revisión para 4.7; verificar comportamiento con el ensayo local. Transparencias: [limitaciones de render](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_rendering_limitations.html).

El LOD automático documentado se genera al importar escenas 3D; **no aparece automáticamente en los ArrayMesh procedurales actuales**. Para esos modelos, empezar por grupos de detalle con visibilidad controlada; si se adopta GLB, validar el LOD importado y la silueta. Godot selecciona mesh LOD según pantalla, FOV y resolución. [Guía de mesh LOD](https://docs.godotengine.org/en/4.7/tutorials/3d/mesh_lod.html).

Evitar blur de movimiento, profundidad de campo, aberración cromática, grano y exposición automática como valores normales de vuelo: pueden entorpecer la lectura de un avión pequeño. Pueden evaluarse en un modo de fotografía separado. MSAA no corrige por sí solo el aliasing especular; TAA puede dejar estelas. Revisar vídeo además de PNG. [Antialiasing 3D](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html).

## 6. Herramientas, bibliotecas y recursos

La [investigación de herramientas](research/visual-quality-tools-2026-10-05.md) y la [integración del aporte del propietario (2026-10-06)](research/visual-quality-supplement-2026-10-06.md) registran fuentes, licencias y pruebas pendientes. Priorizar assets reutilizables y herramientas de autoría cuando ahorren trabajo; adoptar dependencias runtime solo por necesidad demostrada. Selección ejecutable:

| Opción | Uso aquí | Decisión inicial |
| --- | --- | --- |
| Godot nativo: StandardMaterial3D, ShaderMaterial, MultiMesh, profiler, capturas | Iluminación, materiales, terreno simple y vegetación | Base de las primeras entregas; ninguna dependencia runtime adicional |
| Blender → glTF/GLB | Props, UV, normales, reducción de malla y horneado de atlas | Usarlo cuando el asset lo necesite; export explícito y versión fijada. Conservar pivotes y contratos del avión |
| glTF Transform 4.5.0 + Khronos glTF Validator 2.0.0-dev.3.10 | Inspección, reescritura acotada y validación offline de GLB | **Usados** en §6.2; lockfile y receta conservados. `weld` conserva la captura de las tres muestras; no activar compresión/flatten/simplificación por defecto |
| Material Maker | Generar texturas PBR de suelo, caucho o pintura | Ensayo offline pequeño; exportar mapas, no incorporar un grafo nuevo al runtime |
| Poly Haven / ambientCG / cgbookcase | Materiales CC0; Poly Haven también props/HDRI | L9/VQ-02: hasta cuatro familias de superficies a 1K–2K; una por A/B. Pista actual de hierba; asfalto solo para un área que lo necesite. Height no cambia colisión |
| Kenney / KayKit / Poly Pizza | Props y vegetación como punto de partida | Kenney Nature Kit **ensayado** para L6a/L8: tres fuentes CC0 y adaptación concreta (§6.2). KayKit/Poly Pizza siguen como candidatos L10/L11; no heredan esta validación |
| Quaternius | Paquetes concretos, con revisión de licencia | No es fuente CC0 por defecto: QAL y fichas antiguas CC0 coexisten. Admitir solo archivos con evidencia de distribución CC0; usar alternativa si hay ambigüedad |
| Terrain3D | Esculpir/pintar campos grandes en editor | Ensayo condicionado a necesidad de autoría. El render del terreno no reemplaza nuestro sampler físico float64 |
| HTerrain | Alternativa de terreno para comparar | Un solo ensayo comparativo si el terreno propio limita; no mantener dos addons |
| ProtonScatter | Colocación de vegetación por reglas | Evaluar si editar campos a mano se vuelve costoso; guardar distribución reproducible y perfil simple sin plugin obligatorio |
| Tree3D / gdTree3D | Generador alternativo de árboles | Reserva para L6a/L8 si las fuentes elegidas no bastan; probar salida offline sin GDExtension en runtime. Colliders generados no implementan L14 |
| Simple Grass Textured | Referencia y alternativa de autoría de hierba | Ensayo L11a frente a geometría opaca: `TIME`/viento, alfa, mipmaps y coste. Conservar nuestro contrato `sim_clock`/`wind_vec` |
| Sky3D / PhysicalSkyMaterial | Referencias y alternativas de cielo | L19 si se necesita día/noche; A/B con L1–L4, reloj y exposición controlados. Sky3D declara Compatibility; MIT del código no cubre sus mapas estelares CC BY 4.0 |
| Procedural Forest Demo | Estudiar scattering, biomas y billboard LOD | L6/L8; efectos de compositor solo en ensayo VQ-07. Revisar atribución CC BY y cada asset tercero; no importar el demo completo |
| Godot Road Generator | Autoría de accesos y carreteras curvas | L10/L18 cuando el campo lo requiera; salida estática probada sin addon. No incorporar navegación IA ni colisión automática al simulador |
| Boujie Water Shader | Agua visual para un campo futuro con lago | Shader usa `TIME`; Compatibility 4.7.2 no verificado. Ensayar profundidad/transparencia, adaptar reloj y medir coste antes de incorporar |
| WaterBox / Godot Aerodynamic Physics | Investigación de flotación y modelos aerodinámicos | Referencia separada: sus nodos/fuerzas no sustituyen el integrador float64 ni se añaden sobre él |
| Pillow / NumPy / FLIP ya presentes en tooling visual | Máscaras del avión, diferencias locales y galerías | Reutilizar [requirements-visual.txt](../app/tests/requirements-visual.txt) y [visual-env.sh](../app/tests/visual-env.sh); no añadir otro framework |

Cada candidato debe resolver un paso concreto, quedar fijado a versión/revisión exacta y demostrar importación/exportación limpia. Ensayos de autoría: una herramienta por problema, una jornada estimada para producir una salida utilizable y medir también tiempo de edición. Si no compensa, conservar la ruta vigente. Licencia de herramienta, licencia de cada asset y compatibilidad del backend son verificaciones diferentes: por ejemplo, ProtonScatter no convierte las texturas Textures.com de su demo en MIT. La [verificación del aporte](research/visual-quality-supplement-2026-10-06.md) conserva las fuentes. La integración inicial fue documental; **§6.2 añade descargas y ejecuciones reales aisladas**, sin addons en la app.

### 6.1. Buscar antes de crear un recurso genérico

La [investigación adicional de fuentes](research/asset-sources-catalog-2026-10-06.md) convierte la reutilización en parte del trabajo de cada paso. Antes de modelar un prop, crear una textura o construir un sistema genérico nuevo, revisar el inventario del repo y las fuentes pertinentes. Una investigación previa aún aplicable satisface esta revisión; no repetirla por cada función, corrección o variante.

| Necesidad | Ruta inicial de búsqueda | Uso en este plan |
| --- | --- | --- |
| Modelos y naturaleza | Repo → Poly Haven → Kenney → KayKit → Poly Pizza → itch.io CC0 → OpenGameArt CC0 | L6/L8/L10/L11; comenzar por Kenney/KayKit si se busca silueta simple. Escoger según coste y estilo, no por tamaño del catálogo |
| Texturas | Repo → ambientCG → Poly Haven → cgbookcase | L9/VQ-02; mantiene cuatro familias y 1K–2K inicial, escala/normal/roughness comprobados |
| Plugins y código | Godot nativo/repo → Asset Store → Asset Library → upstream GitHub | Necesidades nuevas del paso; MIT/Apache-2.0/BSD preferidos, revisión exacta y contratos de este simulador |
| Shaders/VFX | Repo → Godot Shaders → Asset Store/Library → upstream | VQ-02/04/07 y L9/L15/L19; preferir CC0/MIT, revisar backend, reloj, transparencia y origen de texturas |
| UI e iconos | Theme/controles propios → Kenney → packs con licencia de KayKit/itch.io/OpenGameArt | Coordinación con MENU-PLAN; preservar idioma, contraste y escala |
| Audio | Síntesis/archivos propios → Freesound CC0 → OpenGameArt CC0 → Kenney | Reserva para tareas de sonido; no reemplaza motor ligado a RPM ni amplía el hito visual |
| Personas animadas | Confirmar necesidad → CMU / KayKit → Mixamo condicionado | Futuro contenido de pits; términos de distribución y rig por recurso. L10 puede cerrar con props estáticos |

**Procedimiento de selección:** dedicar inicialmente 30–60 minutos y comparar hasta tres candidatos (estimaciones de trabajo, no espera obligatoria). Dejar en la evidencia del ID una nota con necesidad, candidatos/URLs, revisión/licencia, coste de adaptación y decisión `reutilizar`, `adaptar`, `crear` o `posponer`. Si no hay candidato adecuado, implementar la solución acotada y explicar por qué. La falta de resultado de búsqueda no requiere una nueva aprobación.

Para el seleccionado, probar primero una muestra con las condiciones de §8/§11: silueta y escala, UV/normales, materiales/draws/memoria, reloj si anima, importación y export limpio; ampliar a un lote después. El coste de adaptar, atribuir, mantener y exportar forma parte de la comparación. El permiso de usar un asset en un juego no se toma automáticamente como permiso de redistribuir su archivo fuente.

**Precisiones verificadas:** el [Asset Store oficial](https://store.godotengine.org/) está en beta y convive con Asset Library; ni «oficial» ni «gratis» acreditan compatibilidad o una licencia única. En [Godot Shaders](https://godotshaders.com/license/) la licencia del código excluye los medios y assets de demostración. Los tags CC0 en buscadores son un punto de entrada: manda la licencia del recurso elegido. Para [Freesound, CMU y Mixamo](research/asset-audio-animation-sources-2026-10-06.md), conservar las condiciones individuales; CMU/Mixamo no se etiquetan CC0 por permitir usos gratuitos. Quaternius mantiene la comprobación individual descrita arriba.

Esta regla amplía las fuentes y cambia la selección L6a; conserva la secuencia de §4 y la física/radio existentes. La prioridad del desarrollo propio sigue siendo la simulación RC y sus contratos, junto con las adaptaciones visuales que los recursos externos no resuelvan.

### 6.2. Herramientas usadas y decisiones que ya tienen evidencia

Los ensayos están en `research/visual-quality/`, fuera de `app/`, con fuentes, recetas, capturas y versiones. Godot **4.7.2 Compatibility sobre llvmpipe**: prueban importación, aspecto y contadores; no aprueban rendimiento en la 3090 ni en un PC modesto.

| Prueba ejecutada | Resultado observado | Decisión para implementar |
| --- | --- | --- |
| [Kenney + glTF Transform + Khronos](research/visual-quality-nature-trial-2026-10-06.md): tres GLB CC0 | 78/114/196 triángulos. Los tres originales tienen `SCENE_NON_ROOT_NODE`; tras `weld` y reescritura, cero errores/warnings. Total 31.272 → 28.852 B; PNG original/derivado idéntico | **Adaptar** esta familia en L6a; derivados validados como entrada del bake. La búsqueda inicial queda satisfecha. ez-tree solo si la silueta facetada falla al probarla en el campo |
| Godot MultiMesh: 480 árboles, 24 grupos visibles, dos superficies vs una | 48 → **24 draws**, mismas 62.080 primitivas; diferencia máxima de 1 nivel por canal al unir materiales con colores por vértice. Seis casos repiten su PNG en dos procesos | L6b/L8 presupuestan **superficies y pases**, no solo nodos. El adaptador es específico para mallas estáticas opacas; generar derivados offline antes de integrarlo |
| Materiales importados y paleta del mismo árbol | Hojas/troncos llegan con `metallic=1`. La variante dieléctrica y una paleta natural provisional se renderizan con la misma geometría | Ajustar material/paleta antes del atlas. Conservar captura original para separar optimización de cambio artístico. Revisar altura y datum: unidades de origen no acreditan escala botánica |
| [ambientCG Grass001 1K](research/visual-quality-material-trial-2026-10-06.md) + StandardMaterial3D | Muestrario real de Color frente a Color + NormalGL + Roughness; escala de origen aproximada 1,4 m. El relieve es visible de cerca; la repetición permanece | **Candidato** para L9b/c, con A/B en suelo real antes de adoptarlo. No sustituir directamente el shader actual. VQ-02 reutiliza el método de comparación; la hierba no valida los acabados del avión |
| Pillow/NumPy y captura nativa | Comparación numérica separa la reescritura idéntica del cambio deliberado de materiales; runner de árboles rechaza salidas antiguas | Reutilizar estas recetas en VQ-01/L6. Métrica de diferencias y juicio visual tienen funciones distintas |

**Receta de aceptación de GLB:** inspeccionar → validar fuente → transformar solo lo necesario → validar derivado → importar en proyecto limpio → comparar imagen/materiales/contadores → exportar en los tres targets. Un original inválido puede archivarse como evidencia; no autoriza distribuir un derivado inválido. Declarar una extensión en el JSON no significa que cada material la use: el ensayo detectó ese caso con `KHR_materials_unlit`.

**L9b/c y VQ-02:** registrar escala del tile, convención del normal, canal de roughness, UV/tangentes, filtrado y mips. Comparar albedo, +normal y +roughness en pasos separados sobre el mismo objeto/cámara/luz; la muestra actual combina ambos mapas y todavía no aísla sus contribuciones. El fixture carga `ImageTexture`: falta validar el import/export real. Conservar anti-tiling y bruma del shader de campo. La escala aproximada de la textura no define altura, fricción ni colisión.

**Pendiente antes de adoptar:** atlas 1024² y sus bordes/mips, integración con bruma/luz del campo, escala/claros, lectura humana de L6c, export y medición GPU. La variante por vértices necesita otro A/B al pasar a Forward+: el control sRGB correspondiente no actúa en Compatibility. Material Maker, Blender y los plugins de terreno/cielo permanecen condicionados a una necesidad concreta; estos ensayos no exigen instalarlos para continuar con L5.

## 7. Guías y tutoriales para aprender haciendo

| Recurso primario | Ejercicio que debe dejar en el repo | Paso |
| --- | --- | --- |
| [Materiales Godot](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html) | Muestrario de cinco acabados bajo la misma luz y aplicado al avión | VQ-02 |
| [Entorno y postproceso](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html) | Contact sheet con exposición y SSAO A/B; conservar color y legibilidad | VQ-02/07 |
| [Reflejos localizados](https://docs.godotengine.org/en/4.7/tutorials/3d/global_illumination/reflection_probes.html) | Mesa y avión en pits, con/sin probe fijo; medir actualización | VQ-02 |
| [MultiMesh](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html) | Un sector de árboles y uno de hierba con AABB y contadores | L6/L11 |
| [LOD importado](https://docs.godotengine.org/en/4.7/tutorials/3d/mesh_lod.html) | Árbol GLB con comparación de silueta a varios FOV | L6/L8 |
| [Antialiasing y demo enlazada](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html) | Pasada del avión y árboles a 30/60/144 fps, con evaluación de estelas/parpadeo | VQ-03/06/07 |
| [Optimización GPU](https://docs.godotengine.org/en/4.7/tutorials/performance/gpu_optimization.html) | Aislar coste de resolución, transparencias, sombras y draw calls por separado | Gate L |

Las guías de autoría de Blender, Material Maker, Terrain3D y ProtonScatter están enlazadas en la investigación de herramientas. Tutorial antiguo o demo espectacular sirve como idea; backend, licencia y API se verifican antes de copiarlo. Un resultado de vídeo de otro proyecto no acredita rendimiento en este simulador.

## 8. Presupuesto, casos de prueba y evidencia

**Objetivos iniciales de ingeniería, por validar en hardware real:** Equilibrado a 1920 × 1080 / 60 Hz en la 3090: p95 ≤ 16,7 ms y p99 ≤ 25 ms; Bajo a 1280 × 720 / 30 Hz en un equipo modesto aún por identificar: p95 ≤ 33,3 ms y p99 ≤ 50 ms. No son FPS prometidos ni mínimos de hardware publicados. Alto se acepta solo con medición a resolución declarada; 4K no se infiere de 1080p. Los ajustes numéricos al presupuesto deben justificarse con coste y lectura, no hacerse solo para pasar un test.

Conservar guardas de [LANDSCAPE-PLAN](LANDSCAPE-PLAN.md): paisaje ≤ 300 draws y ≤ 1 M primitivas, árboles ≤ 24 y hierba ≤ 5; avión separado; memoria de paisaje ≤ baseline sin avión + 64 MB y tamaño del build ≤ +15 MB (estimaciones). Contar con y sin avión, misma cámara; declarar si las sombras están incluidas. Godot mide su propia memoria, no toda la VRAM del driver. Texturas del paisaje ≤ 2K, atlas inicial 1K; excepción de fondo de cielo ≤ 4K solo en L16.

### Matriz mínima de VQ-01b

| Caso fijo | Uso | Evidencia |
| --- | --- | --- |
| Fixture de atmósfera vacía L1–L4 | Mantener pruebas de gradiente, bruma, sol y nubes cuando aparezcan árboles | Controles existentes sin cambiar umbrales; capturas independientes del campo completo |
| Piloto: 30 m y pasada a 3 m, t=1,5 s, con/sin autozoom | Regresión de lectura Stik | Pares con/sin avión y `shadow=off`; datos de `compare_captures.py` |
| Campo: azimut 0/90/180/270°, elevación 0/10°; cenital a 30 m | Huecos, repetición y borde de pista | PNG y contadores de paisaje sin avión, repetidos dos veces |
| Stik y preview Extra: 20/50/100 m, seis actitudes | Orientación y materiales | Casos sintéticos etiquetados; misma luz/FOV por A/B. Desde VQ-01b ambos constructores usan un fixture común de inspección en la app; el inspector propio del Extra sigue para detalle |
| Inicio inglés/español y vuelo tras pulsar Volar | Constructor común y cambios de escena | Capturas UI; sin cámaras/WorldEnvironment duplicados al entrar a vuelo |
| Ruta render fija de 60 s y vuelo físico de regresión | Coste y separación de simulación | Scripted para coste reproducible; pruebas físicas existentes para trazas. El informe distingue ambas rutas |

VQ-01b añade al harness existente los 66 casos descritos y mantiene los 46 anteriores. Dejar en su manifiesto pose, distancia al piloto, FOV/autozoom, exposición, estado, cámara, reloj, semilla, revisión de código y hashes de assets. Guardar prueba por paso en `docs/research/visual-quality-implementation/<ID>/`; las capturas temporales siguen en `app/captures/`. No guardar archivos de usuario ni depender de recursos no versionados.

**Lectura:** conservar los umbrales Stik existentes en el fixture de referencia. Para escenas nuevas con árboles, no reutilizar a ciegas el contraste negativo del avión frente al cielo: registrar fracción casi invisible, ΔE y máscara local. L6c usa un ensayo humano de 24 imágenes a 100 m (seis actitudes × cielo/árboles/suelo/horizonte), orden fijado y separado del nombre del caso; anotar orientación superior/inferior y sentido de alabeo cuando aplique. Objetivo inicial: ≥ 22/24 respuestas correctas por perfil, sin respuestas reveladas; más una pasada y un viraje en vuelo. Umbral de diseño, no validación estadística de pilotos. Si falta playtest se marca pendiente; las capturas no lo sustituyen.

**Rendimiento:** VQ-01b amplía `_log_frame_time()` con `openrc-frametimes v2`: conserva las claves anteriores, calcula pacing con reloj monotónico y guarda `delta` de Godot por separado; añade intervalos crudos, ruta/caso, configuración/backend, revisión y calentamiento solicitado/real. `--warmup` conserva 1 s por defecto; los frames que cruzan el calentamiento se excluyen completos. Propuesta: tres procesos, 10 s de calentamiento + 60 s de muestra cada uno. Registrar también tiempo de simulación/ticks para descubrir ralentización bajo carga. Medir CPU/GPU con Visual Profiler en sesiones separadas y pacing en export sin capturadores. Fijar resolución, VSync y refresco por comparación; una ronda sin límite ayuda a medir margen, otra con la configuración de juego evalúa pacing. Guardar cada pasada, no solo su media.

**Primera presentación:** medir aparte Inicio → Volar y primera aparición de cada efecto. Declarar caché fría/caliente, instalación y driver; un proceso nuevo no prueba caché de shaders fría. No borrar cachés del usuario para ensayar. En Compatibility preparar materiales visibles según la investigación y probar que el tiempo de simulación no avanza durante una eventual pantalla de carga. Ningún dato llvmpipe se usa para aprobar rendimiento de la 3090.

### Cierre común por cambio

1. Registrar baseline del mismo código/entorno antes del cambio. Repetir capturas en el mismo entorno; la paridad byte a byte se exige en refactors como L5, no entre aspectos artísticos deliberadamente distintos. FLIP detecta regresiones locales; no decide si una composición es mejor.
2. Ejecutar `app/test.sh` cuando cambie implementación. Ejecutar `app/capture.sh` con renderer real para shaders; actualizar fixtures específicos, sin borrar pruebas del comportamiento anterior. Comparar trazas con mismo tick/entradas; no regenerar goldens físicos por cambios visuales.
3. Si entran assets, paths, importación o filtros de export, probar clon limpio y los tres exports/smokes. La geometría se lee desde `res://`; un archivo que solo existe en la raíz del repo no acredita el build.
4. Guardar galería A/B, manifiestos, datos y decisión: aprobado, reducido, pospuesto o descartado. Los ensayos pueden cerrarse sin adoptar el efecto. Actualizar LEARNINGS y el plan propietario; commit por ID con prueba concreta.
5. Rollback por cambio independiente: conservar receta anterior y recursos fuente. Una configuración inválida restaura valores conocidos; volver al preset anterior no cambia la sesión física. No activar efectos adicionales hasta cerrar sus pruebas.

## 9. Alcance y decisiones pendientes

VQ-01a y VQ-01b se implementaron sin esperar hardware modesto, resolución final o gustos de acabado. Esos datos bloquean **la declaración de rendimiento/calidad soportada**, no el desarrollo del horizonte. El playtest humano cierra L6c; UI-02/UI-07 cierran el acceso a ajustes durante el vuelo; EX-03/04 delimitan la integración del Extra.

Fuera de la primera entrega: terreno con colisión, aterrizaje, clima dinámico, mundos enormes, GI dinámica, nubes volumétricas, ray tracing, fotogrametría, streaming de texturas y migración de renderer. L7 espera su generador; L12–L15 siguen el plan físico; L16–L20 siguen condicionados a sus gates. Un panorama real continúa siendo una alternativa futura, no una segunda implementación paralela.

**Siguiente cambio concreto: L6a.** VQ-01a/b protegen las referencias; [L5 comparte el campo validado entre Inicio y vuelo](research/visual-quality-implementation/L5/README.md), conservando imágenes y trazas. Implementar ahora la silueta del arbolado y comprobar su lectura desde el piloto; los perfiles y el rendimiento en hardware del propietario siguen pendientes.

## 10. Segunda ronda de investigación: condiciones nuevas de implementación

La [segunda ronda](research/visual-quality-round2/README.md) amplía fuentes, técnicas y herramientas, con un [proyecto sintético ejecutado](research/visual-quality-round2/godot-probe/README.md). No implementa pasos de producto ni cambia el orden de L5/L6.

| Paso | Añadir al diseño y a su prueba |
| --- | --- |
| VQ-02 / EX-10 | UV y tangentes antes de normal maps; comprobar bordes del atlas a distancia. El ensayo confirmó tintes por objeto con `instance uniform` en Compatibility 4.7.2; no acredita samplers por instancia ni MultiMesh |
| L6/L8/L11/L15 | Reducir también coste del material distante; usar histéresis en vez de asumir fade HLOD de Forward+. Bounds deben cubrir viento/deformación: el ensayo reprodujo desaparición y recuperación ajustando AABB |
| L9c | Filtrar bandas procedurales según tamaño de píxel, manteniendo contraste de pista; MSAA no sustituye el filtrado del shader |
| VQ-06 / UI de carga | Añadir primera entrada/primer efecto al protocolo; cargar recursos no equivale a dibujar y preparar shaders en Compatibility |
| SM / VQ-07 | Probar profundidad e intersecciones transparentes por backend; separar Shader Baker, precompilación y calentamiento OpenGL |
| VQ-07 / exportación | Registrar backend, herramienta de perfilado y actividad soportada. Optimizar GLB en copia y verificar jerarquía, bisagras, UV y escala antes de adoptar la salida |

Prueba de la segunda ronda: 5 estados y 8 muestras de píxel por ejecución; dos ejecuciones con 5 PNG idénticos y sin errores de motor/script/shader. Es evidencia de comportamiento en llvmpipe, no benchmark de la 3090. Los ensayos de importación, GPU y optimizadores externos siguen propuestos.

## 11. Contratos para implementar sin inventar otra arquitectura

Los nombres nuevos de este apartado son **propuestos**. Reutilizar módulos existentes cuando ya cumplan el contrato; no crear un bus global, un segundo catálogo de aviones ni un sistema genérico de plugins.

### Campo y recursos

- `app/data/fields/default.json`: `format: "openrc-field v1"`, ID estable, pista, estación del piloto, rectángulos de superficie y objetos. Cantidades con `{value, unit, kind, source}`; números finitos y tamaños positivos. Posiciones NED en metros; convertir a coordenadas Godot solo en render. L5 mueve exactamente los valores de `Spec.RUNWAY` (100 × 12 m, centro norte 15 m, este 0) y conserva piloto en origen/altura de ojos 1,7 m. La elevación visual de 3 cm de la pista es un detalle de render, no relieve físico. Lo estimado se etiqueta; no atribuir estas medidas actuales a normas AMA/BMFA sin evidencia.
- `app/data/field_loader.gd`: carga/valida y devuelve `{ok, errors, field}`. Rechazar formato desconocido, ID vacío/duplicado, unidades/tipos incorrectos, no finitos y rectángulos degenerados. Solape de superficies deliberado: pista > segado > rough; empates entre superficies del mismo nivel se rechazan. L5 no cambia la lógica de contacto con el suelo. `collides=true` se rechaza como capacidad aún no soportada hasta L14; no aceptar en silencio un obstáculo atravesable.
- `app/render/field.gd`: construye un `Node3D` de suelo/pista/vegetación a partir de datos validados y opciones visuales; no crea sesión, avión, cámara ni WorldEnvironment. `main.gd` y `ui/home_scene.gd` lo llaman. El loader se ejecuta antes de iniciar la sesión: archivo inválido muestra error en ruta interactiva; automatización falla con código no cero. No cargar un campo diferente silenciosamente.
- Fuentes originales, recetas y licencias: `assets/landscape/` y `assets/landscape/PROVENANCE.json`; herramientas offline en `tools/trees/`. Recursos que se distribuyen: **`app/assets/landscape/`**, accesibles por `res://assets/landscape/`. El manifiesto relaciona fuente → recurso runtime con SHA, versión de herramienta, parámetros y licencia; versionar las salidas necesarias y no depender de enlaces a carpetas fuera de `app/`.
- L6b conserva posiciones de árboles offline; derivar apariencia desde coordenadas/semilla estable, nunca RNG por frame. Documentar cuantización/hash y verificar CPU/shader si ambos lo calculan. La representación no cambia identidad/altura necesaria para vuelo. La parte de bounds y mipmaps se prueba en el asset completo, incluyendo rotación, escala y futura deformación.
- Vincular cada recurso incorporado a la nota de selección de §6.1 y al ID que lo necesita; no crear un catálogo paralelo de recursos descargados sin uso.
- Para GLB, guardar el informe Khronos de fuente/derivado y la receta exacta con lockfile; cero errores en el derivado y warnings revisados. Registrar superficies, materiales efectivos, transformaciones de raíz y cambios de color. La prueba Kenney de §6.2 cubre mallas estáticas; no autoriza unir nodos ni eliminar hinges del avión.
- Licencia por archivo: además de fuente/hash, conservar texto o evidencia de la licencia del paquete adquirido, autor, fecha y modificaciones. Separar código del addon de assets de terceros; trasladar créditos requeridos a los builds. No asumir CC0 por nombre del proveedor: Quaternius exige comprobación individual según la [revisión de fuentes](research/visual-quality-supplement-2026-10-06.md#correcciones-de-licencia-y-alcance).
- Export: revisar los **tres** presets. Hoy `all_resources` importa recursos Godot y `include_filter="data/*.json"` cubre datos explícitos; demostrar que entran los nuevos subdirectorios y licencias. No copiar un filtro propuesto sin probar el ZIP/PCK desde clon limpio.

### Calidad, preferencias y ruta técnica

- `app/render/visual_quality.gd` propuesto: resolver defaults + overrides válidos y aplicar exclusivamente parámetros visuales. Empezar por MSAA; añadir vegetación cuando exista. Un resolver puro facilita comprobar valores desconocidos/rangos y la relación preset/Personalizado. Aplicar dos veces la misma configuración debe ser idempotente.
- `app/app_state/preferences.gd` sigue siendo el único dueño de `user://settings.cfg`. Al incorporar calidad, incrementar el esquema **desde la versión que tenga UI-07 al integrar**, migrar la anterior conservando idioma/autozoom/volumen y mantener la protección de esquema futuro (`writable=false`). El guardado actual reconstruye ConfigFile: actualizar todos los consumidores para que cambiar idioma no borre calidad ni viceversa. Sin escritura posible, usar los valores en memoria y mostrar el error.
- Precedencia: defaults del proyecto → preferencias válidas **solo en ruta interactiva** → cambios de la sesión. En ruta técnica: defaults → CLI explícita; no leer ni escribir preferencias, incluso con `--quick-flight`. Argumentos nuevos propuestos: `--quality=low|balanced|high`, `--msaa=off|2|4|8`; rechazo explícito de valores inválidos. Los comandos actuales sin esos argumentos conservan aspecto y semántica. El renderer es un argumento del motor anterior a `--`, no una clave de este resolver.
- Ajustes desde pausa tras UI-02: aplicar MSAA y densidad sin resetear vuelo, ticks, radio o calibración; restaurar valores anteriores al cancelar. Confirmar guarda una vez. «Restaurar gráficos» no borra idioma ni otras preferencias. Las variantes de textura, si se añaden, se aplican al siguiente inicio de escena y lo indican en UI.
- Home recibe la misma calidad que vuelo, con reloj fijo; salida de Home elimina su escena antes de crear la de vuelo (contrato actual de `app_root.gd`). No añadir otra cámara activa ni dejar árboles/probes de Home vivos en vuelo. Cambiar calidad no debe volver a reconstruir el avión.
- Casos VQ-06: preset válido, override → Personalizado, inválido, restauración, relanzar, esquema viejo/futuro, error de guardado, cambio de idioma tras guardar calidad, ruta técnica con archivo hostil, cinco aplicaciones repetidas y traza idéntica a mismos ticks/entradas. Un test del valor guardado no sustituye observar el MSAA/densidad realmente aplicado.

### Tiempo, cámara, sombra y datos del avión

El render consume estado; no escribe en `sim/` ni `physics/`. Pausa, reinicio y crash proceden de la sesión. `ShaderClock` conserva su wrap de 1024 s; animaciones periódicas deben cerrar el ciclo. `TIME` sigue prohibido. La ruta scripted de captura puede tener estado sintético, identificado como tal.

VQ-05 no infiere RPM de throttle en vuelo: usa `sim.aux[0]`. Hoy `_process()` acumula la hélice con delta visual y `_capture()` usa `Commands.prop_rev_per_sec`; por eso el criterio exige reconciliar captura/tiempo con UI-02, no solo colocar un disco. Mantener fase visual separada de fuerzas y sonido, acotada y detenida durante pausa/crash; documentar estado inicial y cómo se reconstruye en captura. No introducir física de motor nueva.

VQ-03 conserva puntería al avión; solo ensaya encuadre/FOV. Cuando conservar horizonte obligue a perder tamaño legible o sacar el avión del margen, prevalece el avión y se permite perder horizonte. Umbral inicial de margen: 5 % del viewport (estimado), con prueba de viraje vertical y cruce sobre el piloto. Descartar el modo si requiere retardo de seguimiento.

VQ-04a consume metadatos por modelo: máscara, span/length y posición del datum dentro de la máscara, sin duplicar parámetros aerodinámicos. `model_extent()` solo devuelve dimensiones: no sustituye el datum ni la forma. La máscara plana es una ayuda limitada sobre suelo plano; no se declara autosombra ni solución al relieve de L12. Desactivar la planar al ensayar una sombra nativa equivalente para evitar duplicación. El problema de color L3 necesita su A/B propio.

## 12. Revisión senior y veredicto

**Propuesta revisada:** mejorar primero referencias de vuelo y materiales dentro del motor actual, y escalar efectos después de medir. Su versión más sólida entrega un campo reconocible conservando legibilidad, determinismo y trazas; la cantidad de plugins no es un objetivo. Faltan SO/resolución final, PC modesto y playtest, pero no impiden implementar VQ-01/L5/L6.

Se intentó refutar cada objeción buscando soporte ya existente en código y planes. Las que sobrevivieron quedan resueltas **en el diseño** a continuación; VQ-01a ya resolvió las guardas de captura y el fixture; las demás correcciones de código siguen pendientes en sus pasos.

| Hallazgo y riesgo | Evidencia y contraevidencia revisada | Decisión que cierra la ambigüedad |
| --- | --- | --- |
| **Resuelto en VQ-01a:** un PNG antiguo podía aparentar una captura nueva | El harness anterior dejaba archivos previos, ignoraba el código de salida y comprobaba existencia; buscar líneas ERROR no cubría todos los fallos | Limpieza, proceso/imagen/hash/manifiesto obligatorios; 15 pruebas y mutaciones demuestran rechazo de evidencia vieja |
| **Resuelto en L5:** montaje distinto en Inicio y vuelo | Ambos usan ahora `field_loader.gd` y `field.gd`, con recursos propios por escena | [Paridad de imágenes/traza, rutas y exports](research/visual-quality-implementation/L5/README.md) |
| **Resuelto en VQ-01a:** árboles invalidarían pruebas de cielo vacío | `check_landscape_captures.py` usa filas/franjas fijas (bruma/nubes). Los controles L0 sí existen; no deben rehacerse ni relajarse | Fixture de referencia separado y nueve vistas del campo; una mutación del campo deja intacta la referencia, sin relajar umbrales |
| **Bloqueante de planificación:** L7 depende de L13a | El plan de paisaje nombra explícitamente su generador de colinas; L7 figuraba antes en la primera entrega | L7 sale del mínimo entregable y espera esa salida; no arrastra física de terreno |
| **Bloqueante para presets:** límites 1K/2K/4K sin mecanismo | `Ground.grass_material()` crea ImageTexture por código y el proyecto no tiene cargador de variantes. El importador documentado no resuelve ese runtime | Primeros perfiles comparten texturas; variantes solo tras necesidad y pipeline offline demostrado |
| **Bloqueante para UI:** propiedad de preferencias/pausa poco definida | `preferences.gd` ya versiona idioma y protege esquema futuro; `app_root.gd` omite preferencias con cualquier argumento. UI-02/07 siguen siendo dependencias | VQ-06 se divide; conserva ruta técnica y extiende el almacén común con migración, sin segundo sistema |
| **Bloqueante para assets distribuibles:** fuentes fuera de `res://` | El plan de paisaje proponía `assets/landscape/`; el proyecto exportable vive en `app/`. Los tres presets usan `all_resources`, pero no empaquetan automáticamente la raíz del repo | Separar fuentes y derivados runtime en §11 y verificar importación/export limpia |
| **Riesgo aceptable con ensayo:** querer más realismo oculta el avión | Ya existen autozoom y métricas L0c, así que no falta toda la instrumentación. Sus umbrales de cielo no validan orientación entre árboles | L6c añade lectura humana y presupuesto local; corregir vegetación antes de sumar efectos |
| **Riesgo aceptable con ensayo:** asumir Ultra soportado en la 3090 | Hardware declarado no es benchmark; VQ-01b ya registra muestras crudas/rutas, pero no sustituye medición GPU en el hardware objetivo | Medir en export; VQ-07 sigue aislado y puede concluir pospuesto |

**Preguntas que cambian decisiones, convertidas en pruebas:** ¿la mejora se ve durante vuelo y no solo en inspector? → L6c/VQ-02; ¿el recurso entra en un build limpio? → L6a/L5; ¿el preset cambia algo y conserva la traza? → VQ-06; ¿la sombra nativa cambia la pintura? → VQ-04b; ¿el coste cabe sin ralentizar la simulación? → registro de ticks y frame times en §8. No requieren una nueva ronda de permisos para comenzar.

**Veredicto: buena idea, proceder.** El plan está listo para implementar por la secuencia de §4 con sus límites y criterios de cierre. Las decisiones de diseño anteriores resuelven los bloqueos del plan; la aprobación de rendimiento, lectura humana y efectos experimentales conserva sus gates. Próxima acción: L6a; usar la matriz, el campo compartido de L5 y las guardas verificadas, sin migrar renderer.

Prueba de la revisión senior original: inspección del flujo real de entrada, construcción de campo, render/capturas, persistencia, logger y tres presets de export; comprobación de enlaces y consistencia documental. Esa revisión fue documental. Los ensayos añadidos después en §6.2 acreditan sus pruebas aisladas; no acreditan implementación en la app, suite del juego ni nuevos benchmarks GPU.

## 13. Aporte adicional integrado el 2026-10-06

El [texto aportado](research/visual-quality-user-input-2026-10-06.txt) queda conservado como entrada, y su [contraste con fuentes](research/visual-quality-supplement-2026-10-06.md) diferencia recomendaciones de compatibilidad comprobada. §6 incorpora todos sus candidatos con destino; §11 concreta procedencia y distribución. Se añade selección de superficies a L9/VQ-02, KayKit a L10 y estudio de la demo de bosque a L6/L8. Agua, carreteras y herramientas de cielo/terreno entran como ensayos condicionados a contenido que los necesite.

La primera entrega y el siguiente paso de §4 se mantienen: las bibliotecas amplían cómo producirla. Terrain3D y Sky3D no pasan a ser requisitos por aparecer en un stack recomendado; agua/flotación no se añaden a los criterios de cierre del campo actual. Reutilizar recursos adecuados reduce autoría, conservando las pruebas de vuelo, render y export ya definidas.

El [segundo aporte de fuentes](research/asset-sources-catalog-2026-10-06.md), integrado el mismo día, añade §6.1 y la búsqueda previa de L6a. Su [texto original](research/asset-sources-user-input-2026-10-06.txt) queda conservado por separado del primer aporte.

El uso práctico posterior de esas herramientas queda integrado en §6.2 y en los criterios L6a/b: [árboles/validación/instancing](research/visual-quality-nature-trial-2026-10-06.md) y [muestra de materiales PBR](research/visual-quality-material-trial-2026-10-06.md). Son prototipos reproducibles, no pasos de la app declarados completos. VQ-01a, VQ-01b y L5 se implementaron después de esos ensayos; el siguiente paso de integración es L6a.

## 14. VQ-01a implementado — 2026-10-06

[Prueba y reproducción](research/visual-quality-implementation/VQ-01a/README.md): 46 capturas nuevas con sidecar en clon limpio; 29 referencias idénticas al baseline; datos de traza idénticos; suite headless y 15 pruebas del runner pasan. Timeouts, salidas fallidas, archivos viejos, JSON/hash erróneos y errores de motor no pueden aprobar una captura. El marcador del conjunto solo aparece al terminar todo correctamente.

El fixture conserva suelo/pista de referencia para L1–L4; el campo real tiene nueve vistas independientes. Un obstáculo añadido al campo en una copia no afecta al fixture. No se relajaron umbrales, no se añadió vegetación y no se implementó L5 por extraer `_build_field()`. Catálogo de aviones y nuevas pantallas UI conservan su implementación concurrente. Al cerrar VQ-01a quedaban VQ-01b, L5 y L6 pendientes; el siguiente registro cierra VQ-01b.


### VQ-01b — implementado (2026-10-06)

[Prueba y reproducción](research/visual-quality-implementation/VQ-01b/README.md): matriz de 66 casos nuevos (112 PNG con el conjunto previo), nueve pares de campo idénticos, datos de lectura con/sin autozoom y 36 inspecciones Stik/Extra. Inicio → Volar queda en tick 360 y verifica una cámara/un entorno. El logger v2 mantiene claves compatibles, guarda reloj monotónico y `delta` por separado, descarta el frame de transición del calentamiento e identifica ruta/caso/backend/configuración. Se conservan tres muestras de 60 s tras 10 s de calentamiento; son prueba del protocolo en llvmpipe, no rendimiento aprobado. La hoja de referencias conserva atribuciones/licencias fuera del runtime.

La suite, captura en clon limpio y exports verifican la entrega; no cambian física, geometría ni umbrales anteriores. La integración conserva el catálogo y la ampliación concurrente del P-51. Al cerrar VQ-01b, L5 era el siguiente cambio previsto; el registro siguiente cierra ese paso.

## 15. Registro L5 — campo compartido implementado

[Entrega y reproducción](research/visual-quality-implementation/L5/README.md): datos `openrc-field v1` validados antes de crear sesión, constructor compartido, cámara/composición desde la estación del piloto, error interactivo EN/ES y fallo explícito en automatización. Se conservan las medidas y materiales anteriores; no se añade vegetación ni se cambia el contacto con el suelo.

Prueba en clones limpios: suite completa, 158 comprobaciones de loader, 38 de integración, ocho entradas inválidas/rutas y dos pantallas de error; 112 capturas, 108 casos deterministas byte-idénticos y traza sin cambios. Los tres packs contienen el JSON y loader compilado, verificados sin árbol fuente; smoke de vuelo Linux. Siguiente paso: **L6a**.
