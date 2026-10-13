"""Independent blend identities, rated-power anchors and closed offline schema checks."""
import math
import unittest

from build_profiles import SPEC, blend, candidate, outputs, schema


class ProfileGenerationTests(unittest.TestCase):
    def test_blend_uses_volume_to_mass_conversion(self):
        p = candidate('glow_2t'); b = blend(p['fuel'])
        self.assertAlmostEqual(b['density_kg_m3'], 856.92)
        self.assertAlmostEqual(b['oil_fraction'], 172.98/856.92)
        self.assertNotAlmostEqual(b['oil_fraction'], .18)

    def test_inert_oil_bound_and_combustible_basis_agree(self):
        b = blend(candidate('glow_4t')['fuel'])
        masses = [.72*792, .10*1137, .18*961]
        energy_per_litre = masses[0]*20e6+masses[1]*11.3e6
        air_per_litre = masses[0]*6.429+masses[1]*1.687
        self.assertAlmostEqual(b['fuel_lhv_j_kg']*(1-b['oil_fraction']), energy_per_litre/sum(masses))
        self.assertAlmostEqual(b['stoich_air_fuel_ratio']*(1-b['oil_fraction']), air_per_litre/sum(masses))

    def test_metric_horsepower_rating_conversion(self):
        for family, ps, rpm in [('glow_2t',1.7,16000.),('glow_4t',1.14,11000.)]:
            p=candidate(family)
            self.assertEqual(p['operation']['rated_power_w']['value'], ps*735.49875)
            self.assertEqual(p['operation']['rated_rpm']['value'], rpm)
            self.assertNotEqual(p['operation']['rated_power_w']['value'], ps*745.6998715822702)

    def test_candidate_cycle_work_reconstructs_the_reference_rating(self):
        # Independent calculation directly from generated rows at the rated speed;
        # do not invoke either production kernel to validate its parameter inference.
        for family in SPEC['families']:
            p=candidate(family); v={k:q['value'] for k,q in p['parameters'].items()}; b=blend(p['fuel'])
            rpm=p['operation']['rated_rpm']['value']
            at=lambda name: dict(v[name])[rpm]
            air=1.225*v['displacement_m3']*(at('delivery_ratio')*at('trapping_efficiency') if family=='glow_2t' else at('volumetric_efficiency'))
            work=air/b['stoich_air_fuel_ratio']*b['fuel_lhv_j_kg']*at('indicated_efficiency')
            angle=math.tau if family=='glow_2t' else 2*math.tau
            pump=(at('scavenge_pressure_pa')*at('delivery_ratio') if family=='glow_2t' else at('pumping_pressure_pa'))*v['displacement_m3']/angle
            loss=at('mechanical_torque_nm')+(0 if family=='glow_2t' else at('valve_torque_nm'))+pump
            brake=(work/angle-loss)*rpm*math.tau/60
            self.assertAlmostEqual(brake,p['operation']['rated_power_w']['value'],places=10)

    def test_family_shapes_are_independently_authored(self):
        two=candidate('glow_2t')['parameters'];four=candidate('glow_4t')['parameters']
        self.assertIn('trapping_efficiency',two);self.assertNotIn('trapping_efficiency',four)
        self.assertIn('valve_torque_nm',four);self.assertNotIn('valve_torque_nm',two)
        self.assertNotEqual(two['indicated_efficiency']['value'],four['indicated_efficiency']['value'])

    def test_profile_status_and_unmeasured_values_remain_explicit(self):
        for family in SPEC['families']:
            p=candidate(family)
            self.assertEqual(p['status'],'candidate')
            self.assertEqual(p['parameters']['mechanical_torque_nm']['kind'],'estimated')
            self.assertIn('ONLY rated-power knot',p['parameters']['indicated_efficiency']['source'])
        self.assertEqual(len(outputs()),4)

    def test_schema_is_closed_and_family_specific(self):
        s=schema()
        self.assertFalse(s['additionalProperties'])
        self.assertEqual(s['properties']['status']['const'],'candidate')
        for branch in s['allOf']:
            family=branch['if']['properties']['family']['const']
            parameters=branch['then']['properties']['parameters']
            self.assertFalse(parameters['additionalProperties'])
            self.assertEqual(set(parameters['required']),set(SPEC['common'])|set(SPEC['families'][family]))


if __name__=='__main__': unittest.main()
