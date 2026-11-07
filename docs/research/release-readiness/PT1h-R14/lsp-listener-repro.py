#!/usr/bin/env python3
"""D14: reproduce the unresolved foreign-LSP-listener false-clean result.

Run from any directory with Python 3. A zero exit means the historical defect
was reproduced, not that the warning scanner passed qualification. Uses a local
fake LSP listener, temporary source and an exited editor stub; no Godot launched.
"""
import json
import os
import socket
import sys
import tempfile
import threading
from pathlib import Path
from unittest.mock import Mock, patch
sys.path.insert(0, str(Path(__file__).resolve().parents[4] / 'tools/debug'))
import gdscript_warnings as gw

server = socket.create_server(('127.0.0.1', 0))
port = server.getsockname()[1]
received, failures = [], []
def send(conn, value):
    body = json.dumps(value).encode()
    conn.sendall(b'Content-Length: %d\r\n\r\n' % len(body) + body)
def serve():
    try:
        conn, _ = server.accept()
        with conn, conn.makefile('rb') as stream:
            while True:
                headers = {}
                while True:
                    line = stream.readline()
                    if not line:
                        return
                    if line == b'\r\n':
                        break
                    key, value = line.decode().strip().split(':', 1)
                    headers[key.lower()] = int(value.strip())
                message = json.loads(stream.read(headers['content-length']))
                received.append(message['method'])
                if message['method'] == 'initialize':
                    send(conn, {'jsonrpc':'2.0', 'id':message['id'], 'result':{}})
                elif message['method'] == 'textDocument/didOpen':
                    uri = message['params']['textDocument']['uri']
                    send(conn, {'jsonrpc':'2.0', 'method':'textDocument/publishDiagnostics', 'params':{'uri':uri, 'diagnostics':[]}})
                elif message['method'] == 'textDocument/didClose':
                    return
    except Exception as error:
        failures.append(repr(error))
thread = threading.Thread(target=serve, daemon=True)
thread.start()
with tempfile.TemporaryDirectory() as directory:
    app = Path(directory)
    (app / 'sample.gd').write_text('extends Node\n', encoding='utf-8')
    process = Mock()
    process.poll.return_value = 9
    with patch.object(gw.subprocess, 'Popen', return_value=process), patch.dict(os.environ, {'OPENRC_GODOT':'synthetic-editor'}):
        findings = gw.collect(app, ['sample.gd'], port, 2, app / 'editor.log')
server.close()
thread.join(5)
result = {'foreign_server_methods':received, 'launched_editor_exit_status':9, 'launched_editor_polled':process.poll.call_count, 'findings':findings, 'server_errors':failures}
print(json.dumps(result))
assert received == ['initialize', 'initialized', 'textDocument/didOpen', 'textDocument/didClose'] and not findings and process.poll.call_count == 0 and not failures
