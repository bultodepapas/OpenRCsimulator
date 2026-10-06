# L6c · kit de lectura de actitud a 100 m

24 imágenes de la vista del juego (autozoom, Ugly Stik a 100 m del piloto, seis actitudes × cielo, borde de
copas, árboles y hierba) en un orden fijo que no depende del caso. Las respuestas correctas están solo en
`key/answer-key.json`: no abrirlo hasta terminar.

1. Abrir `index.html` en un navegador a zoom 100 %. Mirar cada imagen como en vuelo y elegir la actitud
   (botones o teclas 1–6). Se puede volver atrás.
2. En el juego, volar una pasada baja delante de los árboles (al norte) y un viraje frente a ellos; puntuar
   de 1 a 5 y anotar lo que confunda (filas `flight-pass` y `flight-turn`).
3. Descargar `responses.csv` y puntuar:

```bash
"$(app/tests/visual-env.sh)" app/tests/treeline_readability.py score responses.csv --kit <esta carpeta>
```

Objetivo inicial del plan (§8): ≥ 22/24 correctas por perfil; umbral de diseño, no validación
estadística. Un fallo señala qué fondo y qué actitud se confunden, para reducir densidad o contraste de la
arboleda o abrir huecos antes de añadir detalle.

| Respuesta | Significado |
| --- | --- |
| `level` | Horizontal, derecho |
| `inverted` | Horizontal, invertido |
| `knife_left` | Cuchillo, panza hacia la izquierda |
| `knife_right` | Cuchillo, panza hacia la derecha |
| `climb` | Morro arriba 45° |
| `dive` | Morro abajo 45° |

`responses-template.csv` tiene el mismo formato que la descarga (`image,answer,notes`), por si se rellena a mano.
