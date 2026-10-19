#!/usr/bin/env python3
"""Draw the recorded respond comparison for the README.

Run: python3 bench/tape_memory_svg.py
Results: TAPE_DESIGN.md, respond, median of nine runs.
Playback is 5x slower. Cells are schematic, not measured addresses.
"""
from pathlib import Path
import random

WIDTH = 742
HEIGHT = 540
START = 0.45
SLOWDOWN = 5
LOOP = (START + 1.55 + 1.4) * SLOWDOWN
COLUMNS = 34


def percent(seconds):
    return f"{100 * seconds * SLOWDOWN / LOOP:.6f}%"


def draw():
    svg = [
        '<svg xmlns="http://www.w3.org/2000/svg"',
        f'  viewBox="0 0 {WIDTH} {HEIGHT}" width="{WIDTH}"',
        f'  height="{HEIGHT}" role="img" aria-labelledby="title desc">',
        '  <title id="title">Tape and heap: the same respond workload</title>',
        '  <desc id="desc">Recorded: tape 0.67 seconds and 1.7 MB;',
        '    heap 1.55 seconds and 7.6 MB. Playback is 5 times slower.',
        '    Each block represents 0.05 MB: 34 tape blocks, 152 heap blocks.',
        '    Median of nine runs, 1.6 million DTOs.</desc>',
        '  <style>',
        '    :root { --fg:#e4edf5; --dim:#9aafc1; --bg:#080e17;',
        '      --track:#182637; --tape:#39e6cf; --heap:#ffb454; }',
        '    text { font:13px ui-monospace, SFMono-Regular, Menlo,',
        '      Consolas, monospace; fill:var(--fg); }',
        '    .dim { fill:var(--dim); }',
        '    .time { font-weight:600; }',
        '    .brand { font-size:24px; font-weight:800;',
        '      letter-spacing:3px; }',
        '    .tag { font-size:11px; letter-spacing:1.5px; }',
        '    .memory { font-size:20px; font-weight:700; }',
        '    .cells rect { stroke:#080e17; stroke-width:1; }',
    ]
    rows = [('tape', 0.67, 1.7, 100), ('heap', 1.55, 7.6, 205)]
    for name, duration, memory, _ in rows:
        count = round(memory * 20)
        for index in range(count):
            at = percent(START + duration * (index + 1) / count)
            svg.extend([
                f'    @keyframes {name}{index} {{',
                '      0% { opacity:0; }',
                f'      {at}, 100% {{ opacity:1; }}',
                '    }',
                f'    .{name}{index} {{ animation:{name}{index}',
                f'      {LOOP}s steps(1, end) infinite; }}',
            ])
        at = percent(START + duration)
        svg.extend([
            f'    @keyframes done-{name} {{',
            '      0% { opacity:0; }',
            f'      {at}, 100% {{ opacity:1; }}',
            '    }',
            f'    .done-{name} {{ animation:done-{name}',
            f'      {LOOP}s steps(1, end) infinite; }}',
        ])
    svg.extend([
        '    @media (prefers-reduced-motion:reduce) {',
        '      .cells rect, .time { animation:none; opacity:1; }',
        '    }',
        '  </style>',
        '  <defs>',
        '    <pattern id="grid" width="20" height="20"',
        '      patternUnits="userSpaceOnUse">',
        '      <path d="M20 0H0V20" fill="none"',
        '        stroke="#142132" stroke-width="0.5"/>',
        '    </pattern>',
        '  </defs>',
        f'  <rect width="{WIDTH}" height="{HEIGHT}" fill="var(--bg)"/>',
        f'  <rect width="{WIDTH}" height="{HEIGHT}" fill="url(#grid)"/>',
        '  <path d="M0 0H742" stroke="var(--tape)" stroke-width="4"/>',
        '  <text x="26" y="38" class="brand">ris</text>',
        '  <text x="112" y="36" class="tag" fill="#39e6cf">',
        '    // MEMORY LAB</text>',
        '  <text x="26" y="64" class="dim">',
        '    $ bench respond --dtos 1.6M --runs 9</text>',
        '  <text x="716" y="36" text-anchor="end" class="tag">',
        '    TAPE / GC</text>',
        '  <path d="M26 78H716" stroke="#26384b"/>',
    ])
    for name, duration, memory, top in rows:
        label = ('// sequential writes' if name == 'tape'
                 else '// GC-managed objects')
        svg.extend([
            f'  <text x="26" y="{top}" class="tag"'
            f'    style="fill:var(--{name})">{name.upper()}</text>',
            f'  <text x="102" y="{top}" class="dim">{label}</text>',
            f'  <text x="590" y="{top}" class="time done-{name}"',
            f'    style="fill:var(--{name})">{duration:.2f} s / done</text>',
        ])
        count = round(memory * 20)
        svg.append(
            f'  <text x="26" y="{top + 65 if name == "tape" else 350}"'
            f'    class="memory" style="fill:var(--{name})">'
            f'{memory:.1f} MB</text>'
        )
        order = list(range(count))
        if name == 'heap':
            random.Random(42).shuffle(order)
        for cell in range(count):
            x = 26 + (cell % COLUMNS) * 20
            y = top + 14 + (cell // COLUMNS) * 23
            svg.append(
                f'  <rect x="{x}" y="{y}" width="16" height="18"'
                ' rx="0" fill="var(--track)"/>'
            )
        svg.append(f'  <g class="cells" fill="var(--{name})">')
        for index, cell in enumerate(order):
            x = 26 + (cell % COLUMNS) * 20
            y = top + 14 + (cell // COLUMNS) * 23
            svg.extend([
                f'    <rect x="{x}" y="{y}" width="16" height="18"',
                f'      rx="0" class="{name}{index}"/>',
            ])
        svg.append('  </g>')
        if name == 'heap':
            svg.extend([
                '  <text x="26" y="375" class="dim">* Illustration only:',
                '    the heap does not actually fill in this random order.',
                '  </text>',
            ])
    svg.append(
        '  <text x="26" y="410" class="dim">// MEMORY FOOTPRINT [MB]</text>'
    )
    for name, _, memory, top in rows:
        y = 422 if name == 'tape' else 452
        width = 460 * memory / 7.6
        svg.extend([
            f'  <text x="26" y="{y + 15}">{name}</text>',
            f'  <rect x="90" y="{y}" width="460" height="20"',
            '    rx="0" fill="var(--track)"/>',
            f'  <rect x="90" y="{y}" width="{width:.2f}" height="20"',
            f'    rx="0" fill="var(--{name})"/>',
            f'  <text x="566" y="{y + 15}">{memory:.1f} MB</text>',
        ])
    svg.extend([
        '  <text x="26" y="499" class="dim">Playback 5x slower;',
        '    labels show measured time. Median of 9 runs.</text>',
        '  <text x="26" y="521" class="dim">Allocation layout is schematic;',
        '    1 block = 0.05 MB; 34 tape / 152 heap blocks.</text>',
        '</svg>',
    ])
    root = Path(__file__).resolve().parents[1]
    path = root / 'doc/assets/tape-heap.anim.svg'
    path.write_text("\n".join(svg) + "\n")


if __name__ == '__main__':
    draw()
