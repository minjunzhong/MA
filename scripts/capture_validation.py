"""Capture machine-readable evidence from actual simulator XML and source hashes."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
from pathlib import Path
import platform
import shutil
import subprocess
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--red', type=Path, default=Path('red-results.xml'))
parser.add_argument('--green', type=Path, default=Path('results.xml'))
args = parser.parse_args()


def summary(path):
    cases = []
    for case in ET.parse(path).getroot().iter('testcase'):
        failed = case.find('failure') is not None or case.find('error') is not None
        cases.append(dict(name=case.get('name'), failed=failed,
                          skipped=case.find('skipped') is not None,
                          simulation_ns=case.get('sim_time_ns')))
    return dict(tests=len(cases), failed=sum(c['failed'] for c in cases), cases=cases)


red, green = summary(args.red), summary(args.green)
assert red['tests'] == red['failed'] == 9
assert green['tests'] == 9 and green['failed'] == 0
assert not any(c['skipped'] for c in red['cases'] + green['cases'])
out = Path('reports/verified')
out.mkdir(parents=True, exist_ok=True)
source_files = sorted(list(Path('rtl').glob('*.sv')) + list(Path('tests').glob('*.py')))
record = dict(
    recorded_at_utc=datetime.now(timezone.utc).isoformat(),
    platform=platform.platform(), python=platform.python_version(),
    dependencies={name: importlib.metadata.version(name) for name in ('cocotb', 'pyuvm', 'pytest')},
    simulator=subprocess.run(['iverilog', '-V'], capture_output=True, text=True).stdout.splitlines()[0],
    red_baseline_commit='419bfef', red=red, green=green,
    source_sha256={str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files},
    note='Red used the test-first stub and original tests; green uses final tests and real RTL. '
         'See git history for test refinements. These are measured simulation results, not paper PPA.')
(out / 'validation.json').write_text(json.dumps(record, indent=2) + '\n')
shutil.copyfile('reports/local/benchmark.json', out / 'benchmark.json')
print(json.dumps(dict(red_failed=red['failed'], green_failed=green['failed'], output=str(out))))
