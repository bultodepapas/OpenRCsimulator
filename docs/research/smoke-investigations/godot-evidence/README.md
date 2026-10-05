# Evidencia Godot para humo RC

Experimento sintético ejecutado con el binario fijado del repo: Godot 4.7.2-stable (`ed1daf0bf`), Compatibility/OpenGL 4.5 bajo Xvfb con Mesa 25.2.8 llvmpipe. No es captura de la app ni representa valores de lookdev.

`emission-timing-probe.gd` genera cuatro emisores de quads rojos de 0.35 m, 1,200 partículas y vida de 5 s (tasa nominal 240/s). Capó `Engine.max_fps` a 30; el origen recorre 64 m a 40 m/s durante 1.6 s y luego se captura a los 2 s. Las tres primeras filas comparan `fixed_fps/interpolate` `(30,false)`, `(30,true)` y `(60,true)`, siempre con coordenadas globales; la cuarta usa `(30,false)` y `local_coords=true`.

Observación visual: el humo mundial deja marcas discretas sobre el recorrido; activar interpolación entre estados o subir `fixed_fps` de partículas a 60 no rellena claramente las distancias entre posiciones de emisor presentadas a 30 fps. Con coordenadas locales, las partículas permanecen junto al origen actual. Esto es una observación del PNG en el backend y máquina indicados, no una medida de rendimiento ni una garantía para otras GPU.

Para reproducir desde la raíz del repositorio, ejecutar:

```sh
xvfb-run -a -s '-screen 0 1280x720x24' \
  "$(app/get-godot.sh)" \
  --path docs/research/smoke-investigations/godot-evidence \
  --rendering-driver opengl3 --audio-driver Dummy \
  -- --out=/tmp/smoke-emission-timing.png
```

No requiere copiar o renombrar scripts. Sin `--out`, escribe en `user://smoke-emission-timing.png`. El resultado JSON de stdout identifica motor/backend, frames y delta máximo; guardar ese log junto a nuevas capturas. `Engine.max_fps=30` impone un techo, no una garantía de cadencia exacta. Este ensayo no usa el reloj manual propuesto para el producto y no certifica su encolado fuera de cámara. La captura guardada corresponde a la revalidación del proyecto autocontenido; las nuevas ejecuciones no tienen por qué coincidir por hash porque aquí se usa delta de ejecución.

El proyecto es solo evidencia de investigación; no se importa desde `app/` ni añade una dependencia.

Revalidación: salida 0, 63 frames, 2.0226 s simulados por el delta de ejecución y delta máximo de 0.033386 s. Se inspeccionó el PNG resultante y se conservó su hash en [emission-timing-result.json](emission-timing-result.json). El aviso de V-Sync no soportado corresponde al driver virtual; no hubo error de guardado. Las filas se leen de abajo hacia arriba: `(30,false,global)`, `(30,true,global)`, `(60,true,global)` y `(30,false,local)`.
