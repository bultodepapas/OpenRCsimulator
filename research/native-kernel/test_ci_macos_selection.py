"""Portable handoff checks; no Godot, compiler or native process is executed."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('ci_selection_driver', HERE/'ci_macos.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)

OLD = 'apple-clang-2100.3.34.2-sdk-27.0'
NEW = 'apple-clang-2100.4.1.1-sdk-27.2'


class SelectionHandoffTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.godot = self.root/'never-executed-godot'
        self.godot.write_text('fixture, not an executable')
        self.out = self.root/'tmp/run'
        self.policy = ci.engine_policy()

    def research_flags(self):
        args = ['--research-engine-sha256','ab'*32,
                '--research-engine-cli-version','4.8.beta2.openrc_metalfx',
                '--research-engine-runtime-version','4.8-beta2 (openrc_metalfx)',
                '--research-engine-build-receipt',str(self.root/'editor receipt.json'),
                '--research-engine-archive',str(self.root/'source.zip'),
                '--research-engine-extension-api',str(self.root/'extension_api-4-7.json'),
                '--research-engine-reference-godot',str(self.root/'official Godot'),
                '--research-engine-toolchain-profile',NEW]
        for index in range(1,20):
            args += ['--research-engine-patch',str(self.root/f'{index:04d} patch.patch')]
        return args

    def invoke(self, extra, *, fail_identity=False, inherited=None):
        calls = []
        events = []

        def fake_run(command, label, logs, env):
            events.append(label)
            calls.append((label,list(command),dict(env)))
            if label == 'domain-guard':
                check = self.out/'guard-check/checked'
                check.mkdir(parents=True)
                log = check/'engine.log'
                log.write_text('MACOS_DOMAIN_GUARD verdict=pass checks=72\n')
                (check/'report.json').write_text(json.dumps({'log':str(log)}))

        def identify(godot, lock, selection):
            events.append('verify-engine')
            if fail_identity:
                raise ValueError('selected engine hash differs')
            return {'fixture':'verified-engine', 'research_engine':selection}

        def toolchain(profile):
            events.append('verify-toolchain')
            return {'profile':profile}

        builder = SimpleNamespace(locked=SimpleNamespace(load_lock=lambda:{}),
                                  godot_identity=identify, host_toolchain=toolchain)
        builder_spec = SimpleNamespace(loader=SimpleNamespace(exec_module=lambda module:None))
        with mock.patch.object(ci,'ROOT',self.root), mock.patch.object(ci,'engine_policy',return_value=self.policy), \
             mock.patch.object(ci,'oracle_commands',return_value=[('base_oracle','oracle.gd',[])]), \
             mock.patch.object(ci,'run',side_effect=fake_run), \
             mock.patch.object(ci.importlib.util,'spec_from_file_location',return_value=builder_spec), \
             mock.patch.object(ci.importlib.util,'module_from_spec',return_value=builder), \
             mock.patch.dict(os.environ,inherited or {},clear=True), \
             mock.patch.object(sys,'argv',['ci_macos.py','--godot',str(self.godot),'--out',str(self.out),*extra]), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            result = ci.main()
        self.assertEqual(result,1 if fail_identity else 0)
        self.assertEqual(events[:2],['verify-toolchain','verify-engine'])
        if fail_identity:
            self.assertEqual(calls,[])
        else:
            self.assertEqual(events[2],'prepare-before')
        return calls

    def test_legacy_default_does_not_invent_research_selection(self):
        calls = self.invoke([])
        for label, command, env in calls:
            self.assertFalse(any(arg.startswith('--research-engine-') for arg in command), label)
        by_label = {label:command for label,command,_ in calls}
        for label in ('build-candidate','build-mutant','fpcr-control','install'):
            command = by_label[label]
            self.assertEqual(command[command.index('--toolchain-profile')+1],OLD)

    def test_full_selection_and_independent_profiles_reach_every_identity_consumer(self):
        flags = self.research_flags()
        calls = self.invoke([*flags,'--toolchain-profile',OLD])
        by_label = {label:command for label,command,_ in calls}
        for label in ('build-candidate','build-mutant','fpcr-control','install'):
            command = by_label[label]
            index = command.index('--research-engine-sha256')
            self.assertEqual(command[index:index+len(flags)],flags,label)
            self.assertEqual(command[command.index('--toolchain-profile')+1],OLD)
            self.assertEqual(command[command.index('--research-engine-toolchain-profile')+1],NEW)
        for label in ('oracle-base-oracle','domain-guard','installed-stage','installed-lifecycle','installed-replay'):
            command = by_label[label]
            self.assertFalse(any(arg.startswith('--research-engine-') for arg in command),label)
            self.assertNotIn('--toolchain-profile',command,label)

    def test_native_profile_can_change_without_a_research_engine(self):
        calls = self.invoke(['--toolchain-profile',NEW])
        for label,command,_ in calls:
            if label in ('build-candidate','build-mutant','fpcr-control','install'):
                self.assertEqual(command[command.index('--toolchain-profile')+1],NEW)
            self.assertFalse(any(arg.startswith('--research-engine-') for arg in command),label)

    def test_partial_selection_is_refused_before_any_child_or_output(self):
        with self.assertRaises(SystemExit):
            self.invoke(['--research-engine-sha256','ab'*32])
        self.assertFalse(self.out.exists())

    def test_mismatched_engine_is_refused_before_prepare_or_import(self):
        self.invoke(self.research_flags(),fail_identity=True)
        self.assertFalse((self.out/'before').exists())

    def test_research_direct_children_do_not_inherit_sanitizer_overrides(self):
        calls = self.invoke(self.research_flags(),inherited={'ASAN_OPTIONS':'unsupported',
                            'UBSAN_OPTIONS':'unsupported','PRESERVED_FIXTURE_VALUE':'yes'})
        for label,command,env in calls:
            self.assertNotIn('ASAN_OPTIONS',env,label)
            self.assertNotIn('UBSAN_OPTIONS',env,label)
            self.assertEqual(env['PRESERVED_FIXTURE_VALUE'],'yes')

    def test_official_lane_preserves_its_existing_environment(self):
        calls = self.invoke([],inherited={'ASAN_OPTIONS':'existing-official-setting'})
        self.assertTrue(calls)
        self.assertTrue(all(env['ASAN_OPTIONS']=='existing-official-setting' for _,_,env in calls))


if __name__ == '__main__':
    unittest.main()
