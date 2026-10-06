# Auditoría visual inicial

2026-10-05 · Evidencia nueva para el [plan de calidad visual](../../VISUAL-QUALITY-PLAN.md). Capturas del árbol de trabajo concurrente; HEAD de referencia `59cca5613fd235d9c6360eee3531a398851ec075`. No representan un checkout limpio ni una mejora implementada.

Se ejecutaron tres procesos de la app con Godot `4.7.2.stable.official.ed1daf0bf`, Compatibility, Mesa llvmpipe, `LP_NUM_THREADS=1`, 1280 × 720. Las tres capturas terminaron con `error 0`, sin errores de motor/shader/script; sus SHA-256 coinciden con los manifiestos. Hay avisos de VSync no disponible y del CG del inventario, conservados en los logs. No se repitieron las capturas ni se midió rendimiento de GPU real.

La trayectoria es `--scripted` en t = 3 s. Sirve para inspeccionar presentación sin depender del vuelo físico en desarrollo. El constructor principal sigue seleccionando Ugly Stik; estas imágenes **no muestran el Extra 300S** ni demuestran su integración.

| Vista | Qué permite observar | Imagen / evidencia |
| --- | --- | --- |
| Piloto | Avión pequeño en el centro, cielo dominante, horizonte fuera de cuadro | [PNG](pilot.png), [manifiesto](pilot.json), [log](pilot.log) |
| Inspección | Acabado actual del Stik, campo repetitivo, pista plana sin transición | [PNG](inspect.png), [manifiesto](inspect.json), [log](inspect.log) |
| Horizonte este | Ausencia de árboles, colinas y referencias de escala en esta escena | [PNG](horizon.png), [manifiesto](horizon.json), [log](horizon.log) |

Juicios sobre qué mejorar son interpretación visual, no resultados de un playtest. El cuadro de contadores está en [audit.json](audit.json). Los contadores `visible` de los manifiestos y los totales impresos en consola tienen distinto alcance: no mezclarlos. La memoria es la contabilidad reportada por Godot, no una medición externa de VRAM.

Reproducción desde la raíz (cambiar la ruta de salida a un directorio temporal propio):

```bash
mkdir -p /tmp/openrc-visual-audit
LP_NUM_THREADS=1 timeout 55 xvfb-run -a -s '-screen 0 1280x720x24' \
  "$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy \
  -- --capture --scripted --out=/tmp/openrc-visual-audit/pilot.png
```

Para inspección añadir `--inspect`; para horizonte añadir `--look_az=90 --look_el=0`. Los argumentos van después del separador `--`. No ejecutar sobre estos PNG archivados: son la evidencia de esta ronda.
