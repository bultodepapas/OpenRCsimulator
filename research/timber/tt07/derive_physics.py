#!/usr/bin/env python3
"""TT-07: provenance-complete, provisional Timber configuration. Standard library only."""
import argparse
import copy
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
IDENTITY_DIR = ROOT / "research/aircraft-standardization"
if str(IDENTITY_DIR) not in sys.path:
    sys.path.insert(0, str(IDENTITY_DIR))
from physical_identity import validate_physical_identity  # noqa: E402

HERE = Path(__file__).resolve().parent
GEOMETRY = ROOT / "assets/aircraft/turbo-lumber-evolution/geometry.json"
OUTPUT = ROOT / "app/data/aircraft/turbo_lumber_evolution.json"
# BAT-13: the same airframe and inventory with the finite pack_ecm battery (catalog battery mode "pack").
PACK_OUTPUT = ROOT / "app/data/aircraft/turbo_lumber_evolution_4s_pack.json"
PACK_ID = "lipo-4s1p-3200-30c-class"
PACK_FILE = ROOT / "app/data/batteries/packs" / (PACK_ID + ".json")
PACK_SOURCE = "research/timber/tt07/derive_physics.py BAT-13 pack variant"
SOURCE = "research/timber/tt07/derive_physics.py"
BELLY_PROBE_IDS_BY_STATION = {
    -0.22: "probe_belly_nose",
    -0.10: "probe_belly_forward_fuselage",
    0.02: "probe_belly_wing_front",
    0.14: "probe_belly_wing_center",
    0.26: "probe_belly_wing_aft",
    0.38: "probe_belly_cabin_aft",
    0.50: "probe_belly_tail_forward",
    0.62: "probe_belly_tail_center",
    0.74: "probe_belly_tail_end",
}


def q(value, unit, kind="derived", source=""):
    return dict(value=value, unit=unit, kind=kind, source=source or SOURCE + ": estimated geometry/textbook derivation; not flight identified")


def slope(ar, kappa=0.9):
    return 2 * math.pi * kappa * ar / (2 + math.sqrt(4 + ar * ar))


def flap_tau(fraction):
    theta = math.acos(2 * fraction - 1)
    return 1 - (theta - math.sin(theta)) / math.pi


def throw_degrees(displacement_mm, radius):
    if radius <= 0 or not 0 <= displacement_mm / 1000 <= 2 * radius:
        raise ValueError("Trailing-edge displacement outside the hinge circle")
    return math.degrees(2 * math.asin(displacement_mm / 2000 / radius))


def _sequential_float_sum(values):
    # Python 3.12 changed sum(float) to compensated accumulation. Keep the
    # generated result rounding stable with explicit left-to-right accumulation.
    total = 0.0
    for value in values:
        total += value
    return total


def tensor(items, cg):
    j = [0.0] * 6
    for it in items:
        m, p, s = it["mass"]["value"], it["position"]["value"], it["size"]["value"]
        x, y, z = -(p[0] - cg[0]), p[1] - cg[1], -(p[2] - cg[2])
        j[0] += m * (y*y + z*z + (s[1]**2 + s[2]**2)/12)
        j[1] += m * (x*x + z*z + (s[0]**2 + s[2]**2)/12)
        j[2] += m * (x*x + y*y + (s[0]**2 + s[1]**2)/12)
        j[3] -= m*x*y
        j[4] -= m*x*z
        j[5] -= m*y*z
    return j


def derive(inputs=None):
    i = copy.deepcopy(inputs if inputs is not None else json.loads((HERE / "inputs.json").read_text()))
    g = json.loads(GEOMETRY.read_text())
    v = lambda name: i["estimates"][name]["value"]
    eq = lambda name, unit: q(v(name), unit, "estimated", i["estimates"][name]["source"])
    gv = lambda section, name: g[section][name]["value"]
    b, s = g["manual"]["span_m"]["value"], gv("wing", "area")
    c, ar = s/b, b*b/s
    cg_x = g["manual"]["cg_aft_of_root_le_m"]["value"]
    items = []
    for it in i["inventory"]:
        p = list(it["position"])
        # A recorded discrepancy experiment moves only nose-mounted components.
        if it.get("nose_mounted"):
            p[0] += v("nose_station_offset")
        items.append(dict(id=it["id"], name=it["name"], mass=q(it["mass_kg"] * v("component_mass_scale"), "kg", "estimated", it["source"]),
                          position=q(p, "m", "estimated", it["source"] + "; D0 structural frame"),
                          size=q(it["size"], "m", "estimated", it["source"] + "; aligned box inertia envelope")))
    # CR-22b: the flight pack carries energy (crash smoke presentation only).
    for item in items:
        if item["name"] == "4S 3200 mAh battery":
            item["energy_source"] = "lipo"
    mass = g["manual"]["mass_flying_kg"]["value"]
    residue = mass - _sequential_float_sum(it["mass"]["value"] for it in items)
    if residue < 0.001:
        raise ValueError("Inventory leaves no positive balancing mass")
    xb = (mass*cg_x - _sequential_float_sum(it["mass"]["value"]*it["position"]["value"][0] for it in items))/residue
    if not -0.2835 <= xb <= 0.8331:
        raise ValueError("Virtual balancing station outside the airframe")
    items.append(dict(id="ballast_reference", name="virtual reference-build balancing mass", mass=q(residue,"kg", source=SOURCE+": residual of manual 2.190 kg minus estimated component inventory; NOT measured hardware"),
                      position=q([xb,0,0],"m",source=SOURCE+": residual moment needed for manual 60 mm CG; NOT measured ballast"),
                      size=q([0.04,0.04,0.04],"m","estimated","TT-07 virtual ballast envelope")))
    cg = [_sequential_float_sum(it["mass"]["value"]*it["position"]["value"][k] for it in items)/mass for k in range(3)]
    j = tensor(items,cg)
    sh, bh = gv("tail","area"), gv("tail","span")
    sv = gv("fin","area_above_fuselage")
    xarp = gv("wing","le_z") + 0.25*gv("wing","mac")
    root_station = g["wing"]["stations"][0]
    arp_up = (root_station[3] + 0.25*(root_station[4]-root_station[3])
              - root_station[0]*math.tan(math.radians(gv("wing","dihedral_deg"))))
    xh = xarp + gv("tail","tail_arm_quarter_chords")
    zh = gv("tail","y")
    hv = gv("fin","top_y") - gv("fin","root_y")
    zv = gv("fin","root_y") + 0.45*hv
    xv = gv("fin","le_z_at_root") + 0.25*gv("fin","root_chord") + 0.5*hv*math.tan(math.radians(gv("fin","le_sweep_deg")))
    aw = slope(ar,v("section_slope_factor"))
    ah_free = slope(bh*bh/sh)*v("tail_pressure_ratio")
    deps = 2*aw/(math.pi*ar)
    ah = ah_free*(1-deps)
    av = slope(v("fin_endplate_factor")*hv*hv/sv)*v("fin_pressure_ratio")
    tau_e = flap_tau(gv("tail","elevator_chord_aft_of_hinge_root")/gv("tail","root_chord"))*v("control_efficiency")
    tau_a = flap_tau(1-gv("wing","hinge_fraction"))*v("control_efficiency")
    tau_r = flap_tau(gv("fin","rudder_chord_aft_of_hinge")/gv("fin","root_chord"))*v("control_efficiency")
    ceh, cev = tau_e/(1-deps), tau_r/v("fin_pressure_ratio")
    iw = math.radians(gv("wing","incidence_deg"))-v("wing_zero_lift_angle")
    ih = (v("tail_incidence") - 2*aw*iw/(math.pi*ar))/(1-deps)
    cla = aw+ah*sh/s
    cl0 = aw*iw+ah*sh/s*ih
    clde = ah*sh/s*ceh
    lh, lv = xh-xarp, xv-xarp
    ain,aout = g["wing"]["aileron_x"]
    clda_each = aw*tau_a*gv("wing","chord")*(aout-ain)/s
    clda = -aw*tau_a*gv("wing","chord")*(aout*aout-ain*ain)/(2*s*b)
    cyb_v, cydr = -av*sv/s, av*sv/s*cev
    cm0 = v("wing_section_moment")-ah*sh/s*lh/c*ih
    cd0 = v("skin_drag_coefficient") + v("gear_drag_area")/s + v("excrescence_drag_area")/s
    k = 1/(math.pi*v("span_efficiency")*ar)
    vs = math.sqrt(2*mass*9.80665/(1.225*s*v("CL_max")))
    speed = 1.6*vs
    clref = mass*9.80665/(0.5*1.225*speed*speed*s)
    gamma = math.radians(gv("wing","dihedral_deg"))
    values = dict(CL0=cl0,CLa=cla,CLq=2*ah_free*sh/s*(xh-cg_x)/c,
        CLde=clde,CLda_each=clda_each,CD0=cd0,CL_minD=v("minimum_drag_lift"),k_induced=k,
        CDda_each=v("control_drag_aileron"),CDdr=v("control_drag_rudder"),CDde=v("control_drag_elevator"),
        CYb=cyb_v-v("body_side_slope"),CYp=2*cyb_v*(zv-cg[2])/b,CYr=-2*cyb_v*(xv-cg_x)/b,CYdr=cydr,
        Clb=-aw*gamma/4+cyb_v*(zv-cg[2])/b-v("high_wing_dihedral_effect"),
        Clp=-aw/6,Clr=clref/4-2*(xv-cg_x)*(zv-cg[2])/b**2*cyb_v,
        Clda_right=clda,Clda_left=-clda,Cldr=cydr*(zv-arp_up)/b,
        Cm0=cm0,Cma=-ah*sh/s*lh/c,Cmq=-2*ah_free*sh/s*((xh-cg_x)/c)**2,
        Cmde=-clde*lh/c,Cmda_each=-clda_each*(gv("wing","le_z")+0.4*c-xarp)/c,
        Cnb=av*sv/s*lv/b,Cnp=-clref/8,Cnr=2*((xv-cg_x)/b)**2*cyb_v-cd0/3,
        Cnda_right=-v("adverse_yaw_factor")*clref*clda,Cnda_left=v("adverse_yaw_factor")*clref*clda,Cndr=-cydr*lv/b)
    coefficients={name:q(val,"1" if name in ["CL0","CD0","CL_minD","k_induced","Cm0"] else "1/rad",source=SOURCE+": Helmbold finite wing/tails, thin-airfoil flap effectiveness, strip and tail-volume derivatives; see derivation.md") for name,val in values.items()}
    # The local strip adapter's uniform effectiveness reproduces the integrated roll derivative.
    effectiveness=abs(clda)*8/cla
    surfaces={"wing_aileron_effectiveness":q(effectiveness,"1"),"wing_section_cm_ac":eq("wing_section_moment","1"),
        "attached_limit":eq("attached_limit","deg"),"tail_local_limit":eq("tail_local_limit","deg"),"tail_stall_end":eq("tail_stall_end","deg"),
        "tail_CD0":eq("tail_CD0","1"),"tail_k":eq("tail_k","1"),"tail_CD90":q(1.11+0.018*ar,"1"),
        "horizontal":dict(area=g["tail"]["area"],position=q([xh,0,zh],"m"),lift_slope=q(ah,"1/rad"),control_effectiveness=q(ceh,"1"),incidence=q(ih,"rad"),downwash_gradient=q(deps,"1")),
        "vertical":dict(area=g["fin"]["area_above_fuselage"],position=q([xv,0,zv],"m"),lift_slope=q(av,"1/rad"),control_effectiveness=q(cev,"1"),incidence=q(0.0,"rad"))}
    # Static support shares from the actual tilted contact plane (not horizontal body geometry).
    contacts=g["landing_gear"]["contacts_neutral"]
    points={name:[p[2],p[0],p[1]] for name,p in contacts.items()}
    theta=math.atan2(points["tail"][2]-points["main_left"][2],points["tail"][0]-points["main_left"][0])
    horizontal=lambda p:p[0]*math.cos(theta)+p[2]*math.sin(theta)
    tail_share=(horizontal(cg)-horizontal(points["main_left"]))/(horizontal(points["tail"])-horizontal(points["main_left"]))
    shares={"main_left":(1-tail_share)/2,"main_right":(1-tail_share)/2,"tail":tail_share}
    ktot=mass*(v("heave_omega_dt")*240)**2
    gc=[]
    contact_sources=i["landing_gear_contact_identity"]
    if {record["source_name"] for record in contact_sources} != set(points):
        raise ValueError("TT-07 contact identity source does not match the authored gear contacts")
    for contact_source in contact_sources:
        name=contact_source["source_name"]
        p=points[name]
        stiffness=ktot*shares[name]
        gc.append(dict(id=contact_source["id"],
            name=name,position=q(p,"m","measured","TT-19 imported r2 wheel centre minus radius; D0 frame"),
            stiffness=q(stiffness,"N/m",source=SOURCE+": E1 heave omega*dt rule, split by three-point static load share; assumed compliance"),
            damping=q(2*v("gear_damping_ratio")*math.sqrt(stiffness*mass/3),"N·s/m"),
            max_compression=eq("gear_travel","m"),max_steering=q(-v("tail_steering") if name=="tail" else 0.0,"deg","estimated","TT-07 tailwheel opposite rudder angle for positive right taxi yaw; mains unsteered")))
    hub=gv("thrust","origin")
    propulsion=copy.deepcopy(i["propulsion"])
    propulsion["id"] = "propulsion_main"
    motor=propulsion["motor"]
    for field,estimate,unit in [("resistance_ohm","motor_resistance","ohm"),("no_load_current_a","motor_no_load_current","A")]:motor[field]=eq(estimate,unit)
    voltage=v("bus_voltage")
    propulsion["battery"]["voltage_v"]=eq("bus_voltage","V")
    motor["no_load_context"]=dict(voltage_v=eq("bus_voltage","V"),rpm=q((voltage-v("motor_resistance")*v("motor_no_load_current"))*800,"rpm"),temperature_c=eq("winding_temperature","°C"))
    prop=propulsion["propeller"]
    prop["rotating_inertia"]=eq("rotor_inertia","kg·m2")
    prop["thrust_angles"]=q([gv("thrust","downthrust_deg"),gv("thrust","right_thrust_deg")],"deg","measured","TT-02 imported thrust_frame; authored angles estimated, hardware not measured")
    prop["thrust_line_offset"]=q([hub[2]-cg[0],hub[0]-cg[1],hub[1]-cg[2]],"m",source=SOURCE+": imported propeller hub minus inventory CG, structural axes")
    for field,estimate in [("ct_table","ct_scale"),("cp_table","cp_scale")]:
        prop[field]["value"]=[[x,y*v(estimate)] for x,y in prop[field]["value"]]
        prop[field]["source"]+=f"; explicit estimated mismatch multiplier {v(estimate)}; saturation outside J endpoints, unmeasured static-to-tunnel bridge"
    landmarks=g["landmarks"]
    # R1's tip landmark selected a navigation lens, while r2's max-span cap selects an aft vertex.
    # Use a stable leading-skin sample for collision: outermost measured right-wing station, mirrored left.
    # This is 2.752 mm inboard of the r2 cap; it avoids a spurious 155 mm aft probe shift from landmark semantics.
    tip=g["wing"]["stations"][-1]  # [x_right, le_z, te_z, le_y, te_y]
    hull_probes = [
        ("probe_wing_left_tip", [tip[1],-tip[0],tip[3]]),
        ("probe_wing_right_tip", [tip[1],tip[0],tip[3]]),
    ]
    for key, identity in [("nose_spinner_tip", "probe_spinner_tip"),
                          ("tail_rudder_trailing_edge", "probe_tail_rudder_edge")]:
        p=landmarks[key]["measured"];hull_probes.append((identity,[p[2],p[0],p[1]]))
    hull_probes += [
        ("probe_stabilizer_left_tip", [gv("tail","te_z_centreline"),-bh/2,zh]),
        ("probe_stabilizer_right_tip", [gv("tail","te_z_centreline"),bh/2,zh]),
        ("probe_fin_top", [gv("fin","rudder_te_z"),0,gv("fin","top_y")]),
        ("probe_propeller_bottom", [-0.2515,0,-gv("thrust","propeller_radius")]),
    ]
    # Fuselage skin excludes wheels; retain several lower-envelope stations for belly strikes.
    sampled_belly_stations = [row[0] for row in g["fuselage"]["stations"][::max(1,len(g["fuselage"]["stations"])//8)]]
    if set(sampled_belly_stations) != set(BELLY_PROBE_IDS_BY_STATION):
        raise ValueError("TT-07 belly-probe identity source does not match the authored station set")
    hull_probes.extend(
        (BELLY_PROBE_IDS_BY_STATION[row[0]], [row[0],0,row[2]])
        for row in g["fuselage"]["stations"][::max(1,len(g["fuselage"]["stations"])//8)]
    )
    hull = [point for _, point in hull_probes]
    hull_ids = [identity for identity, _ in hull_probes]
    # CR-01d: one semantic name per hull point, in the order built above (crash presentation only).
    hull_names=["left_wing_tip","right_wing_tip","spinner","tail_end","left_stab_tip","right_stab_tip","fin_top","propeller"]
    hull_names+=["belly"]*(len(hull)-len(hull_names))
    model=dict(format="openrc-aircraft v2",physical_identity_version=1,id="turbo-lumber-evolution",
      description="EXPERIMENTAL TT-07: photograph-inspired r2 mesh (r2-d75ae605aa3a), B-reference 800 Kv/70 A/4S 3200 mAh/11x7.3 three-blade loadout. Estimated inventory, motor losses and borrowed two-blade propeller map. Wheels fixed, flaps up, slats absent, assists off; prescribed bus, no battery depletion. Not physical validation.",
      convention_id="openrc-le-frd-v1",capabilities=dict(controls="conventional",gear="fixed_taildragger",propulsion_layout="single_tractor",energy="fixed_voltage",damage="terminal_hull",flaps="not_simulated"),
      frames=dict(le_frame="D0: [x_aft,y_right,z_up] = [model Z,model X,model Y], metres",body="FRD about inventory CG"),
      reference=dict(wing_area=g["wing"]["area"],wing_span=g["manual"]["span_m"],mean_chord=q(c,"m"),aero_reference_point=q([xarp,0,arp_up],"m",source=SOURCE+": quarter chord at measured wing height, dihedral extrapolated to centreline D0"),planform="rectangular"),
      balance=dict(plan_cg=q(cg,"m",source=SOURCE+": manual longitudinal CG, inventory-derived vertical CG"),firewall=q([-0.19,0,0],"m","estimated","TT-07 assumed motor mount station retained inside r2 cowl"),configuration="virtual-balanced-reference-v1",cg_tolerance=q(0.001,"m","estimated","TT-07 reference build tolerance")),
      inventory=items,start=dict(level_speed=q(speed,"m/s",source=SOURCE+": 1.6 times clean 1-g stall from manual mass, measured model area and estimated CL_max")),
      controls=dict(surface_ids={"aileron_left":"surface_aileron_left","aileron_right":"surface_aileron_right","elevator":"surface_elevator","rudder":"surface_rudder"},max_throw={key:q(throw_degrees(g["controls"]["manual_mm"][key]["high"],g["controls"][key]["r"]["value"]),"deg",source=SOURCE+": 2 asin(manual displacement/(2 measured hinge radius)); TT-02 assumed measurement station") for key in ["aileron","elevator","rudder"]},servo_full_throw_time=eq("servo_full_throw_time","s")),
      aero=dict(source=SOURCE+": geometry/textbook estimate, no identified Timber aerodynamics",conventions=i["conventions"],coefficients=coefficients,surfaces=surfaces,reference_coefficients=dict(CLadot=q(2*ah_free*sh/s*(xh-cg_x)/c*deps,"1/rad")),
          envelope=dict(CL_max=eq("CL_max","1"),CL_min=eq("CL_min","1"),stall_blend_width=eq("stall_blend_width","deg"),CD90=q(1.11+0.018*ar,"1"),sideslip_blend=q([15,25],"deg","estimated","TT-07 linear-to-sine sideslip blend"))),
      propulsion=propulsion,landing_gear=dict(contacts=gc,rolling_resistance=eq("rolling_resistance","1"),side_friction=eq("side_friction","1"),peak_slip_angle=eq("peak_slip_angle","deg"),breakaway_factor=eq("breakaway_factor","1")),
      crash_hull=q(hull,"m",source=SOURCE+": TT-19 outermost measured wing leading-skin station mirrored left/right (not max-span cap or nav lens), imported nose/tail extrema, tail tips, fuselage skin bottoms and rotor lower envelope; wheels excluded"),
      crash_hull_ids=hull_ids,
      crash_hull_components=hull_names,
      plausibility=dict(mass_range=q([1.86,2.4],"kg","estimated","Manual 1.860 kg empty/2.190 kg with pack; widened upper reference-build limit"),inertia_reference=q(j[:3],"kg·m2",source=SOURCE+": same inventory box estimate; self-reference is no independent plausibility evidence")))
    validate_physical_identity(model)
    return model,dict(mass=mass,cg=cg,inertia=j,stall_speed=vs,start_speed=speed,static_margin=(xarp-values["Cma"]/cla*c-cg_x)/c,CD0=cd0,tail_load_share=tail_share,virtual_mass=residue,virtual_station=xb)


def derive_pack_variant(model):
    """BAT-13: replace only the energy model; airframe, inventory and identity stay those of TT-07."""
    import hashlib
    pack_bytes = PACK_FILE.read_bytes()
    pack = json.loads(pack_bytes.decode("utf-8"))
    battery_item = next(item for item in model["inventory"] if item["id"] == "battery_main")
    if pack["mass_kg"]["value"] != battery_item["mass"]["value"]:
        raise ValueError("BAT-13: pack mass must equal the TT-07 battery_main inventory mass")
    variant = copy.deepcopy(model)
    variant["description"] = ("EXPERIMENTAL TT-07 + BAT-13: the TT-07 airframe and inventory with a finite 4S 3200 mAh LiPo "
        "class pack (pack_ecm: dataset-derived cell curve, estimated class resistance, lumped temperature) and an "
        "estimated soft low-voltage cutoff. Not physical validation.")
    variant["capabilities"]["energy"] = "pack_ecm"
    est = lambda value, unit, source: q(value, unit, "estimated", source)
    variant["propulsion"]["battery"] = dict(
        kind="pack_ecm",
        pack=dict(id=PACK_ID, sha256=hashlib.sha256(pack_bytes).hexdigest()),
        mount_inventory_id="battery_main",
        initial_soc=est(1.0, "1", PACK_SOURCE + ": freshly charged pack at rest (CC-CV to 4.2 V/cell); the session may override it"),
        auxiliary_current_a=est(0.3, "A", PACK_SOURCE + ": receiver, six micro servos and navigation LEDs, about 3.3 W at the BEC rail through an assumed 80 % BEC, referred to a 15 V pack; not measured"),
        cooling_airflow_fraction=est(0.1, "1", PACK_SOURCE + ": enclosed foam battery bay behind the hatch; ram airflow past the pack assumed 10 % of airspeed"),
        weak_cell=dict(
            capacity_factor=q(1.0, "1", "derived", PACK_SOURCE + ": new balanced pack; a pack record may lower it"),
            resistance_factor=q(1.0, "1", "derived", PACK_SOURCE + ": new balanced pack; a pack record may raise it"),
            soc_offset=q(0.0, "1", "derived", PACK_SOURCE + ": balanced charge")))
    avian = "Spektrum Avian ESC family manual pp. 9-13 (EL1a-R1/02-battery.md)"
    variant["propulsion"]["esc"] = dict(kind="ideal_motoring", command_mapping="identity", low_voltage_cutoff=dict(
        mode="soft", cell_detection="auto",
        detection_max_cell_v=est(4.3, "V", "Avian auto cell count rule undocumented; Betaflight-style 4.30 V/cell maximum assumed (BAT-00 F7)"),
        cutoff_per_cell_v=est(3.2, "V", avian + ": selectable 2.8-3.8 V/cell; installed default not identified; 3.2 V/cell assumed"),
        soft_limit=q(0.5, "1", "manual", avian + ": soft cutoff reduces output to 50 %; the troubleshooting section says 60 %"),
        soft_ramp_s=q(3.0, "s", "manual", avian + ": soft cutoff applied over 3 s"),
        debounce_s=est(0.5, "s", "ESC low-voltage debounce undocumented; 0.5 s assumed so brief punch-out sag does not trip"),
        recovery="throttle_reset",
        reset_throttle_max=q(0.05, "1", "derived", "app/input/rc_input.gd ARM_THROTTLE 0.05: the same idle-stick threshold"),
        voltage_filter_s=est(0.1, "s", "ESC voltage measurement filtering undocumented; 0.1 s low-pass assumed")))
    validate_physical_identity(variant)
    return variant


def _encode(model):
    return (json.dumps(model,indent=2,ensure_ascii=False,allow_nan=False)+"\n").replace("\n","\r\n").encode("utf-8")


def main():
    parser=argparse.ArgumentParser();parser.add_argument("--check",action="store_true");args=parser.parse_args()
    model,summary=derive()
    outputs=[(OUTPUT,_encode(model)),(PACK_OUTPUT,_encode(derive_pack_variant(model)))]
    if args.check:
        for path,data in outputs:
            if not path.exists() or path.read_bytes()!=data:raise SystemExit("Timber physics data stale: regenerate with "+SOURCE)
        print("TT-07 Timber physics current")
    else:
        for path,data in outputs:path.write_bytes(data)
        print(json.dumps(summary,indent=2))


if __name__=="__main__":main()
