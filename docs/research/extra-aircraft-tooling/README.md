# Doce investigaciones de herramientas para Extra 300 y Ugly Stik

2026-10-05 · Godot **4.7.2**, **Compatibility**, física propia en `float64`. Investigación con documentación oficial, repositorios de autores y lectura del código local. Complementa las [diez investigaciones anteriores del Stik](../ugly-stik-tooling-investigations/README.md) con problemas del ala trapezoidal, cabina, hélice y coexistencia de dos aviones.

**Resultado:** doce investigaciones completas; adopción y ensayos propuestos pendientes. No se instalaron dependencias ni se modificó la aplicación en esta ronda. [Plan Extra](../../EXTRA-300-PLAN.md) · [recursos geométricos y fotográficos](../extra-300-resources.md).

## Preguntas y decisiones

| # | Investigación | Aplicación al Extra y mejora del Stik | Prioridad propuesta |
| --- | --- | --- | --- |
| 01 | [ezdxf, unidades y curvas](01-03-geometry-pipeline.md#investigacion-01) | Recuperar contornos del CAD con escala comprobada; reutilizar medición para planos Stik | EX-01: ensayo offline acotado |
| 02 | [Shapely y trimesh](01-03-geometry-pipeline.md#investigacion-02) | Validar contornos, huecos y orientación; complementar holguras de ambos modelos | EX-01/04: solo ante necesidad concreta |
| 03 | [Blender, loft y glTF](01-03-geometry-pipeline.md#investigacion-03) | Carenado/cabina curvos; opción de autoría para piezas complejas del Stik | EX-02/10: constructor nativo primero |
| 04 | [Bisagras oblicuas e interpolación](04-06-rig-editor-resources.md#investigacion-04) | Alerones Extra sobre eje real; movimiento de mandos suave y verificable para ambos | EX-04: adoptar contrato de marcos locales |
| 05 | [Materiales y recursos por instancia](04-06-rig-editor-resources.md#investigacion-05) | Dos aviones sin contaminación de acabado/estado; caché compartida explícita | EX-03: adoptar aislamiento |
| 06 | [Inspector y gizmos del editor](04-06-rig-editor-resources.md#investigacion-06) | Visualizar datum, CG, cuerda y bisagras; menos errores de coordenadas en ambos | EX-01/04: visor simple antes de plugin |
| 07 | [Cabina transparente en Compatibility](07-09-rendering.md#investigacion-07) | Elegir solución de canopy; controlar brillos y transparencias sin cambiar renderer | EX-10: comparar alternativas |
| 08 | [MSAA, mipmaps, filtrado y LOD](07-09-rendering.md#investigacion-08) | Mantener orientación y silueta a distancia; preservar estrellas Extra y cruces Stik | EX-10: medir legibilidad antes de simplificar |
| 09 | [Hélice y aliasing temporal](07-09-rendering.md#investigacion-09) | Representación visual de RPM útil en los dos nitro; pausa y capturas coherentes | EX-10: ensayo de palas/disco |
| 10 | [SubViewport, inspección y sombras](10-12-inspection-loading-aero.md#investigacion-10) | Capturas por avión y máscara propia; eliminar proporciones duplicadas del Stik | EX-02/03/10: parametrizar primero |
| 11 | [ResourceLoader y exportación](10-12-inspection-loading-aero.md#investigacion-11) | Cambio Stik → Extra → Stik con recursos completos y sesión coherente | EX-03/11/12: síncrono primero, hilos si se justifican |
| 12 | [XFOIL/AVL para datos de vuelo](10-12-inspection-loading-aero.md#investigacion-12) | Contraste offline de perfiles/planta y derivados; revisar supuestos de ambos | EX-05/09: después de fijar geometría |

## Qué haría primero

1. **Extra sencillo, bien medido:** escoger cotas de control del plano, fijar datum y curvas necesarias; construir la primera forma con los helpers nativos. Mantener mediciones reservadas para comprobar escala, no ajustar todo contra las mismas cotas.
2. **Dos modelos coherentes:** catálogo mínimo, geometría/datos del mismo ID, materiales inmutables y bisagras con marcos propios. Preservar pruebas y capturas Stik, además de añadir las del Extra.
3. **Comparación visual acotada:** cabina, hélice y acabado en las mismas cámaras; evaluar legibilidad en movimiento, cielo y suelo. Medir coste en hardware identificado antes de instalar optimizadores o cambiar renderer.

Blender, ezdxf, Shapely/trimesh y los solvers son candidatos offline; investigar una herramienta no la convierte en dependencia del juego. Todo artefacto adoptado necesita versión exacta, licencia y entrada/salida reproducible. Las APIs nativas se contrastaron con documentación 4.7; su comportamiento concreto en nuestras mallas requiere los ensayos descritos.

## Evidencia y límites

Cada investigación separa lectura del código, hechos documentados, recomendación y prueba pendiente. Los umbrales propuestos son criterios de ingeniería, no mediciones realizadas. Las referencias Extra .40 siguen siendo visuales; dimensiones y primer perfil de vuelo corresponden al GPMA0236 .60. Las bibliotecas geométricas no identifican aerodinámica y los solvers no validan por sí solos acrobacia.

El árbol tiene trabajo concurrente: los hashes y fuentes de [sources.json](sources.json) describen esta entrega documental; los puntos de integración deben releerse al implementar. [validation.json](validation.json) recoge el control de doce temas, enlaces y hashes. No se ejecutó la suite de Godot por este cambio exclusivamente documental.

Verificación de esta entrega: **12 temas, 63 URLs de fuentes, 146 enlaces locales y 12 anclas de tema comprobados**, sin destinos ausentes. Los cuatro informes tienen SHA-256 registrado y verificado; el control de espacios y `git diff --check` del alcance documental pasó. También se repitió el recuento básico del DXF local: 2.063 polilíneas cerradas y 167 valores de bulge no nulos, con el hash indicado en la investigación 01. Ese conteo no sustituye la importación/calibración propuesta.
