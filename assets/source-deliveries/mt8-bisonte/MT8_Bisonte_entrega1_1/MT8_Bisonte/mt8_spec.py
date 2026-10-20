"""MT8 "Bisonte" - especificacion geometrica y cinematica (fuente unica de verdad).

Todas las medidas en metros, en el marco de Godot:
  +X derecha del vehiculo, +Y arriba, -Z adelante (izquierda/derecha mirando hacia delante).
Origen: centro del chasis = plano de simetria (x=0), punto medio entre ejes (z=0),
cara inferior de las placas laterales del chasis (y=0).
En la pose de diseno (ride height) el origen queda a 0.125 m sobre el suelo.

Este modulo no depende de bpy: lo usan el build de Blender, los chequeos y el JSON para Godot.
"""
import json
import math

VERSION = "0.1.0-blockout"
NAME = "Bisonte MT8"

# ---------------------------------------------------------------- dimensiones base
WHEELBASE = 0.420          # distancia entre ejes
TRACK = 0.430              # separacion entre centros de rueda (izq-der), igual delante y detras
TIRE_R = 0.100             # radio exterior del neumatico (sobre tacos)
TIRE_W = 0.090             # ancho del neumatico
RIM_R = 0.062              # radio del borde de la llanta (pestana)
RIM_W = 0.078              # ancho de la llanta
RIM_FACE = 0.022           # cara de radios desplazada hacia fuera del plano medio (llanta de plato hondo)
RIDE_Y_WHEEL = -0.025      # altura del centro de rueda en pose de diseno (marco del chasis)
GROUND_Y = RIDE_Y_WHEEL - TIRE_R   # -0.125: suelo en pose de diseno

Z_FRONT = -WHEELBASE / 2   # eje delantero
Z_REAR = +WHEELBASE / 2    # eje trasero
X_WHEEL = TRACK / 2        # 0.215

# ---------------------------------------------------------------- suspension (paralelogramo)
# Brazo inferior y bieleta superior de igual longitud y paralelos: la mangueta se traslada
# sobre un arco de radio ARM_L sin cambiar de camber. Un solo parametro por rueda: el recorrido t.
ARM_X_IN = 0.060           # x del eje de bisagra interior (ambos brazos)
ARM_L = X_WHEEL - ARM_X_IN # 0.155
BJ_DY = 0.022              # rotulas a +-0.022 del centro de rueda, sobre el eje de pivote (kingpin)
Y_ARM_LO = RIDE_Y_WHEEL - BJ_DY   # -0.055
Y_ARM_UP = RIDE_Y_WHEEL + BJ_DY   # +0.005
ARM_PIN_DZ = 0.045         # pasadores del brazo inferior a z_eje +- 0.045

TRAVEL_BUMP = 0.050        # compresion maxima (rueda sube respecto al chasis)
TRAVEL_DROOP = 0.070       # extension maxima (rueda baja)
STEER_MAX_DEG = 30.0       # giro maximo de las manguetas delanteras, simetrico

# ---------------------------------------------------------------- amortiguadores (2 por rueda)
SHOCK_DZ = 0.030           # A en z_eje-0.030 (delante), B en z_eje+0.030 (detras)
SHOCK_LO_ARM = (0.050, 0.012)   # anclaje inferior en coords del brazo: (a lo largo del brazo, altura)
SHOCK_UP = (0.070, 0.125)       # anclaje superior en la torreta: (|x|, y)
SHOCK_CAP_UP = 0.012       # distancia ojal superior -> platillo superior del muelle
SHOCK_CAP_LO = 0.018       # distancia ojal inferior -> platillo inferior del muelle
SHOCK_CUP_OVERLAP = 0.015  # solape minimo del vastago dentro del cuerpo

# ---------------------------------------------------------------- transmision
DIFF_OUT_X = 0.065         # salida del diferencial (x), a la altura del eje en pose de diseno
CV_OFF = 0.022             # junta homocinetica exterior: 0.022 hacia dentro del eje de pivote
CV_CUP_DEPTH = 0.015

# ---------------------------------------------------------------- chasis / carroceria / otros
CHASSIS_PLATE_X = 0.040    # cara interior de las placas laterales
CHASSIS_PLATE_T = 0.005
CHASSIS_PLATE_H = 0.058
CHASSIS_LEN = 0.500
BODY_HALF_W = 0.190
BODY_FRONT_Z = -0.285
BODY_REAR_Z = 0.285
BODY_BOTTOM_Y = 0.060
BODY_ROOF_Y = 0.225
BUMPER_Z = 0.322           # tubo del parachoques a z = +-0.322
BUMPER_HALF_W = 0.130


def side_of(corner):
    return -1.0 if corner[1] == "L" else 1.0


def axle_z(corner):
    return Z_FRONT if corner[0] == "F" else Z_REAR


CORNERS = ("FL", "FR", "RL", "RR")


def arm_angle(travel):
    """Angulo de los brazos (rad, + = rueda arriba) para un recorrido vertical dado."""
    t = max(-TRAVEL_DROOP, min(TRAVEL_BUMP, travel))
    return math.asin(t / ARM_L)


def wheel_offset(corner, travel):
    """Desplazamiento (dx, dy, dz) del centro de rueda respecto a la pose de diseno."""
    th = arm_angle(travel)
    s = side_of(corner)
    return (s * ARM_L * (math.cos(th) - 1.0), ARM_L * math.sin(th), 0.0)


def rot_z(v, a):
    c, s_ = math.cos(a), math.sin(a)
    return (c * v[0] - s_ * v[1], s_ * v[0] + c * v[1], v[2])


def rot_y(v, a):
    c, s_ = math.cos(a), math.sin(a)
    return (c * v[0] + s_ * v[2], v[1], -s_ * v[0] + c * v[2])


def shock_points(corner, which, travel):
    """Ojal superior (fijo) e inferior (en el brazo) en el marco raiz."""
    s = side_of(corner)
    za = axle_z(corner)
    dz = -SHOCK_DZ if which == "A" else SHOCK_DZ
    up = (s * SHOCK_UP[0], SHOCK_UP[1], za + dz)
    th = arm_angle(travel)
    local = (s * SHOCK_LO_ARM[0], SHOCK_LO_ARM[1], 0.0)
    r = rot_z(local, s * th)
    lo = (s * ARM_X_IN + r[0], Y_ARM_LO + r[1], za + dz)
    return up, lo


def dist(a, b):
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))


def shock_length(corner, which, travel):
    up, lo = shock_points(corner, which, travel)
    return dist(up, lo)


def cv_points(corner, travel, steer):
    s = side_of(corner)
    za = axle_z(corner)
    pin = (s * DIFF_OUT_X, RIDE_Y_WHEEL, za)
    off = wheel_offset(corner, travel)
    wc = (s * X_WHEEL + off[0], RIDE_Y_WHEEL + off[1], za)
    o = rot_y((-s * CV_OFF, 0.0, 0.0), steer if corner[0] == "F" else 0.0)
    pout = (wc[0] + o[0], wc[1] + o[1], wc[2] + o[2])
    return pin, pout


# ---------------------------------------------------------------- valores derivados
L_REST = shock_length("FR", "A", 0.0)
L_MIN = shock_length("FR", "A", TRAVEL_BUMP)
L_MAX = shock_length("FR", "A", -TRAVEL_DROOP)
SHOCK_BODY_LEN = round(L_MIN - 0.016, 4)                          # ojal sup -> fondo del cuerpo
SHOCK_SHAFT_LEN = round(L_MAX - SHOCK_BODY_LEN + SHOCK_CUP_OVERLAP, 4)  # ojal inf -> punta del vastago
SPRING_REST = L_REST - SHOCK_CAP_UP - SHOCK_CAP_LO

_cv = []
for _t in (-TRAVEL_DROOP, 0.0, TRAVEL_BUMP):
    for _d in (-STEER_MAX_DEG, 0.0, STEER_MAX_DEG):
        a, b = cv_points("FR", _t, math.radians(_d))
        _cv.append(dist(a, b))
CV_LEN_MIN, CV_LEN_MAX = min(_cv), max(_cv)
CV_REST = dist(*cv_points("FR", 0.0, 0.0))
# palier telescopico en dos piezas (como el amortiguador): interior desde el diferencial, exterior desde la junta
DS_IN_LEN = 0.075
DS_OUT_LEN = 0.075
assert DS_IN_LEN + DS_OUT_LEN >= CV_LEN_MAX + 0.008 and max(DS_IN_LEN, DS_OUT_LEN) <= CV_LEN_MIN - 0.008


def spec_dict():
    corners = {}
    for c in CORNERS:
        s = side_of(c)
        za = axle_z(c)
        d = {
            "side": "left" if s < 0 else "right",
            "axle": "front" if c[0] == "F" else "rear",
            "wheel_center_rest": [s * X_WHEEL, RIDE_Y_WHEEL, za],
            "arm_lower_pivot": [s * ARM_X_IN, Y_ARM_LO, za],
            "arm_upper_pivot": [s * ARM_X_IN, Y_ARM_UP, za],
            "arm_axis": [0, 0, 1],
            "arm_rotation_sign": s,
            "driveshaft_inner": [s * DIFF_OUT_X, RIDE_Y_WHEEL, za],
            "driveshaft_in_rest_dir": [s, 0, 0],
            "driveshaft_out_rest_dir": [-s, 0, 0],
            "driveshaft_out_local_pos": [-s * CV_OFF, 0, 0],
            "shocks": {},
        }
        for w in ("A", "B"):
            up, lo = shock_points(c, w, 0.0)
            d["shocks"][w] = {"upper_mount": list(up), "lower_mount_rest": list(lo),
                              "lower_mount_arm_local": [s * SHOCK_LO_ARM[0], SHOCK_LO_ARM[1], 0.0]}
        corners[c] = d
    return {
        "name": NAME,
        "version": VERSION,
        "units": "m",
        "frame": {"right": "+X", "up": "+Y", "forward": "-Z"},
        "origin": "x=0 plano de simetria, z=0 punto medio entre ejes, y=0 cara inferior de las placas del chasis",
        "ride_origin_height": -GROUND_Y,
        "wheelbase": WHEELBASE,
        "track": TRACK,
        "tire_radius": TIRE_R,
        "tire_width": TIRE_W,
        "rim_radius": RIM_R,
        "arm_length": ARM_L,
        "travel_bump": TRAVEL_BUMP,
        "travel_droop": TRAVEL_DROOP,
        "steer_max_deg": STEER_MAX_DEG,
        "steer_axis": "local +Y del nodo XX_Steer, pasa por el centro de rueda; + = gira a la izquierda",
        "spin_axis": "local +X del nodo XX_Spin; avanzar (-Z) = angulo decreciente",
        "shock_length": {"rest": L_REST, "min": L_MIN, "max": L_MAX},
        "shock_body_len": SHOCK_BODY_LEN,
        "shock_shaft_len": SHOCK_SHAFT_LEN,
        "shock_cap_up": SHOCK_CAP_UP,
        "shock_cap_lo": SHOCK_CAP_LO,
        "spring_rest_len": SPRING_REST,
        "driveshaft_in_len": DS_IN_LEN,
        "driveshaft_out_len": DS_OUT_LEN,
        "cv_offset": CV_OFF,
        "corners": corners,
    }


if __name__ == "__main__":
    print(json.dumps({k: v for k, v in spec_dict().items() if k != "corners"}, indent=1))
    print("CV len range", CV_LEN_MIN, CV_LEN_MAX, "rest", CV_REST)
    for t in (-TRAVEL_DROOP, 0, TRAVEL_BUMP):
        print("travel", t, "angle deg", round(math.degrees(arm_angle(t)), 2),
              "wheel offset", [round(x, 4) for x in wheel_offset("FR", t)],
              "shock len", round(shock_length("FR", "A", t), 4))
