# 09. Advección del humo, viento y herramientas de Godot

**Fecha:** 2026-10-05. **Pregunta:** ¿cómo mover la estela ya emitida cuando exista viento, y qué coste añade frente a simular fluidos? **Evidencia:** documentación Godot 4.7, auditoría local del sistema de viento y lectura comparativa de FlightGear/SimGear y CRRCSim. No se implementó un emisor ni se ejecutó un benchmark.

## Estado real del repositorio

La auditoría [viento en Godot](../wind-godot-integration.md) confirma que la sesión aún pasa `[0,0,0]` a la física. [shader_clock.gd](../../../app/render/shader_clock.gd) registra `sim_clock` y `wind_vec`, pero el viento sigue a cero. El reloj de simulación se envuelve a 1024 s y los shaders del proyecto no deben leer `TIME`. Por tanto, v1 queda en calma; la deriva de árboles/nubes no sustituye al viento físico.

## Qué aporta Godot

Con `local_coords = false`, `GPUParticles3D` simula movimiento en ejes globales aunque el avión rote. `Visibility AABB` puede ocultar partículas fuera de su caja, por lo que esta debe cubrir vida y velocidad de humo. [Godot 4.7: propiedades de partículas 3D](https://docs.godotengine.org/en/4.7/tutorials/3d/particles/properties.html).

El shader de partículas GPU conserva datos y recibe `DELTA`, `VELOCITY` y `TRANSFORM`, permitiendo integrar una velocidad uniforme en partículas existentes. `TIME` no se detiene con la pausa; usar el global `sim_clock` para variación visual reproducible. [Godot 4.7: particle shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/particle_shader.html). El servicio meteorológico compartido debe convertir viento NED al marco render mediante `Frames`; no duplicarlo restando velocidad del avión.

## Modelo suficiente y alternativas

Para la estela basta un modelo Lagrangiano: cada partícula conserva posición mundial y recibe viento más deriva residual pequeña. Con viento constante, una nube de edad `t` debe desplazarse `wind × t`. Si el viento cambia, procesar también partículas antiguas; asignarlo solo al nacer congelaría el viento anterior. Una futura variación espacial requiere muestreo por posición y tiempo.

Un solver CFD/volumétrico resolvería el fluido y remolinos, pero la necesidad actual es una estela legible en un espacio grande; añadiría rejilla, pasos de simulación y coste de GPU sin un requisito que lo justifique. Empezar con partículas y ruido determinista leve. Wake/turbulencia merece un prototipo aparte si pasa a ser objetivo.

FlightGear/SimGear ofrece un contraste técnico útil. Su cabecera declara que el vector de viento de partículas usa un marco `Z-up, Y-north` y magnitud en m/s; el código conecta el flag `wind` del sistema de partículas, pero contiene el comentario `THIS WIND COMPUTATION DOESN'T SEEM TO AFFECT PARTICLES`. Ese aviso impide tratar el módulo legado como una implementación correcta para copiar: sí respalda que el marco y la unidad deben declararse, no prueba que su advección funcione. El repositorio SimGear publica licencia LGPL; el plan no necesita copiar código. [cabecera de partículas de SimGear](https://github.com/FlightGear/simgear/blob/next/simgear/scene/model/particles.hxx), [implementación C++](https://github.com/FlightGear/simgear/blob/next/simgear/scene/model/particles.cxx), [licencia/repositorio](https://github.com/FlightGear/simgear).

CRRCSim es pertinente como simulador de aviones RC: el árbol de código consultado lista `src/mod_windfield/windfield.cpp` y `windfield.h`, con actividad registrada en 2013. No inspeccioné la implementación de esos archivos, no verifiqué una ruta de advección para humo y no los uso como soporte de comportamiento. SourceForge indica GPL-2.0 para el proyecto; cualquier reutilización exigiría revisión de licencia y compatibilidad, así que la recomendación aquí es no portar código. [árbol del módulo](https://sourceforge.net/p/crrcsim/code/ci/default/tree/src/mod_windfield/), [licencia del proyecto](https://sourceforge.net/projects/crrcsim/).

## Cambio y prueba que conviene añadir

En SM-00, comprobar en Compatibility que `local_coords=false` fija la nube al mundo y el AABB la conserva en loopings y vistas piloto/inspección. Más adelante, probar viento constante y comparar desplazamiento tras 1 s con `wind × 1 s`; repetir cero, frente, cola y cruzado. Pausa detiene edad, advección y reloj; reanudar no salta. Probar con emisión OFF para confirmar que la nube vieja también deriva. Una cámara móvil de prueba puede ampliar cobertura del AABB.

**Decisión:** partículas mundiales; v1 en calma; advección uniforme determinista cuando exista el viento físico; sin CFD ni deriva atmosférica paralela. **Pendiente:** el contrato futuro de `wind_vec` debe fijar marco, unidades y frecuencia de actualización antes de activar el comportamiento, y el ensayo con partículas manuales determinará cómo alinear sus pasos con el reloj físico.
