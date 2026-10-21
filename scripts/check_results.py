"""Fail CI even with cocotb/make versions that exit zero after failed tests."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('xml', type=Path)
parser.add_argument('--expect-failure', action='store_true')
args = parser.parse_args()
cases = list(ET.parse(args.xml).getroot().iter('testcase'))
failed = [c for c in cases if c.find('failure') is not None or c.find('error') is not None]
skipped = [c for c in cases if c.find('skipped') is not None]
summary = dict(tests=len(cases), passed=len(cases)-len(failed)-len(skipped),
               failed=len(failed), skipped=len(skipped))
print(json.dumps(summary))
if args.expect_failure:
    assert len(cases) == 9 and len(failed) == 9 and not skipped, 'Expected all nine stub tests to fail'
else:
    assert len(cases) == 9 and not failed and not skipped, 'Acceptance suite failed or incomplete'
