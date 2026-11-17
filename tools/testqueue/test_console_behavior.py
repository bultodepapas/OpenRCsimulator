"""Portable flag/IO tests and an isolated native Windows process-ownership test."""
from contextlib import redirect_stdout
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest import mock

from tools.debug import debugctl
from tools.godot import run_checked as runner
from tools.testqueue import common, processes, pool, snapshots, collection

NO_WINDOW = 0x08000000

class PlatformProxy:
    def __init__(self, target, name):
        self._target, self.name = target, name
    def __getattr__(self, key):
        return getattr(self._target, key)

class ConsolePolicyTests(unittest.TestCase):
    def test_isolated_gate_requests_no_console_and_preserves_exit(self):
        child = mock.Mock()
        child.wait.return_value = 7
        fake_stdin = SimpleNamespace(buffer=io.BytesIO(b'1'))
        with mock.patch.object(sys, 'stdin', fake_stdin), \
             mock.patch.object(sys, 'argv', ['gate', 'fake', 'argument']), \
             mock.patch.object(subprocess, 'CREATE_NO_WINDOW', NO_WINDOW, create=True), \
             mock.patch.object(subprocess, 'Popen', return_value=child) as spawn:
            with self.assertRaises(SystemExit) as ended:
                exec(processes._WINDOWS_GATE, {'__name__': '__main__'})
        self.assertEqual(ended.exception.code, 7)
        self.assertEqual(spawn.call_args.args[0], ['fake', 'argument'])
        self.assertEqual(spawn.call_args.kwargs['creationflags'], NO_WINDOW)
        self.assertIs(spawn.call_args.kwargs['stdin'], subprocess.DEVNULL)
        self.assertTrue(spawn.call_args.kwargs['close_fds'])

    def test_checked_runner_options_and_captured_output(self):
        real_popen = subprocess.Popen
        seen = []
        def capture(*args, **kwargs):
            seen.append(dict(kwargs))
            # Simulate Windows selection on POSIX while letting a fake child run.
            if os.name != 'nt':
                kwargs.pop('creationflags')
            return real_popen(*args, **kwargs)
        with tempfile.TemporaryDirectory(prefix='console-runner-') as directory, \
             mock.patch.object(runner, 'os', PlatformProxy(os, 'nt')), \
             mock.patch.object(common, 'enabled', return_value=False), \
             mock.patch.dict(os.environ, {'OPENRC_TESTPOOL_CONFIG': '', 'OPENRC_TESTQUEUE_CONTEXT': ''}), \
             mock.patch.object(subprocess, 'CREATE_NO_WINDOW', NO_WINDOW, create=True), \
             mock.patch.object(subprocess, 'Popen', side_effect=capture):
            report = runner.run_checked([sys.executable, '-c',
                "import sys;print('STDOUT-MARK');print('STDERR-MARK',file=sys.stderr);sys.exit(7)"],
                Path(directory), timeout=10)
            log = Path(report['log']).read_text(encoding='utf-8')
        self.assertEqual(len(seen), 1)
        self.assertEqual(seen[0]['creationflags'], NO_WINDOW)
        self.assertIs(seen[0]['stdout'], subprocess.PIPE)
        self.assertIs(seen[0]['stderr'], subprocess.STDOUT)
        self.assertIs(seen[0]['stdin'], subprocess.DEVNULL)
        self.assertNotIn('startupinfo', seen[0])
        self.assertIn('STDOUT-MARK', log)
        self.assertIn('STDERR-MARK', log)
        self.assertEqual((report['process_exit'], report['exit_code'], report['ok']), (7, 7, False))

    def test_taskkill_is_scoped_to_owned_pid_and_retains_options(self):
        process = mock.Mock(pid=1234)
        process.poll.side_effect = [None, 0]
        completed = SimpleNamespace(returncode=0)
        with mock.patch.object(runner, 'os', PlatformProxy(os, 'nt')), \
             mock.patch.object(subprocess, 'CREATE_NO_WINDOW', NO_WINDOW, create=True), \
             mock.patch.object(subprocess, 'run', return_value=completed) as call:
            self.assertEqual(runner.stop_process(process), '')
        self.assertEqual(call.call_args.args[0], ['taskkill', '/PID', '1234', '/T', '/F'])
        self.assertEqual(call.call_args.kwargs['creationflags'], NO_WINDOW)
        self.assertIs(call.call_args.kwargs['stdout'], subprocess.DEVNULL)
        self.assertIs(call.call_args.kwargs['stderr'], subprocess.DEVNULL)
        process.kill.assert_not_called()
        process.wait.assert_called_once()

    def test_pool_probe_options_on_windows_and_posix(self):
        authority = pool.Pool.__new__(pool.Pool)
        host = {'python': 'python', 'agent': '/runtime/agent.py', 'root': '/private/jobs', 'ssh': 'host'}
        response = SimpleNamespace(returncode=0, stdout='{"ok":true,"result":{"state":"RUNNING"}}', stderr='')
        for name, flags in (('nt', NO_WINDOW), ('posix', 0)):
            with self.subTest(platform=name), mock.patch.object(pool, 'os', PlatformProxy(os, name)), \
                 mock.patch.object(subprocess, 'CREATE_NO_WINDOW', NO_WINDOW, create=True), \
                 mock.patch.object(subprocess, 'run', return_value=response) as call:
                result = authority.remote(host, 'status', {'request_id': 'id1'})
            self.assertEqual(result, {'state': 'RUNNING'})
            self.assertEqual(call.call_args.kwargs['creationflags'], flags)
            self.assertTrue(call.call_args.kwargs['capture_output'])
            self.assertEqual(json.loads(call.call_args.kwargs['input']), {'request_id': 'id1'})
            self.assertIn('StrictHostKeyChecking=yes', call.call_args.args[0])

    def test_snapshot_git_probe_retains_stderr_and_timeout(self):
        with mock.patch.object(snapshots, 'os', PlatformProxy(os, 'nt')), \
             mock.patch.object(subprocess, 'CREATE_NO_WINDOW', NO_WINDOW, create=True), \
             mock.patch.object(subprocess, 'check_output', return_value=b'commit') as call:
            self.assertEqual(snapshots._git(Path('/fixture'), 'rev-parse', 'HEAD'), b'commit')
        self.assertEqual(call.call_args.kwargs['creationflags'], NO_WINDOW)
        self.assertEqual(call.call_args.kwargs['timeout'], 120)
        self.assertIs(call.call_args.kwargs['stderr'], subprocess.PIPE)

    def test_rendered_debug_launch_does_not_request_hidden_gui(self):
        fake_process = SimpleNamespace(pid=921345)
        fake_sys = PlatformProxy(sys, 'nt')
        fake_sys.platform = 'win32'
        with tempfile.TemporaryDirectory(prefix='console-gui-test-') as directory, \
             mock.patch.object(debugctl, 'os', PlatformProxy(os, 'nt')), \
             mock.patch.object(debugctl, 'sys', fake_sys), \
             mock.patch.object(debugctl, 'godot', return_value='fixture_console.exe'), \
             mock.patch.object(debugctl, 'reserve_port', return_value=43210), \
             mock.patch.object(debugctl, 'write_private'), \
             mock.patch.object(debugctl, 'wait_ready', return_value={'result': {'pid': 921346}}), \
             mock.patch.dict(debugctl._OWNED_PROCESSES), \
             mock.patch.object(subprocess, 'CREATE_NO_WINDOW', NO_WINDOW, create=True), \
             mock.patch.object(subprocess, 'Popen', return_value=fake_process) as spawn, \
             redirect_stdout(io.StringIO()):
            status = debugctl._launch_local(['--out', str(Path(directory) / 'run'), '--port', '43210'])
        self.assertEqual(status, 0)
        command, options = spawn.call_args.args[0], spawn.call_args.kwargs
        self.assertNotIn('--headless', command)
        self.assertIn('--resolution', command)
        self.assertEqual(options['creationflags'], NO_WINDOW)
        self.assertNotIn('startupinfo', options)
        self.assertIs(options['stderr'], subprocess.STDOUT)
        self.assertTrue(options['start_new_session'])

    def test_artifact_ssh_retains_host_verification_and_flags(self):
        payload = b'verified-data'
        expected = {'size': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}
        def copy(command, **options):
            options['stdout'].write(payload)
            return SimpleNamespace(returncode=0)
        with tempfile.TemporaryDirectory(prefix='console-ssh-test-') as directory, \
             mock.patch.object(collection, 'os', PlatformProxy(os, 'nt')), \
             mock.patch.object(subprocess, 'CREATE_NO_WINDOW', NO_WINDOW, create=True), \
             mock.patch.object(subprocess, 'run', side_effect=copy) as call:
            target = Path(directory) / 'result'
            collection._copy_remote(pool, {'ssh': 'host', 'python': 'python3'}, '/remote/root', 'result', target, expected)
            self.assertEqual(target.read_bytes(), payload)
        self.assertEqual(call.call_args.kwargs['creationflags'], NO_WINDOW)
        self.assertIn('StrictHostKeyChecking=yes', call.call_args.args[0])
        self.assertEqual(call.call_args.kwargs['timeout'], 120)

    @unittest.skipUnless(os.name == 'nt', 'requires native Windows process/job')
    def test_real_windows_gate_and_child_console_are_not_visible(self):
        # A pseudoconsole may return an HWND, so visibility is the relevant observation.
        sample = ("import ctypes\n"
                  "ctypes.windll.kernel32.GetConsoleWindow.restype=ctypes.c_void_p\n"
                  "ctypes.windll.user32.IsWindowVisible.argtypes=[ctypes.c_void_p]\n"
                  "h=ctypes.windll.kernel32.GetConsoleWindow()\n"
                  "print('GATE_VISIBLE='+str(bool(h and ctypes.windll.user32.IsWindowVisible(h))),flush=True)\n")
        child = ("import ctypes,sys,time\n"
                 "ctypes.windll.kernel32.GetConsoleWindow.restype=ctypes.c_void_p\n"
                 "ctypes.windll.user32.IsWindowVisible.argtypes=[ctypes.c_void_p]\n"
                 "h=ctypes.windll.kernel32.GetConsoleWindow()\n"
                 "print('CHILD_VISIBLE='+str(bool(h and ctypes.windll.user32.IsWindowVisible(h))),flush=True)\n"
                 "print('CHILD_STDERR',file=sys.stderr,flush=True)\n"
                 "time.sleep(0.8)\n"
                 "sys.exit(7)\n")
        with tempfile.TemporaryDirectory(prefix='console-owned-') as directory:
            log = Path(directory) / 'owned.log'
            with mock.patch.object(processes, '_WINDOWS_GATE', sample + processes._WINDOWS_GATE), \
                    mock.patch.object(subprocess, 'Popen', wraps=subprocess.Popen) as spawn:
                process = processes.OwnedProcess([sys.executable, '-c', child], cwd=Path(directory),
                                                  env=os.environ.copy(), log=log)
                process.start()
                try:
                    deadline = time.monotonic() + 12
                    code = process.poll()
                    while code is None and time.monotonic() < deadline:
                        time.sleep(.05)
                        code = process.poll()
                    self.assertEqual(code, 7)
                    self.assertEqual(spawn.call_args.kwargs['creationflags'], subprocess.CREATE_NO_WINDOW)
                    self.assertIs(spawn.call_args.kwargs['stdin'], subprocess.PIPE)
                    self.assertNotIn('startupinfo', spawn.call_args.kwargs)
                finally:
                    process.close()
            text = log.read_text(encoding='utf-8')
            self.assertIn('GATE_VISIBLE=False', text)
            self.assertIn('CHILD_VISIBLE=False', text)
            self.assertIn('CHILD_STDERR', text)

    def test_background_supervisors_never_run_without_a_console(self):
        # DETACHED_PROCESS leaves no console to inherit, so every unflagged
        # descendant (git, ssh, shells, console wrappers) opens a visible window.
        root = Path(__file__).resolve().parent
        for name in ('pool_mcp.py', 'remote_agent.py'):
            with self.subTest(module=name):
                used = 'subprocess.DETACHED_PROCESS' in (root / name).read_text(encoding='utf-8')
                self.assertFalse(used, f'{name} launches a supervisor without a console')

    @unittest.skipUnless(os.name == 'nt', 'requires native Windows consoles')
    def test_unflagged_grandchild_of_background_supervisor_stays_invisible(self):
        from tools.testqueue import pool_mcp
        probe = ("import ctypes\n"
                 "ctypes.windll.kernel32.GetConsoleWindow.restype=ctypes.c_void_p\n"
                 "ctypes.windll.user32.IsWindowVisible.argtypes=[ctypes.c_void_p]\n"
                 "h=ctypes.windll.kernel32.GetConsoleWindow()\n"
                 "print('VISIBLE='+str(bool(h and ctypes.windll.user32.IsWindowVisible(h))),flush=True)\n")
        # The supervisor stand-in launches a helper with no creation flags,
        # exactly like a library or tool that forgets CREATE_NO_WINDOW.
        supervisor = ("import subprocess,sys\n"
                      "out=subprocess.run([sys.executable,'-c',sys.argv[1]],capture_output=True,text=True).stdout\n"
                      "print(out,end='',flush=True)\n")
        completed = subprocess.run([sys.executable, '-c', supervisor, probe], capture_output=True, text=True,
                                   timeout=60, creationflags=pool_mcp.BACKGROUND_CREATIONFLAGS)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn('VISIBLE=False', completed.stdout)
        self.assertEqual(pool_mcp.BACKGROUND_CREATIONFLAGS & 0x00000008, 0)  # DETACHED_PROCESS


if __name__ == '__main__':
    unittest.main(verbosity=2)
