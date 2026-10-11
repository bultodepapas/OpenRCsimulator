#!/usr/bin/env python3
"""FIELD-WORLD-PLAN FW-21: the sky through the day, from a physical atmosphere, as a small committed table.

For each sun elevation from -20 to +90 degrees (0.5 degree steps) it integrates single scattering through a
spherical atmosphere (Rayleigh + Mie + ozone absorption, Earth shadow included) and stores, per RGB channel:

- zenith:   sky radiance straight up;
- haze:     horizon radiance (view elevation 1 degree) away from the sun: the colour distant objects fade to;
- lobe:     extra horizon radiance toward the sun's azimuth, and lobe_k, its fitted angular exponent
            (horizon(az) = haze + lobe * cos(az)^lobe_k); lobe_height_deg, its vertical e-folding height fitted
            between 1 and 15 degrees of view elevation (the twilight arch hugs the horizon);
- sun:      transmittance from the ground to the sun (the direct light's colour and strength);
- cloud:    transmittance to the sun from the cloud deck (1.5 km): clouds stay lit after sunset.

Values are relative (top-of-atmosphere sun = 1 in every channel). The game anchors them at the calibrated 45 degree
look (Spec.ATMOSPHERE), so only their change with elevation comes from this model.

Model constants: E. Bruneton's 2017 reference implementation (BSD-3) and S. Hillaire, "A Scalable and Production
Ready Sky and Atmosphere Rendering Technique", EGSR 2020 (Earth defaults), sampled at 680/550/440 nm.
Multiple scattering: an isotropic approximation after Hillaire 2020 (second order averaged over the sphere, the
infinite series as 1 / (1 - f_ms)), tabulated by altitude and local sun elevation. Ground reflection is omitted
(estimate: twilight slightly darker than real).

Stdlib only. Output rounded to 6 significant digits so platform libm differences cannot change the bytes.
  python3 tools/world/sky_table.py            write app/data/sky/sky_table.json
  python3 tools/world/sky_table.py --check    fail if the committed table differs from a fresh run
"""
import json
import math
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "app" / "data" / "sky" / "sky_table.json"

R_GROUND = 6360e3          # m
R_TOP = 6420e3             # m
OBSERVER_M = 2.0           # pilot eye height, rounded
CLOUD_DECK_M = 1500.0      # Spec.ATMOSPHERE.cloud_deck_m
RAYLEIGH = (5.802e-6, 13.558e-6, 33.1e-6)   # scattering, 1/m at sea level (680, 550, 440 nm)
RAYLEIGH_H = 8000.0
MIE_SCATTER = 3.996e-6
MIE_EXTINCT = 4.40e-6
MIE_H = 1200.0
MIE_G = 0.8
OZONE = (0.650e-6, 1.881e-6, 0.085e-6)       # absorption, 1/m at peak density
OZONE_CENTER = 25e3
OZONE_HALF_WIDTH = 15e3
ELEVATIONS = [e / 2.0 for e in range(-40, 181)]
VIEW_STEPS = 96
SUN_STEPS = 32
HORIZON_VIEW_DEG = 1.0
LOBE_HIGH_DEG = 15.0
SUN_RADIUS_DEG = 0.2665
ZENITH_MIE_MU_MAX = math.cos(math.radians(35.0))  # aureole excluded from the zenith sample (estimate: halo width)


def densities(r):
    h = r - R_GROUND
    ozone = max(0.0, 1.0 - abs(h - OZONE_CENTER) / OZONE_HALF_WIDTH)
    return math.exp(-h / RAYLEIGH_H), math.exp(-h / MIE_H), ozone


def extinction(r):
    dr, dm, do = densities(r)
    return [RAYLEIGH[c] * dr + MIE_EXTINCT * dm + OZONE[c] * do for c in range(3)]


def ray_sphere_exit(p, d, radius):
    """Distance along d from p (inside the sphere) to the sphere's surface."""
    b = sum(p[i] * d[i] for i in range(3))
    c = sum(x * x for x in p) - radius * radius
    return -b + math.sqrt(max(b * b - c, 0.0))


def hits_ground(p, d):
    b = sum(p[i] * d[i] for i in range(3))
    c = sum(x * x for x in p) - R_GROUND * R_GROUND
    return b < 0.0 and b * b - c > 0.0


def transmittance(p, d, steps):
    """Transmittance from p along d to the top of the atmosphere; 0 when the Earth is in the way."""
    if hits_ground(p, d):
        return [0.0, 0.0, 0.0]
    length = ray_sphere_exit(p, d, R_TOP)
    depth = [0.0, 0.0, 0.0]
    prev = 0.0
    for i in range(1, steps + 1):
        t = length * (i / steps) ** 2           # denser steps near the start (thicker air)
        mid = (prev + t) / 2.0
        q = [p[k] + d[k] * mid for k in range(3)]
        ext = extinction(math.sqrt(sum(x * x for x in q)))
        for c in range(3):
            depth[c] += ext[c] * (t - prev)
        prev = t
    return [math.exp(-x) for x in depth]


def scattering(r):
    dr, dm, _ = densities(r)
    return [RAYLEIGH[c] * dr + MIE_SCATTER * dm for c in range(3)]


def single_from(p, view, sun, steps, sun_steps):
    """Single-scattered radiance arriving at p along -view, and f_ms, the isotropic re-scatter fraction (Hillaire)."""
    if hits_ground(p, view):
        b = sum(p[i] * view[i] for i in range(3))
        c = sum(x * x for x in p) - R_GROUND * R_GROUND
        length = -b - math.sqrt(max(b * b - c, 0.0))
    else:
        length = ray_sphere_exit(p, view, R_TOP)
    mu = sum(view[i] * sun[i] for i in range(3))
    pr, pm = phase_rayleigh(mu), phase_mie(mu)
    depth = [0.0, 0.0, 0.0]
    out = [0.0, 0.0, 0.0]
    fms = [0.0, 0.0, 0.0]
    prev = 0.0
    for i in range(1, steps + 1):
        t = length * (i / steps) ** 2
        ds = t - prev
        mid = (prev + t) / 2.0
        q = [p[k] + view[k] * mid for k in range(3)]
        r = math.sqrt(sum(x * x for x in q))
        dr, dm, do = densities(r)
        ext = [RAYLEIGH[c] * dr + MIE_EXTINCT * dm + OZONE[c] * do for c in range(3)]
        t_sun = transmittance(q, sun, sun_steps)
        for c in range(3):
            att = math.exp(-(depth[c] + ext[c] * ds / 2.0))
            out[c] += att * (RAYLEIGH[c] * dr * pr + MIE_SCATTER * dm * pm) * t_sun[c] * ds
            fms[c] += att * (RAYLEIGH[c] * dr + MIE_SCATTER * dm) * ds
            depth[c] += ext[c] * ds
        prev = t
    return out, fms


def sphere_directions(n):
    """Fibonacci sphere, deterministic."""
    golden = math.pi * (3.0 - math.sqrt(5.0))
    out = []
    for i in range(n):
        y = 1.0 - 2.0 * (i + 0.5) / n
        rad = math.sqrt(max(0.0, 1.0 - y * y))
        out.append([math.cos(golden * i) * rad, y, math.sin(golden * i) * rad])
    return out


PSI_HEIGHTS = [0.0, 500.0, 1000.0, 2000.0, 3500.0, 5000.0, 8000.0, 12000.0, 18000.0, 25000.0, 35000.0, 50000.0, 60000.0]
PSI_SUN = [float(e) for e in range(-24, 92, 2)]
PSI_DIRS = 32


def psi_table():
    """Multiple-scattering radiance per unit scattering coefficient, Psi(height, local sun elevation), RGB."""
    dirs = sphere_directions(PSI_DIRS)
    table = []
    for h in PSI_HEIGHTS:
        row_h = []
        p = [0.0, R_GROUND + h, 0.0]
        for se in PSI_SUN:
            sun = direction(se, 0.0)
            l_avg = [0.0, 0.0, 0.0]
            f_avg = [0.0, 0.0, 0.0]
            for d in dirs:
                l1, f1 = single_from(p, d, sun, 24, 12)
                for c in range(3):
                    l_avg[c] += l1[c] / PSI_DIRS
                    f_avg[c] += f1[c] / PSI_DIRS
            # Sphere-averaged radiance is the isotropic second-order source per unit scattering coefficient.
            row_h.append([l_avg[c] / (1.0 - min(f_avg[c], 0.99)) for c in range(3)])
        table.append(row_h)
    return table


def psi_lookup(psi, h, sun_elevation_deg):
    h = min(max(h, PSI_HEIGHTS[0]), PSI_HEIGHTS[-1])
    i = 0
    while i < len(PSI_HEIGHTS) - 2 and PSI_HEIGHTS[i + 1] < h:
        i += 1
    fh = (h - PSI_HEIGHTS[i]) / (PSI_HEIGHTS[i + 1] - PSI_HEIGHTS[i])
    se = min(max(sun_elevation_deg, PSI_SUN[0]), PSI_SUN[-1])
    j = min(int((se - PSI_SUN[0]) / 2.0), len(PSI_SUN) - 2)
    fs = (se - PSI_SUN[j]) / 2.0
    out = []
    for c in range(3):
        a = psi[i][j][c] * (1.0 - fs) + psi[i][j + 1][c] * fs
        b = psi[i + 1][j][c] * (1.0 - fs) + psi[i + 1][j + 1][c] * fs
        out.append(a * (1.0 - fh) + b * fh)
    return out


def phase_rayleigh(mu):
    return 3.0 / (16.0 * math.pi) * (1.0 + mu * mu)


def phase_mie(mu):  # Cornette-Shanks
    g = MIE_G
    return 3.0 / (8.0 * math.pi) * (1.0 - g * g) * (1.0 + mu * mu) / ((2.0 + g * g) * (1.0 + g * g - 2.0 * g * mu) ** 1.5)


def direction(elevation_deg, azimuth_deg):
    """Unit vector in a frame where +y is up at the observer and azimuth 0 is toward +x."""
    e = math.radians(elevation_deg)
    a = math.radians(azimuth_deg)
    return [math.cos(e) * math.cos(a), math.sin(e), math.cos(e) * math.sin(a)]


def radiance(view, sun, psi, mie_mu_max=1.0):
    """Sky radiance seen from the observer along `view` for a unit top-of-atmosphere sun: single scattering plus the
    isotropic multiple-scattering source Psi(height, local sun elevation). `mie_mu_max` caps the Mie phase so a sample
    near the sun leaves out the aureole (the sky shader draws the sun's halo itself)."""
    p0 = [0.0, R_GROUND + OBSERVER_M, 0.0]
    length = ray_sphere_exit(p0, view, R_TOP)
    mu = sum(view[i] * sun[i] for i in range(3))
    pr, pm = phase_rayleigh(mu), phase_mie(min(mu, mie_mu_max))
    depth = [0.0, 0.0, 0.0]
    out = [0.0, 0.0, 0.0]
    prev = 0.0
    for i in range(1, VIEW_STEPS + 1):
        t = length * (i / VIEW_STEPS) ** 2
        ds = t - prev
        mid = (prev + t) / 2.0
        q = [p0[k] + view[k] * mid for k in range(3)]
        r = math.sqrt(sum(x * x for x in q))
        dr, dm, do = densities(r)
        ext = [RAYLEIGH[c] * dr + MIE_EXTINCT * dm + OZONE[c] * do for c in range(3)]
        half = [depth[c] + ext[c] * ds / 2.0 for c in range(3)]
        t_sun = transmittance(q, sun, SUN_STEPS)
        local_sun = math.degrees(math.asin(max(-1.0, min(1.0, sum(q[k] * sun[k] for k in range(3)) / r))))
        ms = psi_lookup(psi, r - R_GROUND, local_sun)
        for c in range(3):
            scatter = RAYLEIGH[c] * dr * pr + MIE_SCATTER * dm * pm
            total = RAYLEIGH[c] * dr + MIE_SCATTER * dm
            out[c] += math.exp(-half[c]) * (scatter * t_sun[c] + total * ms[c]) * ds
            depth[c] += ext[c] * ds
        prev = t
    return out


def sun_visible_fraction(elevation_deg):
    """Share of the solar disc above the geometric horizon (a straight edge across a disc of 0.2665 degrees)."""
    x = max(-1.0, min(1.0, elevation_deg / SUN_RADIUS_DEG))
    return 0.5 + (x * math.sqrt(1.0 - x * x) + math.asin(x)) / math.pi


def row(elevation_deg, psi):
    sun = direction(elevation_deg, 0.0)
    zenith = radiance([0.0, 1.0, 0.0], sun, psi, ZENITH_MIE_MU_MAX)
    toward = radiance(direction(HORIZON_VIEW_DEG, 0.0), sun, psi)
    side = radiance(direction(HORIZON_VIEW_DEG, 45.0), sun, psi)
    away = radiance(direction(HORIZON_VIEW_DEG, 180.0), sun, psi)
    lobe = [max(toward[c] - away[c], 0.0) for c in range(3)]
    high_toward = radiance(direction(LOBE_HIGH_DEG, 0.0), sun, psi)
    high_away = radiance(direction(LOBE_HIGH_DEG, 180.0), sun, psi)
    # cos(45°)^k = (side - away) / (toward - away), fitted on luminance.
    lum = lambda v: 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]
    ratio = (lum(side) - lum(away)) / max(lum(toward) - lum(away), 1e-30)
    lobe_k = math.log(min(max(ratio, 1e-6), 0.999999)) / math.log(math.cos(math.radians(45.0)))
    # Vertical decay of the sunward excess: excess(15°) / excess(1°) = exp(-14° / h).
    excess_low = max(lum(toward) - lum(away), 1e-30)
    excess_high = max(lum(high_toward) - lum(high_away), 1e-30)
    v_ratio = min(max(excess_high / excess_low, 1e-6), 0.999999)
    lobe_height = (LOBE_HIGH_DEG - HORIZON_VIEW_DEG) / -math.log(v_ratio)
    lift = [0.0, R_GROUND + OBSERVER_M, 0.0]
    visible = sun_visible_fraction(elevation_deg)
    # Above the horizon the disc is lifted a little so the transmittance is evaluated where the light comes from.
    sun_t = transmittance(lift, direction(max(elevation_deg, SUN_RADIUS_DEG), 0.0), SUN_STEPS * 4)
    cloud_t = transmittance([0.0, R_GROUND + CLOUD_DECK_M, 0.0], sun, SUN_STEPS * 4)
    return {
        "elevation_deg": elevation_deg,
        "zenith": zenith,
        "haze": away,
        "lobe": lobe,
        "lobe_k": min(max(lobe_k, 1.0), 64.0),
        "lobe_height_deg": min(max(lobe_height, 1.0), 90.0),
        "sun": [x * visible for x in sun_t],
        "cloud": cloud_t,
    }


def rounded(value):
    if isinstance(value, list):
        return [rounded(v) for v in value]
    if isinstance(value, float):
        return float(f"{value:.6g}")
    return value


def table():
    psi = psi_table()
    rows = [{k: rounded(v) for k, v in row(e, psi).items()} for e in ELEVATIONS]
    return {
        "format": "openrc-sky-table v1",
        "generator": "tools/world/sky_table.py",
        "metadata": {
            "kind": "derived",
            "source": "Single scattering through a spherical atmosphere (Rayleigh, Mie, ozone; Bruneton 2017 and "
                      "Hillaire 2020 Earth constants at 680/550/440 nm) plus Hillaire's isotropic multiple-scattering "
                      "approximation; no ground reflection (estimate: twilight slightly dark). Relative to a unit "
                      "top-of-atmosphere sun; anchored in game at 45°.",
            "elevation_deg": {"unit": "deg", "kind": "derived", "source": "Apparent sun elevation, -20 to 90 in 0.5 steps"},
            "zenith": {"unit": "relative radiance (RGB)", "kind": "derived", "source": "Sky straight up, Mie aureole within 35° of the sun excluded"},
            "haze": {"unit": "relative radiance (RGB)", "kind": "derived", "source": "Horizon (1° up) opposite the sun"},
            "lobe": {"unit": "relative radiance (RGB)", "kind": "derived", "source": "Horizon toward the sun minus haze"},
            "lobe_k": {"unit": "1", "kind": "derived", "source": "Exponent of cos(azimuth) fitted at 45° on luminance"},
            "lobe_height_deg": {"unit": "deg", "kind": "derived", "source": "Vertical e-folding height of the sunward excess, fitted between 1° and 15° of view elevation"},
            "sun": {"unit": "transmittance (RGB)", "kind": "derived", "source": "Ground to sun, times the visible disc share"},
            "cloud": {"unit": "transmittance (RGB)", "kind": "derived", "source": "1.5 km deck to sun, Earth shadow included"},
        },
        "rows": rows,
    }


def main():
    text = json.dumps(table(), indent=1, sort_keys=True) + "\n"
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text(encoding="utf-8").replace("\r\n", "\n") != text:
            print(f"{OUT} is stale: run tools/world/sky_table.py", file=sys.stderr)
            sys.exit(1)
        print("sky table current")
        return
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {OUT} ({len(ELEVATIONS)} rows)")


if __name__ == "__main__":
    main()
