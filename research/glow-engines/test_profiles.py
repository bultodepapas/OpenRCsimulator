"""Independent blend identities, rated-power anchors and closed offline schema checks."""
import math
import unittest

from build_profiles import ENGINES, SPEC, blend, candidate, outputs, schema


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

    def test_slider_crank_inputs_have_manufacturer_dimensions_and_explicit_common_estimates(self):
        expected = {
            'glow_2t': (.023, .0215, .404, 'https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/15610.htm'),
            'glow_4t': (.025, .0213, .442, 'https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html'),
        }
        for family, (bore, stroke, dry_mass, source) in expected.items():
            params = candidate(family)['parameters']
            self.assertEqual(params['bore_m']['value'], bore)
            self.assertEqual(params['stroke_m']['value'], stroke)
            self.assertEqual(params['bore_m']['kind'], 'manual')
            self.assertEqual(params['stroke_m']['kind'], 'manual')
            self.assertIn(source, params['bore_m']['source'])
            self.assertIn(source, params['stroke_m']['source'])
            self.assertAlmostEqual(math.pi * bore*bore*stroke/4, params['displacement_m3']['value'], delta=params['displacement_m3']['value']*.005)
            self.assertEqual(params['rod_to_crank_radius_ratio']['value'], 3.5)
            self.assertEqual(params['rod_to_crank_radius_ratio']['kind'], 'estimated')
            self.assertIn('unmeasured', params['rod_to_crank_radius_ratio']['source'])
            self.assertAlmostEqual(params['reciprocating_mass_kg']['value'], .025*dry_mass)
            self.assertEqual(params['reciprocating_mass_kg']['kind'], 'estimated')
            self.assertIn('1–5% sensitivity', params['reciprocating_mass_kg']['source'])
        self.assertNotEqual(expected['glow_2t'][2], expected['glow_4t'][2])

    def test_profile_status_and_unmeasured_values_remain_explicit(self):
        for engine in ENGINES:
            p=candidate(engine)
            self.assertEqual(p['status'],'candidate')
            self.assertEqual(p['parameters']['mechanical_torque_nm']['kind'],'estimated')
            self.assertIn('ONLY rated-power knot',p['parameters']['indicated_efficiency']['source'])
        self.assertEqual(len(outputs()),2+len(ENGINES))

    def test_61fx_scales_the_55ax_by_displacement(self):
        fx,ax=candidate('os_max_61fx_candidate'),candidate('os_max_55ax_candidate')
        self.assertEqual(fx['family'],'glow_2t')
        self.assertEqual((fx['parameters']['bore_m']['value'],fx['parameters']['stroke_m']['value']),(.024,.022))
        self.assertAlmostEqual(fx['operation']['rated_power_w']['value'],1.9*735.49875,9)
        k=9.95/8.93
        for (r,a),(_,b) in zip(fx['parameters']['mechanical_torque_nm']['value'],ax['parameters']['mechanical_torque_nm']['value']):
            self.assertAlmostEqual(a,b*k,12)
        self.assertIn('NITRO-61FX',fx['parameters']['indicated_efficiency']['source'])

    def test_schema_is_closed_and_family_specific(self):
        s=schema()
        self.assertFalse(s['additionalProperties'])
        self.assertEqual(s['properties']['status']['const'],'candidate')
        for branch in s['allOf']:
            family=branch['if']['properties']['family']['const']
            parameters=branch['then']['properties']['parameters']
            self.assertFalse(parameters['additionalProperties'])
            self.assertEqual(set(parameters['required']),set(SPEC['common'])|set(SPEC['families'][family]))
        for key in ['bore_m', 'stroke_m', 'reciprocating_mass_kg']:
            self.assertTrue(SPEC['common'][key]['positive'])
        self.assertEqual(SPEC['common']['rod_to_crank_radius_ratio']['minimum'], 2.0)


if __name__=='__main__': unittest.main()
