# Calibración provisional del modelo visual Jensen .61

Fecha: 2026-10-05. Fuente geométrica: plano Jensen oz1253 firmado, hoja rasterizada. El resultado es una **traza proporcional provisional**, no una calibración metrológica aceptada.

El plano firmado imprime 60 in de envergadura y 720 in² de área, pero no rotula la longitud del fuselaje. La hoja 1 tiene vistas en planta y perfil con suficiente detalle para iniciar la primera malla; varios contornos se cruzan con el ala, varillajes y una vista ampliada de la cola.

## Medida y uso inmediato

El render usado mide 2400 × 1790 px para la hoja 1. Su SHA-256 es `d5a79f156901fd6ed2c7948a186d0c17e66b99b7d1e84eb8732e8e533fd056bc`. La rueda delantera rotulada **2¾ in** mide 131 × 131 px entre extremos elegidos. Esto da **0.533206 mm/px**, solo como conversión condicional. Con ±2 px por extremo, el intervalo es 0.5174–0.5500 mm/px. La escala calculada del ancho físico de la hoja es 0.511069 mm/px: difiere 4.33 % de la rueda, que también puede ser esquemática.

En planta, la línea exterior del fuselaje va aproximadamente de x=48 a x=2050 px. Aplicando la conversión de la rueda, esa longitud resulta 1.068 m. Para que las estaciones encajen con la envolvente actual del app, el JSON también incluye un mapeo normalizado a Z=−0.44…+0.68 m (1.12 m total); eso estira la longitud condicional 4.9 % y **no** convierte 1.12 m en una cota Jensen.

Las anchuras totales aproximadas leídas en planta son 147 px junto al cortafuegos (78 mm condicionales), 194–199 px en la sección ancha del fuselaje (103–106 mm), y cerca de 59 px al final del fuselaje (31 mm). El semiancho es la mitad de esos valores: alrededor de 39–53 mm. El lado inferior del perfil se lee cerca de y=1373 px. La línea alta queda oculta por el ala en el tramo central, así que esas alturas tienen menos confianza que las anchuras de planta.

El JSON conserva estaciones cada 100 px, los puntos en coordenadas originales del render, la incertidumbre de selección, conversión condicional y mapeo directo a la envolvente local. **La cola queda sin resolver y no se ofrece un contorno válido para la malla.** Retiré los puntos que parecían contorno de estabilizador porque cruzaban fuselaje, varillajes y el detalle ampliado. El arco visible en el detalle de fin/rudder queda como observación solamente: su escala y datum no están establecidos, así que no representa un borde montado medible.

## Controles intentados

La rueda da un control corto en ambas direcciones del raster, pero no prueba la escala de toda la hoja. Las ruedas principales dicen **3 in o 3¼ in**, por lo que solo dan un rango. Se intentó usar 30 in por semiala de la hoja 2, pero el extremo de línea central y el de punta no quedan lo bastante claros en este escaneo para fijar ambos sin ambigüedad. El área media `720/60=12 in` deriva de dos cotas ya impresas; no es una tercera medida independiente. Por eso no se declara calibración global ni se reescala el plano para forzar concordancia.

Las estaciones de fuselaje del JSON pueden guiar el volumen visual de esa pieza. El archivo no proporciona un contorno de cola utilizable, ni datos para derivar masa, centro de gravedad o aerodinámica.

## Archivos

- [Puntos y conversiones en JSON](../../research/ugly-stik/calibration-v1/jensen-contours.json)
- PDF Jensen local (`references/ugly-stik/downloads/jensen/Das_Ugly_Stik_Jensen_oz1253.pdf`, local only)
- Los renders de revisión y sus crops están en `references/ugly-stik/calibration-v1/renders/` (artefactos locales ignorados por Git).
