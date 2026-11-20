#!/usr/bin/env python3
"""Time the CLI workloads without duplicating their functional programs.

The CLI's speed markers are comments. This runner expands them into clock
reads in a temporary source file and prints the resulting observations.
No clock value determines success; compile and functional failures do.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
RIS = os.environ.get("RIS", str(ROOT / "bin/ris"))
PROBES = {
    'bzip2.workload': '  puts "\\n== timings"\n  # The sort\'s guard: one byte a megabyte, which the first run-length\n  # code shrinks to 20 KB of five-byte runs; two bytes a megabyte, which\n  # it leaves alone and whose rotations agree for the whole block; noise;\n  # and text.\n  {\n    {"1 MiB of one byte", run_of(0x61, 1048576)},\n    {"1 MiB of \\"ab\\"", "ab" * 524288},\n    {"1 MiB of random bytes", random_bytes(1048576, 99_u64)},\n    {"1 MiB of text", text(15000)[0, 1048576]},\n  }.each do |c|\n    # speed: bzip2.0\n    s = Bzip2.compress(c[1])\n    # speed: bzip2.2\n    back = whole(s, c[0])\n    # speed: bzip2.4\n    assert_true back == c[1], "#{c[0]} reads back"\n    # speed: bzip2.6\n    # speed: bzip2.7\n    # speed: bzip2.8\n\n  end',
    'bit_array.0': 'wide_started = __iyi_monotonic_ns\n',
    'bit_array.1': 'wide_ms = (__iyi_monotonic_ns - wide_started) // 1000000\n',
    'bit_array.2': 'puts "200,000 bits print in under a second, not #{wide_ms} ms"\n',
    'tuple.3': 'started = __iyi_monotonic_ns\n',
    'tuple.4': 'named_ns = __iyi_monotonic_ns - started\nstarted = __iyi_monotonic_ns\n',
    'tuple.6': 'plain_ns = __iyi_monotonic_ns - started\n',
    'tuple.7': 'puts "hash table: 22500 keys took #{named_ns // 1000000} ms where tuples took #{plain_ns // 1000000} ms"\n',
    'uri.8': 'started = __iyi_monotonic_ns\n',
    'uri.9': 'keyed_ns = __iyi_monotonic_ns - started\nstarted = __iyi_monotonic_ns\n',
    'uri.11': 'texted_ns = __iyi_monotonic_ns - started\n',
    'uri.12': 'puts "hash table: 16000 URI keys took #{keyed_ns // 1000000} ms where String keys took #{texted_ns // 1000000} ms"\n',
    'uri.13': 'started = __iyi_monotonic_ns\n',
    'uri.14': 'split_ns = __iyi_monotonic_ns - started\nstarted = __iyi_monotonic_ns\n',
    'uri.16': 'removed_ns = __iyi_monotonic_ns - started\n',
    'uri.17': 'puts "dot segments: 132 KB took #{removed_ns // 1000000} ms where splitting it took #{split_ns // 1000000} ms"\n',
    'json.18': 'keyed_started = __iyi_monotonic_ns\n',
    'json.19': 'keyed_ms = (__iyi_monotonic_ns - keyed_started) // 1000000\n',
    'json.20': 'puts "160,000 objects took #{keyed_ms} ms to go into a Hash, not under 2,000"\n',
    'dir.21': 'started = Time.monotonic\n',
    'dir.22': 'puts "glob: #{(Time.monotonic - started).total_milliseconds} ms"',
    'big.23': 'zeros_started = __iyi_monotonic_ns\n',
    'big.24': 'zeros_ms = (__iyi_monotonic_ns - zeros_started) // 1000000\n',
    'big.25': 'puts "decimal: 1e50000 and 1e-50000 took #{zeros_ms} ms to print"\n',
    'big.26': 'far_started = __iyi_monotonic_ns\n',
    'big.27': 'far_ms = (__iyi_monotonic_ns - far_started) // 1000000\n',
    'big.28': 'puts "decimal: far exponents took #{far_ms} ms to compare and hash"\n',
    'big.30': 'print_ms = 9223372036854775807_i64\nparse_ms = 9223372036854775807_i64\n',
    'big.32': '  huge_started = __iyi_monotonic_ns\n',
    'big.33': '  huge_printed = __iyi_monotonic_ns\n',
    'big.34': '  huge_parsed = __iyi_monotonic_ns\n  took = (huge_printed - huge_started) // 1000000\n  print_ms = took if took < print_ms\n  took = (huge_parsed - huge_printed) // 1000000\n  parse_ms = took if took < parse_ms\n',
    'big.39': 'puts "base: printing a long value costs what parsing it does (#{print_ms} ms against #{parse_ms})"\n',
    'big.40': 'divide_ns = 9223372036854775807_i64\nproduct_ns = 9223372036854775807_i64\n',
    'big.42': '  started = __iyi_monotonic_ns\n',
    'big.43': '  divided = __iyi_monotonic_ns\n',
    'big.44': '  multiplied = __iyi_monotonic_ns\n  divide_ns = divided - started if divided - started < divide_ns\n  product_ns = multiplied - divided if multiplied - divided < product_ns\n',
    'big.47': 'puts "div: a long division took #{divide_ns // 1000000} ms, the product #{product_ns // 1000000} ms"\n',
    'big.48': 'strip_ns = 9223372036854775807_i64\nprint_ns = 9223372036854775807_i64\n',
    'big.50': '  strip_started = __iyi_monotonic_ns\n',
    'big.51': '  stripped = __iyi_monotonic_ns\n',
    'big.52': '  printed = __iyi_monotonic_ns\n  strip_ns = stripped - strip_started if stripped - strip_started < strip_ns\n  print_ns = printed - stripped if printed - stripped < print_ns\n',
    'big.55': 'puts "decimal: 40,000 trailing zeros took #{strip_ns // 1000000} ms to strip, printing 10**40000 #{print_ns // 1000000} ms"\n',
    'big.pow0': '  started = __iyi_monotonic_ns\n',
    'big.pow2': '  montgomery = __iyi_monotonic_ns\n',
    'big.pow4': '  fixed = __iyi_monotonic_ns\n',
    'big.pow6': '  finished = __iyi_monotonic_ns\n',
    'big.pow8': '  new_us = (montgomery - started) // 1000\n  secret_us = (fixed - montgomery) // 1000\n  old_us = (finished - fixed) // 1000\n  puts "powtime: #{bits} #{b.to_s(16)} #{e.to_s(16)} #{m.to_s(16)} = #{fast.to_s(16)} #{new_us} #{secret_us} #{old_us}"\n  # Measured at 12 times faster in a plain build at every size, and 9 to\n  # 11 in a --release one. One timing of each is one sample of a shared\n  # runner, and a held-up fast case fails the bound by itself: a darwin\n  # runner\'s broken copy of this file panicked before its own check\n  # (integration/0.20, job 119211068359), plausibly here - the log kept\n  # only the backtrace\'s last line. So the fast case is timed again, up to\n  # twice, and the best of its times held to the bound.\n  2.times do\n    break if new_us * 3 < old_us\n    again = __iyi_monotonic_ns\n    b.pow_mod(e, m)\n    took = (__iyi_monotonic_ns - again) // 1000\n    new_us = took if took < new_us\n  end\n  puts "pow_mod: a #{bits}-bit exponentiation took #{new_us} us, square-and-multiply #{old_us} us"',
    'bzip2.0': '    t0 = __iyi_monotonic_ns\n',
    'bzip2.2': '    t1 = __iyi_monotonic_ns\n',
    'bzip2.4': '    t2 = __iyi_monotonic_ns\n',
    'bzip2.6': '    compress_ms = (t1 - t0) // 1000000\n',
    'bzip2.7': '    puts "#{c[0]}: compress #{compress_ms} ms"\n',
    'bzip2.8': '    puts "  #{c[0]}: #{s.bytesize} bytes, compressed in #{compress_ms} ms, decompressed in #{(t2 - t1) // 1000000} ms"',
}


def main():
    import sys
    names = sys.argv[1:] or [
        "bit_array", "tuple", "uri", "json", "dir", "big", "bzip2",
        "text_scale",
    ]
    failures = []
    with tempfile.TemporaryDirectory(prefix="ris-cli-timings-") as work:
        for name in names:
            source = (ROOT / "test/cli" /
                      f"std_{name}_exercise.ri").read_text()
            if name == "bzip2":
                source += "\n# speed: bzip2.workload\n"
            for key, code in PROBES.items():
                if key.startswith(name + "."):
                    token = "# speed: " + key + "\n"
                    if source.count(token) != 1:
                        raise SystemExit(f"missing speed marker: {key}")
                    source = source.replace("# speed: " + key + "\n",
                                            code.strip() + "\n")
            program = Path(work) / "probe.ri"
            program.write_text(source)
            binary = Path(work) / "probe"
            subprocess.run([RIS, "build", "--release", "-o", str(binary),
                            str(program)], check=True)
            env = dict(os.environ, TEST_SANDBOX=str(Path(work) / "sandbox"))
            started = time.perf_counter()
            result = subprocess.run([str(binary)], env=env, text=True,
                                    stdout=subprocess.PIPE)
            elapsed = (time.perf_counter() - started) * 1000
            print(f"== {name}: whole workload {elapsed:.2f} ms", flush=True)
            for line in result.stdout.splitlines():
                if any(word in line for word in
                       (" ms", "print:", "division:", "decimal zeros:")):
                    print(line, flush=True)
                if line.startswith("powtime: "):
                    lhs, rhs = line.removeprefix("powtime: ").split(" = ")
                    bits, *words = lhs.split()
                    b, e, m = (int(w, 16) for w in words)
                    started = time.perf_counter()
                    pow(b, e, m)
                    python_ms = (time.perf_counter() - started) * 1000
                    _, fast, secret, old = rhs.split()
                    print(f"{bits} bits: pow_mod {int(fast) / 1000:.2f} ms, "
                          f"secret {int(secret) / 1000:.2f} ms, "
                          f"square-and-multiply {int(old) / 1000:.2f} ms, "
                          f"Python {python_ms:.2f} ms", flush=True)
            if result.returncode:
                failures.append(name)
    if failures:
        raise SystemExit("functional failures: " + ", ".join(failures))


if __name__ == "__main__":
    main()
