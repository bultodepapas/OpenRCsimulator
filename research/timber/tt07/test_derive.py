"""Independent geometric and source guards for the Timber authoring pipeline."""
import copy
import json
import unittest
from derive_physics import derive, throw_degrees, HERE
from sensitivity import summary


class TimberAuthoring(unittest.TestCase):
    def test_hinge_circle(self):
        self.assertAlmostEqual(throw_degrees(100, .1), 60, places=12)
        self.assertAlmostEqual(throw_degrees(200, .1), 180, places=12)
        for displacement,radius in [(-1,.1),(201,.1),(1,0)]:
            with self.assertRaises(ValueError):throw_degrees(displacement,radius)

    def test_manual_balance_and_no_airframe_substitution(self):
        model,report=derive()
        self.assertEqual(model['id'],'turbo-lumber-evolution')
        self.assertAlmostEqual(sum(p['mass']['value'] for p in model['inventory']),2.19,places=12)
        self.assertAlmostEqual(report['cg'][0],.06,places=12)
        self.assertEqual(model['capabilities']['flaps'],'not_simulated')
        self.assertIn('NOT measured hardware',model['inventory'][-1]['mass']['source'])
        for field in ['ct_table','cp_table']:
            self.assertEqual(model['propulsion']['propeller'][field]['kind'],'borrowed')
            self.assertIn('two-blade',model['propulsion']['propeller'][field]['source'])

    def test_static_equilibrium_and_estimate_changes(self):
        inputs=json.loads((HERE/'inputs.json').read_text(encoding='utf-8'))
        base=summary(inputs)
        self.assertTrue(0<base['static_current']<70)
        self.assertTrue(0<base['static_rpm']<11840)
        changed=copy.deepcopy(inputs);changed['estimates']['cp_scale']['value']=1.3
        loaded=summary(changed)
        self.assertLess(loaded['static_rpm'],base['static_rpm'])
        self.assertGreater(loaded['static_current'],base['static_current'])
        self.assertEqual(loaded['mass'],base['mass'])


if __name__=='__main__':unittest.main()
