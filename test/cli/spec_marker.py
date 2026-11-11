#!/usr/bin/env python3
"""Exercise marker parsing and reports through the real compiler."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RIS = str(Path(os.environ.get('IYI', ROOT / 'bin/ris')).resolve())
TEXT = 'A value keeps its bytes.'
VERSION = hashlib.sha256(TEXT.encode()).hexdigest()[:8]
BASE = '# Demo\n## 1. Values\n* 1.1 ' + TEXT + '\n'
MARK = '  <!-- todo: needs a value fixture -->\n'


def main():
    work = ROOT / 'test/cli/.work'
    work.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=work, prefix='marker-') as tmp:
        root = Path(tmp)
        (root / 'ris.mod').write_text('')
        (root / 'CHANGELOG.md').write_text(
            '# Changelog\n\n## 2026-11-11 · 1.1@' + VERSION + '\n\nFixture.\n')

        def spec(text=BASE + MARK):
            (root / 'SPEC.md').write_text(text)

        def run(*args, code=0, has=None):
            result = subprocess.run([RIS, *args], cwd=root,
                                    capture_output=True, text=True)
            output = result.stdout + result.stderr
            assert result.returncode == code, (args, result.returncode, output)
            assert has is None or has in output, (args, has, output)
            return output

        spec(BASE)
        plain = json.loads(run('spec', '--json'))['clauses'][0]
        spec()
        marked = json.loads(run('spec', '--json'))['clauses'][0]
        assert marked['status'] == 'todo', marked
        assert marked['version'] == plain['version'] == VERSION
        assert marked['marker'] == 'needs a value fixture'
        run('spec', '1.1', has='marker: SPEC.md:4')
        run('spec', 'todo', has='SPEC.md:4 1.1 needs a value fixture')
        rows = json.loads(run('spec', 'todo', '--json'))['todo']
        assert rows[0]['clauses'] == ['1.1']
        assert rows[0]['file'] == 'SPEC.md:4'
        run('check', 'spec')
        run('spec', 'ack', '1.1', has='spec.lock: 1.1 ' + VERSION)
        run('check', 'spec')
        spec(BASE + '  <!-- todo: another reason -->\n')
        run('check', 'spec')
        spec(BASE.replace(TEXT, TEXT + ' Changed.') + MARK)
        run('check', 'spec', code=1,
            has='changed since its proofs were reviewed')
        spec(BASE)
        unmarked = json.loads(run('spec', '--json'))['clauses'][0]
        assert unmarked['version'] == VERSION
        run('check', 'spec', code=1, has='has no proof')
        spec()
        (root / 'proof.ri').write_text(
            'module proof\nspec 1.1\n  1 == 1\nend\n')
        run('check', 'spec', code=1,
            has='SPEC.md:4: 1.1 is proven by proof.ri:2; '
                'remove its todo marker')
        marked_text = (root / 'SPEC.md').read_text()
        run('check', 'spec', '--fix', code=1, has='remove its todo marker')
        assert (root / 'SPEC.md').read_text() == marked_text
        (root / 'proof.ri').write_text(
            'module proof\nspec 1.1\n  todo "later"\nend\n')
        run('check', 'spec', code=1,
            has='the block holds the todo; remove the marker')
        (root / 'proof.ri').unlink()
        (root / 'test').mkdir()
        test = root / 'test/proof.ri'
        test.write_text('# SPEC 1.1 is discussed here.\nputs 1\n')
        run('check', 'spec')  # Prose is not proof.
        test.write_text('# spec: 1.1@' + VERSION + '\nputs 1\n')
        run('check', 'spec', code=1, has='is proven by test/proof.ri:1')
        test.write_text('# spec: 9.9@00000000\n# spec: 1.1@' + VERSION +
                        '\nputs 1\n')
        run('check', 'spec', code=1, has='is proven by test/proof.ri:2')
        test.write_text('# spec: 1.1@' + VERSION + '\ntodo "later"\n')
        run('check', 'spec', code=1, has='remove the marker')
        test.unlink()
        for malformed in [BASE + '\n' + MARK, BASE + MARK.lstrip(),
                          BASE + MARK + MARK, BASE + MARK + '  more text\n',
                          BASE + '  <!-- todo:  -->\n',
                          BASE + '  <!-- todo: ' + 'x' * 70 + ' -->\n']:
            spec(malformed)
            run('check', 'spec', code=1, has='SPEC.md:')
            run('spec', code=1, has='todo marker')
        spec()
        before = (root / 'SPEC.md').read_text()
        run('check', 'spec', '--fix')
        assert (root / 'SPEC.md').read_text() == before
    print('PASS: spec marker')


if __name__ == '__main__':
    try:
        main()
    except AssertionError as error:
        raise SystemExit(f'FAIL: spec marker: {error}')
