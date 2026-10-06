# L5 — campo validado y construcción compartida

2026-10-06 · Godot 4.7.2, Compatibility/OpenGL, Linux y llvmpipe.

Inicio y vuelo construyen el mismo campo desde `res://data/fields/default.json`, mediante `data/field_loader.gd` y `render/field.gd`. Cada escena conserva su cámara, avión, entorno y reloj. El loader se ejecuta antes de crear mundo o sesión; un archivo inválido no se sustituye por otro campo. La ruta interactiva muestra un error con detalles y Salir; las rutas técnicas/headless terminan con código 1.

Se conservan pista de 100 × 12 m, centro N=15/E=0, suelo de 40 km de lado, piloto en el origen y ojos a 1,7 m. Los valores se etiquetan `estimated`, procedentes de la configuración histórica; no son medidas certificadas de un campo ni especificaciones AMA/BMFA. La elevación de la pista de 0,03 m evita z-fighting y pertenece al render. No cambia el contacto físico con el suelo.

## Contrato implementado

`load_from(path = DEFAULT_PATH)` y `validate(raw)` devuelven `{ok, errors, field}`. `errors` es `PackedStringArray`; `field` está vacío ante cualquier error. El resultado normalizado conserva la estructura y convierte las cantidades a `float` en metros NED. No contiene nodos ni vectores Godot.

| Clave | Contenido |
| --- | --- |
| `format`, `id` | `openrc-field v1` y un identificador no vacío |
| `runway` | ID de un rectángulo de tipo `runway`; no duplica su geometría |
| `pilot` | ID; cantidades `north`, `east`, `down`, `eye_height` |
| `surfaces` | Rectángulos con ID, `type`, `center_north`, `center_east`, `length_east_west`, `width_north_south` |
| `objects` | Array vacío en L5; objetos aún no soportados se rechazan explícitamente |

Cada cantidad requiere exactamente `{value, unit, kind, source}`. Unidad `m`, número real finito (un booleano no es un número), procedencia no vacía y uno de los tipos de evidencia del repo: `manual`, `measured`, `borrowed`, `estimated`, `derived`. Tamaños y altura de ojos positivos; coordenadas y extremos representables en float32; un rectángulo que colapsa al convertir al renderer se rechaza. La física sigue usando float64.

No se aceptan campos desconocidos, IDs vacíos o duplicados, referencias de pista incorrectas ni nombres de superficie que Godot tendría que renombrar. Rectángulos del mismo tipo pueden tocarse pero no compartir área. La prioridad es **pista > segado > rough**, independiente del orden de declaración, mediante alturas visuales de 0,03/0,015/0 m. El material segado es provisionalmente el material actual de pista; L9c diseñará las transiciones y franjas. `collides=true` produce un diagnóstico específico de capacidad pendiente hasta L14.

`render/field.gd` crea instancias y recursos propios en cada llamada; no crea cámara, avión, entorno, sesión ni colisiones. La cámara de vuelo recibe la estación del piloto del archivo. Inicio conserva su composición fotográfica fija mediante offsets desde los ojos del piloto; mover la estación desplaza también esa composición. Los defaults de `Spec.RUNWAY` y `Spec.GROUND_SIZE` se conservan como referencia del fixture atmosférico; la construcción del campo de producción ya no los consulta.

No se añaden todavía zona de pits, aparcamiento, línea de seguridad ni flight box: no existen en la escena actual y añadir medidas nuevas impediría acreditar la paridad de este paso. Tampoco se aceptan objetos que todavía no se pueden representar. Es una reserva explícita del formato que deberá ampliarse con su constructor y pruebas en L6/L8.

## Reproducción

```bash
app/test.sh
app/capture.sh
app/export.sh

# Compara dos ejecuciones COMPLETAS con el mismo motor/backend/resolución:
python3 docs/research/visual-quality-implementation/L5/check_parity.py \
  /ruta/baseline/app/captures /ruta/resultado/app/captures > parity.json

# Casos negativos y pantalla de error, sin modificar el JSON fuente:
python3 app/tests/test_field_failures.py
```

El comparador verifica inventario y SHA de PNG, sidecar, matriz y traza antes de comparar. Excluye únicamente los cuatro snapshots antiguos de pausa/hint que usan tiempo de pared; los casos deterministas Inicio → Volar sí deben ser idénticos. Los umbrales de atmósfera/legibilidad y los goldens físicos permanecen intactos.

El export prueba el archivo y el loader compilado dentro de los tres paquetes desde un proyecto vacío, sin posibilidad de resolver el JSON desde el árbol fuente. Conserva además el vuelo real del ejecutable Linux y las comprobaciones de versión/estructura/firma existentes. No acredita ejecución nativa de Windows/macOS ni rendimiento en la RTX 3090.

## Evidencia

[validation.json](validation.json) identifica las ejecuciones y sus límites; [changed-files.json](changed-files.json) registra los SHA antes/después. Baseline verificado contra el commit `a039980c453ba6a93151ec57b4746887e4bfdc31`; clon privado de validación `790ed4eb7c0b5cb57a8dc12b323d57ea1bd52b9d`, sin crear commits en la rama compartida.

- Suite completa del juego: exit 0; **158 comprobaciones del loader y 38 de integración**, además de ocho combinaciones de archivo inválido/ruta y dos rutas interactivas. Los casos negativos no mutan archivos fuente.
- [Paridad](parity.json): **112 capturas válidas por ejecución; 108 casos deterministas byte-idénticos**, cuatro snapshots antiguos de pausa/hint excluidos por tiempo de pared. Filas de datos de la traza idénticas; los headers de build/ruta pueden diferir. Nueve pares de repetición válidos en cada ejecución.
- Tres exports: mismo SHA del JSON, validado por el loader compilado desde un proyecto vacío. El smoke negativo rechaza un SHA incorrecto. Vuelo real Linux, estructura/firma universal macOS y versiones de Windows/macOS correctos; [log](logs/export.log) y [checksums](export-SHA256SUMS).
- Linter: cero errores, las mismas diez advertencias previas. El warning de `AudioStreamGeneratorPlayback` al cerrar una traza ya aparece en el [baseline](logs/baseline-trace.log); no se presenta este paso como una corrección del sistema de audio.

Logs: [suite](logs/test.log), [capturas](logs/capture.log), [baseline](logs/baseline-capture.log). Imágenes revisadas: [Inicio](home-es.png), [campo cenital](field-top.png), [piloto](pilot.png) y [error en español](field-error-es.png). Los manifiestos completos antes/después se conservan junto a este informe; PNG/logs completos quedan en `app/captures/l5-validation/{before,after}/` (ignorados por Git, regenerables). Los renders y pruebas de esta máquina usan software; no son un benchmark del equipo del propietario. Siguiente paso del plan: **L6a**, silueta del arbolado y su lectura en vuelo.

Después de validar el snapshot, el trabajo concurrente del P-51 modificó geometría/source. Esos archivos se conservaron íntegros: no forman parte de L5 ni de sus capturas. Los 24 archivos de código/datos instalados coinciden con el clon verificado y las [pruebas L5 en el árbol compartido](logs/shared-focused.log) también pasan. `validation.json` registra los SHA del trabajo concurrente observado; la suite completa y los exports acreditan el snapshot indicado arriba, no revisiones posteriores del modelo.
