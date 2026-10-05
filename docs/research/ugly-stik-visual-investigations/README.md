# Diez investigaciones web para la siguiente entrega visual

2026-10-05 · **Diez preguntas investigadas; conclusiones incorporadas en la revisión 3 del [plan visual](../../UGLY-STIK-VISUAL-PLAN.md).** Son investigaciones nuevas sobre la apariencia y la implementación, complementarias a las [diez investigaciones iniciales](../ugly-stik-investigations/README.md).

Se consultaron páginas y manuales de fabricantes, documentación oficial Godot 4.7 y planos originales conservados por Outerzone. Cada informe distingue hallazgo, límite, propuesta y comprobación. Los datos comerciales aportan anatomía o materiales; no seleccionan automáticamente equipo para el Jensen. La observación local del inserto sobre bandas se identifica expresamente como tal.

| Investigación | Resultado que cambia la implementación | Aplicación |
| --- | --- | --- |
| [01 · Identidad y decoración](01-decoration-identity.md) | Durafly documenta una variante eléctrica/EPO con motor nitro simulado: referencia de acabado separada del glow .61. El intradós de las fotos sigue sin resolver | V01: ficha de procedencia por superficie |
| [02 · Film y acabado](02-covering-finish.md) | Los fabricantes describen una película continua y brillante; las arrugas son defectos, no detalle necesario | V02: piel limpia, juntas justificadas y prueba de luz rasante |
| [03 · Anatomía del .61](03-engine-detail.md) | Separar motor, bancada, carburador, aguja y glowplug; evitar cable de chispa permanente inventado | V03: piezas identificables y conexiones visibles |
| [04 · Escape y combustible](04-exhaust-fuel.md) | Presión del silenciador, alimentación y puente aguja–carburador tienen destinos distintos | V03/V06: diagrama de rutas antes de modelar tubos |
| [05 · Hélice y cubo](05-propeller-hub.md) | Sección variable y torsión, montaje del cubo; APC publica datos geométricos para una futura referencia concreta | V03/V07: pala con volumen y herrajes ordenados |
| [06 · Servos y montaje](06-servo-installation.md) | Carcasa estándar documentada, orejas, gomas, ojales, tornillos y cable; disposición Jensen conservada | V05: soporte completo visible en mantenimiento |
| [07 · Transmisiones](07-control-linkages.md) | Cuerno alineado con bisagra y varilla de longitud constante, con terminales reales | V04/V05: cierre geométrico y barrido de posiciones |
| [08 · Bandas y tren](08-gear-fasteners.md) | Inserto Jensen: bandas #64; catálogos DU-BRO: collarín y abrazadera con función de montaje | V06: bucles planos y fijaciones con apoyo |
| [09 · UV y materiales](09-materials-atlas.md) | Compatibility sin Decal3D; atlas sobre la malla, UV, mipmaps y acabado por material. El albedo multiplica la textura | V02: prueba pequeña de atlas antes del avión completo |
| [10 · Lectura y rendimiento](10-readability-performance.md) | MSAA 4× no resuelve por sí solo las marcas finas; medir draw calls. LOD de importación no cubre el constructor actual | V08: capturas en movimiento, métricas reales y optimización condicionada |

## Decisiones adoptadas en el plan

Primero resolver composición y piel del avión en el renderizador actual. Una prueba pequeña debe mostrar rojo, blanco y negro correctos, sin teñir el atlas por duplicado; comprobar marcas lejanas y rasantes con mipmaps. Después completar el motor y sus rutas, mandos con geometría consistente, instalación interna y herrajes. El microdetalle fijo se agrupa; las piezas móviles se crean una vez.

La fuente de apariencia sigue siendo las fotos A/B del propietario y la geometría sigue siendo Jensen .61. Los manuales O.S., Hitec, Futaba y DU-BRO ayudan a representar piezas concretas sin convertir el modelo en una combinación de especificaciones comerciales supuestamente confirmada.

Los informes 09/10 citan la serie **Godot 4.7**; el proyecto fija **4.7.2**. La compatibilidad descrita se deberá comprobar al implementar con ese binario. Se revisó el código existente, pero esta ronda no ejecutó prototipos de material, benchmarks ni nuevas pruebas de percepción.

## Entregables y trazabilidad

Los diez informes contienen las fuentes enlazadas junto a los hallazgos. [sources.json](sources.json) reúne las URLs citadas y los informes que las usan para facilitar su recuperación; no es una afirmación de licencia de reutilización ni una copia de los sitios. La lectura específica de las fotos permanece en el [expediente A/B](../ugly-stik-visual-photo-brief.md).

Sigue pendiente ejecutar el plan visual. La investigación cambia decisiones y criterios de aceptación; no significa que el motor detallado, el atlas ni los servos estén implementados.
