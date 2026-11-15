#!/usr/bin/env bash
# spec: 6.8@023f849f
# A project always has a spec and a public def a proof
# (doc/drafts/spec-required, S2): the built `ris check spec` on fixtures.
set -euo pipefail
cd "$(dirname "$0")/../.."
export PYTHONDONTWRITEBYTECODE=1
python3 - <<'PY'
from pathlib import Path
import subprocess
import tempfile

ris = str(Path('bin/ris').resolve())
SPEC = '# Demo\n\n## 1. Root\n\n* 1.1 Root promise.\n'
CLAUSE = '\nspec 1.1\n  true\nend\n'


def project(files, spec=True):
    tmp = tempfile.TemporaryDirectory(prefix='ris-spec-required-')
    root = Path(tmp.name)
    base = {'ris.mod': 'module demo\n'}
    if spec:
        base['SPEC.md'] = SPEC
        base['src/root.ri'] = CLAUSE
    base.update(files)
    for name, text in base.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    if spec:
        head = subprocess.run([ris, 'spec', '1.1'], cwd=root, text=True,
                              capture_output=True).stdout.split()[0]
        (root / 'CHANGELOG.md').write_text(f'# C\n\n## 2026-11-15 · {head}\n')
        subprocess.run([ris, 'spec', 'ack', '1.1'], cwd=root, check=True,
                       stdout=subprocess.DEVNULL)
    return tmp, root


def check(title, files, ok, err=(), spec=True, before=None):
    tmp, root = project(files, spec)
    with tmp:
        if before:
            for args in before:
                subprocess.run([ris, *args], cwd=root, check=True,
                               stdout=subprocess.DEVNULL)
        p = subprocess.run([ris, 'check', 'spec'], cwd=root, text=True,
                           capture_output=True)
        assert (p.returncode == 0) == ok, (title, p.returncode, p.stderr,
                                           p.stdout)
        for want in err:
            assert want in p.stderr, (title, want, p.stderr)
        if ok:
            assert 'has no proof' not in p.stderr, (title, p.stderr)
        print(f'ok   {title}')
        return root


def block(lines, todo=False):
    body = ''.join(f'  {line}\n' for line in lines)
    if todo:
        body += '  todo "later"\n'
    return f'\nspec 1.1\n{body}end\n'


POST = 'class Post\n  def self.slugify(s : String) : String\n    s\n' \
       '  end\nend\n'

check('no spec', {'src/a.ri': '1\n'}, False, spec=False, err=[
    'no spec: write SPEC.md with a clause', '  * 1.1 TEXT',
    'and prove it at the end of the root module', '    EXPR == VALUE'])
check('module clauses only',
      {'src/m.ri': '# m.1 Keeps.\nspec m.1\n  true\nend\n'}, True,
      spec=False, before=[['spec', 'ack', 'm.1']])
check('uncovered def', {'src/post.ri': POST}, False, err=[
    'src/post.ri:2: public def slugify has no proof; add at the end',
    '  spec N.M\n    Post.slugify("...") == "..."\n  end\n',
    'or `todo "reason"` inside it, `@[NoSpec("reason")]`, or private'])
check('private, protected, lib, @[Ffi]', {
    'src/p.ri': 'class P\n  private def a\n  end\n'
                '  protected def b\n  end\nend\n',
    'src/l.ri': 'lib LibX\n  fun x : Int32\nend\n',
    'src/f.ri': '@[Ffi]\nclass F\n  def raw\n  end\nend\n'}, True)
check('covered on an assertion line',
      {'src/post.ri': POST + block(['Post.slugify("a") == "a"'])}, True)
check('todo cover',
      {'src/post.ri': POST + block(['x = Post.slugify("a")'], todo=True)},
      True)
check('&.name', {'src/w.ri': 'class W\n  def size\n    1\n  end\nend\n'
                 + block(['[W.new].map(&.size) == [1]'])}, True)
check('.new covers initialize',
      {'src/n.ri': 'class N\n  def initialize\n  end\nend\n'
       + block(['N.new != nil'])}, True)
check('operator', {'src/v.ri': 'struct V\n  def +(o : V)\n    self\n'
                   '  end\n  def [](i : Int32)\n    i\n  end\nend\n'
                   + block(['a = V.new', 'a + a == a', 'a[1] == 1'])},
      True)
check('call only off an assertion line',
      {'src/post.ri': POST + block(['x = Post.slugify("a")', 'x == "a"'])},
      False, err=['public def slugify has no proof'])
check('cross-module call only', {
    'src/post.ri': POST,
    'src/other.ri': block(['Post.slugify("a") == "a"'])},
    False, err=['src/post.ri:2: public def slugify has no proof'])
check('NoSpec def',
      {'src/post.ri': POST.replace('  def self',
                                   '  @[NoSpec("shown later")]\n  def self')},
      True)
check('NoSpec with an empty reason',
      {'src/post.ri': POST.replace('  def self',
                                   '  @[NoSpec("")]\n  def self')},
      False, err=['src/post.ri:2: NoSpec needs a reason'])
MARKED = '@[NoSpec("old API")]\n' + POST
check('NoSpec module not acked', {'src/post.ri': MARKED}, False,
      err=['run `ris spec ack --nospec src/post.ri`'])
check('NoSpec module', {'src/post.ri': MARKED}, True,
      before=[['spec', 'ack', '--nospec', 'src/post.ri']])
tmp, root = project({'src/post.ri': MARKED})
with tmp:
    subprocess.run([ris, 'spec', 'ack', '--nospec', 'src/post.ri'],
                   cwd=root, check=True, stdout=subprocess.DEVNULL)
    lock = (root / '.spec.lock').read_text()
    assert 'nospec src/post.ri slugify\n' in lock, lock
    (root / 'src/post.ri').write_text(MARKED.replace(
        'end\nend', 'end\n  def self.fresh\n  end\nend'))
    p = subprocess.run([ris, 'check', 'spec'], cwd=root, text=True,
                       capture_output=True)
    assert p.returncode == 1, p.stderr
    assert "public def fresh has no proof (added after the module's " \
           "NoSpec)" in p.stderr, p.stderr
    todo = subprocess.run([ris, 'spec', 'todo'], cwd=root, text=True,
                          capture_output=True).stdout
    assert 'src/post.ri:1 NoSpec module, 1 def: old API' in todo, todo
    print('ok   def added later fails; spec todo lists the mark')
check('property', {'src/q.ri': 'class Q\n  property name = ""\nend\n'},
      True)
tmp, root = project({'src/post.ri': POST})
with tmp:
    p = subprocess.run([ris, 'check', 'spec', 'src'], cwd=root, text=True,
                       capture_output=True)
    assert p.returncode == 0 and 'a PATH was given' in p.stdout, p
    print('ok   a PATH skips the part')
PY
# The compiler refuses an empty reason too.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf '@[NoSpec("")]\ndef f\nend\nf\n' > "$work/e.ri"
if ./bin/ris build --no-codegen "$work/e.ri" > "$work/out" 2>&1; then
  echo "FAIL: an empty NoSpec reason compiled"; exit 1
fi
grep -qF 'NoSpec needs a reason' "$work/out" ||
  { cat "$work/out"; exit 1; }
printf '@[NoSpec("old")]\nimport std/json\n\n@[NoSpec("x")]\ndef f\nend\nf\n' \
  > "$work/m.ri"
./bin/ris build --no-codegen "$work/m.ri" > "$work/out" 2>&1 ||
  { cat "$work/out"; exit 1; }
echo "ok   the compiler takes NoSpec marks and refuses an empty reason"
# A module's mark stands above its header: doc still finds the header.
mkdir -p "$work/p/app"
printf '@[NoSpec("old")]\nmodule app/greet\n\npub def hi : String\n  "hi"\nend\n' \
  > "$work/p/app/greet.ri"
./bin/ris doc "$work/p/app/greet.ri" > "$work/out" 2>&1 &&
  grep -qF 'module app/greet' "$work/out" || { cat "$work/out"; exit 1; }
echo "ok   a marked module keeps its header for doc"
