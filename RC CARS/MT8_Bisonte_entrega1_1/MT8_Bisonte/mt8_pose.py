"""Aplica una pose de suspension/direccion/giro al blockout dentro de Blender.

Es la misma cinematica que debe implementar el simulador (ver mt8_rig.gd):
  - recorrido t por rueda (m, + = compresion), direccion delta (rad, + = izquierda), giro de rueda omega (rad).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mt8_spec as S  # noqa: E402
from mt8_geo import mat_g2b  # noqa: E402


def _T(v):
    return Matrix.Translation(Vector(v))


def _set(name, mg):
    o = bpy.data.objects[name]
    o.matrix_basis = mat_g2b(mg)


def pose(travel=None, steer=0.0, spin=0.0):
    """travel: float o dict {corner: t}. steer en rad (solo delanteras)."""
    if not isinstance(travel, dict):
        travel = {c: (travel or 0.0) for c in S.CORNERS}
    for c in S.CORNERS:
        s = S.side_of(c)
        za = S.axle_z(c)
        t = max(-S.TRAVEL_DROOP, min(S.TRAVEL_BUMP, travel.get(c, 0.0)))
        th = S.arm_angle(t)
        _set(f"{c}_ArmLower", _T((s * S.ARM_X_IN, S.Y_ARM_LO, za)) @ Matrix.Rotation(s * th, 4, 'Z'))
        _set(f"{c}_ArmUpper", _T((s * S.ARM_X_IN, S.Y_ARM_UP, za)) @ Matrix.Rotation(s * th, 4, 'Z'))
        off = S.wheel_offset(c, t)
        _set(f"{c}_Suspension", _T((s * S.X_WHEEL + off[0], S.RIDE_Y_WHEEL + off[1], za)))
        d = max(-math.radians(S.STEER_MAX_DEG), min(math.radians(S.STEER_MAX_DEG), steer))
        if c[0] == "F":
            _set(f"{c}_Steer", Matrix.Rotation(d, 4, 'Y'))
        _set(f"{c}_Spin", Matrix.Rotation(spin, 4, 'X'))
        for w in ("A", "B"):
            up, lo = S.shock_points(c, w, t)
            D = Vector(lo) - Vector(up)
            beta = math.atan2(D.x, -D.y)
            _set(f"{c}_Shock{w}_Body", _T(up) @ Matrix.Rotation(beta, 4, 'Z'))
            spring_len = D.length - S.SHOCK_CAP_UP - S.SHOCK_CAP_LO
            sc = Matrix.Diagonal((1.0, spring_len / S.SPRING_REST, 1.0, 1.0))
            _set(f"{c}_Shock{w}_Spring", _T((0, -S.SHOCK_CAP_UP, 0)) @ sc)
            dz = lo[2] - za
            _set(f"{c}_Shock{w}_Shaft", _T((s * S.SHOCK_LO_ARM[0], S.SHOCK_LO_ARM[1], dz)) @ Matrix.Rotation(beta - s * th, 4, 'Z'))
        dd = d if c[0] == "F" else 0.0
        pin, pout = S.cv_points(c, t, dd)
        cur = (Vector(pout) - Vector(pin)).normalized()
        q = Vector((s, 0, 0)).rotation_difference(cur)
        _set(f"{c}_DriveshaftIn", _T(pin) @ q.to_matrix().to_4x4())
        q2 = Vector((-s, 0, 0)).rotation_difference(-cur)
        local = Matrix.Rotation(-dd, 4, 'Y') @ q2.to_matrix().to_4x4()
        _set(f"{c}_DriveshaftOut", _T((-s * S.CV_OFF, 0, 0)) @ local)
    bpy.context.view_layer.update()
