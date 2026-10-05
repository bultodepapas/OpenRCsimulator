# Avanti S Jet 2.2 m · investigación del JetCat P100-RX

2026-10-05 · Investigación de fuentes primarias para simulación; sin cambios de aplicación ni recursos binarios añadidos al repositorio.

## Decisión de referencia

La pareja más trazable para un segundo avión de turbina es el **SebArt Avanti S Jet 2.2m ARF**, con el motor **JetCat P100-RX según el catálogo JetCat 2017, sin sufijo BL**. El manual de SebArt documenta 200 cm de envergadura, 222 cm de longitud y 10,5 kg de peso RTF en seco con P100. El fabricante presenta esa instalación como opción de entrenamiento acrobático; reserva P140/P160 para FAI F3S y P180 o superior para 3D ilimitado. El mismo manual atribuye el fuselaje a compuesto y alas/estabilizadores a estructura de madera. [Manual oficial Avanti S Jet 2.2m](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf)

La familia tiene variantes cercanas cuyo nombre no debe servir para mezclar medidas. La página actual de SebArt para el **Avanti S FC Jet by KRILL** indica 210 cm de envergadura, 222 cm de largo y 11 kg RTF seco con P100 RX; también lista P140RX y P180RX para otras clases de uso. Esa es otra configuración y geometría. [Ficha oficial Avanti S FC](https://www.sebart.it/jets-L-Krill.html)

No encontré cifras públicas primarias de ventas o unidades que permitan afirmar cuál variante es “la más popular”. El 2.2m es la selección de ingeniería: el manual del fabricante ofrece cotas, CG y una instalación P100 inequívocos. No se afirma que sea el más vendido. El manual revisado es un folleto de montaje y referencia, no un plano de taller calibrado.

El manual recomienda CG a 250 mm detrás del borde de ataque del ala medido en el fuselaje; distingue 240 mm para la configuración de “jet beginner” y 260 mm para 3D ilimitado. Para esta referencia de simulación se puede tomar 240 mm como punto inicial de investigación, ligado a ese datum, y mantenerlo como valor de manual hasta fijar geometría, combustible y masa final. No convertir esta cifra en una coordenada de CG del cuerpo sin documentar el marco y el datum.

## Identidad de la turbina y revisiones

Los documentos oficiales muestran que “P100-RX” no es una fotografía única e inmutable. Por eso el plan debe elegir y nombrar una revisión antes de incorporar cifras al JSON. Para el primer modelo propongo congelar el **P100-RX de la tabla del catálogo JetCat 2017**: aparece sin “BL” y trae la serie completa de cifras operativas y la nota de masa. El manual técnico JetCat de 2011 es comparación histórica, no una tabla para completar huecos del catálogo.

| Fuente y variante explícita | Ralentí / máximo | Empuje ralentí / máximo | Combustible ralentí / máximo | Masa, diámetro, largo con arrancador | Lectura para el simulador |
| --- | --- | --- | --- | --- | --- |
| JetCat, manual RX cuya portada dice “Stand August 2011”, tabla final P100-RX | 40.000 / 154.000 rpm | 2 / 100 N | 80 / 390 ml/min | 1.080 g; 97 mm; 235 mm | Revisión anterior. El cuadro no aclara qué accesorios incluye la masa. [Manual RX 2011, PDF oficial](https://www.jetcat.de/jetcat/Bedienungsanleitung/Strahlturbinen_DE_JetCat_RX_%20120218.pdf) |
| JetCat, catálogo 2017, tabla P100-RX (sin BL) | 44.000 / 154.000 rpm | 2 / 100 N | 80 / 390 ml/min; 0,064 / 0,312 kg/min | 1.080 g con nota “incluye válvulas”; 97 mm; 241 mm | Baseline recomendado. El catálogo da condiciones STP ±3% (15 °C, 1013 mbar). [Catálogo oficial 2017](https://www.jetcat.de/jetcat/Kataloge/JetCat%20Lieferprogramm%202017_web.pdf) |
| JetCat, producto actual P100-RX-BL, con bomba brushless | 44.000 / 154.000 rpm | 2 / 100 N | 80 / 390 ml/min | 1.080 g; 97 mm; 241 mm | Solo contraste actual; ECU/configuración y revisión difieren. [Ficha oficial P100-RX-BL](https://www.jetcat.de/en/productdetails/produkte/jetcat/produkte/RC%20ENGINES/Engines/p100_rx-bl) |

La advertencia sobre la masa merece precisión: **1.080 g también aparece en el manual 2011 y en la tabla 2017 de P100-RX sin BL**, además de en el producto actual BL. La cifra no identifica por sí sola la variante. La tabla 2017 aclara que ese valor incluye válvulas; la tabla de 2011 no especifica la inclusión con el mismo detalle. Conservar revisión, alcance y procedencia junto a la cifra. No usar masa del motor como si fuera masa del conjunto instalado: depósito, combustible, bomba, ECU, batería, soportes y accesorios requieren inventario separado.

El P100-RX-BL actual publica además una relación de presión 2,9, flujo másico 0,23 kg/s, velocidad de escape 1.565 km/h y potencia de chorro 21,7 kW. El catálogo 2017 muestra esos mismos valores para la entrada P100-RX, pero no deben atribuirse al ejemplar de 2011 sin indicarlo. Tampoco extrapolar entre revisiones por coincidencia de varias cifras.

## Planos y recursos oficiales localizados

La página JetCat actual del P100-RX-BL enlaza dos PDFs cuyos nombres omiten “BL”. Sus direcciones directas son:

- [JetCat P100 RX.PDF](https://www.jetcat.de/jetcat/produkte/hobby/p100_rx/JetCat%20P100%20RX.PDF): tres páginas con vistas de ingeniería del motor. El PDF no contiene una tabla textual de prestaciones; su metadata identifica una exportación de SOLIDWORKS de enero de 2017.
- [JetCat P100 RX Size.PDF](https://www.jetcat.de/jetcat/produkte/hobby/p100_rx/JetCat%20P100%20RX%20Size.PDF): plano acotado de una página, con largo total de 241 mm y diámetro de 97 mm, entre otras cotas. Su metadata indica enero de 2017.
- [Manual SebArt Avanti S Jet 2.2m](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf): fuente de proporciones publicadas, construcción, CG y mandos; no es un plano completo a escala.
- [Catálogo JetCat 2017](https://www.jetcat.de/jetcat/Kataloge/JetCat%20Lieferprogramm%202017_web.pdf): fuente de la especificación P100-RX sin sufijo BL usada como baseline.

Los dos dibujos P100 RX se sirven desde la ficha vigente RX-BL. Aunque sus metadatos son de 2017, su asociación al producto actual no demuestra por sí sola que todas las dimensiones sean de la revisión RX anterior. Usar el plano de 241 mm junto a la referencia 2017; para la revisión RX de 2011, la tabla oficial documenta 235 mm. Los PDFs quedan como enlaces de procedencia para que el equipo pueda guardarlos fuera del control de versiones si decide usarlos como inspiración visual.

## Implicaciones para la física

El P100 es un **turborreactor**. El módulo actual [propulsion.gd](../../app/physics/propulsion.gd) calcula RPM con retardo de primer orden y empuje/par mediante `Ct(J)` y `Cp(J)` de hélice; ese modelo no representa un P100. No aplicar coeficientes de hélice, reacción de par de hélice, descarga de RPM por hélice, propwash de cola ni momento giroscópico de la hélice. Tampoco calcular un momento giroscópico del rotor interno de la turbina solo a partir de RPM: falta el momento de inercia del conjunto rotatorio.

La forma general del empuje de chorro es el cambio de flujo de cantidad de movimiento más el término de presión de salida. NASA Glenn da para una turbina con presión de salida aproximadamente igual a la del ambiente la forma simplificada `F ≈ ṁ_eng (V_e − V_0)`. [Ecuación de empuje de NASA Glenn](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/). Con los valores máximos publicados por JetCat (`0,23 kg/s` y `1.565 km/h = 434,7 m/s`), el caso estático da aproximadamente 100 N; es un chequeo de coherencia de unidades, no una curva adicional ni una medición de vuelo.

El empuje nominal máximo se conserva como un punto de referencia del fabricante. No equivale a un mapa de empuje con velocidad, altitud, instalación de admisión ni tubo de escape. La fórmula de NASA explica por qué la velocidad libre afecta el empuje, pero JetCat no publica en las fuentes consultadas una tabla P100 de vuelo que permita parametrizar ese efecto completo. No reducir empuje según una curva inventada.

La ECU RX documenta una respuesta “Normal” como valor estándar, ajustes de respuesta de ralentí y plena potencia, y describe que la respuesta de la turbina es lenta. No da segundos de aceleración ni una curva RPM/tiempo utilizable. Por tanto, `rpm_max` no determina `spool_tau`: las constantes temporales, las curvas entre ralentí y máximo y el decaimiento al apagar deben permanecer **estimated**, con intervalos de sensibilidad hasta conseguir una traza de la revisión seleccionada. [Manual JetCat RX, secciones de respuesta y datos técnicos](https://www.jetcat.de/jetcat/Bedienungsanleitung/Strahlturbinen_DE_JetCat_RX_%20120218.pdf)

## Modelo escalonado propuesto

1. **Congelar configuración y procedencia.** Identidad de avión `SebArt Avanti S Jet 2.2m ARF`; propulsor `JetCat P100-RX, referencia de catálogo 2017, no BL`. Guardar cada valor con `{value, unit, kind, source}`. Mantener el P100-RX de 2011 y el P100-RX-BL actual como referencias comparativas separadas.
2. **Vuelo jugable con motor encendido al ralentí.** Iniciar el escenario aéreo trimado con estado `RUNNING_IDLE`, RPM de ralentí de la revisión elegida y 2 N de empuje. En este paso no hace falta simular arranque, enfriamiento o telemetría de la ECU.
3. **Estado de spool y empuje sin hélice.** Añadir estados explícitos `RUNNING_IDLE`, `SPOOLING`, `RUNNING`, `SPOOLING_DOWN`, `FLAMEOUT` y `OFF`. El acelerador fija una demanda; un estado dinámico aproxima el retraso hasta ella. Solo los extremos de empuje/consumo son datos del fabricante. Toda interpolación intermedia y todo `tau` son aproximaciones marcadas como `estimated`, no curvas JetCat.
4. **Eje de empuje y momentos.** Aplicar la fuerza a lo largo del eje de la turbina y el momento `r × F` respecto al CG, usando el offset y la orientación de instalación medidos en planos/modelo. El empuje centrado no debe introducir un momento. No inventar la posición o inclinación del eje para forzar el trim.
5. **Combustible y CG.** Reducir combustible usando el flujo correspondiente al estado del motor, limitado por los puntos documentados de ralentí y máximo. La interpolación de flujo entre esos puntos también es `estimated`. Representar combustible, depósitos y accesorios como componentes de masa con ubicación explícita; recalcular masa total, CG e inercias al consumir. El folleto SebArt menciona un depósito opcional de queroseno/UAT/humo, pero no fija en el documento una capacidad y coordenadas suficientes para calcular su variación de CG. Ese inventario sigue pendiente.
6. **Parada y agotamiento.** Diferenciar mando de ralentí de una orden de parada y de agotamiento/fallo. Una turbina en marcha tiene empuje residual; una orden de parada o falta de combustible debe pasar por `SPOOLING_DOWN`/`FLAMEOUT` y hacer decaer el empuje con una constante temporal estimada. No garantizar empuje cero en el mismo tick que se corta combustible. `OFF` solo se alcanza tras decelerar o por un evento destructivo de la simulación.
7. **Contraste gradual.** Verificar con trazas el empuje de ralentí y máximo, continuidad temporal, monotonicidad de combustible consumido y respuesta a cortes. Registrar claramente si se contrasta contra tabla estática, traza de spool o comportamiento de vuelo; pasar los casos iniciales no convierte las constantes estimadas en datos medidos.

## Datos confirmados y pendientes

| Dato | Estado |
| --- | --- |
| Avanti S Jet 2.2m: 200 cm, 222 cm, 10,5 kg RTF seco con P100 | Confirmado en manual SebArt |
| P100-RX baseline 2017 sin BL: 44k/154k rpm, 2/100 N, 80/390 ml/min, 1.080 g, 97/241 mm | Confirmado en catálogo JetCat 2017; masa con válvulas según nota |
| P100-RX manual 2011: 40k/154k rpm y largo 235 mm | Confirmado como revisión anterior; no fusionar con la tabla 2017 |
| Curva de aceleración/deceleración, tau de spool y fuerza a throttle intermedio | Sin dato primario cuantitativo; `estimated` hasta traza |
| Mapa de empuje con velocidad de vuelo/altitud e instalación | Sin mapa del P100 en fuentes consultadas |
| Capacidad, ubicación del tanque, inventario completo, CG con combustible | Pendiente de plano/configuración identificada |
| Inercia del rotor interno y efecto transitorio de montaje | Sin dato; no añadir momento implícito |
| Ranking de ventas/popularidad por variante Avanti S | Sin dato público verificable; no afirmar liderazgo de ventas |
