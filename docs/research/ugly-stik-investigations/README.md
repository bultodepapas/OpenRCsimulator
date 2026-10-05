# Diez investigaciones para mejorar el Ugly Stik

Fecha: 2026-10-05. [Plan revisado](../../UGLY-STIK-PLAN.md) · [Recursos descargados](../ugly-stik-resources.md).

El objetivo confirmado por el propietario es **Ugly Stik nitro .61 primero; mini y gigante después**. Se eligieron preguntas que afectan la próxima malla, sus articulaciones o la lectura desde el piloto. Cada estudio distingue fuente publicada, inspección/experimento realizado y propuesta pendiente.

| # | Pregunta elegida | Resultado útil | Efecto en el plan / evidencia |
| --- | --- | --- | --- |
| [01](01-03-geometry.md#investigación-01--dimensiones-nominales-y-discrepancias) | ¿Qué plano y dimensiones representan al Jensen? | El escaneo firmado y el anterior coinciden; difieren del cartucho de la miniatura local | Fuente principal identificada y valores candidatos con procedencia; inspección visual de PDFs |
| [02](01-03-geometry.md#investigación-02--perfil-diedro-incidencia-y-contornos-del-ala) | ¿Qué ala debemos modelar? | Nota de perfil semisimétrico y cota de elevación del diedro; sin coordenadas ni incidencia confirmadas | Trazar Jensen y separar incertidumbres; no copiar geometría Grid Leaks |
| [03](01-03-geometry.md#investigación-03--masa-cg-mandos-y-notas-del-kit) | ¿Qué CG, masa y mandos están documentados? | CG gráfico; faltan masa y recorridos de nuestra configuración | Separar origen visual y datos físicos; conservar límites estimados |
| [04](04-06-components.md) | ¿Cómo situar motor .61, escape, hélice y tren? | Manual y dibujo O.S. 61FX como referencia provisional de clase .61 | Cerrar una instalación identificada antes de ajustar morro/holguras; marca abierta |
| [05](04-06-components.md) | ¿Hay un modelo digital reutilizable? | Recurso REFLEX y documento del autor localizados; compatibilidad de malla no demostrada | Aprovechar documentación; la importación del avión ajeno no es requisito del primer modelo |
| [06](04-06-components.md) | ¿Qué fotos/decoración aportan evidencia? | Tres fotos identificadas de construcciones reales; modificaciones distinguibles | Clasificar por variante y vista; comparar apariencias sobre la misma geometría |
| [07](07-cad.md) | ¿Qué hay realmente dentro del CAD disponible? | Inspección de unidades, tipos, capas y mallas almacenadas | Extraer información por piezas; evitar transportar estructura interna completa al recurso de vuelo |
| [08](08-plan-metrology.md) | ¿Podemos medir por píxeles o por tamaño de página? | Una referencia rotulada y el tamaño PDF difieren en escala | Añadir calibración y verificación independiente; [ensayo reproducible](evidence/plan-scale.json) |
| [09](09-export.md) | ¿Se conservan escala, ejes y bisagras al importar? | Ensayo de GLB e importación Godot fuera de `app/` | Fijar contrato antes de modelar todas las piezas; ampliar luego a todos los mandos |
| [10](10-screen-readability.md) | ¿Qué detalle podrá ver el piloto? | Proyección calculada para distancia, resolución y orientación | Priorizar silueta/color; [CSV](evidence/screen-size.csv), falta validar percepción y render del avión |

## Evidencia guardada y cómo repetirla

- **Fuentes:** [catálogo](../ugly-stik-resources.md), manifiestos por grupo y hashes de las descargas. Los originales de terceros se guardan en `references/`, excluido de Git por la política actual del proyecto.
- **Valores candidatos:** [Jensen en JSON](evidence/jensen-geometry-candidates.json), sin incorporarlos al runtime.
- **Escala del plano:** `python3 research/ugly-stik/measure_plan.py`; requiere solo Python estándar para recalcular. Las selecciones están guardadas; si el PDF existe, verifica su hash.
- **Proyección:** `python3 research/ugly-stik/screen_size.py`; escribe JSON/CSV y comprueba invariantes matemáticos.
- **CAD:** procedimiento y resultados en [07](07-cad.md); biblioteca aislada, lectura sin modificar el original.
- **Importación:** procedimiento y límites en [09](09-export.md); escena experimental propia y comprobación de nodos en Godot.

La documentación no acredita un modelo de vuelo, una masa/inercia medida, una malla completa importada ni rendimiento en la GPU del usuario. Esas pruebas pertenecen a pasos posteriores del roadmap.

## Lecciones de esta ronda

Registro para incorporar a `LEARNINGS.md` cuando el desarrollador cierre su edición concurrente:

1. **La fuente de mayor resolución cambió un dato de trabajo.** El conflicto del área se pudo resolver para el plano firmado; una miniatura con otro cartucho no era una transcripción fiable de esa misma hoja.
2. **Abrir una descarga puede requerir la navegación prevista por su sitio.** La sesión HTTP pública con la ficha como referencia recuperó los PDFs que el navegador de investigación no había obtenido. Se guardaron archivos y hashes, no solo enlaces.
3. **Leer un plano no significa haberlo calibrado.** La rueda y el tamaño de página dieron escalas distintas; el ensayo no autorizó usar ninguna como escala global definitiva.
4. **Ausencia de objetos Mesh no significa ausencia de mallas.** El CAD contenía mallas de renderizado asociadas a caras de sólidos; había que inspeccionar ambas representaciones.
5. **La transformación de ejes debe comprobarse con una pieza móvil.** Un recurso pequeño permite detectar errores antes de terminar el avión y documentar dónde ocurre la conversión.
6. **La distancia decide qué detalle merece trabajo primero.** El cálculo de píxeles favorece contorno y color; el beneficio perceptual sigue requiriendo capturas y observación.
7. **El trabajo paralelo cambia rutas y estado del proyecto.** El plan conserva la actualización del desarrollador sobre Godot y mantiene pruebas separadas de `app/`.
