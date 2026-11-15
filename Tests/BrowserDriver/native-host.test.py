"""Test only generated UUID upload fixtures; never touches page/state/command files."""
import base64
import datetime
import json
import pathlib
import struct
import subprocess
import uuid

host = pathlib.Path('dist/Newtv1.app/Contents/MacOS/Newtv1BrowserHost').resolve()
root = pathlib.Path.home() / 'Library/Application Support/Newtv1/BrowserBridge'
root.mkdir(parents=True, exist_ok=True, mode=0o700)
command, session, document = [str(uuid.uuid4()).upper() for _ in range(3)]
metadata = root / f'upload-{command}.json'
payload = root / f'upload-{command}.data'
sample = bytes(range(256)) * 274

def request(value):
    data = json.dumps(value).encode()
    result = subprocess.run([str(host)], input=struct.pack('<I', len(data)) + data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert len(result.stdout) >= 4
    size = struct.unpack('<I', result.stdout[:4])[0]
    assert len(result.stdout) == size + 4
    return json.loads(result.stdout[4:])

try:
    expires = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=120)).strftime('%Y-%m-%dT%H:%M:%SZ')
    metadata.write_text(json.dumps(dict(commandID=command, session=session, document=document,
                                       fileName='generated-fixture.bin', mimeType='application/octet-stream',
                                       size=len(sample), expiresAt=expires)))
    metadata.chmod(0o600)
    payload.write_bytes(sample)
    payload.chmod(0o600)
    arguments = dict(kind='uploadChunk', commandID=command, session=session, document=document, index=0)
    denied = request(dict(arguments, session=str(uuid.uuid4())))
    assert denied['ok'] is False and 'chunk' not in denied
    denied = request(dict(arguments, document=str(uuid.uuid4())))
    assert denied['ok'] is False and 'chunk' not in denied
    denied = request(dict(arguments, index=-1))
    assert denied['ok'] is False and 'chunk' not in denied
    first = request(arguments)['chunk']
    assert first['mimeType'] == 'application/octet-stream'
    assert first['last'] is False
    second = request(dict(arguments, index=1))['chunk']
    assert second['last'] is True
    assert base64.b64decode(first['data']) + base64.b64decode(second['data']) == sample
    assert not metadata.exists() and not payload.exists()
    print('PASS native upload integration: framing, session/document isolation, chunk bounds, binary round-trip and staging cleanup')
finally:
    metadata.unlink(missing_ok=True)
    payload.unlink(missing_ok=True)
