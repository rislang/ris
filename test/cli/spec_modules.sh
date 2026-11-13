#!/usr/bin/env bash
# spec: 6.7@436841dc, 6.8@82707d6b, 8.2@ddd1640f
# Module clauses: discovery, ownership, reasons, review and labels.
set -euo pipefail
cd "$(dirname "$0")/../.."
export PYTHONDONTWRITEBYTECODE=1
python3 - <<'PY'
import json
from pathlib import Path
import subprocess
import tempfile

ris = str(Path('bin/ris').resolve())

with tempfile.TemporaryDirectory(prefix='ris-module-spec-') as tmp:
    root = Path(tmp)

    def put(name, text):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def run(*args, ok=True, contains=None, directory=None):
        p = subprocess.run([ris, *args], cwd=directory or root, text=True,
                           stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT)
        assert (p.returncode == 0) == ok, (args, p.returncode, p.stdout)
        if contains:
            assert contains in p.stdout, (args, contains, p.stdout)
        return p.stdout

    def owner(mod, n=1, body='  true', text='Keeps its promise.'):
        return f'# {mod}.{n} {text}\nspec {mod}.{n}\n{body}\nend\n'

    put('ris.mod', 'module example\n')
    put('SPEC.md', '# Demo\n\n## 1. Root\n\n* 1.1 Root promise.\n')
    put('test/root.sh', '# spec: 1.1\n')
    put('src/std/json.ri', owner('json', 10) + '\n' + owner('json', 2))
    put('src/route.ri', owner('route', text='Keeps its\n#   promise.'))
    put('src/a/b.ri', owner('a/b'))
    put('src/plain.ri', owner('plain'))
    reasons = ['first "quoted" reason', r'second \ reason']
    body = '\n'.join('  todo ' + json.dumps(r) for r in reasons)
    put('src/std/log.ri', owner('log', body=body))
    # All exclusions use the shared project walk; none may own clauses.
    for directory in ('lib', 'mods', '.hidden', 'fixtures'):
        put(f'src/{directory}/bad.ri', owner('bad'))
    put('src/fixtures/.ris-fixtures', '')
    put('lib/ignored.ri', owner('ignored'))
    (root / 'src/link.ri').symlink_to(root / 'src/route.ri')
    put('test/tag.sh', '# spec: route.1\n')
    put('extra.ri', '# route.50 Outside src is prose.\n'
        'spec route.1  # Keeps its promise.\n  true\nend\n')
    data = json.loads(run('spec', '--json'))['clauses']
    ids = [c['number'] for c in data]
    assert ids == ['1.1', 'a/b.1', 'json.2', 'json.10', 'log.1',
                   'plain.1', 'route.1'], ids
    assert next(c for c in data if c['number'] == 'log.1')['todo'] == reasons
    assert len(json.loads(run('spec', 'json', '--json'))['clauses']) == 2
    assert next(c for c in data if c['number'] == 'route.1')['version'] == (
        next(c for c in data if c['number'] == 'plain.1')['version'])
    run('spec', 'route.1', contains='src/route.ri:3')
    for reason in reasons:
        run('spec', 'todo', contains=reason)
    todos = json.loads(run('spec', 'todo', '--json'))['todo']
    assert [t['reason'] for t in todos] == reasons
    version = data[0]['version']
    history = f'## 2026-11-13 · 1.1@{version}\n\nReason.\n'
    module_version = next(c for c in data if c['number'] == 'a/b.1')[
        'version']
    put('CHANGELOG.md', history + f'a/b.1@{module_version}\n')
    run('spec', 'a/b.1', contains='changelog: 2026-11-13')
    put('CHANGELOG.md', history)
    run('check', 'spec', ok=False, contains='has proofs not reviewed yet')
    for target in ('1', 'route.1', 'a/b', 'json', 'log', 'plain'):
        run('spec', 'ack', target)
    assert 'route.1@' in (root / 'test/tag.sh').read_text()
    assert [l.split()[0] for l in (root / '.spec.lock').read_text()
            .splitlines()] == ids
    run('check', 'spec', contains='0 to review')
    before = (root / 'src/std/json.ri').read_bytes()
    run('check', 'spec', '--fix')
    run('check', 'spec', '--fix')
    assert (root / 'src/std/json.ri').read_bytes() == before
    # The parser accepts both ids and several trailing todo statements.
    for path, header in [('src/route.ri', 'src/route'),
                         ('src/a/b.ri', 'src/a/b')]:
        put(path, f'module {header}\n\n' + (root / path).read_text())
    run('build', '--spec', '--no-codegen', 'src/std/log.ri')
    run('build', '--spec', '--no-codegen', 'src/route.ri')
    run('build', '--spec', '--no-codegen', 'src/a/b.ri')
    put('src/std/log.ri', owner('log', body=body + '\n  true'))
    run('build', '--spec', '--no-codegen', 'src/std/log.ri', ok=False,
        contains='nothing runs after `todo`')
    put('src/std/log.ri', owner('log', body=body))
    put('src/std/json.ri', owner('json', 2))
    run('spec', 'ack', 'json', contains='removed: json.10')
    assert 'json.10' not in (root / '.spec.lock').read_text()

    def refused(path, text, diagnostic, safe):
        previous = (root / path).read_text() if (root / path).exists() else None
        put(path, text)
        out = run('check', 'spec', ok=False, contains=diagnostic)
        assert safe in out, out
        if previous is None:
            (root / path).unlink()
        else:
            put(path, previous)

    refused('src/std/yaml.ri', owner('json'), 'does not match yaml',
            'move it to src/std/json.ri')
    refused('src/route.ri', '# route.1 Orphan.\n\n', 'orphan clause',
            'put `spec route.1` directly after its comment')
    refused('src/route.ri', owner('route') * 2, 'duplicate owner',
            'keep one owning comment and block')
    refused('src/route.iyi', '', 'a ris file ends in .ri',
            'rename it to route.ri')
    refused('src/json.ri', '', 'two files are module json',
            'keep one file')
    for number in ('0', '01', '-1'):
        refused('src/route.ri', owner('route', number),
                'invalid module clause', 'N positive, without leading zeros')
    refused('src/route.ri', '# route.1 Text.\n# bad continuation\n'
            'spec route.1\n  true\nend\n', 'invalid continuation',
            'write `#   text`')
    refused('src/route.ri', owner('route').replace('spec route.1',
            'spec route.1  # label'), 'owning block takes no label',
            'write `spec route.1`')
    refused('test/bad.sh', '# spec: missing.1\n',
            'names missing.1, which is no clause', 'spec` lists')
    # Another module's comment without its matching block is plain prose.
    put('src/prose.ri', '# json.30 Just a reference.\n')
    run('check', 'spec')
    # Module clauses can be the entire spec, with no root markdown file.
    (root / 'SPEC.md').unlink()
    (root / 'test/root.sh').unlink()
    (root / 'ris.mod').unlink()
    run('spec', 'route.1', contains='Keeps its promise.')
    # ris test and check share the detector for modules with spec blocks.
    execution = root / 'execution'
    put('execution/ris.mod', 'module execution\n')
    put('execution/src/route.ri', 'module src/route\n\n' + owner('route'))
    run('test', directory=execution,
        contains='1 module, 1 blocks: 1 ok, 0 broken, 0 todo')
print('spec_modules: ok')
PY
