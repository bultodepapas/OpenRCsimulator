# Doce investigaciones para mejorar el humo RC

**Fecha:** 2026-10-05. **Entrega:** segunda revisión del [plan de humo](../../SMOKE-PLAN.md). Se conserva la [investigación inicial](../rc-exhaust-smoke.md) como antecedente.

Se investigaron doce preguntas distintas en documentación oficial, código fuente, repositorios de autores y manuales de fabricantes. Cada estudio distingue lo observado, la decisión para este proyecto y lo que falta comprobar. La referencia técnica es **Godot 4.7.2-stable con Compatibility**, no una demo ejecutada con Forward+.

Se ejecutó un [experimento sintético de emisión en movimiento](godot-evidence/README.md), con proyecto y PNG conservados. No se integró humo en la app, no se instalaron addons y no se midió el rendimiento del efecto en vuelo. Los demás ensayos propuestos siguen pendientes. Las fuentes móviles `main`/`stable` se identifican como tales; antes de adoptar código o herramientas nuevas hay que fijar su revisión exacta.

## Índice y decisiones

| # | Investigación | Pregunta resuelta | Cambio al plan |
| --- | --- | --- | --- |
| [01](01-godot-backends.md) | Godot y backends | ¿GPU o CPU y qué API soporta Compatibility? | Dos emisores GPU nativos; alternativas solo por un fallo medido |
| [02](02-clock-captures.md) | Reloj, pausa y capturas | ¿Una solicitud de tiempo también procesa un emisor fuera de cámara? | Comprobar tiempo + encolado, RID correcto y vuelta al frustum |
| [03](03-moving-emitter.md) | Emisor en movimiento | ¿Por qué una estela puede tener huecos aunque haya muchas partículas? | Prueba de nacimientos entre poses y continuidad a baja tasa de frames |
| [04](04-repositories-addons.md) | Repositorios y addons | ¿Qué demos o plugins conviene reutilizar? | Referencias inspeccionadas; no importar configuraciones Forward+ enteras |
| [05](05-materials-transparency.md) | Transparencia y profundidad | ¿Cómo suavizar cortes sin romper orden y visibilidad? | Probar proximity fade nativo antes de shader propio |
| [06](06-authoring-textures.md) | Herramientas de autoría | ¿Ruido procedural, textura pintada o simulación offline? | Máscara pequeña reproducible; herramientas avanzadas condicionadas |
| [07](07-aux-radio.md) | Radio y perfiles AUX | ¿Cómo soportar eje/botón sin estropear AETR? | Bloque opcional validado aparte, modos nivel/flanco y rearme por perfil |
| [08](08-pump-behavior.md) | Bomba real frente a efecto | ¿Qué comportamiento respaldan los fabricantes? | OFF inmediato y nube residual por partículas existentes; cifras visuales estimadas |
| [09](09-wind-advection.md) | Viento y advección | ¿Qué mueve la nube vieja y qué existe ya en el proyecto? | Calma en v1; un solo campo de viento futuro para avión y humo |
| [10](10-testing-sequences.md) | Tests y secuencias | ¿Cómo detectar defectos que un PNG aislado no muestra? | Movie Maker/PNG + FLIP actual, máscaras distintas y casos negativos |
| [11](11-profiling-budgets.md) | Rendimiento y diagnóstico | ¿Pocas draw calls implican humo barato? | Ensayos de overdraw, release sin grabación y herramientas por plataforma |
| [12](12-git-assets-export.md) | Git, assets y export | ¿Cómo reproducir el efecto fuera del checkout del autor? | Procedencia/licencia, importación y prueba visual de paquete desde clon limpio |

## Selección de herramientas

| Categoría | Selección | Motivo y condición |
| --- | --- | --- |
| Runtime | Godot nativo: GPUParticles3D, ParticleProcessMaterial, QuadMesh, StandardMaterial3D | Menor integración inicial; verificar las rutas temporales exactas en SM-00 |
| Referencias visuales | BasicParticleEffects, VFX in Godot y demo oficial de partículas | Estudiar separación de capas/materiales; no equivalen a una escena aprobada para GLES3 |
| Edición de partículas | Inspector Godot; Particle Controls como opción futura | Evitar dependencia de editor sin una mejora de trabajo demostrada |
| Autoría | Gradiente/ruido propio primero; estudiar herramientas offline en [06](06-authoring-textures.md) | Fuentes pequeñas y reproducibles; el juego no necesita un simulador de fluidos |
| Regresión | Movie Maker/PNG; FLIP 1.7, NumPy 2.5.3 y Pillow 12.3.0 ya fijados | Reutilizar el harness y corregir separación de máscaras |
| Vídeos | FFmpeg opcional | Clips para revisar, PNG para comparar; fijar versión cuando se use |
| Rendimiento | Profiler/Visual Profiler + logger propio; RenderDoc opcional | Cada herramienta mide algo distinto; no interpretar ausencia de métrica como coste cero |
| Referencia de benchmark | godot-benchmarks | Leer metodología; la media de una escena aislada no sustituye p95/p99 en vuelo |
| Trabajo paralelo | Git worktree / clon limpio y manifiestos de recursos | Aislar experimentos y detectar dependencias de caché; sin Git LFS por anticipado |

Las licencias y límites de cada candidato están en su estudio. No se incorporó código ni material gráfico externo. Una licencia del código no se extiende automáticamente a las imágenes de muestra.

## Qué hacer primero

El primer trabajo de implementación es **SM-00**, dividido en comprobaciones breves: soporte visual básico; control temporal con salida/entrada de cámara; emisión rápida; material/transparencias. Solo después se integra escape tenue y, encima, bomba AUX. Un fallo de continuidad o reloj no se corrige ocultándolo con sprites más grandes ni agregando un plugin de efectos completo.

El catálogo [sources.json](sources.json) reúne los enlaces citados y los estudios que los usan; es un índice de fuentes, no un informe de ejecución ni una descarga de contenido de terceros. Los aprendizajes aceptados y pasos revisados están en el plan principal.

La [validación documental](validation.json) registra los doce informes, 73 URLs de fuentes y la comprobación de enlaces locales. El único ensayo renderizado de esta ronda está descrito con sus límites en [godot-evidence](godot-evidence/README.md).
