"""Run the PE, SPad cluster, and static-router benches with real HDL tools."""
import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / 'rtl'
CASES = {
    'pe': ('tb_eyeriss_pe', ['eyeriss_pe.sv']),
    'cluster': ('tb_rs_spad_cluster', ['eyeriss_pe.sv', 'rs_vertical_accumulator.sv', 'rs_spad_cluster.sv']),
    'router': ('tb_dense_static_router', ['dense_static_router.sv']),
}
LINT_TOPS = {
    'eyeriss_pe': ['eyeriss_pe.sv'],
    'rs_spad_cluster': ['eyeriss_pe.sv', 'rs_vertical_accumulator.sv', 'rs_spad_cluster.sv'],
    'rs_vertical_accumulator': ['rs_vertical_accumulator.sv'],
    'dense_static_router': ['dense_static_router.sv'],
}


def run(command, log):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60)
    log.append('$ ' + ' '.join(map(str, command)) + '\n' + result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError('Command returned ' + str(result.returncode))
    return result.stdout + result.stderr


def report_failure(entry, log):
    detail = '\n'.join(log)[-6000:] or entry.get('reason', 'Unknown failure')
    print(detail, file=sys.stderr)
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        # Compiler diagnostics remain visible in the public check annotations.
        message = detail.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        print('::error title=' + entry['test'] + '::' + message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', choices=CASES)
    parser.add_argument('--lint', action='store_true', help='Also run Verilator lint')
    parser.add_argument('--lint-only', action='store_true')
    args = parser.parse_args()
    out = ROOT / 'reports/local/stage3'
    build = ROOT / 'build/stage3'
    out.mkdir(parents=True, exist_ok=True)
    build.mkdir(parents=True, exist_ok=True)
    required = [] if args.lint_only else ['iverilog', 'vvp']
    if args.lint or args.lint_only:
        required.append('verilator')
    missing = [name for name in required if not shutil.which(name)]
    if missing:
        message = 'Missing tools: ' + ', '.join(missing)
        (out / 'results.json').write_text(json.dumps({'status': 'BLOCKED', 'reason': message}, indent=2) + '\n')
        print(message, file=sys.stderr)
        return 1
    entries = []
    if not args.lint_only:
        for name in ([args.case] if args.case else CASES):
            top, sources = CASES[name]
            log = []
            entry = {'test': name, 'status': 'FAIL'}
            try:
                executable = build / (name + '.vvp')
                run(['iverilog', '-g2012', '-s', top, '-o', str(executable),
                     *[str(RTL / source) for source in sources], str(ROOT / 'tests' / (top + '.sv'))], log)
                output = run(['vvp', str(executable)], log)
                if 'PASS ' + name + ':' not in output:
                    raise RuntimeError('Missing bench completion marker')
                entry['status'] = 'PASS'
            except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
                entry['reason'] = str(exc)
            (out / (name + '.log')).write_text('\n'.join(log), encoding='utf-8')
            entries.append(entry)
            print(entry['status'] + ' ' + name + (': ' + entry['reason'] if 'reason' in entry else ''))
            if entry['status'] == 'FAIL':
                report_failure(entry, log)
    if args.lint or args.lint_only:
        for top, sources in LINT_TOPS.items():
            log = []
            entry = {'test': 'lint:' + top, 'status': 'FAIL'}
            try:
                run(['verilator', '--lint-only', '-Wno-SYNCASYNCNET', '--top-module', top,
                     *[str(RTL / source) for source in sources]], log)
                entry['status'] = 'PASS'
            except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
                entry['reason'] = str(exc)
            (out / ('lint-' + top + '.log')).write_text('\n'.join(log), encoding='utf-8')
            entries.append(entry)
            print(entry['status'] + ' ' + entry['test'])
            if entry['status'] == 'FAIL':
                report_failure(entry, log)
    summary = {'time_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'results': entries}
    (out / 'results.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    return 0 if entries and all(entry['status'] == 'PASS' for entry in entries) else 1


if __name__ == '__main__':
    raise SystemExit(main())
