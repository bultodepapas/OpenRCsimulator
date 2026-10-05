# 04 · SVG y rasterización para cruces y atlas

2026-10-05 · Investigación documental; fixture propuesto, sin ejecutar. Aplica a US-V01/V02.

## Pregunta y estado local

¿Qué ruta da cruces y filetes reproducibles con pocas dependencias? El plan mantiene el constructor del avión en Godot y plantea un SVG propio para el atlas rojo, blanco y negro. La aplicación fija Godot 4.7.2; la documentación consultada corresponde a la rama 4.7. El constructor actual crea mallas/materiales nativamente y todavía no importa SVG. [Plan visual](../../UGLY-STIK-VISUAL-PLAN.md) · [atlas y materiales](../ugly-stik-visual-investigations/09-materials-atlas.md) · [constructor actual](../../../app/aircraft/ugly_stik_model.gd).

## Hallazgos

Godot rasteriza SVG al importarlo y usa ThorVG. La documentación advierte que su cobertura de SVG es limitada y exige convertir texto en trazados; señala Inkscape como alternativa para vectores complejos. También expone el ajuste SVG Scale. Para una cruz geométrica de campos planos —sin texto, filtros ni imágenes embebidas— el importador ya disponible es la ruta de menor coste: queda ligada al motor fijado y no añade paquete al repositorio. [Importación de imágenes Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html).

Inkscape tiene interfaz para dibujar y un modo CLI para exportar PNG a dimensiones explícitas, por ejemplo `inkscape atlas.svg --export-type=png --export-filename=/tmp/atlas.png --export-width=1024`. Es la opción editorial más completa y Godot la recomienda cuando SVG es demasiado complejo para ThorVG, pero incorporar su aplicación completa solo para esta lámina añade una dependencia de escritorio; sus binarios están bajo GPL-3.0-or-later. [CLI de Inkscape](https://wiki.inkscape.org/wiki/Using_the_Command_Line) · [licencia del proyecto](https://gitlab.com/inkscape/inkscape/-/blob/master/COPYING).

resvg publica una CLI para rasterizar SVG estáticos y tiene licencia dual MIT/Apache-2.0. Puede servir como exportador de desarrollo si aparece un defecto reproducible en ThorVG; a cambio, habrá que distribuir o compilar un binario por plataforma y fijar su versión. No se selecciona aún una versión exacta. [Repositorio y licencia resvg](https://github.com/linebender/resvg) · [argumentos de CLI](https://github.com/linebender/resvg/blob/main/crates/resvg/src/main.rs).

## Decisión y microprueba

**Adoptar Godot primero:** guardar el SVG fuente simple en el proyecto y dejar que el Godot fijado lo importe con ajustes versionados. Inkscape queda como editor opcional del artista, no como requisito de compilación; resvg se aplaza hasta observar una diferencia de rasterización que afecte cruces o filetes. No se cambia el motor ni se introduce imagen generada.

El fixture mínimo es un SVG opaco de 1.024 × 1.024 px con campos rojo/blanco, una cruz negra de brazos ensanchados y filetes finos; sin texto, filtros, scripts ni referencias externas. Importarlo con `timeout 60 "$(app/get-godot.sh)" --headless --path app --import`, asignarlo a una pieza UV de ala con una isla reflejada y otra superficie bajo bisagra, y capturar neutro y deflexión con Compatibility. Revisar márgenes, halos al reducir, continuidad de la marca y color en captura; comparar Godot con resvg únicamente si el primer render falla. Esta prueba aún no se ejecutó: la documentación no demuestra el aspecto de la cruz ni el comportamiento de las UV del avión.
