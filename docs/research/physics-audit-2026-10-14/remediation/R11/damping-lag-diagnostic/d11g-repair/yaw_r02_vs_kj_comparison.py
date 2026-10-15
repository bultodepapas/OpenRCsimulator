"""Read-only matched sensitivity study for the unresolved R02 / D11f wing-yaw residual.

This is a diagnostic, not a candidate flight law. It uses the current exported Stik strip inputs,
the preserved D11f horseshoe kernel, and finite differences at the same V/rho/step. Positive-axial,
attached cases only (alpha=0..11 deg, r=+/-0.05 rad/s); no reverse-flow or stalled interpretation.
The D11f reference's x and z axes are opposite the simulator's body-forward/body-down axes for the
wing loads used here, so its N=sum(y*Fx) is compared with production Mz=-sum(y*Fx_body).
"""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import math
from pathlib import Path


HERE = Path(__file__).resolve().parent
INPUT_PATH = HERE / "yaw_r02_input_export-v1.json"
PRODUCTION_LOG = HERE / "yaw_decomposition-current-law.log"
D11F_PATH = Path(__file__).resolve().parents[7] / "research" / "aero" / "d11f" / "wing_yaw_damping.py"
V = 15.0
RHO = 1.225
H = 0.05
ALPHAS_DEG = (0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 11.0)


def _solve(a: list[list[float]], rhs: list[float]) -> list[float]:
    n = len(rhs)
    m = [row[:] + [rhs[i]] for i, row in enumerate(a)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda row: abs(m[row][col]))
        m[col], m[pivot] = m[pivot], m[col]
        if abs(m[col][col]) < 1.0e-14:
            raise ValueError("singular 6-strip solve")
        for row in range(col + 1, n):
            factor = m[row][col] / m[col][col]
            for k in range(col, n + 1):
                m[row][k] -= factor * m[col][k]
    out = [0.0] * n
    for row in range(n - 1, -1, -1):
        out[row] = (m[row][n] - sum(m[row][k] * out[k] for k in range(row + 1, n))) / m[row][row]
    return out


def _inverse(a: list[list[float]]) -> list[list[float]]:
    n = len(a)
    columns = [_solve(a, [1.0 if row == col else 0.0 for row in range(n)]) for col in range(n)]
    return [[columns[col][row] for col in range(n)] for row in range(n)]


def _matvec(a: list[list[float]], x: list[float]) -> list[float]:
    return [sum(a[i][j] * x[j] for j in range(len(x))) for i in range(len(a))]


def _load_d11f():
    spec = importlib.util.spec_from_file_location("preserved_d11f_yaw_reference", D11F_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot import preserved D11f reference")
    module = importlib.util.module_from_spec(spec)
    with contextlib.redirect_stdout(io.StringIO()):
        spec.loader.exec_module(module)
    return module


def _load_production_rows() -> dict[float, dict[str, float]]:
    result: dict[float, dict[str, float]] = {}
    columns: list[str] | None = None
    for line in PRODUCTION_LOG.read_text(encoding="utf-8").splitlines():
        if line.startswith("columns="):
            columns = line[len("columns="):].split(",")
        elif columns and line and line[0].isdigit() and "," in line:
            fields = line.split(",")
            if len(fields) == len(columns):
                values = {name: float(value) for name, value in zip(columns, fields)}
                result[values["alpha_deg"]] = values
    if not result:
        raise RuntimeError("current production decomposition log has no numeric rows")
    return result


def _setup():
    data = json.loads(INPUT_PATH.read_text(encoding="utf-8"))
    geom, aero = data["geometry"], data["aero"]
    ys = list(map(float, geom["station_y_m"]))
    n = len(ys)
    e_flat = list(map(float, geom["induced_map_E"]))
    e = [e_flat[i * n:(i + 1) * n] for i in range(n)]
    a0 = float(geom["strip_slope_per_rad"])
    e_inv = _inverse(e)
    # A = E^-1 = I + a0*K; M=A/a0 is the no-rate Weissinger operator.
    a_static = e_inv
    m_static = [[a_static[i][j] / a0 for j in range(n)] for i in range(n)]
    camber_alpha = _matvec(m_static, list(map(float, geom["strip_cl0"])))
    # This is M*cl0, the fixed incidence source that reproduces the
    # checked-in strip intercepts at alpha=r=0 in the matched circulation model.
    return data, ys, e, a0, a_static, m_static, camber_alpha


def _flow(alpha: float, rate: float, ys: list[float]):
    u = [V * math.cos(alpha) - rate * y for y in ys]
    w = [V * math.sin(alpha) for _ in ys]
    vp = [math.hypot(u[i], w[i]) for i in range(len(ys))]
    max_speed = max(vp)
    angles = [math.atan2(w[i], u[i]) for i in range(len(ys))]
    source = [vp[i] / max_speed for i in range(len(ys))]
    if min(u) <= 0.0:
        raise ValueError("probe left its positive-axial domain")
    return u, w, vp, angles, source


def _r02_cl(data, ys, e, a0, alpha, rate, mode="production"):
    g, aero = data["geometry"], data["aero"]
    u, w, vp, angles, source = _flow(alpha, rate, ys)
    intercept = list(map(float, g["strip_cl0"]))
    if mode == "zero_intercept":
        intercept = [0.0] * len(ys)
    out = []
    for i in range(len(ys)):
        cl = intercept[i]
        for j in range(len(ys)):
            weight = 1.0 if i == j or mode == "unweighted" else source[j]
            cl += a0 * e[i][j] * angles[j] * weight
        out.append(cl)
    return out, (u, w, vp, angles, source)


def _dynamic_cl(data, ys, a0, m_static, camber_alpha, alpha, rate, rhs_kind="angle"):
    """Rate-dependent u_j/u_i Weissinger operator, independently solved.

    rhs_kind='angle' holds the production geometric angle input fixed and changes only the
    induced operator. rhs_kind='weissinger' uses the exact W/u_i+alpha0 incidence RHS.
    """
    n = len(ys)
    u, w, vp, angles, source = _flow(alpha, rate, ys)
    dmat = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            # Recover the static vortex coefficient from the production E matrix, then apply
            # the Weissinger u_j/u_i ratio to off-diagonal coupling only. Self term is unchanged.
            kval = m_static[i][j] - (1.0 / float(data["geometry"]["strip_slope_per_rad"]) if i == j else 0.0)
            if i != j:
                kval *= u[j] / u[i]
            dmat[i][j] = kval + (1.0 / a0 if i == j else 0.0)
    if rhs_kind == "weissinger":
        rhs = [w[i] / u[i] + camber_alpha[i] for i in range(n)]
    else:
        rhs = [angles[i] + camber_alpha[i] for i in range(n)]
    return _solve(dmat, rhs), (u, w, vp, angles, source)


def _dimensional_g_cl(data, ys, e, a0, camber_alpha, alpha, rate, exact_weissinger=True):
    """Fixed-E dimensional-source identity g=u*CL for the attached positive-u domain."""
    n = len(ys)
    u, w, vp, angles, source = _flow(alpha, rate, ys)
    if exact_weissinger:
        dimensional_source = [w[i] + u[i] * camber_alpha[i] for i in range(n)]
    else:
        dimensional_source = [u[i] * (angles[i] + camber_alpha[i]) for i in range(n)]
    g = [a0 * value for value in _matvec(e, dimensional_source)]
    return [g[i] / u[i] for i in range(n)], (u, w, vp, angles, source)


def _r02_forces(data, ys, aero, alpha, rate, cl, flow, *, profile_x_only=False,
                induced_x_only=False, k_override=None, clmin_override=None):
    u, w, vp, angles, source = flow
    n = len(ys)
    area = float(data["geometry"]["area_m2"]) / n
    cd0 = float(aero["CD0"])
    k = float(aero["k_induced_whole_aircraft"]) if k_override is None else k_override
    clmin = float(aero["CL_minD"]) if clmin_override is None else clmin_override
    per_component = {key: 0.0 for key in ("profile", "induced", "lift")}
    for i, y in enumerate(ys):
        profile_speed = vp[i] * vp[i] if profile_x_only else vp[i] * u[i]
        induced_speed = vp[i] * vp[i] if induced_x_only else vp[i] * u[i]
        fx = {
            "profile": -0.5 * RHO * area * cd0 * profile_speed,
            "induced": -0.5 * RHO * area * k * (cl[i] - clmin) ** 2 * induced_speed,
            "lift": 0.5 * RHO * area * vp[i] * cl[i] * w[i],
        }
        for key, force_x in fx.items():
            per_component[key] += -y * force_x
    per_component["total"] = sum(per_component.values())
    return per_component


def _d11f_moments(d11f, data, ys, a0, m_static, camber_alpha, alpha, rate, *, use_camber,
                  cl_override=None):
    n = len(ys)
    b = float(data["geometry"]["span_m"])
    c = float(data["geometry"]["mean_chord_m"])
    dy = b / n
    u, w, vp, angles, source = _flow(alpha, rate, ys)
    if cl_override is None:
        if use_camber:
            # D11f's exact attached equation is M(r) CL = W/u + alpha0. This solver uses
            # the same recovered static operator as production E, with the original u_j/u_i law.
            cl, _ = _dynamic_cl(data, ys, a0, m_static, camber_alpha, alpha, rate, "weissinger")
        else:
            # Reproduce the preserved D11f zero-camber solve, except use exported current a0.
            cl, _ = _dynamic_cl(data, ys, a0, m_static, [0.0] * n, alpha, rate, "weissinger")
    else:
        cl = list(cl_override)
    gamma = [0.5 * u[i] * c * cl[i] for i in range(n)]
    qk_moment = 0.0
    profile_moment = 0.0
    for i in range(n):
        downwash = -sum(d11f.trailing_w(0.0, ys[i], j) * gamma[j] for j in range(n))
        # D11f coordinates use x aft and z up. Mapping Fx_body=-Fx_D11f gives the
        # same positive yaw convention as production Mz=-sum(y*Fx_body).
        fx_kj = -RHO * gamma[i] * (w[i] - downwash) * dy
        fx_profile = 0.5 * RHO * (u[i] * u[i] + w[i] * w[i]) * c * dy * float(data["aero"]["CD0"])
        qk_moment += ys[i] * fx_kj
        profile_moment += ys[i] * fx_profile
    return {"kj": qk_moment, "profile": profile_moment, "total": qk_moment + profile_moment,
            "cl": cl, "gamma": gamma}


def _cnr(moment_at_rate):
    b = 1.524
    s = 0.464515
    denom = 0.5 * RHO * V * V * s * b * b / (2.0 * V)
    return (moment_at_rate(H) - moment_at_rate(-H)) / (2.0 * H) / denom


def _split_cnr(rows, key):
    return {part: _cnr(lambda rate: rows(alpha, rate)[part]) for part in ("profile", "induced", "lift", "total")}


def main():
    d11f = _load_d11f()
    data, ys, e, a0, a_static, m_static, camber_alpha = _setup()
    g, aero = data["geometry"], data["aero"]
    cl0 = list(map(float, g["strip_cl0"]))
    n = len(ys)
    kernel = [[-(d11f.horseshoe_w(float(g["mean_chord_m"]) / 2.0, ys[i], j)
                 * 0.5 * float(g["mean_chord_m"]))
               - (1.0 / (2.0 * math.pi) if i == j else 0.0)
               for j in range(n)] for i in range(n)]
    kernel_m = [[(1.0 / a0 if i == j else 0.0) + kernel[i][j]
                 for j in range(n)] for i in range(n)]
    kernel_a = [[(1.0 if i == j else 0.0) + a0 * kernel[i][j]
                 for j in range(n)] for i in range(n)]
    d11f_e = _inverse(kernel_a)
    d11f_e_gap = max(abs(e[i][j] - d11f_e[i][j]) for i in range(n) for j in range(n))
    kernel_gap = max(abs(m_static[i][j] - kernel_m[i][j]) for i in range(n) for j in range(n))

    production = _load_production_rows()
    output_rows = []
    for deg in ALPHAS_DEG:
        alpha = math.radians(deg)
        def r02_components(rate, mode="production", *, profile_x_only=False, induced_x_only=False,
                           k_override=None, clmin_override=None, cl_source="r02"):
            if cl_source == "r02":
                cl, flow = _r02_cl(data, ys, e, a0, alpha, rate, mode)
            elif cl_source == "dynamic_angle":
                cl, flow = _dynamic_cl(data, ys, a0, m_static, camber_alpha, alpha, rate, "angle")
            elif cl_source == "dynamic_weissinger":
                cl, flow = _dynamic_cl(data, ys, a0, m_static, camber_alpha, alpha, rate, "weissinger")
            elif cl_source == "dimensional_g_exact":
                cl, flow = _dimensional_g_cl(data, ys, e, a0, camber_alpha, alpha, rate, True)
            elif cl_source == "dimensional_g_angle":
                cl, flow = _dimensional_g_cl(data, ys, e, a0, camber_alpha, alpha, rate, False)
            else:
                raise ValueError(cl_source)
            return _r02_forces(data, ys, aero, alpha, rate, cl, flow,
                               profile_x_only=profile_x_only, induced_x_only=induced_x_only,
                               k_override=k_override, clmin_override=clmin_override)

        variants = {
            "R02_current_fixed_E_weighted": _cnr(lambda rate: r02_components(rate)["total"]),
            "R02_fixed_E_unweighted": _cnr(lambda rate: r02_components(rate, "unweighted")["total"]),
            "R02_zero_strip_intercept": _cnr(lambda rate: r02_components(rate, "zero_intercept")["total"]),
            "R02_k_induced_zero": _cnr(lambda rate: r02_components(rate, k_override=0.0)["total"]),
            "R02_CL_minD_zero": _cnr(lambda rate: r02_components(rate, clmin_override=0.0)["total"]),
            "R02_CD0_force_x_only": _cnr(lambda rate: r02_components(rate, profile_x_only=True)["total"]),
            "R02_rate_dependent_operator_angle_rhs": _cnr(lambda rate: r02_components(rate, cl_source="dynamic_angle")["total"]),
            "R02_dimensional_g_exact_Weissinger_rhs": _cnr(lambda rate: r02_components(rate, cl_source="dimensional_g_exact")["total"]),
            "R02_dimensional_g_u_times_atan2_approx": _cnr(lambda rate: r02_components(rate, cl_source="dimensional_g_angle")["total"]),
            "R02_dynamic_matched_camber_CL_with_R02_force": _cnr(lambda rate: r02_components(rate, cl_source="dynamic_weissinger")["total"]),
        }
        # Same current R02 CL, but substitute D11f's mapped-axis KJ + x-only profile force closure.
        def d11f_force_for_r02(rate):
            cl, _ = _r02_cl(data, ys, e, a0, alpha, rate, "production")
            return _d11f_moments(d11f, data, ys, a0, m_static, camber_alpha, alpha, rate,
                                 use_camber=True, cl_override=cl)["total"]
        variants["D11f_KJ_force_with_R02_fixed_E_CL"] = _cnr(d11f_force_for_r02)
        variants["D11f_original_zero_camber_authored_a0"] = _cnr(
            lambda rate: RHO * d11f.loads(alpha, rate)[1])
        variants["D11f_zero_camber_current_a0"] = _cnr(
            lambda rate: _d11f_moments(d11f, data, ys, a0, m_static, [0.0] * n,
                                       alpha, rate, use_camber=False)["total"])
        variants["D11f_matched_strip_intercept_current_a0"] = _cnr(
            lambda rate: _d11f_moments(d11f, data, ys, a0, m_static, camber_alpha,
                                       alpha, rate, use_camber=True)["total"])
        variants["D11f_matched_CL_with_R02_section_force"] = _cnr(
            lambda rate: r02_components(rate, cl_source="dynamic_weissinger")["total"])

        current_components = {name: _cnr(lambda rate, name=name: r02_components(rate)[name])
                              for name in ("profile", "induced", "lift")}
        current_components["total"] = sum(current_components.values())
        oracle = production[float(deg)]
        output_rows.append({
            "alpha_deg": deg,
            "production_check": {
                "R02_python_current_Cnr": current_components["total"],
                "GDScript_wing_Cnr_h005": oracle["wing_Cnr"],
                "absolute_error": abs(current_components["total"] - oracle["wing_Cnr"]),
                "components_python": current_components,
                "components_GDScript": {
                    "profile": oracle["wing_profile_Cnr"],
                    "induced": oracle["wing_induced_Cnr"],
                    "lift_projection": oracle["wing_lift_projection_Cnr"],
                },
            },
            "variants_Cnr": variants,
            "dynamic_vs_g_identity_max_abs_CL": max(
                abs(_dynamic_cl(data, ys, a0, m_static, camber_alpha, alpha, rate, "weissinger")[0][i]
                    - _dimensional_g_cl(data, ys, e, a0, camber_alpha, alpha, rate, True)[0][i])
                for rate in (H, -H) for i in range(n)),
            "zero_rate_CL_means": {
                "R02_current": sum(_r02_cl(data, ys, e, a0, alpha, 0.0, "production")[0]) / n,
                "D11f_matched_intercept": sum(_dynamic_cl(data, ys, a0, m_static, camber_alpha,
                                                            alpha, 0.0, "weissinger")[0]) / n,
            },
        })
    result = {
        "schema": "d11g-r02-vs-d11f-matched-yaw-sensitivity-v1",
        "interpretation": "Software and model-form sensitivity only; no physical validation or universal force-law claim.",
        "domain": {"speed_mps": V, "density_kg_m3": RHO, "central_difference_rad_s": H,
                   "alpha_deg": list(ALPHAS_DEG), "axial_flow": "positive throughout; attached R02 local law"},
        "identity": {
            "input_export_sha256": __import__("hashlib").sha256(INPUT_PATH.read_bytes()).hexdigest(),
            "aircraft_input_sha256": data["aircraft_input"]["sha256"],
            "aero_source_sha256": data["aero_source_sha256"],
            "d11f_source_sha256": __import__("hashlib").sha256(D11F_PATH.read_bytes()).hexdigest(),
            "production_decomposition_sha256": __import__("hashlib").sha256(PRODUCTION_LOG.read_bytes()).hexdigest(),
        },
        "model_inputs": {
            "area_m2": g["area_m2"], "span_m": g["span_m"], "mean_chord_m": g["mean_chord_m"],
            "strip_slope_per_rad": a0, "strip_CL_intercepts": cl0,
            "strip_CL_intercept_mean": sum(cl0) / n, "whole_aircraft_CL0": aero["CL0_whole_aircraft"],
            "CD0": aero["CD0"], "whole_aircraft_k_induced": aero["k_induced_whole_aircraft"],
            "whole_aircraft_CL_minD": aero["CL_minD"], "induced_map_E_max_abs_error_vs_D11d_kernel": d11f_e_gap,
            "D11f_static_operator_max_abs_error_vs_production_E": kernel_gap,
            "camber_equivalent_alpha0_rad": camber_alpha,
            "camber_alpha0_semantics": "fixed incidence vector chosen so the zero-rate Weissinger system reproduces production strip_cl0; not measured airfoil camber",
        },
        "rows": output_rows,
    }
    print(json.dumps(result, indent=2, sort_keys=True, allow_nan=False))


if __name__ == "__main__":
    main()
