#!/usr/bin/env bash
# Compare a baseline module tree (containing std/) with this checkout.
# Usage: IYI=.build23/ris bash bench/http2_tape.sh [BASE_MODULE_TREE]
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
BASE=${1:-}
IYI=${IYI:-$REPO/.build23/ris}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
if [ -z "$BASE" ]; then
  BASE=$WORK/original
  mkdir -p "$BASE/std"
  for file in http.iyi hpack.iyi; do
    git -C "$REPO" show "HEAD:src/std/$file" > "$BASE/std/$file"
  done
fi
python3 - "$BASE" "$REPO/src" "$WORK" <<'PY'
from pathlib import Path
import sys
for label, source in zip(('base', 'tape'), sys.argv[1:3]):
    dest = Path(sys.argv[3], label, 'std')
    dest.mkdir(parents=True)
    for name in ('http.iyi', 'hpack.iyi'):
        text = Path(source, 'std', name).read_text()
        # Only the fixture copies expose internals. The transport is never
        # called; drain simulates a peer consuming output and opening its
        # connection window again. Both variants use exactly these hooks.
        text = text.replace('class H2Connection\n', '''
pub class H2Connection
  def bench_settled : Nil
    @settled = true
  end

  def bench_drain : Int32
    size = @pending_size
    @send_window = WINDOW
    @pending.clear
    @pending_size = 0
    size
  end
''')
        text = text.replace('class Conn\n', '''
pub class Conn
  def bench_seed(text : String, id : Int32) : Nil
    raise "fixture too large" if text.bytesize > @capacity
    @data.copy_from(text.to_unsafe, text.bytesize)
    @start = 0
    @stop = text.bytesize
    @data[5] = ((id >> 24) & 0x7f).to_u8
    @data[6] = ((id >> 16) & 0xff).to_u8
    @data[7] = ((id >> 8) & 0xff).to_u8
    @data[8] = (id & 0xff).to_u8
  end
''')
        Path(dest, name).write_text(text)
PY
for kind in codec response frames request; do
  case $kind in
    codec) source=http2_tape.iyi ;;
    *) source=http2_tape_$kind.iyi ;;
  esac
  for variant in base tape; do
    flags=()
    if [ "$variant" = tape ] &&
       { [ "$kind" = codec ] || [ "$kind" = response ]; }; then
      flags=(-D h2_tape)
    fi
    IYI_PATH="$WORK/$variant:$REPO/src" \
      IYI_CACHE_DIR="$WORK/cache-$variant" \
      "$IYI" build --release "${flags[@]}" \
      -o "$WORK/$kind-$variant" "$REPO/bench/$source"
  done
  for run in 1 2 3 4 5 6 7; do
    for variant in base tape; do
      "$WORK/$kind-$variant" |
        sed "s/^/$variant /" | tee -a "$WORK/results"
    done
  done
done
python3 - "$WORK/results" <<'PY'
import sys
rows = {}
for line in open(sys.argv[1]):
    variant, part, *values = line.split()
    row = dict(item.split('=') for item in values)
    rows.setdefault((part, variant), []).append(row)
print('\nFastest of seven; allocation is min..max (collection off):')
for (part, variant), runs in rows.items():
    times = [int(row['ns']) for row in runs]
    sizes = [int(row['bytes']) for row in runs]
    sums = {row['sum'] for row in runs}
    assert len(sums) == 1, (part, variant, sums)
    peer = rows.get((part, 'base'))
    if peer:
        assert sums == {row['sum'] for row in peer}, part
    print(f'{part:8} {variant:4} {min(times) / 1e6:9.3f} ms '
          f'{min(sizes)}..{max(sizes)} bytes')
PY
