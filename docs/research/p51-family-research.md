# Investigación: P-51D Mustang gigante para motor de 120 cc

Revisión: **2026-10-06**. Objetivo: elegir una referencia RC documentada para un **P-51D de clase 120 cc gasolina** (DA-120 / DLE-120 / 3W-110) y reunir los números que necesita el modelador físico. Todo lo citado se leyó en la sesión salvo lo marcado **[fragmento]** (número visto solo en el resumen de un buscador, página no abierta) o **[calculado]**. Descargas locales con hash en [p51-resources.json](p51-resources.json) y en `references/p51-mustang/` (ignorado por git).

## Hallazgo principal: no existe un ARF comercial de P-51D para 120 cc

Se comprobaron todos los candidatos del encargo. Ningún ARF comercial se especifica para 100-150 cc:

| Candidato | Qué es realmente | Fuente |
| --- | --- | --- |
| Top Flite Giant P-51D (TOPA0400 kit / TOPA0700 ARF) | 84,5 in (2146 mm), 1245 in², 73,5 in, 18-23 lb, 35-45 cc glow / 41-70 cc gasolina | towerhobbies.com (ficha), manual TOPA0400 (descargado) |
| Hangar 9 P-51D 60cc (HAN4770) | 89,0 in (2260 mm), 1420 in², 77,5 in, 25-27 lb, 50-60 cc | manual HAN4770 (descargado, 112 pp) |
| CARF-Models P-51 Mustang «1:4.3» | 100 in (2540 mm), 89 in, 33-37 lb (15-17 kg) seco, **50-85 cc**; £2.775 | nexusmodels.co.uk; manual CARF (descargado, 29 pp) |
| ESM P-51B | 71 in, 13,5 lb, 26 cc | Model Aviation |
| Black Horse P-51D | 1560 mm y 2050 mm (33-40 cc) | blackhorsemodel.com.vn |
| Seagull / Legend Hobby P-51D | 56 in (10 cc) y 71 in (35 cc) | legendhobby.com |
| Phoenix Model PH205 | 87 in, 60 cc | phoenixmodel.com |
| TopRC Model P-51D | 89 in, 1397 in², 11 kg, 50-65 cc, composite | toprcmodel-usa.com |
| RC Warbird Models 96" P-51D | 96 in, 60-85 cc, composite, 31 lb con DLE-85 | rcwarbirdmodels.com |
| Meister Scale Heritage P-51D | 1/5, 84 in, ~25 lb, 50-60 cc | meister-scale.com |
| Ziroli P-51D (planos) | 1/4,6, 98 in, 1650 in², 26-36 lb, 62-85 cc | ziroligiantscaleplans.com |
| Jerry Bates P-51B/C 1/4 (planos) | 112,25 in, 96,75 in, 50 lb+, 80 cc+ | fighteraces.co.uk |
| Chad Veich P-51D 1/4 (planos) | 284,5 cm, 1,36 m², 18-27 kg, «5 cu in +» (≈82 cc+) | lcka.com.au |
| FokkeRC P-51D 1/4 (short kit) | 2819 mm / 2457 mm, motor Kolm IL155 (155 cc), retráctiles Sierra | fokkerc.com |
| Pilot-RC, Hostetler | Sin producto actual | — |

**Conclusión.** El «P-51 de 120 cc» es un **modelo a escala 1/4 (2,82 m, 18-27 kg) construido de planos o short kit**, con DA-120 / DLE-120 / 3W-110 / Kolm 155. La documentación comercial completa termina en el CARF de 2,54 m / 85 cc.

## Referencia elegida y por qué

**Geometría: P-51D real a escala exacta 1/4** (envergadura 11,28/4 = 2,82 m; longitud 9,83/4 = 2,457 m; área 21,83/16 = 1,364 m² **[calculado]**, que coincide con los 1,36 m² de Veich y con los 111 in / 96,75 in de Bates y FokkeRC). **Instalación: DA-120** (121 cc, 11,7 hp, 1300-6900 rpm, 2,445 kg con encendido; hélices listadas 27×11, 28×9,5, 28×10, 28×12, 29×10 bipala y 26×12, 27×12 tripala). **Ajustes de vuelo: manuales CARF, Hangar 9 60cc y Ziroli**, escalados por cuerda/envergadura.

Motivos: (a) la clase de 120 cc existe solo en esa escala; (b) la escala 1/4 exacta permite derivar toda la geometría de las cotas públicas del avión real y de la tres vistas de dominio público, sin copiar planos comerciales; (c) tres manuales gratuitos de P-51 grandes (CARF 2,54 m, Hangar 9 2,26 m, Top Flite 2,15 m) dan CG, recorridos y flaps convergentes.

### Datos de los manuales descargados

| Dato | CARF 2540 mm | Hangar 9 HAN4770 (2260 mm) | Top Flite TOPA0400 (2146 mm) | Ziroli 98 in |
| --- | --- | --- | --- | --- |
| CG | borde delantero del tubo alar; sin lastre con baterías en el morro (p. 28) | 171 mm tras el BA en la raíz (rango 165-178 mm); alternativa 158 mm delante de la esquina del alerón en la punta | 116 mm (4-9/16 in) tras el BA en el «quiebro» del BA, ±8 mm | 8¼ in tras el BA en el fuselaje |
| Alerones (alto) | 12,7 mm arriba/abajo | 22 mm arriba / 17 abajo (medio 18/14, bajo 15/11) | 19 arriba / 16 abajo | — |
| Elevador (alto) | 19 mm arriba / 12,7 abajo | 25 mm | 14 mm | — |
| Timón (alto) | 51 mm | 55 mm (el «25/32 in» impreso es una errata) | 38 mm | — |
| Flaps | 15° despegue, 45° aterrizaje | 25 mm medio, 72 mm aterrizaje; mezcla elevador arriba 7 % / 14 % | 22 mm y 54 mm | — |
| Motor | 13,5° girado en la bancada, 2 mm desplazamiento lateral; sin ángulos de empuje publicados | Evolution 62GXi, hélice 22×8-24×10, ruedas 130 mm | 1,75° de empuje abajo; empuje derecho «en la bancada» | ala +2,5° raíz, estabilizador +1°, diedro 5¼ in bajo W14 |
| Peso | 15-17 kg seco | 11,3-12,2 kg | 8,2-10,4 kg (ARF) | 11,8-16,3 kg |

Conversión a %MAC **[calculado]**: Hangar 9 171 mm a 1/5 = 0,86 m a escala real tras el BA de raíz; con la extensión del BA de raíz del D (≈1,5 in en el modelo) queda cerca del 25 % MAC; Top Flite 116 mm ≈ 23 %. El P-51D real admite 20-32 % MAC. Para el simulador se adopta **27 % MAC** como punto inicial (estimado).

Recorridos adoptados **[calculado]**: Hangar 9 alto escalado por envergadura (2,82/2,26 = 1,25): alerón 27 mm, elevador 31 mm, timón 69 mm, convertidos a grados con las cuerdas locales del modelo en `research/p51/p51-05/derive_physics.py`.

## Geometría del P-51D real para el modelo 3D

| Elemento | Valor | Fuente |
| --- | --- | --- |
| Envergadura | 37 ft 0 in (11,28 m) | warbirdsresourcegroup.org; DCS |
| Longitud | 32 ft 3 in (9,83 m) | ídem |
| Área alar | 235 ft² (21,83 m²) [WRG]; 233,19 ft² [DCS]; 233 ft² [Mason] | ídem |
| Cuerdas raíz/punta | 104 / 50 in (reproducen 235 ft² a la línea central) frente a Mason 101,8 / 46,4 in, AR 5,876 (233 ft²): **sin resolver**; el modelo usa 104/50 | Mason (VT) |
| MAC | ≈ 80 in (2,03 m) **[calculado]** | — |
| Perfil | NAA/NACA 45-100. Ordenadas UIUC: raíz BL17,5 t/c 16,5 % a 39 %, curvatura 1,26 %; punta BL215 11,4 % a 46 %, curvatura 1,30 % **[calculado de los .dat]** | m-selig.ae.illinois.edu |
| Diedro / incidencia | 5° a lo largo del 25 % de cuerda; ~1° en la raíz **[fragmento]** | modelflying.co.uk |
| Cola horizontal | 45,4 ft², envergadura 13,1 ft, cuerdas 4,6 / 2,3 ft | Mason |
| Cola vertical | 14,8 ft², altura 4,7 ft, cuerdas 4,7 / 1,6 ft | Mason |
| Hélice | Hamilton Standard cuatripala hidromática, 11 ft 2 in | DCS |
| Vía del tren | «casi 12 pies» **[fragmento]**; 11 ft 10 in y ruedas 27 / 12,5 in **sin verificar** | — |
| Pesos | vacío 7.635 lb, cargado 9.200 lb, máximo 12.100 lb | WRG |
| Velocidades | máx. 437 mph; pérdida 100 mph; con tren y flaps 45°: 94 mph (9.000 lb) | WRG; DCS p. 115 |
| Coeficientes (estudio docente) | CLmax 1,5; CL crucero 0,2; CD0 0,0055 | Mason |

Cabina burbuja (las Dallas y las Inglewood son intercambiables), aleta dorsal añadida en el D por estabilidad direccional, extensión del borde de ataque en la raíz. Toma de radiador por efecto Meredith con compuerta de salida variable: sin cotas públicas.

## Motores de clase 120 cc

| Motor | Cilindrada | Peso | Potencia | Régimen | Hélices | Fuente |
| --- | --- | --- | --- | --- | --- | --- |
| DA-120 | 121 cc | 2,30 kg motor / 2,445 kg con encendido | 11,7 hp | 1.300-6.900 | 27×11, 28×9,5, 28×10, 28×12, 29×10; tripala 26×12, 27×12 | desertaircraft.com; toni-clark.com |
| DLE-120 | 120 cc | 2,31 kg motor; 2,78-2,90 kg completo | 12 hp a 7.500 | ralentí 1.300 | 26×10, 26×12, 27×10, 28×10 | manual DLE; macgregor.co.uk |
| 3W-110i B2 / CS | 110 cc | 3,05 kg con encendido | 11,8 / 12,8 hp | 1.200-8.500 | 26×10, 27×14 tripala, 28×12, 30×10 | 3w-modellmotoren.de |

Medidas de hélice **[fragmentos]**: Mejzlik 28×10 en DA-120 ≈ 6.700 rpm estático; Falcon 28×10: 6.550 rpm y 31 kg de empuje. Consumo DA-120 ≈ 70-95 ml/min **[calculado de fragmentos]**. El empuje estático del DLE-120 aparece como 9,5 kg y como «50 lb» en dos distribuidores: inconsistente, no usado.

## Comportamiento en vuelo de los P-51 gigantes (lo que el simulador debería reproducir)

- Despegue: al levantar la cola, guiñada a la izquierda por par, factor P y precesión; despegar antes de tiempo entra en pérdida el ala izquierda. El CARF «solo necesita un poco de timón izquierdo» **[fragmento]**.
- Pérdida: el Hangar 9 20 cc «deja caer un ala en la pérdida completa»; el real avisa con buffeting y se recupera con timón.
- Aterrizaje: preferido de ruedas; en tres puntos «rebota feo» sin ejecución perfecta; con medio flap y cortar gas a un palmo del suelo. Flaps completos en el Top Flite dan mucha tasa de descenso.
- Acoplamiento flaps-cabeceo: el Hangar 9 necesita 7 % / 14 % de elevador arriba.
- Estimación de pérdida para el simulador **[calculado]**: 1/4, 22 kg, 1,36 m², CLmax 1,3 → 14,1 m/s; con flaps CLmax 1,6 → 12,7 m/s.

## Modelos 3D libres

No hay P-51D con licencia CC0/CC-BY; Sketchfab ofrece CC BY-NC y CC BY-NC-ND (no aptos). Se construye la malla propia desde la tres vistas de dominio público y los perfiles UIUC.

## Preguntas abiertas

1. Cuerdas raíz/punta 104/50 in frente a 101,8/46,4 in (Mason): hace falta la página de cotas del AN 01-60JE-2 (solo con registro en aircorpslibrary.com / avialogs.com).
2. Vía 11 ft 10 in y ruedas 27 / 12,5 in sin confirmar.
3. Espesor de raíz: 16,5 % (UIUC BL17,5, zona del encastre) frente a 15,1 % y 13,8 % citados; el modelo usa el .dat de UIUC.
4. Hélice cuatripala del modelo: el DA-120 lista tripalas 26×12 / 27×12; la cuatripala 26×12 es una elección de aspecto, su régimen estático sale del modelo de elemento de pala (sin medida).
5. Hilos de RCU/RCGroups/FlyingGiants con reportes de vuelo están tras muros 402/403: solo fragmentos.
