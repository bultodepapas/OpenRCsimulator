# Investigación: campo de viento y física de ráfagas para OpenRC

**Fecha:** 2026-10-05. **Alcance:** fundamentos físicos y parámetros configurables para integrar viento en el simulador Godot. Las fuentes consultadas son documentación oficial, normas, código de JSBSim y reportes técnicos de NASA. Esto es una base de diseño; no acredita que ningún ajuste reproduzca todavía el vuelo de un avión RC real.

## Resultado principal

Conviene representar el viento como una **velocidad del aire en el marco NED** que cambia con la posición y el tiempo, y dejar que el modelo aerodinámico calcule qué flujo ve el avión. Una velocidad media constante da una primera función útil y comprobable. Las ráfagas de forma `1 − cos` sirven como eventos reproducibles de entrada; la turbulencia continua es otro fenómeno y requiere ruido filtrado con intensidad y escalas configurables. Una señal aleatoria distinta en cada tick no es un modelo Dryden ni una aproximación temporalmente estable.

Las magnitudes de MIL-F-8785 y FAR Part 25 se formularon para cualidades de vuelo o cargas de aviones de tamaño completo. Se pueden reutilizar sus **formas espectrales y de onda** como referencias de ingeniería, pero sus niveles, escalas y envolventes no deben copiarse como si fueran datos medidos de un avión RC.

## Lo que ya existe en este proyecto

- La hoja de ruta coloca “viento, luego ráfagas” dentro de M5, después de la prueba de vuelo v0.1. La regla de avanzar de poco a mucho y validar cada paso encaja con esta secuencia. [ROADMAP §M5](../../ROADMAP.md)
- [`Air.compute`](../../app/physics/air_data.gd) ya rota la velocidad NED del aire a ejes del cuerpo y calcula velocidad relativa, ángulo de ataque, resbalamiento y presión dinámica. Las pruebas cubren viento frontal, cruzado y velocidad relativa cero. [test_air_data.gd](../../app/tests/test_air_data.gd)
- La sesión sigue pasando viento cero a la función de cargas en [`FlightSession._loads`](../../app/sim/flight_session.gd). Así que existe la operación vectorial, pero falta conectarla a un campo meteorológico común para aerodinámica, propulsión y telemetría.
- La investigación visual previa cubre manga, vegetación, reloj de simulación y uniformes de shader. Es útil para que el paisaje comunique el **mismo viento simulado**; no demuestra una respuesta aerodinámica ni parámetros físicos de viento. [11 · Windsock, tree sway, flags and ambient life](landscape-investigations/11-wind-animation-ambience.md)
- La auditoría de integración complementaria identifica las decisiones de Godot, precisión, reloj RK4, traza, HUD y uso de `Area3D`. [Auditoría viento/Godot](wind-godot-integration.md)

## Convenciones y efecto sobre el avión

El servicio físico debería producir un vector `wind_ned_mps = [north, east, down]`: la velocidad **hacia donde se mueve el aire**, en m/s. Los informes meteorológicos describen dirección **de donde viene** el viento, en grados verdaderos desde el norte en sentido horario. La FAA y el National Weather Service siguen esa convención. [NWS: Wind Direction](https://forecast.weather.gov/glossary.php?word=WIND+DIRECTION) · [FAA JO 7900.5E, cap. 7](https://www.faa.gov/media/70751)

**Precaución al consultar JSBSim:** la documentación de `SetWindPsi` dice “from”, pero `SetWindspeed()` construye `N=speed*cos(psiw), E=speed*sin(psiw)`, que representa transporte hacia ese azimut. No copiar esa conversión sin resolver qué convención consume cada API. Usar NOAA/FAA para nuestra convención meteorológica y probar 000°/090°/180°/270°. [Documentación y código de los setters](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGWinds.html).

Para velocidad horizontal $V$ y dirección meteorológica $\theta_{from}$, expresada desde el norte verdadero:

\[
\theta_{to}=(\theta_{from}+180^\circ)\bmod 360^\circ,\qquad
W_N=V\cos\theta_{to}=-V\cos\theta_{from},\qquad
W_E=V\sin\theta_{to}=-V\sin\theta_{from}.
\]

En NED, la componente vertical positiva apunta **hacia abajo**, por tanto $W_D=-W_{up}$. Ejemplo: viento **desde norte** a 5 m/s produce [-5, 0, 0] m/s; viento desde este produce [0, -5, 0]. Si $V=0$, la dirección no define un vector y se conserva solo como preferencia de interfaz.

Sea $v_{g,b}$ la velocidad del avión respecto al suelo expresada en cuerpo y $R_{n\to b}$ la rotación NED→cuerpo. La velocidad que entra a la aerodinámica es:

\[
v_{air,b}=v_{g,b}-R_{n\to b}W_{NED},\qquad
V_{air}=\lVert v_{air,b}\rVert,\qquad
\bar q=\tfrac12\rho V_{air}^{2}.
\]

El código actual ya aplica esta resta. Su efecto debe propagarse por el mismo `AirData`: viento frontal cambia la velocidad de flujo y la presión dinámica; viento cruzado cambia β y cargas laterales; el viento también cambia el flujo axial que recibe la hélice, pues la propulsión consume `air.v_air`. No se debe sumar otra vez el viento a la posición del avión: la integración de posición sigue usando velocidad respecto al suelo. En un campo uniforme, el viento altera la velocidad **relativa al aire** que determina las cargas; no es una fuerza de empuje independiente.

El inicio en vuelo merece una decisión explícita: si se quiere conservar el trim al activar viento, inicializar con una velocidad relativa al aire de trim y derivar la velocidad respecto al suelo sumándole el viento en el marco correspondiente. Si se enciende el viento sobre el estado de calma existente, el cambio brusco de $v_{air}$ es un evento físico de entrada y habrá transitorio. Ambas opciones son útiles, pero significan escenarios distintos.

## Viento medio, dirección cambiante y capa superficial

### Viento uniforme configurable

La primera versión puede recibir magnitud y dirección desde la interfaz o desde un preset y convertirlos una sola vez al vector NED. Guardar internamente m/s, grados verdaderos y sentido del vector elimina conversiones implícitas en la física. Para trazas y capturas repetibles, la configuración debe formar parte del escenario junto con una fuente y tipo de evidencia para cada valor, siguiendo la regla del repositorio.

### Cambio lento del viento

El viento de fondo puede ser constante por tramo o seguir puntos clave de tiempo y dirección. Si se necesita inercia sin hacer un perfil por segmentos, una relajación de primer orden es sencilla:

\[
\dot V=(V_{target}-V)/\tau_V,\qquad
\dot\theta=\operatorname{wrap}(\theta_{target}-\theta)/\tau_\theta.
\]

(V) se mide en m/s, θ en radianes y las constantes τ en segundos. Para no girar por el camino largo a través de 0°/360°, se envuelve la diferencia angular al intervalo de menor magnitud. Una alternativa aún más clara para repetir ejercicios es una curva temporal con puntos clave de velocidad y dirección. Los valores de τ o la duración de esas curvas son controles del escenario, **no constantes universales de meteorología**; hasta tener datos de campo deben declararse `estimated`.

Separar “cambio lento de la media” de “ráfaga” permite ajustar y probar cada uno por separado. La definición de observación de FAA de una ráfaga —fluctuación rápida con diferencia de al menos 10 kt entre picos y valles en el período de observación de 10 min— es un criterio de reporte, no una receta de frecuencia, forma o amplitud para el simulador. [FAA JO 7900.5E, §7.2](https://www.faa.gov/media/70751)

### Viento que varía con la altura AGL

En la capa superficial neutra, una aproximación documentada es el perfil logarítmico:

\[
\bar V(z)=\frac{u_*}{\kappa}\ln\left(\frac{z-d}{z_0}\right),\qquad
\bar V(z)=\bar V(z_r)\frac{\ln((z-d)/z_0)}{\ln((z_r-d)/z_0)}.
\]

Aquí (z) es altura AGL en m, (z_0) longitud de rugosidad superficial en m, (d) desplazamiento de plano cero en m, (u_*) velocidad de fricción en m/s y κ la constante de von Kármán adimensional; la segunda forma escala el viento dado a una altura de referencia (z_r). NASA documenta que la estructura superficial depende de rugosidad, fricción, desplazamiento, estabilidad y altura; para atmósfera neutra usa un perfil logarítmico, con correcciones para estratificación estable o inestable, y advierte que la ley logarítmica deja de valer en condiciones muy estables. [NASA-CR-2288, *A model of wind shear and turbulence in the surface boundary layer*](https://ntrs.nasa.gov/citations/19730018294)

El perfil solo tiene sentido dentro de su dominio de capa superficial y con (z-d>z_0); no extrapolarlo hasta (z=0), donde daría una singularidad o un valor sin significado. Sin rugosidad, estabilidad ni datos locales, mantener viento uniforme es una decisión más honesta que asignar por defecto una ley de potencia y llamarla realista. Cuando se añada el perfil, altura **AGL**, referencia y rugosidad deben ser configurables y su validez quedar indicada. La variación de viento con altura es cizalladura; el “ground effect” aerodinámico de la aeronave es otra física, aunque ambas se noten cerca del suelo.

## Ráfagas discretas reproducibles

14 CFR §25.341 define un pulso espacial `1 − cos` para investigar cargas dinámicas de aviones de categoría transporte:

\[
U(s)=\frac{U_{ds}}{2}\left[1-\cos\left(\frac{\pi s}{H}\right)\right],\quad 0\le s\le 2H.
\]

(U_{ds}) es la velocidad pico y (H) la distancia de gradiente paralela a la trayectoria; la ráfaga alcanza (U_{ds}) en (s=H), y vuelve a cero en (2H). Para una aproximación temporal a velocidad de avance aproximadamente constante (V_a), usar (s\approx V_a t), con (T_{peak}=H/V_a) y duración completa (2H/V_a). No usar los (H=30\text{–}350\) ft ni las amplitudes de diseño de la norma como límites o presets RC: esa sección busca cargas certificables en categoría transporte. [GovInfo, 14 CFR §25.341](https://www.govinfo.gov/content/pkg/CFR-2022-title14-vol1/pdf/CFR-2022-title14-vol1-sec25-341.pdf) · [FAA AC 25.341-1: Dynamic Gust Loads](https://www.faa.gov/documentLibrary/media/Advisory_Circular/AC_25_341-1.pdf)

Para el entorno de simulación es práctico parametrizar una ráfaga como (G(t)=A f(t)\hat d), donde (A) es amplitud en m/s, \hat d una dirección NED unitaria y (f\in[0,1]) el perfil. Es importante dejar elegir si el usuario proporciona longitud de gradiente (H) —el modo espacial anterior— o tiempos —rise, hold y fade—; no hay que mezclar metros con segundos ni suponer que el pico se alcanza en el mismo tiempo a cualquier velocidad si el control elegido es espacial.

JSBSim expone una variante en tiempo: subida con \((1-\cos(\pi t/T_r))/2\), meseta (T_h) opcional y caída cosenoidal durante (T_f), además de magnitud y marco de dirección. Su implementación mantiene fijo el vector transformado al activar el evento y suma el viento medio, la ráfaga y la turbulencia como componentes del viento total. Es un ejemplo muy útil de interfaz de parámetros y fuente abierta para contrastar la implementación. [JSBSim `FGWinds` docs](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGWinds.html) · [JSBSim `CosineGustProfile` source](https://jsbsim-team.github.io/jsbsim/FGWinds_8cpp_source.html)

Para un primer evento elegir un inicio (t_0), vector/amplitud, perfil y si se repite o es manual. Una única ráfaga determinista es fácil de revisar y reproducir. Los valores de amplitud, tiempos y orientación deben ser editables; no he encontrado fuentes primarias que establezcan un rango universal de ráfagas para aviones RC.

## Turbulencia continua: proceso coloreado y elección espectral

La turbulencia es una sucesión aleatoria **correlacionada**, definida por nivel e integral de escala, no una suma de valores independientes en cada tick. NASA describe la construcción Dryden como ruido blanco limitado en banda que atraviesa filtros lineales para producir componentes longitudinal, lateral y vertical; el reescalado de frecuencia usa la velocidad verdadera (V_a). El tiempo característico de cada componente es:

\[
\tau_i=\frac{L_i}{V_a},\qquad \Omega=\frac{\omega}{V_a},
\]

donde (L_i) es escala de turbulencia en m, (V_a) en m/s, τ en s, ω frecuencia angular temporal en rad/s y Ω frecuencia angular espacial en rad/m. Las intensidades σₑ, σᵥ, σw son desviaciones estándar RMS de velocidad de ráfaga en m/s. Por eso, a misma (L), más velocidad de vuelo significa atravesar la estructura más rápido. [NASA-TM-78141, *A technique for simulating turbulence for aerospace vehicle flight simulation studies*](https://ntrs.nasa.gov/archive/nasa/casi.ntrs.nasa.gov/19780004071.pdf)

Una forma de las densidades espectrales espaciales Dryden, de un solo lado y normalizadas para que el área sobre Ω positiva sea σ², es:

\[
\begin{aligned}
\Phi_u(\Omega)&=\sigma_u^2\frac{2L_u}{\pi}\frac{1}{1+(L_u\Omega)^2},\\
\Phi_v(\Omega)&=\sigma_v^2\frac{L_v}{\pi}\frac{1+3(L_v\Omega)^2}{[1+(L_v\Omega)^2]^2},\\
\Phi_w(\Omega)&=\sigma_w^2\frac{L_w}{\pi}\frac{1+3(L_w\Omega)^2}{[1+(L_w\Omega)^2]^2}.
\end{aligned}
\]

Los términos σ² son varianzas de velocidad; (L) en m y Ω en rad/m. Para pasar a frecuencia temporal angular, (ω=V_aΩ) y la densidad se transforma con el jacobiano correspondiente (por ejemplo, (Phi_t(\omega)=\Phi_x(\omega/V_a)/V_a) bajo la misma convención unilateral). La documentación NASA presenta estas formas y contrasta sus filtros; NASA/CR-1998-206937 compara implementaciones de filtros Dryden y comprueba sus series frente a los espectros y respuestas del modelo. [Madden, NASA, *Verifying Implementation of the Dryden Turbulence Model and MIL-F-8785 Gust Gradient*](https://ntrs.nasa.gov/search.jsp?R=20190000875) · [Yeager, NASA/CR-1998-206937](https://ntrs.nasa.gov/citations/19980028448)

El modelo Dryden es útil para empezar una turbulencia continua porque sus espectros son racionales y se realizan con filtros de orden finito. En $V_a=0$, $L/V_a$ y la conversión de frecuencia no están definidos; la implementación debe tomar una rama explícita y documentada, sin dividir por cero. Al acercarse $V_a$ a cero, $\tau=L/V_a$ crece y el filtro debe permanecer estable; no introducir un umbral silencioso. Dryden con escalas convertidas por la velocidad de avance presupone que el avión atraviesa el campo, por lo que no caracteriza por sí solo turbulencia temporal en hover. Una configuración debería exponer al menos modelo, σ por eje, $L$ por eje, semilla y quizá referencia de altura/ley de intensidad. Sus valores por defecto pueden ser cero/desactivado. Si se crea antes un ruido coloreado de un polo, etiquetarlo como **aproximación correlacionada**: no llamarlo Dryden a menos que los tres espectros, los parámetros y la transformación de frecuencia correspondan al modelo.

Von Kármán ajusta mejor el tramo de alta frecuencia del espectro inercial en algunas mediciones, con caída asintótica cercana a Ω⁻⁵ᐟ³; los espectros Dryden racionales caen como Ω⁻² y son más simples de factorizar en filtros causales. NASA remarca que el ajuste observado depende de componente y condición. En datos de turbulencia medidos a 100–200 ft AGL, la componente vertical fue claramente no gaussiana y algunas bandas ajustaron mejor a Dryden y otras a von Kármán. Así que von Kármán es una ruta de fidelidad espectral posterior, no una mejora garantizada para un modelo RC sin registros de vuelo. [NASA-TM-2008-215633, §2.3.13](https://ntrs.nasa.gov/api/citations/20090022159/downloads/20090022159.pdf) · [NASA-CR-2886, low-altitude turbulence measurements](https://ntrs.nasa.gov/citations/19770025195)

## Coherencia espacial y diferencias sobre la envergadura

Una turbulencia temporal en el centro del avión modela qué flujo encuentra ese punto, pero no define cómo cambia el viento a lo largo del ala ni si dos aviones cercanos encuentran la misma ráfaga. La hipótesis de Taylor, usada para pasar de espectro temporal a espacial, aproxima que un campo eddy se traslada congelado por el flujo, de modo que una separación temporal $\Delta t$ equivale a distancia $V_a\Delta t$. Un campo coherente requiere que el viento se pueda muestrear como función reproducible de ubicación y tiempo, no que cada estación consuma otra muestra aleatoria. La hipótesis presupone una trayectoria y velocidad de avance suficientemente estables; en virajes fuertes la dirección de muestreo cambia y en vuelo estacionario con $V_a\to0$ la conversión deja de servir.

Como orden de magnitud, la diferencia de flujo entre extremos de ala en una variación suave es:

\[
\Delta W\approx b\,\frac{\partial W}{\partial y},\qquad
v_{rel,j}^{body}=v_{g,CG}^{body}+\omega_{body}\times r_j^{body}-R_{body\to NED}^{T}W(x_{CG}^{NED}+R_{body\to NED}r_j^{body},t).
\]

$b$ es envergadura; $r_j^{body}$ es el punto de una estación respecto al CG en ejes del cuerpo; $R_{body\to NED}$ rota puntos del cuerpo a NED y su transpuesta rota la velocidad del viento de NED a cuerpo. Esta diferencia puede dar cargas asimétricas y momento de alabeo. NASA midió varios componentes en ambas puntas de ala y publica correlaciones cruzadas spanwise; su estudio afirma que la distribución espacial afecta fuerzas y momentos. También señala que la turbulencia de la capa límite cerca del suelo, tormentas y terreno puede no ser isotrópica ni homogénea. [NASA-CR-2886](https://ntrs.nasa.gov/citations/19770025195) · [NASA-CR-178288, *Analyses and assessments of spanwise gust gradient data*](https://ntrs.nasa.gov/citations/19880000625)

Para la primera versión, asumir una ráfaga uniforme sobre todo el avión da una fuerza coherente simple, aunque omite momentos producidos por diferencias de viento entre ala izquierda y derecha. Más adelante se puede crear un campo espacial determinista (semilla, escala y advección) y evaluar viento local en superficies aerodinámicas. En este proyecto las estaciones actuales no son un solver completo de cargas distribuidas; no basta con restar un valor de viento distinto a cada una sin derivar cómo sumar fuerzas y conservar los términos de amortiguamiento aerodinámico.

## Secuencia sugerida y pruebas que demuestran el modelo

1. **Viento medio constante:** vector NED configurable, conexión a `Air.compute`, propulsión y telemetría; calma equivale exactamente al comportamiento actual. Los escenarios y trazas registran unidades, dirección `from`, referencia y procedencia de parámetros.
2. **Ráfaga determinista:** subida `1 − cos`, magnitud y dirección configurables, opción de duración por segundos o distancia (H); controlar reloj/tiempo de etapa, pausa, replay y semilla.
3. **Cambio lento del fondo:** curva de velocidad/dirección o lag ajustable, con interpolación angular por el arco corto; no reutilizar el parámetro como “intensidad de turbulencia”.
4. **Turbulencia correlacionada ligera** (solo si mejora la sensación de vuelo): señalarla como modelo simplificado y calibrar amplitud con pilotos.
5. **Perfil de altura/cizalladura y coherencia espacial:** añadir cuando el escenario tenga altura AGL/rugosidad definida y el modelo pueda sumar cargas por superficie.
6. **Dryden configurable opcional** basada en σ, L, Va, filtro correcto y un generador privado con semilla. Verificar estadística, no un valor exacto de cada muestra. Von Kármán o una distribución no gaussiana quedarían para cuando haya mediciones RC que justifiquen ese costo.

Esta jerarquía física complementa [WIND-PLAN.md](../WIND-PLAN.md), que fija el orden de producto: aproximación OU, campo por altura/posición y Dryden como opción posterior.

Pruebas matemáticas útiles para separar implementación de validación física:

- Convenciones: dirección desde 000° produce vector norte negativo; 090° produce este negativo; los casos calmo, frontal y cruzado mantienen los signos probados por `test_air_data.gd`.
- Aire relativo: (V_{air}=|V_g-W|), α/β rotan con actitud, (\bar q\to0) cuando velocidades de avión y aire coinciden; viento cero reproduce la traza de referencia.
- Ráfaga espacial `1-cos`: en (s=0,H,2H), los factores son 0, 1, 0; a (s=H/2), 0.5. Inicio/fin con tiempo cero o duración inválida deben rechazarse o desactivarse con una regla definida.
- Cambio lento: velocidad y dirección alcanzan el 63.2 % de un salto en una constante τ si se elige primer orden; al cruzar 359°→1° debe cambiar 2°, no 358°.
- Reproducibilidad: mismo escenario, semilla y tiempo simulado producen la misma secuencia bajo 30/60/144 FPS y en traza/captura; pausa congela el viento. El RNG se consume al ritmo físico elegido, no cada vez que el integrador consulta cargas.
- Dryden: para una serie larga, media cercana a cero, RMS cercano a σ y PSD aproximada a las curvas objetivo dentro de banda y tolerancia fijadas. Esto verifica el filtro; solo mediciones externas de viento o vuelos de un RC, idealmente con anemómetro y registros de maniobra, pueden validar que sus parámetros representen esa condición real.

Las estimaciones deben conservar su procedencia y límite. Una prueba de unidad o una coincidencia del espectro generado con la ecuación no demuestra que el jugador perciba un viento “realista”; para ese juicio hacen falta vuelos repetibles y evaluación de pilotos.

## Fuentes primarias

| Fuente | Para qué sirve aquí | Límite de transferencia |
| --- | --- | --- |
| [NOAA NWS, glosario: Wind Direction](https://forecast.weather.gov/glossary.php?word=WIND+DIRECTION) | Dirección meteo es desde donde sopla; norte a sur se llama viento del norte. | Define convención, no dinámica del avión. |
| [FAA JO 7900.5E, Surface Weather Observing, capítulo 7](https://www.faa.gov/media/70751) | Movimiento horizontal, dirección desde la que sopla y criterio observacional para reportar ráfaga. | Criterio de reporte, no espectro ni preset RC. |
| [14 CFR §25.341, GovInfo PDF](https://www.govinfo.gov/content/pkg/CFR-2022-title14-vol1/pdf/CFR-2022-title14-vol1-sec25-341.pdf); [FAA AC 25.341-1](https://www.faa.gov/documentLibrary/media/Advisory_Circular/AC_25_341-1.pdf) | Onda discreta `1 − cos`, distancia de gradiente y análisis dinámico. | Criterio de carga de aviones de categoría transporte; no amplitudes típicas de RC. |
| [JSBSim FGWinds, documentación](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGWinds.html); código fuente FGWinds.cpp | Composición NED de componentes, marcos de ráfaga, perfil sube/meseta/cae, semilla y filtros Dryden. | La documentación y signos de SetWindPsi/SetWindspeed parecen contradecirse; revisar sus cardinales antes de portar. Sus presets MIL no están calibrados para RC. |
| [NASA-TM-78141, método Dryden recursivo](https://ntrs.nasa.gov/archive/nasa/casi.ntrs.nasa.gov/19780004071.pdf); [NASA/CR-1998-206937, Yeager](https://ntrs.nasa.gov/citations/19980028448) | σ, escalas, dependencia de (V_a), filtros y comprobación de PSD. | Diseño de simulación de aeronaves, no observación de una flota de RC. |
| [NASA-CR-2886, turbulencia de baja altura medida](https://ntrs.nasa.gov/citations/19770025195); [NASA-CR-178288, gradiente spanwise](https://ntrs.nasa.gov/citations/19880000625) | Evidencia de variación espacial, mediciones de ala/puntas y límites de modelos homogéneos. | Aviones, velocidades, superficies y condiciones del estudio son de otra escala. |
| [NASA-CR-2288, viento y turbulencia en capa superficial](https://ntrs.nasa.gov/citations/19730018294) | Rugosidad, estabilidad, altura y perfiles logarítmicos de viento. | La condición neutra no describe todos los campos o terrenos del simulador. |
| [NASA TM-2008-215633, §2.3.13](https://ntrs.nasa.gov/api/citations/20090022159/downloads/20090022159.pdf) | Diferencia espectral de Dryden y von Kármán y motivo de uso de filtros racionales. | Referencia de aeronaves; elegir espectro no sustituye la calibración de σ y (L). |
