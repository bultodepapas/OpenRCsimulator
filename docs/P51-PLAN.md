# Cuarto avión: P-51D Mustang 1/4, clase 120 cc

2026-10-06 · Revisión 2 · **P51-00, P51-01, P51-02, P51-02b, P51-03, P51-05 y P51-07 hechos**: el P-51D existe como geometría escalada, modelo visual procedimental, datos físicos experimentales y pruebas de vuelo; se selecciona en Inicio como *experimental*. [Investigación](research/p51-family-research.md) · [Recursos](research/p51-resources.json) · [Derivación física](../research/p51/p51-05/derivation.md) · [Roadmap](../ROADMAP.md) · [Método del Extra](EXTRA-300-PLAN.md).

## 1. Elección

El encargo pedía «un P-51 para un motor de más o menos 120 cc, buscando uno en internet como guía». La [investigación](research/p51-family-research.md) muestra que **no existe ningún ARF comercial de P-51D para 100-150 cc**: los ARF más grandes documentados son el CARF de 2,54 m (50-85 cc) y el Hangar 9 60cc de 2,26 m. La clase 120 cc corresponde al **P-51D a escala 1/4** (2,82 m, 18-27 kg) de planos de Chad Veich y Jerry Bates o del short kit de FokkeRC, volado con DA-120, DLE-120, 3W-110 o Kolm 155.

Decisión: **geometría = P-51D real a escala exacta 1/4**, derivada de las cotas publicadas del avión real, de la tres vistas de dominio público (AN 01-60-3) y de las ordenadas UIUC del perfil NAA 45-100; **instalación = DA-120 con cuatripala 26×12** (elección de aspecto; el fabricante lista tripalas 26×12/27×12); **CG y recorridos** tomados de los manuales CARF, Hangar 9 y Ziroli y escalados. No se copia ningún plano comercial.

Lo que distingue a este avión en el simulador: ala baja con diedro de 5° y perfil laminar con curvatura, tren ancho (visual, fijo abajo), masa 18-24 kg, velocidad de pérdida ~14 m/s, hélice grande de paso bajo con fuerte frenado al reducir gas, y una cola con aleta dorsal.

## 2. Convenciones

Mismas que el Extra: `assets/aircraft/p51d-mustang-120/` es la fuente visual (`source.json` → `build_geometry.py` → `geometry.json` → `compile_geometry.py` → `app/aircraft/p51d_geometry.gd`); `app/data/aircraft/p51d_mustang_120.json` son los datos físicos (`openrc-aircraft v1`), generados por `research/p51/p51-05/derive_physics.py`. Ejes del modelo: +X derecha, +Y arriba, −Z morro; z = 0 en el borde de ataque de raíz (línea central), y = 0 en el eje de la hélice. El marco físico `le` coincide con ese datum (`render/airplane.gd::datum()` devuelve (0, 0)).

Cada valor lleva su tipo de evidencia. Tras la revisión 1 por siluetas, las estaciones del fuselaje, la cabina, la toma, la cola, el cono y el tren son *measured* (siluetas rellenas de la tres vistas AN 01-60-3 calibradas con sus cotas impresas; comprobaciones reservadas dentro del 0,7 %); siguen *estimated* las anchuras de toma y cabina, las fracciones de alerón y flap, los pesos de componentes y la hélice (elemento de pala).

## 3. Pasos

| ID | Paso | Prueba | Estado |
| --- | --- | --- | --- |
| P51-00 | Investigación: kits, planos, motores, geometría real, comportamiento; descargas en `references/p51-mustang/` con hashes | [informe](research/p51-family-research.md), [manifiesto](research/p51-resources.json) | Hecho 2026-10-06 |
| P51-01 | Geometría escalada 1/4 desde las cotas reales; perfil UIUC; cola según Mason | `build_geometry.py --check`, `compile_geometry.py --check` | Hecho 2026-10-06; **revisión 1**: estaciones, cabina, toma, cola, cono y tren **medidos en la tres vistas AN 01-60-3** ([siluetas](research/p51-silhouette-review-v1.md)) |
| P51-02 | Modelo visual procedimental: fuselaje, toma ventral, cabina burbuja, ala con diedro y alerones, flaps fijos, cola con dorsal, tren abajo, cuatripala | `aircraft/verify_p51.gd` (126 checks) en `app/test.sh`; renders `aircraft/inspect_p51.gd` → [revisión](../research/p51/p51-02/review-2026-10-06/), app real [vista cercana](../research/p51/p51-02/app/flight-inspect.png) | Hecho 2026-10-06 (v1: 67 mallas, 39.811 triángulos; pendientes el carenado de raíz, el labio de la toma y la unión de la dorsal) |
| P51-02b | Técnica de las siluetas (Avanti): cámaras ancladas sobre la tres vistas, render transparente, visor y métrica de contornos; metrología aplicada a `source.json` | [informe](research/p51-silhouette-review-v1.md): perfil 22,4 → 7,8 px, IoU 0,68 → 0,87; planta 31,3 → 15,0 px, IoU 0,60 → 0,83 | Hecho 2026-10-06 |
| P51-02c | Foto oblicua del usuario (P-51D real, tren abajo): cámara en perspectiva ajustada, superposición y métrica; boca de la toma corregida a escalón | [informe](research/p51-silhouette-review-v1.md#comparación-con-la-foto-oblicua-del-usuario): ajuste 8,6 px RMS, contorno 8,6 px, IoU 0,80 | Hecho 2026-10-06 |
| P51-03 | Entrada en el catálogo como *experimental*; `render/airplane.gd` construye y da el datum | `tests/test_aircraft_catalog.gd` (de UI-05), `--aircraft=p51d-mustang-120` | Hecho 2026-10-06 |
| P51-04 | Holguras de bisagra a los recorridos volados y a 45° (timón/deriva, elevadores/estabilizador) con el comprobador genérico del Extra | `aircraft/verify_p51_clearance.gd` (12 checks, holgura mínima 2,1 mm) en `app/test.sh` | Hecho 2026-10-06 (con V01) |
| P51-05 | Datos físicos derivados y reproducibles (Helmbold/DATCOM, volumen de cola, teoría de franjas, diedro, elemento de pala) | `derive_physics.py --check`, [derivación](../research/p51/p51-05/derivation.md) | Hecho 2026-10-06 |
| P51-06 | Eje de empuje y par del motor (hoy axial); comparar con los 1,75° del Top Flite | traza | Pendiente |
| P51-07 | Vuelo en el bucle real: trimado, 30 s manos fuera, alabeo contra predicción, looping, pérdida, barrena | `tests/test_p51_handling.gd` (15 checks, 11 s): trimado a 22 m/s con 56 % de gas, 30 s manos fuera, alabeo 99°/s y 118°/s frente a 99/122 previstos, looping en 5,4 s, pérdida a 30° de α, barrena recuperada | Hecho 2026-10-06 |
| P51-08 | Envolvente completa y lectura por un piloto: frenado de hélice, aproximación, tendencia a caer de ala | trazas y revisión | Pendiente |
| P51-09 | Contraste independiente: cotas del AN 01-60JE-2, polar del perfil, medidas de hélice (Mejzlik/Falcon) | documento | Pendiente |
| P51-10 | Acabado y formas: ver [P51-VISUAL-PLAN](P51-VISUAL-PLAN.md) (V01 cola, V02 raíz alar, V03 toma, V04 cabina, V05 escapes, V06 tren, V07 hélice, V08 materiales, V09 esquema, V10 detalles), a partir de la [revisión visual 1](research/p51-visual-review-v1.md) | siluetas sin empeorar + capturas | **V01-V08 y V10 hechos 2026-10-06** ([revisión visual 2](research/p51-visual-review-v2.md): lado 7,7 → 5,9 px, planta IoU 0,907 → 0,914, foto IoU 0,80 → 0,81, `verify_p51` 100 → 248); V09 espera el esquema del propietario |
| P51-11 | Flaps (15°/45°) y retráctiles cuando la simulación los soporte (ROADMAP E/G) | — | Bloqueado por el motor físico |

## 4. Límites conocidos de la v1

- Tren fijo abajo (el arrastre lo incluye); sin flaps; empuje axial; sin descarga de hélice en vuelo (régimen fijo al objetivo).
- Velocidad máxima nivelada ~34 m/s con la cuatripala 26×12 (velocidad de paso 30 m/s): un P-51 real de 1/4 con bipala 28×12 volaría más rápido. Cambiar la hélice es un ajuste de datos.
- El solucionador de trimado devuelve «Jacobiano singular» cuando la velocidad pedida excede la que la hélice puede sostener (gas > 1); conviene un mensaje explícito (nota para la línea de física).
- Cuerdas medidas en la tres vistas: 105,0/48,3 in; vía 142 in (cota impresa). La extensión del borde de ataque de raíz del D y el carenado de salida no están modelados.
