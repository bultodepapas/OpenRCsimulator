# Repositorios y herramientas Godot para humo de partículas

**Fecha de revisión:** 2026-10-05. **Pregunta:** ¿hay una demo o extensión existente que convenga integrar en el humo tenue del motor y el canal de bomba, bajo Godot 4.7.2 Compatibility/OpenGL?

## Hallazgo

Hay buenos ejemplos de composición y edición, pero ninguno justifica añadir código externo al simulador. Los repositorios más prometedores usan Forward+ o no declaran prueba en 4.7.2/Compatibility. La decisión de menor riesgo es conservar `GPUParticles3D`, `QuadMesh` y `StandardMaterial3D` propios del proyecto; tomar ideas de composición; y demostrar la apariencia en un experimento del paso SM-00. No se copió código ni se descargó, instaló o añadió una dependencia.

## Candidatos inspeccionados

| Candidato y evidencia examinada | Licencia/versión observada | Compatibilidad y decisión | Ref consultada el 2026-10-05 |
| --- | --- | --- | --- |
| [Bonkahe/BasicParticleEffects](https://github.com/Bonkahe/BasicParticleEffects): README, licencia, `particle_effects_demo.tscn` y `project.godot`. El árbol muestra `particle_sprite_smoke.webp`; el material usa billboard para partículas, atlas 8×8 y `proximity_fade`; la escena separa controles y emisores. | El README lo presenta para Godot 4.x y el repo publica licencia CC0-1.0. El archivo de proyecto consultado no fija una versión patch. | Referencia útil para separar emisor/material y para evaluar un flipbook, pero la escena completa pide SSIL, SDFGI y niebla volumétrica. Son funciones que no trasladan directamente el demo al renderer Compatibility. No integrar el proyecto ni su textura: reproducir primero una máscara propia pequeña y probar `proximity_fade` en nuestra escena. | `main` → `7589f716854ede38678ef9617d331909961a619b` |
| [Brackeys/vfx-in-godot](https://github.com/Brackeys/vfx-in-godot): README, `vfx/project.godot` y `vfx/scenes/fire.tscn`. El recurso separa varios emisores, incluida una capa de humo, y asigna un pase de malla a partículas. | README declara CC0 para el proyecto y recursos incluidos. `project.godot` declara `config/features=PackedStringArray("4.6", "Forward Plus")`. | La separación de capas sirve como referencia visual para humo abundante. El proyecto está declarado Forward+, no demuestra OpenGL Compatibility y debe rechazarse como paquete ejecutable para este repo. No importar assets ni escenas. | `main` → `23b58f272b828b0a894ed7ef72fbf9033ee9d177` |
| [Godot Foundation: Particles 3D Demo](https://store.godotengine.org/asset/godot-foundation/particles-3d-demo/), ficha oficial y [fuente](https://github.com/godotengine/godot-demo-projects/tree/3e08537616661a5883831628decab4c526260289/3d/particles). | Licencia MIT, mínimo Godot 4.7; Renderer declarado Forward+. | Su cercanía de versión ayuda a estudiar funciones actuales y a distinguir GPU de CPU. La ficha enumera trails, attractors, colisiones y subemitters; Compatibility no soporta trails ni colisión SDF. Sirve como mapa de capacidades, no como base que importar al pin 4.7.2/GLES3. | `master` → `3e08537616661a5883831628decab4c526260289` |
| [Brackeys Particle Controls](https://github.com/Brackeys/brackeys-particle-controls): README y código del plugin para vista del editor. | MIT; README dice «last tested with Godot 4.4.1». | Como herramienta opcional deja pausar/avanzar y revisar varios sistemas juntos mediante duplicados de editor; no añade runtime. No instalarlo para esta entrega: falta evidencia con 4.7.2. Si SM-00 muestra que la vista integrada no permite revisar dos perfiles sincronizados, probarlo aislado en editor antes de adoptarlo. | `main` → `26089746f71982f675602458e369e72034c89a81` |

## Consecuencia para el plan y prueba

Mantener SM-00 como escena aislada y mínima con dos `GPUParticles3D` propios, un `QuadMesh` y una máscara procedural creada en el repo. Fijar el ejecutable obtenido por `app/get-godot.sh` (Godot 4.7.2-stable) y abrir con el mismo Compatibility/OpenGL de `app/project.godot`; no inferir soporte porque el proyecto de muestra anuncie Godot 4.7. Capturar a 30/60/144 fps y a las dos cámaras: escape en ralentí, bomba ON/OFF, nube cruzando el avión y pausa/reinicio. Registrar errores de importación/shader, sorting y frame time. Si se prueba una escena externa como referencia, conservar sólo parámetros observables en notas y descartar su código/assets; sus resultados no reemplazan la aceptación en nuestro ejecutable.

La limitación pendiente es visual: las escenas de tutorial están compuestas para fuego, niebla o demostración en primer plano; ninguna evidencia inspeccionada establece qué radio, opacidad o tasa será legible para un modelo RC pequeño. Medirlo con el paisaje y cámara del simulador.

## Fuentes primarias

- [README y licencia CC0 de BasicParticleEffects](https://github.com/Bonkahe/BasicParticleEffects/tree/7589f716854ede38678ef9617d331909961a619b); [escena con el material de humo](https://github.com/Bonkahe/BasicParticleEffects/blob/7589f716854ede38678ef9617d331909961a619b/particle_effects_demo.tscn).
- [README de VFX in Godot](https://github.com/Brackeys/vfx-in-godot/tree/23b58f272b828b0a894ed7ef72fbf9033ee9d177); [configuración 4.6 Forward Plus](https://github.com/Brackeys/vfx-in-godot/blob/23b58f272b828b0a894ed7ef72fbf9033ee9d177/vfx/project.godot); [escena de partículas](https://github.com/Brackeys/vfx-in-godot/blob/23b58f272b828b0a894ed7ef72fbf9033ee9d177/vfx/scenes/fire.tscn).
- [Ficha oficial Godot Foundation Particles 3D Demo](https://store.godotengine.org/asset/godot-foundation/particles-3d-demo/).
- [README/licencia y versión probada del plugin Particle Controls](https://github.com/Brackeys/brackeys-particle-controls/tree/26089746f71982f675602458e369e72034c89a81).
- [Documentación de límites del renderer Compatibility en Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html).
