"""
Export map for the r2 game delivery (OpenRC Simulator): CAD part -> exported object -> crash section.

Source master: Turbo Timber Evolution parametric CAD.
  - exterior solids from the v15 BREP cache (solid foam shells, same outer skin as v16/v17)
  - markings (decals) from the v17 cache: they are 0.35 mm skins there (v15 decals are solids through the fuselage)
  - rotor bell and backplate from v17 (10-size motor, corrected backplate step)
All parts are in the CAD "sidecar" frame: mm, X aft, Y right wing, Z up, origin at the wing-root leading edge
at thrust-axis height (D0).

A part that straddles a section boundary is cut there (never welded across sections). The only boundary that
cuts markings is the cowl joint at photo x = 85 mm (sidecar x = -157 mm).
"""
X_COWL_CUT = -157.0          # sidecar mm: cowl / fuselage joint (photo frame x = 85 mm)

SECTIONS = ("core", "wing_left", "wing_right", "wing_center", "horizontal_tail", "vertical_tail", "engine",
            "propeller", "gear", "canopy")

# object: (section, [(cache, part, cut)], description). cut: None, "fwd" (x < X_COWL_CUT) or "aft" (x > X_COWL_CUT)
V15, V17 = "v15", "v17"
OBJECTS = {
    "fuselage_core": ("core", [(V15, "fuselaje_blanco", "aft"), (V15, "fuselaje_panza_roja", "aft"),
                               (V17, "franjas_negras", "aft"), (V17, "franja_blanca_cola", None), (V17, "franja_negra_cola", None),
                               (V17, "panel_nariz", "aft"), (V17, "escotilla_panel_nariz", None), (V17, "filete_nariz", "aft"),
                               (V15, "placas_escape", "aft"),
                               (V15, "soporte_tren_der", None), (V15, "soporte_tren_izq", None), (V15, "soporte_rueda_cola", None),
                               (V15, "base_baliza", None), (V15, "lente_baliza", None)],
                      "fuselage foam shell (white top, red belly), stripes, nose panel aft of the cowl joint, gear brackets, beacon"),
    "wing_left_fixed": ("wing_left", [(V15, "ala_izq", None), (V15, "puntera_izq", None), (V17, "barras_ala_izq", None),
                                      (V17, "extrados_rojo_izq", None), (V17, "extrados_negro_izq", None), (V17, "intrados_gris_izq", None),
                                      (V15, "soportes_slat_izq", None), (V15, "tapa_servo_aleron_izq", None),
                                      (V15, "tapa_servo_flap_izq", None), (V15, "luz_nav_izq", None)],
                        "left fixed half-wing with tip, markings, servo covers, slat brackets and red nav lens"),
    "wing_right_fixed": ("wing_right", [(V15, "ala_der", None), (V15, "puntera_der", None), (V17, "barras_ala_der", None),
                                        (V17, "extrados_rojo_der", None), (V17, "extrados_negro_der", None), (V17, "intrados_gris_der", None),
                                        (V15, "soportes_slat_der", None), (V15, "tapa_servo_aleron_der", None),
                                        (V15, "tapa_servo_flap_der", None), (V15, "luz_nav_der", None)],
                         "right fixed half-wing with tip, markings, servo covers, slat brackets and green nav lens"),
    "aileron_left": ("wing_left", [(V15, "aleron_izq", None), (V15, "cuerno_aleron_izq", None)], "left aileron + horn"),
    "aileron_right": ("wing_right", [(V15, "aleron_der", None), (V15, "cuerno_aleron_der", None)], "right aileron + horn"),
    "flap_left": ("wing_left", [(V15, "flap_izq", None), (V15, "cuerno_flap_izq", None)], "left flap + horn"),
    "flap_right": ("wing_right", [(V15, "flap_der", None), (V15, "cuerno_flap_der", None)], "right flap + horn"),
    "stabilizer_fixed": ("horizontal_tail", [(V15, "estabilizador", None), (V17, "estab_superior_rojo", None),
                                             (V17, "estab_superior_negro", None)], "fixed horizontal stabilizer + top markings"),
    "elevator": ("horizontal_tail", [(V15, "timon_profundidad", None), (V15, "union_elevador", None),
                                     (V17, "elevador_superior_rojo", None), (V17, "elevador_superior_negro", None),
                                     (V15, "cuerno_elevador", None)], "one-piece elevator (both halves + torsion rod), markings, horn"),
    "fin_fixed": ("vertical_tail", [(V15, "deriva", None), (V17, "deriva_franja_roja", None), (V17, "deriva_franjas_negras", None),
                                    (V15, "aleta_dorsal", None)], "fixed fin, dorsal fin and fin markings"),
    "rudder": ("vertical_tail", [(V15, "timon_direccion", None), (V17, "timon_franja_roja", None),
                                 (V17, "timon_franjas_negras", None), (V15, "cuerno_timon", None)], "rudder + markings + horn"),
    "cowl": ("engine", [(V15, "capota", "fwd"), (V17, "panel_nariz", "fwd"), (V17, "filete_nariz", "fwd"),
                        (V17, "franjas_negras", "fwd"), (V15, "placas_escape", "fwd"), (V15, "escapes", None)],
             "plastic cowl with nose panel, red fillet, stripe ends, exhaust plates and dummy exhausts"),
    "canopy_glass": ("canopy", [(V17, "parabrisas", None), (V17, "escotilla_parabrisas", None), (V17, "ventanas", None)],
                     "windshield and side windows (one glazing assembly)"),
    "propeller_rotor": ("propeller", [(V17, "helice", None), (V17, "spinner", None), (V17, "contraplaca", None),
                                      (V17, "campana_motor", None)], "rotating: 3 blades, spinner, backplate, outrunner bell (10-size)"),
    "gear_left_leg": ("gear", [(V15, "pata_izq", None), (V15, "collarin_izq", None), (V15, "perno_eje_izq", None), (V15, "eslabon_izq", None)],
                      "left leg + axle bolt + spacer + wire link"),
    "gear_right_leg": ("gear", [(V15, "pata_der", None), (V15, "collarin_der", None), (V15, "perno_eje_der", None), (V15, "eslabon_der", None)],
                       "right leg + axle bolt + spacer + wire link"),
    "wheel_left": ("gear", [(V15, "neumatico_izq", None), (V15, "buje_izq", None), (V15, "arandela_izq", None), (V15, "tuerca_izq", None)],
                   "left tire, hub, washer, nut"),
    "wheel_right": ("gear", [(V15, "neumatico_der", None), (V15, "buje_der", None), (V15, "arandela_der", None), (V15, "tuerca_der", None)],
                    "right tire, hub, washer, nut"),
    "tailwheel_fork": ("gear", [(V15, "alambre_rueda_cola", None)], "steerable tailwheel wire (coaxial with the rudder hinge)"),
    "tailwheel": ("gear", [(V15, "rueda_cola", None), (V15, "buje_cola", None)], "tailwheel tire + hub"),
    "gear_cables": ("gear", [], "cosmetic low-poly cables and springs regenerated in Blender (rest pose only)"),
}
# pivots: openrc_section of each moving pivot (root and thrust_frame stay untagged)
PIVOT_SECTION = {
    "aileron_left_hinge": "wing_left", "aileron_right_hinge": "wing_right", "flap_left_hinge": "wing_left",
    "flap_right_hinge": "wing_right", "elevator_hinge": "horizontal_tail", "rudder_hinge": "vertical_tail",
    "propeller_spin": "propeller", "gear_left_suspension": "gear", "wheel_left_axle": "gear",
    "gear_right_suspension": "gear", "wheel_right_axle": "gear", "tailwheel_steer": "gear", "tailwheel_axle": "gear",
}
EXCLUDED = {
    # hidden interior of the v16/v17 master (EPO structure and electronics): adds nothing to a flight view
    "escotilla": "v17 battery hatch: the game uses the closed v15 fuselage shell (same outer skin, no hatch seam)",
    "interno_*": "hidden interior (battery, ESC, receiver, servos, trays, plates, cables): masses stay data, not geometry",
    "bancada_motor": "hidden inside the cowl", "soporte_motor": "hidden inside the cowl", "estator_motor": "hidden inside the bell",
    "bobinado_motor": "hidden inside the bell", "eje_motor": "hidden shaft", "tornillos_motor": "hidden hardware",
    "tuerca": "prop nut inside the spinner", "tornillos_spinner": "tiny hardware", "tornillos_capota": "tiny hardware",
    "tornillos_placa_escape": "tiny hardware", "tornillos_rueda_cola": "tiny hardware", "tornillos_ala": "tiny hardware",
    "tornillos_tren_der": "tiny hardware", "tornillos_tren_izq": "tiny hardware", "tornillos_servos_cola": "hidden hardware",
    "brazo_servo_*": "servo arms (tiny / hidden)", "servo_aleron_*": "hidden wing servo", "servo_flap_*": "hidden wing servo",
    "clevis_*": "tiny pushrod clevis (follows the pushrod, which the simulator does not model)",
    "pasadores_bisagra_*": "hidden hinge pins (knuckles stay with their parts)", "pasador_tren_*": "hidden gear hinge pin",
    "tubo_union_*": "hidden carbon joiner tubes", "espigas_ala": "hidden wing dowels", "conector_ala_*": "hidden wing connector",
    "imanes_*": "hidden hatch magnets", "guias_varillas": "tiny pushrod exits", "buje_torsion_elevador": "hidden bushing",
    "ojal_*": "tiny brass eyelet", "cable_der": "replaced by low-poly gear_cables", "cable_izq": "replaced by low-poly gear_cables",
    "resorte_der": "replaced by low-poly gear_cables (765k-triangle CAD spring)", "resorte_izq": "replaced by low-poly gear_cables",
    "led_baliza": "LED chip inside the beacon lens", "led_nav_*": "LED chip inside the nav lens", "led_estrobo_*": "LED chip inside the lens",
    "reflector_luz_*": "reflector inside the nav lens",
}
# consolidated GLB palette: CAD material -> exported material (the ten r1 materials)
PALETTE = {
    "blanco": "white", "plastico": "white", "rojo": "red", "negro": "black", "nylon_negro": "black",
    "spinner_negro": "black", "gris_claro": "light_grey", "gris_oscuro": "dark_grey", "gris": "dark_grey",
    "cromo": "metal", "metal": "metal", "aluminio": "metal", "laton": "metal", "dorado": "metal",
    "vidrio": "glass", "espuma": "foam", "led_rojo": "light_red", "led_verde": "light_green", "lente_roja": "light_red",
}
# overrides: merge small parts into a material already present on their mesh (fewer surfaces)
MATERIAL_OVERRIDE = {
    "cuerno_aleron_der": "white", "cuerno_aleron_izq": "white", "cuerno_flap_der": "white", "cuerno_flap_izq": "white",
    "cuerno_elevador": "white", "cuerno_timon": "white", "union_elevador": "white",
    "luz_nav_izq": "light_red", "luz_nav_der": "light_green",                 # pilot-left red, pilot-right green
    "soportes_slat_izq": "dark_grey", "soportes_slat_der": "dark_grey",
    "tapa_servo_aleron_izq": "dark_grey", "tapa_servo_aleron_der": "dark_grey",
    "tapa_servo_flap_izq": "dark_grey", "tapa_servo_flap_der": "dark_grey",
    "soporte_tren_der": "white", "soporte_tren_izq": "white", "soporte_rueda_cola": "white", "base_baliza": "black",
    "collarin_der": "metal", "collarin_izq": "metal", "buje_der": "light_grey", "buje_izq": "light_grey", "buje_cola": "light_grey",
    "arandela_der": "light_grey", "arandela_izq": "light_grey", "tuerca_der": "light_grey", "tuerca_izq": "light_grey",
    "placas_escape": "white", "contraplaca": "metal",
}
# overlapping markings: the lower priority loses the overlap (subtracted), as in r1
PRIORITY = {"barras_ala": 5, "negro": 4, "negras": 4, "negra": 4, "rojo": 3, "roja": 3, "gris": 2, "blanca": 1, "panel": 4, "filete": 3}
DECALS = ["franjas_negras", "franja_blanca_cola", "franja_negra_cola", "panel_nariz", "escotilla_panel_nariz", "filete_nariz",
          "barras_ala_der", "barras_ala_izq", "extrados_rojo_der", "extrados_rojo_izq", "extrados_negro_der",
          "extrados_negro_izq", "intrados_gris_der", "intrados_gris_izq", "estab_superior_rojo", "estab_superior_negro",
          "elevador_superior_rojo", "elevador_superior_negro", "deriva_franja_roja", "deriva_franjas_negras",
          "timon_franja_roja", "timon_franjas_negras"]
def priority(n):
    return max([v for k, v in PRIORITY.items() if k in n] or [0])
# substrate of each marking (for removing the hidden underside of the 0.35 mm decal skin)
SUBSTRATE = {
    "fuselage_core": ["fuselaje_blanco", "fuselaje_panza_roja"], "cowl": ["capota"],
    "wing_left_fixed": ["ala_izq", "puntera_izq"], "wing_right_fixed": ["ala_der", "puntera_der"],
    "stabilizer_fixed": ["estabilizador"], "elevator": ["timon_profundidad"], "fin_fixed": ["deriva", "aleta_dorsal"],
    "rudder": ["timon_direccion"],
}
# neighbours checked by the clearance sweep (moving object -> fixed objects it could touch)
NEIGHBOURS = {
    "aileron_left": ["wing_left_fixed", "flap_left"], "aileron_right": ["wing_right_fixed", "flap_right"],
    "flap_left": ["wing_left_fixed", "aileron_left", "fuselage_core"], "flap_right": ["wing_right_fixed", "aileron_right", "fuselage_core"],
    "elevator": ["stabilizer_fixed", "fuselage_core", "fin_fixed", "rudder"],
    "rudder": ["fin_fixed", "stabilizer_fixed", "fuselage_core", "elevator"],
    "tailwheel_fork": ["fuselage_core", "rudder"], "gear_left_leg": ["fuselage_core"], "gear_right_leg": ["fuselage_core"],
}

# r2 base-colour painting (delivery spec: prefer base colour over stacked decal shells). On the wing and tail the
# master markings are offset-skin solids that enclose their substrate; the substrate is split by them in CAD
# (highest priority first) and each piece keeps the marking colour. No marking sheet is exported for these.
PAINT = {
    "wing_left_fixed": (["ala_izq"], ["barras_ala_izq", "extrados_negro_izq", "extrados_rojo_izq", "intrados_gris_izq"]),
    "wing_right_fixed": (["ala_der"], ["barras_ala_der", "extrados_negro_der", "extrados_rojo_der", "intrados_gris_der"]),
    "stabilizer_fixed": (["estabilizador"], ["estab_superior_negro", "estab_superior_rojo"]),
    "elevator": (["timon_profundidad"], ["elevador_superior_negro", "elevador_superior_rojo"]),
    "fin_fixed": (["deriva", "aleta_dorsal"], ["deriva_franjas_negras", "deriva_franja_roja"]),
    "rudder": (["timon_direccion"], ["timon_franjas_negras", "timon_franja_roja"]),
}
PAINTED_DECALS = [d for _, ds in PAINT.values() for d in ds]
