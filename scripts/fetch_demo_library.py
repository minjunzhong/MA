"""Download an externally maintained research-only library; never commit the PDK."""
import hashlib
from pathlib import Path
import urllib.request

URL = ('https://raw.githubusercontent.com/The-OpenROAD-Project/'
       'OpenROAD-flow-scripts/master/flow/platforms/nangate45/lib/'
       'NangateOpenCellLibrary_typical.lib')
EXPECTED_SHA256 = '8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1'
target = Path(__file__).resolve().parents[1] / 'build/demo-lib/NangateOpenCellLibrary_typical.lib'
data = urllib.request.urlopen(URL, timeout=60).read()
digest = hashlib.sha256(data).hexdigest()
if digest != EXPECTED_SHA256:
    raise SystemExit(f'Upstream library changed: {digest}; review before using it.')
target.parent.mkdir(parents=True, exist_ok=True)
target.write_bytes(data)
print(f'{target}\nSHA256={digest}')
print('Research/test library only; see OpenROAD-flow-scripts/flow/platforms/nangate45/LICENSE.')
