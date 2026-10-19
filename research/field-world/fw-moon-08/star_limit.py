# FW-MOON-08b analysis: the naked-eye star limit under moonlight, from Krisciunas & Schaefer (1991, PASP 103:1033;
# moon sky brightness, eqs. 2, 3, 15, 19-21) and Crumey (2014, MNRAS 442:2600; point-source threshold eq. 53, F = 2).
# Prints the limiting magnitude against the angle from the moon for given moon cases, with the whole moonlit sky
# and without the aureole's forward peak (KS91's aerosol term above its 45° value, the part FW-MOON-08a draws).
# Usage: python3 -I research/field-world/fw-moon-08/star_limit.py
import math

K = 0.2                # V extinction per airmass (the stars' value, app/render/world/stars.gdshader)
DARK_CD = 2.0e-4       # Crumey's representative dark-site zenith sky, cd/m² (21.83 mag/arcsec²)
NL_TO_CD = 3.183e-6    # 1 nanoLambert in cd/m²
F = 2.0                # Crumey's notional overall field factor
SCOTOPIC_MAX = 3.426e-2  # cd/m²: upper validity of eq. 53


def airmass(z_deg):
    s = math.sin(math.radians(z_deg))
    return (1.0 - 0.96 * s * s) ** -0.5


def ks91_shape(rho):
    far = 10 ** (6.15 - rho / 40.0)
    return max(6.2e7 / (rho * rho), far) if rho < 30.0 else far


def moon_sky_nl(rho, z, moon_z, alpha, aerosol, peak_only=False):
    istar = 10 ** (-0.4 * (3.84 + 0.026 * abs(alpha) + 4e-9 * alpha ** 4))
    scale = istar * 10 ** (-0.4 * K * airmass(moon_z)) * (1 - 10 ** (-0.4 * K * airmass(z)))
    mie = ks91_shape(rho) * aerosol
    peak = max(ks91_shape(rho) - 10 ** (6.15 - 45.0 / 40.0), 0.0) * aerosol if rho < 45.0 else 0.0
    if peak_only:
        return peak * scale
    c = math.cos(math.radians(rho))
    return (10 ** 5.36 * (1.06 + c * c) + mie) * scale


def dark_cd(z):
    x = airmass(z)
    return DARK_CD * 10 ** (-0.4 * K * (x - 1.0)) * x


def crumey_limit(b_cd):
    b = min(max(b_cd, 1e-5), SCOTOPIC_MAX)
    t = 6.505e-4 * b ** 0.25 - 8.461e-4 * b ** 0.5
    return -2.5 * math.log10(F * t * t / 2.54e-6), b_cd > SCOTOPIC_MAX


def mag_arcsec2(b_cd):
    return -2.5 * math.log10(b_cd / 1.08e5)


def main():
    print("Crumey eq. 53 check: dark sky %.2f mag/arcsec² -> limit %.2f (paper: 6.18 for F = 2)" % (
        mag_arcsec2(DARK_CD), crumey_limit(DARK_CD)[0]))
    cases = [("Night preset: 98 % moon 19° up, default air (aerosols 1.9)", 71.0, 15.7, 1.9),
             ("Full moon 60° up, clear air (aerosols 1.0)", 30.0, 0.0, 1.0)]
    for name, moon_z, alpha, aerosol in cases:
        print("\n%s" % name)
        print("| Angle from the moon | Sky (mag/arcsec²) | Limit, whole moonlit sky | Limit without the aureole peak | Drop from the peak |")
        print("| --- | --- | --- | --- | --- |")
        for rho in (2.0, 5.0, 10.0, 20.0, 30.0, 45.0, 90.0):
            z = max(moon_z - rho, 0.0)  # toward the zenith from the moon
            total = dark_cd(z) + moon_sky_nl(rho, z, moon_z, alpha, aerosol) * NL_TO_CD
            no_peak = total - moon_sky_nl(rho, z, moon_z, alpha, aerosol, peak_only=True) * NL_TO_CD
            lim, out_t = crumey_limit(total)
            lim0, out0 = crumey_limit(no_peak)
            flag = " (beyond eq. 53's range)" if out_t else ""
            print("| %4.0f° | %.2f | %.2f%s | %.2f | %.2f |" % (rho, mag_arcsec2(total), lim, flag, lim0, lim0 - lim))
        dark = crumey_limit(dark_cd(0.0))[0]
        print("Moonless zenith limit %.2f." % dark)


if __name__ == "__main__":
    main()
