# Fuentes de recursos y búsqueda antes de crear

2026-10-06. Integra el [segundo catálogo aportado](asset-sources-user-input-2026-10-06.txt) en el [plan visual §6](../VISUAL-QUALITY-PLAN.md#6-herramientas-bibliotecas-y-recursos). Complementa la [selección de plugins anterior](visual-quality-supplement-2026-10-06.md). Fuentes consultadas, sin descargar packs, importar contenido ni instalar herramientas.

Integridad: copia del adjunto byte a byte; SHA-256 `ec315527c036aa51c0c2b241274f12799663eded8977a0e7d57c06617d99fcdf`. El texto de entrada conserva las recomendaciones recibidas; las decisiones vigentes están aquí y en el plan.

El cambio de trabajo es concreto: ante un recurso genérico nuevo, revisar primero el repo y después una lista corta de fuentes. Decidir entre reutilizar, adaptar o crear según coste total, lectura en vuelo, licencia y facilidad de mantenerlo. No sustituir sistemas existentes que ya cumplen sus pruebas para satisfacer la regla de búsqueda.

## Fuentes nuevas verificadas

| Fuente primaria | Qué se verificó | Uso y condición en el simulador |
| --- | --- | --- |
| [cgbookcase](https://www.cgbookcase.com/textures) | El catálogo declara CC0 1.0 para sus texturas. La ficha [Grass 01](https://www.cgbookcase.com/textures/grass-01) ofrece distintos mapas, incluido normal DirectX | Tercera fuente de superficies L9/VQ-02 tras ambientCG/Poly Haven. Seleccionar mapas necesarios, revisar convención del normal con el pipeline ya documentado y escala física; 1K–2K inicial. Marcas viales se adaptan al shader/geometría del campo, no se asume soporte de Decal |
| [Poly Pizza](https://poly.pizza/) y sus [términos](https://poly.pizza/docs/tos) | Modelos low-poly aportados por usuarios; se aplica la licencia Creative Commons de cada contenido al descargarlo | L6/L10/L11: buscar árboles, vallas, bancos y rocas. Priorizar fichas CC0 y guardar autor/licencia del archivo. No declarar toda la plataforma CC0 ni todos sus modelos disponibles en el mismo formato |
| [Godot Asset Store](https://store.godotengine.org/), [anuncio oficial](https://godotengine.org/article/introducing-the-godot-asset-store/) y [roadmap](https://store.godotengine.org/roadmap/) | Presentado en 2026; sigue en beta. Planea suceder a Asset Library, que continúa siendo necesaria para contenido previo. El catálogo muestra licencias distintas, incluso source-available | Primer buscador de plugins nuevos junto al upstream; licencia/revisión por paquete. Estar publicado por la plataforma oficial no acredita Godot 4.7.2 Compatibility ni los tres exports de nuestra app |
| [Godot Asset Library](https://docs.godotengine.org/en/4.7/community/asset_library/what_is_assetlib.html) | Godot documenta contenido gratuito con licencias open source diversas | Complementar la búsqueda del Store; seguir el enlace al código/release y no importar una demo entera por su licencia de cabecera |
| [Godot Shaders, licencias](https://godotshaders.com/license/) y [filtros](https://godotshaders.com/shader/) | El sitio distingue CC0, MIT y GPLv3. La licencia elegida cubre código/snippets; excluye imágenes, vídeos y assets de demostración | VQ-02/04/07, L9/L15/L19: preferir CC0/MIT, verificar versión/backend, `TIME`, profundidad y texturas requeridas. Un port de Shadertoy exige revisar el original; el rótulo «port» no es licencia |
| [OpenGameArt, FAQ](https://opengameart.org/content/faq) | Licencia por recurso, incluidas CC0 y distintas variantes con atribución/otras condiciones; previews pueden tener términos diferentes | Fuente complementaria de props/texturas/UI y audio, priorizando CC0. Guardar la licencia que efectivamente se usa cuando haya varias opciones |
| [itch.io, Free + 3D + cc0](https://itch.io/game-assets/free/tag-3d/tag-cc0) | Existen esos filtros/tags de descubrimiento; precio Free y etiqueta cc0 no son una revisión del archivo descargado | L6/L10/L11 o UI según necesidad: terminar en la página del autor y el texto de licencia del pack, no en la página de resultados |
| [GitHub, licenciar un repositorio](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository) | Ser público permite verlo/forkearlo en la plataforma, pero no concede por sí solo licencia para reutilización general. GitHub ofrece búsqueda por licencia | Buscar implementación y actividad/bugs del candidato, fijar commit/release y revisar dependencias/assets incluidos. Preferencia del proyecto: MIT, Apache-2.0 o BSD para código, sin asumir que la cabecera cubre cada archivo |

No se fijan cifras de tamaño de catálogos ni puntuaciones de calidad: no deciden si un recurso cumple la escena de prueba. Que un modelo sea gratuito, fotogramétrico o low-poly tampoco determina su coste total; medir superficies/draws, triángulos, texturas, overdraw, importación y exportación.

## Fuentes ya presentes y fuentes de audio y animación

Poly Haven, ambientCG, Kenney y KayKit ya están integrados. Se conserva la selección pequeña de materiales y la coherencia de una familia de props, en vez de mezclar estilos por disponibilidad. Quaternius mantiene la comprobación por archivo/paquete de la [revisión anterior](visual-quality-supplement-2026-10-06.md#correcciones-de-licencia-y-alcance); este aporte no lo readmite como CC0 general.

[Freesound, CMU y Mixamo](asset-audio-animation-sources-2026-10-06.md) se verifican por separado. Audio amplía la investigación de presentación/sonido cuando haya una tarea concreta; no reemplaza el sonido de motor sintetizado por RPM. Personas animadas solo se consideran si el playtest pide actividad en pits; L10 puede cerrar con objetos estáticos. «Free for all uses» o uso comercial permitido no equivale a CC0 ni decide automáticamente si se pueden versionar animaciones fuente.

## Orden de búsqueda aplicable

| Necesidad | Orden inicial, ajustable al estilo/coste | Destino |
| --- | --- | --- |
| Modelos y naturaleza | Inventario repo → Poly Haven → Kenney → KayKit → Poly Pizza → itch.io CC0 → OpenGameArt CC0 | L6/L8/L10/L11; para siluetas simples se puede comenzar por Kenney/KayKit |
| Texturas | Inventario repo → ambientCG → Poly Haven → cgbookcase | L9/VQ-02; evitar normal/displacement que no aporten a distancia |
| Plugins/código | Godot nativo y repo → Asset Store → Asset Library → upstream GitHub | Solo el paso con una necesidad sin resolver; no migrar radio/física por encontrar un plugin |
| Shaders/VFX | Shaders del repo → Godot Shaders → Asset Store/Library → upstream | Mismo backend, reloj y presupuesto; preferir adaptar lo existente cuando sea menor cambio |
| UI, iconos y controles | Theme/controles del repo → Kenney → pack KayKit/itch.io/OpenGameArt con licencia adecuada | Plan de menú; respetar idioma, contraste y escala, no introducir un segundo sistema visual |
| Audio | Síntesis/archivos propios → Freesound CC0 → OpenGameArt CC0 → Kenney | Investigación de audio fuera del hito visual; pausa y señales audibles conservadas |
| Animaciones | Determinar si hace falta animar → CMU con revisión de términos / KayKit con licencia por pack → Mixamo solo con redistribución acreditada | Futuro contenido humano de pits; preferir una opción con archivos redistribuibles documentados |

## Cómo cerrar la búsqueda sin bloquear la implementación

1. Definir el recurso, paso, tamaño aparente y presupuesto. Revisar si el repo ya lo resuelve; registrar esa referencia si es suficiente.
2. Dedicar inicialmente 30–60 minutos (estimación de trabajo) a las fuentes más pertinentes; comparar hasta tres candidatos. Reutilizar investigación reciente si los requisitos y la revisión del candidato no cambiaron. No es una búsqueda exhaustiva ni un trámite por cada arreglo o función pequeña.
3. Registrar en la evidencia del paso: necesidad, URL/ID/revisión, formato/licencia, coste de adaptación, y decisión `reutilizar`, `adaptar`, `crear` o `posponer`. Crear es válido si lo externo falla licencia, silueta, rendimiento, precisión o mantenimiento; basta documentar el motivo.
4. Para el elegido, conservar fuente, licencia, hashes y receta. Probar una muestra importada, capturas, pausa/reinicio si anima, y export desde clon limpio según el plan. El archivo visible en el editor no acredita el build.
5. Ampliar a un lote solo tras aprobar la muestra. No usar el tamaño del catálogo como razón para aumentar escenas, dependencias o alcance.

**Cambio en L6a:** la búsqueda de un asset ya adecuado precede al ensayo de generador. Si se encuentra una familia reutilizable que cumple ≤ 1k triángulos/malla, atlas 1K, coherencia visual y distribución, puede sustituir la etapa de generación; se mantienen el bake, provenance, import y pruebas. Si no aparece, sigue vigente el ensayo acotado de ez-tree y la alternativa Kenney. No se crea un plugin de búsqueda ni un gestor de assets nuevo.
