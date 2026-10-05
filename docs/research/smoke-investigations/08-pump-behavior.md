# 08. Comportamiento observable de bombas de humo RC

**Fecha:** 2026-10-05. **Pregunta:** ¿qué comportamiento de bomba conviene representar para un avión glow RC de 0.61 y cuál debe quedarse como efecto visual? **Fuentes:** manuales PowerBox y Sullivan. Ninguno confirma una instalación en el Ugly Stik concreto.

## Hechos de producto

La PowerBox SmokePump se controla desde un canal del receptor. Su manual separa distintas revisiones de firmware: versiones anteriores usan recorrido negativo para OFF y positivo para aumentar potencia; V4 declara `-100…0 % = apagada` y `+100 % = potencia completa`, con potencia intermedia proporcional. Su modo V05 para jets añade intervalos. El fabricante recomienda **20–30 % de caudal para modelos con motor de pistón**, y caudal completo para jets de alta velocidad. Advierte que demasiado aceite no se vaporiza, ensucia el modelo y puede producir humo después de cortar la bomba porque queda aceite en el escape. [PowerBox, manual de SmokePump, §§3.3–5](https://www.powerbox-systems.com/data/dokumente/00001024/EN/Downloads/Bedienungsanleitung/Operating%20instructions%20PowerBox%20Smokepump.pdf).

El manual Sullivan SkyWriter pide que el canal esté en OFF negativo durante al menos cinco segundos al iniciar; un canal conmutado solo ofrece caudal máximo, mientras que la salida proporcional permite ajustar velocidad y se puede mezclar con el acelerador. Señala que el caudal óptimo depende del motor, silenciador, temperatura ambiente y fluido. [Sullivan, instrucciones SkyWriter distribuidas por Minicars](https://www.minicars.se/internt/artiklar/internal_documents/38753_Skywriter_Instructions.pdf).

La evidencia apoya AUX con OFF explícito y caudal proporcional opcional. Los porcentajes dependen de bomba y mezcla, y no equivalen a mililitros. OFF inicial es un patrón de seguridad; cinco segundos corresponden al SkyWriter, no a todas las bombas.

## Qué emular

El requisito es una **estela blanca de acrobacia muy abundante**. Emular ON como nacimientos densos; al volver a OFF, cesan y las partículas existentes se disipan. AUX de tres posiciones o potenciómetro puede variar la tasa. El escape tenue queda ligado al motor. OFF inicial y desarme por desconexión representan el fail-safe sin simular la electrónica.

El plan vincula la bomba al permiso del motor. Los manuales muestran control AUX y Sullivan permite mezclar con acelerador, pero no definen un enclavamiento universal por RPM. Para el glow del juego, inhibir con motor detenido es política de producto; si un modo de planeo admite humo eléctrico, decide la configuración del avión.

El exceso real puede continuar humeando después del corte por aceite remanente, pero no conviene modelarlo como fuga o fallo en la primera entrega. Al cruzar a OFF o perder permiso, el objetivo y `flow` efectivo pasan inmediatamente a cero; no nacen más partículas densas y la cola visible es solo el humo ya depositado en el espacio. Aplicar una rampa descendente solo cuando se reduce un caudal todavía positivo (por ejemplo de 100 % a 50 %), no después de OFF. Un breve retardo visual al subir puede suavizar la animación, pero la constante `0.18 s` no proviene de los fabricantes y debe permanecer como estimación de jugabilidad. El smoke residual real después de OFF es otro fenómeno, originado por aceite en el escape; queda fuera de v1.

## Qué dejar visual

El proyecto carece de consumo, masa de aceite, temperatura de silenciador y compatibilidad validada con esta geometría .61. No mostrar ml/min, nivel de depósito ni calor. El nivel alto debe venir de mayor densidad/cobertura visual. Que ambos efectos compartan boquilla sigue siendo hipótesis hasta que el modelo confirme un inyector.

## Revisión del plan y prueba

Conservar `smoke_pump` como AUX independiente con valores OFF, proporcional y ON; mostrar el modo asignado y el estado OFF. Mantener una ruta de tasa máxima para cumplir la petición de humo abundante, pero marcar tamaño, opacidad, rampas y duración como `estimated`. No inferir visibilidad a partir de las tasas comerciales de una bomba para otro motor.

Prueba de estado: AUX ON y motor permitido; verificar rampa de entrada; pasar a OFF y comprobar `flow = 0` y tasa de nacimiento cero en la misma transición; repetir al retirar permiso de motor y desconectar radio. Prueba visual: OFF → ON → 50 % → 100 % → OFF, manteniendo otra toma hasta que la cola emitida se disipe. Repetir con motor apagado y sin accesorio instalado para confirmar que la regla elegida pertenece a la configuración del avión. Una toma comparativa con el motor al ralentí distingue el escape tenue de la bomba densa.

**Decisión:** representar entrada, rearme, proporcionalidad opcional y persistencia del humo ya emitido; reservar fluido, temperatura y residuo físico para después de contar con datos específicos del avión. **Incertidumbre:** no se encontró evidencia de una bomba real montada en el Ugly Stik .61 concreto ni un caudal calibrado para ese silenciador.
