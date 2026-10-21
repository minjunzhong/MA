"""Run Genus and require a completion marker: some tool errors still exit zero."""
import argparse
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--stage', choices=['parse', 'elaborate', 'synthesize'], default='synthesize')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
stages = {
    'parse': ('read_hdl.tcl', 'MA_RTL_READ_COMPLETED'),
    'elaborate': ('elaborate.tcl', 'MA_ELABORATION_COMPLETED'),
    'synthesize': ('run.tcl', 'MA_SYNTHESIS_COMPLETED'),
}
script, marker = stages[args.stage]
if args.stage != 'parse' and not Path(os.environ.get('LIBERTY_FILE', '')).is_file():
    parser.error('LIBERTY_FILE must point to a readable authorized timing library')
binary = os.environ.get('GENUS_BIN', '/nas/ei/share/tools/cadence/GENUS/GENUS_21.17.000-ISR7/bin/genus')
log = root / f'build/genus-{args.stage}.log'
log.parent.mkdir(parents=True, exist_ok=True)
completed = False
with log.open('w', encoding='utf-8') as output:
    process = subprocess.Popen([binary, '-batch', '-files', str(root / 'synth' / script)],
                               cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, encoding='utf-8', errors='replace')
    for line in process.stdout:
        print(line, end='', flush=True)
        output.write(line)
        # Genus echoes Tcl source, so an echoed puts statement is NOT completion.
        if line.strip() == marker:
            completed = True
    status = process.wait()
if status != 0 or not completed:
    raise SystemExit(f'Genus stage did not complete (exit={status}); inspect {log}')
print(f'Validated {args.stage} completion; log: {log}')
