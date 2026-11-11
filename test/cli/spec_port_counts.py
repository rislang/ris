#!/usr/bin/env python3
"""Frozen per-source counts and one failing mutation per ported block."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)
sys.dont_write_bytecode = True
LEDGER = Path('test/cli/spec_port_ledger.txt')


def ledger():
    source, body = None, []
    for line in LEDGER.read_text().splitlines():
        if line.startswith('#'):
            continue
        if line.startswith('  '):
            body.append(line)
        else:
            if source:
                yield source, json.loads('\n'.join(body))
            source, body = line, []
    if source:
        yield source, json.loads('\n'.join(body))


def old_count(path):
    return len(re.findall(
        r'^\s*(?:exit \d+ (?:unless|if)|raise .* unless)\b',
        path.read_text(), re.M))


def blocks(path):
    lines = path.read_text().splitlines()
    starts = [i for i, s in enumerate(lines) if s.startswith('spec ')]
    for start in starts:
        end = next(i for i in range(start + 1, len(lines))
                   if lines[i] == 'end')
        checks = []
        for i in range(start + 1, end):
            s = lines[i]
            if not re.match(r'^  \S', s) or s.lstrip().startswith('#'):
                continue
            text = s.strip()
            if re.match(r'\w+\s*=(?!=)', text):
                continue
            if text in ('end', 'else') or text.startswith('tape '):
                continue
            stop = i + 1
            while stop < end and lines[stop].startswith('    '):
                stop += 1
            expression = ' '.join(t.strip() for t in lines[i:stop])
            # Ignore operators and question marks inside string literals.
            expression = re.sub(r'"(?:\\.|[^"\\])*"', '""', expression)
            # Count the comparison or Bool call, not builder effects.
            if not (re.search(r'==|!=| < | > | <= | >= |\?\(|\?$', expression)
                    or expression.startswith('!')):
                continue
            checks.append((i, stop))
        yield start, lines[start].split()[1], checks


def shell_count(source, cases):
    name = Path(source).stem
    total = 0
    for block in cases:
        text = '\n'.join(block)
        loop = re.search(r'for name in (.*?); do', text, re.S)
        members = loop[1].replace('\\', '').split() if loop else []
        if source not in text and name not in members:
            continue
        total += sum(any(mark in line for mark in
                         ('want=', 'grep -q', '[ "$out" =',
                          'RIS_HEAP_STATS')) for line in block)
    return total


def main():
    spec = importlib.util.spec_from_file_location(
        'port_checks', ROOT / 'test/ris/check_parallel.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    cases = module.split()[1]
    ported = []
    for source, item in ledger():
        if item['state'].startswith('stays:'):
            assert Path(source).is_file(), f'missing ledger source: {source}'
            assert old_count(Path(source)) >= item['old'], \
                f'{source}: old assertion dropped'
            assert shell_count(source, cases) >= item.get('shell_old', 0), \
                f'{source}: shell output/heap check dropped'
            target = item.get('target')
            assert not target or target == 'marker' or Path(target).is_file(), \
                f'{source}: missing target {target}'
            continue
        dest = Path(item['dest'])
        assert dest.is_file(), f'{source}: missing target {dest}'
        found = list(blocks(dest))
        assert {b[1] for b in found} == set(item['clauses']), \
            f'{source}: ledger clauses differ from blocks'
        count = sum(len(b[2]) for b in found)
        total = count + item.get("retained", 0)
        assert total >= item['old'], \
            f'{source}: {total} new < {item["old"]} old'
        assert total == item['new'], f'{source}: update new count ({count})'
        assert all(b[2] for b in found), f'{dest}: block without Bool'
        if item.get('driver'):
            # Output drivers need no PASS sentinel: their case is frozen.
            assert Path(source).is_file(), f'{source}: missing output driver'
        else:
            assert not Path(source).exists(), f'{source}: old test still exists'
            assert shell_count(source, cases) == 0, \
                f'{source}: obsolete check.sh case still names the old test'
        ported.append((dest, found))
        print(f'counts: {source}: {item["old"]} old <= {total} new')
    baseline = int(re.search(r'# baseline cases: (\d+)',
                             LEDGER.read_text())[1])
    removed = sum(item.get('removed_cases', 0) for _, item in ledger())
    assert len(cases) == baseline - removed + len(ported), \
        'check.sh case arithmetic'
    for source, item in ledger():
        if item.get('driver'):
            selected = [b for b in cases
                        if item['case'] in '\n'.join(b)]
            assert len(selected) == 1, f'{source}: output/heap case missing'
            digest = hashlib.sha256('\n'.join(selected[0]).encode()).hexdigest()[:16]
            assert digest == item['case_hash'], \
                f'{source}: retained output/heap checks changed'
    for dest, _ in ported:
        assert sum(f'check test {dest}' in '\n'.join(b)
                   for b in cases) == 1, f'{dest}: module case missing'
    print(f'cases: {baseline} old - {removed} removed + '
          f'{len(ported)} modules = {len(cases)} new')
    work = ROOT / 'test/cli/.work'
    work.mkdir(exist_ok=True)
    ris = str(Path(os.environ.get('RIS', './bin/ris')).resolve())
    flips = 0
    with tempfile.TemporaryDirectory(dir=work, prefix='port-') as scratch:
        for dest, found in ported:
            original = dest.read_text().splitlines()
            for start, clause, checks in found:
                first, stop = checks[0]
                lines = original.copy()
                expression = ' '.join(s.strip() for s in lines[first:stop])
                lines[first:stop] = ['  !(' + expression + ')']
                copy = Path(scratch) / "std" / dest.name
                copy.parent.mkdir(exist_ok=True)
                copy.write_text('\n'.join(lines) + '\n')
                result = subprocess.run([ris, 'test', str(copy)],
                                        capture_output=True, text=True)
                out = result.stdout + result.stderr
                assert result.returncode == 1, f'{dest}: flip did not fail: {out}'
                assert f'{clause}' in out and f':{first + 1}' in out, \
                    f'{dest}: flip missed clause/line: {out}'
                assert f'BROKEN  spec {clause} ' in out, f'{dest}: flip was a build error: {out}'
                flips += 1
    print(f'PASS: spec port counts ({len(ported)} modules, {flips} flips)')


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, ValueError, OSError) as error:
        raise SystemExit(f'FAIL: spec port counts: {error}')
