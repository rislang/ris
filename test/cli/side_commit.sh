#!/usr/bin/env bash
# Small builders reserve stable addresses without charging whole slices.
set -euo pipefail
cd "$(dirname "$0")/../.."
export RIS="${RIS:-$PWD/bin/ris}"
python3 - <<'PY'
import os
import pathlib
import re
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix="ris-side-commit-") as work:
    source = pathlib.Path(work) / "small.ri"
    lines = ['module small', 'import std/file']
    for i in range(64):
        lines += [f'b{i} = String::Builder.new(128)', f'b{i} << "small"']
    # Grow after neighbours have reserved their slices; cross commit steps.
    lines += ['200000.times { b0 << "x" }',
              'raise "growth lost bytes" unless b0.bytesize == 200005']
    for i in range(1, 64):
        lines += [f'raise "neighbour changed" unless b{i}.finish == "small"']
    lines += ['if File.exists?("/proc/self/status")',
              '  puts File.read("/proc/self/status")', 'end', 'puts "ok"']
    source.write_text('\n'.join(lines) + '\n')
    result = subprocess.run([os.environ['RIS'], 'run', str(source)],
                            env={**os.environ, 'RIS_TAPE_STATS': '1',
                                 'RIS_CACHE_DIR': work + '/cache'},
                            text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'ok\n' in result.stdout, result.stdout
    assert '0 growth moves off' in result.stderr, result.stderr
    assert '0 transfer bytes copied' in result.stderr, result.stderr
    data = re.search(r'^VmData:\s+(\d+) kB', result.stdout, re.M)
    if data:
        # 64 small builders must not charge 8 GiB, nor a 64 GiB arena.
        assert int(data[1]) < 1024 * 1024, data.group(0)
    footprint = data.group(0) if data else 'VmData unavailable'
    print(f'side_commit: PASS (0 growth moves; {footprint})')
PY
