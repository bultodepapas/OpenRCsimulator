# Transparencia, proximidad y orden del humo

**Fecha:** 2026-10-05. **Pregunta:** ¿cómo suavizar el contacto del humo con avión y terreno en Godot 4.7.2 Compatibility sin basar el material en funciones ausentes?

## Resultado

La primera opción es `StandardMaterial3D`, billboard de partículas y alpha blending. Solo si la captura muestra un corte contra objetos opacos, probar `proximity_fade_enabled`, la opción nativa descrita para partículas suaves. No empezar con un shader custom; comprobar el material real en el binario 4.7.2-stable y renderer Compatibility.

Godot 4.7 admite depth texture en Compatibility. Si una prueba necesita reconstrucción manual, la profundidad cruda no es lineal. La coordenada Z NDC de OpenGL ocupa [-1,1]:

```glsl
float depth = texture(depth_texture, SCREEN_UV).r;
vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
view.xyz /= view.w;
float scene_depth = -view.z;
```

La fórmula Vulkan/Mobile con XY reescalados no se traslada directamente. Un depth fade custom compara distancias lineales y reduce alpha cerca del sólido. La matriz de renderers confirma la ruta; una incidencia en 4.4.1 informó un fallo dentro de una función en Compatibility, así que sigue siendo obligatorio compilar y capturar en 4.7.2 antes de adoptarlo.

## Tres problemas separados

- `proximity_fade` suaviza profundidad **opaca** (ala, fuselaje, suelo). No borra la intersección visual entre dos billboards: una transparencia anterior no aparece como profundidad opaca para la siguiente.
- `Camera3D.near` recorta la escena completa; no es un control local de soft particles. Si la cámara entra en humo, probar aparte fade de distancia del material o alejar el punto de nacimiento, desde las cámaras piloto y externa.
- El orden entre `VisualInstance3D` transparentes es aproximado. Por defecto se ordena usando la posición global; `sorting_use_aabb_center = true` usa el centro AABB y `sorting_offset` añade desplazamiento. El centro puede ayudar en mallas largas, pero la posición suele dar mejor control con partículas. Ninguna opción ordena por fragmento ni implementa order-independent transparency. `GPUParticles3D.DRAW_ORDER_VIEW_DEPTH` ordena partículas **dentro de un emisor**; no combina el escape, la bomba y otros objetos transparentes. Mantener `DRAW_ORDER_INDEX` como base y probar view-depth solo en la bomba densa.

La niebla de profundidad/altura de Environment sí funciona en Compatibility; FogVolume y niebla volumétrica no. La niebla ambiental reduce contraste lejano y puede revelar banding. Comparar las capturas con y sin niebla, usando el paisaje final; no sumar niebla volumétrica para disimular transparencias.

## Referencias de shaders y licencia

[Smoke Shader de arlez80 / Yui Kinomoto](https://godotshaders.com/shader/smoke-shader/) declara MIT. Su ruido por fragmento repite varias octavas y el código original usa sintaxis antigua (`hint_color`); estudiarlo para ideas de borde no justifica copiarlo ni presupone costo aceptable. [Stylized Smoke Shader de Loop_Box](https://godotshaders.com/shader/stylized-smoke-shader/) declara CC0 para el código del post y enlaza un demo Godot 4.5. La página aclara que sus imágenes/video/assets no están cubiertos por esa licencia; también registra uniforms sin uso y un reporte de invisibilidad. Godot Shaders aplica la licencia que el autor declara al snippet, no automáticamente a sus previews o assets. Mantener material y recursos propios.

## Cambio al plan y aceptación

En SM-00 comparar el StandardMaterial3D sin proximidad y con proximity fade. La escena prueba humo contra plano opaco, ala cercana, niebla on/off, entrada de cámara y cruce de estela nueva/vieja; luego compara índice y `DRAW_ORDER_VIEW_DEPTH` en la bomba, sin suponer sorting entre emisores. Registrar versión, renderer, errores de shader, frame time y capturas a 30/60/144 fps. Aceptar el fade nativo si suaviza sólidos sin borrar humo contra humo. Si falla, crear una prueba custom pequeña con NDC Compatibility arriba y promoverla solo tras compilar y capturar desde ambas cámaras.

La documentación establece soporte y API, no costo del fade ni estabilidad del orden durante un looping en el equipo objetivo. SM-00 resuelve esas dos incertidumbres.

## Fuentes primarias

- [Matriz de renderers Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html); [VisualInstance3D: centro AABB y offset](https://docs.godotengine.org/en/4.7/classes/class_visualinstance3d.html).
- [Screen-reading shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/screen-reading_shaders.html), [reconstrucción NDC Compatibility](https://docs.godotengine.org/en/4.7/tutorials/shaders/advanced_postprocessing.html), [StandardMaterial3D](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html) y [límites de sorting](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_rendering_limitations.html).
- [Fog de Environment y banding](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html); [incidencia de shader Compatibility 4.4.1](https://github.com/godotengine/godot/issues/109553).
- [Licencia Godot Shaders](https://godotshaders.com/license/), [snippet MIT de arlez80](https://godotshaders.com/shader/smoke-shader/) y [snippet CC0 de Loop_Box](https://godotshaders.com/shader/stylized-smoke-shader/).
