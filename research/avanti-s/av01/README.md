# AV-01: preparación dimensional y archivo visual

Variante: **SebArt Avanti S A200 original, 2000 × 2220 mm**, P100-RX sin BL, catálogo 2017. Trabajo previo al constructor; no configura la física de `app/`.

- `measurements.json`: cotas nominales, mandos, cocientes derivados y pendientes. Cada dato declara unidad, evidencia y fuente. Ninguna cota de fuselaje se obtiene escalando una perspectiva.
- `organize.py`: conserva originales, añade copias descriptivas, extrae páginas/recortes del PDF con sus anotaciones y genera una galería local.
- `selection.json`: nombres de fotos y selección de pasos del montaje. Las posiciones del recorte se registran en el manifiesto generado; la página completa permite revisar contexto.
- `study-board.html`: plantilla de un panel SVG interactivo de dimensiones y recorridos. Esquemático; no representa perfil, área alar ni dinámica aerodinámica.

Desde la raíz:

```sh
python3 research/avanti-s/av01/organize.py --check-data
python3 research/avanti-s/av01/organize.py
```

La segunda orden requiere los originales locales listados en `docs/research/avanti-s-resources.json`, Poppler (`pdftoppm`, `pdfinfo`, `pdftotext`) y Pillow para comprobar dimensiones de archivo. No descarga ni instala dependencias. La primera funciona sin `references/` y usa solo la biblioteca estándar de Python.

Salida: `references/avanti-s/organized/index.html`, `study-board.html`, `catalog.json` y carpetas por componente. Los originales no se renombran: sus rutas y hashes siguen siendo válidos. Los recortes documentales se rasterizan directamente desde regiones del PDF, sin reconstrucción generativa, rectificación de perspectiva ni retoque. Las etiquetas y cotas vectoriales del PDF se conservan; extraer solo sus imágenes incrustadas las perdería.

Los archivos de referencia y sus derivados permanecen ignorados por Git. El catálogo y la validación guardados en `docs/research/` describen la procedencia; no contienen imágenes ni texto íntegro de terceros. La ausencia de referencias en un clon limpio es esperada y no afecta al simulador.
