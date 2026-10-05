# Ugly Stik .61 — entrega visual v4

2026-10-05 · `jensen-61-classic-red-v4` · Geometría base Jensen v3 conservada. [Plan y estado US-V01–08](../UGLY-STIK-VISUAL-PLAN.md).

La implementación integra el acabado rojo con cruces, motor de culata dorada, mofle con nervaduras, servos, transmisiones y herrajes en el constructor nativo de Godot. [Galería offline](../../research/ugly-stik/model-v4/review.html) · [Vista general](../../research/ugly-stik/model-v4/beauty/beauty-a-dark.png) · [Motor y mofle](../../research/ugly-stik/model-v4/details/engine-right.png) · [Servos](../../research/ugly-stik/model-v4/details/maintenance-servos.png).

## Apariencia y procedencia

Las [fotos A–F del propietario](ugly-stik-visual-photo-brief.md) fijan la dirección visual. A/B aportan centro alar rojo, campos blancos exteriores, puntas rojas, filetes negros, cruces de brazos ensanchados, cola vertical blanca y marca dorsal. C aporta horquillas, varillas y apoyos de latón. D/F aportan culata dorada ranurada y silenciador separado; E aclara su montaje. Los dos archivos locales del motor quedan indexados con SHA-256, dentro de `references/` ignorado.

Las fotos no fijan cotas, marca exacta del motor instalado ni esquema completo del intradós. La cara inferior continúa como propuesta simétrica. El cuerpo del avión conserva las cotas, bisagras y contactos de v3; el festoneado añade una profundidad estimada de 2,8 mm y paso de 50,8 mm sin cambiar envergadura ni cuerda nominal. No se incorpora film transparente: las líneas de costilla son un indicio gráfico tenue sobre piel opaca.

La apariencia vive en [appearance.json](../../assets/aircraft/ugly-stik-60/appearance.json), separada de `geometry.json`. El compilador produce SVG original y GDScript con el mismo SVG embebido. Godot rasteriza el atlas 1024² una vez y genera mipmaps; las mallas usan UV explícitas y un material sin tinte de color adicional. Se emplean perfiles distintos para recubrimiento, aluminio, acero, caucho, plástico y madera; se comparten recursos inmutables por perfil y color.

La comparación importada/runtime dio igualdad completa de píxeles. Se eligió `ImageTexture` sin compresión VRAM para evitar una dependencia de caché del editor y de archivos fuente en exportación. La prueba de importación vive en un proyecto temporal mínimo. No se añade Blender, GLB, addon ni dependencia al ejecutable.

## Mecánica e integración

[Equipo y estimaciones](ugly-stik-model-v4-equipment.md) documenta cárter, nueve aletas, culata ranurada, carburador inclinado, cuello ancho del mofle, brida, nervaduras, cono posterior, boquilla hueca y racor de presión. Bancadas y racores alcanzan el cortafuegos. Las líneas visibles distinguen combustible y presión; el tanque interior no está modelado. La hélice conserva eje y diámetro; sección, torsión y acabado de madera clara son decisiones visuales.

[Mandos e instalación](ugly-stik-model-v4-controls.md) describe cinco servos genéricos: dos alares con reenvíos, elevador, timón y gas. Se modelan soportes, gomas, ojales, brazos, cableado corto, cuernos de latón, horquillas con doble oreja/pasador y guías. Las seis varillas articuladas conservan longitud mediante cierre geométrico continuo. Gas queda estático: la interfaz de bisagras no proporciona esa señal.

`build()` mantiene `root`, `propeller`, `hinges` y `gear`, y añade `controls`. `apply_surfaces()` actualiza el mecanismo después de las bisagras; no crea nodos en cada actualización. `set_maintenance()` expone el equipo interno; el inspector oculta solo la piel seleccionada y restaura visibilidad por captura. Ninguna vista desplaza componentes para exhibirlos. Las mallas fijas se agrupan por material y los conjuntos articulados conservan sus pivotes.

Esta entrega modifica únicamente el frente del modelo y su adaptador. No ajusta masas, aerodinámica, motores físicos, cámaras de juego ni escena principal del otro desarrollador.

## Evidencia reproducible

[Validación estructurada](../../research/ugly-stik/model-v4/validation.json) conserva resultados, hashes y límites. Comandos desde la raíz:

```bash
python3 assets/aircraft/ugly-stik-60/compile_geometry.py --check
python3 assets/aircraft/ugly-stik-60/compile_appearance.py --check
$(app/get-godot.sh) --headless --path app --script res://aircraft/verify_model.gd
$(app/get-godot.sh) --headless --path app --script res://aircraft/verify_controls.gd
python3 research/ugly-stik/model-v4/check_atlas.py --log /tmp/atlas-check.log
python3 research/ugly-stik/model-v4/check_mutations.py
research/ugly-stik/model-v4/capture.sh --output-dir /tmp/ugly-stik-v4-new
```

El último comando requiere `xvfb-run` y Pillow **11.3.0**, fijado en `requirements.txt`. Rechaza destinos existentes y protege v1/v2/v3. Las 97 piezas de evidencia histórica inventariadas permanecieron sin cambios.

| Comprobación | Resultado |
| --- | --- |
| Suite completa de la aplicación | **`app/test.sh` pasa**; vuelo trimado y estado final idéntico a 30/60/144 fps |
| Contrato integrado del modelo | **807 comprobaciones, 0 fallos** |
| Controles bajo jerarquía trasladada/rotada | **289 comprobaciones, 0 fallos**; 21 poses por superficie, continuidad y cero nodos nuevos |
| Seis varillas con órdenes de vuelo reales | **71 poses**; extremo construido a unión ≤0,000000089 m; error de longitud ≤0,000000119 m |
| Atlas | Generador vigente, importación/runtime idénticos en 1024², mipmaps y UV comprobados |
| Mutaciones en copias temporales | SVG desactualizado, caras invertidas y varillas estiradas rechazados |
| Galería | **95 PNG**: 9 inspección, 36 orientación, 12 detalles, 36 movimiento y 2 presentación |
| Repetición independiente | **36/36 PNG idénticos** por SHA-256 |
| Clon limpio de snapshot temporal | Contratos pasan; dos vistas de presentación idénticas a las integradas; sin caché Godot ni originales de referencia |

El barrido mide las mallas construidas, además del resultado del solver. Su tolerancia de 0,25 mm es de implementación; los errores numéricos pequeños no son una afirmación de precisión de construcción. Las pruebas de holgura de las superficies v3 siguen pasando. No hay una prueba exhaustiva de colisión entre cada accesorio: los apoyos, guías, extremos y contactos intencionales se revisan en las vistas y poses guardadas.

Las muestras de movimiento son poses deterministas, no un vídeo a tiempo real. La galería identifica el intervalo nominal y usa 700 ms por diapositiva para inspección. El [formulario de orientación v4](../../research/ugly-stik/model-v4/readability36/review.html) permite responder antes de revelar la clave; su JSON incluye revisión visual y hash del manifiesto. Hay **cero respuestas humanas** registradas.

### Suite global y trabajo paralelo

La última ejecución de **`app/test.sh` pasa** en el árbol integrado: guardia float64, parseo de scripts, pruebas unitarias, entrada extremo a extremo, contrato del modelo, vuelo trimado y estado final idéntico a 30/60/144 fps. [Log final](../../research/ugly-stik/model-v4/validation-logs/integrated-tests-final.log).

Los logs anteriores se conservan para distinguir desarrollo paralelo de regresión visual. Durante una ejecución el árbol compartido encontró `station_y` ausente en `test_envelope.gd`; un clon sobre `4645213d72c835eaaca594635b91e5d41e6a73f3` falló en la equivalencia aerodinámica lineal (`oracle`, 500 estados). Este último fallo se reprodujo también al extraer el commit base **sin cambios visuales**. El otro frente continuó su trabajo y la ejecución final integrada pasó; esta entrega no modificó su física. El clon confirmó por separado los contratos visuales y las dos capturas idénticas.

## Coste y aceptación restante

| Vista / estado | Mallas visibles | Triángulos visibles | Materiales |
| --- | ---: | ---: | ---: |
| Referencia v3 montada | 54 | 4.816 | 5 |
| V4 montada | 74 | 27.040 | 23 |
| V4 mantenimiento, piel seleccionada oculta | 86 | 29.324 | 27 |

La inspección tres cuartos registra 314 draw calls del fotograma completo; el primer plano de servos registra 171. Las cámaras y objetos visibles difieren, así que no son presupuestos intercambiables del modelo. Las tres muestras de pared de tres cuartos fueron 51,054 / 45,634 / 73,201 ms. Se capturó con Godot 4.7.2, Compatibility/OpenGL, 1280 × 720, `msaa_3d=2`, Mesa llvmpipe LLVM 20.1.2. Son diagnósticos en renderizado por software, con otras validaciones activas en el host; **no constituyen un benchmark GPU**. Los manifiestos conservan luces, cámara, contadores y hashes por fuente.

El incremento geométrico se concentra en siluetas, motor y montaje. Quedan pendientes el ensayo del piloto, perfilado CPU/GPU en el equipo objetivo y decisiones de simplificación basadas en esa medición. No se declara fidelidad comercial exacta, aceptación humana ni rendimiento objetivo por generar capturas. Mini/gigante, interior completo, transparencia, efectos de hélice y simulación mecánica continúan como trabajo posterior.

## Revalidación del árbol integrado

2026-10-05 · Base `dbe0cb2`, árbol compartido con trabajo paralelo ajeno al modelo. Al retomar la solicitud de aplicar el plan se comprobó que la implementación v4 ya estaba integrada en el constructor usado por el simulador. Esta pasada no modifica geometría, acabado ni código de ejecución: corrige estados documentales obsoletos y registra comprobaciones nuevas.

[Evidencia y hashes de las fuentes](ugly-stik-revalidation-2026-10-05/validation.json):

- `compile_geometry.py --check` y `compile_appearance.py --check`: fuentes y salidas coincidentes.
- [`app/test.sh`](ugly-stik-revalidation-2026-10-05/app-tests.log): pasa, incluido el contrato del modelo **807/0**, vuelo trimado y estado físico idéntico a 30/60/144 FPS. El log conserva un aviso de fuga ObjectDB del ensayo de radio; no hubo errores de motor ni comprobaciones fallidas.
- [`verify_controls.gd`](ugly-stik-revalidation-2026-10-05/controls.log): **289/0**, error máximo de cierre y longitud 0,000000060 m.
- [Atlas en proyecto temporal limpio](ugly-stik-revalidation-2026-10-05/atlas.log): importación y rasterización runtime idénticas; la mutación de SVG desactualizado se rechaza.
- [Capturas nuevas de presentación](ugly-stik-revalidation-2026-10-05/beauty.log): `beauty-a-dark.png` y `beauty-b-sky.png` coinciden por SHA-256 con ambas imágenes de la entrega. Se revisó visualmente la vista general y el perfil; los PNG repetidos quedaron temporales para evitar duplicar evidencia idéntica. No se repitió toda la galería de 95 imágenes.

La auditoría del plan y del constructor no encontró una mejora de código pendiente dentro del alcance visual solicitado. Se corrigieron la frase que aún declaraba todos los pasos pendientes, las descripciones antiguas de caché/destino y la identificación del plan v5 como archivo histórico. Continúan pendientes las respuestas humanas de orientación y las medidas de rendimiento en la GPU del propietario.
