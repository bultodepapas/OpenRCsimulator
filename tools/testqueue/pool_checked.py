"""Opt-in automatic placement for the existing functional checked-runner API."""
import os
import platform
from pathlib import Path
import sys
import time

from tools.testqueue.pool import Pool


def checked(command, *, out_dir, timeout, required, max_log_bytes, warnings_as_errors, label):
    values = {}
    index = 1
    if '--headless' not in command or '--' in command:
        raise ValueError('Automatic pool checks require a headless functional script')
    while index < len(command):
        value = command[index]
        if value == '--headless':
            index += 1
            continue
        if value not in {'--path', '--script', '--audio-driver'} or index + 1 >= len(command):
            raise ValueError('Unsupported pool checked argument: ' + value)
        if value in values:
            raise ValueError('Duplicate pool checked argument: ' + value)
        values[value] = command[index + 1]
        index += 2
    if '--path' not in values or '--script' not in values or values.get('--audio-driver', 'Dummy') != 'Dummy':
        raise ValueError('Pool checked requires an app path, script and Dummy audio')
    app = Path(values['--path']).resolve()
    if app.name != 'app':
        raise ValueError('Pool checked requires the checkout app directory')
    pool = Pool(os.environ['OPENRC_TESTPOOL_CONFIG'])
    snapshot = pool.snapshot(app.parent)
    import uuid
    identifier = uuid.uuid4().hex
    deadline = time.monotonic() + timeout + 600
    while True:
        submitted = pool.submit(snapshot, values['--script'], require=required, timeout=timeout,
                                platform=os.environ.get('OPENRC_TESTPOOL_PLATFORM', platform.system().lower()),
                                request_id=identifier, settings={'max_log_bytes': max_log_bytes,
                                'warnings_as_errors': warnings_as_errors, 'label': label})
        if submitted['state'] != 'WAITING':
            break
        if time.monotonic() >= deadline:
            raise ValueError('No eligible host became available before the admission deadline')
        time.sleep(2)
    print('Pool receipt: ' + submitted['receipt'], file=sys.stderr)
    while True:
        status = pool.status(identifier)
        if status['state'] == 'FINISHED':
            result = pool.collect(identifier, out_dir=out_dir)
            if result['pool_outcome'] not in {'PASSED', 'TEST_FAILED'} or result.get('diagnostic_only') is True:
                raise ValueError('Pool infrastructure failure; receipt ' + submitted['receipt'])
            return result
        if status['state'] in {'UNKNOWN', 'SUBMISSION_UNCONFIRMED'} or time.monotonic() >= deadline:
            raise ValueError('Pool attempt requires recovery through receipt ' + submitted['receipt'])
        time.sleep(2)
