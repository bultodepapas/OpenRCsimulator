#!/usr/bin/env python3
"""G1a1 synthetic parser, precision, provenance and command-line regressions."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('uiuc_import', HERE/'import_table.py')
IMP = importlib.util.module_from_spec(spec)
spec.loader.exec_module(IMP)
STATIC = b'RPM CT CP\n2000 0.1 0.05\n4000 0.11 0.04\n'


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((HERE/'example.synthetic.json').read_text())
        self.raw = (HERE/'example.synthetic.txt').read_bytes()

    def run_import(self, raw=None, kind='tunnel', manifest=None):
        raw = self.raw if raw is None else raw
        m = copy.deepcopy(self.manifest if manifest is None else manifest)
        m['source_sha256'] = hashlib.sha256(raw).hexdigest()
        m['table_kind'] = kind
        if kind == 'static':m['run_rpm_label'] = None
        return IMP.import_table(json.dumps(m).encode(), raw)

    def test_sorted_signed_knots_and_duplicate_provenance(self):
        r = self.run_import()
        self.assertEqual(r['normalization'], {'input_rows':4,'unique_rows':3,'duplicate_rows_collapsed':1,'reordered':True})
        self.assertEqual([k['j'] for k in r['knots']], [0.2,0.4,0.6])
        self.assertEqual(r['knots'][1]['source_lines'], [4,5])
        self.assertEqual((r['knots'][-1]['ct'], r['knots'][-1]['cp']), (-0.01,-0.02))
        self.assertEqual(r['coordinate_extent'], [0.2,0.6])
        self.assertIsNone(r['per_row_rpm_extent'])
        self.assertTrue(all(k['rpm'] is None for k in r['knots']))
        self.assertIsNone(r['source']['coefficient_reference_diameter'])

    def test_static_measured_column_not_fixed_run_label(self):
        r = self.run_import(STATIC, 'static')
        self.assertEqual(r['per_row_rpm_extent'], [2000,4000])
        self.assertEqual(r['coordinate_axis'], 'rpm')
        self.assertTrue(all(k['j']==0 and k['eta'] is None for k in r['knots']))
        self.assertFalse(r['normalization']['reordered'])

    def test_numeric_duplicate_not_lexical_duplicate(self):
        raw = b'J CT CP eta\n.2 .1 .05 .4\n2e-1 1e-1 .050 4e-1\n.4 .04 .03 .5\n'
        r = self.run_import(raw)
        self.assertEqual(r['normalization']['duplicate_rows_collapsed'], 1)
        self.assertEqual(r['knots'][0]['source_lines'], [2,3])

    def test_conflicting_coordinate_refused_including_decimal_late_digits(self):
        for row in [b'.2 .2 .05 .4', b'.2 .1 .06 .4', b'.2 .1 .05 .5', b'.2 .10000000000000000001 .05 .4']:
            raw = b'J CT CP eta\n.2 .1 .05 .4\n'+row+b'\n.4 .05 .03 .6\n'
            with self.subTest(row=row), self.assertRaisesRegex(ValueError, 'conflicting'):
                self.run_import(raw)

    def test_distinct_axes_collapsing_to_same_float_refused(self):
        raw=b'J CT CP eta\n0.2 .1 .05 .4\n0.20000000000000000001 .1 .05 .4\n'
        with self.assertRaisesRegex(ValueError, 'collapse in float64'):self.run_import(raw)

    def test_underflow_overflow_and_nonfinite_refused(self):
        for token in [b'NaN',b'inf',b'-Infinity',b'1e999',b'1e-999',b'1_000',b'0x10',b'1,2']:
            raw = b'J CT CP eta\n.2 '+token+b' .05 .4\n.4 .05 .03 .6\n'
            with self.subTest(token=token), self.assertRaises(ValueError):self.run_import(raw)

    def test_negative_and_superunit_eta_are_preserved(self):
        raw = b'J CT CP eta\n.2 -.1 -.05 -2\n.4 .4 .03 1.2\n'
        self.assertEqual([k['eta'] for k in self.run_import(raw)['knots']], [-2,1.2])

    def test_wrong_header_and_row_shapes_refused(self):
        for raw in [b'<html>failure</html>',b'J CT CQ eta\n.2 .1 .05 .4\n.4 .05 .03 .6\n',
                    b'J CT CP eta\n.2 .1 .05\n.4 .05 .03 .6\n',b'J CT CP eta\n.2 .1 .05 .4 extra\n',
                    b'J CT CP eta\n# a comment is not a data row\n',b'',b'J CT CP eta\n.2 .1 .05 .4\n']:
            with self.subTest(raw=raw), self.assertRaises(ValueError):self.run_import(raw)

    def test_positive_static_rpm_nonnegative_j(self):
        for raw,kind in [(STATIC.replace(b'2000',b'0'),'static'),(STATIC.replace(b'2000',b'-2'),'static'),
                         (self.raw.replace(b'0.2',b'-0.2'),'tunnel')]:
            with self.assertRaisesRegex(ValueError, 'domain'):self.run_import(raw,kind)

    def test_blank_lines_keep_original_line_numbers(self):
        raw = b'\nJ CT CP eta\r\n\r\n.2 .1 .05 .4\r\n.4 .04 .03 .5\r\n'
        r = self.run_import(raw)
        self.assertEqual([k['source_lines'] for k in r['knots']], [[4],[5]])

    def test_full_file_duplicates_and_backward_tail(self):
        raw=b'J CT CP eta\n.2 .1 .05 .4\n.65 -.005 .006 -.5\n.64 -.004 .007 -.4\n.64 -.004 .007 -.4\n.2 .1 .05 .4\n'
        r=self.run_import(raw)
        self.assertTrue(r['normalization']['reordered'])
        self.assertEqual(r['normalization']['duplicate_rows_collapsed'],2)
        self.assertEqual(r['knots'][0]['source_lines'],[2,6])
        self.assertEqual(r['knots'][1]['source_lines'],[4,5])

    def test_run_label_is_optional_and_never_becomes_measured_coverage(self):
        for label in [None,{'value':10000,'unit':'rpm','source':'Nominal label only'}]:
            self.manifest['run_rpm_label']=label
            r=self.run_import()
            self.assertIsNone(r['per_row_rpm_extent'])
            self.assertTrue(all(k['rpm'] is None for k in r['knots']))
            self.assertEqual(r['source']['run_rpm_label'],label)

    def test_unknown_diameter_stays_unknown_and_known_reference_preserved(self):
        self.assertIsNone(self.run_import()['source']['coefficient_reference_diameter'])
        value={'value':0.303,'unit':'m','kind':'synthetic','source':'Invented coefficient-reference diameter, not catalog size'}
        self.manifest['coefficient_reference_diameter']=value
        self.assertEqual(self.run_import()['source']['coefficient_reference_diameter'],value)
        self.manifest['evidence']='measured-source'
        with self.assertRaisesRegex(ValueError,'synthetic diameter'):self.run_import()

    def test_hash_binds_exact_bytes_before_parsing(self):
        raw=(HERE/'example.synthetic.json').read_bytes()
        r=IMP.import_table(raw,self.raw)
        self.assertEqual(r['input_sha256']['manifest'],hashlib.sha256(raw).hexdigest())
        with self.assertRaisesRegex(ValueError,'SHA-256 mismatch'):IMP.import_table(raw,self.raw+b'\n')
        with self.assertRaisesRegex(ValueError,'SHA-256 mismatch'):IMP.import_table(raw,b'garbage')

    def test_manifest_shape_and_provenance_refused(self):
        for group in [None,'propeller','run_rpm_label']:
            for mode in ['extra','missing']:
                m=copy.deepcopy(self.manifest);node=m if group is None else m[group]
                if mode=='extra':node['extra']=1
                else:node.pop(next(iter(node)))
                with self.subTest(group=group,mode=mode),self.assertRaises(ValueError):self.run_import(manifest=m)
        for key,value in [('source_sha256','x'),('source_url','file:///tmp/source'),('evidence','predicted'),('notes','')]:
            m=copy.deepcopy(self.manifest);m[key]=value
            with self.assertRaises(ValueError):IMP.validate(m)
        for value in [True,-1,0,float('inf'),'6000']:
            m=copy.deepcopy(self.manifest);m['run_rpm_label']['value']=value
            with self.assertRaises(ValueError):self.run_import(manifest=m)

    def test_static_label_and_nonfinite_json_refused(self):
        m=copy.deepcopy(self.manifest);m['table_kind']='static'
        with self.assertRaisesRegex(ValueError,'static sweep'):IMP.validate(m)
        for raw in [b'{"a":1,"a":2}',b'{"a":NaN}',b'{"a":Infinity}']:
            with self.assertRaises(ValueError):IMP.decode(raw)

    def test_repeatability_and_no_input_mutation(self):
        before=copy.deepcopy(self.manifest)
        self.assertEqual(self.run_import(),self.run_import())
        self.assertEqual(before,self.manifest)

    def test_cli_identity_and_rejection_without_report(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);m=root/'manifest.json';p=root/'table.txt'
            m.write_bytes((HERE/'example.synthetic.json').read_bytes());p.write_bytes(self.raw)
            cmd=[sys.executable,str(HERE/'import_table.py'),str(m),str(p)]
            first=subprocess.run(cmd,text=True,capture_output=True,timeout=10)
            second=subprocess.run(cmd,text=True,capture_output=True,timeout=10)
            self.assertEqual(first.returncode,0,first.stderr)
            self.assertEqual(first.stdout,second.stdout)
            result=json.loads(first.stdout)
            self.assertEqual(result['importer_sha256'],hashlib.sha256((HERE/'import_table.py').read_bytes()).hexdigest())
            p.write_bytes(self.raw+b'\n')
            failed=subprocess.run(cmd,text=True,capture_output=True,timeout=10)
            self.assertEqual(failed.returncode,1)
            self.assertEqual(failed.stdout,'')
            self.assertIn('SHA-256 mismatch',failed.stderr)
            self.assertEqual(p.read_bytes(),self.raw+b'\n')


if __name__=='__main__':unittest.main(verbosity=2)
