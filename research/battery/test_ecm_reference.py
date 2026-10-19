"""Tests for research/battery/ecm_reference.py (BAT-03 reference of the BAT-04 law).

Run:  python3 -I research/battery/test_ecm_reference.py
  or  python3 -I -m unittest discover -s research/battery -p 'test_*.py'
"""

from __future__ import annotations

import math
import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ecm_reference as ecm  # noqa: E402


def q(value, unit):
    return {"value": value, "unit": unit, "kind": "derived", "source": "unit test"}


def make_template(soc=(0.0, 1.0), temps=(298.15,), ocv=None, r0=None, branches=(), cp=1000.0, ref_ah=1.0,
                  chemistry="lipo"):
    n_t, n_z = len(temps), len(soc)

    def full(v):
        if callable(v):
            return [[v(z, t) for z in soc] for t in temps]
        return [[v] * n_z for _ in range(n_t)]

    return {
        "format": ecm.CELL_FORMAT, "id": "test-cell", "display_name": "test", "chemistry": chemistry, "tier": "C",
        "generator": "test", "provenance": {"fit_report": "none", "inputs": []},
        "reference_capacity_ah": q(ref_ah, "Ah"), "soc_knots": q(list(soc), "1"),
        "temperature_knots_k": q(list(temps), "K"),
        "ocv_v": q(full(ocv if ocv is not None else (lambda z, t: 3.3 + 0.9 * z)), "V"),
        "r0_ohm": q(full(r0 if r0 is not None else 0.01), "ohm"),
        "rc_branches": [{"r_ohm": q(full(r), "ohm"), "tau_s": q(full(tau), "s")} for r, tau in branches],
        "specific_heat_j_per_kg_k": q(cp, "J/(kg·K)"),
        "limits": {"v_max": q(4.2, "V"), "v_cutoff": q(3.0, "V"), "v_damage_floor": q(2.5, "V"),
                   "t_min_k": q(253.15, "K"), "t_max_k": q(333.15, "K")},
    }


def make_pack(template, series=1, parallel=1, rated_ah=1.0, scale=1.0, wiring=0.0, mass=0.1, still=0.5,
              forced=0.2):
    return {
        "format": ecm.PACK_FORMAT, "id": "test-pack", "display_name": "test", "class_note": "test",
        "chemistry": template["chemistry"], "cell_template": {"id": template["id"], "sha256": "0" * 64},
        "series": series, "parallel": parallel, "rated_capacity_ah": q(rated_ah, "Ah"),
        "resistance_scale": q(scale, "1"), "interconnect_resistance_ohm": q(wiring, "ohm"), "mass_kg": q(mass, "kg"),
        "dimensions_m": q([0.1, 0.04, 0.03], "m"),
        "heat_transfer": {"still_air_w_per_k": q(still, "W/K"), "forced_w_per_k_per_sqrt_mps": q(forced, "W/(K·(m/s)^0.5)")},
        "label": {"c_rating_continuous": 30, "c_rating_burst": None, "source": "test"},
    }


class NormalizationAndTables(unittest.TestCase):
    def test_normalization(self):
        tpl = make_template(ref_ah=1.1, branches=[(0.02, 10.0)])
        pack = ecm.normalize(make_pack(tpl, series=4, parallel=2, rated_ah=4.4, scale=0.5, wiring=0.002, mass=0.4,
                                       still=0.3, forced=0.1), tpl)
        self.assertEqual(pack.group_capacity_c, 3600.0 * 4.4)
        self.assertAlmostEqual(pack.resistance_factor, 1.1 / 4.4 * 0.5, places=15)
        self.assertAlmostEqual(pack.thermal_capacity_j_per_k, 400.0, places=12)
        self.assertAlmostEqual(pack.hA(4.0), 0.3 + 0.1 * 2.0, places=15)
        self.assertAlmostEqual(pack.hA(-1.0), 0.3, places=15)

    def test_bilinear_and_clamping(self):
        tbl = ecm.Table((0.0, 0.5, 1.0), (273.15, 298.15), ((1.0, 2.0, 4.0), (3.0, 4.0, 8.0)))
        self.assertAlmostEqual(ecm.lookup(tbl, 0.25, 273.15), 1.5)
        self.assertAlmostEqual(ecm.lookup(tbl, 0.75, 298.15), 6.0)
        self.assertAlmostEqual(ecm.lookup(tbl, 0.25, 285.65), 0.5 * (1.5 + 3.5))
        self.assertEqual(ecm.lookup(tbl, -0.3, 200.0), 1.0)   # z and T clamped, never extrapolated
        self.assertEqual(ecm.lookup(tbl, 1.7, 400.0), 8.0)
        single = ecm.Table((0.0, 1.0), (298.15,), ((1.0, 3.0),))
        self.assertEqual(ecm.lookup(single, 0.5, 100.0), ecm.lookup(single, 0.5, 900.0))

    def test_refusals(self):
        tpl = make_template()
        bad = make_template(ocv=lambda z, t: 4.0 - 0.1 * z)
        with self.assertRaises(ecm.BatteryDataError):
            ecm.normalize(make_pack(bad), bad)
        bad_soc = make_template(soc=(0.0, 0.9))
        with self.assertRaises(ecm.BatteryDataError):
            ecm.normalize(make_pack(bad_soc), bad_soc)
        with self.assertRaises(ecm.BatteryDataError):
            ecm.normalize(make_pack(tpl, series=25), tpl)
        unordered = make_template(branches=[(0.01, 100.0), (0.01, 10.0)])
        with self.assertRaises(ecm.BatteryDataError):
            ecm.normalize(make_pack(unordered), unordered)
        with self.assertRaises(ecm.BatteryDataError):
            ecm.Session(initial_soc=0.2, soc_offset=0.2)


class LawKnownAnswers(unittest.TestCase):
    def test_constant_current_one_rc(self):
        r1, tau, i = 0.03, 20.0, 2.5
        tpl = make_template(ocv=3.7, r0=0.01, branches=[(r1, tau)], ref_ah=10.0)
        pack = ecm.normalize(make_pack(tpl, rated_ah=10.0, wiring=0.001), tpl)
        out = ecm.simulate_current(pack, ecm.Session(), lambda t: i, t_end=100.0, dt=0.1)
        lay = ecm.layout(pack)
        worst = 0.0
        for s in out["samples"][1:]:
            v1 = i * r1 * (1.0 - math.exp(-s.t / tau))
            worst = max(worst, abs(s.state[lay.v_average(0)] - v1) / (i * r1))
            self.assertAlmostEqual(s.voltage_v, 3.7 - (0.01 + 0.001) * i - s.state[lay.v_average(0)], places=13)
        self.assertLess(worst, 1e-10)

    def test_motor_closed_form(self):
        tpl = make_template(branches=[(0.02, 5.0)])
        pack = ecm.normalize(make_pack(tpl, series=4, rated_ah=3.0, scale=0.2, wiring=0.002), tpl)
        session = ecm.Session(initial_soc=0.8, auxiliary_current_a=0.4)
        motor = ecm.Motor(kv_rpm_per_v=800.0, resistance_ohm=0.05)
        y = ecm.reset(pack, session, 290.0)
        y[3] = 0.05
        res = ecm.stage(pack, session, y, ecm.Inputs(rpm=7000.0, duty=0.7, limit=0.9), motor)
        bus = res.voltage_v
        self.assertAlmostEqual(res.motor_current_a, (0.7 * bus - 7000.0 / 800.0) / 0.05, places=9)
        self.assertAlmostEqual(res.current_a, 0.7 * res.motor_current_a + 0.4, places=12)
        self.assertAlmostEqual(bus, res.open_circuit_v - res.path_resistance_ohm * res.current_a, places=12)
        limited = ecm.stage(pack, session, y, ecm.Inputs(rpm=7000.0, duty=0.7, limit=0.3), motor)
        self.assertEqual(limited.duty, 0.3)
        generating = ecm.stage(pack, session, y, ecm.Inputs(rpm=40000.0, duty=0.2), motor)
        self.assertEqual(generating.motor_current_a, 0.0)  # one-quadrant clamp
        disabled = ecm.stage(pack, session, y, ecm.Inputs(rpm=0.0, duty=1.0, enabled=False), motor)
        self.assertEqual(disabled.current_a, 0.4)

    def test_energy_closure_pointwise(self):
        rng = random.Random(7)
        tpl = make_template(soc=(0.0, 0.3, 1.0), temps=(273.15, 313.15),
                            ocv=lambda z, t: 3.2 + 0.9 * z + 0.001 * (t - 273.15),
                            r0=lambda z, t: 0.02 + 0.01 * (1.0 - z) + 0.0002 * (313.15 - t),
                            branches=[(lambda z, t: 0.01 + 0.005 * z, lambda z, t: 5.0 + z),
                                      (lambda z, t: 0.02, lambda z, t: 300.0 + 10.0 * z)])
        pack = ecm.normalize(make_pack(tpl, series=6, rated_ah=5.0, scale=0.3, wiring=0.003), tpl)
        session = ecm.Session(initial_soc=0.9, auxiliary_current_a=0.5, capacity_factor=0.95,
                              resistance_factor=1.4, soc_offset=0.03)
        motor = ecm.Motor(500.0, 0.03)
        lay = ecm.layout(pack)
        for _ in range(200):
            y = ecm.reset(pack, session, 280.0)
            y[lay.charge] *= rng.uniform(0.05, 1.0)
            for k in range(pack.branches):
                y[lay.v_average(k)] = rng.uniform(-0.02, 0.08)
                y[lay.v_weak(k)] = rng.uniform(-0.02, 0.08)
            y[lay.temperature] = rng.uniform(260.0, 320.0)
            res = ecm.stage(pack, session, y, ecm.Inputs(rpm=rng.uniform(0, 8000), duty=rng.uniform(0, 1)), motor)
            source = ((pack.series - 1) * res.ocv_average + res.ocv_weak) * res.current_a
            sink = res.voltage_v * res.current_a + res.loss_w + res.stored_energy_rate_w
            self.assertLess(abs(source - sink), 1e-12 * max(1.0, abs(source)))

    def test_energy_closure_integrated(self):
        tpl = make_template(ocv=3.8, r0=0.015, branches=[(0.01, 3.0), (0.02, 60.0)], ref_ah=2.0)
        pack = ecm.normalize(make_pack(tpl, series=3, rated_ah=2.0, wiring=0.002), tpl)
        session = ecm.Session(auxiliary_current_a=0.3)
        motor = ecm.Motor(900.0, 0.08)
        out = ecm.simulate_motor(pack, session, motor, lambda t: 0.4 + 0.5 * math.sin(0.2 * t) ** 2,
                                 lambda t: 6000.0 + 2000.0 * math.sin(0.1 * t), t_end=120.0, dt=0.01)
        lay = ecm.layout(pack)
        y0, y1 = out["samples"][0].state, out["samples"][-1].state
        drawn = (y0[lay.charge] - y1[lay.charge]) * 3 * 3.8
        stored = 0.0
        for k, (r, tau) in enumerate([(0.01, 3.0), (0.02, 60.0)]):
            c = tau / r
            stored += 3 * 0.5 * c * y1[lay.v_average(k)] ** 2  # (n-1) average cells + 1 weak cell, all equal here
        self.assertLess(abs(drawn - (y1[lay.energy] + y1[lay.loss] + stored)) / drawn, 1e-9)

    def test_rk4_refinement_order(self):
        tpl = make_template(soc=(0.0, 1.0), temps=(273.15, 313.15),
                            ocv=lambda z, t: 3.3 + 0.9 * z + 0.0005 * (t - 273.15),
                            r0=lambda z, t: 0.03 - 0.01 * z - 0.0003 * (t - 273.15),
                            branches=[(lambda z, t: 0.02 - 0.005 * z, lambda z, t: 4.0 + 2.0 * z)])
        pack = ecm.normalize(make_pack(tpl, series=4, rated_ah=1.0, scale=1.0, wiring=0.002, mass=0.2,
                                       still=0.05), tpl)
        session = ecm.Session(auxiliary_current_a=0.2, resistance_factor=1.5, capacity_factor=0.9,
                              voltage_filter_s=0.5)
        motor = ecm.Motor(1000.0, 0.1)

        def run(dt):
            out = ecm.simulate_motor(pack, session, motor, lambda t: 0.8, lambda t: 9000.0, t_end=40.0, dt=dt,
                                     ambient_k=290.0)
            final = out["samples"][-1]
            self.assertLess(final.temperature_k, 313.15)  # stay inside the knots: tables smooth along the path
            return final.state

        a, b, c = run(0.2), run(0.1), run(0.05)
        lay = ecm.layout(pack)
        for idx in (lay.charge, lay.v_average(0), lay.v_weak(0), lay.temperature, lay.energy, lay.loss):
            ratio = abs(a[idx] - b[idx]) / abs(b[idx] - c[idx])
            self.assertTrue(14.0 < ratio < 18.0, f"index {idx}: ratio {ratio}")

    def test_exhaustion_located(self):
        tpl = make_template(ref_ah=1.0, branches=[(0.01, 2.0)])
        pack = ecm.normalize(make_pack(tpl), tpl)
        session = ecm.Session(initial_soc=0.1, capacity_factor=0.8, soc_offset=0.02)
        i = 5.0
        out = ecm.simulate_current(pack, session, lambda t: i, t_end=60.0, dt=0.5)
        expected = (0.1 - 0.02) * 0.8 * 3600.0 / i
        self.assertLess(abs(out["exhausted_at"] - expected), 1e-9)
        last = out["samples"][-1]
        self.assertTrue(last.exhausted)
        self.assertEqual(last.current_a, 0.0)
        self.assertEqual(last.state[0], 0.0)
        res = ecm.stage(pack, session, last.state, ecm.Inputs(), None, True)
        self.assertEqual(last.voltage_v, res.open_circuit_v)

    def test_weak_cell_path_resistance(self):
        tpl = make_template(r0=0.01, branches=[(0.02, 5.0)], ref_ah=2.0)
        pack = ecm.normalize(make_pack(tpl, series=4, rated_ah=4.0, scale=0.5, wiring=0.003), tpl)
        session = ecm.Session(resistance_factor=2.0)
        y = ecm.reset(pack, session, 298.15)
        y[ecm.layout(pack).v_average(0)] = 0.01
        y[ecm.layout(pack).v_weak(0)] = 0.03
        res = ecm.stage(pack, session, y, ecm.Inputs(aux_current_a=2.0))
        s_r = 2.0 / 4.0 * 0.5
        self.assertAlmostEqual(res.path_resistance_ohm, 3 * s_r * 0.01 + 2.0 * s_r * 0.01 + 0.003, places=15)
        lay = ecm.layout(pack)
        self.assertAlmostEqual(res.rates[lay.v_weak(0)], (2.0 * s_r * 0.02 * 2.0 - 0.03) / 5.0, places=15)
        self.assertAlmostEqual(res.rates[lay.v_average(0)], (s_r * 0.02 * 2.0 - 0.01) / 5.0, places=15)

    def test_weak_cell_socs(self):
        tpl = make_template()
        pack = ecm.normalize(make_pack(tpl, series=4, rated_ah=2.0), tpl)
        session = ecm.Session(initial_soc=0.9, capacity_factor=0.8, soc_offset=0.1)
        y = ecm.reset(pack, session, 298.15)
        y[0] -= 0.2 * 3600.0
        res = ecm.stage(pack, session, y, ecm.Inputs())
        self.assertAlmostEqual(res.z_average, 0.9 - 0.2 / 2.0, places=14)
        self.assertAlmostEqual(res.z_weak, (0.8 * 0.8 * 2.0 - 0.2) / (0.8 * 2.0), places=14)


class Supervisor(unittest.TestCase):
    def cfg(self, **kw):
        base = dict(mode="soft", cell_detection="fixed", fixed_cells=4, detection_max_cell_v=None,
                    cutoff_per_cell_v=3.0, soft_limit=0.5, soft_ramp_s=3.0, debounce_s=0.5,
                    recovery="throttle_reset", reset_throttle_max=0.05, voltage_filter_s=0.05)
        base.update(kw)
        return ecm.LowVoltageCutoff(**base)

    def run_seq(self, cfg, volts, throttle, dt):
        st = ecm.SupervisorState(cells=ecm.detect_cells(cfg, 16.0))
        out = []
        for v, u in zip(volts, throttle):
            st = ecm.supervisor_step(cfg, st, v, u, dt)
            out.append(st)
        return out

    def test_debounce_rejects_short_dips(self):
        dt = 1.0 / 240.0
        cfg = self.cfg()
        dip = [11.5] * 100 + [12.5] * 10   # 100 samples = 0.4167 s < 0.5 s
        out = self.run_seq(cfg, dip, [0.8] * len(dip), dt)
        self.assertTrue(all(s.phase in (0, 1) and s.limit == 1.0 for s in out))
        self.assertEqual(out[-1].phase, 0)
        long_dip = [11.5] * 130
        out = self.run_seq(cfg, long_dip, [0.8] * 130, dt)
        first_cut = next(k for k, s in enumerate(out) if s.phase == 2)
        self.assertEqual(first_cut, 119)  # 120 samples x dt = 0.5 s (1 ns tolerance)
        self.assertEqual(out[first_cut].limit, 1.0)
        self.assertEqual(out[first_cut].timer, 0.0)

    def test_soft_ramp_reaches_limit_at_ramp_time(self):
        dt = 1.0 / 240.0
        cfg = self.cfg(debounce_s=0.0, soft_limit=0.6)
        n = 1 + int(round(3.0 / dt)) + 10
        out = self.run_seq(cfg, [11.0] * n, [1.0] * n, dt)
        self.assertEqual(out[0].phase, 2)            # debounce 0: cut on the first low sample
        ramp = out[1:]
        k_end = int(round(3.0 / dt)) - 1              # sample where timer = soft_ramp_s
        self.assertAlmostEqual(ramp[k_end].timer, 3.0, places=9)
        self.assertEqual(ramp[k_end].limit, 0.6)
        self.assertGreater(ramp[k_end - 1].limit, 0.6)
        half = int(round(1.5 / dt)) - 1               # timer = 1.5 s: 1 - 0.4 * 0.5
        self.assertAlmostEqual(ramp[half].limit, 0.8, places=9)
        self.assertTrue(all(s.limit == 0.6 for s in ramp[k_end:]))
        limits = [s.limit for s in ramp]
        self.assertTrue(all(b <= a for a, b in zip(limits, limits[1:])))

    def test_hard_cut_and_timer_frozen(self):
        cfg = self.cfg(mode="hard", debounce_s=0.1)
        out = self.run_seq(cfg, [11.0] * 30, [1.0] * 30, 0.01)
        k = next(i for i, s in enumerate(out) if s.phase == 3)
        self.assertEqual(k, 9)
        self.assertTrue(all(s.limit == 0.0 and s.timer == 0.0 for s in out[k:]))

    def test_throttle_reset_and_latched(self):
        cfg = self.cfg(debounce_s=0.0)
        volts = [11.0] * 5 + [12.4] * 5 + [12.4] * 5
        throttle = [1.0] * 10 + [0.0] * 5
        out = self.run_seq(cfg, volts, throttle, 0.01)
        self.assertEqual(out[9].phase, 2)            # voltage recovered but throttle high: stays in soft cut
        self.assertEqual(out[10].phase, 0)
        self.assertEqual(out[10].limit, 1.0)
        latched = self.run_seq(self.cfg(debounce_s=0.0, recovery="latched", mode="hard"), volts, throttle, 0.01)
        self.assertTrue(all(s.phase == 3 for s in latched))

    def test_mode_off(self):
        out = self.run_seq(self.cfg(mode="off"), [5.0] * 10, [1.0] * 10, 0.01)
        self.assertTrue(all(s.phase == 0 and s.limit == 1.0 for s in out))

    def test_auto_cell_detection(self):
        cfg = self.cfg(cell_detection="auto", fixed_cells=None, detection_max_cell_v=4.35)
        self.assertEqual(ecm.detect_cells(cfg, 4 * 4.35), 4)        # exact multiple guarded by 1e-9
        self.assertEqual(ecm.detect_cells(cfg, 4 * 4.2), 4)
        self.assertEqual(ecm.detect_cells(cfg, 4 * 3.7), 4)
        self.assertEqual(ecm.detect_cells(cfg, 0.5), 1)
        self.assertEqual(ecm.detect_cells(cfg, 3 * 4.2), 3)
        sweep = [ecm.detect_cells(cfg, v / 100.0) for v in range(100, 2700)]
        self.assertTrue(all(b >= a for a, b in zip(sweep, sweep[1:])))

    def test_misdetected_deeply_discharged_4s(self):
        """A 4S pack resting at 3.2 V/cell reads 12.8 V: ceil(12.8/4.35) = 3 cells, so LVC trips too late."""
        tpl = make_template(soc=(0.0, 0.1, 1.0), ocv=lambda z, t: {0.0: 3.0, 0.1: 3.4}.get(z, 4.2), ref_ah=3.2)
        pack = ecm.normalize(make_pack(tpl, series=4, rated_ah=3.2), tpl)
        cfg = self.cfg(cell_detection="auto", fixed_cells=None, detection_max_cell_v=4.35, cutoff_per_cell_v=3.2,
                       debounce_s=0.0, mode="hard")
        full = ecm.reset(pack, ecm.Session(initial_soc=1.0), 298.15)
        self.assertEqual(ecm.supervisor_reset(cfg, full[-1]).cells, 4)
        session = ecm.Session(initial_soc=0.05)
        y = ecm.reset(pack, session, 298.15)
        rest = y[ecm.layout(pack).sensed_voltage]
        self.assertAlmostEqual(rest, 4 * 3.2, places=12)
        st = ecm.supervisor_reset(cfg, rest)
        self.assertEqual(st.cells, 3)
        st = ecm.supervisor_step(cfg, st, rest, 0.5, 0.01)
        self.assertEqual(st.phase, 0)                # 12.8 V >= 3 x 3.2 V: no cut on a pack at 3.2 V/cell
        fixed = self.cfg(fixed_cells=4, cutoff_per_cell_v=3.25, debounce_s=0.0, mode="hard")
        self.assertEqual(ecm.supervisor_step(fixed, ecm.supervisor_reset(fixed, rest), rest, 0.5, 0.01).phase, 3)

    def test_supervisor_in_simulation_zero_order_hold(self):
        tpl = make_template(ocv=lambda z, t: 3.0 + 1.2 * z, r0=0.02, ref_ah=1.0)
        pack = ecm.normalize(make_pack(tpl, series=4, rated_ah=1.0), tpl)
        session = ecm.Session(initial_soc=0.3)
        motor = ecm.Motor(1000.0, 0.05)
        cfg = self.cfg(cutoff_per_cell_v=3.35, debounce_s=0.0, soft_ramp_s=1.0, voltage_filter_s=0.05)
        out = ecm.simulate_motor(pack, session, motor, lambda t: 1.0, lambda t: 10000.0, t_end=5.0, dt=0.01, lvc=cfg)
        samples = out["samples"]
        k = next(i for i, s in enumerate(samples) if s.phase == 2)
        self.assertEqual(samples[k].limit, 1.0)
        self.assertLess(samples[k + 2].limit, 1.0)
        self.assertLessEqual(min(s.limit for s in samples), 1.0)
        self.assertGreaterEqual(min(s.limit for s in samples), 0.5)


if __name__ == "__main__":
    unittest.main(verbosity=1)
