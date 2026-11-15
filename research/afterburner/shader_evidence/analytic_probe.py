#!/usr/bin/env python3
"""Scalar blend and idealized cone-normal checks; no renderer, textures or GPU."""
import json
import math
from pathlib import Path


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def unit(v):
    length = math.sqrt(dot(v, v))
    return tuple(x / length for x in v)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def normal_example(t, theta):
    # Smooth ideal unit cone with the prototype's amplitude and frequencies.
    # The real discrete primitive is not inspected or rendered here.
    r, length, amplitude = 0.036, 0.42, 0.065
    s, c = math.sin(29 * t), math.cos(29 * t)
    st, ct = math.sin(3 * theta), math.cos(3 * theta)
    factor = 1 + amplitude * t * s * st
    radius = r * (1 - t) * factor
    dr_dt = r * (-factor + (1 - t) * amplitude * (s + 29 * t * c) * st)
    dr_dtheta = r * (1 - t) * amplitude * t * s * 3 * ct
    co, si = math.cos(theta), math.sin(theta)
    p_theta = (dr_dtheta * co - radius * si, dr_dtheta * si + radius * co, 0)
    p_t = (dr_dt * co, dr_dt * si, length)
    exact = unit(cross(p_theta, p_t))
    simple = unit((co / (r * factor), si / (r * factor), 1 / length))
    angle = math.degrees(math.acos(max(-1, min(1, dot(exact, simple)))))
    return {"t": t, "theta_rad": theta, "angle_degrees": angle,
            "exact_ideal_normal": exact, "scaled_input_normal": simple}


def mix_stack(bg, source, alpha, count):
    out = bg
    for _ in range(count):
        out = source * alpha + out * (1 - alpha)
    return out


def layer_over(back, front, alpha):
    return tuple(front[i] * alpha + back[i] * (1 - alpha) for i in range(3))


def main():
    bg, source, reference_alpha = 0.2, 0.8, 0.2
    tau = -math.log1p(-reference_alpha)
    layers = []
    for count in (1, 2, 4, 8):
        per_alpha = -math.expm1(-tau / count)
        layers.append({"count": count,
                       "fixed_alpha_each": reference_alpha,
                       "additive_fixed": bg + count * source * reference_alpha,
                       "additive_normalized": bg + source * reference_alpha,
                       "mix_fixed": mix_stack(bg, source, reference_alpha, count),
                       "tau_normalized_per_alpha": per_alpha,
                       "mix_tau_normalized": mix_stack(bg, source, per_alpha, count),
                       "premul_tau_normalized": mix_stack(bg, source, per_alpha, count)})
        assert abs(layers[-1]["mix_tau_normalized"] - 0.32) < 1e-12
    base, orange, blue, alpha = (0.2, 0.2, 0.2), (1.0, 0.3, 0.05), (0.1, 0.4, 1.0), 0.3
    orange_then_blue = layer_over(layer_over(base, orange, alpha), blue, alpha)
    blue_then_orange = layer_over(layer_over(base, blue, alpha), orange, alpha)
    candidates = [normal_example(i / 100, 2 * math.pi * j / 200)
                  for i in range(5, 96) for j in range(200)]
    maximum = max(candidates, key=lambda v: v["angle_degrees"])
    result = {
        "scope": "CPU arithmetic only. These are idealized blend equations and a smooth cone, not Godot rendering, GPU pixels, a 4.8-beta2 engine test, physical exhaust, or actual CylinderMesh vertex-array sampling.",
        "blend_model": "Scalar additive B + n*C*a; straight mix and premultiplied P=C*a use P+(1-a)*B. The fixed-total optical depth tau=-ln(1-a_ref) is divided equally among layers. No clipping, sRGB transforms, tone mapping, depth tests, or surface variation.",
        "background": bg, "source": source, "reference_alpha": reference_alpha,
        "tau": tau, "layers": layers,
        "colored_mix_order": {"background": base, "orange": orange, "blue": blue, "alpha_each": alpha,
                              "orange_then_blue": orange_then_blue, "blue_then_orange": blue_then_orange},
        "cone_model": "Continuous ideal cone R(t,theta)=r*(1-t)*(1+0.065*t*sin(29*t)*sin(3*theta)); L=0.42m, r=0.036m. Compares exact parametric normal with the prototype-style constant-scale transformed undeformed cone normal; no rasterization.",
        "cone_grid": {"t_range": "0.05..0.95 step 0.01", "theta_samples": 200, "maximum": maximum,
                      "representative": normal_example(0.5, 0.13 * 2 * math.pi)},
        "vertex_map": {"axes": "(x,y,z) -> (r*x, r*z, L*y)", "determinant_expression": "-r^2*L", "r": 0.036, "L": 0.42, "determinant": -(0.036**2) * 0.42}
    }
    out = Path(__file__).with_name("analytic_probe.json")
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(out.read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
