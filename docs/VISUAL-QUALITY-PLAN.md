# Calidad visual del simulador: dirección, herramientas y entregas

2026-10-05 · **Plan propuesto; no implementado.** Preferencia del propietario: «una mezcla de todos, con opciones para subir calidad»: realismo RC, presentación limpia y buen rendimiento, con calidad escalable. Equipo disponible para probar: **Ryzen 9 5900X, RTX 3090 y 64 GB RAM**. Resolución, sistema operativo y equipo modesto de referencia todavía sin definir.

La recomendación es construir **un campo RC reconocible, un avión con materiales convincentes y una imagen estable en movimiento**, conservando Compatibility como base. Primero composición, escala, contraste y materiales; después efectos caros. Forward+ merece una comparación controlada, no una migración asumida.

Este documento coordina [ROADMAP](../ROADMAP.md), [paisaje](LANDSCAPE-PLAN.md), [Extra 300](EXTRA-300-PLAN.md), [acabado Stik](UGLY-STIK-VISUAL-PLAN.md), [menú](MENU-PLAN.md), [humo](SMOKE-PLAN.md) y [viento](WIND-PLAN.md). Los pasos existentes conservan sus IDs. Los IDs **VQ** identifican únicamente la coordinación y los ensayos nuevos de esta propuesta; no declaran nuevas entregas completadas del roadmap.

## 1. Qué tenemos realmente

Se revisaron scripts, configuración, planes previos y fuentes oficiales. Se produjeron e inspeccionaron **tres capturas nuevas**: [piloto](research/visual-quality-baseline-2026-10-05/pilot.png), [inspección](research/visual-quality-baseline-2026-10-05/inspect.png) y [horizonte](research/visual-quality-baseline-2026-10-05/horizon.png). [Protocolo y límites](research/visual-quality-baseline-2026-10-05/README.md).

| Evidencia local | Consecuencia |
| --- | --- |
| [get-godot.sh](../app/get-godot.sh) y binario ejecutado: 4.7.2-stable; [project.godot](../app/project.godot): Compatibility | Evaluar herramientas contra esta combinación concreta |
| `msaa_3d=2` | Ya es **MSAA 4×**, no 2×. El valor es un enum: [Viewport](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#enum-viewport-msaa) |
| [atmosphere.gd](../app/render/atmosphere.gd): cielo propio, ACES, exposición, bruma, reflejo de cielo y nubes | L1–L4 ya existen; afinar con pruebas A/B, sin volver a implementarlos |
| [main.gd](../app/main.gd), `_build_world`: plano de suelo y plano de pista; capturas sin vegetación ni objetos del campo | L5–L11 son la mejora más evidente de composición y escala |
| [ground.gdshader](../app/render/ground.gdshader): tile de hierba en coordenadas mundiales con mipmaps y muestreo anisotrópico | Conservar ese filtrado; falta romper repetición, introducir superficies y transiciones |
| [shadow.gd](../app/render/shadow.gd): máscara planar genérica, geometría/datum propios del Stik | Extra necesita su propia silueta; alabeo extremo y suelo irregular requieren otro tratamiento |
| [pilot_camera.gd](../app/render/pilot_camera.gd): seguimiento y autozoom; horizonte puede salir del cuadro | Calidad incluye encuadre y lectura del vuelo, además de materiales |
| [airplane.gd](../app/render/airplane.gd) sigue construyendo Stik; [extra_300s_model.gd](../app/aircraft/extra_300s_model.gd) se declara preview EX-02 | No presentar las capturas del Stik como validación del Extra; coordinar EX-03/04/10 |
| Captura piloto: 101 draw calls visibles, 46.842 primitivas; horizonte: 2 y 4 | El escenario está casi vacío. Medir avión y paisaje por separado; estos números no son FPS ni presupuesto universal |

El árbol contenía cambios concurrentes. Las capturas corresponden a `--scripted`, 1280 × 720, llvmpipe; no son un benchmark ni un ensayo de vuelo físico. No se modificó `app/` en esta entrega.

## 2. Dirección artística que une las tres prioridades

**Realismo en lo que informa al piloto:** proporciones, materiales, tamaño de pista y árboles, dirección del sol, altura percibida, orientación superior/inferior del avión y viento coherente. **Simplificación deliberada en lo que distrae:** microdetalle distante, ruido del terreno, HUD, vegetación de fondo y reflejos que borran la pintura.

Crear en VQ-01 una hoja de referencia con fotos licenciadas de campo RC, materiales del avión y tres encuadres: piloto, pasada baja e inspección. Cada referencia debe responder una pregunta concreta. No usar una imagen promocional con lente, exposición o profundidad de campo distintas como objetivo del vuelo normal.

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

**Perfiles propuestos, todavía sin calibrar:**

| Ajuste | Bajo | Equilibrado — candidato por defecto | Alto | Ultra — experimento |
| --- | --- | --- | --- | --- |
| Backend | Compatibility | Compatibility | Compatibility | Forward+ |
| Resolución 3D | Nativa; escala reducida solo a elección del usuario | Nativa | Nativa | Nativa; comparar TAA/FSR2 aparte |
| MSAA | Off / 2× | 4× actual | 4×; 8× solo si compensa | Comparar 4× con temporal en movimiento |
| Texturas principales | Límite inicial 1K | 2K donde haya diferencia visible | 2K; 4K para primer plano justificado | Mismos assets con límites mayores si se justifican |
| Árboles/hierba | Horizonte conservado, hierba geométrica off | Árboles por sectores, hierba cercana limitada | Más variedad y densidad cercana | Sombras adicionales y vegetación según presupuesto |
| Sombras | Silueta planar por avión | Igual; revisar apoyos y contacto | Probar sombra nativa con control de color | PSSM y autosombra del avión, calibradas |
| Reflejos / AO | Cielo, AO de asset donde proceda | Cielo y probe estático localizado | Probe + SSAO opcional probado | Probe; SSR/GI solo si aportan una mejora medible |
| Humo | Reducido / off | Emisión moderada | Más continuidad y resolución | Coste de transparencia bajo presupuesto |

Los límites de textura, densidad y MSAA son **estimaciones de diseño**, no mediciones. Cambiar preset no puede alterar fuerzas, obstáculos, viento, reloj, entradas o trazas. Un árbol que sea obstáculo debe seguir representado en Bajo mediante una silueta sencilla. Reducir calidad elimina ornamentación, no referencias necesarias para volar.

Exponer preset y ajustes individuales mediante los ajustes del [plan de menú](MENU-PLAN.md); mostrar «Personalizado» al cambiarlos. Guardar versión del esquema y aplicar/restaurar sin reiniciar el vuelo cuando el motor lo permita. El cambio de backend se trata como configuración de arranque con reinicio y ruta de recuperación, no como un slider instantáneo.

**Gate Forward+:** ejecutar la misma escena, resolución y trayectoria en ambas rutas, recalibrando color pero conservando contenidos. Registrar legibilidad, estabilidad temporal, frame time, memoria, arranque y export en equipos objetivo. Adoptarlo como perfil soportado solo si mejora sombras/materiales de forma visible y mantiene el presupuesto. Los shaders propios de niebla/color y profundidad necesitan revisión: no se promete paridad cambiando una sola línea.

## 4. Entregas pequeñas y comprobables

Orden recomendado: **VQ-01 → L5 → L6a/b/c → L7 → L9a/b/c → VQ-02**. Luego vegetación próxima, cámara, sombras, hélice y perfiles. Un paso conserva un resultado volable y reversible.

Esfuerzo expresado en días de trabajo concentrado de una persona familiarizada con el repo; incluye prueba local, no esperas de playtest ni investigación abierta. Son estimaciones, no fechas comprometidas. Dividir cada fila con varios IDs en cambios por ID.

| Entrega / correspondencia | Resultado visible y alcance | Dependencia | Prueba y criterio de cierre | Esfuerzo estimado |
| --- | --- | --- | --- | --- |
| VQ-01 · L0 / D7 | Hoja visual, escena de comparación, estados/cámaras fijos y presupuesto inicial; ampliar evidencia al Extra en su visor | Esta auditoría | Capturas y vídeo base etiquetados por avión/backend; no mezclar inspección con vuelo | 0,5–1 d |
| L5 | Archivo de campo y superficies con escala/procedencia; conserva aspecto actual | VQ-01 | Pruebas del loader y captura de paridad | 0,5–1,5 d |
| L6a/b/c | Primer anillo de árboles con claros; máximo unas pocas especies | L5 | Orientación del avión frente a árboles; contadores y capturas 360° | 2–4 d |
| L7 | Colinas y bosque distante con bruma coherente | L6 | Horizonte sin cortes ni aspecto de muro; ninguna colisión nueva implícita | 0,5–1,5 d |
| L9a/b/c | Hierba menos repetitiva, bandas de siega discretas, pista integrada en suelo | L5 | Vista cenital y aproximación rasante; borde de pista sigue reconocible | 1,5–3 d |
| VQ-02 · EX-10 / acabado Stik | Catálogo pequeño de acabados: pintura/film, plástico, caucho, metal y cabina | VQ-01; coordinar modelos | Mismo avión/luz en A/B; blancos sin clipping, pintura reconocible, sin parpadeo de normales | 1–3 d |
| L10 → L11a/b | Manga, mesas, valla y pocos objetos de escala; después hierba cercana y arbustos | L5/L9 | Tamaños documentados; calle de vuelo despejada; coste por sector | 2–4 d |
| VQ-03 · D7 / EX-10 | Cámara opcional que conserve referencia de horizonte cuando sea viable; transiciones de zoom acotadas | VQ-01 | Misma maniobra a 30/60/144 fps, sin oscilación ni demora que haga perder el avión; opción de desactivar | 1–2 d |
| VQ-04 · L3 / EX-10 | Sombra con contorno/datum de cada avión; evaluación de autosombra | EX-03/04 para Extra | Pasada baja, alabeo y contraluz; forma/sentido correctos y color estable | 1–2 d |
| VQ-05 · EX-10 / G2 visual / UI-02 | Hélice con barrido a RPM alto, pala legible a RPM bajo y pausa coherente | Fuente fiable de RPM; coordinación UI | Vídeo 30/60/144 fps, reinicio/pausa/captura; empuje e inercia sin cambios | 1–2 d |
| VQ-06 · ajustes UI | Bajo/Equilibrado/Alto, persistencia y ajustes avanzados | Mediciones anteriores | Reabrir app conserva perfil; cambiar calidad no altera traza ni oculta obstáculos | 1–2 d |
| VQ-07 · Gate L | Ensayo aislado Forward+, con assets comunes | VQ-02/04 y GPU objetivo | Comparación de calidad y coste; decisión documentada de adoptar/posponer | 1–3 d |
| SM / L15 / M5 | Humo, manga y vegetación coherentes con tiempo/viento | Planes de humo/viento y mediciones | Pausa/reinicio correctos, estela continua y sin ocultar el avión | Estimar en sus planes |

No reabrir como pendientes los acabados Stik ya entregados en [v4](UGLY-STIK-PLAN-v4.md) y [v5](UGLY-STIK-PLAN-v5.md). VQ-02 compara y corrige carencias observadas, no sustituye esos modelos. La cabina del Extra se valida en su preview mientras la integración de vuelo sigue su propio plan.

Coordinar cualquier edición de `app/aircraft/`, `render/airplane.gd` y geometría con el frente de modelos. Preservar los nodos `airplane`, `propeller` y `*_hinge`. La presentación consume el estado existente: física/simulación sigue usando floats de 64 bits y no recibe Vector3/Basis del render. Los materiales compartidos por caché se tratan como inmutables; un efecto exclusivo de un avión necesita su propia instancia.

Primera entrega visible sugerida: **un campo con arbolado, claros, colinas suaves y pista mejor integrada**, con las mismas nubes y avión actuales. Es una unidad útil de evaluación antes de ampliar el escenario o adoptar plugins de terreno.

## 5. Técnicas y trucos con aplicación concreta

Son propuestas de implementación, salvo donde se señala evidencia existente. Cada una debe demostrar una mejora en su escena de prueba.

| Técnica | Aplicación al simulador | Coste o precaución |
| --- | --- | --- |
| **Detalle según píxeles ocupados** | A distancia conservar silueta, colores superior/inferior y superficies; ocultar tornillos antes de simplificar el ala | El autozoom cambia el tamaño proyectado: una distancia fija no basta para el avión |
| **Macro + meso + micro en suelo** | Grandes variaciones suaves, zonas segadas y textura fina; evitar que cada nivel tenga la misma escala | Dos muestras adicionales ya cuestan fill rate; comparar contra L9b existente antes de sumar capas |
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

La [investigación de herramientas](research/visual-quality-tools-2026-10-05.md) registra fuentes primarias, licencias, compatibilidad declarada y pruebas pendientes. Selección propuesta:

| Opción | Uso aquí | Decisión inicial |
| --- | --- | --- |
| Godot nativo: StandardMaterial3D, ShaderMaterial, MultiMesh, profiler, capturas | Iluminación, materiales, terreno simple y vegetación | Base de las primeras entregas; ninguna dependencia runtime adicional |
| Blender → glTF/GLB | Props, UV, normales, reducción de malla y horneado de atlas | Usarlo cuando el asset lo necesite; export explícito y versión fijada. Conservar pivotes y contratos del avión |
| Material Maker | Generar texturas PBR de suelo, caucho o pintura | Ensayo offline pequeño; exportar mapas, no incorporar un grafo nuevo al runtime |
| Poly Haven / ambientCG | Materiales y HDRI de referencia o producción | Elegir pocos assets, resolución ajustada y procedencia por archivo; comprobar escala física |
| Kenney / Quaternius | Props y vegetación como punto de partida | Elegir una familia visual coherente; no mezclar estilos solo porque sean gratuitos |
| Terrain3D | Esculpir/pintar campos grandes en editor | Ensayo condicionado a necesidad de autoría. El render del terreno no reemplaza nuestro sampler físico float64 |
| HTerrain | Alternativa de terreno para comparar | Un solo ensayo comparativo si el terreno propio limita; no mantener dos addons |
| ProtonScatter | Colocación de vegetación por reglas | Evaluar si editar campos a mano se vuelve costoso; guardar distribución reproducible y perfil simple sin plugin obligatorio |
| Pillow / NumPy / FLIP ya presentes en tooling visual | Máscaras del avión, diferencias locales y galerías | Reutilizar [requirements-visual.txt](../app/tests/requirements-visual.txt) y [visual-env.sh](../app/tests/visual-env.sh); no añadir otro framework |

No instalar toda la lista. Cada candidato debe resolver un paso concreto, quedar fijado a versión/revisión exacta y demostrar importación/exportación limpia. Licencia de herramienta, licencia de cada asset y compatibilidad del backend son verificaciones diferentes. Esta ronda no instaló addons ni descargó paquetes de assets.

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

## 8. Presupuesto y comprobación

**Equipo alto conocido:** Ryzen 9 5900X / RTX 3090 / 64 GB, informado por el propietario; no medido en esta sesión. Propuesta de matriz: 1080p, 1440p y 4K en ese equipo; añadir un portátil con GPU integrada o GPU modesta real para Bajo. Probar un límite de FPS en la 3090 no simula la arquitectura, memoria ni drivers de ese segundo equipo.

Objetivos iniciales **estimados**: Equilibrado a 60 Hz (p95 del frame ≤ 16,7 ms) y opción de respuesta alta a 120 Hz (≤ 8,3 ms) donde el hardware lo permita. Para Ultra, comenzar midiendo 1440p y 4K a 60 Hz. No prometer esos valores antes del benchmark. RAM del sistema, VRAM y capacidad de render son presupuestos distintos.

Conservar los límites provisionales de [LANDSCAPE-PLAN](LANDSCAPE-PLAN.md): paisaje ≤ 300 draw calls y ≤ 1 M primitivas; vegetación arbórea ≤ 24 calls y hierba ≤ 5; avión aparte. Son guardas iniciales, no objetivo de llenar el presupuesto. El frame time medido manda. El contador de memoria Godot no sustituye una lectura de memoria dedicada en hardware real.

Protocolo por entrega:

1. Congelar revisión, avión, campo, semilla, reloj, trayectoria, cámara, resolución y preset. Añadir metadata de OS/GPU/driver/backend. Distinguir primera carga de recorrido ya calentado.
2. Capturar piloto y primer plano, cielo/horizonte/árboles/suelo, pasada baja y alabeo. Evaluar el Extra en su visor hasta que esté integrado. Para localizar píxeles del avión, usar un par con/sin avión y sin humo ni sombra contaminando la máscara.
3. Comparar repetición bajo el mismo entorno; usar FLIP y regiones de interés entre entornos distintos. Un promedio de toda la pantalla puede ocultar la desaparición de un avión de pocos píxeles. Mantener revisión humana de orientación: ninguna métrica sustituye esa prueba.
4. Reproducir un tramo idéntico al menos tres veces en export de release; propuesta de 10 s de calentamiento y 60 s de muestra, excluyendo carga. Registrar p50/p95/p99 de frame time, picos por actualización de cielo/probes, CPU/GPU y memoria. Ampliar el logger actual si no registra todo: hoy el modo `--frametimes` por sí solo no da ese informe completo.
5. Usar capturas reales con renderer para detectar errores de shader; `--headless` usa renderer dummy. Para implementación, ejecutar `app/test.sh`, pruebas de captura afectadas y export smoke cuando cambien recursos/dependencias. Con cambios de paths/imports, verificar clon limpio según AGENTS.md.
6. Registrar la prueba en commit y LEARNINGS. Si un efecto reduce legibilidad o excede presupuesto, atenuarlo, convertirlo en opción o retirarlo. No regenerar goldens físicos para aprobar un cambio puramente visual.

El sol nativo requiere un A/B especial: [issue #90259](https://github.com/godotengine/godot/issues/90259) documenta cambios de brillo con sombras en Compatibility; el proyecto ya registró una reproducción local en L3. No asumir que subir resolución del shadow map lo corrige. El gate debe observar blancos, tonos y pasadas de render además de la forma de sombra.

## 9. Alcance y decisiones pendientes

Quedan por medir resolución/monitor/OS de la 3090, hardware de gama baja, el coste real de cada perfil y orientación humana contra arbolado. El acabado final se decide con la primera entrega visible y sus referencias, sin bloquear la investigación de herramientas.

Se posponen mundos enormes, erosión compleja, nubes volumétricas como requisito base, GI dinámica generalizada, ray tracing y fotogrametría pesada. Ninguno resuelve primero el campo vacío o la lectura del avión. Un panorama de campo real sigue siendo alternativa posterior de L16/L17, con proxies de oclusión/colisión y límites claros para cámaras móviles.

**Siguiente cambio concreto:** VQ-01 formaliza referencias y escenas; **L5** mueve los datos del campo sin alterar su aspecto; **L6a/b/c** entrega el primer horizonte arbolado. En cuanto existan materiales y escena de comparación, la RTX 3090 permite adelantar el ensayo VQ-07, manteniéndolo aislado de la ruta para equipos modestos.
