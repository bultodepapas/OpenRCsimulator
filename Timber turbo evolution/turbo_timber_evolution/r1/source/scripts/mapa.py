"""Mapa de exportacion de la version de juego (OpenRC Simulator): pieza CAD -> rol exportado."""
ROLES = {
    # rol: (piezas CAD, descripcion)
    "airframe": (["fuselaje_blanco", "fuselaje_panza_roja", "franjas_negras", "franja_blanca_cola", "franja_negra_cola",
                  "panel_nariz", "filete_nariz", "parabrisas", "ventanas", "capota", "placas_escape", "escapes", "baliza",
                  "ala_der", "ala_izq", "puntera_der", "puntera_izq", "barras_ala_der", "barras_ala_izq",
                  "soportes_slat_der", "soportes_slat_izq", "extrados_rojo_der", "extrados_rojo_izq",
                  "extrados_negro_der", "extrados_negro_izq", "intrados_gris_der", "intrados_gris_izq",
                  "tapa_servo_aleron_der", "tapa_servo_aleron_izq", "tapa_servo_flap_der", "tapa_servo_flap_izq",
                  "luz_nav_der", "luz_nav_izq", "estabilizador", "estab_superior_rojo", "estab_superior_negro",
                  "deriva", "deriva_franja_roja", "deriva_franjas_negras", "aleta_dorsal",
                  "soporte_tren_der", "soporte_tren_izq", "soporte_rueda_cola"],
                 "fixed structure, markings, glazing, cowl, exhaust, gear brackets"),
    "aileron_left":  (["aleron_izq", "cuerno_aleron_izq"], "left aileron + horn"),
    "aileron_right": (["aleron_der", "cuerno_aleron_der"], "right aileron + horn"),
    "flap_left":     (["flap_izq", "cuerno_flap_izq"], "left flap + horn"),
    "flap_right":    (["flap_der", "cuerno_flap_der"], "right flap + horn"),
    "elevator":      (["timon_profundidad", "union_elevador", "elevador_superior_rojo", "elevador_superior_negro",
                       "cuerno_elevador"], "one-piece elevator (both halves + torsion rod), markings, horn"),
    "rudder":        (["timon_direccion", "timon_franja_roja", "timon_franjas_negras", "cuerno_timon"], "rudder + markings + horn"),
    "propeller_rotor": (["helice", "spinner", "contraplaca", "campana_motor"], "rotating: 3 blades, spinner, backplate, outrunner bell"),
    "gear_left_leg":  (["pata_izq", "collarin_izq", "perno_eje_izq", "eslabon_izq"], "left leg + axle bolt + spacer + wire link"),
    "gear_right_leg": (["pata_der", "collarin_der", "perno_eje_der", "eslabon_der"], "right leg + axle bolt + spacer + wire link"),
    "wheel_left":     (["neumatico_izq", "buje_izq", "arandela_izq", "tuerca_izq"], "left tire, hub, washer, nut"),
    "wheel_right":    (["neumatico_der", "buje_der", "arandela_der", "tuerca_der"], "right tire, hub, washer, nut"),
    "tailwheel_fork": (["alambre_rueda_cola"], "steerable tailwheel wire (coaxial with rudder hinge)"),
    "tailwheel":      (["rueda_cola", "buje_cola"], "tailwheel tire + hub"),
    "gear_cables":    ([], "cosmetic low-poly cables/springs regenerated in Blender (rest pose only)"),
}
EXCLUIDAS = {
    "interno_bateria": "hidden internal component (CG data kept in metadata)",
    "interno_variador": "hidden internal component", "interno_receptor": "hidden internal component",
    "interno_servos_cola": "hidden internal component", "bancada_motor": "hidden inside cowl",
    "soporte_motor": "hidden inside cowl", "eje_motor": "hidden (shaft inside spinner/bell)",
    "tuerca": "hidden prop nut inside spinner", "tornillos_spinner": "tiny hardware",
    "tornillos_capota": "tiny hardware", "tornillos_placa_escape": "tiny hardware",
    "tornillos_rueda_cola": "tiny hardware", "tornillos_ala": "tiny hardware",
    "brazo_servo_aleron_der": "servo arm (moves with servo; tiny)", "brazo_servo_aleron_izq": "servo arm",
    "brazo_servo_flap_der": "servo arm", "brazo_servo_flap_izq": "servo arm",
    "brazo_servo_elevador": "hidden servo arm", "brazo_servo_timon": "hidden servo arm",
    "guias_varillas": "tiny pushrod exits", "buje_torsion_elevador": "hidden bushing",
    "pasador_tren_der": "hidden hinge pin", "pasador_tren_izq": "hidden hinge pin",
    "ojal_der": "tiny brass eyelet", "ojal_izq": "tiny brass eyelet",
    "cable_der": "replaced by low-poly gear_cables", "cable_izq": "replaced by low-poly gear_cables",
    "resorte_der": "replaced by low-poly gear_cables (765k-triangle CAD spring)", "resorte_izq": "replaced by low-poly gear_cables",
}
# paleta consolidada para el GLB: material CAD -> material exportado
PALETA = {
    "blanco": "white", "plastico": "white", "rojo": "red", "negro": "black", "nylon_negro": "black",
    "spinner_negro": "black", "gris_claro": "light_grey", "gris_oscuro": "dark_grey", "gris": "dark_grey",
    "cromo": "metal", "metal": "metal", "aluminio": "metal", "laton": "metal", "dorado": "metal",
    "vidrio": "glass", "espuma": "foam", "led_rojo": "light_red", "led_verde": "light_green",
}
# excepciones: piezas cuyo material se fusiona para ahorrar superficies
MATERIAL_FORZADO = {n: "white" for n in ("cuerno_aleron_der", "cuerno_aleron_izq", "cuerno_flap_der",
                                         "cuerno_flap_izq", "cuerno_elevador", "cuerno_timon")}
# prioridad de calcomanias que se superponen (la mayor queda encima; a la menor se le resta)
PRIORIDAD_CALCO = {"barras_ala": 5, "negro": 4, "negras": 4, "negra": 4, "rojo": 3, "roja": 3, "gris": 2, "blanca": 1, "panel": 4, "filete": 3}
CALCOS = ["franjas_negras", "franja_blanca_cola", "franja_negra_cola", "panel_nariz", "filete_nariz",
          "barras_ala_der", "barras_ala_izq", "extrados_rojo_der", "extrados_rojo_izq", "extrados_negro_der",
          "extrados_negro_izq", "intrados_gris_der", "intrados_gris_izq", "estab_superior_rojo", "estab_superior_negro",
          "elevador_superior_rojo", "elevador_superior_negro", "deriva_franja_roja", "deriva_franjas_negras",
          "timon_franja_roja", "timon_franjas_negras"]
def prioridad(n):
    return max([v for k, v in PRIORIDAD_CALCO.items() if k in n] or [0])
