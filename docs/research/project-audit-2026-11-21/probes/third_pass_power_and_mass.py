#!/usr/bin/env python3
"""A36/R3 independent equations: BL coasting battery and RCV nitro mass.

Python arithmetic mirror of the source formula, NOT an executed Godot stage or
an accepted flight. Numbers pinned to the shipped JSON at branch base
9bb1f2c3dac2cead68445161f94513d965d12248.
"""
import math

SHAFT_W = (27., 27., 13., 8.7)
EFFICIENCIES = (.75, .75, .75, .72)
RESPONSE_S = (.14, .14, .14, .12)
OCV_V = 12.6
PACK_R_OHM = .045
PACK_AH = 2.2
REFERENCE_V = 11.8
SPRUNG_KG = 4.952
UNSPRUNG_PER_CORNER_KG = .5186
INITIAL_FUEL_KG = .1
G = 9.80665


def blimp_stage(normalized_speed, throttle):
    assert 0 <= normalized_speed <= 1 and 0 <= throttle <= 1
    # airship_dynamics.gd electrical demand is based on ACTUAL rotor speed
    # without consulting the pilot's new target command.
    requested = sum(p * abs(normalized_speed**3) / eta
                    for p, eta in zip(SHAFT_W, EFFICIENCIES))
    disc = OCV_V**2 - 4. * PACK_R_OHM * requested
    voltage = .5 * (OCV_V + math.sqrt(disc)) if disc > 0 else .5 * OCV_V
    current = (requested / voltage) if disc > 0 else (OCV_V-voltage)/PACK_R_OHM
    supply = voltage / REFERENCE_V  # loaded-voltage cutoff equals 1 at full SOC here
    speed_rates = [(throttle*supply-normalized_speed)/tau for tau in RESPONSE_S]
    return (requested, voltage, current, speed_rates)


def main():
    print("A36 R3 independent algebra only, no Godot or flight execution")
    for n in (0., .25, .5, .75, 1.):
        power, volts, amps, rates = blimp_stage(n, 0.)
        print(f"BL zero command n={n:.2f}: P_request={power:.6f} W, "
              f"V_bus={volts:.6f} V, I_pack={amps:.6f} A, "
              f"dn_port/dt={rates[0]:.6f} 1/s")
        assert n == 0. or (amps > 0 and all(rate < 0 for rate in rates))
    zero=blimp_stage(.5, 0.)
    full=blimp_stage(.5, 1.)
    assert zero[2] == full[2]  # current ignores command at fixed shaft speed
    print(f"BL same n=0.5 throttle 0 vs 1: equal I_pack={zero[2]:.9f} A")
    total = SPRUNG_KG + 4.*UNSPRUNG_PER_CORNER_KG
    print(f"RCV constant nominal mass={total:.6f} kg; fuel used={INITIAL_FUEL_KG:.6f} kg; "
          f"physical full-empty Delta W={INITIAL_FUEL_KG*G:.6f} N; "
          f"fraction={100*INITIAL_FUEL_KG/total:.6f}%")
    assert math.isclose(total, 7.0264)
    assert math.isclose(INITIAL_FUEL_KG*G, .980665)
    print("PASS independent algebra; Godot stage/trajectory regression still REQUIRED.")


if __name__ == "__main__":
    main()
