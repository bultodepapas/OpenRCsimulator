# Segundo avión: Extra 300S .60

2026-10-06 · Revisión 5 · **EX-00–03, EX-05, EX-07 (en el aire) y EX-11 hechos: el Extra se elige en Inicio y vuela con datos físicos propios, etiquetado experimental ([estado](#volable-en-el-menú-experimental--2026-10-06)).** [Informe EX-01/EX-02](research/extra-300-model-v1.md).

Elegimos el **Great Planes Extra 300S .60, kit GPMA0236, 64 in / 1,6256 m**, con instalación inicial de clase O.S. MAX-61FX. Es un acrobático RC de construcción balsa/contrachapado, con carenado, cabina monoplaza y tren de cola. Será el siguiente paso después del Ugly Stik: otro avión reconocible y un comportamiento propio, construido mediante entregas pequeñas.

[Investigación de la familia](research/extra-300-family-research.md) · [Recursos descargados y lectura de planos](research/extra-300-resources.md) · [Auditoría del código actual](research/extra-300-integration-audit.md) · [Roadmap](../ROADMAP.md) · [Método del Ugly Stik](UGLY-STIK-PLAN.md).

La [segunda ronda](research/extra-300-round2.md) identifica el contexto de la foto roja/blanca con estrellas, añade una vista inferior y documentación de la variante .40, y recupera una construcción .60 con masa publicada. La selección dimensional sigue siendo el GPMA0236 .60; la foto del propietario guía el acabado.

La [ronda de doce investigaciones Godot y herramientas](research/extra-aircraft-tooling/README.md) concreta opciones para CAD, geometría, articulación, materiales, cabina, hélice, inspección y carga. Incluye mejoras reutilizables en el Ugly Stik, fuentes primarias y ensayos de aceptación pendientes. No añade dependencias ni marca pasos de implementación como completados.

## 1. Elección de variante

El **300L** tiene la evidencia más clara de difusión histórica entre los aviones reales considerados: Extra documenta 326 unidades entre 1993 y 2015 y lo describe como una plataforma importante para entrenamiento y competición. Esto no establece un ranking de ventas de modelos RC. [Historia del fabricante](https://extraaircraft.com/milestones/1993/).

Para este simulador elegimos el **300S .60 de Great Planes** por la documentación recuperable y la cercanía a la instalación nitro existente. Encontramos manual original, vistas constructivas, secciones y fotos superiores/inferiores. El EXP de Extreme Flight es una alternativa RC eléctrica documentada, pero el propio fabricante explica que modifica libremente al avión real; sería otra configuración y otro trabajo de propulsión. [Manual oficial EXP](https://extremeflightrc.com/cdn/shop/files/EF-60extra-V2_manual_b58079bb-afb0-434a-a4da-930f2d508ced.pdf?v=13810129977580418015).

La elección es de ingeniería y contenido jugable; **no afirmamos que GPMA0236 sea el Extra RC más vendido**. No mezclaremos la cabina del 300L, la planta del 330SC y los mandos del EXP bajo un nombre genérico. La identidad interna propuesta es `gp_extra_300s_60`; la revisión del modelo, su instalación y el estado de validación van separados del ID.

## 2. Primera experiencia que queremos entregar

Desde la cámara de piloto se distingue del Stik por ala baja trapezoidal, fuselaje carenado, cabina y deriva. Se selecciona, aparece ya en vuelo trimado, responde a los mismos mandos y permite volver al Stik. Reiniciar, desconectar la radio, grabar una traza o fallar la carga de datos conserva las reglas actuales.

La primera entrega visual se ve en un inspector o vuelo `scripted`, etiquetada como **vista previa**. Solo será seleccionable para vuelo físico cuando tenga datos propios y pase trim, controles y regresiones. Un modelo bonito moviéndose en el círculo no prueba su comportamiento aerodinámico.

La primera entrega volable cubre vuelo nivelado, viraje, tonel, looping, invertido y pérdida básica dentro de una envolvente experimental documentada. Hover, harrier, torque roll, cuchillo sostenido y fidelidad de snap/spin quedan fuera de la aceptación inicial: requieren validación y capacidades adicionales del modelo físico. Tampoco se exige aterrizar para mostrar el segundo avión; el contacto actual todavía significa accidente.

## 3. Qué aprendimos del Ugly Stik

| Aprendizaje comprobado | Aplicación al Extra |
| --- | --- |
| Una vista oblicua ocultaba una raíz alar separada | Planta, perfil y frente desde el primer bloque; medir asiento ala/fuselaje |
| Los detalles del mismo plano pueden tener escalas diferentes | Calibración por vista; mantener puntos fuente y una medida reservada fuera del ajuste |
| Origen visual y CG son distintos | Conservar transformación explícita; probar que el punto CG del modelo coincide con la posición simulada |
| Una bisagra mal orientada se nota demasiado tarde en vuelo | Probar signos y eje real sobre geometría construida antes de decorar |
| Distancia positiva entre pieles no excluye contención | Holguras y contención en neutro, extremos y mandos combinados |
| El inspector arrastraba la pose anterior | Cada captura restablece todos los mandos y registra pose, cámara, luz y revisión |
| Hashes idénticos de capturas no prueban legibilidad humana | Ensayo de orientación con respuestas del piloto y evaluación en hardware real |
| Un motor genérico y una foto de otro modelo no fijan una instalación | Elegir motor/escape/hélice, etiquetar cada dimensión y limitar detalle oculto |
| Coeficientes prestados que triman no validan un avión | Separar verificación numérica de contraste independiente y sensibilidad |

Las evidencias originales están en [LEARNINGS](../LEARNINGS.md), [metrología v3](research/ugly-stik-model-v3-metrology.md), [ala v3](research/ugly-stik-model-v3-wing.md), [instalación](research/ugly-stik-model-v3-installation.md) y [herramientas investigadas](research/ugly-stik-tooling-investigations/README.md).

## 4. Fuente geométrica y datos que faltan

La ficha de recursos conserva los valores nominales y sus conversiones. Los PDF son referencias: el plano ampliado y el DXF proceden de una extracción/reconstrucción del manual, con partes redibujadas. **No se ha calibrado su escala ni auditado geométricamente el CAD.** La página de dos vistas del manual sirve para silueta y decoración; no es un plano de taller calibrado. [Procedencia de los archivos](https://outerzone.co.uk/plan_details.asp?ID=10977).

En EX-01 se fija un datum estable ligado al borde de ataque de una estación alar identificada. La referencia del CG en el plano menciona la costilla 2D; hay que situarla antes de transferir la distancia al marco físico. El ala en flecha impide tratar todos sus bordes de ataque como el mismo origen.

Medir primero contornos alares, cuerdas raíz/punta, posición de bisagras, contornos de cola, estaciones de fuselaje, cabina, bancada y contactos. Conservar hash, página, coordenadas PDF/píxel, escala, datum, incertidumbre y criterio de tolerancia previo al ajuste. Reservar al menos una sección de fuselaje y una cota alar como controles independientes.

Envergadura, superficie y `S/b` no son tres mediciones independientes. En un ala trapezoidal **`S/b` no sustituye la cuerda aerodinámica media**. Hay que calcular y declarar la cuerda usada para normalizar momentos y tasas; transformar coeficientes si una fuente usa otra referencia.

El loader v1 exige actualmente `span × mean_chord ≈ area` con tolerancia de 1 %. Para el primer Extra se conserva `mean_chord = S/b` como **longitud de referencia de normalización**, convirtiendo las derivadas a esa convención. La MAC y su borde de ataque se documentan aparte para interpretar el CG. Usar MAC en ese campo sin cambiar el contrato provocaría rechazo o incoherencia. Una futura separación de cuerdas en el esquema será otro cambio explícito, con compatibilidad del Stik.

La segunda ronda encontró una masa publicada de una construcción identificada, recogida en su informe como caso de contraste; siguen faltando inventario de componentes, inercias, perfil aerodinámico identificado, polares, derivadas, CL máximo/mínimo y ensayos cuantitativos de vuelo comparables. No asignar un NACA por parecido visual. Las masas nominales del cartucho son un rango de construcción, no una pesada del avión que simulamos.

## 5. Modelado Godot

Mantener **Godot 4.7.2, Compatibility y construcción nativa**, siguiendo el flujo JSON → generador → malla que funciona en el Stik. No incorporar dependencias nuevas para comenzar. SurfaceTool permite controlar normales/UV por vértice; su orden de caras y costuras se prueban en una pieza pequeña antes de extender el acabado. [API oficial 4.7](https://docs.godotengine.org/en/4.7/classes/class_surfacetool.html).

Rutas propuestas, todavía inexistentes: `assets/aircraft/extra-300s-60/geometry.json`, `appearance.json` y compiladores; `app/aircraft/extra_300s_geometry.gd`, `extra_300s_model.gd` y módulos de acabado/mandos únicamente cuando hagan falta. El JSON contiene datos y evidencia; no es una copia renombrada del esquema rectangular del Stik.

Orden de construcción:

1. **Volumen sencillo:** fuselaje por estaciones, ala trapezoidal, cola, cabina opaca, spinner y tren. Silueta primero.
2. **Superficies móviles:** alerones sobre su línea de bisagra oblicua, elevador y timón; marcos de reposo separados de la deflexión. Verificar un lado antes de reflejarlo.
3. **Carenado y cabina:** perfiles suaves sin perder aristas características; abertura de refrigeración y salida del escape donde se vean. Interior muy sencillo. Ensayar transparencia de la cabina contra ala, hélice y cielo; mantener una cabina opaca convincente si la transparencia introduce defectos. [Materiales Godot](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html).
4. **Tren convencional:** patas principales y rueda de cola; carenas coherentes con la variante. No reutilizar la rueda delantera del Stik cambiándole el nombre.
5. **Acabado propio desde la foto aportada:** rojo predominante, paneles blancos longitudinales con estrellas rojas, franja lateral blanca con filetes oscuros, cabina transparente/oscura y carenas rojas. La vista inferior localizada aporta bandas azules/blancas como candidata para contrastar orientación. [Brief y límites](research/extra-300-photo-investigation.md). Sustituye la propuesta cromática inicial sin referencia del propietario; se adapta a la geometría .60 mediante atlas propio, sin incorporar fotos ni logos ajenos al juego. Evaluar su distinción respecto al Stik rojo mediante silueta y patrón, no solo color base.
6. **Detalle condicionado al uso:** varillajes visibles, uniones y equipo que aporten lectura. El motor queda mayormente bajo el carenado; no dedicarle otra ronda de microdetalle antes de volar.

No fijar ahora un presupuesto arbitrario de polígonos ni copiar el del Stik como objetivo. Registrar mallas, triángulos, materiales y coste; optimizar lo que mida el hardware objetivo. Blender/GLB queda como alternativa para una pieza orgánica concreta si el generador se vuelve difícil de mantener, mediante un ensayo de escala, ejes y articulación. No migrar ambos aviones para estrenar el segundo.

## 6. Integración mínima de dos aviones

La [auditoría](research/extra-300-integration-audit.md) identifica los puntos concretos. La costura necesaria es una **definición de avión que resuelva conjuntamente constructor, geometría de referencia y archivo físico**. Un registro explícito de dos entradas basta; no hace falta un sistema de plugins, herencia de familias, descarga de contenido ni editor de aviones.

Mantener el resultado `build()` con `root`, `propeller` y `hinges`, los nodos `airplane`, `propeller` y `*_hinge`, y las claves `aileron_left`, `aileron_right`, `elevator`, `rudder`. Ejes visuales: metros, +X derecha, +Y arriba, −Z morro. La simulación conserva float64 y marcos NED/FRD; solo el render usa Vector3/Basis.

**Dos cambios pequeños de contrato serán necesarios:**

- La orden de superficie representa una deflexión escalar. Cada constructor proporciona su eje/marco local o una función de aplicación; asignar Euler X/Y como hoy no sirve para todos los alerones en flecha. El caso Stik conserva exactamente sus signos y poses.
- El tren aporta ruedas opcionales identificadas y su dirección. `left/right/nose` deja de ser un supuesto obligatorio; el Extra aporta `tail`. Esto prepara E1/E2, sin añadir fuerzas de suelo en la entrega visual.

El registro entrega también los anclajes para transformar el CG y los metadatos de inspección. Extensión, cámara y sombra deben corresponder al avión activo. La sombra actual mide el tamaño construido, pero su dibujo y centro alar son fijos; necesita una silueta original del Extra o un contorno generado una vez desde sus datos.

Crear/cambiar avión entre sesiones, con simulación detenida, validación previa y sustitución completa de modelo/datos; no ofrecer cambio en pleno vuelo. Un ID desconocido no puede terminar mostrando un Extra con la física del Stik. Conservar el Stik como predeterminado para comandos, pruebas y capturas existentes.

Coordinar con **UI-05 de [MENU-PLAN](MENU-PLAN.md)**: usar un solo catálogo e ID estable. Si el menú aún no existe, la integración técnica puede usar un argumento propuesto `--aircraft=gp_extra_300s_60`; no construir un menú paralelo. La ficha de avión distingue vista previa, vuelo experimental y validación pendiente.

## 7. Física propia y límites de la primera entrega

Crear datos `openrc-aircraft v1` con `{value, unit, kind, source}`; los tipos admitidos actualmente son `manual`, `measured`, `borrowed`, `estimated`, `derived`. Una cifra desconocida no se rellena como «manual». Conservar inventario de componentes, CG de vuelo y discrepancia del inventario como asuntos separados.

**Mandos:** los desplazamientos del manual deben convertirse usando el brazo perpendicular real a la bisagra en el punto donde se midieron. Si el desplazamiento representa altura respecto a neutro, usar `δ = asin(d/r)`; si la referencia representa otra distancia, reconstruir esa geometría. Registrar convenio y error. No introducir pulgadas como grados ni dividir por toda la cuerda alar. Empezar con recorridos bajos; los altos son otra configuración comprobada. Mantener entrada de radio sin expo duplicado.

**Propulsión:** la instalación .61 mantiene pequeño el alcance, pero escape, hélice, montaje y curva de empuje tienen procedencia propia. El plano muestra inclinaciones lateral y vertical: el módulo actual aplica empuje únicamente sobre +X del cuerpo. Introducir dirección de eje, fuerza, reacción de par y momento giroscópico coherentes en un paso aislado, con el valor por defecto axial para el Stik. Un desplazamiento del punto de empuje no equivale a inclinarlo. Si se aplaza, declarar la instalación axial como aproximación y no afirmar concordancia con el plano.

**Ala y estabilidad:** las estaciones actuales de pérdida usan una aproximación de ala equivalente que se debe revisar frente a esta planta trapezoidal. Se puede conservar una primera aproximación global etiquetada; la pérdida de punta y el snap no quedan validados por eso. El loader exige signos propios de un avión estáticamente estable: empezar con un CG conservador y no eliminar validaciones para permitir números de una variante 3D radical.

También protege una región lineal de ±8° para ambos lados de la pérdida. Si evidencia del Extra contradice ese límite, revisar el contrato y sus pruebas en una tarea específica; no inflar CL máximo/mínimo para hacer pasar el archivo.

**Coeficientes:** no copiar todas las derivadas Ultra Stick y multiplicar la eficacia de los mandos hasta que parezca acrobático. Construir una estimación trazable, consistente en referencias/signos, contrastar sensibilidad a CG/inercia/amortiguación y buscar una fuente independiente del mismo kit/configuración. Un cálculo desde nuestros coeficientes verifica el código; no valida el avión.

**Vuelo inicial:** resolver el trim de seis ejes a una velocidad justificada por la nueva carga alar, sin imponer los 15 m/s actuales. Las trazas registran ID, ruta y revisión reales, inicio y velocidad. Un fallo de trim bloquea ese inicio y explica la causa; no se oculta cambiando el avión físico.

**Acrobacia avanzada:** E0a/E0b y Gate F del roadmap siguen gobernando cola separada y propwash. El plan Extra no abre un segundo solver ni promete hover con el actual. Para tren de cola, E1/E2 deberán aceptar topología y geometría específicas: estabilidad direccional en suelo, apoyo de cola, vuelco y frenado requieren sus propias pruebas.

## 8. Entregas pequeñas y prueba de cada una

Los IDs EX son tareas del segundo avión vinculadas al roadmap; no sustituyen sus hitos. **EX-00, EX-01, EX-02 y EX-04 están hechos** (✅ en la tabla), además del adelanto EX-10a; el resto sigue propuesto.

| ID / relación | Entrega | Dependencia | Prueba de cierre |
| --- | --- | --- | --- |
| EX-00 · preparación D1 | Elegir variante, reunir fuentes y auditar integración | Ninguna | Manual/planos/fotos abiertos, manifiesto con hashes, originales excluidos de Git, documentos enlazados |
| EX-01 · D1 ✅ | Ficha geométrica inicial y datum | EX-00 | Puntos/escala por vista, incógnitas declaradas y cotas reservadas; una sesión acotada, no esperar metrología perfecta. **2026-10-06:** regla de 36 in (399,88 px/in), siete controles reservados en verde (envergadura −0,13 %, área +0,10 %, longitud +0,67 %, CG 4,116 frente a 4⅛ in), `measure.py --check` reproduce `metrology.json` |
| EX-02 · D1 visual ✅ | Extra sencillo en inspector independiente | EX-01 | Capturas frente/perfil/planta/oblicua y escala nominal; root/propeller/hinges presentes; Stik sigue funcionando. **2026-10-06:** `verify_extra.gd` (84 comprobaciones en `app/test.sh`, seis mutaciones detectadas), 8 capturas repetibles byte a byte, `verify_model.gd` del Stik sigue en 807/0 |
| EX-03 · D1 / UI-05 ✅ | Registro de modelos y selección de vista previa | EX-02 | Dos IDs resuelven sus propios recursos; ID inválido y Extra aún no volable tratados explícitamente; capturas Stik conservadas |
| EX-04 · B5/D1 ✅ | Articulación con ejes de bisagra propios | EX-02/03 | Neutro/extremos/combinaciones, signos, contención, continuidad; defecto deliberado en copia detectado. **2026-10-06:** `extra_clearance.gd`, holgura mínima 1,75 mm a los recorridos del manual (0,83 sin bisel), bisagras biseladas libres a 45°, timón limitado a 43,0° por el corte del elevador del plano; tres mutaciones detectadas |
| EX-05 · D1/D2 ✅ | Datos físicos iniciales e inventario | EX-01 | Loader acepta datos con procedencia; masa/inercia válidas; CG, cuerda de referencia y hull cotejados con geometría |
| EX-06 · D5/D9c | Instalación y eje de motor | EX-05 | Fuerza/par transformados y signos probados; caso axial Stik sin cambios; limitaciones de hélice/escape documentadas |
| EX-07 · D3/D4 ✅ (en el aire) | Primer vuelo físico del Extra | EX-04–06 | Trim, 30 s sin mando, reinicio, hull, radio/armado/failsafe; trazas con identidad correcta y vuelos repetibles |
| EX-08 · D8a/D9/D10 | Envolvente inicial verificada | EX-07 | Nivelado, viraje, tonel, looping, invertido, pérdida; estados finitos y timestep; goldens propios sin regrabar los del Stik |
| EX-09 · D8b/Gate 2 | Contraste independiente y playtest | EX-08 | Observación del kit/configuración o fuente externa identificada; discrepancias y sensibilidad; si falta, conservar etiqueta experimental |
| EX-10 · D7/Gate 2 | Acabado y orientación desde tierra | EX-04; puede avanzar en paralelo a física | Mismo conjunto de cámaras/luz; 20/50/100 m, seis actitudes, cielo/suelo; respuestas humanas separadas de hashes |
| EX-11 · UI-05 / M1 ✅ | Selector de avión volable y ciclo de sesión | EX-07, coordinado con menú | Elegir Extra y volver a Stik, restart/reload/pausa; sin nodos/sesiones duplicados; traza y HUD muestran avión correcto |
| EX-12 · exportación / Gate 2 | Entrega instalable de los dos aviones | EX-08/10/11 | Suite completa, import/export desde clon limpio sin references ni caché; smoke por avión y medición en hardware objetivo |
| EX-13 · E0–E2 / Gate F | Ampliar acrobacia y tren convencional | EX-09 + capacidades del roadmap | Ensayos específicos de cola/propwash y suelo; no es bloqueo del primer vuelo en el aire |

EX-03 integra primero la selección técnica de la vista previa; EX-11 cierra el flujo de producto con datos volables. Si UI-05 ya entrega ese flujo, EX-11 solo añade contenido y pruebas. EX-08 puede empezar con maniobras conservadoras; cada una debe declarar velocidad, CG, rates y tolerancias **antes** de ajustar el modelo.

Por cambio integrado: regeneradores `--check`, comprobación específica del contrato y `app/test.sh`. Borradores fuera de `app/` hasta que parseen; mutaciones en copias. Exportar desde limpio al introducir rutas/recursos. Registrar prueba en el commit y aprendizaje en LEARNINGS. No regrabar vuelos golden del Stik para esconder una regresión de la extracción compartida.

## 9. Criterios de aceptación separados

**Visible y reconocible:** silueta Extra, piezas conectadas, escala coherente, ruedas/cabina/carenado, bisagras y poses. Capturas preparadas no equivalen a aceptación del piloto.

**Volable y verificable:** modelo físico propio con incertidumbres, trim válido, mandos y fallos seguros, maniobras repetibles, goldens por avión y ninguna regresión del Stik. El hull incluye spinner, puntas, cola y contactos correctos; no hereda el triciclo.

**Fiel a la referencia:** medidas reservadas, transformación conocida, inventario y observaciones externas. Cuando falte evidencia, declarar el parámetro y el comportamiento afectados; no usar un número total de tests como certificado de realismo.

**Entregable:** ambos aviones funcionan en export sin los recursos locales de inspiración; selección coherente, presupuesto físico del roadmap y coste gráfico medidos en el equipo del propietario. Las pruebas numéricas no sustituyen su valoración del tacto del avión.

## 10. Estado al cerrar esta investigación

Se revisaron código, planes y research del Stik; se investigó la familia Extra y se conservaron 34 descargas locales con procedencia y hashes, más la foto del propietario. La primera ronda reunió 13 archivos y la segunda añadió 21. Se inspeccionaron cabeceras/entidades de los dos CAD, sin calibración geométrica. Hay planos, manuales, fotos y una galería local. No se implementó código de vuelo/modelado, no se modificó la elección global del roadmap y no se ejecutó `app/test.sh` por estas entregas documentales.

La siguiente acción concreta es **EX-01 → EX-02: fijar datum y unas pocas cotas fiables, y ver un Extra sencillo en Godot**. Su metrología completa, decoración final y física avanzada evolucionan después de comprobar esa primera forma.

**Actualización 2026-10-06:** EX-01 y EX-02 hechos ([informe](research/extra-300-model-v1.md)). La hoja de fuselaje está a escala reducida (300,56 px/in) y se calibra con la cuerda de raíz; el dibujo p.47 resultó un croquis con errores de hasta 1,2 in y no se usa para cotas. El alerón en flecha se resolvió con un marco fijo sobre la bisagra, sin cambiar `apply_surfaces()`. Siguen estimados: vía del tren, carenas, hélice y redondeo de las cuadernas. Siguiente: EX-03 (registro de dos aviones) o EX-04 (holguras de articulación).

**Revisión visual 2026-10-06** ([informe](research/extra-300-visual-review-v1.md)): 79 vistas automáticas más 6 a escala, superposición del plano y métricas. La forma coincide con el plano; el defecto más relevante es que extradós e intradós no se distinguen desde tierra (H1, adelantar el intradós de EX-10). Propuesto EX-02b: suavizado del fuselaje, cabina y tren. **Hecho el mismo día:** EX-02b (fuselaje suave por interpolación monótona, cabina corregida, tren en gota y pletina desde el plano) y **EX-10a**, el adelanto de EX-10 centrado en la orientación: decoración procedural roja/blanca con estrellas e intradós azul/blanco. Desde tierra el intradós da un 23–31 % de azul y el extradós un 0 % a 20–100 m. EX-10 conserva la prueba humana de orientación y el acabado final.

## 10. Herramientas investigadas y orden de adopción

Las [doce investigaciones](research/extra-aircraft-tooling/README.md) amplían la preparación EX-00. Aplicarlas mediante los pasos existentes:

- **EX-01/02:** evaluar ezdxf para curvas y unidades del CAD; conservar el constructor nativo como primera vía. Shapely/trimesh y Blender solo si resuelven un problema concreto de contorno, topología o autoría. Un modelo GLB necesitaría demostrar escala y pivotes tras importar.
- **EX-03/04:** materiales compartidos inmutables y estado separado por avión; ejes de bisagra en marcos locales. Interpolación únicamente visual sobre estados de simulación; no sustituir el integrador por nodos físicos. El visor de datum/CG precede a un plugin de editor completo.
- **EX-10:** comparar cabina, filtrado/LOD y representación de hélice en Compatibility. Dar al Extra una máscara de sombra y datum propios; la extensión calculada desde mallas no corrige la máscara Stik fija. Capturas y lecturas humanas tienen propósitos diferentes.
- **EX-11/12:** medir carga/construcción antes de introducir hilos; sustitución de sesión completa y exportación comprobada por cada ID. La carga asíncrona de un recurso no acelera automáticamente un constructor procedural.
- **EX-05/09:** XFOIL/AVL son candidatos de contraste offline tras fijar geometría, ejes y referencias de coeficientes. Sus resultados se etiquetan por procedencia y no acreditan pérdida dinámica ni acrobacia avanzada.

Las mejoras comunes se prueban primero con el Stik y luego con ambos modelos. Ninguna herramienta opcional bloquea ver el Extra inicial en el inspector.

## Volable en el menú (experimental) — 2026-10-06

**EX-03, EX-05, EX-07 (en el aire) y EX-11 hechos.** El Extra se elige en Inicio (flechas junto a «Próximo vuelo»), vuela con sus propios datos y vuelve al Stik sin mezclar modelo y física. La ficha lo marca **experimental**.

- **Datos (EX-05):** [`gp_extra_300s_60.json`](../app/data/aircraft/gp_extra_300s_60.json) lo **genera** [`derive_physics.py`](../research/extra-300/ex05/derive_physics.py) desde la geometría medida y el manual; el [informe de derivación](../research/extra-300/ex05/derivation.md) lista cada magnitud intermedia. Helmbold/DATCOM para pendientes, volumen de cola para estabilidad y amortiguamiento, teoría de franjas para alerones y Clp, acumulación de fricción para CD0. Masa de vuelo 3,364 kg (seco 7,10 lb, dentro de las 7–7,5 lb del manual), CG en el punto del manual (30,0 % CMA), margen estático 12,5 % CMA, pérdida 1 g a 10,3 m/s, inicio trimado a 17 m/s, CD0 0,031. Recorridos: los altos del manual p43 (alerón 17,6°, elevador 23,9°, timón 30,0°) como máximo mecánico; la radio reduce con su dual rate. Un cambio en las claves de geometría que lee obliga a regenerar (CI ejecuta `--check`).
- **Cargador:** `reference.planform = "tapered"` con `root_chord`/`tip_chord`; las franjas de igual área se colocan en sus centroides (el Stik rectangular queda idéntico). `start.level_speed` opcional (el Stik conserva 15 m/s).
- **Vuelo (EX-07, primera parte de EX-08):** [`test_extra_handling.gd`](../app/tests/test_extra_handling.gd): 30 s sin mandos, alabeo coordinado 213°/s a 17 m/s y 266°/s a 22 m/s (±7 % de la predicción), looping con 0,3 de palanca, pérdida al tirar a fondo con el elevador alto (como avisa el manual), pérdida sin motor y recuperación de barrena. `--aircraft=gp-extra-300s-60` en la ruta directa; la traza nombra el avión y la velocidad.
- **Límites:** empuje axial (2° derecha y 0,5° abajo del plano pendientes en EX-06); misma hélice y datos que el Stik (APC 12x6); Cnβ del fuselaje omitido por contrato v1; derivadas cruzadas fijadas al CL de inicio; sin propwash ni combustible variable. Es verificación numérica, no validación: EX-08 completo (invertido, viraje, tonel) y EX-09 siguen abiertos.
