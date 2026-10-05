# Ala v3: contorno trazado y límites de la interpretación

2026-10-05 · US-05 · Fuente: hoja 2 del Jensen oz1253, conservada localmente. Los [puntos y conversiones](../../research/ugly-stik/model-v3/wing-trace.json) registran hash, página, raster de 100 dpi y tolerancia de selección de ±4 px.

La sección visual v2 tenía coordenadas elegidas a mano para representar una descripción semisimétrica. V3 usa puntos leídos sobre el contorno exterior de la costilla: borde de ataque `(2283,1748)`, borde de salida `(3641,1764)` y línea de bisagra aproximada en `x=3489`. Se resta la recta entre ambos bordes para expresar alturas relativas a la cuerda. La bisagra queda en el 88,81 % de la cuerda, frente al 78 % anterior; el alerón tiene aproximadamente 34,1 mm de cuerda visual antes del alivio de bisagra.

**La sección no aporta una nueva cuerda física.** El detalle mide 13,58 pulgadas según la escala de página, diferente de las 12,07 pulgadas leídas en el perfil montado de la hoja 1. Se normalizan proporciones y se conserva la cuerda representativa de 0,3048 m del modelo y de física. El resultado sigue etiquetado como estimado: no demuestra incidencia instalada ni una polar aerodinámica. No se le atribuye un perfil NACA.

En planta se identificaron el centro alar `x=4450`, la punta delantera alrededor de `x=1630`, la punta trasera alrededor de `x=1380`, la costilla de punta `x=1675` y el extremo interior del alerón `x=3900`. Sus diferencias se normalizan a la semienvergadura nominal de 0,762 m. La punta ya no termina en una tapa perpendicular rectangular: su límite avanza hacia el interior en el borde de ataque. El generador aplica la misma transformación al borde fijo y al móvil. El festoneado del borde de salida y el redondeo fino se simplifican; no se presentan como una reproducción exacta.

La envergadura nominal, cuerda representativa, borde de ataque longitudinal y línea de empuje compartidos con física permanecen fijos. Se mantiene el diedro estimado de 2,86°, identificado como tal. La forma de la costilla no autoriza alterar los coeficientes de vuelo.

El alivio de bisagra de 1,6 mm y la separación interior del alerón de 1,5 mm son decisiones visuales de montaje para evitar penetración durante el recorrido existente, no cotas publicadas Jensen. Sus holguras se comprueban sobre las mallas construidas. Los pivotes conservan los marcos estáticos de diedro y los signos de los mandos.

La revisión final del modelo reúne capturas y comprobaciones de esta modificación con el fuselaje y la cola. Los puntos de la fuente se guardan como evidencia; no se copian los rasterizados de terceros al repositorio público.
