"""Synthetic algebraic checks for the afterburner research report.

Run with python3 analytic_cases.py. These are independent hand-specifiable
examples, not OpenRC code, hardware measurements, or production tests.
"""

from math import ceil, sqrt


def row(label, value):
    print(f"{label}: {value}")


def main():
    # Same captured air and speed, with a specified *gross* nozzle increment.
    air, speed, gross_dry, gross_increment = 0.23, 40.0, 100.0, 20.0
    ram = air * speed
    row("ram_N", f"{ram:.6f}")
    row("dry_net_N", f"{gross_dry - ram:.6f}")
    row("wet_net_N", f"{gross_dry + gross_increment - ram:.6f}")
    row("wet_wrong_extra_ram_N", f"{gross_dry + gross_increment - 2 * ram:.6f}")
    row("wet_wrong_scaled_net_N", f"{(gross_dry - ram) * 1.2:.6f}")

    # Ideal-gas throat comparison, common gamma/R and fixed discharge factor.
    gamma = 1.4
    critical = (2 / (gamma + 1)) ** (gamma / (gamma - 1))
    area_ratio = 1.02 * sqrt(1.5) / 0.95
    row("ideal_gamma_1p4_critical_back_to_total_pressure", f"{critical:.9f}")
    row("ideal_required_throat_ratio", f"{area_ratio:.9f}")

    # Known rectangular wet-force pulse. Dry fuel is zero here only to make
    # the standalone integral explicit; total available fuel is a single store.
    ignition, q_ab, initial_mass, dforce, horizon = 0.3702, 0.020, 0.0072, 20.0, 1.0
    exact_duration = initial_mass / q_ab
    row("exact_ignition_s", f"{ignition:.9f}")
    row("exact_exhaustion_s", f"{ignition + exact_duration:.9f}")
    row("exact_ab_impulse_Ns", f"{dforce * exact_duration:.9f}")
    row("exact_ab_mass_kg", f"{q_ab * exact_duration:.9f}")
    for rate in (240, 480, 960):
        h = 1.0 / rate
        start_step = ceil(ignition / h)
        burn_steps = ceil(exact_duration / h)
        accepted_start = start_step * h
        accepted_stop = (start_step + burn_steps) * h
        assert accepted_stop < horizon
        duration = burn_steps * h
        flow_integral = q_ab * duration
        # A naive implementation caps the reported inventory after using the
        # entire last step. The extra integral exposes the clamp mismatch.
        mismatch = flow_integral - min(initial_mass, flow_integral)
        row(f"{rate}Hz_quantized_start_s", f"{accepted_start:.9f}")
        row(f"{rate}Hz_quantized_cut_s", f"{accepted_stop:.9f}")
        row(f"{rate}Hz_ab_impulse_Ns", f"{dforce * duration:.9f}")
        row(f"{rate}Hz_flow_minus_depletion_kg", f"{mismatch:.9f}")

    # FRD: +x forward, +y right, +z down. Positive M_y rotates x toward -z.
    z_nozzle, cg_initial, cg_after = 0.05, 0.0, 0.01
    row("dry_pitch_moment_Nm", f"{(z_nozzle - cg_initial) * 100.0:.6f}")
    row("wet_initial_cg_pitch_moment_Nm", f"{(z_nozzle - cg_initial) * 120.0:.6f}")
    row("wet_shifted_cg_pitch_moment_Nm", f"{(z_nozzle - cg_after) * 120.0:.6f}")

    # Both effective gain-flow pairs fit identical thrust but burn differently.
    row("identifiability_case_1_N", f"{1000.0 * 0.020:.6f}")
    row("identifiability_case_2_N", f"{500.0 * 0.040:.6f}")


if __name__ == "__main__":
    main()
