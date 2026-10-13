"""Analytic and cross-formulation fixtures for AV-10b's mass dynamics."""

from __future__ import annotations

import math
import unittest

from variable_mass_reference import (
    BodyState,
    Component,
    MassProperties,
    Outflow,
    Wrench,
    ZERO,
    add,
    combine_components,
    cross,
    is_positive_definite,
    is_symmetric,
    mass_property_rates,
    mat_scale,
    mat_vec,
    origin_position_for_constant_body_twist,
    rotate_exp,
    scale,
    solve_current_cg,
    solve_fixed_datum,
    sub,
    geometric_cg_position_rate_body,
)


def assert_vec_close(test: unittest.TestCase, actual, expected, tol: float = 2e-10) -> None:
    for got, want in zip(actual, expected):
        test.assertAlmostEqual(got, want, delta=tol)


class VariableMassReferenceTests(unittest.TestCase):
    def test_constant_net_thrust_matches_logarithmic_variable_mass_fixture(self) -> None:
        # The engine force is already net thrust.  Liquid inventory is removed
        # co-moving at O, so there is no second rocket/exhaust term.
        m0 = 10.0
        k = 0.4
        duration = 4.0
        force_x = 30.0
        inertia = ((1.0, 0.0, 0.0), (0.0, 1.4, 0.0), (0.0, 0.0, 1.8))
        flow = (Outflow(k, ZERO),)

        def acceleration(t: float, velocity):
            mass = m0 - k * t
            props = MassProperties(mass, ZERO, inertia)
            state = BodyState(velocity, ZERO)
            result = solve_fixed_datum(
                props,
                state,
                Wrench((force_x, 0.0, 0.0), ZERO),
                flow,
            )
            return result.origin_velocity_dot

        # RK4 integrates the reference kernel itself, with stage-local mass.
        steps = 400
        dt = duration / steps
        velocity = ZERO
        for index in range(steps):
            t = index * dt
            k1 = acceleration(t, velocity)
            k2 = acceleration(t + 0.5 * dt, add(velocity, scale(0.5 * dt, k1)))
            k3 = acceleration(t + 0.5 * dt, add(velocity, scale(0.5 * dt, k2)))
            k4 = acceleration(t + dt, add(velocity, scale(dt, k3)))
            increment = add(add(k1, scale(2.0, k2)), add(scale(2.0, k3), k4))
            velocity = add(velocity, scale(dt / 6.0, increment))

        final_mass = m0 - k * duration
        expected = (force_x / k) * math.log(m0 / final_mass)
        self.assertAlmostEqual(velocity[0], expected, delta=2e-10)
        assert_vec_close(self, velocity[1:], (0.0, 0.0), 2e-12)

    def test_comoving_outflow_causes_no_translation_or_spin(self) -> None:
        # With zero relative outlet speed, uniform body translation is simply
        # carried away with the mass; it creates no thrust by itself.
        props = combine_components(
            (
                Component(4.0, (0.1, -0.2, 0.05), ((1.4, 0.0, 0.0), (0.0, 1.7, 0.0), (0.0, 0.0, 1.2))),
                Component(1.3, (0.7, 0.3, -0.1), ((0.02, 0.0, 0.0), (0.0, 0.03, 0.0), (0.0, 0.0, 0.02))),
            )
        )
        state = BodyState((13.0, -4.0, 2.0), ZERO)
        flows = (Outflow(0.08, (0.7, 0.3, -0.1)),)
        result = solve_fixed_datum(props, state, Wrench(ZERO, ZERO), flows)
        assert_vec_close(self, result.origin_velocity_dot, ZERO, 2e-12)
        assert_vec_close(self, result.angular_velocity_dot, ZERO, 2e-12)

    def test_uniform_rotating_annulus_has_no_spurious_spin_up(self) -> None:
        # Four equal azimuthal ports are the exact second moments of a uniform
        # thin annulus.  This keeps the declining mass distribution consistent
        # with the outgoing angular-momentum flux.
        radius = 0.62
        fuel_mass = 2.5
        outflow_rate = 0.3
        omega_z = 8.0
        annulus_i_per_kg = (
            (0.5 * radius * radius, 0.0, 0.0),
            (0.0, 0.5 * radius * radius, 0.0),
            (0.0, 0.0, radius * radius),
        )
        fuel_i = mat_scale(fuel_mass, annulus_i_per_kg)
        props = combine_components(
            (
                Component(4.0, ZERO, ((1.2, 0.0, 0.0), (0.0, 1.4, 0.0), (0.0, 0.0, 1.5))),
                Component(fuel_mass, ZERO, fuel_i),
            )
        )
        points = ((radius, 0.0, 0.0), (-radius, 0.0, 0.0), (0.0, radius, 0.0), (0.0, -radius, 0.0))
        flows = tuple(Outflow(outflow_rate / len(points), p) for p in points)
        omega = (0.0, 0.0, omega_z)

        _, _, inertia_dot = mass_property_rates(flows)
        angular_flux = ZERO
        for flow in flows:
            angular_flux = add(
                angular_flux,
                scale(flow.mass_rate, cross(flow.position, cross(omega, flow.position))),
            )
        assert_vec_close(self, add(mat_vec(inertia_dot, omega), angular_flux), ZERO, 2e-12)

        result = solve_fixed_datum(props, BodyState(ZERO, omega), Wrench(ZERO, ZERO), flows)
        assert_vec_close(self, result.origin_velocity_dot, ZERO, 2e-12)
        assert_vec_close(self, result.angular_velocity_dot, ZERO, 2e-12)

    def test_off_axis_pickup_matches_current_cg_form_and_open_balance(self) -> None:
        # Dry structure, tank shell, and a liquid parcel have distinct off-axis
        # centers.  The liquid parcel is removed at its body-fixed pickup.
        pickup = (0.76, 0.18, -0.04)
        dry_i = ((2.2, 0.11, -0.07), (0.11, 2.6, 0.08), (-0.07, 0.08, 1.9))
        shell_i = ((0.05, 0.002, 0.0), (0.002, 0.07, -0.001), (0.0, -0.001, 0.06))
        props = combine_components(
            (
                Component(5.4, (0.12, -0.08, 0.04), dry_i),
                Component(0.7, (0.55, 0.22, -0.07), shell_i),
                Component(1.1, pickup, ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0))),
            )
        )
        self.assertTrue(is_symmetric(props.inertia_origin))
        self.assertTrue(is_symmetric(props.inertia_center))
        self.assertTrue(is_positive_definite(props.inertia_center))

        state = BodyState((3.2, -1.4, 0.7), (0.8, -0.4, 1.1))
        net_thrust = (22.0, 0.5, -0.2)
        nozzle = (1.05, -0.16, 0.12)
        other_moment = (0.4, -0.3, 0.8)
        moment_o = add(cross(nozzle, net_thrust), other_moment)
        wrench = Wrench(net_thrust, moment_o)
        flows = (Outflow(0.17, pickup, (0.015, -0.02, 0.01)),)

        fixed = solve_fixed_datum(props, state, wrench, flows)
        moving = solve_current_cg(props, state, wrench, flows)
        c_dot = moving.center_dot
        c = props.center
        transformed_momentum_velocity_dot = add(
            add(fixed.origin_velocity_dot, cross(fixed.angular_velocity_dot, c)),
            cross(state.angular_velocity, c_dot),
        )
        assert_vec_close(self, moving.momentum_velocity_dot, transformed_momentum_velocity_dot, 3e-10)
        assert_vec_close(self, moving.angular_velocity_dot, fixed.angular_velocity_dot, 3e-10)

        # Independently reconstruct Reynolds-transport force and moment from
        # the solved derivatives, including absolute outlet momentum.
        mass_dot, first_dot, inertia_dot = mass_property_rates(flows)
        v = state.origin_velocity
        omega = state.angular_velocity
        momentum = add(scale(props.mass, v), cross(omega, props.first_moment))
        angular_momentum_o = add(cross(props.first_moment, v), mat_vec(props.inertia_origin, omega))
        momentum_dot = add(
            add(scale(mass_dot, v), scale(props.mass, fixed.origin_velocity_dot)),
            add(cross(fixed.angular_velocity_dot, props.first_moment), cross(omega, first_dot)),
        )
        angular_momentum_dot = add(
            add(cross(first_dot, v), cross(props.first_moment, fixed.origin_velocity_dot)),
            add(mat_vec(inertia_dot, omega), mat_vec(props.inertia_origin, fixed.angular_velocity_dot)),
        )
        force_balance = add(momentum_dot, cross(omega, momentum))
        moment_balance = add(
            add(angular_momentum_dot, cross(omega, angular_momentum_o)),
            cross(v, momentum),
        )
        for flow in flows:
            outlet_velocity = add(add(v, cross(omega, flow.position)), flow.relative_velocity)
            force_balance = add(force_balance, scale(flow.mass_rate, outlet_velocity))
            moment_balance = add(moment_balance, scale(flow.mass_rate, cross(flow.position, outlet_velocity)))
        assert_vec_close(self, force_balance, wrench.force, 4e-10)
        assert_vec_close(self, moment_balance, wrench.moment_origin, 4e-10)

        # The nozzle force is already net engine thrust: its one moment is
        # computed at the nozzle, then shifted to C by -c x F in the CG form.
        expected_thrust_moment_c = cross(sub(nozzle, c), net_thrust)
        actual_thrust_moment_c = sub(cross(nozzle, net_thrust), cross(c, net_thrust))
        assert_vec_close(self, actual_thrust_moment_c, expected_thrust_moment_c, 2e-12)

    def test_exact_geometric_cg_position_rate_contains_center_rate(self) -> None:
        c = (0.34, -0.16, 0.09)
        c_dot = (-0.07, 0.02, 0.03)
        state = BodyState((2.2, -1.1, 0.8), (0.9, -0.5, 1.3))
        expected = geometric_cg_position_rate_body(state, c, c_dot)
        momentum_velocity = add(state.origin_velocity, cross(state.angular_velocity, c))
        assert_vec_close(self, sub(expected, momentum_velocity), c_dot, 2e-12)

        # Finite-difference x_C(t) = x_O(t) + R(t)c(t) under a constant body
        # twist and locally constant c_dot.  The formula includes both omega
        # cross c and the changing inventory center.
        h = 1e-5

        def cg_position(t: float):
            origin = origin_position_for_constant_body_twist(state.origin_velocity, state.angular_velocity, t)
            center_t = add(c, scale(t, c_dot))
            return add(origin, rotate_exp(center_t, state.angular_velocity, t))

        finite_difference = scale(1.0 / (2.0 * h), sub(cg_position(h), cg_position(-h)))
        assert_vec_close(self, finite_difference, expected, 2e-9)


if __name__ == "__main__":
    unittest.main()
